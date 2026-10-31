;============================================================================
; find.asm - CTRL-F: find text in the document
;
; A "FIND:" box asks for the text, with the last one filled in (so CTRL-F
; then RETURN finds the next). The search starts at the cursor - or just
; past the start of the marked text, which is usually the last match -
; runs to the end of the document, then goes on once from the top. A match
; is marked, with the cursor at its end, and brought onto the screen.
;
; Only visible characters are compared: color, reverse and other codes in
; the text are stepped over, so a word with a color change inside it still
; matches. Capitals and small letters count as the same. A match cannot
; run over a line end (the search text cannot hold one).
;
; Runs with the KERNAL ROM switched out (it uses the editor), and lives
; with the editor under the KERNAL ROM (moved there in phase 11 to make
; room in the lower part: it never runs during disk work). CTRL-R (Find
; and Replace, replace.asm) uses this search too, and find_key is there.
;============================================================================
; (find_key, find_buf, find_len, find_from, find_wrapped and FIND_MAX are
; in replace.asm)

; ask_text - a box asking for the search text (Y = 0) or the replacement
; (Y = 1), with the last one filled in. A/X = the question. Carry set if
; cancelled.
!zone ask_text
ask_text
        sty .which
        pha
        txa
        pha
        lda find_len,y
        sta input_len
        lda .offs,y             ; Y = where its text is (after find_buf)
        tay
        ldx #0
-       lda find_buf,y
        sta input_buf,x
        iny
        inx
        cpx #FIND_MAX
        bcc -
        stx input_max
        pla
        tax
        pla
        jsr prompt_input
        bcs .ret
        ldy .which              ; keep it for next time
        lda input_len
        sta find_len,y
        lda .offs,y
        tay
        ldx #0
-       lda input_buf,x
        sta find_buf,y
        iny
        inx
        cpx #FIND_MAX
        bcc -
        clc
.ret    rts
.offs   !byte 0, FIND_MAX
.which  !byte 0

; find_start - search from the cursor - or just past the start of the
; marked text, which is usually the last match - and go round once. While
; CTRL-R goes on (find_cont): from the cursor, round to where it began.
!zone find_start
find_start
        jsr leave_cursor        ; (tidy the codes here before offsets count)
        jsr get_cursor_off      ; where to start: the cursor ...
        lda work
        sta off
        lda work+1
        sta off+1
        lda find_cont
        bne .go
        lda sel_on              ; ... or just past the start of the marked
        beq +                   ; text (the last match, usually)
        jsr sel_range
        clc
        lda sel_s
        adc #1
        sta off
        lda sel_s+1
        adc #0
        sta off+1
+       lda off                 ; this is where it began
        sta find_from
        lda off+1
        sta find_from+1
        lda reu_docs            ; (a long document: where that is in all
        beq +                   ; of it)
        jsr rd_find_start
+       lda #0
        sta find_wrapped
; find_at - search from offset off (CTRL-R: from the top)
find_at
.go     jsr set_ptr
        jmp find_search

; find_search - search from ptr (set_ptr done). find_start (replace.asm)
; asks nothing: it sets find_from, find_wrapped (and rd_from with a long
; document) and ptr, then comes here. Finds the next match and marks it, or
; says "NOT FOUND" (not while CTRL-R goes on: find_cont).
!zone find_search
find_search
.try    ; Does the text match at ptr? First step over codes to the next
        ; visible byte: a match starts there.
        ldx #ptr
        jsr find_skip
        bcc +
        jmp .at_end
+       lda ptr                 ; after wrapping round: stop on reaching
        sta .start              ; where the search began
        lda ptr+1
        sta .start+1
        lda find_wrapped
        beq +
        jsr ptr_to_off
        jsr .past
        bcc +
        jmp .none
+       lda ptr                 ; ptr2 walks along the text, comparing
        sta ptr2
        lda ptr+1
        sta ptr2+1
        ldy #0
        sty .i
-       ldx #ptr2
        jsr find_next           ; the next visible byte of the text
        bcs .cmp_end            ; (the end of the text)
        jsr find_fold
        sta .t
        ldy .i
        lda find_buf,y
        jsr find_fold
        cmp .t
        bne .no_match
        inc .i
        lda .i
        cmp find_len
        bcc -
        jmp .found

.no_match
        lda .start              ; on to the next visible byte
        sta ptr
        lda .start+1
        sta ptr+1
        ldx #ptr
        jsr find_next
        jmp .try
.cmp_end                        ; the text ends before the match could:
        lda .start              ; with a long document, more may come
        sta ptr
        lda .start+1
        sta ptr+1
        jsr .more
        bcc .try_off
        lda ptr                 ; (it may have moved all the same)
        sta .start
        lda ptr+1
        sta .start+1
        jmp .no_match
.at_end jsr .more               ; (a long document: more may come)
        bcc .try_off
        lda find_wrapped        ; the end of the text: once round from the
        bne .none               ; top
        inc find_wrapped
        lda reu_docs            ; (a long document: its start)
        beq +
        jsr reu_to_start
        inc rd_slid
+       lda #<BUF_START
        sta ptr
        lda #>BUF_START
        sta ptr+1
        jmp .try
.try_off
        jsr set_ptr
        jmp .try
.none   jsr .slid               ; (a long document's window moved: the
        beq +                   ; cursor back)
        jsr rd_find_back
+       lda find_cont           ; (CTRL-R going on: it counts instead)
        bne .ret
        lda #<msg_not_found
        ldx #>msg_not_found
        jmp message_box

; .more - a long document, the window's end reached with ptr: the window
; moves on (ptr to the same place). Carry set if nothing more came.
.more   lda reu_docs
        bne +
        sec
        rts
+       jsr ptr_to_off
        jsr rd_slide
        php
        jsr set_ptr
        plp
.ret    rts

; .past - carry set if off is at or past where the search began
.past   lda reu_docs
        beq +
        jmp rd_past_from
+       lda off
        cmp find_from
        lda off+1
        sbc find_from+1
        rts

; .slid - Z clear if a long document's window moved during the search
.slid   lda reu_docs
        beq +
        lda rd_slid
+       rts

.found  ; Mark it: from .start to ptr2 (just after its last byte), the
        ; cursor at its end.
        lda .start
        sta ptr
        lda .start+1
        sta ptr+1
        jsr ptr_to_off
        lda off
        sta sel_anchor
        sta sel_anchor_end
        lda off+1
        sta sel_anchor+1
        sta sel_anchor_end+1
        lda ptr2
        sta ptr
        lda ptr2+1
        sta ptr+1
        jsr ptr_to_off
        jsr move_gap_to
        lda #1
        sta sel_on
        lda replace_all         ; (CTRL-R replacing all: drawn at the end)
        bne .ret
        jsr .slid               ; (the window moved: all of it again)
        bne +
        jsr locate_cursor       ; on the screen: just draw it marked
        bcs +
        jsr redraw_all
        jsr locate_cursor
        jmp set_want_col
+       ldx #ROWS/2             ; elsewhere: it goes in the middle
        jmp show_cursor_at

.start  !word 0
.i      !byte 0
.t      !byte 0

;----------------------------------------------------------------------------
; Walking the text for Find. X = the zero page address of a pointer (ptr
; or ptr2) into the text; it may be at the gap, which is jumped. (The
; 6502's (zp,X) addressing reads through the pointer X names.)
;----------------------------------------------------------------------------

; find_skip - move the pointer on over codes, to the next visible byte
; (not past it). Carry set at the end of the text.
!zone find_skip
find_skip
-       jsr find_gap
        bcs .end
        lda ($00,x)
        tay
        lda ctype,y
        cmp #CT_CHAR
        beq .ok
        cmp #CT_EOL
        beq .ok
        jsr find_inc
        jmp -
.ok     clc
.end    rts

; find_next - A = the next visible byte, the pointer past it. Carry set at
; the end of the text.
find_next
        jsr find_skip
        bcs +
        lda ($00,x)
        pha
        jsr find_inc
        pla
        clc
+       rts

; find_gap - jump the pointer over the gap if it is there; carry set if
; it is at the end of the text
find_gap
        lda $00,x
        cmp gap_start
        bne +
        lda $01,x
        cmp gap_start+1
        bne +
        lda gap_end
        sta $00,x
        lda gap_end+1
        sta $01,x
+       lda $01,x
        cmp text_end+1
        bne +
        lda $00,x
        cmp text_end
+       rts

; find_inc - the pointer on by one
find_inc
        inc $00,x
        bne +
        inc $01,x
+       rts

; find_fold - A = a byte: capitals and small letters made the same
; ($c1-$da and $61-$7a become $41-$5a)
!zone find_fold
find_fold
        cmp #$c1
        bcc +
        cmp #$db
        bcs +
        and #$7f                ; $c1-$da -> $41-$5a
        rts
+       cmp #$61
        bcc +
        cmp #$7b
        bcs +
        and #$df                ; $61-$7a -> $41-$5a
+       rts
