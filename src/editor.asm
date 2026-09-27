;============================================================================
; editor.asm - gap buffer, cursor, selection, clipboard, redraw, wrap
; (The editor itself comes in phase 3.)
;============================================================================

;----------------------------------------------------------------------------
; petscii_to_screen - A = PETSCII code, returns A = screen code (not
; reversed) and carry clear. For control codes, which print nothing,
; returns carry set.
;
;   PETSCII        screen code
;   $20-$3f   ->   $20-$3f    space, digits, punctuation
;   $40-$5f   ->   $00-$1f    @, letters, [ pound ] up-arrow left-arrow
;   $60-$7f   ->   $40-$5f    (same characters as $c0-$df)
;   $a0-$bf   ->   $60-$7f    C= graphics
;   $c0-$fe   ->   $40-$7e    SHIFT letters and graphics
;   $ff       ->   $5e        pi
;   $00-$1f, $80-$9f          control codes
;----------------------------------------------------------------------------
!zone petscii_to_screen
petscii_to_screen
        cmp #$20
        bcc .control
        cmp #$40
        bcc .same
        cmp #$60
        bcc .minus40
        cmp #$80
        bcc .minus20
        cmp #$a0
        bcc .control
        cmp #$c0
        bcc .minus40
        cmp #$ff
        beq .pi
        and #$7f                ; $c0-$fe -> $40-$7e
.same   clc
        rts
.minus40
        sec
        sbc #$40
        clc
        rts
.minus20
        sec
        sbc #$20
        clc
        rts
.pi     lda #$5e
        clc
        rts
.control
        sec
        rts
