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
;   $0801-       the program's lower part: start-up, IRQs, keyboard, boxes,
;                disk; then a stored copy of the editor (see below)
;   after that   run-time tables, over the stored copy once it is copied
;   $3e80-$3fff  sprite blocks ($3fff must be 0: the open borders show it)
;   $4000-$cfff  the text buffer (36 KB, with the clipboard at its top)
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

; All of $02 up to ZP_END is BASIC's too. Start-up keeps a copy of it and
; quit puts it back (BASIC keeps some values there between commands).
; Move ZP_END up when adding zero page variables.
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
        ; Step 1: read $BA before anything else touches it. It holds the
        ; device the program was loaded from (used for MAGIC T DEFAULTS).
        lda LAST_DEVICE
        sta load_device
        ldx #ZP_END-ZP_START-1  ; a copy of BASIC's zero page, for quit
-       lda ZP_START,x
        sta basic_zp,x
        dex
        bpl -

        sei                   ; no interrupts while we set things up
        cld

        jsr copy_high           ; the editor to its place under the KERNAL
        jsr detect_system       ; PAL / NTSC / old NTSC / Drean
!if DEBUG {
        jsr mailbox_init
}

        ; Switch out the BASIC and KERNAL ROMs: $a000-$bfff becomes RAM for
        ; the text buffer, and the editor at $e000 comes into view. With
        ; the KERNAL ROM out, the CPU takes its NMI and IRQ vectors from the
        ; RAM at $fffa-$ffff, so ours go there first.
        lda #<nmi_handler       ; RESTORE (input.asm)
        sta RAM_NMI_VECTOR
        lda #>nmi_handler
        sta RAM_NMI_VECTOR+1
        lda #<irq_entry         ; a copy of the KERNAL's IRQ entry (irq.asm)
        sta RAM_IRQ_VECTOR
        lda #>irq_entry
        sta RAM_IRQ_VECTOR+1
        lda #ROMS_EDIT
        sta CPU_PORT

        jsr init_screen
        jsr init_sprites
        jsr init_marker
        jsr init_keyboard
        jsr init_mouse
        jsr init_irq
        cli
        jsr load_defaults       ; the settings saved with Save defaults
        jsr editor_init         ; an empty document, ready to type

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
        jsr mailbox_log_key     ; tell the test harness
        ldx frame_count         ; and how many frames the key takes
        stx key_start_frame
}
        jsr editor_key
!if DEBUG {
        lda frame_count
        sec
        sbc key_start_frame
        sta MB_KEY_TIME
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
; quit - undo everything we changed and return to BASIC's READY prompt.
; Can be jumped to from anywhere: BASIC's warm start resets the stack.
;
; It ends with a NEW, as the program in BASIC memory is no longer whole:
; the run-time tables lie over the stored copy of the editor, so RUN would
; crash. Load it again to restart.
;----------------------------------------------------------------------------
BASIC_NEW       = $a644         ; BASIC's NEW, after its syntax check
BASIC_WARM      = $a002         ; vector to BASIC's warm start (the one that
                                ; RUN/STOP + RESTORE uses)
quit
-       lda key_now+7           ; wait until RUN/STOP is let go, so BASIC
        bmi -                   ; doesn't see it and print BREAK

        sei
        jsr restore_irq
        jsr restore_keyboard
        lda #0
        sta VIC_SPR_ENABLE
        lda #CTRL1_25ROWS
        sta VIC_CTRL1
        lda #CSEL_40
        sta VIC_CTRL2
        lda #MEMPTR_UPPER
        sta VIC_MEMPTR
        lda #LIGHT_BLUE         ; BASIC's power-on colors
        sta VIC_BORDER
        lda #BLUE
        sta VIC_BG0
        lda #ROMS_ALL           ; BASIC and KERNAL ROMs back in
        sta CPU_PORT

        ; BASIC's zero page back as it was. BASIC keeps a few values there
        ; between commands (e.g. $13, the current I/O channel, and $18,
        ; used with its string stack); without them it forgets the RETURN
        ; after a command, or gives ?FORMULA TOO COMPLEX for "A"+"B".
        ldx #ZP_END-ZP_START-1
-       lda basic_zp,x
        sta ZP_START,x
        dex
        bpl -
        cli
        jsr KERNAL_CLRSCR
        jsr BASIC_NEW           ; forget the program (see above)
        jmp (BASIC_WARM)        ; READY.

;----------------------------------------------------------------------------
; init_screen - VIC settings and colors. (The editor draws the text.)
;----------------------------------------------------------------------------
!zone init_screen
init_screen
        lda #CTRL1_25ROWS
        sta VIC_CTRL1
        lda #CSEL_40            ; 40 columns, no X scroll, no multicolor
        sta VIC_CTRL2
        lda #MEMPTR_LOWER       ; default: upper/lower case set
        sta VIC_MEMPTR
        lda #BLUE               ; top strip color until the first split
        sta VIC_BORDER
        lda #STRIP_BG
        sta VIC_BG0
        rts

;----------------------------------------------------------------------------
; copy_high - copy the editor from where the PRG file put it (right after
; the lower part of the program) to $e000, the RAM under the KERNAL ROM.
; A write always reaches the RAM, even while the ROM is switched in (only
; reads see the ROM), so this works before the ROMs are switched out.
; It copies whole pages; the few bytes past the end do no harm (the
; vectors at $fffa are set afterwards).
;----------------------------------------------------------------------------
!zone copy_high
copy_high
        lda #<high_load         ; from
        sta zp_ptr
        lda #>high_load
        sta zp_ptr+1
        lda #<HIGH_CODE         ; to
        sta zp_ptr2
        lda #>HIGH_CODE
        sta zp_ptr2+1
        ldx #>(HIGH_SIZE + 255) ; number of pages
        ldy #0
-       lda (zp_ptr),y
        sta (zp_ptr2),y
        iny
        bne -
        inc zp_ptr+1            ; next page
        inc zp_ptr2+1
        dex
        bne -
        rts

;----------------------------------------------------------------------------
; Variables
;----------------------------------------------------------------------------
load_device     !byte 0         ; $BA at start-up
basic_zp        !fill ZP_END-ZP_START, 0 ; BASIC's zero page at start-up
text_bg         !byte BLACK     ; text background color (setting)
text_color      !byte LIGHT_GREY ; default text color (setting)


;----------------------------------------------------------------------------
; The other source files: first the lower part of the program ...
;----------------------------------------------------------------------------
!source "src/system.asm"
!source "src/irq.asm"
!source "src/input.asm"
!source "src/menu.asm"
!source "src/fileio.asm"
!source "src/find.asm"
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
high_end                                ; (an address under the KERNAL ROM)
}
program_end                             ; the end of the PRG file
HIGH_SIZE       = program_end - high_load

!if high_end > RAM_NMI_VECTOR {
        !error "The code under the KERNAL ROM has grown into the vectors at $fffa"
}

;----------------------------------------------------------------------------
; Tables that need no starting values. They lie over the stored copy of
; the editor, which is free once copy_high has run, so the PRG file does
; not carry them. They are set up at start-up.
;----------------------------------------------------------------------------
tables          = high_load
ctype           = tables                ; 256: what each byte of text is
scrcode         = ctype + 256           ; 256: the screen code of each byte
row_off_lo      = scrcode + 256         ; per screen row (MROWS each):
row_off_hi      = row_off_lo + MROWS    ;   where it starts in the text,
row_color       = row_off_hi + MROWS    ;   the color there,
row_rvs         = row_color + MROWS     ;   reverse there ($80 = on),
row_len         = row_rvs + MROWS       ;   how many cursor places it has
dummy_row       = row_len + MROWS       ; 40: row 25 is "drawn" here
prompt_save     = dummy_row + 40        ; 240: what is under a prompt box
!if DEBUG {
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
