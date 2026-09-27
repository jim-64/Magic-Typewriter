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
; Phase 1 (current): system detect, raster IRQ chain (open top/bottom
; borders, color splits, page marker), the six border sprites, and the
; debug test mailbox. RUN/STOP quits back to BASIC for now.
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
        jsr init_irq
        cli

;============================================================================
; Main loop
;============================================================================
main_loop
!if DEBUG {
        jsr mailbox_poll        ; let the test harness move the page marker
}
        jsr check_quit          ; temporary for phase 1: RUN/STOP quits
        jmp main_loop

;----------------------------------------------------------------------------
; check_quit - temporary until the keyboard scanner (phase 2) exists.
; Looks at the RUN/STOP key directly and returns to BASIC if it is down.
;----------------------------------------------------------------------------
!zone check_quit
check_quit
!ifdef QUIT_TEST {
        lda frame_count+1       ; test builds (-DQUIT_TEST=1): quit by
        bne quit                ; themselves after 256 frames
}
        lda #$7f                ; select keyboard column 7
        sta CIA1_PRA
        lda CIA1_PRB
        bpl quit                ; bit 7 low = RUN/STOP pressed
        rts

;----------------------------------------------------------------------------
; quit - undo everything we changed and return to BASIC's READY prompt.
;----------------------------------------------------------------------------
quit
        pla                     ; drop check_quit's return address;
        pla                     ; the SYS return address is under it
-       lda CIA1_PRB            ; wait until RUN/STOP is let go, so BASIC
        bpl -                   ; doesn't see it and print BREAK

        sei
        jsr restore_irq
        lda #0
        sta VIC_SPR_ENABLE
        lda #CTRL1_25ROWS
        sta VIC_CTRL1
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
; init_screen - colors, character set, clear the text area, test text.
;----------------------------------------------------------------------------
!zone init_screen
init_screen
        lda #CTRL1_25ROWS
        sta VIC_CTRL1
        lda #$08                ; 40 columns, no X scroll, no multicolor
        sta VIC_CTRL2
        lda #MEMPTR_LOWER       ; default: upper/lower case set
        sta VIC_MEMPTR
        lda #BLUE               ; top strip color until the first split
        sta VIC_BORDER
        lda #STRIP_BG
        sta VIC_BG0

        ; Clear 1000 screen cells to spaces in the text color.
        ldx #0
-       lda #$20
        sta SCREEN,x
        sta SCREEN+$100,x
        sta SCREEN+$200,x
        sta SCREEN+$2e8,x       ; last block ends at $07e7, before the
        lda text_color          ; sprite pointers at $07f8
        sta COLOR_RAM,x
        sta COLOR_RAM+$100,x
        sta COLOR_RAM+$200,x
        sta COLOR_RAM+$2e8,x
        inx
        bne -

        ; Phase 1 test text (screen codes, see data.asm)
        ldx #0
-       lda test_text,x
        beq +
        sta SCREEN+2*40+2,x
        inx
        bne -
+
        ; Show which video system was detected on row 4.
        ldx system_type
        lda system_name_offset,x
        tax
        ldy #0
-       lda system_names,x
        beq +
        sta SCREEN+4*40+2,y
        inx
        iny
        bne -
+       rts

;----------------------------------------------------------------------------
; Variables
;----------------------------------------------------------------------------
load_device     !byte 0         ; $BA at start-up
text_bg         !byte BLACK     ; text background color (setting)
text_color      !byte LIGHT_GREY ; default text color (setting)

;----------------------------------------------------------------------------
; The other source files
;----------------------------------------------------------------------------
!source "src/system.asm"
!source "src/irq.asm"
!source "src/input.asm"
!source "src/data.asm"

; The program must end before the sprite blocks at $3e80.
!if * > SPRITE_BASE {
        !error "Program has grown into the sprite blocks at $3e80"
}
