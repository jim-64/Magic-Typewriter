;============================================================================
; input.asm - keyboard matrix scanner, 1351 mouse, debug test mailbox
; (The scanner comes in phase 2 and the mouse in phase 7.)
;============================================================================

!if DEBUG {
;============================================================================
; Debug test mailbox (DEBUG=1 builds only)
;
; A fixed block of RAM that the test harness (Claude, through VICE's
; monitor) reads and writes while the editor runs. It sits in $02c0-$02ef,
; which the KERNAL and BASIC never use.
;
; Offset  Size  Who writes  What
;  +0      4    program     signature "MTDB" (ASCII) = mailbox is ready
;  +4      2    program     frame counter (lo/hi), +1 every frame
;  +6      1    program     system type: 0 PAL, 1 NTSC, 2 old NTSC, 3 Drean
;  +7      1    program     load device ($BA at start-up)
;  +8      2    harness     marker test: first visible line (lo/hi)
;  +10     2    harness     marker test: total lines (lo/hi)
;  +12     1    harness     write 1 to apply +8/+10; program sets it to 0
;  +13     1    program     marker result: first grey raster line
;  +14     1    program     marker result: first dark grey line after it
;  +15     1    -           spare
;  +16     1    harness     key queue head (next slot the harness fills)
;  +17     1    program     key queue tail (next slot the program reads)
;  +18    16    harness     key queue: 8 events of 2 bytes
;                             byte 0: matrix position = column * 8 + row bit
;                                     (column 0-7 is the $DC00 line pulled
;                                     low, row bit 0-7 is the $DC01 bit)
;                             byte 1: modifiers: bit 0 left SHIFT,
;                                     bit 1 right SHIFT, bit 2 CTRL, bit 3 C=
;  +34     1    harness     mouse queue head
;  +35     1    program     mouse queue tail
;  +36    12    harness     mouse queue: 4 events of 3 bytes
;                             dx (signed), dy (signed),
;                             buttons (bit 0 left, bit 1 right)
;  +48     4    program     SPLIT_TEST builds: top split early/late,
;                           bottom split early/late (1 = has happened)
;
; Queues: the harness writes an event at slot "head", then moves head on
; by one (wrapping 7 -> 0 for keys, 3 -> 0 for the mouse). The queue is
; empty when head = tail. The keyboard scanner and mouse driver will take
; events from here before looking at the hardware (phases 2 and 7).
;============================================================================
MB_BASE         = $02c0
MB_SIG          = MB_BASE+0
MB_FRAMES       = MB_BASE+4
MB_SYSTEM       = MB_BASE+6
MB_LOADDEV      = MB_BASE+7
MB_MK_FIRST     = MB_BASE+8
MB_MK_TOTAL     = MB_BASE+10
MB_MK_GO        = MB_BASE+12
MB_MK_TOP       = MB_BASE+13
MB_MK_BOT       = MB_BASE+14
MB_KEY_HEAD     = MB_BASE+16
MB_KEY_TAIL     = MB_BASE+17
MB_KEY_QUEUE    = MB_BASE+18
MB_MOUSE_HEAD   = MB_BASE+34
MB_MOUSE_TAIL   = MB_BASE+35
MB_MOUSE_QUEUE  = MB_BASE+36
MB_TEST_TOP     = MB_BASE+48
MB_TEST_BOT     = MB_BASE+50
MB_SIZE         = 52

;----------------------------------------------------------------------------
; mailbox_init - clear the mailbox and fill in the program's fields.
;----------------------------------------------------------------------------
!zone mailbox_init
mailbox_init
        lda #0
        ldx #MB_SIZE-1
-       sta MB_BASE,x
        dex
        bpl -
        lda system_type
        sta MB_SYSTEM
        lda load_device
        sta MB_LOADDEV
        ldx #3                  ; signature last: now the harness may start
-       lda .signature,x
        sta MB_SIG,x
        dex
        bpl -
        rts

.signature
        !byte $4d, $54, $44, $42        ; "MTDB" in ASCII

;----------------------------------------------------------------------------
; mailbox_poll - called from the main loop. Handles the marker test.
;----------------------------------------------------------------------------
!zone mailbox_poll
mailbox_poll
!ifdef SPLIT_TEST {
        ; Show the four split test flags as blocks at the start of row 10:
        ; white = has happened, black = not (read from a screenshot).
        ldx #3
-       lda #$a0                ; reversed space = solid block
        sta SCREEN+10*40,x
        lda MB_TEST_TOP,x
        sta COLOR_RAM+10*40,x   ; 1 = white, 0 = black
        dex
        bpl -
        ; Vary the length of the main loop, so the IRQs interrupt it at
        ; every possible point (this makes every jitter case happen).
        inc .vary
        lda .vary
        and #15
        tax
-       dex
        bpl -
}
        lda MB_MK_GO
        beq +
        lda MB_MK_FIRST
        sta mk_first
        lda MB_MK_FIRST+1
        sta mk_first+1
        lda MB_MK_TOTAL
        sta mk_total
        lda MB_MK_TOTAL+1
        sta mk_total+1
        ora mk_total            ; total of 0 would divide by zero:
        beq .done               ; ignore it
        jsr marker_set
.done   lda #0
        sta MB_MK_GO
+       rts

!ifdef SPLIT_TEST {
.vary   !byte 0
}

}       ; end of !if DEBUG
