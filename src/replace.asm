;============================================================================
; replace.asm - CTRL-F's box, and CTRL-R: find and replace (Jim, v0.3)
;
; CTRL-F asks for the text (FIND:) and finds the next match (find.asm).
; CTRL-R asks for it too, then for what goes in its place (WITH:;
; nothing typed: the matches just go), and finds the matches one after
; another, as Find does, asking at each: REPLACE Y/N/A=ALL. Y replaces
; this one, N leaves it, A replaces it and all the rest without asking;
; RUN/STOP stops. It goes through the document once, from the top to the
; end. Then a box says how many it replaced.
;
; A match is replaced as typing over marked text replaces it: the match
; goes, codes and all (delete_selection), and the new text takes the color
; in effect where the match began. Each Y can be undone with CTRL-Z; after
; A, CTRL-Z undoes all that A replaced (as one action, if the text taken
; out fits the undo log). While replacing all, nothing is drawn until the
; end (replace_all: show_cursor_at, leave_cursor and Find skip it).
;
; Find is told it has gone round from the top already (find_wrapped), and
; that it began at the very end (find_from, rd_from): so it stops at the
; end of the document. (With a long document the cursor then ends at the
; end of it.)
;
; Lives in the lower part (ask_text and find_start, which CTRL-F uses
; too, are in find.asm); runs with the KERNAL ROM switched out. Its bytes
; are in sprite block 255, for room.
;============================================================================
FIND_MAX        = 26            ; longest search text (the box fills the
                                ; screen's width)
; Find's and Replace's bytes are in sprite block 255 ($3fc0-$3ffe, unused
; and cleared at start-up; $3fff must stay 0), for room:
find_buf        = $3fc0         ; 26: the last search text (PETSCII) ...
repl_buf        = find_buf + FIND_MAX ; 26: ... and the last replacement
find_len        = repl_buf + FIND_MAX ; their lengths, in the same order
repl_len        = find_len + 1
find_cont       = repl_len + 1  ; 1 while CTRL-R goes on: Find starts at
                                ; the cursor and says nothing at the end
replace_all     = find_cont + 1 ; 1 while CTRL-R replaces all: no drawing
find_from       = replace_all + 1 ; 2: where the search began
find_wrapped    = find_from + 2 ; 1 once it has gone round from the top
r_count         = find_wrapped + 1 ; 2: CTRL-R: how many it replaced
r_all           = r_count + 2   ; 1 after A (all the rest)
r_i             = r_all + 1     ; (counts the new text's bytes)
!if r_i >= $3fff { !error "Find's bytes must end before $3fff" }

; find_key - CTRL-F
!zone find_key
find_key
        lda #<msg_find
        ldx #>msg_find
        ldy #0
        jsr ask_text
        bcs +                   ; cancelled
        jmp find_start
+       rts

; replace_key - CTRL-R
!zone replace_key
replace_key
        lda #<msg_find
        ldx #>msg_find
        ldy #0
        jsr ask_text
        bcc +
        rts                     ; cancelled
+       lda #1                  ; (nothing typed is an answer: the
        sta input_empty_ok      ; matches just go)
        lda #<msg_with
        ldx #>msg_with
        ldy #1
        jsr ask_text
        bcc +
        rts
+       lda #0
        sta r_count
        sta r_count+1
        sta r_all
        sta sel_on              ; (nothing marked)
        lda #1                  ; from the top to the end (see above)
        sta find_cont
        sta find_wrapped
        lda #$ff
        sta find_from
        sta find_from+1
        lda reu_docs
        beq +
        lda #$ff
        sta rd_from
        sta rd_from+1
        sta rd_from+2
        jsr reu_to_start        ; (a long document: its start in the window)
+       lda #0
        sta off
        sta off+1
        jsr find_at             ; the first match
        jmp .found

.match  ; A match, marked
        lda r_all
        bne .replace
        ldx #4                  ; it goes above the question's box (rows
        jsr show_cursor_at      ; 11-13)
        lda #<msg_replace
        ldx #>msg_replace
        ldy #0
        jsr box_open
-       jsr wait_key
        cmp #KEY_Y
        beq .yes
        cmp #KEY_N
        beq .no
        cmp #KEY_A
        beq .yes_all
        cmp #KEY_STOP
        beq .stop
        cmp #KEY_RESTORE
        bne -
.stop   jsr box_close
        jmp .done
.no     jsr box_close
        jmp .next
.yes_all
        inc r_all
        inc replace_all
.yes    jsr box_close
        lda #UK_OTHER           ; (one action for CTRL-Z - with A, all the
        jsr undo_start          ; rest)
.replace
        jsr delete_selection    ; the match goes ...
        ldx #0
-       cpx repl_len            ; ... and the new text goes in
        bcs +
        stx r_i
        lda repl_buf,x
        jsr insert_byte
        bcs .done               ; (no room)
        ldx r_i
        inx
        bne -
+       inc r_count
        bne .next
        inc r_count+1

.next   lda #0
        sta sel_on
        lda reu_docs            ; (a long document: the window follows the
        beq +                   ; cursor, as after every key)
        jsr reu_keep
+       jsr find_start          ; the next match
.found  lda sel_on
        beq .done
        jmp .match

.done   lda #0                  ; all of it drawn again (after replacing
        sta find_cont           ; all: for the first time), the cursor on
        sta replace_all         ; row 4, as at the questions
        sta top_known
        ldx #4
        jsr show_cursor_at
        lda r_count             ; "12 REPLACED"
        sta num24
        lda r_count+1
        sta num24+1
        lda #0
        sta num24+2
        jsr num24_text
        ldx #0
-       lda num_text,x
        beq +
        sta status_buf,x
        inx
        bne -
+       ldy #0
-       lda m_replaced,y
        sta status_buf,x
        inx
        iny
        cmp #0
        bne -
        lda #<status_buf
        ldx #>status_buf
        jmp message_box

