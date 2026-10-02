;============================================================================
; undo.asm - CTRL-Z: undo the last action (Jim, phase 12)
;
; Every change to the text goes through a few routines in the editor:
; insert_byte and insert_after (a byte in), take_byte, delete_left and
; overwrite_next (a byte out) and cleanup (codes tidied away).
; Each tells this file what it is about to do, and the changes of one
; action are kept in the undo log as entries, each saying "at offset P of
; the document, these A bytes (kept here) were replaced by B bytes".
; CTRL-Z puts them back, the last first. (One undo, no redo, and CLEAR ALL
; can't be undone: Jim, to keep it small.)
;
; An action: a run of typing (letters, RETURN), a run of INST/DEL, or one
; of the other editing keys (cut, paste, a color key, SHIFT + INST).
; Typing over marked text, or deleting it, always starts a new one.
; Any other key ends a run - but codes the editor tidies away when the
; cursor moves still go into the log: they belong to what the action left.
; A byte in or out next to the last entry's text makes that entry longer:
; a run of typing is one entry, a cut is one entry holding what went.
;
; The log has 1 KB at the top of the text buffer (undo_base; the text ends
; below it). An action that takes out more than that can't be undone:
; "TOO BIG TO UNDO". (Inserting costs nothing: pasting a lot can be
; undone.) The offsets count in the
; whole document: with a long document in an REU, win_base is added.
;
; An entry in the log (its header last, so the log is read from its end):
;   A bytes   the text that was there
;   3 bytes   P, the offset          \
;   2 bytes   A                       } the header (U_HDR bytes: u_hdr)
;   2 bytes   B                      /
; Lives in the lower part; uses zp_ptr and zp_ptr2 (main program only).
;============================================================================
UNDO_SIZE       = 1024          ; (taken from the text buffer at start-up)
U_HDR           = 7
UK_TYPE         = 1             ; kinds of action (undo_start)
UK_DEL          = 2
UK_OTHER        = 3

undo_base       !word 0         ; the log's room: undo_base up to undo_end
undo_end        !word 0
undo_top        !word 0         ; the log ends here (undo_base: it is empty)
undo_ok         !byte 1         ; 0: the action didn't fit ("too big")
undo_on         !byte 1         ; 0 while CTRL-Z itself changes the text
undo_kind       !byte 0         ; what this key does (UK_...; 0: nothing)
undo_prev       !byte 0         ; ... and what the last key did
u_hdr                           ; an entry's header:
u_q             !byte 0, 0, 0   ;   P
u_a             !word 0         ;   A
u_b             !word 0         ;   B
u_p             !byte 0, 0, 0   ; an offset (a change at it)
u_t             !byte 0, 0, 0   ; P - u_q
u_n             !word 0         ; a number of bytes
u_x             !word 0
u_byte          !byte 0
u_run_p         !byte 0, 0, 0   ; cleanup's run: where it starts,
u_run_a         !word 0         ;   how long it was,
u_run_ok        !byte 0         ;   kept in the log for now (1)
u_rp            !word 0         ; CTRL-Z: the log is read back from here

;----------------------------------------------------------------------------
; Actions
;----------------------------------------------------------------------------

; undo_reset - an empty log. A = undo_ok (1: CTRL-Z says "nothing to undo")
undo_reset
        sta undo_ok
        lda undo_base
        sta undo_top
        lda undo_base+1
        sta undo_top+1
        rts

; undo_key_in - every key (editor_key): it changes no text unless it says
; so (undo_start); what the last key did is kept for undo_start
undo_key_in
        lda undo_kind
        sta undo_prev
        lda #0
        sta undo_kind
        rts

; undo_start - A = the kind of action this key is (UK_...). A run of typing
; or of INST/DEL goes on with the action the last key started; anything
; else - and anything done to marked text - starts a new one.
undo_start
        cmp #UK_OTHER
        beq +
        ldx sel_on
        bne +
        cmp undo_prev
        beq ++
+       pha
        lda #1
        jsr undo_reset
        pla
++      sta undo_kind
        rts

;----------------------------------------------------------------------------
; What the editor is about to do
;----------------------------------------------------------------------------

; undo_ins - a byte is going into the text at the cursor (insert_byte,
; insert_after)
!zone undo_ins
undo_ins
        jsr u_recording
        beq .ret
        jsr u_here
        jsr u_last
        bcs .new
        jsr u_diff              ; in the last entry's text or just after it
        lda u_t+2               ; (0 <= P - Q <= B)? Then that grows by one.
        bne .new
        lda u_b
        cmp u_t
        lda u_b+1
        sbc u_t+1
        bcc .new
        inc u_b
        bne +
        inc u_b+1
+       jmp u_put
.new    lda #U_HDR              ; else a new entry: P, A = 0, B = 1
        jsr u_room
        bcc u_full
        jsr u_q_is_p
        lda #0
        sta u_a
        sta u_a+1
        sta u_b+1
        lda #1
        sta u_b
        jmp u_push
.ret    rts

; u_full - more than the log can hold: CTRL-Z can't undo this action
u_full  lda #0
        sta undo_ok
        rts

; undo_del_here - A = the byte just after the cursor, which is going out
; of the text (take_byte, delete_left)
; undo_del_at - the same, for a byte at window offset "off" (overwrite_next)
!zone undo_del
undo_del_at
        pha
        lda off
        sta u_p
        lda off+1
        sta u_p+1
        lda #0
        sta u_p+2
        jsr u_doc
        jmp +
undo_del_here
        pha
        jsr u_here
+       pla
        sta u_byte
        jsr u_recording
        beq .ret
        jsr u_last
        bcs .new
        jsr u_diff
        lda u_t+2
        bpl +
        jmp .before             ; (P before Q)
+       bne .new
        lda u_t                 ; P - Q < B: one of the action's own bytes
        cmp u_b                 ; goes again: B one less
        lda u_t+1
        sbc u_b+1
        bcs .after
        lda u_b
        bne +
        dec u_b+1
+       dec u_b
        jmp u_put
.new    lda #U_HDR+1            ; else a new entry: the byte, then P, A = 1,
        jsr u_room              ; B = 0
        bcc .full
        lda undo_top
        sta zp_ptr
        lda undo_top+1
        sta zp_ptr+1
        lda u_byte
        ldy #0
        sta (zp_ptr),y
        lda #1
        jsr u_add_top
        jsr u_q_is_p
        lda #1
        sta u_a
        lda #0
        sta u_a+1
        sta u_b
        sta u_b+1
        jmp u_push
.full   jmp u_full
.ret    rts
.after  lda u_t                 ; P - Q = B: the byte just after its text
        cmp u_b                 ; (the old text gets it at its end, and
        bne .new                ; the header moves up one)
        lda u_t+1
        cmp u_b+1
        bne .new
        lda #1
        jsr u_room
        bcc .full
        lda zp_ptr              ; (the header up by one)
        sta zp_ptr2
        lda zp_ptr+1
        sta zp_ptr2+1
        lda #U_HDR
        jsr u_shift
        lda u_byte
        ldy #0
        sta (zp_ptr),y
        jmp u_grow
.before lda u_t                 ; P - Q = -1: the byte just before it (the
        and u_t+1               ; old text gets it in front: all of the
        and u_t+2               ; entry moves up one)
        cmp #$ff
        bne .new
        lda #1
        jsr u_room
        bcc .full
        sec                     ; (from the old text's start)
        lda zp_ptr
        sbc u_a
        sta zp_ptr2
        lda zp_ptr+1
        sbc u_a+1
        sta zp_ptr2+1
        clc
        lda u_a
        adc #U_HDR
        ldx u_a+1
        bcc +
        inx
+       jsr u_shift_n
        lda u_byte
        ldy #0
        sta (zp_ptr2),y
        ldx #0                  ; Q one less
-       lda u_q,x
        sec
        sbc #1
        sta u_q,x
        bcs u_grow
        inx
        cpx #3
        bcc -
        bcs u_grow              ; (always)

; u_grow - the entry at zp_ptr got a byte longer (and so did the log)
u_grow  inc zp_ptr
        bne +
        inc zp_ptr+1
+       inc undo_top
        bne +
        inc undo_top+1
+       inc u_a
        bne +
        inc u_a+1
+       jmp u_put

;----------------------------------------------------------------------------
; Helpers
;----------------------------------------------------------------------------

; u_recording - Z clear if changes are to be noted now
u_recording
        lda undo_on
        and undo_ok
        rts

; u_here - u_p = the cursor's offset in the document
u_here  sec
        lda gap_start
        sbc #<BUF_START
        sta u_p
        lda gap_start+1
        sbc #>BUF_START
        sta u_p+1
        lda #0
        sta u_p+2
; u_doc - u_p (a window offset) becomes an offset in the document
u_doc   lda reu_docs
        beq +
        clc
        lda u_p
        adc win_base
        sta u_p
        lda u_p+1
        adc win_base+1
        sta u_p+1
        lda u_p+2
        adc win_base+2
        sta u_p+2
+       rts

; u_q_is_p - Q = P
u_q_is_p
        ldx #2
-       lda u_p,x
        sta u_q,x
        dex
        bpl -
        rts

; u_diff - u_t = P - Q
u_diff  sec
        lda u_p
        sbc u_q
        sta u_t
        lda u_p+1
        sbc u_q+1
        sta u_t+1
        lda u_p+2
        sbc u_q+2
        sta u_t+2
        rts

; u_last - the last entry's header into u_hdr, zp_ptr at it. Carry set if
; the log is empty.
u_last  lda undo_top
        cmp undo_base
        bne +
        lda undo_top+1
        cmp undo_base+1
        bne +
        sec
        rts
+       sec
        lda undo_top
        sbc #U_HDR
        sta zp_ptr
        lda undo_top+1
        sbc #0
        sta zp_ptr+1
        ldy #U_HDR-1
-       lda (zp_ptr),y
        sta u_hdr,y
        dey
        bpl -
        clc
        rts

; u_put - u_hdr into the header at zp_ptr
u_put   ldy #U_HDR-1
-       lda u_hdr,y
        sta (zp_ptr),y
        dey
        bpl -
        rts

; u_push - u_hdr as a new header at the log's end
u_push  lda undo_top
        sta zp_ptr
        lda undo_top+1
        sta zp_ptr+1
        jsr u_put
        lda #U_HDR
; u_add_top - the log A bytes longer
u_add_top
        clc
        adc undo_top
        sta undo_top
        bcc +
        inc undo_top+1
+       rts

; u_room - room for A more bytes in the log? Carry set if so.
; u_room16 - the same for u_n bytes
u_room  sta u_n
        lda #0
        sta u_n+1
u_room16
        clc
        lda undo_top
        adc u_n
        sta u_x
        lda undo_top+1
        adc u_n+1
        sta u_x+1
        lda undo_end
        cmp u_x
        lda undo_end+1
        sbc u_x+1
        rts

; u_shift - the A bytes from zp_ptr2 on, up by one place; u_shift_n - the
; same for A/X bytes. From the last back, as the two places overlap.
; zp_ptr2 ends where it began.
!zone u_shift
u_shift ldx #0
u_shift_n
        sta u_n
        stx u_n+1
        clc                     ; zp_ptr2 just past the last of them
        lda zp_ptr2
        adc u_n
        sta zp_ptr2
        lda zp_ptr2+1
        adc u_n+1
        sta zp_ptr2+1
-       lda u_n
        ora u_n+1
        beq .done
        lda zp_ptr2             ; back one, and that byte up one
        bne +
        dec zp_ptr2+1
+       dec zp_ptr2
        ldy #0
        lda (zp_ptr2),y
        iny
        sta (zp_ptr2),y
        lda u_n
        bne +
        dec u_n+1
+       dec u_n
        jmp -
.done   rts

; u_copy - u_n bytes from zp_ptr2 to zp_ptr, first to last; both move on
u_copy
-       lda u_n
        ora u_n+1
        beq +
        ldy #0
        lda (zp_ptr2),y
        sta (zp_ptr),y
        inc zp_ptr2
        bne ++
        inc zp_ptr2+1
++      inc zp_ptr
        bne ++
        inc zp_ptr+1
++      lda u_n
        bne ++
        dec u_n+1
++      dec u_n
        jmp -
+       rts

;----------------------------------------------------------------------------
; cleanup
;----------------------------------------------------------------------------

; undo_run - cleanup is about to take codes out of the run that starts at
; A/X (an address) and ends at the cursor: the run as it is goes into the
; log, after its end, for now. undo_run_end (A/X: the run's start again)
; then makes it an entry - if codes really went.
!zone undo_run
undo_run
        sta zp_ptr2
        stx zp_ptr2+1
        lda #0
        sta u_run_ok
        jsr u_recording
        beq .ret
        sec                     ; its length
        lda gap_start
        sbc zp_ptr2
        sta u_run_a
        lda gap_start+1
        sbc zp_ptr2+1
        sta u_run_a+1
        clc                     ; room for it, and a header?
        lda u_run_a
        adc #U_HDR
        sta u_n
        lda u_run_a+1
        adc #0
        sta u_n+1
        jsr u_room16
        bcs +
        jmp u_full
+       sec                     ; where it starts, in the document
        lda zp_ptr2
        sbc #<BUF_START
        sta u_p
        lda zp_ptr2+1
        sbc #>BUF_START
        sta u_p+1
        lda #0
        sta u_p+2
        jsr u_doc
        ldx #2
-       lda u_p,x
        sta u_run_p,x
        dex
        bpl -
        lda undo_top            ; the run's bytes after the log's end
        sta zp_ptr
        lda undo_top+1
        sta zp_ptr+1
        lda u_run_a
        sta u_n
        lda u_run_a+1
        sta u_n+1
        jsr u_copy
        inc u_run_ok
.ret    rts

undo_run_end
        ldy u_run_ok
        beq .no_run
        sta zp_ptr2
        stx zp_ptr2+1
        ldx #2                  ; P: where the run starts
-       lda u_run_p,x
        sta u_q,x
        dex
        bpl -
        lda u_run_a             ; A: how long it was
        sta u_a
        lda u_run_a+1
        sta u_a+1
        sec                     ; B: how long it is now
        lda gap_start
        sbc zp_ptr2
        sta u_b
        lda gap_start+1
        sbc zp_ptr2+1
        sta u_b+1
        lda u_a                 ; the old run is in the log already: the
        jsr u_add_top           ; header goes after it
        lda undo_top+1
        clc
        adc u_a+1
        sta undo_top+1
        jmp u_push
.no_run rts

;----------------------------------------------------------------------------
; undo_key - CTRL-Z: the entries put back, the last first. Then the log is
; empty (one undo).
;----------------------------------------------------------------------------
!zone undo_key
undo_key
        lda undo_ok
        bne +
        lda #<msg_undo_big
        ldx #>msg_undo_big
        jmp message_box
+       jsr u_last
        bcc +
        lda #<msg_undo_none
        ldx #>msg_undo_none
        jmp message_box
+       lda #0
        sta sel_on              ; (nothing marked afterwards)
        sta undo_on             ; (the changes below are not noted)
        lda #1
        sta modified
        lda undo_top            ; read back from the log's end
        sta u_rp
        lda undo_top+1
        sta u_rp+1

.entry  lda u_rp                ; back at the log's start: done
        cmp undo_base
        bne +
        lda u_rp+1
        cmp undo_base+1
        beq .done
+       sec                     ; the entry's header ...
        lda u_rp
        sbc #U_HDR
        sta zp_ptr
        lda u_rp+1
        sbc #0
        sta zp_ptr+1
        ldy #U_HDR-1
-       lda (zp_ptr),y
        sta u_hdr,y
        dey
        bpl -
        sec                     ; ... and its old text, just below
        lda zp_ptr
        sbc u_a
        sta u_rp
        sta zp_ptr2
        lda zp_ptr+1
        sbc u_a+1
        sta u_rp+1
        sta zp_ptr2+1
        jsr u_window            ; the cursor to P
        jsr move_gap_to
        clc                     ; the B bytes there go ...
        lda gap_end
        adc u_b
        sta gap_end
        lda gap_end+1
        adc u_b+1
        sta gap_end+1
-       lda u_a                 ; ... and the A old ones come back
        ora u_a+1
        beq .entry
        ldy #0
        lda (zp_ptr2),y
        jsr insert_byte
        inc zp_ptr2
        bne +
        inc zp_ptr2+1
+       lda u_a
        bne +
        dec u_a+1
+       dec u_a
        jmp -

.done   lda #1                  ; the log empty: undone
        sta undo_on
        jsr undo_reset
        jsr count_colors
        lda #0
        sta top_known
        ldx cur_row
        jmp show_cursor_at

; u_window - off = the window offset of P (u_q). A long document: the
; window goes there first, with P's B bytes in it too (reu_goto).
u_window
        lda reu_docs
        beq +
        jsr reu_goto
        sec
        lda u_q
        sbc win_base
        sta off
        lda u_q+1
        sbc win_base+1
        sta off+1
        rts
+       lda u_q
        sta off
        lda u_q+1
        sta off+1
        rts
