;============================================================================
; system.asm - video system detection, timing tables, math helpers
; (REU detection and DMA come here in phase 9.)
;============================================================================

; system_type values
SYS_PAL         = 0             ; 312 lines x 63 cycles
SYS_NTSC        = 1             ; 263 lines x 65 cycles
SYS_OLD_NTSC    = 2             ; 262 lines x 64 cycles
SYS_DREAN       = 3             ; PAL-N: 312 lines x 65 cycles

;----------------------------------------------------------------------------
; detect_system - find out which video system this machine has.
;
; First find the highest raster line: wait for $D012 to change, and stop
; when the new value is lower than the old one (the frame wrapped to line 0).
; The low byte of the last line tells us:
;   $37 = line 311 (PAL or Drean), $06 = line 262 (NTSC), $05 = 261 (old NTSC)
;
; PAL and Drean both have 312 lines, but Drean lines are 65 cycles long
; instead of 63, so we time one whole frame with CIA1 timer B:
;   PAL 312*63 = 19656 cycles, Drean 312*65 = 20280 cycles.
;
; Call with interrupts off. Sets system_type.
;----------------------------------------------------------------------------
!zone detect_system
detect_system
-       lda VIC_RASTER
--      cmp VIC_RASTER          ; wait for the line to change
        beq --
        bmi -                   ; new line is higher: keep going
                                ; (the 255->256 step also lands here, since
                                ; $ff - $00 is negative as a signed byte)
        ldx #SYS_NTSC
        cmp #$06
        beq .found
        ldx #SYS_OLD_NTSC
        cmp #$05
        beq .found

        ; 312 lines: PAL or Drean? Time one frame.
        jsr wait_line0
        lda #$ff                ; timer B counts down from $ffff
        sta CIA1_TBLO
        sta CIA1_TBHI
        lda #%00010001          ; force load, start, count CPU cycles
        sta CIA1_CRB
        jsr wait_line0
        lda #%00000000          ; stop the timer so we can read it safely
        sta CIA1_CRB
        lda CIA1_TBHI           ; cycles used = $ffff - timer, so the
        eor #$ff                ; high byte of the count is (timer hi EOR $ff)
        ldx #SYS_PAL            ; PAL gives $4c, Drean gives $4f
        cmp #$4e
        bcc .found
        ldx #SYS_DREAN
.found  stx system_type
        rts

; wait_line0 - wait for the start of raster line 0.
; (Line 256 also reads 0 in $D012, so check bit 7 of $D011 as well.)
wait_line0
-       lda VIC_RASTER          ; first get off line 0 / 256
        beq -
--      lda VIC_RASTER          ; then wait for it to come round again
        bne --
        lda VIC_CTRL1
        bmi -                   ; that was line 256, not line 0
        rts

system_type     !byte 0

;----------------------------------------------------------------------------
; Timing tables, one entry per system_type: PAL, NTSC, old NTSC, Drean
;----------------------------------------------------------------------------
tab_cycles_per_line
        !byte 63, 65, 64, 65

; Cursor blink: about 1/3 second (the KERNAL's rate). Used in phase 3.
tab_blink_frames
        !byte 17, 20, 20, 17

; Key repeat: 1/300 second steps per frame (see REPEAT_DELAY in input.asm).
; 300 / 50 frames per second = 6, 300 / 60 = 5.
tab_repeat_step
        !byte 6, 5, 5, 6

; Mouse: the pointer hides after 10 seconds without mouse use (frames).
tab_mouse_idle_lo
        !byte <500, <600, <600, <500
tab_mouse_idle_hi
        !byte >500, >600, >600, >500

; Mouse acceleration: a move of at least this many steps in one frame
; counts double (fast moves cross the screen quicker). A frame is shorter
; on NTSC, so the same hand speed gives fewer steps per frame there.
tab_mouse_accel
        !byte 4, 3, 3, 4

; Stable raster handlers for the top and bottom strips (see irq.asm).
tab_border_top_lo
        !byte <border_top_pal, <border_top_ntsc, <border_top_oldntsc, <border_top_drean
tab_border_top_hi
        !byte >border_top_pal, >border_top_ntsc, >border_top_oldntsc, >border_top_drean
tab_border_bot_lo
        !byte <border_bot_pal, <border_bot_ntsc, <border_bot_oldntsc, <border_bot_drean
tab_border_bot_hi
        !byte >border_bot_pal, >border_bot_ntsc, >border_bot_oldntsc, >border_bot_drean

;----------------------------------------------------------------------------
; Math helpers
;----------------------------------------------------------------------------
math_num        !byte 0,0,0     ; 24-bit number / dividend / quotient
math_div        !byte 0,0       ; 16-bit divisor
math_rem        !byte 0,0,0     ; 24-bit remainder
math_add        !byte 0,0,0     ; work value for mul_16x8
math_mul        !byte 0         ; 8-bit multiplier for mul_16x8

;----------------------------------------------------------------------------
; mul_16x8 - math_num (24 bit) = math_num (low 16 bits) * math_mul
; Shift-and-add: for each bit of the multiplier, add the shifted number.
;----------------------------------------------------------------------------
!zone mul_16x8
mul_16x8
        lda math_num            ; move the 16-bit number to the work value
        sta math_add
        lda math_num+1
        sta math_add+1
        lda #0
        sta math_add+2
        sta math_num            ; and clear the result
        sta math_num+1
        sta math_num+2
        ldx #8
.mul_loop
        lsr math_mul            ; next multiplier bit into carry
        bcc .mul_skip
        clc                     ; bit set: add the work value
        lda math_num
        adc math_add
        sta math_num
        lda math_num+1
        adc math_add+1
        sta math_num+1
        lda math_num+2
        adc math_add+2
        sta math_num+2
.mul_skip
        asl math_add            ; work value times 2
        rol math_add+1
        rol math_add+2
        dex
        bne .mul_loop
        rts

;----------------------------------------------------------------------------
; div_24x16 - math_num = math_num / math_div, remainder in math_rem.
; Long division, one bit at a time. math_div must not be 0.
;----------------------------------------------------------------------------
!zone div_24x16
div_24x16
        lda #0
        sta math_rem
        sta math_rem+1
        sta math_rem+2
        ldx #24
.div_loop
        asl math_num            ; shift the next dividend bit ...
        rol math_num+1
        rol math_num+2
        rol math_rem            ; ... into the remainder
        rol math_rem+1
        rol math_rem+2
        sec                     ; does the divisor fit?
        lda math_rem
        sbc math_div
        tay
        lda math_rem+1
        sbc math_div+1
        sta math_add            ; (math_add used as scratch here)
        lda math_rem+2
        sbc #0
        bcc .div_next           ; no: quotient bit stays 0
        sta math_rem+2          ; yes: keep the subtraction ...
        lda math_add
        sta math_rem+1
        sty math_rem
        inc math_num            ; ... and set the quotient bit
.div_next
        dex
        bne .div_loop
        rts
