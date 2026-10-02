;============================================================================
; data.asm - sprite data, strings, tables
;============================================================================

; Sprite positions for sprites 0-5: X (low 8 bits), Y
PTR_TEST_X = 24 + 37*8          ; phase 1: pointer parked on text column 37,
PTR_TEST_Y = 51 + 22*8 - 1      ; row 22 (the mouse moves it in phase 7)
; X bit 8 for each sprite (bit n = sprite n)
SPR_XMSB_BITS = (>PTR_TEST_X) | ((>SPR_MENU_X) << 1) | ((>SPR_LEFT_X) << 2) | ((>SPR_RIGHT_X) << 3) | ((>SPR_LEFT_X) << 4) | ((>SPR_RIGHT_X) << 5)
ICON_XMSB = SPR_XMSB_BITS & %11111110   ; the icons' bits (the pointer's is
                                        ; set by mouse_frame)

;----------------------------------------------------------------------------
; Screen row addresses: row n starts at SCREEN + 40*n (low and high bytes).
; Color RAM rows are at the same offsets from COLOR_RAM.
;----------------------------------------------------------------------------
row_lo
!for .r, 0, 24 {
        !byte <(SCREEN + 40 * .r)
}
row_hi
!for .r, 0, 24 {
        !byte >(SCREEN + 40 * .r)
}

;----------------------------------------------------------------------------
; Keyboard tables: key code (row * 8 + bit, see input.asm) -> PETSCII.
; Copied from the C64 KERNAL, so every key types what it types in BASIC.
; $01-$04 stand for the modifier keys and RUN/STOP; $ff = no character.
;----------------------------------------------------------------------------
keytab_normal                   ; no modifier (KERNAL $EB81)
        !byte $14, $0d, $1d, $88, $85, $86, $87, $11   ; DEL RETURN CRSR-RT F7 F1 F3 F5 CRSR-DN
        !byte $33, $57, $41, $34, $5a, $53, $45, $01   ; 3 W A 4 Z S E L-SHIFT
        !byte $35, $52, $44, $36, $43, $46, $54, $58   ; 5 R D 6 C F T X
        !byte $37, $59, $47, $38, $42, $48, $55, $56   ; 7 Y G 8 B H U V
        !byte $39, $49, $4a, $30, $4d, $4b, $4f, $4e   ; 9 I J 0 M K O N
        !byte $2b, $50, $4c, $2d, $2e, $3a, $40, $2c   ; + P L - . : @ ,
        !byte $5c, $2a, $3b, $13, $01, $3d, $5e, $2f   ; pound * ; HOME R-SHIFT = up-arrow /
        !byte $31, $5f, $04, $32, $20, $02, $51, $03   ; 1 <- CTRL 2 SPACE C= Q RUN/STOP
keytab_shift                    ; SHIFT (KERNAL $EBC2)
        !byte $94, $8d, $9d, $8c, $89, $8a, $8b, $91   ; DEL RETURN CRSR-RT F7 F1 F3 F5 CRSR-DN
        !byte $23, $d7, $c1, $24, $da, $d3, $c5, $01   ; 3 W A 4 Z S E L-SHIFT
        !byte $25, $d2, $c4, $26, $c3, $c6, $d4, $d8   ; 5 R D 6 C F T X
        !byte $27, $d9, $c7, $28, $c2, $c8, $d5, $d6   ; 7 Y G 8 B H U V
        !byte $29, $c9, $ca, $30, $cd, $cb, $cf, $ce   ; 9 I J 0 M K O N
        !byte $db, $d0, $cc, $dd, $3e, $5b, $ba, $3c   ; + P L - . : @ ,
        !byte $a9, $c0, $5d, $93, $01, $3d, $de, $3f   ; pound * ; HOME R-SHIFT = up-arrow /
        !byte $21, $5f, $04, $22, $a0, $02, $d1, $83   ; 1 <- CTRL 2 SPACE C= Q RUN/STOP
keytab_cbm                      ; C= (KERNAL $EC03)
        !byte $94, $8d, $9d, $8c, $89, $8a, $8b, $91   ; DEL RETURN CRSR-RT F7 F1 F3 F5 CRSR-DN
        !byte $96, $b3, $b0, $97, $ad, $ae, $b1, $01   ; 3 W A 4 Z S E L-SHIFT
        !byte $98, $b2, $ac, $99, $bc, $bb, $a3, $bd   ; 5 R D 6 C F T X
        !byte $9a, $b7, $a5, $9b, $bf, $b4, $b8, $be   ; 7 Y G 8 B H U V
        !byte $29, $a2, $b5, $30, $a7, $a1, $b9, $aa   ; 9 I J 0 M K O N
        !byte $a6, $af, $b6, $dc, $3e, $5b, $a4, $3c   ; + P L - . : @ ,
        !byte $a8, $df, $5d, $93, $01, $3d, $de, $3f   ; pound * ; HOME R-SHIFT = up-arrow /
        !byte $81, $5f, $04, $95, $a0, $02, $ab, $83   ; 1 <- CTRL 2 SPACE C= Q RUN/STOP
keytab_ctrl                     ; CTRL (KERNAL $EC78)
        !byte $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff   ; DEL RETURN CRSR-RT F7 F1 F3 F5 CRSR-DN
        !byte $1c, $17, $01, $9f, $1a, $13, $05, $ff   ; 3 W A 4 Z S E L-SHIFT
        !byte $9c, $12, $04, $1e, $03, $06, $14, $18   ; 5 R D 6 C F T X
        !byte $1f, $19, $07, $9e, $02, $08, $15, $16   ; 7 Y G 8 B H U V
        !byte $12, $09, $0a, $92, $0d, $0b, $0f, $0e   ; 9 I J 0 M K O N
        !byte $ff, $10, $0c, $ff, $ff, $1b, $00, $ff   ; + P L - . : @ ,
        !byte $1c, $ff, $1d, $ff, $ff, $1f, $1e, $ff   ; pound * ; HOME R-SHIFT = up-arrow /
        !byte $90, $06, $ff, $05, $ff, $ff, $11, $ff   ; 1 <- CTRL 2 SPACE C= Q RUN/STOP

;----------------------------------------------------------------------------
; Strings (screen codes; !scr turns lower case into the letters of the
; upper/lower character set and upper case into its capitals)
;----------------------------------------------------------------------------

; The PETSCII color codes, in C64 color order (0 black ... 15 light grey)
color_codes
        !byte $90, $05, $1c, $9f, $9c, $1e, $1f, $9e
        !byte $81, $95, $96, $97, $98, $99, $9a, $9b

; A color that reads well on each background color (black on the light
; ones, white on the dark ones), for prompts when the text color is the
; same as the background.
contrast_color
        !byte WHITE, BLACK, WHITE, BLACK, WHITE, BLACK, WHITE, BLACK
        !byte WHITE, WHITE, BLACK, WHITE, BLACK, BLACK, BLACK, BLACK

; The mouse pointer's color on each background color: red, but black on
; the backgrounds where red hardly shows (red, purple, orange and brown).
; The line 10 IRQ (irq_frame_top) puts it in every frame, and a border
; icon under the pointer lights up in the same color (mouse_frame).
pointer_colors
        !byte RED, RED, BLACK, RED, BLACK, RED, RED, RED
        !byte BLACK, BLACK, RED, RED, RED, RED, RED, RED

; Questions for prompt_yes_no. Written in lower case: that gives screen
; codes 1-26, which the prompt shows as capitals in either character set.
msg_quit_unsaved
        !scr "quit without saving y/n", 0
msg_undo_none
        !scr "nothing to undo", 0
msg_undo_big
        !scr "too big to undo", 0
msg_no_tape
        !scr "not for tape", 0
msg_find
        !scr "find:", 0
msg_not_found
        !scr "not found", 0
msg_command
        !scr "command:", 0
msg_need_disk
        !scr "defaults need a disk", 0
msg_defaults_saved
        !scr "defaults saved", 0
m_more
        !scr "more: any key   back: run/stop", 0
msg_clear_all
        !scr "clear all y/n", 0
msg_load_unsaved
        !scr "load without saving y/n", 0
msg_load
        !scr "load:", 0
msg_save
        !scr "save:", 0
msg_loading
        !scr "loading", 0
msg_saving
        !scr "saving", 0
msg_no_device
        !scr "device not present", 0
msg_bad_name
        !scr "no * ? or , in a file name", 0
msg_colors_lost
        !scr "colors will be lost y/n", 0
msg_printing
        !scr "printing", 0
msg_press_play
        !scr "press play on tape", 0
msg_press_record
        !scr "press record & play on tape", 0
msg_tape_error
        !scr "tape error", 0
msg_too_long
        !scr "too long: only part loaded", 0
msg_break
        !scr "break", 0
msg_no_room
        !scr "not enough room", 0

; Added to a file name when it is opened (PETSCII): sequential file, read
; or write
suffix_read
        !byte $2c, $53, $2c, $52        ; ,S,R
suffix_write
        !byte $2c, $53, $2c, $57        ; ,S,W
suffix_prg_read
        !byte $2c, $50, $2c, $52        ; ,P,R
suffix_prg_write
        !byte $2c, $50, $2c, $57        ; ,P,W
