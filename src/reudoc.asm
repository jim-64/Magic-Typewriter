;============================================================================
; reudoc.asm - long documents held in the REU (phase 11b)
;
; With an REU of 3 banks or more (reu_docs), a document may be much longer
; than main memory. The text buffer ($4000-$bfff then) is a window onto
; it, around the cursor; the rest lies in the REU, from bank 2 up, as a
; second gap buffer:
;
;   head   the text before the window, in chunks going up from bank 2.
;          Each chunk starts with a header: the REU address of the chunk
;          before it (3 bytes), its length (2), and the color in effect at
;          its start (1; $ff = the default text color). A chunk ends just
;          after a RETURN when it can, so the window starts at a line
;          start (reverse off), in the color win_color.
;   tail   the text after the window, down from the REU's end, in one
;          piece.
;
; The editor sees only the window: its offsets count from the window's
; start, which is the document's offset win_base. After every key,
; reu_keep moves the window when the cursor comes near one of its ends
; and there is more text beyond, or when the window gets too full: whole
; chunks go to or come from the head, pieces to or from the tail. Then the
; screen is drawn again around the cursor.
;
; Assembled to run at $c000 and copied there at start-up, only with such
; an REU (reudoc_install in reu.asm); without one, that RAM is part of the
; text buffer. This RAM is there whatever $01 is, so loading and saving
; use this code while the KERNAL ROM is in - but then the editor's
; routines at $e000 are out of reach (the moves here use reu_copy).
;
; Marked text must stay inside the window: a move that would cut it off is
; left out (so marking reaches a good way, but not without end).
;============================================================================
DOC_BANK        = 2             ; the document's REU banks: 2 and up
CHUNK_SIZE      = 12288         ; about the size of a window move
MARGIN          = 4096          ; text kept on each side of the cursor
MIN_GAP         = 8192          ; room kept in the window for typing
HDR             = 6             ; a head chunk's header
RD_PAGE         = $cb00         ; a page for reading the REU's text (the
                                ; last page before the work area at
                                ; $cc00; the code stays below it)

head_top        !byte 0, 0, DOC_BANK ; REU: where the next head chunk goes
last_chunk      !byte 0, 0, 0   ; REU: the last head chunk's header
win_base        !byte 0, 0, 0   ; the document offset of the window's start
tail_len        !byte 0, 0, 0   ; how long the tail is
reu_top         !byte 0, 0, 0   ; REU: its end (the tail ends there)

;----------------------------------------------------------------------------
; reudoc_reset - nothing in the REU: a new, empty document (or before a
; load)
;----------------------------------------------------------------------------
reudoc_reset
        lda #0
        sta head_top
        sta head_top+1
        sta win_base
        sta win_base+1
        sta win_base+2
        sta tail_len
        sta tail_len+1
        sta tail_len+2
        sta reu_top
        sta reu_top+1
        lda #DOC_BANK
        sta head_top+2
        lda reu_banks
        sta reu_top+2
        lda #$ff
        sta win_color
        rts

; head_empty - Z set if there is no head
head_empty
        lda head_top
        ora head_top+1
        bne +
        lda head_top+2
        cmp #DOC_BANK
+       rts

; tail_empty - Z set if there is no tail
tail_empty
        lda tail_len
        ora tail_len+1
        ora tail_len+2
        rts

;----------------------------------------------------------------------------
; The moves. Each keeps the gap buffer whole (gap_start, gap_end), so the
; cursor stays at its place in the text.
;----------------------------------------------------------------------------

; push_chunk - the window's first rd_len bytes (all before the gap) go to
; the end of the head, as a chunk. The rest of the window moves down.
!zone push_chunk
push_chunk
        ldx #2                  ; its header: the chunk before it, ...
-       lda last_chunk,x
        sta rd_hdr,x
        lda head_top,x          ; (this one becomes the last)
        sta last_chunk,x
        dex
        bpl -
        lda rd_len              ; ... its length, and the color at its
        sta rd_hdr+3            ; start
        lda rd_len+1
        sta rd_hdr+4
        lda win_color
        sta rd_hdr+5
        lda #<rd_hdr            ; the header to head_top ...
        ldx #>rd_hdr
        ldy #HDR
        jsr rd_stash_head
        lda #<BUF_START         ; ... then the text after it
        ldx #>BUF_START
        ldy #0
        jsr rd_stash_head_len
        ldy #0                  ; the color after it: its last color code,
        jsr last_color          ; if it has one
        clc                     ; win_base on by the length
        lda win_base
        adc rd_len
        sta win_base
        lda win_base+1
        adc rd_len+1
        sta win_base+1
        bcc +
        inc win_base+2
+       lda #<BUF_START         ; the rest of the window moves down:
        clc                     ; BUF_START + length up to gap_start
        adc rd_len
        sta ptr
        lda #>BUF_START
        adc rd_len+1
        sta ptr+1
        lda #<BUF_START
        sta ptr2
        lda #>BUF_START
        sta ptr2+1
        sec
        lda gap_start
        sbc ptr
        sta blk_count
        lda gap_start+1
        sbc ptr+1
        sta blk_count+1
        lda #0
        jsr reu_copy
        sec                     ; the gap starts that much lower
        lda gap_start
        sbc rd_len
        sta gap_start
        lda gap_start+1
        sbc rd_len+1
        sta gap_start+1
        rts

; pop_chunk - the head's last chunk comes back to the window's start
; (the caller has made the room: the gap at least its length, rd_len,
; from peek_chunk).
!zone pop_chunk
pop_chunk
        jsr peek_chunk          ; its header: rd_hdr, rd_len
        clc                     ; the text before the gap moves up
        lda gap_start
        sta ptr
        adc rd_len
        sta ptr2
        lda gap_start+1
        sta ptr+1
        adc rd_len+1
        sta ptr2+1
        sec
        lda gap_start
        sbc #<BUF_START
        sta blk_count
        lda gap_start+1
        sbc #>BUF_START
        sta blk_count+1
        lda #1
        jsr reu_copy
        clc
        lda gap_start
        adc rd_len
        sta gap_start
        lda gap_start+1
        adc rd_len+1
        sta gap_start+1
        clc                     ; the chunk's text (after its header) ...
        lda last_chunk
        adc #HDR
        sta reu_addr
        lda last_chunk+1
        adc #0
        sta reu_addr+1
        lda last_chunk+2
        adc #0
        sta reu_bank
        lda #<BUF_START         ; ... to the window's start
        sta reu_c64
        lda #>BUF_START
        sta reu_c64+1
        lda rd_len
        sta reu_len
        lda rd_len+1
        sta reu_len+1
        lda #REU_FETCH
        jsr reu_move
        ldx #2                  ; the head ends where it began
-       lda last_chunk,x
        sta head_top,x
        lda rd_hdr,x
        sta last_chunk,x
        dex
        bpl -
        sec                     ; win_base back by its length
        lda win_base
        sbc rd_len
        sta win_base
        lda win_base+1
        sbc rd_len+1
        sta win_base+1
        bcs +
        dec win_base+2
+       lda rd_hdr+5            ; and its color is the window's start color
        sta win_color
        rts

; peek_chunk - the head's last chunk's header into rd_hdr, its length
; into rd_len
peek_chunk
        ldx #2
-       lda last_chunk,x
        sta reu_addr,x          ; (reu_addr, then reu_bank after it)
        dex
        bpl -
        lda #<rd_hdr
        sta reu_c64
        lda #>rd_hdr
        sta reu_c64+1
        lda #HDR
        sta reu_len
        lda #0
        sta reu_len+1
        lda #REU_FETCH
        jsr reu_move
        lda rd_hdr+3
        sta rd_len
        lda rd_hdr+4
        sta rd_len+1
        rts

; tail_push - the window's last rd_len bytes (all after the gap) go to
; the front of the tail. The rest of the text after the gap moves up.
!zone tail_push
tail_push
        clc                     ; the tail gets longer
        lda tail_len
        adc rd_len
        sta tail_len
        lda tail_len+1
        adc rd_len+1
        sta tail_len+1
        bcc +
        inc tail_len+2
+       jsr tail_addr           ; its new front, in the REU
        sec                     ; the bytes: text_end - length up to it
        lda text_end
        sbc rd_len
        sta reu_c64
        sta ptr
        lda text_end+1
        sbc rd_len+1
        sta reu_c64+1
        sta ptr+1
        lda rd_len
        sta reu_len
        lda rd_len+1
        sta reu_len+1
        lda #REU_STASH
        jsr reu_move
        lda text_end            ; the rest after the gap moves up
        sta ptr2
        lda text_end+1
        sta ptr2+1
        sec
        lda ptr
        sbc gap_end
        sta blk_count
        lda ptr+1
        sbc gap_end+1
        sta blk_count+1
        lda #1
        jsr reu_copy
        clc
        lda gap_end
        adc rd_len
        sta gap_end
        lda gap_end+1
        adc rd_len+1
        sta gap_end+1
        rts

; tail_pop - the tail's first rd_len bytes come to the window's end (the
; caller has made the room: the gap at least that long)
!zone tail_pop
tail_pop
        lda gap_end             ; the text after the gap moves down
        sta ptr
        sec
        sbc rd_len
        sta ptr2
        lda gap_end+1
        sta ptr+1
        sbc rd_len+1
        sta ptr2+1
        sec
        lda text_end
        sbc gap_end
        sta blk_count
        lda text_end+1
        sbc gap_end+1
        sta blk_count+1
        lda #0
        jsr reu_copy
        sec
        lda gap_end
        sbc rd_len
        sta gap_end
        lda gap_end+1
        sbc rd_len+1
        sta gap_end+1
        jsr tail_addr           ; then the tail's front to the end
        sec
        lda text_end
        sbc rd_len
        sta reu_c64
        lda text_end+1
        sbc rd_len+1
        sta reu_c64+1
        lda rd_len
        sta reu_len
        lda rd_len+1
        sta reu_len+1
        lda #REU_FETCH
        jsr reu_move
        sec                     ; and the tail is shorter
        lda tail_len
        sbc rd_len
        sta tail_len
        lda tail_len+1
        sbc rd_len+1
        sta tail_len+1
        bcs +
        dec tail_len+2
+       rts

; tail_addr - reu_addr/reu_bank = the tail's front: reu_top - tail_len
tail_addr
        sec
        lda reu_top
        sbc tail_len
        sta reu_addr
        lda reu_top+1
        sbc tail_len+1
        sta reu_addr+1
        lda reu_top+2
        sbc tail_len+2
        sta reu_bank
        rts

; rd_stash_head - Y bytes (1-255; Y = 0 with rd_stash_head_len: rd_len
; bytes) from C64 address A/X to head_top, which moves on past them
rd_stash_head_len
        sta reu_c64
        stx reu_c64+1
        lda rd_len
        sta reu_len
        lda rd_len+1
        sta reu_len+1
        jmp +
rd_stash_head
        sta reu_c64
        stx reu_c64+1
        sty reu_len
        lda #0
        sta reu_len+1
+       ldx #2
-       lda head_top,x
        sta reu_addr,x          ; (reu_addr, then reu_bank after it)
        dex
        bpl -
        clc                     ; head_top on by the length
        lda head_top
        adc reu_len
        sta head_top
        lda head_top+1
        adc reu_len+1
        sta head_top+1
        bcc +
        inc head_top+2
+       lda #REU_STASH
        jmp reu_move

; last_color - the last color code in the window's first rd_len bytes,
; if any, becomes win_color
!zone last_color
last_color
        clc
        lda #<BUF_START
        adc rd_len
        sta ptr
        lda #>BUF_START
        adc rd_len+1
        sta ptr+1
-       lda ptr
        cmp #<BUF_START
        bne +
        lda ptr+1
        cmp #>BUF_START
        beq .none
+       lda ptr
        bne +
        dec ptr+1
+       dec ptr
        ldy #0
        lda (ptr),y
        tax
        lda ctype,x
        bmi -
        sta win_color
.none   rts

;----------------------------------------------------------------------------
; Choosing how much to move
;----------------------------------------------------------------------------

; push_len - rd_len = how much of the window's start may go to the head:
; up to CHUNK_SIZE, keeping MARGIN before the cursor (or, with A = 0, as
; much as there is before the gap - for loading), ending just after a
; RETURN when there is one. Carry set if nothing can go.
!zone push_len
push_len
        sta .keep
        sec                     ; the text before the gap, less the margin
        lda gap_start
        sbc #<BUF_START
        sta rd_len
        lda gap_start+1
        sbc #>BUF_START
        sta rd_len+1
        lda .keep
        beq +
        sec
        lda rd_len
        sbc #<MARGIN
        sta rd_len
        lda rd_len+1
        sbc #>MARGIN
        sta rd_len+1
        bcc .none
+       lda rd_len+1            ; at most CHUNK_SIZE
        cmp #>CHUNK_SIZE
        bcc +
        lda #<CHUNK_SIZE
        sta rd_len
        lda #>CHUNK_SIZE
        sta rd_len+1
+       lda rd_len
        ora rd_len+1
        beq .none
        clc                     ; back to just after the last RETURN in it
        lda #<BUF_START
        adc rd_len
        sta ptr
        lda #>BUF_START
        adc rd_len+1
        sta ptr+1
-       lda ptr
        cmp #<BUF_START
        bne +
        lda ptr+1
        cmp #>BUF_START
        beq .whole              ; no RETURN: the whole of it after all
+       lda ptr
        bne +
        dec ptr+1
+       dec ptr
        ldy #0
        lda (ptr),y
        tax
        lda ctype,x
        cmp #CT_EOL
        bne -
        sec                     ; up to just after it
        lda ptr
        sbc #<(BUF_START-1)
        sta rd_len
        lda ptr+1
        sbc #>(BUF_START-1)
        sta rd_len+1
.whole  clc
        rts
.none   sec
        rts
.keep   !byte 0

; reu_room - carry set if the REU has room for rd_len bytes more (and a
; chunk header): the head and the tail must not meet.
; reu_room_grow - the same, for a move that makes the document's REU part
; bigger (loading, room for typing): RESERVE more must stay free. Then a
; move that swaps text between the head and the tail (going back to the
; start, say) always finds room for its first half.
RESERVE         = CHUNK_SIZE + 2*HDR
!zone reu_room
reu_room_grow
        lda #<(HDR+RESERVE)
        ldx #>(HDR+RESERVE)
        bne +                   ; (always)
reu_room
        lda #HDR
        ldx #0
+       sta .x
        stx .x+1
        clc                     ; head_top + length + the extra
        lda head_top
        adc rd_len
        sta .t
        lda head_top+1
        adc rd_len+1
        sta .t+1
        lda head_top+2
        adc #0
        sta .t+2
        clc
        lda .t
        adc .x
        sta .t
        lda .t+1
        adc .x+1
        sta .t+1
        bcc +
        inc .t+2
+       jsr tail_addr           ; <= the tail's front?
        lda reu_addr
        cmp .t
        lda reu_addr+1
        sbc .t+1
        lda reu_bank
        sbc .t+2
        rts                     ; (carry set: the tail's front is not below)
.t      !byte 0, 0, 0
.x      !word 0

; rd_sizes - rd_before, rd_after, rd_gap: the text before and after the
; gap, and the gap, in the window
!zone rd_sizes
rd_sizes
        sec
        lda gap_start
        sbc #<BUF_START
        sta rd_before
        lda gap_start+1
        sbc #>BUF_START
        sta rd_before+1
        sec
        lda text_end
        sbc gap_end
        sta rd_after
        lda text_end+1
        sbc gap_end+1
        sta rd_after+1
        sec
        lda gap_end
        sbc gap_start
        sta rd_gap
        lda gap_end+1
        sbc gap_start+1
        sta rd_gap+1
        rts

;----------------------------------------------------------------------------
; reu_keep - after every key (main loop): move the window if the cursor is
; near one of its ends and there is more text beyond, or if the window is
; getting full. Then draw the screen again around the cursor.
; reu_room_for - the same, with room for A/X bytes (not just MIN_GAP) in
; the gap: for paste
;----------------------------------------------------------------------------
!zone reu_keep
reu_keep
        lda #<MIN_GAP
        ldx #>MIN_GAP
reu_room_for
        sta .want
        stx .want+1
        lda #0
        sta .moved
        lda #8                  ; (never more than a few moves at a time)
        sta .tries
.again  dec .tries
        bne +
        jmp .done
+       jsr rd_sizes
        ; 1. The text before the cursor: at least MARGIN, if the head has
        ;    more. Its last chunk comes back (after room is made for it,
        ;    and for MIN_GAP besides: else rule 3 would send it straight
        ;    back out).
        lda rd_before+1
        cmp #>MARGIN
        bcs .after
        jsr head_empty
        beq .after
        jsr peek_chunk
        clc                     ; room for it, and MIN_GAP?
        lda rd_len
        adc #<MIN_GAP
        sta .need
        lda rd_len+1
        adc #>MIN_GAP
        sta .need+1
        lda rd_gap
        cmp .need
        lda rd_gap+1
        sbc .need+1
        bcs .pop
        lda #0                  ; no: some of the end to the tail first
        jsr .to_tail            ; (then the chunk comes back: a swap)
        bcs .after              ; (none to spare)
        jmp .again
.pop    jsr pop_chunk
        inc .moved
        clc                     ; (marked text: its offsets move up with it)
        lda sel_anchor
        adc rd_len
        sta sel_anchor
        lda sel_anchor+1
        adc rd_len+1
        sta sel_anchor+1
        clc
        lda sel_anchor_end
        adc rd_len
        sta sel_anchor_end
        lda sel_anchor_end+1
        adc rd_len+1
        sta sel_anchor_end+1
        jmp .again

.after  ; 2. The text after the cursor: at least MARGIN, if the tail has
        ;    more. A piece of the tail comes back.
        lda rd_after+1
        cmp #>MARGIN
        bcs .room
        jsr tail_empty
        beq .room
        sec                     ; as much as the gap can spare, keeping
        lda rd_gap              ; MIN_GAP (so rule 3 has nothing to do) ...
        sbc #<MIN_GAP
        sta rd_len
        lda rd_gap+1
        sbc #>MIN_GAP
        sta rd_len+1
        bcc .push_first         ; (less than 1 KB: make room first)
        cmp #>1024
        bcc .push_first
        cmp #>CHUNK_SIZE        ; ... up to CHUNK_SIZE ...
        bcc +
        lda #<CHUNK_SIZE
        sta rd_len
        lda #>CHUNK_SIZE
        sta rd_len+1
+       lda tail_len+2          ; ... and no more than the tail has
        bne .tpop
        lda tail_len
        cmp rd_len
        lda tail_len+1
        sbc rd_len+1
        bcs .tpop
        lda tail_len
        sta rd_len
        lda tail_len+1
        sta rd_len+1
        jmp .tpop
.push_first
        lda #1                  ; no: some of the start to the head first
        jsr push_len            ; (then the tail's piece comes back: a swap)
        bcs .room
        jsr reu_room
        bcc .room
        jsr .push
        bcs .room
        jmp .again
.tpop   jsr tail_pop
        inc .moved
        jmp .again

.room   ; 3. Room for typing: the gap at least MIN_GAP (or what paste
        ;    wants). From the side with more text.
        lda rd_gap
        cmp .want
        lda rd_gap+1
        sbc .want+1
        bcs .done
        lda rd_before           ; more before the cursor than after?
        cmp rd_after
        lda rd_before+1
        sbc rd_after+1
        bcc .end_off
        lda #1
        jsr push_len
        bcs .end_off
        jsr reu_room_grow
        bcc .end_off
        jsr .push
        bcs .end_off
        jmp .again
.end_off
        lda #1                  ; (the REU part gets bigger)
        jsr .to_tail
        bcs .done
        inc .moved
        jmp .again

.done   lda .moved              ; moved: the editor's offsets count from the
        beq +                   ; window's start, so the screen is laid out
        jsr count_colors        ; again, the cursor on its row
        lda #0
        sta top_known
        ldx cur_row
        jmp show_cursor_at
+       rts

; .to_tail - up to CHUNK_SIZE of the window's end (keeping MARGIN after
; the cursor) to the tail. A = 1: it makes the REU part bigger (keep
; RESERVE free). Carry set if there is none to spare.
.to_tail
        sta .grow
        sec
        lda rd_after
        sbc #<MARGIN
        sta rd_len
        lda rd_after+1
        sbc #>MARGIN
        sta rd_len+1
        bcc .none
        ora rd_len
        beq .none
        lda rd_len+1
        cmp #>CHUNK_SIZE
        bcc +
        lda #<CHUNK_SIZE
        sta rd_len
        lda #>CHUNK_SIZE
        sta rd_len+1
+       lda sel_on              ; marked text: it must not reach into what
        beq .tt_room            ; goes (up to the window's text less that)
        clc
        lda rd_before
        adc rd_after
        tax
        lda rd_before+1
        adc rd_after+1
        tay
        txa
        sec
        sbc rd_len
        sta .lim
        tya
        sbc rd_len+1
        sta .lim+1
        lda .lim
        cmp sel_anchor
        lda .lim+1
        sbc sel_anchor+1
        bcc .none
        lda .lim
        cmp sel_anchor_end
        lda .lim+1
        sbc sel_anchor_end+1
        bcc .none
.tt_room
        lda .grow
        beq +
        jsr reu_room_grow
        jmp ++
+       jsr reu_room
++      bcc .none
        jsr tail_push
        inc .moved
        jsr rd_sizes
        clc
        rts
.none   sec
        rts

; .push - push_chunk, if marked text stays in the window (it starts at or
; after rd_len): then its offsets move down with it. Carry set if not.
.push   lda sel_on
        beq .push_go
        lda sel_anchor
        cmp rd_len
        lda sel_anchor+1
        sbc rd_len+1
        bcc .none
        lda sel_anchor_end
        cmp rd_len
        lda sel_anchor_end+1
        sbc rd_len+1
        bcc .none
        sec
        lda sel_anchor
        sbc rd_len
        sta sel_anchor
        lda sel_anchor+1
        sbc rd_len+1
        sta sel_anchor+1
        sec
        lda sel_anchor_end
        sbc rd_len
        sta sel_anchor_end
        lda sel_anchor_end+1
        sbc rd_len+1
        sta sel_anchor_end+1
.push_go
        jsr push_chunk
        inc .moved
        clc
        rts

.moved  !byte 0
.tries  !byte 0
.grow   !byte 0
.lim    !word 0
.need   !word 0
.want   !word 0

;----------------------------------------------------------------------------
; reu_to_end - the window to the end of the document (SHIFT + F5): the tail
; comes in a piece at a time, the window's start going to the head to make
; room for it. The cursor ends at the end. (reu_keep, after the key, then
; makes room for typing.)
;----------------------------------------------------------------------------
!zone reu_to_end
reu_to_end
-       jsr tail_empty
        beq .done
        jsr text_len            ; the gap to the window's end
        lda work
        sta off
        lda work+1
        sta off+1
        jsr move_gap_to
        jsr rd_sizes
        lda #<CHUNK_SIZE        ; up to CHUNK_SIZE of the tail
        sta rd_len
        lda #>CHUNK_SIZE
        sta rd_len+1
        lda tail_len+2
        bne +
        lda tail_len
        cmp #<CHUNK_SIZE
        lda tail_len+1
        sbc #>CHUNK_SIZE
        bcs +
        lda tail_len
        sta rd_len
        lda tail_len+1
        sta rd_len+1
+       lda rd_gap              ; room for it?
        cmp rd_len
        lda rd_gap+1
        sbc rd_len+1
        bcs .pop
        lda #0                  ; no: the window's start to the head first
        jsr push_len            ; (a swap: the REU part stays the same size)
        bcs .done
        jsr reu_room
        bcc .done
        jsr push_chunk
        jmp -
.pop    jsr tail_pop
        jmp -
.done   jsr count_colors        ; (the window's text is another now)
        lda #0
        sta top_known
        rts

;----------------------------------------------------------------------------
; reu_to_start - the window to the start of the document: every head chunk
; comes back, the window's end going to the tail to make room (after a
; load; also HOME at the top). The cursor ends at the start.
;----------------------------------------------------------------------------
!zone reu_to_start
reu_to_start
        lda #0                  ; the gap to the start (all the window's
        sta off                 ; text after it: its end can go to the
        sta off+1               ; tail)
        jsr move_gap_to
-       jsr head_empty
        beq .done
        jsr peek_chunk
        jsr rd_sizes
        lda rd_gap              ; room for the chunk?
        cmp rd_len
        lda rd_gap+1
        sbc rd_len+1
        bcs +
        lda rd_len              ; no: the window's end to the tail - as
        sec                     ; much as it takes (if the REU has room)
        sbc rd_gap
        sta rd_len
        lda rd_len+1
        sbc rd_gap+1
        sta rd_len+1
        jsr reu_room
        bcc .done
        jsr tail_push
        jmp -
+       jsr pop_chunk
        lda #0                  ; (and the gap back to the start)
        sta off
        sta off+1
        jsr move_gap_to
        jmp -
.done   jsr rd_sizes            ; then room for typing (if the REU has it)
        lda rd_gap+1
        cmp #>MIN_GAP
        bcs +
        sec
        lda #<MIN_GAP
        sbc rd_gap
        sta rd_len
        lda #>MIN_GAP
        sbc rd_gap+1
        sta rd_len+1
        jsr reu_room_grow
        bcc +
        jsr tail_push
+       jsr count_colors        ; (the window's text is another now)
        lda #0
        sta top_known
        rts

;----------------------------------------------------------------------------
; load_spill - loading, the window full (from load_file, between io_begin
; and io_end): what has come so far is made into text (convert_start /
; convert_more), and chunks of it go to the head until less than a chunk
; is left. Carry set if the REU has no room for more (the rest of the file
; is left off: "TOO LONG"). X is kept (the byte just read).
;----------------------------------------------------------------------------
!zone load_spill
load_spill
        stx .x
        lda conv_started
        bne +
        jsr convert_start
        jmp ++
+       jsr convert_more
++      lda ptr2                ; the text so far ends here ...
        sta gap_start
        sta conv_rd             ; (... and all of it is converted)
        sta conv_wr
        lda ptr2+1
        sta gap_start+1
        sta conv_rd+1
        sta conv_wr+1
.push   sec                     ; a chunk's worth left, or more?
        lda gap_start
        sbc #<(BUF_START+CHUNK_SIZE)
        lda gap_start+1
        sbc #>(BUF_START+CHUNK_SIZE)
        bcc .ok
        lda #0                  ; a chunk, to just after a RETURN
        jsr push_len
        jsr reu_room_grow
        bcc .no
        jsr push_chunk
        lda gap_start           ; (what is left moved down)
        sta conv_rd
        sta conv_wr
        lda gap_start+1
        sta conv_rd+1
        sta conv_wr+1
        jmp .push
.ok     clc                     ; room again (less than a chunk is left)
        ldx .x
        rts
.no     ldx .x                  ; (the window may still have some room, but
        sec                     ; the file is cut off here)
        rts
.x      !byte 0

;----------------------------------------------------------------------------
; The whole document in order (each_range in fileio.asm: saving, printing,
; Stats): the head and the tail come a page at a time through RD_PAGE.
;----------------------------------------------------------------------------

; each_head - the head's chunks, from the first (at the start of bank
; DOC_BANK) up to head_top. Carry set if range_call stopped.
!zone each_head
each_head
        lda #0
        sta rd_at
        sta rd_at+1
        lda #DOC_BANK
        sta rd_at+2
.chunk  lda rd_at               ; at head_top: that was all
        cmp head_top
        bne +
        lda rd_at+1
        cmp head_top+1
        bne +
        lda rd_at+2
        cmp head_top+2
        bne +
        clc
        rts
+       lda #HDR                ; its header: how long it is
        jsr rd_fetch
        lda RD_PAGE+3
        sta rd_left
        lda RD_PAGE+4
        sta rd_left+1
        lda #0
        sta rd_left+2
        jsr each_pages          ; then its text
        bcc .chunk
        rts

; each_tail - the tail, from its front to reu_top
each_tail
        jsr tail_addr
        ldx #2
-       lda reu_addr,x          ; (reu_addr, then reu_bank after it)
        sta rd_at,x
        lda tail_len,x
        sta rd_left,x
        dex
        bpl -
        ; (on into each_pages)

; each_pages - rd_left bytes (24 bits) from the REU at rd_at, a page at a
; time through RD_PAGE, to range_call. Carry set if it stopped.
!zone each_pages
each_pages
.page   lda rd_left
        ora rd_left+1
        ora rd_left+2
        bne +
        clc
        rts
+       lda rd_left+1           ; a page (A = 0), or what is left
        ora rd_left+2
        beq +
        lda #0
        beq ++
+       lda rd_left
++      sta .n
        jsr rd_fetch
        lda .n                  ; that much less left
        bne +
        lda rd_left+1           ; (a whole page)
        bne ++
        dec rd_left+2
++      dec rd_left+1
        jmp .go
+       sec
        lda rd_left
        sbc .n
        sta rd_left
        bcs .go
        lda rd_left+1
        bne +
        dec rd_left+2
+       dec rd_left+1
.go     lda #<RD_PAGE           ; the piece: RD_PAGE up to RD_PAGE + .n
        sta ptr
        lda #>RD_PAGE
        sta ptr+1
        lda .n
        sta range_end
        lda #>RD_PAGE
        ldx .n
        bne +
        lda #(>RD_PAGE)+1       ; (a whole page)
+       sta range_end+1
        jsr range_go
        bcc .page
        rts
.n      !byte 0

; rd_fetch - A bytes (0 = 256) from the REU at rd_at into RD_PAGE; rd_at
; moves on past them
rd_fetch
        sta reu_len
        ldx #0
        cmp #0
        bne +
        inx
+       stx reu_len+1
        lda #<RD_PAGE
        sta reu_c64
        lda #>RD_PAGE
        sta reu_c64+1
        ldx #2
-       lda rd_at,x
        sta reu_addr,x          ; (reu_addr, then reu_bank after it)
        dex
        bpl -
        clc
        lda rd_at
        adc reu_len
        sta rd_at
        lda rd_at+1
        adc reu_len+1
        sta rd_at+1
        bcc +
        inc rd_at+2
+       lda #REU_FETCH
        jmp reu_move

;----------------------------------------------------------------------------
; Stats for a long document (count_text, free_percent in menu.asm)
;----------------------------------------------------------------------------

; long_free - the room left: the REU's too (between the head and the tail,
; less RESERVE)
!zone long_free
long_free
        jsr tail_addr
        sec
        lda reu_addr
        sbc head_top
        sta .r
        lda reu_addr+1
        sbc head_top+1
        sta .r+1
        lda reu_bank
        sbc head_top+2
        sta .r+2
        sec
        lda .r
        sbc #<(RESERVE+HDR)
        sta .r
        lda .r+1
        sbc #>(RESERVE+HDR)
        sta .r+1
        lda .r+2
        sbc #0
        bcc +                   ; (none)
        sta .r+2
        clc
        lda st_counts+ST_FREE
        adc .r
        sta st_counts+ST_FREE
        lda st_counts+ST_FREE+1
        adc .r+1
        sta st_counts+ST_FREE+1
        lda st_counts+ST_FREE+2
        adc .r+2
        sta st_counts+ST_FREE+2
+       rts
.r      !byte 0, 0, 0

; long_percent - num24 = the room left as a percentage of all the room:
; the window and the REU's banks from DOC_BANK on, less RESERVE. Both in
; 256-byte units, so they fit the math helpers.
long_percent
        lda st_counts+ST_FREE+1
        sta math_num
        lda st_counts+ST_FREE+2
        sta math_num+1
        lda #100
        sta math_mul
        jsr mul_16x8
        lda #<((REUDOC-UNDO_SIZE-BUF_START-RESERVE-HDR)/256)
        sta math_div
        sec
        lda reu_banks
        sbc #DOC_BANK
        sta math_div+1
        jsr div_24x16
        lda math_num
        sta num24
        lda #0
        sta num24+1
        sta num24+2
        rts

;----------------------------------------------------------------------------
; marker_long - update_marker for a long document: mk_first, mk_last and
; mk_total (window offsets) become offsets in the whole document (win_base
; on, and the tail in the total), then are halved together until the total
; fits in 16 bits
;----------------------------------------------------------------------------
!zone marker_long
marker_long
        ldx #0                  ; (mk_first, mk_last, mk_total follow each
        ldy #0                  ; other: 2 bytes each; .v 3 bytes each)
-       clc
        lda mk_first,x
        adc win_base
        sta .v,y
        lda mk_first+1,x
        adc win_base+1
        sta .v+1,y
        lda #0
        adc win_base+2
        sta .v+2,y
        inx
        inx
        iny
        iny
        iny
        cpy #9
        bcc -
        clc                     ; the total: the tail too
        lda .v+6
        adc tail_len
        sta .v+6
        lda .v+7
        adc tail_len+1
        sta .v+7
        lda .v+8
        adc tail_len+2
        sta .v+8
.half   lda .v+8
        beq .out
        ldx #6
-       lsr .v+2,x
        ror .v+1,x
        ror .v,x
        dex
        dex
        dex
        bpl -
        jmp .half
.out    ldx #0
        ldy #0
-       lda .v,y
        sta mk_first,x
        lda .v+1,y
        sta mk_first+1,x
        inx
        inx
        iny
        iny
        iny
        cpy #9
        bcc -
        rts
.v      !fill 9, 0

;----------------------------------------------------------------------------
; reu_all_in - the whole document into the window, if it fits (CTRL-A;
; saving a magic document to tape, which is one piece). The cursor stays
; at its place in the text; marked text is unmarked. Carry set (after
; saying so with the message at A/X) if it doesn't fit.
;----------------------------------------------------------------------------
!zone reu_all_in
reu_all_in
        sta .msg
        stx .msg+1
        jsr head_empty
        bne +
        jsr tail_empty
        bne +
        clc                     ; (all in already)
        rts
+       jsr text_len            ; the whole length: win_base + the window's
        clc                     ; text + the tail
        lda work
        adc win_base
        sta .len
        lda work+1
        adc win_base+1
        sta .len+1
        lda #0
        adc win_base+2
        sta .len+2
        clc
        lda .len
        adc tail_len
        sta .len
        lda .len+1
        adc tail_len+1
        sta .len+1
        lda .len+2
        adc tail_len+2
        bne .too_long
        lda .len                ; room: the window, less a little for typing
        cmp #<(REUDOC-UNDO_SIZE-BUF_START-256)
        lda .len+1
        sbc #>(REUDOC-UNDO_SIZE-BUF_START-256)
        bcc +
.too_long
        lda .msg
        ldx .msg+1
        jsr message_box
        sec
        rts
+       lda #0
        sta sel_on
        jsr get_cursor_off      ; the cursor's place in the whole text
        clc
        lda work
        adc win_base
        sta .cur
        lda work+1
        adc win_base+1
        sta .cur+1
        jsr reu_to_start        ; the head in ...
        lda tail_len            ; ... and all of the tail
        sta rd_len
        lda tail_len+1
        sta rd_len+1
        ora rd_len
        beq +
        jsr tail_pop
+       lda .cur
        sta off
        lda .cur+1
        sta off+1
        jsr move_gap_to
        jsr rd_redraw
        clc
        rts
.msg    !word 0
.len    !byte 0, 0, 0
.cur    !word 0

; rd_redraw - after moving the window: the screen laid out again, the
; cursor on its row
rd_redraw
        jsr count_colors
        lda #0
        sta top_known
        ldx cur_row
        jmp show_cursor_at

msg_mark_long
        !scr "too long to mark all", 0
msg_tape_long
        !scr "too long: save it as petscii", 0

;----------------------------------------------------------------------------
; Find in a long document (find.asm). The search goes through the window;
; at its end, rd_slide moves the window on; at the document's end,
; reu_to_start goes back to the start. rd_from is where the search began,
; in the whole document.
;----------------------------------------------------------------------------

; rd_find_start - off = where the search begins (a window offset)
rd_find_start
        clc
        lda off
        adc win_base
        sta rd_from
        lda off+1
        adc win_base+1
        sta rd_from+1
        lda #0
        sta rd_slid
        adc win_base+2
        sta rd_from+2
        rts

; rd_past_from - carry set if off (a window offset) is at or past rd_from
!zone rd_past_from
rd_past_from
        clc
        lda off
        adc win_base
        tax
        lda off+1
        adc win_base+1
        tay
        lda #0
        adc win_base+2
        sta .hi
        cpx rd_from
        tya
        sbc rd_from+1
        lda .hi
        sbc rd_from+2
        rts
.hi     !byte 0

; rd_find_back - not found, after the window moved: the cursor back where
; the search began (the window holds that place again by then), nothing
; marked
!zone rd_find_back
rd_find_back
        sec
        lda rd_from
        sbc win_base
        sta off
        lda rd_from+1
        sbc win_base+1
        sta off+1
        lda rd_from+2
        sbc win_base+2
        bcs +
        lda #0                  ; (before the window: its start)
        sta off
        sta off+1
+       jsr text_len            ; (past its end: its end)
        lda off
        cmp work
        lda off+1
        sbc work+1
        bcc +
        lda work
        sta off
        lda work+1
        sta off+1
+       jsr move_gap_to
        lda #0
        sta sel_on
        jmp rd_redraw

; rd_slide - Find, at the window's end: the window moves on. off = the
; window offset of the place being tried; afterwards, that same place's
; offset. Carry set if no more text came in (the tail is empty).
!zone rd_slide
rd_slide
        jsr tail_empty
        bne +
        sec
        rts
+       lda #1
        sta rd_slid
        lda off
        sta .keep
        lda off+1
        sta .keep+1
        jsr text_len            ; the gap to the window's end
        lda work
        sta off
        lda work+1
        sta off+1
        jsr move_gap_to
.push   jsr rd_sizes            ; room for a chunk of the tail yet?
        lda rd_gap+1
        cmp #>CHUNK_SIZE
        bcs .pop
        lda #0                  ; no: the start to the head (as long as the
        jsr push_len            ; place being tried stays)
        bcs .pop
        lda .keep
        cmp rd_len
        lda .keep+1
        sbc rd_len+1
        bcc .pop
        jsr reu_room
        bcc .pop
        jsr push_chunk
        sec
        lda .keep
        sbc rd_len
        sta .keep
        lda .keep+1
        sbc rd_len+1
        sta .keep+1
        jmp .push
.pop    lda tail_len            ; up to CHUNK_SIZE of the tail, as much as
        sta rd_len              ; there is room for
        lda tail_len+1
        sta rd_len+1
        lda tail_len+2
        bne +
        lda rd_len
        cmp #<CHUNK_SIZE
        lda rd_len+1
        sbc #>CHUNK_SIZE
        bcc ++
+       lda #<CHUNK_SIZE
        sta rd_len
        lda #>CHUNK_SIZE
        sta rd_len+1
++      jsr rd_sizes
        lda rd_gap
        cmp rd_len
        lda rd_gap+1
        sbc rd_len+1
        bcs +
        lda rd_gap
        sta rd_len
        lda rd_gap+1
        sta rd_len+1
+       lda .keep
        sta off
        lda .keep+1
        sta off+1
        lda rd_len
        ora rd_len+1
        bne +
        sec                     ; (no room at all)
        rts
+       jsr tail_pop
        jsr count_colors
        lda #0
        sta top_known
        clc
        rts
.keep   !word 0

;----------------------------------------------------------------------------
; reu_goto - CTRL-Z in a long document (undo.asm): the window to the
; document offset u_q, with the u_b bytes after it in the window too.
; From the start if it lies before the window, then on through it.
;----------------------------------------------------------------------------
!zone reu_goto
reu_goto
        lda u_q                 ; before the window? From the start then
        cmp win_base
        lda u_q+1
        sbc win_base+1
        lda u_q+2
        sbc win_base+2
        bcs +
        jsr reu_to_start
+
-       jsr text_len            ; the window's end, in the document ...
        clc
        lda work
        adc win_base
        sta .e
        lda work+1
        adc win_base+1
        sta .e+1
        lda #0
        adc win_base+2
        sta .e+2
        clc                     ; ... at or past P + B? Then it is there.
        lda u_q
        adc u_b
        sta .t
        lda u_q+1
        adc u_b+1
        sta .t+1
        lda u_q+2
        adc #0
        sta .t+2
        lda .e
        cmp .t
        lda .e+1
        sbc .t+1
        lda .e+2
        sbc .t+2
        bcs .done
        lda work                ; else on through the document
        sta off
        lda work+1
        sta off+1
        jsr rd_slide
        bcc -
.done   rts
.e      !byte 0, 0, 0
.t      !byte 0, 0, 0

rd_from         !byte 0, 0, 0   ; Find: where it began, in the document
rd_slid         !byte 0         ; Find: 1 once the window has moved

;----------------------------------------------------------------------------
; Variables
;----------------------------------------------------------------------------
rd_hdr          !fill HDR, 0    ; a chunk header
rd_len          !word 0         ; a length to move
rd_before       !word 0         ; rd_sizes: text before the gap,
rd_after        !word 0         ;   after it,
rd_gap          !word 0         ;   and the gap
rd_at           !byte 0, 0, 0   ; each_pages: where in the REU ...
rd_left         !byte 0, 0, 0   ;   ... and how much is left
