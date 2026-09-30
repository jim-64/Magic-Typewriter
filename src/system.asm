;============================================================================
; system.asm - video system detection, timing tables, math helpers
; (The REU has its own file: reu.asm.)
;============================================================================

; system_type values
SYS_PAL         = 0             ; 312 lines x 63 cycles
SYS_NTSC        = 1             ; 263 lines x 65 cycles
SYS_OLD_NTSC    = 2             ; 262 lines x 64 cycles
SYS_DREAN       = 3             ; PAL-N: 312 lines x 65 cycles

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
