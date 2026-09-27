;============================================================================
; menu.asm - boxes in the middle of the screen: questions, messages and
; typed-in answers. (The menus themselves come in phase 8.)
;
; A box is three rows high (rows 11-13): a frame of PETSCII line
; characters around one row of text. What was under it is saved and put
; back when it closes. Box texts are screen codes ending in 0, with the
; letters written in lower case (screen codes 1-26): the box shows them as
; capitals in whichever character set is on.
;============================================================================

BOX_ROW         = 11            ; top edge of a box
BOX_TEXT_ROW    = 12            ; its text row

box_left        !byte 0         ; screen column of the box's left side
box_width       !byte 0         ; width, sides included
box_col         !byte 0         ; screen column just after the box's text
box_color       !byte 0         ; the color it is drawn in
box_had_cursor  !byte 0         ; the editor cursor was showing before

;----------------------------------------------------------------------------
; box_open - draw a box in the middle of the screen. A/X = its text,
; Y = extra room after the text (for a typed answer; 0 for none).
; Hides the editor's cursor while the box is up.
;----------------------------------------------------------------------------
!zone box_open
box_open
        sta zp_ptr2
        stx zp_ptr2+1
        sty .extra
        lda cursor_shown
        sta box_had_cursor
        jsr cursor_hide
        jsr readable_color
        sta box_color

        ldy #0                  ; length of the text
-       lda (zp_ptr2),y
        beq +
        iny
        bne -
+       sty .len
        tya                     ; width: side, space, text, extra room,
        clc                     ; space, side
        adc .extra
        adc #4
        sta box_width
        lda #40                 ; centered
        sec
        sbc box_width
        lsr
        sta box_left
        clc                     ; the text ends here
        adc #2
        adc .len
        sta box_col

        jsr .save

        ldx #BOX_ROW            ; top edge
        lda #$70                ; top left corner
        ldy #$6e                ; top right corner
        jsr .edge
        ldx #BOX_ROW+2          ; bottom edge
        lda #$6d                ; bottom left corner
        ldy #$7d                ; bottom right corner
        jsr .edge

        ldx #BOX_TEXT_ROW       ; the text row: sides, then blank ...
        jsr box_row_ptrs
        ldy #0
        lda #$5d                ; side
        jsr box_put
-       lda #$20
        jsr box_put
        cpy box_width
        bcc -
        dey
        lda #$5d
        jsr box_put
        ldx #0                  ; ... then the text, from column 2
-       txa
        tay
        lda (zp_ptr2),y
        beq +
        jsr box_capitals
        pha
        txa
        clc
        adc #2
        tay
        pla
        jsr box_put
        inx
        bne -
+       rts

; .edge - X = row, A = left corner, Y = right corner: a horizontal edge
.edge   sta .left_corner
        sty .right_corner
        jsr box_row_ptrs
        ldy #0
        lda .left_corner
        jsr box_put
-       lda #$40                ; horizontal line
        jsr box_put
        cpy box_width
        bcc -
        dey
        lda .right_corner
        jmp box_put

; .save - keep what is under the box (3 rows of box_width)
.save   lda #0
        sta .i
        lda #BOX_ROW
        sta .r
-       ldx .r
        jsr box_row_ptrs
        ldx .i
        ldy #0
--      lda (zp_ptr),y
        sta prompt_save,x
        lda (work),y
        sta prompt_save+120,x
        inx
        iny
        cpy box_width
        bcc --
        stx .i
        inc .r
        lda .r
        cmp #BOX_ROW+3
        bcc -
        rts

.extra          !byte 0
.len            !byte 0
.left_corner    !byte 0
.right_corner   !byte 0
.i              !byte 0
.r              !byte 0

;----------------------------------------------------------------------------
; box_close - put back what was under the box (and the cursor, if it was
; showing when the box opened).
;----------------------------------------------------------------------------
!zone box_close
box_close
        lda #0
        sta .i
        lda #BOX_ROW
        sta .r
-       ldx .r
        jsr box_row_ptrs
        ldx .i
        ldy #0
--      lda prompt_save,x
        sta (zp_ptr),y
        lda prompt_save+120,x
        sta (work),y
        inx
        iny
        cpy box_width
        bcc --
        stx .i
        inc .r
        lda .r
        cmp #BOX_ROW+3
        bcc -
        lda box_had_cursor
        beq +
        jmp cursor_show
+       rts
.i      !byte 0
.r      !byte 0

;----------------------------------------------------------------------------
; Helpers
;----------------------------------------------------------------------------

; box_row_ptrs - zp_ptr = screen RAM, work = color RAM of row X at the
; box's left side
box_row_ptrs
        lda row_lo,x
        clc
        adc box_left
        sta zp_ptr
        sta work
        lda row_hi,x
        adc #0
        sta zp_ptr+1
        clc
        adc #>(COLOR_RAM - SCREEN)
        sta work+1
        rts

; box_put - A at column Y of the row set by box_row_ptrs, in the box
; color; Y moves on by one. Keeps X.
box_put sta (zp_ptr),y
        lda box_color
        sta (work),y
        iny
        rts

; box_capitals - A = a screen code. Letters (1-26) become capitals in the
; character set that is on: in the upper/lower set capitals are 65-90.
; Keeps X and Y.
!zone box_capitals
box_capitals
        cmp #1
        bcc +
        cmp #27
        bcs +
        pha
        lda VIC_MEMPTR
        and #%00000010
        beq ++                  ; upper/graphics set: 1-26 are capitals
        pla
        ora #$40
        rts
++      pla
+       rts

; readable_color - A = the color for boxes: the default text color, unless
; the background is that same color - then black or white, whichever
; shows up better on it.
!zone readable_color
readable_color
        lda text_color
        cmp text_bg
        bne +
        ldx text_bg
        lda contrast_color,x
+       rts

; wait_key - wait for a key event. Returns A = key code, Y = modifiers.
!zone wait_key
wait_key
!if DEBUG {
        jsr mailbox_poll
}
        jsr get_key
        bcs wait_key
!if DEBUG {
        jsr mailbox_log_key
}
        rts

;============================================================================
; The kinds of boxes
;============================================================================

; prompt_yes_no - ask a question (A/X = its text). Waits for Y, or N /
; RUN/STOP / RESTORE. Returns carry set for Y.
!zone prompt_yes_no
prompt_yes_no
        ldy #0
        jsr box_open
-       jsr wait_key
        cmp #KEY_Y
        beq .yes
        cmp #KEY_N
        beq .no
        cmp #KEY_STOP
        beq .no
        cmp #KEY_RESTORE
        beq .no
        bne -
.yes    jsr box_close
        sec
        rts
.no     jsr box_close
        clc
        rts

; message_box - show a message (A/X = its text) until a key is pressed.
!zone message_box
message_box
        ldy #0
        jsr box_open
        jsr wait_key
        jmp box_close

;----------------------------------------------------------------------------
; prompt_input - ask for a typed answer, such as a file name.
; A/X = the question (e.g. "load:"), input_max = the longest answer.
; input_buf/input_len hold the answer, and whatever is there already is
; shown to start with (so the last file name can be used again).
; RETURN accepts a non-empty answer (carry clear); RUN/STOP cancels
; (carry set). DEL rubs out the last character.
;----------------------------------------------------------------------------
INPUT_SIZE      = 32            ; room in input_buf
!zone prompt_input
prompt_input
        ldy input_max
        iny                     ; (room for the cursor too)
        jsr box_open
.draw   ldx #BOX_TEXT_ROW       ; show the answer so far
        jsr box_row_ptrs
        lda box_col             ; Y = column of the answer in the row:
        sec                     ; one space after the question
        sbc box_left
        tay
        iny
        ldx #0
-       cpx input_len
        bcs .cursor
        lda input_buf,x
        jsr petscii_to_screen
        jsr box_put
        inx
        bne -
.cursor lda #$a0                ; a reversed space marks where typing goes
        jsr box_put
        inx
-       cpx input_max           ; blank the rest
        bcs .key
        lda #$20
        jsr box_put
        inx
        bne -

.key    jsr wait_key
        cmp #KEY_RETURN
        beq .return
        cmp #KEY_STOP
        beq .cancel
        cmp #KEY_RESTORE
        beq .cancel
        cmp #KEY_DEL
        bne .char
        tya
        and #MOD_SHIFT
        bne .key                ; (SHIFT + INST does nothing here)
        lda input_len
        beq .key
        dec input_len
        jmp .draw
.char   jsr key_to_petscii      ; a character to add?
        bcs .key
        tax
        lda ctype,x
        cmp #CT_CHAR
        bne .key                ; control codes: no
        lda input_len
        cmp input_max
        bcs .key                ; full
        tay
        txa
        sta input_buf,y
        inc input_len
        jmp .draw

.return lda input_len
        beq .key                ; nothing typed yet
        jsr box_close
        clc
        rts
.cancel jsr box_close
        sec
        rts

input_buf       !fill INPUT_SIZE, 0
input_len       !byte 0
input_max       !byte 16
