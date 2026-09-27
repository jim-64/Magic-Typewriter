;============================================================================
; irq.asm - raster IRQ chain, border sprites, page position marker
;
; Each frame runs these raster IRQs, in this order:
;
;   line  48  irq_top_a      set up the stable top split
;   line  50  split_top_...  end of line 50: $D020 = side color, $D021 = text bg
;   marker    irq_mark_top   side border -> grey    (skipped if not needed)
;   marker    irq_mark_bot   side border -> dark grey (skipped if not needed)
;   line 247  irq_bot_a      set up the stable bottom split
;   line 249  split_bot_...  24 rows (opens the border), then at the end of
;                            line 250: $D020 = $D021 = blue
;   line 254  irq_housekeep  back to 25 rows, sprites 1-3 off, frame
;                            counter, marker update
;   line  10  irq_frame_top  sprites 1-3 back on (mouse read in phase 7)
;
; All IRQs come in through the KERNAL's IRQ entry at $FF48, which saves
; A, X and Y and jumps through ($0314). Each handler sets up the next one
; and leaves through irq_exit. We never call the KERNAL's own handler at
; $EA31 (it would scan the keyboard and blink the BASIC cursor).
;
; Why the top and bottom borders open: the VIC turns the border on at line
; 251 in 25-row mode, but at line 247 in 24-row mode. Switching to 24 rows
; on line 249 means it misses both, so the border stays off for the rest of
; the frame. We switch back to 25 rows at line 254, after the check.
;============================================================================

FRAME_TOP_LINE   = 10
SPLIT_TOP_A_LINE = 48
SPLIT_TOP_LINE   = 50           ; the last line of the top strip
SPLIT_BOT_A_LINE = 247
SPLIT_BOT_LINE   = 249          ; one line before the last text line (250)
HOUSEKEEP_LINE   = 254

MARK_MIN_LINE   = 54            ; marker IRQs must lie between the splits
MARK_MAX_LINE   = 244

;----------------------------------------------------------------------------
; Stable raster timing
;
; A normal IRQ starts 0-7 cycles late, depending on which instruction the
; CPU was in the middle of. The color splits must change $D020 and $D021
; exactly in the horizontal blanking (the ~12 cycles between the right
; border of one line and the left border of the next), so we use the
; "double IRQ" method to get an exact cycle:
;
; 1. The first IRQ (irq_top_a / irq_bot_a) points the IRQ vector at the
;    second handler, sets the raster compare two lines further on, then
;    allows interrupts and runs a row of NOPs. The second IRQ then arrives
;    during a NOP, so it is only 0 or 1 cycle late.
; 2. The second handler waits until the very end of its line and compares
;    $D012. If the line has not changed yet we were early, and the BEQ
;    takes one cycle more (3 instead of 2) - after that the timing is exact.
;
; Lines are 63, 64 or 65 cycles long depending on the video system, and the
; sprite fetches fall at different places in the line, so each second
; handler is assembled once per system (see the macros below) and init_irq
; picks the right copy.
;
; How the wait counts were found (VICE 3.9, x64sc): build with
;   acme ... -DSPLIT_TEST=1 -DTOP_PAL_WAIT=10 ...
; which records whether each compare saw the old line or the next one
; (see the split_test macro). Only the right wait count gives both results
; over many frames: one count lower is always "old line", one count higher
; always "next line". The second bottom wait (..._WAIT2) was then set by
; screenshots, so that $D020 changes in the blanking just after the sprite
; fetches for the F5 badges.
;
; !ifndef lets a test build override any of them from the command line.
;
; Sprite fetches steal cycles at the end of a line, and the counts below
; assume only the fixed border sprites. The mouse pointer (phase 7) can add
; fetches near lines 50/51 and 250/251; that has to be handled then.
;
;                          top split     bottom split
;                          WAIT          WAIT1   WAIT2
; PAL (63 cycles)          10            5       53
; NTSC (65 cycles)         13            7       54
; old NTSC (64 cycles)     11            6       54
; Drean (65 cycles)        13            7       54
;----------------------------------------------------------------------------
!ifndef TOP_PAL_WAIT       { TOP_PAL_WAIT       = 10 }
!ifndef TOP_NTSC_WAIT      { TOP_NTSC_WAIT      = 13 }
!ifndef TOP_OLDNTSC_WAIT   { TOP_OLDNTSC_WAIT   = 11 }
!ifndef TOP_DREAN_WAIT     { TOP_DREAN_WAIT     = 13 }
!ifndef BOT_PAL_WAIT1      { BOT_PAL_WAIT1      = 5 }
!ifndef BOT_PAL_WAIT2      { BOT_PAL_WAIT2      = 53 }
!ifndef BOT_NTSC_WAIT1     { BOT_NTSC_WAIT1     = 7 }
!ifndef BOT_NTSC_WAIT2     { BOT_NTSC_WAIT2     = 54 }
!ifndef BOT_OLDNTSC_WAIT1  { BOT_OLDNTSC_WAIT1  = 6 }
!ifndef BOT_OLDNTSC_WAIT2  { BOT_OLDNTSC_WAIT2  = 54 }
!ifndef BOT_DREAN_WAIT1    { BOT_DREAN_WAIT1    = 7 }
!ifndef BOT_DREAN_WAIT2    { BOT_DREAN_WAIT2    = 54 }

;----------------------------------------------------------------------------
; Macros
;----------------------------------------------------------------------------

; wait - use up exactly .cycles CPU cycles (0, or 2 and more).
; NOP takes 2 cycles; for an odd count, one BIT zp (3 cycles) goes first.
!macro wait .cycles {
        !if (.cycles < 0) | (.cycles = 1) {
                !error "wait: cannot wait ", .cycles, " cycles"
        }
        !if .cycles & 1 {
                bit zp_ptr      ; 3 cycles (just reads; changes only flags)
                !set .nops = (.cycles - 3) / 2
        } else {
                !set .nops = .cycles / 2
        }
        !if .nops > 0 {
                !for .i, 1, .nops {
                        nop
                }
        }
}

; split_test - timing test builds only (acme -DSPLIT_TEST=1, with DEBUG=1).
; Placed right after the compare of a stable split: records whether the
; compare saw the old line ("early", +0) or the next line ("late", +1).
; The timing after this point is thrown off, but it tells us if the wait
; is right: only with the correct wait count do BOTH outcomes happen,
; because only then does the compare fall exactly on the line change.
!macro split_test .flags {
        php                     ; keep the compare result
        bne .late
        lda #1
        sta .flags              ; saw the old line
        bne .done
.late   lda #1
        sta .flags+1            ; saw the next line
.done   plp
}

; next_irq - set the raster line and handler of the next IRQ.
; (Every IRQ line we use is below 256, so bit 7 of $D011 stays 0.)
!macro next_irq .line, .handler {
        lda #.line
        sta VIC_RASTER
        lda #<.handler
        sta IRQ_VECTOR
        lda #>.handler
        sta IRQ_VECTOR+1
}

;----------------------------------------------------------------------------
; init_irq - take over the IRQ and start the chain. Call with IRQs off.
;----------------------------------------------------------------------------
!zone init_irq
init_irq
        lda #$7f                ; switch off all CIA1 interrupts
        sta CIA1_ICR
        lda CIA1_ICR            ; and clear any that are waiting

        ldx system_type         ; pick the split handlers for this system
        lda tab_split_top_lo,x
        sta split_top_vec
        lda tab_split_top_hi,x
        sta split_top_vec+1
        lda tab_split_bot_lo,x
        sta split_bot_vec
        lda tab_split_bot_hi,x
        sta split_bot_vec+1

        +next_irq SPLIT_TOP_A_LINE, irq_top_a
        lda #$01                ; enable the raster IRQ only
        sta VIC_IRQ_MASK
        lda #$ff                ; clear any old VIC IRQ flags
        sta VIC_IRQ_FLAGS
        rts

;----------------------------------------------------------------------------
; restore_irq - give the IRQ back to the KERNAL. Call with IRQs off.
;----------------------------------------------------------------------------
!zone restore_irq
restore_irq
        lda #0                  ; no more raster IRQs
        sta VIC_IRQ_MASK
        lda #$ff
        sta VIC_IRQ_FLAGS
        lda #<KERNAL_IRQ
        sta IRQ_VECTOR
        lda #>KERNAL_IRQ
        sta IRQ_VECTOR+1
        lda #$81                ; CIA1 timer A IRQ back on (60 Hz KERNAL tick)
        sta CIA1_ICR
        rts

;----------------------------------------------------------------------------
; irq_exit - every handler leaves through here.
; Undoes the KERNAL's pushes of A, X and Y, then returns from the IRQ.
;----------------------------------------------------------------------------
irq_exit
        pla
        tay
        pla
        tax
        pla
        rti

;============================================================================
; Top color split
;============================================================================

; irq_top_a - line 48: prepare the stable IRQ for line 50.
!zone irq_top_a
irq_top_a
        lda split_top_vec       ; second IRQ goes to split_top_pal/ntsc/...
        sta IRQ_VECTOR
        lda split_top_vec+1
        sta IRQ_VECTOR+1
        lda #SPLIT_TOP_LINE
        sta VIC_RASTER
        lda #$ff                ; acknowledge this IRQ
        sta VIC_IRQ_FLAGS
        tsx                     ; remember the stack; the second IRQ
        stx saved_sp            ; will throw its own stack frame away
        ldy text_bg             ; Y survives the KERNAL entry: the second
                                ; handler uses it for $D021
        cli                     ; let the second IRQ in ...
        !for .i, 1, 45 {        ; ... while we run NOPs (90 cycles, more
                nop             ; than enough to reach line 50)
        }
        jmp irq_exit            ; (never reached)

; The second handler, one copy per video system. Enters on line 50 with
; Y = text background color. It only has a few cycles to spare before the
; end of line 50, so fixing the stack waits until the colors are set.
; $D021 only shows in the middle of the line, so it can change any time
; after the text of line 50 ends; $D020 must change in the blanking.
!macro split_top .wait {
        ldx #SPLIT_TOP_LINE
        lda irq_color51         ; side border color for line 51 onward
        +wait .wait
        sty VIC_BG0             ; line 50, in the right border
        cpx VIC_RASTER          ; read at the very end of line 50
!ifdef SPLIT_TEST {
        +split_test MB_TEST_TOP
}
        beq +                   ; still line 50: 1 cycle extra
+       sta VIC_BORDER          ; start of line 51, in the blanking
        ldx saved_sp            ; now drop the second IRQ's stack frame
        txs
        jmp split_top_done
}

!zone split_top
split_top_pal     +split_top TOP_PAL_WAIT
split_top_ntsc    +split_top TOP_NTSC_WAIT
split_top_oldntsc +split_top TOP_OLDNTSC_WAIT
split_top_drean   +split_top TOP_DREAN_WAIT

split_top_done
        lda #$ff                ; acknowledge the IRQ
        sta VIC_IRQ_FLAGS
        lda irq_mark_top        ; next: marker top, marker bottom, or
        beq +                   ; the bottom split, whichever is first
        sta VIC_RASTER
        lda #<irq_mark_top_h
        sta IRQ_VECTOR
        lda #>irq_mark_top_h
        sta IRQ_VECTOR+1
        jmp irq_exit
+       jmp mark_next

;============================================================================
; Page position marker
; The side border turns grey from irq_mark_top down to irq_mark_bot.
; $D020 is written while the beam is in the text part of the line, so the
; right side changes on this line and the left side on the next.
;============================================================================

!zone irq_mark
irq_mark_top_h
        lda #GREY
        sta VIC_BORDER
        lda #$ff
        sta VIC_IRQ_FLAGS
mark_next                       ; set up irq_mark_bot, or the bottom split
        lda irq_mark_bot
        beq +
        sta VIC_RASTER
        lda #<irq_mark_bot_h
        sta IRQ_VECTOR
        lda #>irq_mark_bot_h
        sta IRQ_VECTOR+1
        jmp irq_exit
+       +next_irq SPLIT_BOT_A_LINE, irq_bot_a
        jmp irq_exit

irq_mark_bot_h
        lda #DARK_GREY
        sta VIC_BORDER
        lda #$ff
        sta VIC_IRQ_FLAGS
        +next_irq SPLIT_BOT_A_LINE, irq_bot_a
        jmp irq_exit

;============================================================================
; Bottom color split (and border opening)
;============================================================================

; irq_bot_a - line 247: prepare the stable IRQ for line 249.
!zone irq_bot_a
irq_bot_a
        lda split_bot_vec       ; second IRQ goes to split_bot_pal/ntsc/...
        sta IRQ_VECTOR
        lda split_bot_vec+1
        sta IRQ_VECTOR+1
        lda #SPLIT_BOT_LINE
        sta VIC_RASTER
        lda #$ff
        sta VIC_IRQ_FLAGS
        tsx
        stx saved_sp
        cli
        !for .i, 1, 45 {
                nop
        }
        jmp irq_exit            ; (never reached)

; The second handler, one copy per video system. Enters on line 249.
!macro split_bot .w1, .w2 {
        ldx saved_sp            ; drop the second IRQ's stack frame
        txs
        lda #CTRL1_24ROWS       ; 24 rows: the border will not close
        sta VIC_CTRL1
        ldx #BLUE
        lda #SPLIT_BOT_LINE
        +wait .w1
        cmp VIC_RASTER          ; read at the very end of line 249
!ifdef SPLIT_TEST {
        +split_test MB_TEST_BOT
}
        beq +                   ; still line 249: 1 cycle extra
+       +wait .w2               ; on to the end of line 250
        stx VIC_BG0             ; right border (the text is finished)
        stx VIC_BORDER          ; blanking
        jmp split_bot_done
}

!zone split_bot
split_bot_pal     +split_bot BOT_PAL_WAIT1, BOT_PAL_WAIT2
split_bot_ntsc    +split_bot BOT_NTSC_WAIT1, BOT_NTSC_WAIT2
split_bot_oldntsc +split_bot BOT_OLDNTSC_WAIT1, BOT_OLDNTSC_WAIT2
split_bot_drean   +split_bot BOT_DREAN_WAIT1, BOT_DREAN_WAIT2

split_bot_done
        lda #$ff
        sta VIC_IRQ_FLAGS
        +next_irq HOUSEKEEP_LINE, irq_housekeep
        jmp irq_exit

;============================================================================
; Housekeeping - line 254, below the bottom border check
; (Keyboard scan and cursor blink will go here in phases 2 and 3.)
;============================================================================
!zone irq_housekeep
irq_housekeep
        lda #CTRL1_25ROWS       ; back to 25 rows for the next frame
        sta VIC_CTRL1
        lda #$ff
        sta VIC_IRQ_FLAGS

        ; The VIC compares sprite Y with the low 8 bits of the raster line,
        ; so on PAL (312 lines) the top badges and the menu icon would show
        ; a second time at lines 256+Y, low in the bottom border. Switch them
        ; off until irq_frame_top.
        lda #SPR_ON_BOTTOM
        sta VIC_SPR_ENABLE

        inc frame_count         ; 16-bit frame counter
        bne +
        inc frame_count+1
+
        lda marker_pending      ; new marker position from the main loop?
        beq +
        jsr marker_apply
+
!if DEBUG {
        lda frame_count         ; let the test harness see that we run
        sta MB_FRAMES
        lda frame_count+1
        sta MB_FRAMES+1
}
        +next_irq FRAME_TOP_LINE, irq_frame_top
        jmp irq_exit

;============================================================================
; Top of the frame - line 10, before any sprite starts
;============================================================================
!zone irq_frame_top
irq_frame_top
        lda #$ff
        sta VIC_IRQ_FLAGS
        lda #SPR_ON_ALL         ; all six sprites back on
        sta VIC_SPR_ENABLE
        +next_irq SPLIT_TOP_A_LINE, irq_top_a
        jmp irq_exit

;----------------------------------------------------------------------------
; IRQ variables
;----------------------------------------------------------------------------
saved_sp        !byte 0         ; stack pointer saved by the first IRQ
split_top_vec   !word 0         ; second-IRQ handlers for this system
split_bot_vec   !word 0
frame_count     !word 0

; Marker values used by the IRQs (0 = no IRQ needed)
irq_color51     !byte DARK_GREY ; side color from line 51 (grey if the
                                ; marker starts at the top)
irq_mark_top    !byte 0         ; line where the side turns grey
irq_mark_bot    !byte 0         ; line where it turns back to dark grey

;============================================================================
; Page position marker math
;
; Call marker_set with mk_first = first visible line and mk_total = total
; lines in the document. It works out the band of side border lines:
;   top    = 51 + 200 * first / total
;   height = max(8, 200 * 25 / total)
; and hands the result to the housekeeping IRQ, which switches over
; between frames so the IRQ chain never sees half-updated values.
;============================================================================
mk_first        !word 0
mk_total        !word 0
band_top        !byte 0         ; first grey line
band_bot        !byte 0         ; first dark grey line after the band

new_color51     !byte 0         ; waiting for the housekeeping IRQ
new_mark_top    !byte 0
new_mark_bot    !byte 0
marker_pending  !byte 0

!zone marker_set
marker_set
        lda mk_total+1          ; 25 lines or fewer: all of it is visible
        bne .big
        lda mk_total
        cmp #26
        bcs .big
        lda #51
        sta band_top
        lda #251
        sta band_bot
        jmp .place

.big    ; top = 51 + 200 * first / total
        lda mk_first
        sta math_num
        lda mk_first+1
        sta math_num+1
        lda #200
        sta math_mul
        jsr mul_16x8
        lda mk_total
        sta math_div
        lda mk_total+1
        sta math_div+1
        jsr div_24x16
        lda math_num+2          ; the result should be below 200; if the
        ora math_num+1          ; input was bad, pin it at 199
        bne .pin
        lda math_num
        cmp #200
        bcc +
.pin    lda #199
+       clc
        adc #51
        sta band_top

        ; height = 5000 / total (total is at least 26 here, so it fits
        ; in one byte)
        lda #<5000
        sta math_num
        lda #>5000
        sta math_num+1
        lda #0
        sta math_num+2
        jsr div_24x16           ; divisor is still mk_total
        lda math_num
        cmp #8
        bcs +
        lda #8                  ; at least 8 lines tall
+       clc
        adc band_top
        bcs .clip               ; past line 255
        cmp #252
        bcc +
.clip   lda #251                ; no further than the end of the text area
+       sta band_bot

.place  ; Move edges off badlines (line & 7 = 3, our YSCROLL): on a badline
        ; the CPU is stopped during the text part of the line.
        lda band_top
        jsr .snap
        sta band_top
        lda band_bot
        jsr .snap
        sta band_bot

        ; Work out which IRQs are needed. Near the top of the text area the
        ; top split sets grey itself; near the bottom, the bottom split
        ; ends the band.
        ldx #DARK_GREY
        lda band_top
        cmp #MARK_MIN_LINE
        bcs +
        ldx #GREY               ; band starts at line 51
        lda #0                  ; no marker-top IRQ
+       php                     ; hand over all three values together,
        sei                     ; with IRQs held off for a moment
        stx new_color51
        sta new_mark_top
        lda band_bot
        cmp #MARK_MAX_LINE+1
        bcc +
        lda #0                  ; no marker-bottom IRQ
+       sta new_mark_bot
        lda #1
        sta marker_pending
        plp                     ; IRQs back as they were
!if DEBUG {
        lda band_top            ; results for the test harness
        sta MB_MK_TOP
        lda band_bot
        sta MB_MK_BOT
}
        rts

.snap   tay                     ; A = line; returns A = line, +1 if badline
        and #7
        cmp #3
        bne +
        iny
+       tya
        rts

; marker_apply - copy the new marker values into the IRQ variables.
; Called by the housekeeping IRQ (and once at start-up).
marker_apply
        lda new_color51
        sta irq_color51
        lda new_mark_top
        sta irq_mark_top
        lda new_mark_bot
        sta irq_mark_bot
        lda #0
        sta marker_pending
        rts

; init_marker - phase 1: a made-up position (line 40 of 160).
; (A test build can pick another with -DFAKE_FIRST=... -DFAKE_TOTAL=...)
!ifndef FAKE_FIRST { FAKE_FIRST = 40 }
!ifndef FAKE_TOTAL { FAKE_TOTAL = 160 }
init_marker
        lda #<FAKE_FIRST
        sta mk_first
        lda #>FAKE_FIRST
        sta mk_first+1
        lda #<FAKE_TOTAL
        sta mk_total
        lda #>FAKE_TOTAL
        sta mk_total+1
        jsr marker_set
        jmp marker_apply

;============================================================================
; Border sprites
;
; Sprite blocks live at $3e80-$3fff (blocks 250-255), in VIC bank 0.
; $3fff must stay $00: the VIC draws that byte in the opened borders.
;
;
; A sprite's first row appears on raster line Y+1, and the VIC always
; fetches all 21 rows of a sprite, even blank ones. Those fetches steal CPU
; cycles at the end of each line, which would upset the stable color split
; at the end of line 50. So the top badges and the menu icon keep their
; picture in the BOTTOM rows of their blocks: all 21 fetched lines then end
; by line 50, and nothing is fetched at the line 50 -> 51 split.
;============================================================================
SPRITE_BASE     = $3e80
SPR_BLOCK_PTR   = 250           ; mouse pointer
SPR_BLOCK_MENU  = 251           ; "=F1" menu icon
SPR_BLOCK_F3    = 252           ; F3 badge (sprites 2 and 3)
SPR_BLOCK_F5    = 253           ; F5 badge (sprites 4 and 5)

SPR_TOP_Y       = 50 - 21       ; F3 badges: block on lines 30-50,
                                ; picture (rows 8-20) on lines 38-50
SPR_MENU_Y      = 49 - 21       ; menu icon: block on lines 29-49,
                                ; picture (rows 14-20) on lines 43-49
SPR_BOT_Y       = 251 - 1       ; F5 badges: picture (rows 0-12) on 251-263
SPR_ON_ALL      = %00111111     ; sprites 0-5
SPR_ON_BOTTOM   = %00110001     ; pointer and F5 badges only (see irq_housekeep)
SPR_LEFT_X      = 24            ; left edge of the text area
SPR_RIGHT_X     = 320           ; right edge (pixels 320-343), needs X bit 8
SPR_MENU_X      = 172           ; centered

!zone init_sprites
init_sprites
        ; Clear all six blocks ($3e80-$3fff), which also makes $3fff = 0.
        lda #0
        ldx #0
-       sta SPRITE_BASE+$80,x   ; $3f00-$3fff
        inx
        bne -
        ldx #$7f
-       sta SPRITE_BASE,x       ; $3e80-$3eff
        dex
        bpl -

        ; Copy the stored rows into the blocks.
        lda #<spr_pointer
        ldx #>spr_pointer
        ldy #SPR_BLOCK_PTR
        jsr .copy
        lda #<spr_menu
        ldx #>spr_menu
        ldy #SPR_BLOCK_MENU
        jsr .copy
        lda #<spr_f3
        ldx #>spr_f3
        ldy #SPR_BLOCK_F3
        jsr .copy
        lda #<spr_f5
        ldx #>spr_f5
        ldy #SPR_BLOCK_F5
        jsr .copy

        ; Sprite pointers
        lda #SPR_BLOCK_PTR
        sta SPRITE_PTRS+0
        lda #SPR_BLOCK_MENU
        sta SPRITE_PTRS+1
        lda #SPR_BLOCK_F3
        sta SPRITE_PTRS+2
        sta SPRITE_PTRS+3
        lda #SPR_BLOCK_F5
        sta SPRITE_PTRS+4
        sta SPRITE_PTRS+5

        ; Positions (table in data.asm: X low byte, Y for sprites 0-5)
        ldx #0
-       lda spr_positions,x
        sta VIC_SPR0_X,x
        inx
        cpx #12
        bne -
        lda #SPR_XMSB_BITS
        sta VIC_SPR_XMSB

        ; Colors
        lda #RED
        sta VIC_SPR0_COLOR
        lda #LIGHT_BLUE
        ldx #5
-       sta VIC_SPR0_COLOR,x
        dex
        bne -

        lda #0                  ; hi-res, normal size, in front of text
        sta VIC_SPR_MCOLOR
        sta VIC_SPR_EXPX
        sta VIC_SPR_EXPY
        sta VIC_SPR_PRIO
        lda #SPR_ON_ALL
        sta VIC_SPR_ENABLE
        rts

; .copy - copy sprite rows into a block. A/X = source address, Y = block.
; Source: first row in the block (0-20), byte count, then the bytes.
.copy   sta zp_ptr
        stx zp_ptr+1
        lda #0                  ; destination = block * 64 ...
        sta zp_ptr2+1
        tya
        ldx #6
-       asl
        rol zp_ptr2+1
        dex
        bne -
        sta zp_ptr2
        ldy #0                  ; ... + first row * 3
        lda (zp_ptr),y
        sta zp_tmp
        asl
        adc zp_tmp              ; row*2 + row (carry is clear: row < 21)
        adc zp_ptr2             ; block*64 low byte is at most 192, and
        sta zp_ptr2             ; row*3 at most 60: no carry out
        iny
        lda (zp_ptr),y          ; byte count
        tax
        lda zp_ptr              ; skip the two header bytes
        clc
        adc #2
        sta zp_ptr
        bcc +
        inc zp_ptr+1
+       ldy #0
-       lda (zp_ptr),y
        sta (zp_ptr2),y
        iny
        dex
        bne -
        rts
