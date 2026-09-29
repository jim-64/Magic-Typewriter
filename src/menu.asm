;============================================================================
; menu.asm - boxes in the middle of the screen: questions, messages and
; typed-in answers; the menus.
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
        jsr box_edge
        ldx #BOX_ROW+2          ; bottom edge
        lda #$6d                ; bottom left corner
        ldy #$7d                ; bottom right corner
        jsr box_edge

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

; box_edge - X = row, A = left corner, Y = right corner: a horizontal
; edge of the box (box_left, box_width, box_color)
box_edge
        sta .left_corner
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
        bne +
        lda input_empty_ok      ; nothing typed yet: not an answer (unless
        beq .key                ; the question allows it)
+       lda #0
        sta input_empty_ok
        jsr box_close
        clc
        rts
.cancel lda #0
        sta input_empty_ok
        jsr box_close
        sec
        rts

input_buf       !fill INPUT_SIZE, 0
input_len       !byte 0
input_max       !byte 16
input_empty_ok  !byte 0         ; 1 = RETURN with nothing typed is an
                                ; answer too (for the next question only)

;============================================================================
; Menus
;
; Every menu shows in the same panel in the middle of the screen, the size
; of the main menu: its title, a line, then a row for each item - its
; letter, its name and, for a setting, its value ("D WORDWRAP: ON").
; Pressing an item's letter, or clicking on its row, chooses it. X backs
; out one level; RUN/STOP, the left-arrow key, F1, the right mouse button
; or the menu icon close all the menus. The document is drawn again when
; they close.
;
; Menus are data (the tables are at the end of this section):
;   !word title             screen codes, 0 at the end
;   then for each item:
;   !byte letter            its letter as a screen code (1 = A, 24 = X)
;   !byte kind              MI_... below
;   !word name              screen codes, 0 at the end
;   !word what              a menu (MI_MENU), a setting (MI_SET) or a
;                           routine (MI_RUN, MI_DO); 0 for MI_EXIT
;   and !byte 0 after the last item.
; A setting is:
;   !word variable          where its value is kept
;   !byte count             how many values it has
;   !word values            the values (count bytes), in the order that
;                           choosing the item steps through them
;   !word names             the name of each value (count words, each the
;                           address of screen codes, 0 at the end)
;
; Zero page while a menu is drawn: zp_ptr and work (the box routines),
; zp_ptr2 (a text), ptr (a menu item), scr (a setting's variable) and clr
; (its lists). None of these is in use by anything else meanwhile.
;============================================================================
MI_MENU         = 1             ; opens another menu
MI_SET          = 2             ; a setting: steps to its next value
MI_RUN          = 3             ; runs a routine, then shows the menu again
MI_DO           = 4             ; closes the menus, then runs a routine
MI_EXIT         = 5             ; back one level

MENU_TOP        = 4             ; the panel: rows 4-19 ...
MENU_ROWS       = 16
MENU_LEFT       = 5             ; ... and columns 5-34
MENU_WIDTH      = 30
MENU_TITLE_ROW  = MENU_TOP + 1
MENU_ITEM_ROW   = MENU_TOP + 3  ; the first item's row
MENU_DEPTH      = 3             ; menus open at most at one time

menu_stack_lo   !fill MENU_DEPTH, 0 ; the open menus, the one shown last
menu_stack_hi   !fill MENU_DEPTH, 0
menu_depth      !byte 0
menu_ptr        !word 0         ; the menu shown
menu_count      !byte 0         ; its number of items

;----------------------------------------------------------------------------
; menu_open - RUN/STOP, RESTORE, F1, the menu icon or the right mouse
; button: the main menu. Returns when all the menus are closed and the
; document is on the screen again.
;----------------------------------------------------------------------------
!zone menu_open
menu_open
        lda #0
        sta menu_depth
        lda #<menu_main
        ldx #>menu_main
.push   ldy menu_depth          ; A/X = a menu to open over the others
        sta menu_stack_lo,y
        txa
        sta menu_stack_hi,y
        inc menu_depth
.show   jsr menu_draw
        jmp .key
.to_close
        jmp .close              ; (for branches that cannot reach)
.to_back
        jmp .back

.key    jsr wait_key
        cmp #KEY_STOP           ; the keys that close all the menus
        beq .to_close
        cmp #KEY_ARROW
        beq .to_close
        cmp #KEY_RESTORE
        beq .to_close
        cmp #KEY_F1
        beq .to_close
        cmp #KEY_MOUSE_R
        beq .to_close
        cmp #KEY_MOUSE_L
        beq .click
        cmp #KEY_X
        beq .to_back
        sta .code               ; an item's letter?
        ldx #0
-       cpx menu_count
        bcs .key                ; no
        jsr menu_item
        ldy #0
        lda (ptr),y             ; its letter (1-26) ...
        tay
        lda letter_keys-1,y     ; ... and that letter's key
        cmp .code
        beq .item
        inx
        bne -

.click  lda click_icon          ; the menu icon: close; other icons: nothing
        cmp #ICON_MENU
        beq .to_close
        cmp #ICON_NONE
        bne .key
        lda click_col           ; on an item's row, inside the panel?
        cmp #MENU_LEFT
        bcc .key
        cmp #MENU_LEFT+MENU_WIDTH
        bcs .key
        lda click_row
        sec
        sbc #MENU_ITEM_ROW
        bcc .key
        cmp menu_count
        bcs .key
        tax
        jsr menu_item

.item   ldy #1                  ; ptr = the item chosen: what kind?
        lda (ptr),y
        sta .kind
        ldy #4
        lda (ptr),y             ; what it opens, sets or runs
        sta .what
        iny
        lda (ptr),y
        sta .what+1
        lda .kind
        cmp #MI_MENU
        bne +
        lda .what               ; another menu
        ldx .what+1
        jmp .push
+       cmp #MI_SET
        bne +
        lda .what               ; a setting: its next value
        sta ptr2
        lda .what+1
        sta ptr2+1
        jsr set_next
        jmp .show
+       cmp #MI_RUN
        bne +
        jsr .call               ; a job that comes back to the menu
        jmp .show
+       cmp #MI_DO
        bne .back               ; (MI_EXIT)
        jsr .close              ; a job done with the menus closed
.call   jmp (.what)

.back   dec menu_depth          ; back one level
        beq .close
        jmp .show

.close  lda #0                  ; all closed: the document again, drawn
        sta menu_depth          ; afresh (settings may have changed how it
        sta top_known           ; looks: colors, word wrap)
        ldx cur_row
        jmp show_cursor_at

.code   !byte 0
.kind   !byte 0
.what   !word 0
!if <.what = $ff {
        !error "menu_open: .what straddles a page (6502 JMP () bug)"
}

; menu_item - X = an item's number: ptr = its entry (menu_ptr + 2 + 6*X).
; Keeps X.
!zone menu_item
menu_item
        txa
        asl
        sta .t                  ; 2X
        asl                     ; 4X
        clc
        adc .t                  ; 6X (at most 6*13: no carry)
        adc #2                  ; (past the title)
        clc
        adc menu_ptr
        sta ptr
        lda menu_ptr+1
        adc #0
        sta ptr+1
        rts
.t      !byte 0

;----------------------------------------------------------------------------
; menu_draw - the panel with the menu last opened
;----------------------------------------------------------------------------
!zone menu_draw
menu_draw
        ldx menu_depth
        lda menu_stack_lo-1,x
        sta menu_ptr
        lda menu_stack_hi-1,x
        sta menu_ptr+1
        sta zp_ptr2+1           ; the title
        lda menu_ptr
        sta zp_ptr2
        ldy #0
        lda (zp_ptr2),y
        sta .title
        iny
        lda (zp_ptr2),y
        sta .title+1
        lda .title
        ldx .title+1
        jsr panel_open

        ldx #0                  ; the items
.item   jsr menu_item
        ldy #0
        lda (ptr),y
        bne +
        stx menu_count          ; (the 0 after the last)
        rts
+       sta .letter
        iny
        lda (ptr),y
        sta .kind
        iny
        lda (ptr),y
        sta .name
        iny
        lda (ptr),y
        sta .name+1
        iny
        lda (ptr),y
        sta .what
        iny
        lda (ptr),y
        sta .what+1
        stx .i
        txa                     ; its row
        clc
        adc #MENU_ITEM_ROW
        tax
        jsr box_row_ptrs
        ldy #2                  ; its letter, a space, its name
        lda .letter
        jsr box_capitals
        jsr box_put
        iny
        lda .name
        ldx .name+1
        jsr box_print
        lda .kind               ; a setting: ": " and its value
        cmp #MI_SET
        bne .next
        lda #$3a                ; ":"
        jsr box_put
        iny
        sty .col
        lda .what
        sta ptr2
        lda .what+1
        sta ptr2+1
        jsr set_name            ; A/X = the value's name
        ldy .col
        jsr box_print
.next   ldx .i
        inx
        bne .item               ; (always)

.title  !word 0
.letter !byte 0
.kind   !byte 0
.name   !word 0
.what   !word 0
.i      !byte 0
.col    !byte 0

;----------------------------------------------------------------------------
; panel_open - an empty panel (MENU_TOP ... ) with a title (A/X, screen
; codes), centered, and a line under it. Sets box_left, box_width,
; box_color for box_row_ptrs / box_put / box_print.
;----------------------------------------------------------------------------
!zone panel_open
panel_open
        sta .title
        stx .title+1
        jsr readable_color
        sta box_color
        lda #MENU_LEFT
        sta box_left
        lda #MENU_WIDTH
        sta box_width
        ldx #MENU_TOP           ; the edges and the line under the title
        lda #$70
        ldy #$6e
        jsr box_edge
        ldx #MENU_TOP+2
        lda #$6b
        ldy #$73
        jsr box_edge
        ldx #MENU_TOP+MENU_ROWS-1
        lda #$6d
        ldy #$7d
        jsr box_edge
        ldx #MENU_TITLE_ROW     ; the other rows: sides, blank between
        jsr .blank
        ldx #MENU_ITEM_ROW
-       jsr .blank
        inx
        cpx #MENU_TOP+MENU_ROWS-1
        bcc -
        lda .title              ; the title, centered: its length ...
        sta zp_ptr2
        lda .title+1
        sta zp_ptr2+1
        ldy #0
-       lda (zp_ptr2),y
        beq +
        iny
        bne -
+       sty .len
        ldx #MENU_TITLE_ROW
        jsr box_row_ptrs
        lda #MENU_WIDTH         ; ... then (width - length) / 2
        sec
        sbc .len
        lsr
        tay
        lda .title
        ldx .title+1
        jmp box_print

; .blank - row X: the sides, spaces between. Keeps X.
.blank  stx .x
        jsr box_row_ptrs
        ldy #0
        lda #$5d
        jsr box_put
-       lda #$20
        jsr box_put
        cpy #MENU_WIDTH-1
        bcc -
        lda #$5d
        jsr box_put
        ldx .x
        rts

.title  !word 0
.len    !byte 0
.x      !byte 0

;----------------------------------------------------------------------------
; box_print - A/X = screen codes (0 at the end): put them at column Y of
; the row set by box_row_ptrs, letters as capitals. Y ends up after them.
;----------------------------------------------------------------------------
!zone box_print
box_print
        sta zp_ptr2
        stx zp_ptr2+1
        sty .col
        ldx #0
-       txa
        tay
        lda (zp_ptr2),y
        beq .done
        jsr box_capitals
        ldy .col
        jsr box_put
        sty .col
        inx
        bne -
.done   ldy .col
        rts
.col    !byte 0

;----------------------------------------------------------------------------
; Settings
;----------------------------------------------------------------------------

; set_fields - ptr2 = a setting: scr = its variable, set_count, clr = its
; values; Y = the place of the current value in the list (0 if it is not
; in it)
!zone set_fields
set_fields
        ldy #0
        lda (ptr2),y
        sta scr
        iny
        lda (ptr2),y
        sta scr+1
        iny
        lda (ptr2),y
        sta set_count
        iny
        lda (ptr2),y
        sta clr
        iny
        lda (ptr2),y
        sta clr+1
        ldy #0                  ; the current value ...
        lda (scr),y
        sta .v
-       lda (clr),y             ; ... in the list
        cmp .v
        beq +
        iny
        cpy set_count
        bcc -
        ldy #0
+       rts
.v      !byte 0
set_count       !byte 0

; set_name - ptr2 = a setting: A/X = the name of its current value
!zone set_name
set_name
        jsr set_fields
        tya
        asl
        sta .i
        ldy #5                  ; the names list
        lda (ptr2),y
        sta clr
        iny
        lda (ptr2),y
        sta clr+1
        ldy .i
        lda (clr),y
        pha
        iny
        lda (clr),y
        tax
        pla
        rts
.i      !byte 0

; set_next - ptr2 = a setting: step it to the next value in its list
; (after the last, back to the first)
!zone set_next
set_next
        jsr set_fields
        iny
        cpy set_count
        bcc +
        ldy #0
+       lda (clr),y
        ldy #0
        sta (scr),y
        rts

;----------------------------------------------------------------------------
; The jobs the menus run
;----------------------------------------------------------------------------

; menu_quit - Q: back to BASIC (asking first if there are changes)
menu_quit
        lda modified
        beq +
        lda #<msg_quit_unsaved
        ldx #>msg_quit_unsaved
        jsr prompt_yes_no
        bcs +
        rts
+       jmp quit

; not_yet - a menu item for a later phase
not_yet lda #<msg_not_yet
        ldx #>msg_not_yet
        jmp message_box

;----------------------------------------------------------------------------
; show_stats - the Stats item: characters, words, sentences and the room
; left, counted now and shown in the panel until a key is pressed.
;   characters: visible characters and line ends (codes do not count)
;   words:      runs of characters between spaces, shifted spaces and line
;               ends
;   sentences:  . ! or ? followed by a space, a line end or the end of the
;               text (a run like ... counts once)
;   free:       the room left in the buffer (the gap), and as a share of
;               the whole buffer ("12345 (33%)")
; The counts are 24-bit, ready for documents held in an REU (phase 9).
;----------------------------------------------------------------------------
!zone show_stats
show_stats
        lda #<t_stats           ; "counting" first: a big document takes a
        ldx #>t_stats           ; second or so
        jsr panel_open
        ldx #MENU_ITEM_ROW
        jsr box_row_ptrs
        ldy #2
        lda #<m_counting
        ldx #>m_counting
        jsr box_print
        jsr count_text

        lda #<t_stats           ; the results
        ldx #>t_stats
        jsr panel_open
        ldx #0
.line   stx .i
        txa                     ; row
        clc
        adc #MENU_ITEM_ROW
        tax
        jsr box_row_ptrs
        lda .i
        asl
        tax
        lda .labels,x
        pha
        lda .labels+1,x
        tax
        pla
        ldy #2
        jsr box_print           ; its name ...
        lda .i                  ; ... and its number, from column 14
        asl
        adc .i                  ; (3 bytes a count)
        tax
        lda st_counts,x
        sta num24
        lda st_counts+1,x
        sta num24+1
        lda st_counts+2,x
        sta num24+2
        jsr num24_text
        ldy #14
        lda #<num_text
        ldx #>num_text
        jsr box_print
        ldx .i
        inx
        cpx #4
        bcc .line

        ; After the room left (the last row, Y just after its number): its
        ; share of the whole buffer, " (33%)"
        sty .col                ; (num24_text uses Y)
        jsr free_percent
        jsr num24_text
        ldy .col
        lda #$20                ; " ("
        jsr box_put
        lda #$28
        jsr box_put
        lda #<num_text
        ldx #>num_text
        jsr box_print
        lda #$25                ; "%)"
        jsr box_put
        lda #$29
        jsr box_put

        lda reu_banks           ; with an REU: its size, two rows further
        beq .wait               ; down ("REU  512 KB")
        ldx #MENU_ITEM_ROW+5
        jsr box_row_ptrs
        ldy #2
        lda #<m_reu
        ldx #>m_reu
        jsr box_print
        lda reu_banks           ; banks of 64 KB
        sta num24
        lda #0
        sta num24+1
        sta num24+2
        ldx #6                  ; (times 64)
-       asl num24
        rol num24+1
        dex
        bne -
        jsr num24_text
        ldy #14
        lda #<num_text
        ldx #>num_text
        jsr box_print
        lda #<m_kb
        ldx #>m_kb
        jsr box_print
.wait   jmp wait_key            ; shown until a key is pressed

.labels !word m_characters, m_words, m_sentences, m_free
.i      !byte 0
.col    !byte 0

; count_text - count the characters, words and sentences into st_counts,
; and the room left
!zone count_text
count_text
        ldx #3*4-1              ; all counts 0
        lda #0
-       sta st_counts,x
        dex
        bpl -
        sta .in_word
        sta .ended
        lda #<BUF_START
        sta ptr
        lda #>BUF_START
        sta ptr+1
.loop   lda ptr                 ; at the gap? jump over it
        cmp gap_start
        bne +
        lda ptr+1
        cmp gap_start+1
        bne +
        lda gap_end
        sta ptr
        lda gap_end+1
        sta ptr+1
+       jsr ptr_at_end
        bcs .done
        ldy #0
        lda (ptr),y
        sta .b
        inc ptr
        bne +
        inc ptr+1
+       tax
        lda ctype,x
        cmp #CT_CHAR
        beq .char
        cmp #CT_EOL
        bne .loop               ; codes: nothing
        ldx #ST_CHARS           ; a line end: a character, and between
        jsr inc24               ; words
        jmp .between
.char   ldx #ST_CHARS
        jsr inc24
        lda .b
        cmp #$20                ; space and shifted space: between words
        beq .between
        cmp #$a0
        beq .between
        lda .in_word            ; in a word: a new one?
        bne +
        lda #1
        sta .in_word
        ldx #ST_WORDS
        jsr inc24
+       lda .b                  ; . ! ? end a sentence, if a space, a line
        cmp #$2e                ; end or the end of the text follows
        beq .mark
        cmp #$21
        beq .mark
        cmp #$3f
        beq .mark
        lda #0
        sta .ended
        jmp .loop
.mark   lda #1
        sta .ended
        jmp .loop
.between
        lda #0
        sta .in_word
        lda .ended
        bne +
        jmp .loop
+       lda #0
        sta .ended
        ldx #ST_SENTENCES
        jsr inc24
        jmp .loop
.done   lda .ended              ; the end of the text after . ! or ?
        beq +
        ldx #ST_SENTENCES
        jsr inc24
+       jsr gap_size            ; the room left
        lda work
        sta st_counts+ST_FREE
        lda work+1
        sta st_counts+ST_FREE+1
        rts
.b      !byte 0
.in_word !byte 0
.ended  !byte 0

ST_CHARS        = 0             ; (offsets in st_counts)
ST_WORDS        = 3
ST_SENTENCES    = 6
ST_FREE         = 9
st_counts       !fill 12, 0

; free_percent - num24 = the room left as a percentage of the whole buffer
; (rounded down): free * 100 / (BUF_END - BUF_START), with the math
; helpers in system.asm.
!zone free_percent
free_percent
        lda st_counts+ST_FREE   ; free * 100 (24 bits) ...
        sta math_num
        lda st_counts+ST_FREE+1
        sta math_num+1
        lda #100
        sta math_mul
        jsr mul_16x8
        lda #<(BUF_END - BUF_START) ; ... / the buffer's size
        sta math_div
        lda #>(BUF_END - BUF_START)
        sta math_div+1
        jsr div_24x16
        lda math_num            ; the answer (0-100)
        sta num24
        lda #0
        sta num24+1
        sta num24+2
        rts

; inc24 - one more in the 24-bit count at st_counts + X
inc24   inc st_counts,x
        bne +
        inc st_counts+1,x
        bne +
        inc st_counts+2,x
+       rts

;----------------------------------------------------------------------------
; num24_text - num24 (24 bits) as decimal screen codes in num_text, without
; leading zeros, 0 at the end (up to 8 digits)
;----------------------------------------------------------------------------
!zone num24_text
num24_text
        ldy #0                  ; where the next digit goes
        ldx #0                  ; which power of ten (10 000 000 first)
.digit  lda #0
        sta .d
-       lda num24               ; subtract it while it fits
        sec
        sbc .ten_lo,x
        sta .t
        lda num24+1
        sbc .ten_mid,x
        sta .t+1
        lda num24+2
        sbc .ten_hi,x
        bcc +
        sta num24+2
        lda .t+1
        sta num24+1
        lda .t
        sta num24
        inc .d
        bne -
+       lda .d                  ; a digit - unless it is a leading zero
        bne +
        cpy #0
        beq ++
+       ora #$30
        sta num_text,y
        iny
++      inx
        cpx #8
        bcc .digit
        cpy #0                  ; (the number 0: one digit)
        bne +
        lda #$30
        sta num_text
        iny
+       lda #0
        sta num_text,y
        rts
.ten_lo  !byte <10000000, <1000000, <100000, <10000, <1000, <100, <10, <1
.ten_mid !byte >10000000, >1000000, >100000, >10000, >1000, >100, >10, >1
.ten_hi  !byte ^10000000, ^1000000, ^100000, ^10000, ^1000, ^100, ^10, ^1
.d      !byte 0
.t      !word 0

num24           !byte 0, 0, 0
num_text        !fill 9, 0

t_stats         !scr "stats", 0
m_counting      !scr "counting...", 0
m_characters    !scr "characters", 0
m_words         !scr "words", 0
m_sentences     !scr "sentences", 0
m_free          !scr "free", 0
m_reu           !scr "reu", 0
m_kb            !scr " kb", 0


;----------------------------------------------------------------------------
; The menus (see "Menus" above for the layout)
;----------------------------------------------------------------------------
menu_main
        !word t_main
        !byte 1,  MI_MENU : !word n_load, menu_load
        !byte 2,  MI_MENU : !word n_save, menu_save
        !byte 3,  MI_MENU : !word n_print, menu_print
        !byte 4,  MI_SET  : !word n_wordwrap, set_wordwrap
        !byte 5,  MI_SET  : !word n_mode, set_mode
        !byte 6,  MI_SET  : !word n_markkey, set_markkey
        !byte 7,  MI_SET  : !word n_background, set_background
        !byte 8,  MI_SET  : !word n_textcolor, set_textcolor
        !byte 9,  MI_RUN  : !word n_stats, show_stats
        !byte 10, MI_RUN  : !word n_defaults, save_defaults
        !byte 17, MI_DO   : !word n_quit, menu_quit
        !byte 24, MI_EXIT : !word n_exit, 0
        !byte 0

menu_load
        !word t_load
        !byte 1,  MI_DO   : !word n_load, load_file
        !byte 2,  MI_SET  : !word n_format, set_load_format
        !byte 3,  MI_SET  : !word n_device, set_load_dev
        !byte 4,  MI_RUN  : !word n_directory, dir_load
        !byte 5,  MI_RUN  : !word n_command, cmd_load
        !byte 24, MI_EXIT : !word n_exit, 0
        !byte 0

menu_save
        !word t_save
        !byte 1,  MI_DO   : !word n_save, save_as
        !byte 2,  MI_SET  : !word n_format, set_save_format
        !byte 3,  MI_SET  : !word n_filetype, set_save_type
        !byte 4,  MI_SET  : !word n_device, set_save_dev
        !byte 5,  MI_RUN  : !word n_directory, dir_save
        !byte 6,  MI_RUN  : !word n_command, cmd_save
        !byte 24, MI_EXIT : !word n_exit, 0
        !byte 0

menu_print
        !word t_print
        !byte 1,  MI_DO   : !word n_print, not_yet
        !byte 2,  MI_SET  : !word n_toascii, set_print_ascii
        !byte 3,  MI_SET  : !word n_device, set_print_dev
        !byte 24, MI_EXIT : !word n_exit, 0
        !byte 0

; Settings: variable, count, values, names
set_wordwrap    !word wrap_on : !byte 2 : !word v_1_0, names_on_off
set_mode        !word edit_mode : !byte 2 : !word v_0_1, names_mode
set_markkey     !word mark_key : !byte 2 : !word v_1_0, names_markkey
set_background  !word text_bg : !byte 16 : !word v_colors, names_colors
set_textcolor   !word text_color : !byte 16 : !word v_colors, names_colors
set_load_format !word load_format : !byte 4 : !word v_colors, names_formats
set_load_dev    !word load_dev : !byte 8 : !word v_devices, names_devices
set_save_format !word save_format : !byte 4 : !word v_colors, names_formats
set_save_type   !word save_type : !byte 2 : !word v_0_1, names_types
set_save_dev    !word save_dev : !byte 8 : !word v_devices, names_devices
set_print_ascii !word print_ascii : !byte 2 : !word v_0_1, names_no_yes
set_print_dev   !word print_dev : !byte 4 : !word v_printers, names_printers

v_0_1           !byte 0, 1
v_1_0           !byte 1, 0
v_colors        !byte 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15
v_devices       !byte 8, 1, 9, 10, 11, 12, 13, 14       ; 1 = tape
v_printers      !byte 4, 5, 6, 7

names_on_off    !word n_on, n_off
names_mode      !word n_insert, n_overwrite
names_markkey   !word n_commodore, n_leftshift
names_colors    !word n_black, n_white, n_red, n_cyan, n_purple, n_green
                !word n_blue, n_yellow, n_orange, n_brown, n_lightred
                !word n_darkgrey, n_grey, n_lightgreen, n_lightblue
                !word n_lightgrey
names_formats   !word n_magic, n_petscii, n_ascii, n_speedscript
names_devices   !word n_8, n_tape, n_9, n_10, n_11, n_12, n_13, n_14
names_types     !word n_seq, n_prg
names_no_yes    !word n_no, n_yes
names_printers  !word n_4, n_5, n_6, n_7

; The key of each letter (A-Z), to find an item from its letter
letter_keys
        !byte 10, 28, 20, 18, 14, 21, 26, 29, 33, 34, 37, 42, 36 ; A-M
        !byte 39, 38, 41, 62, 17, 13, 22, 30, 31, 9, 23, 25, 12  ; N-Z

; Titles and names (screen codes; letters as small letters show as
; capitals in either character set)
t_main          !scr "magic typewriter", 0
t_load          !scr "load", 0
t_save          !scr "save", 0
t_print         !scr "print", 0
n_load          !scr "load", 0
n_save          !scr "save", 0
n_print         !scr "print", 0
n_wordwrap      !scr "wordwrap", 0
n_mode          !scr "mode", 0
n_markkey       !scr "mark key", 0
n_background    !scr "background", 0
n_textcolor     !scr "text color", 0
n_stats         !scr "stats", 0
n_defaults      !scr "save defaults", 0
n_quit          !scr "quit magic typewriter", 0
n_exit          !scr "exit menu", 0
n_format        !scr "format", 0
n_device        !scr "device", 0
n_directory     !scr "disk directory", 0
n_command       !scr "disk command", 0
n_filetype      !scr "file type", 0
n_toascii       !scr "convert to ascii", 0
n_ascii         !scr "ascii", 0
n_on            !scr "on", 0
n_off           !scr "off", 0
n_insert        !scr "insert", 0
n_overwrite     !scr "overwrite", 0
n_commodore     !scr "commodore", 0
n_leftshift     !scr "left shift", 0
n_black         !scr "black", 0
n_white         !scr "white", 0
n_red           !scr "red", 0
n_cyan          !scr "cyan", 0
n_purple        !scr "purple", 0
n_green         !scr "green", 0
n_blue          !scr "blue", 0
n_yellow        !scr "yellow", 0
n_orange        !scr "orange", 0
n_brown         !scr "brown", 0
n_lightred      !scr "light red", 0
n_darkgrey      !scr "dark grey", 0
n_grey          !scr "grey", 0
n_lightgreen    !scr "light green", 0
n_lightblue     !scr "light blue", 0
n_lightgrey     !scr "light grey", 0
n_magic         !scr "magic", 0
n_petscii       !scr "petscii", 0
n_speedscript   !scr "speedscript", 0
n_tape          !scr "tape", 0
n_seq           !scr "seq", 0
n_prg           !scr "prg", 0
n_no            !scr "no", 0
n_yes           !scr "yes", 0
n_4             !scr "4", 0
n_5             !scr "5", 0
n_6             !scr "6", 0
n_7             !scr "7", 0
n_8             !scr "8", 0
n_9             !scr "9", 0
n_10            !scr "10", 0
n_11            !scr "11", 0
n_12            !scr "12", 0
n_13            !scr "13", 0
n_14            !scr "14", 0

;============================================================================
; petscii_to_screen - A = PETSCII code, returns A = screen code (not
; reversed) and carry clear. For control codes, which print nothing,
; returns carry set.
;
; (It lives here, not in editor.asm, because the disk code uses it while
; the KERNAL ROM is switched in - see io_begin in fileio.asm.)
;
;   PETSCII        screen code
;   $20-$3f   ->   $20-$3f    space, digits, punctuation
;   $40-$5f   ->   $00-$1f    @, letters, [ pound ] up-arrow left-arrow
;   $60-$7f   ->   $40-$5f    (same characters as $c0-$df)
;   $a0-$bf   ->   $60-$7f    C= graphics
;   $c0-$fe   ->   $40-$7e    SHIFT letters and graphics
;   $ff       ->   $5e        pi
;   $00-$1f, $80-$9f          control codes
;============================================================================
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
