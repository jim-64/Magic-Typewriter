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
; color splits, page marker, border sprites, debug test mailbox) and
; phase 2 (keyboard scanner). The main loop shows a keyboard test screen
; until the editor arrives in phase 3. RUN/STOP quits back to BASIC.
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
        jsr show_held           ; phase 2 test: show the held modifier keys
        jsr get_key             ; any key event?
        bcs main_loop
!if DEBUG {
        jsr mailbox_log_key     ; tell the test harness
}
        jsr handle_key
        jmp main_loop

;----------------------------------------------------------------------------
; handle_key - A = key code, Y = modifiers (from get_key).
; Phase 2: RUN/STOP and RESTORE quit; everything else goes to the test
; screen. (The editor takes over in phase 3.)
;----------------------------------------------------------------------------
!zone handle_key
handle_key
        cmp #KEY_STOP
        beq quit
        cmp #KEY_RESTORE
        beq quit
        cmp #KEY_CHARSET
        beq toggle_charset
        sta last_code
        sty last_mods
        jsr show_last_key
        jmp echo_key

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
; init_screen - colors, character set, clear the text area, test text.
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

        ; Phase 2 test screen (texts in data.asm)
        lda #<test_texts
        sta zp_ptr2
        lda #>test_texts
        sta zp_ptr2+1
        jsr print_list

        ; Show which video system was detected on row 2.
        ldx system_type
        lda system_name_offset,x
        tax
        ldy #0
-       lda system_names,x
        beq +
        sta SCREEN+2*40+1,y
        inx
        iny
        bne -
+       lda #ECHO_TOP
        sta echo_row
        rts

;----------------------------------------------------------------------------
; print_list - print a list of texts. zp_ptr2 points to the list:
; for each text a row, a column, the screen codes and a 0; $ff ends it.
;----------------------------------------------------------------------------
!zone print_list
print_list
        ldy #0
        lda (zp_ptr2),y         ; row, or $ff = end of the list
        cmp #$ff
        beq .end
        tax
        iny
        lda (zp_ptr2),y         ; column
        clc                     ; zp_ptr = start of the row + column
        adc row_lo,x
        sta zp_ptr
        lda row_hi,x
        adc #0
        sta zp_ptr+1
        lda zp_ptr2             ; step over row and column
        clc
        adc #2
        sta zp_ptr2
        bcc +
        inc zp_ptr2+1
+       ldy #0
-       lda (zp_ptr2),y         ; copy the text
        beq +
        sta (zp_ptr),y
        iny
        bne -
+       iny                     ; step over the text and its 0
        tya
        clc
        adc zp_ptr2
        sta zp_ptr2
        bcc print_list
        inc zp_ptr2+1
        bne print_list          ; (always)
.end    rts

;============================================================================
; Phase 2 test screen (the editor replaces this in phase 3)
;============================================================================
ECHO_TOP        = 12            ; typed text goes on rows 12-23
ECHO_BOTTOM     = 23

; show_held - the "Held:" labels on row 8 show reversed while held.
!zone show_held
show_held
        ldx #0                  ; index into held_labels (3 bytes each)
        ldy #0                  ; index into held_text
.label  lda held_labels+2,x     ; the modifier bit for this label
        and key_mods
        beq +
        lda #$80                ; held: reversed characters
+       sta .rvs
        lda held_labels,x       ; column
        sta .col
        lda held_labels+1,x     ; length
        sta .len
        stx .x
.char   lda held_text,y
        ora .rvs
        ldx .col
        sta SCREEN+8*40,x
        inc .col
        iny
        dec .len
        bne .char
        ldx .x
        inx
        inx
        inx
        cpx #4*3
        bne .label
        rts
.rvs    !byte 0
.col    !byte 0
.len    !byte 0
.x      !byte 0

; show_last_key - row 9: key code in hex, the character it types, and the
; modifiers that came with it.
!zone show_last_key
show_last_key
        lda #$24                ; "$"
        sta SCREEN+9*40+11
        lda last_code
        jsr hex_digits
        stx SCREEN+9*40+12
        sta SCREEN+9*40+13

        lda last_code           ; the character it types
        ldy last_mods
        jsr key_to_petscii
        bcs .blank
        jsr petscii_to_screen
        bcc +
.blank  lda #$20
+       sta SCREEN+9*40+15

        lda last_mods           ; LS RS CT C=: a name for each bit that is
        sta .bits               ; set, spaces for the others
        ldx #0
.mod    lsr .bits               ; next modifier bit into carry
        ldy #3
-       lda #$20
        bcc +
        lda mod_names,x
+       sta SCREEN+9*40+18,x
        inx
        dey
        bne -
        cpx #4*3
        bne .mod

        ldx #2                  ; REP for a repeat
-       lda #$20
        bit last_mods
        bpl +
        lda mod_repeat,x
+       sta SCREEN+9*40+31,x
        dex
        bpl -
        rts
.bits   !byte 0

; hex_digits - A = a byte. Returns X = screen code of the high hex digit,
; A = screen code of the low one.
!zone hex_digits
hex_digits
        pha
        lsr
        lsr
        lsr
        lsr
        jsr .digit
        tax
        pla
        and #$0f
.digit  cmp #10
        bcc +
        sbc #9                  ; 10-15 -> 1-6, the screen codes of A-F
        rts                     ; (carry is set here)
+       ora #$30                ; 0-9 -> screen codes of "0"-"9"
        rts

; echo_key - type the last key's character on rows 12-23. RETURN starts a
; new line, DEL rubs out; other control codes are not shown.
!zone echo_key
echo_key
        lda last_code
        ldy last_mods
        jsr key_to_petscii
        bcs .done               ; types nothing
        cmp #$0d                ; RETURN
        beq .newline
        cmp #$8d                ; SHIFT + RETURN
        beq .newline
        cmp #$14                ; DEL
        beq .delete
        jsr petscii_to_screen
        bcs .done               ; other control codes
        pha
        jsr .point
        pla
        ldy echo_col
        sta (zp_ptr),y
        lda text_color
        sta (zp_ptr2),y
        inc echo_col
        lda echo_col
        cmp #40
        bcc .done
.newline
        lda #0
        sta echo_col
        inc echo_row
        lda echo_row
        cmp #ECHO_BOTTOM+1
        bcc .done
        jmp clear_echo          ; full: clear and start at the top again
.done   rts

.delete lda echo_col
        beq .done               ; already at the start of the line
        dec echo_col
        jsr .point
        ldy echo_col
        lda #$20
        sta (zp_ptr),y
        rts

; .point - zp_ptr = echo_row in screen RAM, zp_ptr2 = the same in color RAM
.point  ldx echo_row
        lda row_lo,x
        sta zp_ptr
        sta zp_ptr2
        lda row_hi,x
        sta zp_ptr+1
        clc
        adc #>(COLOR_RAM - SCREEN)
        sta zp_ptr2+1
        rts

; clear_echo - clear rows 12-23 and start typing at the top.
clear_echo
        lda #ECHO_TOP
        sta echo_row
-       jsr .point
        ldy #39
        lda #$20
.clear  sta (zp_ptr),y
        dey
        bpl .clear
        inc echo_row
        lda echo_row
        cmp #ECHO_BOTTOM+1
        bcc -
        lda #ECHO_TOP
        sta echo_row
        lda #0
        sta echo_col
        rts

;----------------------------------------------------------------------------
; Variables
;----------------------------------------------------------------------------
load_device     !byte 0         ; $BA at start-up
entry_sp        !byte 0         ; stack pointer at start-up (for quit)
text_bg         !byte BLACK     ; text background color (setting)
text_color      !byte LIGHT_GREY ; default text color (setting)

last_code       !byte 0         ; phase 2 test screen
last_mods       !byte 0
echo_row        !byte 0
echo_col        !byte 0

;----------------------------------------------------------------------------
; The other source files
;----------------------------------------------------------------------------
!source "src/system.asm"
!source "src/irq.asm"
!source "src/input.asm"
!source "src/editor.asm"
!source "src/data.asm"

; The program must end before the sprite blocks at $3e80.
!if * > SPRITE_BASE {
        !error "Program has grown into the sprite blocks at $3e80"
}
