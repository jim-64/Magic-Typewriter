;============================================================================
; MAGIC TYPEWRITER
; A small, modern-feeling text editor for the Commodore 64.
; Assembler: ACME 0.97
;
; This is the master file. It holds the BASIC start line, the start-up code
; and the main loop, and pulls in the other source files with !source.
;
; Build: run build.bat (Windows) or build.sh (Linux), or use VS64's build.
;
; Done so far: phase 1 (system detect, raster IRQ chain, open borders,
; color splits, page marker, border sprites, debug test mailbox), phase 2
; (keyboard scanner), phase 3 (the editor: typing, cursor, colors), phase 4
; (loading and saving) and phase 5 (marking, cut/copy/paste).
; Until the menus arrive (phase 8), RUN/STOP asks QUIT Y/N.
;
; MEMORY MAP
;   $0400-$07ff  screen
;   $0801-       the program's lower part: IRQs, keyboard, boxes, menus,
;                disk; then a stored copy of the editor (see below), of
;                reudoc.asm, and the start-up code (startup.asm)
;   after that   run-time tables, over the stored copy once it is copied
;   $3e80-$3fff  sprite blocks ($3fff must be 0: the open borders show it)
;   $4000-$cfff  the text buffer (36 KB, with the clipboard at its top); the
;                start-up code runs from here once, before the document
;                takes the room. With an REU of 192 KB or more: $4000-$bfff,
;                and reudoc.asm at $c000 (long documents)
;   $d000-$dfff  I/O
;   $e000-$fff9  the editor, in the RAM under the KERNAL ROM
;   $fffa-$ffff  NMI and IRQ vectors for while the KERNAL ROM is out
;
; While editing, the BASIC and KERNAL ROMs are switched out ($01 = $35):
; the program has its own keyboard scanner and screen code, so it only
; needs the KERNAL for disk work (later also the printer and tape).
; io_begin (fileio.asm) switches the KERNAL ROM in for that, and io_end
; switches it out again. In between, the RAM at $e000 is hidden behind the
; ROM, so the editor's code and variables there must not be used: the
; disk code, and everything it calls, lives in the lower part.
;============================================================================

; DEBUG=1 builds include the test mailbox (see input.asm).
; build.bat / build.sh pass -DDEBUG=1 or -DDEBUG=0 on the command line.
!ifndef DEBUG {
DEBUG = 1
}

;----------------------------------------------------------------------------
; Hardware registers
;----------------------------------------------------------------------------
VIC_SPR0_X      = $d000         ; sprite 0 X; sprite n X is at $d000+2n
VIC_SPR0_Y      = $d001         ; sprite 0 Y; sprite n Y is at $d001+2n
VIC_SPR_XMSB    = $d010         ; bit 8 of each sprite's X position
VIC_CTRL1       = $d011         ; bit 7 = raster bit 8, bit 3 = 25 rows
VIC_RASTER      = $d012         ; raster line (read) / IRQ line (write)
VIC_SPR_ENABLE  = $d015
VIC_CTRL2       = $d016
VIC_SPR_EXPY    = $d017
VIC_MEMPTR      = $d018         ; screen and character set location
VIC_IRQ_FLAGS   = $d019
VIC_IRQ_MASK    = $d01a
VIC_SPR_PRIO    = $d01b
VIC_SPR_MCOLOR  = $d01c
VIC_SPR_EXPX    = $d01d
VIC_BORDER      = $d020
VIC_BG0         = $d021
VIC_SPR0_COLOR  = $d027         ; sprite n color is at $d027+n

CIA1_PRA        = $dc00         ; keyboard columns out / joystick port 2
CIA1_PRB        = $dc01         ; keyboard rows in / joystick port 1
CIA1_TBLO       = $dc06
CIA1_TBHI       = $dc07
CIA1_ICR        = $dc0d
CIA1_CRB        = $dc0f

SCREEN          = $0400
COLOR_RAM       = $d800
SPRITE_PTRS     = SCREEN + $3f8

IRQ_VECTOR      = $0314         ; KERNAL jumps here from its IRQ entry
BRK_VECTOR      = $0316         ; ... here for a BRK instruction
NMI_VECTOR      = $0318         ; ... and here from its NMI entry (RESTORE)
RAM_NMI_VECTOR  = $fffa         ; the CPU's own vectors, read from RAM
RAM_IRQ_VECTOR  = $fffe         ; while the KERNAL ROM is switched out
KERNAL_IRQ      = $ea31         ; the KERNAL's normal IRQ handler
KERNAL_CLRSCR   = $e544         ; clear the screen, home the cursor
LAST_DEVICE     = $ba           ; last device number the KERNAL used

; $01, the CPU's port: which ROMs the CPU sees
CPU_PORT        = $01
ROMS_EDIT       = $35           ; I/O only: RAM at $a000-$bfff and $e000-$ffff
ROMS_KERNAL     = $36           ; KERNAL ROM and I/O (for disk work)
ROMS_ALL        = $37           ; BASIC, KERNAL and I/O: as BASIC wants it

; VIC settings used by the editor
CTRL1_25ROWS    = $1b           ; screen on, 25 rows, YSCROLL = 3
CTRL1_24ROWS    = $13           ; screen on, 24 rows, YSCROLL = 3
MEMPTR_UPPER    = $15           ; screen $0400, upper case/graphics set
MEMPTR_LOWER    = $17           ; screen $0400, upper/lower case set

; C64 color numbers
BLACK = 0 : WHITE = 1 : RED = 2 : CYAN = 3 : PURPLE = 4 : GREEN = 5
BLUE = 6 : YELLOW = 7 : ORANGE = 8 : BROWN = 9 : LIGHT_RED = 10
DARK_GREY = 11 : GREY = 12 : LIGHT_GREEN = 13 : LIGHT_BLUE = 14
LIGHT_GREY = 15

;----------------------------------------------------------------------------
; Zero page ($02-$8f is free once BASIC is banked out)
;----------------------------------------------------------------------------
zp_ptr          = $02           ; general 16-bit pointer
zp_ptr2         = $04           ; second 16-bit pointer
zp_tmp          = $06           ; scratch byte

; Used by the editor (main program only, never the IRQs). They are listed
; here, before any code, so ACME knows they are zero page addresses when
; the lower part of the program uses them.
gap_start       = $08           ; first free byte of the gap = the cursor
gap_end         = $0a           ; first byte after the gap
ptr             = $0c           ; walks through the text
ptr2            = $0e           ; a second walking pointer
scr             = $10           ; screen RAM of the row being drawn
clr             = $12           ; color RAM of the row being drawn
cptr            = $14           ; screen RAM of the cursor
ccol            = $16           ; color RAM of the cursor
work            = $18           ; 16-bit scratch
text_end        = $1a           ; end of the text; the clipboard is above it

; All of $02 up to ZP_END is BASIC's too (Quit resets the C64, so BASIC
; gets it back fresh). Move ZP_END up when adding zero page variables.
ZP_START        = $02
ZP_END          = $1c           ; the first byte we do not use

;----------------------------------------------------------------------------
; BASIC start line:  2026 SYS2061
;----------------------------------------------------------------------------
        * = $0801
        !word basic_end         ; pointer to the next BASIC line
        !word 2026              ; line number
        !byte $9e               ; SYS token
        !text "2061"            ; decimal address of 'start' below
        !byte 0                 ; end of line
basic_end
        !word 0                 ; end of program

;============================================================================
; Start-up
;============================================================================
start                           ; must be at $080d = 2061
!if start != 2061 {
        !error "start must be at 2061 to match the SYS line"
}
        jmp startup             ; (start-up code: startup.asm)
start_done                      ; (it comes back here)
        jsr editor_init         ; an empty document, ready to type
!if DEBUG {
        jsr mailbox_ready       ; (now the test harness may start)
}

;============================================================================
; Main loop
;============================================================================
main_loop
!if DEBUG {
        jsr mailbox_poll        ; let the test harness move the page marker
}
!ifdef QUIT_TEST {
        lda frame_count+1       ; test builds (-DQUIT_TEST=1): quit by
        bne quit                ; themselves after 256 frames
}
        jsr cursor_blink
        jsr get_key             ; any key event?
        bcs main_loop
!if DEBUG {
        ldx #1                  ; busy with a key (first: the harness must
        stx MB_BUSY             ; never see it counted but not busy)
        jsr mailbox_log_key     ; tell the test harness
        ldx frame_count         ; and how many frames the key takes
        stx key_start_frame
}
        jsr editor_key
        lda reu_docs            ; a long document: the window follows the
        beq +                   ; cursor (reudoc.asm)
        jsr reu_keep
+
!if DEBUG {
        lda frame_count
        sec
        sbc key_start_frame
        sta MB_KEY_TIME
        lda #0
        sta MB_BUSY
}
        jmp main_loop

;----------------------------------------------------------------------------
; toggle_charset - switch between the upper/graphics and the upper/lower
; character set, like C= + SHIFT in BASIC.
;----------------------------------------------------------------------------
toggle_charset
        lda VIC_MEMPTR
        eor #%00000010          ; $15 <-> $17: bit 1 picks the ROM set
        sta VIC_MEMPTR
        rts

;----------------------------------------------------------------------------
; quit - back to BASIC by resetting the C64, as the reset button would
; (Jim, v0.2: it frees the room a step-by-step restore took). The reset
; puts everything back - VIC, CIAs, SID, vectors, BASIC - and ends at the
; power-up screen with READY. The document and the program are gone (Quit
; always ended with a NEW: load the program again to restart).
;----------------------------------------------------------------------------
RESET_VECTOR    = $fffc         ; the KERNAL ROM's reset vector
quit
        sei
        lda #ROMS_ALL           ; the ROMs in, so the CPU takes the ROM's
        sta CPU_PORT            ; reset vector, not the RAM under it
        jmp (RESET_VECTOR)

;----------------------------------------------------------------------------
; Variables
;----------------------------------------------------------------------------
load_device     !byte 0         ; $BA at start-up
text_bg         !byte BLACK     ; text background color (setting)
text_color      !byte LIGHT_GREY ; default text color (setting)


;----------------------------------------------------------------------------
; The other source files: first the lower part of the program ...
;----------------------------------------------------------------------------
!source "src/system.asm"
!source "src/reu.asm"
!source "src/irq.asm"
!source "src/input.asm"
!source "src/menu.asm"
!source "src/fileio.asm"
!source "src/undo.asm"
!source "src/data.asm"

;----------------------------------------------------------------------------
; ... then the editor. The PRG file carries it right here, but it is
; assembled to run at $e000, in the RAM under the KERNAL ROM (!pseudopc
; gives its labels those addresses). copy_high puts it there at start-up.
;----------------------------------------------------------------------------
HIGH_CODE       = $e000
high_load                               ; where the PRG file has it
!pseudopc HIGH_CODE {
!source "src/editor.asm"
!source "src/find.asm"
high_end                                ; (an address under the KERNAL ROM)
}

;----------------------------------------------------------------------------
; ... and the code for long documents held in an REU, assembled to run at
; $c000; reudoc_install puts it there only when there is such an REU.
;----------------------------------------------------------------------------
REUDOC          = $c000
reudoc_load                             ; where the PRG file has it
!pseudopc REUDOC {
!source "src/reudoc.asm"
reudoc_end
}
REUDOC_SIZE     = reudoc_end - REUDOC
!if reudoc_end > RD_PAGE {
        !error "reudoc.asm reaches into RD_PAGE"
}

;----------------------------------------------------------------------------
; Tables that need no starting values. They lie over the stored copy of
; the editor, which is free once copy_high has run, so the PRG file does
; not carry them. They are set up at start-up.
;----------------------------------------------------------------------------
tables          = high_load
ctype           = tables                ; 256: what each byte of text is
scrcode         = ctype + 256           ; 256: the screen code of each byte
border_code     = scrcode + 256         ; the border code for this video
                                        ; system (startup.asm puts it here).
                                        ; Right after the two 256-byte
                                        ; tables it starts where the lower
                                        ; part ends in its page, so its loops
                                        ; (kept within a page: same_page)
                                        ; seldom need padding (v0.2).
                                        ; The rest of the tables come after
                                        ; it: see below startup.asm, where
                                        ; its size (BORDER_SIZE) is known.

;----------------------------------------------------------------------------
; ... and last the start-up code, which runs once from where the PRG file
; puts it (in the text buffer: the document takes the room afterwards)
;----------------------------------------------------------------------------
!source "src/startup.asm"
!if startup < $4000 {
        !error "The start-up code must lie in the text buffer, past the sprite blocks"
}
program_end                             ; the end of the PRG file
HIGH_SIZE       = high_end - HIGH_CODE  ; (the editor alone: reudoc follows it)

!if high_end > RAM_NMI_VECTOR {
        !error "The code under the KERNAL ROM has grown into the vectors at $fffa"
}

; The rest of the tables, after the border code (defined here, below
; startup.asm, because the size checks below need BORDER_SIZE known)
row_off_lo      = border_code + BORDER_SIZE ; per screen row (MROWS each):
row_off_hi      = row_off_lo + MROWS    ;   where it starts in the text,
row_color       = row_off_hi + MROWS    ;   the color there,
row_rvs         = row_color + MROWS     ;   reverse there ($80 = on),
row_len         = row_rvs + MROWS       ;   how many cursor places it has
dummy_row       = row_len + MROWS       ; 40: row 25 is "drawn" here
prompt_save     = dummy_row + 40        ; 240: what is under a prompt box

!ifdef MOUSE_TRACE {
mouse_trace     = prompt_save + 240     ; 256: mouse trace (input.asm)
tables_end      = mouse_trace + 256
} else {
tables_end      = prompt_save + 240
}

; The lower part and the tables must end before the sprite blocks at $3e80.
; (The stored copy of the editor may reach past them: it is copied away
; before the sprite blocks and the text buffer are set up.)
!if tables_end > SPRITE_BASE {
        !error "The lower part and its tables have grown into the sprite blocks at $3e80"
}
