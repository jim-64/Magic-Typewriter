;============================================================================
; irq.asm - raster IRQ chain, border sprites, page position marker
;
; Each frame runs these raster IRQs, in this order:
;
;   line  10  irq_frame_top  sprites 1-3 back on; the mouse pointer and icon
;                            colors worked out last frame go into the VIC
;   line  25  irq_top_a      set up the stable top IRQ
;   line  27  border_top_... open the side borders on lines 28-49 (so the
;                            F3 badges show there), then the color split
;                            at the end of line 50; then housekeeping
;                            (sprites 1-3 off, mouse, keyboard scan) with IRQs
;                            allowed, so the marker IRQs can cut in
;   marker    irq_mark_top   side border -> grey    (skipped if not needed)
;   marker    irq_mark_bot   side border -> dark grey (skipped if not needed)
;   line 247  irq_bot_a      set up the stable bottom IRQ
;   line 249  border_bot_... 24 rows (opens the top/bottom border), color
;                            split at the end of line 250, open the side
;                            borders on lines 251-264 (F5 badges), then
;                            back to 25 rows, frame counter, marker update
;
; All IRQs come in through irq_entry, a copy of the KERNAL's IRQ entry at
; $FF48 (the KERNAL ROM is switched out while we run), which saves A, X
; and Y and jumps through ($0314). Each handler sets up the next one and
; leaves through irq_exit. We never call the KERNAL's own handler at $EA31
; (it would scan the keyboard and blink the BASIC cursor).
;
; Opening the top and bottom borders: the VIC turns the border on at line
; 251 in 25-row mode, but at line 247 in 24-row mode. Switching to 24 rows
; on line 249 means it misses both, so the border stays off for the rest of
; the frame. We switch back to 25 rows after line 251.
;
; Opening the side borders: the VIC switches the side border on when the
; beam reaches the right edge of the text area - X=344 in 40-column mode,
; X=335 in 38-column mode. If we switch to 38 columns just after X=335 has
; passed but before X=344, it misses both, and the border stays off until
; the text area starts on the next line. That is one exact CPU cycle per
; line, so it is done from a stable IRQ, one line at a time. An opened side
; border shows the background color ($D021) and any sprites, which is how
; the F3/F5 badges can sit in the corners.
;============================================================================

FRAME_TOP_LINE   = 10
TOP_A_LINE       = 25
TOP_STABLE_LINE  = 27           ; its compare is at the end of this line
TOP_OPEN_LINES   = 22           ; side borders open on lines 28-49
BOT_A_LINE       = 247
BOT_STABLE_LINE  = 249          ; its compare is at the end of this line
BOT_OPEN_LINES   = 14           ; side borders open on lines 251-264

MARK_MIN_LINE   = 54            ; marker IRQs must lie between the strips
MARK_MAX_LINE   = 244

CSEL_40         = $08           ; $D016: 40 columns, no X scroll
CSEL_38         = $00           ; $D016: 38 columns

; Background color of the top and bottom strips. A test build with
; -DBORDER_TEST=1 makes it green, so a screenshot shows exactly which
; lines of the side borders are open (blue = closed, green = open).
!ifdef BORDER_TEST {
STRIP_BG        = GREEN
} else {
STRIP_BG        = BLUE
}

;----------------------------------------------------------------------------
; Stable raster timing
;
; A normal IRQ starts 0-7 cycles late, depending on which instruction the
; CPU was in the middle of. Opening the side borders needs one exact cycle,
; and the color splits need the blanking (the ~12 cycles between the right
; border of one line and the left border of the next), so we use the
; "double IRQ" method:
;
; 1. The first IRQ (irq_top_a / irq_bot_a) points the IRQ vector at the
;    second handler, sets the raster compare two lines further on, then
;    allows interrupts and runs a row of NOPs. The second IRQ then arrives
;    during a NOP, so it is only 0 or 1 cycle late.
; 2. The second handler waits until the very end of its line and compares
;    $D012. If the line has not changed yet we were early, and the BEQ
;    takes one cycle more (3 instead of 2) - after that the timing is exact.
;
; The compare must fall on a line change with no sprite fetches (they would
; stop the CPU right there): line 27/28 is before the top sprites start,
; line 249/250 is before the bottom ones.
;
; From then on everything is counted in cycles, including the cycles the
; sprite fetches steal at the end of each line. It is always the same
; sprites on the same lines, so always the same number of cycles.
;
; Lines are 63, 64 or 65 cycles long depending on the video system, and the
; sprite fetches fall at different places in the line, so each handler is
; assembled once per system (see the macros below) and init_irq picks the
; right copy.
;
; The mouse pointer (phase 7) adds sprite fetches wherever it is; in or
; near the strips that will shift this timing and has to be handled then.
;
; How the wait counts were found (VICE 3.9, x64sc):
; - ..._CMP: build with -DSPLIT_TEST=1, which records whether each compare
;   saw the old line or the next one (see the split_test macro). Only the
;   right count gives both results over many frames.
; - ..._PRE and ..._LOOP: build with -DBORDER_TEST=1 and take a screenshot:
;   every line of the side borders must be open. One cycle off and the
;   border stays closed.
; - ..._SPLIT: screenshots, so that $D020 changes inside the blanking.
;
; !ifndef lets a test build override any of them from the command line.
;----------------------------------------------------------------------------
!ifndef TOP_PAL_CMP        { TOP_PAL_CMP        = 13 }
!ifndef TOP_PAL_PRE        { TOP_PAL_PRE        = 37 }
!ifndef TOP_PAL_LOOP       { TOP_PAL_LOOP       = 41 }
!ifndef TOP_PAL_SPLIT      { TOP_PAL_SPLIT      = 4 }
!ifndef BOT_PAL_CMP        { BOT_PAL_CMP        = 3 }
!ifndef BOT_PAL_SPLIT      { BOT_PAL_SPLIT      = 56 }
!ifndef BOT_PAL_PRE        { BOT_PAL_PRE        = 36 }
!ifndef BOT_PAL_LOOP       { BOT_PAL_LOOP       = 43 }

!ifndef TOP_NTSC_CMP       { TOP_NTSC_CMP       = 15 }
!ifndef TOP_NTSC_PRE       { TOP_NTSC_PRE       = 37 }
!ifndef TOP_NTSC_LOOP      { TOP_NTSC_LOOP      = 43 }
!ifndef TOP_NTSC_SPLIT     { TOP_NTSC_SPLIT     = 6 }
!ifndef BOT_NTSC_CMP       { BOT_NTSC_CMP       = 5 }
!ifndef BOT_NTSC_SPLIT     { BOT_NTSC_SPLIT     = 58 }
!ifndef BOT_NTSC_PRE       { BOT_NTSC_PRE       = 36 }
!ifndef BOT_NTSC_LOOP      { BOT_NTSC_LOOP      = 45 }

!ifndef TOP_OLDNTSC_CMP    { TOP_OLDNTSC_CMP    = 14 }
!ifndef TOP_OLDNTSC_PRE    { TOP_OLDNTSC_PRE    = 37 }
!ifndef TOP_OLDNTSC_LOOP   { TOP_OLDNTSC_LOOP   = 42 }
!ifndef TOP_OLDNTSC_SPLIT  { TOP_OLDNTSC_SPLIT  = 5 }
!ifndef BOT_OLDNTSC_CMP    { BOT_OLDNTSC_CMP    = 4 }
!ifndef BOT_OLDNTSC_SPLIT  { BOT_OLDNTSC_SPLIT  = 57 }
!ifndef BOT_OLDNTSC_PRE    { BOT_OLDNTSC_PRE    = 36 }
!ifndef BOT_OLDNTSC_LOOP   { BOT_OLDNTSC_LOOP   = 44 }

!ifndef TOP_DREAN_CMP      { TOP_DREAN_CMP      = 15 }
!ifndef TOP_DREAN_PRE      { TOP_DREAN_PRE      = 37 }
!ifndef TOP_DREAN_LOOP     { TOP_DREAN_LOOP     = 43 }
!ifndef TOP_DREAN_SPLIT    { TOP_DREAN_SPLIT    = 6 }
!ifndef BOT_DREAN_CMP      { BOT_DREAN_CMP      = 5 }
!ifndef BOT_DREAN_SPLIT    { BOT_DREAN_SPLIT    = 58 }
!ifndef BOT_DREAN_PRE      { BOT_DREAN_PRE      = 36 }
!ifndef BOT_DREAN_LOOP     { BOT_DREAN_LOOP     = 45 }

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

; open_sides - a subroutine that opens the side borders on several lines
; in a row. Call it with X = number of lines, Y = CSEL_38, A = CSEL_40,
; timed so that the first STY writes in the right cycle. .wait makes each
; pass of the loop take exactly one raster line (counting the cycles the
; sprite fetches steal). Put +same_page with the same .wait in front of it.
!macro open_sides .wait {
.line   sty VIC_CTRL2           ; 38 columns, just after X=335: the side
                                ; border stays open
        sta VIC_CTRL2           ; back to 40 columns
        +wait .wait
        dex
        bne .line
        rts
}

; same_page - a branch to another page takes one cycle longer, which would
; upset the timing. Goes in front of an open_sides routine (and its label):
; if the routine would cross into the next page, start it on the next page.
; The padding sits between routines, where it is never run.
!macro same_page .wait {
        !if .wait & 1 {
                !set .len = 12 + (.wait - 3) / 2        ; bytes in the routine
        } else {
                !set .len = 10 + .wait / 2
        }
        !if (<*) + .len > 256 {
                !align 255, 0
        }
}

; late_check - (debug builds) in irq_top_a / irq_bot_a, just after CLI,
; while they wait for the second IRQ: Y = the raster line they started
; on. Count the times one started a line late or more (late_irqs), with
; that line (late_line) and where the main program was (late_pc: below
; the A, X, Y that irq_entry saved and the flags the CPU saved; X = the
; stack pointer). Nothing in the main program may hold these IRQs up.
; Done here, after the second IRQ is set up, so it takes no time before.
!macro late_check .line {
        cpy #.line+1
        bcc .ok
        inc late_irqs
        sty late_line
        lda $0105,x
        sta late_pc
        lda $0106,x
        sta late_pc+1
.ok
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

        ldx system_type         ; pick the stable handlers for this system
        lda tab_border_top_lo,x
        sta border_top_vec
        lda tab_border_top_hi,x
        sta border_top_vec+1
        lda tab_border_bot_lo,x
        sta border_bot_vec
        lda tab_border_bot_hi,x
        sta border_bot_vec+1

        +next_irq FRAME_TOP_LINE, irq_frame_top
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
; irq_entry - where the CPU goes on an IRQ while the KERNAL ROM is switched
; out (the vector at $fffe points here). It is the KERNAL's own entry code
; from $FF48, instruction for instruction, so it takes exactly as many
; cycles: the stable raster timing is the same as through the KERNAL.
; While the KERNAL ROM is in (disk work), the CPU uses the ROM's entry.
;----------------------------------------------------------------------------
!if (<*) > 256 - 19 {           ; keep all 19 bytes in one page, so the BEQ
        !align 255, 0           ; never takes the extra page-cross cycle
}
irq_entry
        pha                     ; save A, X and Y
        txa
        pha
        tya
        pha
        tsx
        lda $0104,x             ; the status the CPU pushed: its B flag
        and #$10                ; is set for a BRK instruction
        beq +
        jmp (BRK_VECTOR)        ; (we never use BRK)
+       jmp (IRQ_VECTOR)        ; the handler for this raster line

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
; Top of the frame - line 10, before any sprite starts
;============================================================================
!zone irq_frame_top
irq_frame_top
        lda #$ff
        sta VIC_IRQ_FLAGS
        jsr mouse_sample        ; the first of three mouse readings a frame

        ; The mouse pointer and the icon colors, as mouse_frame (input.asm)
        ; worked them out last frame. Put into the VIC here, above the text
        ; area, so the pointer never changes while it is being drawn.
        lda ptr_next_x
        sta VIC_SPR0_X
        lda ptr_next_y
        sta VIC_SPR0_Y
        lda ptr_next_msb
        sta VIC_SPR_XMSB
        lda ptr_next_block
        sta SPRITE_PTRS
        ldx #4
-       lda icon_colors,x       ; sprites 1-5
        sta VIC_SPR0_COLOR+1,x
        dex
        bpl -
        ldx text_bg             ; the pointer: red, or black on backgrounds
        lda pointer_colors,x    ; where red hardly shows (data.asm)
        sta VIC_SPR0_COLOR

        lda ptr_next_on         ; the five icons back on, and the pointer
        ora #SPR_ON_ICONS       ; if it shows
        sta VIC_SPR_ENABLE
        and #SPR_ON_BOTTOM      ; (the same for after the top strip, less
        sta spr_bottom          ; its three sprites)
        +next_irq TOP_A_LINE, irq_top_a
        jmp irq_exit

spr_bottom      !byte 0         ; sprites on from the top strip down

;============================================================================
; Top strip: side borders open for the F3 badges, then the color split
;============================================================================

; irq_top_a - line 25: prepare the stable IRQ for line 27.
!zone irq_top_a
irq_top_a
!if DEBUG {
        ldy VIC_RASTER          ; (debug builds: the line now, for the late
}                               ; check further down)
        lda border_top_vec      ; second IRQ goes to border_top_pal/ntsc/...
        sta IRQ_VECTOR
        lda border_top_vec+1
        sta IRQ_VECTOR+1
        lda #TOP_STABLE_LINE
        sta VIC_RASTER
        lda #$ff                ; acknowledge this IRQ
        sta VIC_IRQ_FLAGS
        tsx                     ; remember the stack; the second IRQ
        stx saved_sp            ; will throw its own stack frame away
        cli                     ; let the second IRQ in ...
!if DEBUG {
        +late_check TOP_A_LINE
}
        !for .i, 1, 45 {        ; ... while we run NOPs (90 cycles, more
                nop             ; than enough to reach line 27)
        }
        jmp irq_missed          ; (only if this IRQ came too late)

; irq_missed - the end of a NOP wait above: the second IRQ never came.
; This one came too late - after line 27 (249) had begun - because the CPU
; was held up: an Ultimate's menu or its network memory access, a freezer
; cartridge, a debugger. Line 27's handler must then not run next frame:
; it would throw away a stack frame that is long gone (saved_sp) and crash.
; So the chain starts again at line 10 of the next frame; this frame has no
; strips (one frame of plain borders, no keyboard scan).
irq_missed
        +next_irq FRAME_TOP_LINE, irq_frame_top
!if DEBUG {
        inc missed_irqs
}
        jmp irq_exit

; The second handler, one copy per video system. Enters on line 27.
!macro border_top .cmp, .pre, .loop, .split {
        ldx saved_sp            ; drop the second IRQ's stack frame
        txs
        lda #TOP_STABLE_LINE
        +wait .cmp
        cmp VIC_RASTER          ; read at the very end of line 27
!ifdef SPLIT_TEST {
        +split_test MB_TEST_TOP
}
        beq +                   ; still line 27: 1 cycle extra
+       ldx #TOP_OPEN_LINES     ; from here on, exactly in step with the beam
        ldy #CSEL_38
        lda #CSEL_40
        +wait .pre
        jsr .open               ; open the side borders on lines 28-49

        ; Color split at the end of line 50
        ldx irq_color51         ; side border color from line 51
        ldy text_bg
        +wait .split
        sty VIC_BG0             ; line 50, right border
        stx VIC_BORDER          ; blanking
        jmp border_top_done

        +same_page .loop
.open   +open_sides .loop
}

; (The four copies, border_top_pal ... border_top_drean, are made with
; border_bot's in startup.asm: only this system's copy is kept, at
; border_code.)

border_top_done
        lda #$ff                ; acknowledge the IRQ
        sta VIC_IRQ_FLAGS
        jsr top_next            ; next: marker top, marker bottom, or the
                                ; bottom strip, whichever comes first

; Housekeeping, while the beam draws the text area. The exact timing work
; of this frame is done, so let the next IRQs (the page marker) interrupt
; us from here on: they must not be late. This is the place for the jobs
; that take a while - the keyboard scan now, the cursor blink in phase 3.
        cli
!if DEBUG {
        lda VIC_RASTER          ; where housekeeping starts (test harness)
        sta MB_HK_START
}
        ; The VIC compares sprite Y with the low 8 bits of the raster line,
        ; so on PAL (312 lines) the top badges and the menu icon would show
        ; a second time at lines 256+Y, low in the bottom border. Their last
        ; line is done now: switch them off until irq_frame_top.
        lda spr_bottom
        sta VIC_SPR_ENABLE

        jsr mouse_frame         ; the mouse first: the SID has been reading
                                ; port 1 since the last keyboard scan
        jsr scan_keyboard
!if DEBUG {
        lda VIC_RASTER          ; and where it ends
        sta MB_HK_END
}
        jmp irq_exit

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
        jsr mark_top_next
        jmp irq_exit

irq_mark_bot_h
        lda #DARK_GREY
        sta VIC_BORDER
        lda #$ff
        sta VIC_IRQ_FLAGS
        +next_irq BOT_A_LINE, irq_bot_a
        jmp irq_exit

; top_next - set up the first IRQ after the top strip: the marker top if
; it has one, otherwise whatever comes after it.
top_next
        lda irq_mark_top
        beq mark_top_next
        sta VIC_RASTER
        lda #<irq_mark_top_h
        sta IRQ_VECTOR
        lda #>irq_mark_top_h
        sta IRQ_VECTOR+1
        rts

; mark_top_next - set up the IRQ after the marker top: the marker bottom
; if it has one, otherwise the bottom strip.
mark_top_next
        lda irq_mark_bot
        beq +
        sta VIC_RASTER
        lda #<irq_mark_bot_h
        sta IRQ_VECTOR
        lda #>irq_mark_bot_h
        sta IRQ_VECTOR+1
        rts
+       +next_irq BOT_A_LINE, irq_bot_a
        rts

;============================================================================
; Bottom strip: open the top/bottom border, color split, side borders open
; for the F5 badges, then housekeeping
;============================================================================

; irq_bot_a - line 247: prepare the stable IRQ for line 249.
!zone irq_bot_a
irq_bot_a
!if DEBUG {
        ldy VIC_RASTER          ; (debug builds: as in irq_top_a)
}
        lda border_bot_vec      ; second IRQ goes to border_bot_pal/ntsc/...
        sta IRQ_VECTOR
        lda border_bot_vec+1
        sta IRQ_VECTOR+1
        lda #BOT_STABLE_LINE
        sta VIC_RASTER
        lda #$ff
        sta VIC_IRQ_FLAGS
        tsx
        stx saved_sp
        cli
!if DEBUG {
        +late_check BOT_A_LINE
}
        !for .i, 1, 45 {
                nop
        }
        jmp irq_missed          ; (only if this IRQ came too late)

; The second handler, one copy per video system. Enters on line 249.
!macro border_bot .cmp, .split, .pre, .loop {
        ldx saved_sp            ; drop the second IRQ's stack frame
        txs
        lda #CTRL1_24ROWS       ; 24 rows: the border will not close
        sta VIC_CTRL1
        ldx #BLUE
        ldy #STRIP_BG
        lda #BOT_STABLE_LINE
        +wait .cmp
        cmp VIC_RASTER          ; read at the very end of line 249
!ifdef SPLIT_TEST {
        +split_test MB_TEST_BOT
}
        beq +                   ; still line 249: 1 cycle extra
+       +wait .split            ; on to the end of line 250
        sty VIC_BG0             ; right border (the text is finished)
        stx VIC_BORDER          ; blanking

        ldx #BOT_OPEN_LINES
        ldy #CSEL_38
        lda #CSEL_40
        +wait .pre
        jsr .open               ; open the side borders on lines 251-264
        jmp border_bot_done

        +same_page .loop
.open   +open_sides .loop
}

; (The four copies: in startup.asm, see border_top above.)

; End of the frame, below the bottom border check. Only short jobs here:
; on NTSC the side-border loop above ends around line 1 of the next frame,
; and the top strip IRQ comes at line 25. Longer jobs go in the
; housekeeping after the top strip (border_top_done).
border_bot_done
        lda #CTRL1_25ROWS       ; back to 25 rows for the next frame
        sta VIC_CTRL1
        lda #$ff
        sta VIC_IRQ_FLAGS

        inc frame_count         ; 16-bit frame counter
        bne +
        inc frame_count+1
+
        lda marker_pending      ; new marker position from the main loop?
        beq +
        jsr marker_apply
+       +next_irq FRAME_TOP_LINE, irq_frame_top
        jsr mouse_sample        ; the third mouse reading of the frame (on
                                ; NTSC this can end near line 10: the IRQ
                                ; for line 10 is set already, and then just
                                ; comes a little late - it has until 25)
!if DEBUG {
        lda frame_count         ; let the test harness see that we run
        sta MB_FRAMES
        lda frame_count+1
        sta MB_FRAMES+1
        lda VIC_RASTER          ; and where this ends: on NTSC it must stay
        sta MB_BOT_END          ; well before line 25 (the top strip IRQ)
}
        jmp irq_exit

;----------------------------------------------------------------------------
; IRQ variables
;----------------------------------------------------------------------------
saved_sp        !byte 0         ; stack pointer saved by the first IRQ
!if DEBUG {
late_irqs       !byte 0         ; (debug) line 25/247 IRQs that came late
missed_irqs     !byte 0         ; (debug) ... so late the strip was left out
late_line       !byte 0         ; (debug) the line the last late one began
late_pc         !word 0         ; (debug) and where the main program was
}
border_top_vec  !word 0         ; second-IRQ handlers for this system
border_bot_vec  !word 0
frame_count     !word 0

; Marker values used by the IRQs (0 = no IRQ needed)
irq_color51     !byte DARK_GREY ; side color from line 51 (grey if the
                                ; marker starts at the top)
irq_mark_top    !byte 0         ; line where the side turns grey
irq_mark_bot    !byte 0         ; line where it turns back to dark grey

;============================================================================
; Page position marker math
;
; Call marker_set with mk_first = where the screen starts in the document,
; mk_last = where it ends, and mk_total = the size of the whole document,
; all in the same unit (the editor uses bytes: see update_marker). It
; works out the band of side border lines:
;   top    = 51 + 200 * first / total
;   bottom = 51 + 200 * last / total, but at least 8 lines below the top
; and hands the result to the housekeeping IRQ, which switches over
; between frames so the IRQ chain never sees half-updated values.
; When all of the document is on the screen, the band is the whole side.
;============================================================================
mk_first        !word 0
mk_last         !word 0
mk_total        !word 0
band_top        !byte 0         ; first grey line
band_bot        !byte 0         ; first dark grey line after the band

new_color51     !byte 0         ; waiting for the housekeeping IRQ
new_mark_top    !byte 0
new_mark_bot    !byte 0
marker_pending  !byte 0

!zone marker_set
marker_set
        lda #51                 ; an empty document: all of it is visible
        sta band_top
        lda #251
        sta band_bot
        lda mk_total
        ora mk_total+1
        beq .place
        lda mk_first            ; top
        ldx mk_first+1
        jsr .line
        sta band_top
        lda mk_last             ; bottom
        ldx mk_last+1
        jsr .line
        sta band_bot
        sec                     ; at least 8 lines tall
        sbc band_top
        bcc +                   ; (bad input: bottom above top)
        cmp #8
        bcs .place
+       lda band_top
        clc
        adc #8
        sta band_bot
        cmp #252
        bcc .place
        lda #251                ; no further than the end of the text area
        sta band_bot
        lda #251-8
        sta band_top

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
+       ldy band_bot
        cpy #MARK_MAX_LINE+1
        bcc +
        ldy #0                  ; no marker-bottom IRQ
+       pha                     ; Hand over all three values together:
        lda #0                  ; the bottom IRQ takes them only when
        sta marker_pending      ; marker_pending is set, so clear it while
        pla                     ; they change. (Not with IRQs held off:
        stx new_color51         ; that could make the line 25 IRQ late.)
        sta new_mark_top
        sty new_mark_bot
        lda #1
        sta marker_pending
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

; .line - A/X = a position (low/high byte). Returns A = the raster line
; 51 + 200 * position / mk_total (at most 251).
.line   sta math_num
        stx math_num+1
        lda #200
        sta math_mul
        jsr mul_16x8
        lda mk_total
        sta math_div
        lda mk_total+1
        sta math_div+1
        jsr div_24x16
        lda math_num+2          ; the result is at most 200 when position
        ora math_num+1          ; <= total; pin anything bigger at 200
        bne .pin
        lda math_num
        cmp #201
        bcc +
.pin    lda #200
+       clc
        adc #51
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

;============================================================================
; Border sprites
;
; Sprite blocks live at $3e80-$3fff (blocks 250-255), in VIC bank 0.
; $3fff must stay $00: the VIC draws that byte in the opened borders.
;
; A sprite's first row appears on raster line Y+1, and the VIC always
; fetches all 21 rows of a sprite, even blank ones. Those fetches steal CPU
; cycles at the end of each line. To keep the timing the same on every
; line of the top strip, the top badges and the menu icon share the same
; 21 fetched lines (29-49): their pictures sit near the BOTTOM of their
; blocks. Nothing is fetched at the line 50 -> 51 split.
;
; The badges sit in the side borders, touching the text area sideways.
; Opening the side border on line 50 would also open the left border of
; line 51 (the first text line), so the top badges end on line 49 and the
; bottom badges start on line 252: one blank line from the text area.
;============================================================================
SPRITE_BASE     = $3e80
SPR_BLOCK_PTR   = 250           ; mouse pointer
SPR_BLOCK_MENU  = 251           ; "=F1" menu icon
SPR_BLOCK_F3    = 252           ; F3 badge (sprites 2 and 3)
SPR_BLOCK_F5    = 253           ; F5 badge (sprites 4 and 5)
SPR_BLOCK_PTR_LOW = 254         ; mouse pointer, low in its block

SPR_TOP_Y       = 29 - 1        ; F3 badges and menu icon: blocks on lines
                                ; 29-49; F3 picture (rows 12-20) on 41-49,
                                ; menu picture (rows 12-20) on 41-49
SPR_BOT_Y       = 252 - 1       ; F5 badges: picture (rows 0-8) on 252-260
SPR_ON_ICONS    = %00111110     ; sprites 1-5 (the pointer, 0, only when
                                ; it shows: see irq_frame_top)
SPR_ON_BOTTOM   = %00110001     ; pointer and F5 badges only (see border_top_done)
SPR_LEFT_X      = 2             ; left border: the badge's widest row ends
                                ; at X=23, touching the text area (X=24)
SPR_RIGHT_X     = 342           ; right border: the widest row starts at
                                ; X=344, touching the text area; needs X bit 8
SPR_MENU_X      = 32            ; 8 pixels in from the text area's left edge

