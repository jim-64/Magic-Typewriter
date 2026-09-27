;============================================================================
; data.asm - sprite data, strings, tables
;============================================================================

;----------------------------------------------------------------------------
; Sprite images. Only the rows that are used are stored; init_sprites
; copies them into empty 64-byte sprite blocks.
; Header: first row in the block (0-20), then the number of bytes that
; follow (3 bytes per 24-pixel row). See init_sprites for why the top
; badges and the menu icon sit at the bottom of their blocks.
;----------------------------------------------------------------------------

; Mouse pointer: 8x8 box, red
spr_pointer
        !byte 0, 8*3
        !byte %11111111,0,0
        !byte %11000011,0,0
        !byte %11000011,0,0
        !byte %11000011,0,0
        !byte %11000011,0,0
        !byte %11000011,0,0
        !byte %11000011,0,0
        !byte %11111111,0,0

; Menu icon "=F1" (23x7)
spr_menu
        !byte 21-7, 7*3
        !byte $ff,$3c,$c0       ; XXXXXXXX..XXXX..XX......
        !byte $00,$31,$c0       ; ..........XX...XXX......
        !byte $00,$30,$c0       ; ..........XX....XX......
        !byte $ff,$38,$c0       ; XXXXXXXX..XXX...XX......
        !byte $00,$30,$c0       ; ..........XX....XX......
        !byte $00,$30,$c0       ; ..........XX....XX......
        !byte $ff,$31,$e0       ; XXXXXXXX..XX...XXXX.....

; "F3" badge, points up (24x13)
spr_f3
        !byte 21-13, 13*3
        !byte $00,$18,$00       ; ...........XX...........
        !byte $00,$7e,$00       ; .........XXXXXX.........
        !byte $01,$c3,$80       ; .......XXX....XXX.......
        !byte $07,$00,$e0       ; .....XXX........XXX.....
        !byte $1c,$00,$38       ; ...XXX............XXX...
        !byte $71,$e7,$0e       ; .XXX...XXXX..XXX....XXX.
        !byte $c1,$8d,$83       ; XX.....XX...XX.XX.....XX
        !byte $c1,$81,$83       ; XX.....XX......XX.....XX
        !byte $c1,$c3,$03       ; XX.....XXX....XX......XX
        !byte $c1,$81,$83       ; XX.....XX......XX.....XX
        !byte $c1,$8d,$83       ; XX.....XX...XX.XX.....XX
        !byte $c1,$87,$03       ; XX.....XX....XXX......XX
        !byte $c0,$00,$03       ; XX....................XX

; "F5" badge, points down (24x13)
spr_f5
        !byte 0, 13*3
        !byte $c0,$00,$03       ; XX....................XX
        !byte $c1,$ef,$83       ; XX.....XXXX.XXXXX.....XX
        !byte $c1,$8c,$03       ; XX.....XX...XX........XX
        !byte $c1,$8f,$03       ; XX.....XX...XXXX......XX
        !byte $c1,$c1,$83       ; XX.....XXX.....XX.....XX
        !byte $c1,$81,$83       ; XX.....XX......XX.....XX
        !byte $c1,$8d,$83       ; XX.....XX...XX.XX.....XX
        !byte $71,$87,$0e       ; .XXX...XX....XXX....XXX.
        !byte $1c,$00,$38       ; ...XXX............XXX...
        !byte $07,$00,$e0       ; .....XXX........XXX.....
        !byte $01,$c3,$80       ; .......XXX....XXX.......
        !byte $00,$7e,$00       ; .........XXXXXX.........
        !byte $00,$18,$00       ; ...........XX...........

; Sprite positions for sprites 0-5: X (low 8 bits), Y
PTR_TEST_X = 24 + 37*8          ; phase 1: pointer parked on text column 37,
PTR_TEST_Y = 51 + 22*8 - 1      ; row 22 (the mouse moves it in phase 7)
spr_positions
        !byte <PTR_TEST_X,   PTR_TEST_Y         ; 0 pointer
        !byte <SPR_MENU_X,   SPR_MENU_Y         ; 1 menu icon
        !byte <SPR_LEFT_X,   SPR_TOP_Y          ; 2 F3 left
        !byte <SPR_RIGHT_X,  SPR_TOP_Y          ; 3 F3 right
        !byte <SPR_LEFT_X,   SPR_BOT_Y          ; 4 F5 left
        !byte <SPR_RIGHT_X,  SPR_BOT_Y          ; 5 F5 right
; X bit 8 for each sprite (bit n = sprite n)
SPR_XMSB_BITS = (>PTR_TEST_X) | ((>SPR_MENU_X) << 1) | ((>SPR_LEFT_X) << 2) | ((>SPR_RIGHT_X) << 3) | ((>SPR_LEFT_X) << 4) | ((>SPR_RIGHT_X) << 5)

;----------------------------------------------------------------------------
; Strings (screen codes; !scr turns lower case into the letters of the
; upper/lower character set and upper case into its capitals)
;----------------------------------------------------------------------------
test_text
        !scr "Magic Typewriter - phase 1 test", 0

system_name_offset
        !byte .pal-system_names, .ntsc-system_names
        !byte .oldntsc-system_names, .drean-system_names
system_names
.pal     !scr "Video: PAL", 0
.ntsc    !scr "Video: NTSC", 0
.oldntsc !scr "Video: old NTSC", 0
.drean   !scr "Video: Drean (PAL-N)", 0
