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
; (keyboard scanner) and phase 3 (the editor: typing, cursor, colors).
; Until the menus arrive (phase 8), RUN/STOP asks QUIT Y/N.
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
NMI_VECTOR      = $0318         ; ... and here from its NMI entry (RESTORE)
KERNAL_IRQ      = $ea31         ; the KERNAL's normal IRQ handler
KERNAL_CLRSCR   = $e544         ; clear the screen, home the cursor
LAST_DEVICE     = $ba           ; last device number the KERNAL used

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
        tsx                     ; remember the stack, so quit can get back
        stx entry_sp            ; to BASIC from anywhere

        sei                     ; no interrupts while we set things up
        cld

        jsr detect_system       ; PAL / NTSC / old NTSC / Drean
!if DEBUG {
        jsr mailbox_init
}

        ; Bank out BASIC ROM ($a000-$bfff becomes RAM for the text buffer).
        ; KERNAL ROM and I/O stay in.
        lda #$36
        sta $01

        jsr init_screen
        jsr init_sprites
        jsr init_marker
        jsr init_keyboard
        jsr init_irq
        cli
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
; Can be jumped to from anywhere: it resets the stack first.
;----------------------------------------------------------------------------
quit
        ldx entry_sp            ; the stack as it was at start-up: the top
        txs                     ; is the SYS command's return address
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
        lda #$37                ; BASIC ROM back in
        sta $01
        cli
        jsr KERNAL_CLRSCR
        rts                     ; back to BASIC, which prints READY.

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
; Variables
;----------------------------------------------------------------------------
load_device     !byte 0         ; $BA at start-up
entry_sp        !byte 0         ; stack pointer at start-up (for quit)
text_bg         !byte BLACK     ; text background color (setting)
text_color      !byte LIGHT_GREY ; default text color (setting)


;----------------------------------------------------------------------------
; The other source files
;----------------------------------------------------------------------------
!source "src/system.asm"
!source "src/irq.asm"
!source "src/input.asm"
!source "src/editor.asm"
!source "src/menu.asm"
!source "src/fileio.asm"
!source "src/data.asm"

;----------------------------------------------------------------------------
; Tables that need no starting values live after the program, in memory
; that the PRG file does not have to carry. They are set up at start-up.
;----------------------------------------------------------------------------
program_end
ctype           = program_end           ; 256: what each byte of text is
row_off_lo      = ctype + 256           ; per screen row (MROWS each):
row_off_hi      = row_off_lo + MROWS    ;   where it starts in the text,
row_color       = row_off_hi + MROWS    ;   the color there,
row_rvs         = row_color + MROWS     ;   reverse there ($80 = on),
row_len         = row_rvs + MROWS       ;   how many cursor places it has
dummy_row       = row_len + MROWS       ; 40: row 25 is "drawn" here
prompt_save     = dummy_row + 40        ; 240: what is under a prompt box
tables_end      = prompt_save + 240

; All of it must end before the sprite blocks at $3e80.
!if tables_end > SPRITE_BASE {
        !error "Program and tables have grown into the sprite blocks at $3e80"
}
