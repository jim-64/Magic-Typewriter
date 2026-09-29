;============================================================================
; editor.asm - text buffer, cursor, typing, drawing the screen
;
; This file runs at $e000, in the RAM under the KERNAL ROM (see the memory
; map in main.asm). Its code and variables can only be used while the
; KERNAL ROM is switched out - that is, always, except between io_begin
; and io_end in fileio.asm.
;
; THE TEXT BUFFER
; The document is kept exactly as it is in a PETSCII file: one byte per
; character, lines ending in CR ($0d), color and reverse codes in between.
; It lives in a "gap buffer" from BUF_START to BUF_END:
;
;   BUF_START      gap_start        gap_end          text_end      BUF_END
;   | text before   |  (free space)  | text after     | clipboard   |
;   | the cursor    |                | the cursor     |             |
;
; The cursor is always at the gap. Typing stores a byte at gap_start and
; moves gap_start up; deleting to the left moves it down. Moving the cursor
; moves bytes from one side of the gap to the other. Nothing else in the
; buffer has to move, which is what makes this fast on a 6502.
;
; Positions in the document are kept as "offsets": the number of bytes
; from the start of the text, not counting the gap. An offset stays right
; however the gap moves. set_ptr turns an offset into an address.
;
; VISIBLE AND INVISIBLE BYTES
; Characters and line ends take a place on the screen. Color codes, RVS
; ON/OFF and other control codes are invisible: they only change how the
; characters after them look (see CLAUDE.md, "Colors and Reverse").
; The cursor moves over visible places only, and normally sits just after
; any codes that come before the next visible byte, so typed text takes
; the color in effect there. The ctype table says what each byte is.
;
; THE SCREEN
; Row 0 shows the document from "the top" (row_off[0]). For each screen
; row we remember where it starts (offset), the color and reverse state
; there, and how many cursor places it has. One extra row, below the
; screen, is measured but not drawn.
;
; How the text is split into rows (wrap_on, a setting):
; - A row takes up to 40 characters. A line end needs a cursor place of
;   its own, so a line of exactly 40 characters goes on to a second row.
; - Word wrap on: if the line goes on past 40 characters, the row ends
;   after its last space and the word that did not fit starts the next
;   row; a word longer than 40 characters is cut at 40.
; - Word wrap off: the row is cut after 40 characters, even in the middle
;   of a word, like the BASIC screen.
; redraw_from and row_next both follow these rules, and must stay the
; same. The text itself never changes: wrapping is only how it is shown.
;============================================================================

BUF_START       = $4000         ; the text buffer ...
BUF_END         = $d000         ; ... up to here (BASIC ROM banked out)
ROWS            = 25            ; screen rows
MROWS           = 26            ; rows we keep track of: the screen + 1

; (The editor's zero page, gap_start and so on, is listed in main.asm.)

; ctype values: what a byte of text is
CT_CHAR         = $80           ; a character
CT_EOL          = $81           ; a line end: CR, SHIFT+CR
CT_RVSON        = $82           ; RVS ON
CT_RVSOFF       = $83           ; RVS OFF
CT_OTHER        = $84           ; any other control code (invisible, no effect)
                                ; 0-15: a color code; the value is the color

MODE_INSERT     = 0
MODE_OVERWRITE  = 1
MARK_LSHIFT     = 0             ; the mark key (setting): left SHIFT ...
MARK_CBM        = 1             ; ... or C=

CURSOR_INSERT   = $79           ; screen code 121: lower 3/8 block

;----------------------------------------------------------------------------
; Editor variables (the big tables are at the end of main.asm)
;----------------------------------------------------------------------------
edit_mode       !byte MODE_INSERT ; insert or overwrite (setting, F7)
mark_key        !byte MARK_CBM  ; setting (default C=: left SHIFT can't
                                ; mark up/left in VICE - see CLAUDE.md)
modified        !byte 0         ; 1 = changed since loaded or saved
wrap_on         !byte 1         ; setting: 1 = word wrap, 0 = rows cut at
                                ; 40 characters (main menu, D)
cur_row         !byte 0         ; cursor place on the screen
cur_col         !byte 0
cur_color       !byte 0         ; typing color at the cursor
cur_rvs         !byte 0         ; $80 = reverse on at the cursor
want_col        !byte 0         ; column to aim for when moving up/down
eof_row         !byte 0         ; screen row holding the end of the text,
                                ; $ff if it is below the screen
off             !word 0         ; an offset (argument / result)

;============================================================================
; Setting up
;============================================================================

; editor_init - an empty document and a clean screen.
!zone editor_init
editor_init
        jsr init_ctype
        ldx #0                  ; scrcode: each byte's screen code, so
-       txa                     ; drawing needs only a table look-up
        jsr petscii_to_screen
        sta scrcode,x
        inx
        bne -
        lda #<BUF_END           ; no clipboard yet: the text may use all
        sta text_end            ; of the buffer
        lda #>BUF_END
        sta text_end+1
        ldx system_type
        lda tab_blink_frames,x
        sta blink_frames
        jsr empty_buffer
        jsr redraw_all
        jsr locate_cursor
        jmp cursor_show

; empty_buffer - no text, the top of the screen at the start.
empty_buffer
        lda #<BUF_START
        sta gap_start
        lda #>BUF_START
        sta gap_start+1
        lda text_end            ; (the clipboard above stays)
        sta gap_end
        lda text_end+1
        sta gap_end+1
        lda #0
        sta modified
        sta sel_on
        sta color_count
        sta color_count+1
        ; (falls into empty_view)

; empty_view - the top of the screen at the start of the text.
empty_view
        lda #0
        sta want_col
        sta row_off_lo          ; top = offset 0
        sta row_off_hi
        sta row_rvs
        lda text_color          ; the default text color, reverse off
        sta row_color
        lda #1                  ; (a state set_top_ptr can work from)
        sta top_known
        rts

; gap_to_start - put the cursor at the start of the text by copying all of
; it to the end of the buffer in one go (used after loading, when the
; text is all before the gap).
!zone gap_to_start
gap_to_start
        sec                     ; all of the text: from BUF_START up to
        lda gap_start           ; gap_start ...
        sbc #<BUF_START
        sta blk_count
        lda gap_start+1
        sbc #>BUF_START
        sta blk_count+1
        lda gap_start
        sta ptr
        lda gap_start+1
        sta ptr+1
        lda gap_end             ; ... to just below gap_end
        sta ptr2
        lda gap_end+1
        sta ptr2+1
        jsr block_copy_back     ; (leaves ptr2 where it now starts)
        lda ptr2
        sta gap_end
        lda ptr2+1
        sta gap_end+1
        lda #<BUF_START
        sta gap_start
        lda #>BUF_START
        sta gap_start+1
        rts

; init_ctype - fill in the ctype table (256 bytes, one per byte value).
!zone init_ctype
init_ctype
        ldx #0
-       txa
        and #$7f                ; $00-$1f and $80-$9f are control codes
        cmp #$20
        lda #CT_CHAR
        bcs +
        lda #CT_OTHER
+       sta ctype,x
        inx
        bne -
        lda #CT_EOL
        sta ctype+$0d           ; RETURN
        sta ctype+$8d           ; SHIFT + RETURN
        lda #CT_RVSON
        sta ctype+$12
        lda #CT_RVSOFF
        sta ctype+$92
        ldx #15                 ; the 16 color codes
-       ldy color_codes,x
        txa
        sta ctype,y
        dex
        bpl -
        rts

;============================================================================
; Positions
;============================================================================

; get_cursor_off - work = the cursor's offset (= length of the text before
; the gap).
!zone get_cursor_off
get_cursor_off
        sec
        lda gap_start
        sbc #<BUF_START
        sta work
        lda gap_start+1
        sbc #>BUF_START
        sta work+1
        rts

; set_ptr - ptr = the address of offset "off". The cursor's own offset
; gives gap_start.
!zone set_ptr
set_ptr
        jsr get_cursor_off      ; work = text before the gap
        lda off+1
        cmp work+1
        bcc .before
        bne .after
        lda off
        cmp work
        bcc .before
        beq .before
.after  sec                     ; after the gap: gap_end + (off - work)
        lda off
        sbc work
        sta ptr
        lda off+1
        sbc work+1
        sta ptr+1
        clc
        lda ptr
        adc gap_end
        sta ptr
        lda ptr+1
        adc gap_end+1
        sta ptr+1
        rts
.before clc                     ; before the gap: BUF_START + off
        lda off
        adc #<BUF_START
        sta ptr
        lda off+1
        adc #>BUF_START
        sta ptr+1
        rts

; ptr_to_off - off = the offset of the address in ptr.
!zone ptr_to_off
ptr_to_off
        lda ptr+1
        cmp gap_start+1
        bcc .before
        bne .after
        lda ptr
        cmp gap_start
        bcc .before
        beq .before
.after  sec                     ; after the gap: ptr - gap_end + text before
        lda ptr
        sbc gap_end
        sta off
        lda ptr+1
        sbc gap_end+1
        sta off+1
        jsr get_cursor_off
        clc
        lda off
        adc work
        sta off
        lda off+1
        adc work+1
        sta off+1
        rts
.before sec
        lda ptr
        sbc #<BUF_START
        sta off
        lda ptr+1
        sbc #>BUF_START
        sta off+1
        rts

; text_len - work = the length of the whole text.
!zone text_len
text_len
        jsr get_cursor_off      ; before the gap ...
        sec                     ; ... plus after it: text_end - gap_end
        lda text_end
        sbc gap_end
        tax
        lda text_end+1
        sbc gap_end+1
        tay
        txa
        clc
        adc work
        sta work
        tya
        adc work+1
        sta work+1
        rts

; gap_at_end - carry set if there is no text after the gap (gap_end has
; reached text_end).
gap_at_end
        lda gap_end+1
        cmp text_end+1
        bne +
        lda gap_end
        cmp text_end
+       rts

; ptr_at_end - carry set if ptr has reached the end of the text.
ptr_at_end
        lda ptr+1
        cmp text_end+1
        bne +
        lda ptr
        cmp text_end
+       rts

; is_visible - A = a byte of text. Carry clear if it takes a place on the
; screen (a character or a line end), set if it is an invisible code.
; Keeps Y.
!zone is_visible
is_visible
        tax
        lda ctype,x
        sec
        sbc #CT_CHAR            ; CT_CHAR -> 0, CT_EOL -> 1, the rest >= 2
        cmp #2
        rts

;============================================================================
; Moving the gap (the cursor)
;============================================================================

; gap_right - move one byte from after the gap to before it.
; Returns the byte in A; carry set if there was none (end of the text).
!zone gap_right
gap_right
        jsr gap_at_end
        bcs .end                ; nothing after the gap
        ldy #0
        lda (gap_end),y
        sta (gap_start),y
        inc gap_start
        bne +
        inc gap_start+1
+       inc gap_end
        bne +
        inc gap_end+1
+       clc
.end    rts

; gap_left - move one byte from before the gap to after it.
; Returns the byte in A; carry set if there was none (start of the text).
!zone gap_left
gap_left
        lda gap_start
        cmp #<BUF_START
        bne +
        lda gap_start+1
        cmp #>BUF_START
        bne +
        sec
        rts
+       lda gap_start
        bne +
        dec gap_start+1
+       dec gap_start
        lda gap_end
        bne +
        dec gap_end+1
+       dec gap_end
        ldy #0
        lda (gap_start),y
        sta (gap_end),y
        clc
        rts

; skip_codes - move the cursor forward over invisible codes, so it sits
; just before the next visible byte (or at the end of the text).
!zone skip_codes
skip_codes
-       jsr gap_at_end
        bcs +
        ldy #0
        lda (gap_end),y
        jsr is_visible
        bcc +
        jsr gap_right
        jmp -
+       rts

; move_right - one place right. Carry set if at the end of the text.
!zone move_right
move_right
-       jsr gap_right
        bcs .end
        jsr is_visible
        bcs -                   ; an invisible code: keep going
        jsr skip_codes
        clc
.end    rts

; move_left - one place left. Carry set if at the start of the text.
!zone move_left
move_left
-       jsr gap_left
        bcs .start
        jsr is_visible
        bcs -                   ; an invisible code: keep going
        clc
        rts
.start  jsr skip_codes          ; nothing visible before it: put the codes
        sec                     ; back where they were
        rts

; move_gap_to - move the cursor to offset "off": the bytes between the
; cursor and there move across the gap, in one block copy.
!zone move_gap_to
move_gap_to
        jsr get_cursor_off      ; work = the cursor now
        sec                     ; how far to the right?
        lda off
        sbc work
        sta blk_count
        lda off+1
        sbc work+1
        sta blk_count+1
        bcc .left               ; (to the left)
        ora blk_count
        beq .done               ; there already
        lda gap_end             ; right: bytes from after the gap go to
        sta ptr                 ; before it
        lda gap_end+1
        sta ptr+1
        lda gap_start
        sta ptr2
        lda gap_start+1
        sta ptr2+1
        jsr block_copy_fwd
        lda ptr
        sta gap_end
        lda ptr+1
        sta gap_end+1
        lda ptr2
        sta gap_start
        lda ptr2+1
        sta gap_start+1
.done   rts
.left   sec                     ; left: bytes from before the gap go to
        lda work                ; after it
        sbc off
        sta blk_count
        lda work+1
        sbc off+1
        sta blk_count+1
        lda gap_start
        sta ptr
        lda gap_start+1
        sta ptr+1
        lda gap_end
        sta ptr2
        lda gap_end+1
        sta ptr2+1
        jsr block_copy_back
        lda ptr
        sta gap_start
        lda ptr+1
        sta gap_start+1
        lda ptr2
        sta gap_end
        lda ptr2+1
        sta gap_end+1
        rts

;============================================================================
; Tidying codes
;============================================================================

; cleanup - before the cursor leaves a place, remove codes there that have
; no effect: a color code overridden by the next one, a color the text had
; already, an RVS ON directly followed by RVS OFF, and so on. Only the run
; of codes between the visible bytes on either side of the cursor is
; looked at. What that run does in the end is kept; at the end of the text
; the run does nothing at all, so its color and RVS codes go.
; Other control codes are always kept. Carry set if anything was removed.
!zone cleanup
cleanup
        jsr skip_codes          ; the whole run now ends at the cursor

        ; Walk back to the start of the run; note what kinds of codes it has.
        lda gap_start
        sta ptr
        lda gap_start+1
        sta ptr+1
        lda #0
        sta .kinds              ; bit 0: color codes, bit 1: RVS codes
.back   lda ptr
        cmp #<BUF_START
        bne +
        lda ptr+1
        cmp #>BUF_START
        beq .run_start
+       lda ptr
        bne +
        dec ptr+1
+       dec ptr
        ldy #0
        lda (ptr),y
        tax
        lda ctype,x
        bpl .color              ; 0-15
        cmp #CT_OTHER
        beq .back
        cmp #CT_RVSON
        beq .rvs
        cmp #CT_RVSOFF
        beq .rvs
        inc ptr                 ; visible: the run starts after it
        bne .run_start
        inc ptr+1
        bne .run_start          ; (always)
.color  lda .kinds
        ora #1
        sta .kinds
        bne .back
.rvs    lda .kinds
        ora #2
        sta .kinds
        bne .back

.run_start
        lda .kinds
        bne +
        clc                     ; no color or RVS codes: nothing to do
        rts
+       lda ptr                 ; remember where the run starts
        sta .start
        lda ptr+1
        sta .start+1
        jsr color_before        ; the state just before the run
        sta .color0
        jsr rvs_before
        sta .rvs0

        ; Find the last color code and the last RVS code in the run: they
        ; decide what the run does. (0 = none; the buffer is above $4000.)
        lda #0
        sta .last_color+1
        sta .last_rvs+1
.find   lda ptr
        cmp gap_start
        bne +
        lda ptr+1
        cmp gap_start+1
        beq .decide
+       ldy #0
        lda (ptr),y
        tax
        lda ctype,x
        bpl .is_color
        cmp #CT_RVSON
        beq .is_rvs
        cmp #CT_RVSOFF
        beq .is_rvs
        bne .next
.is_color
        lda ptr
        sta .last_color
        lda ptr+1
        sta .last_color+1
        bne .next
.is_rvs lda ptr
        sta .last_rvs
        lda ptr+1
        sta .last_rvs+1
.next   inc ptr
        bne .find
        inc ptr+1
        bne .find               ; (always)

.decide ; Keep the last color code only if it changes the color, and the
        ; last RVS code only if it changes reverse - and neither at the end
        ; of the text.
        lda #0
        sta .keep_color
        sta .keep_rvs
        jsr gap_at_end
        bcs .compact            ; end of the text: keep neither
        lda .last_color+1
        beq +
        sta ptr+1
        lda .last_color
        sta ptr
        ldy #0
        lda (ptr),y
        tax
        lda ctype,x             ; its color
        cmp .color0
        beq +
        inc .keep_color
+       lda .last_rvs+1
        beq .compact
        sta ptr+1
        lda .last_rvs
        sta ptr
        ldy #0
        lda (ptr),y
        tax
        lda ctype,x
        ldx #0                  ; RVS OFF -> 0
        cmp #CT_RVSON
        bne +
        ldx #$80                ; RVS ON -> $80
+       cpx .rvs0
        beq .compact
        inc .keep_rvs

.compact ; Copy the run onto itself, leaving out the codes that go.
        lda .start
        sta ptr                 ; ptr reads ...
        sta ptr2                ; ... ptr2 writes
        lda .start+1
        sta ptr+1
        sta ptr2+1
.copy   lda ptr
        cmp gap_start
        bne +
        lda ptr+1
        cmp gap_start+1
        beq .done
+       ldy #0
        lda (ptr),y
        sta .byte
        tax
        lda ctype,x
        bpl .c_color
        cmp #CT_RVSON
        beq .c_rvs
        cmp #CT_RVSOFF
        beq .c_rvs
        bne .keep               ; other codes stay
.c_color
        lda .keep_color
        beq .drop_c
        lda ptr                 ; keep only the last color code
        cmp .last_color
        bne .drop_c
        lda ptr+1
        cmp .last_color+1
        beq .keep
.drop_c jsr color_gone          ; a color code goes
        jmp .skip
.c_rvs  lda .keep_rvs
        beq .skip
        lda ptr
        cmp .last_rvs
        bne .skip
        lda ptr+1
        cmp .last_rvs+1
        bne .skip
.keep   lda .byte
        ldy #0
        sta (ptr2),y
        inc ptr2
        bne .skip
        inc ptr2+1
.skip   inc ptr
        bne .copy
        inc ptr+1
        bne .copy               ; (always)

.done   lda ptr2                ; the run may be shorter now
        cmp gap_start
        bne +
        lda ptr2+1
        cmp gap_start+1
        bne +
        clc                     ; nothing removed
        rts
+       lda ptr2
        sta gap_start
        lda ptr2+1
        sta gap_start+1
        sec
        rts

.kinds          !byte 0
.start          !word 0
.color0         !byte 0
.rvs0           !byte 0
.last_color     !word 0
.last_rvs       !word 0
.keep_color     !byte 0
.keep_rvs       !byte 0
.byte           !byte 0

; color_before - A = the color in effect just before address ptr (which
; must be at or before the cursor): the last color code before it, or the
; default text color. Keeps ptr.
; (With no color codes in the text at all, that is the default text color
; at once - no need to look back through a big document.)
!zone color_before
color_before
        lda color_count
        ora color_count+1
        beq .default
        lda ptr
        sta ptr2
        lda ptr+1
        sta ptr2+1
-       lda ptr2
        cmp #<BUF_START
        bne +
        lda ptr2+1
        cmp #>BUF_START
        beq .default
+       lda ptr2
        bne +
        dec ptr2+1
+       dec ptr2
        ldy #0
        lda (ptr2),y
        tax
        lda ctype,x
        bmi -
        rts                     ; A = the color
.default
        lda text_color
        rts

;----------------------------------------------------------------------------
; Counting the color codes in the text. color_before needs no search when
; there are none. Every byte put into the text goes through insert_byte or
; insert_after, and every code taken out through take_byte or cleanup;
; they keep the count. After loading, count_colors counts them all.
;----------------------------------------------------------------------------
color_count     !word 0

; count_color - A = a byte put into the text: one more if it is a color
; code. Keeps A.
count_color
        pha
        tax
        lda ctype,x
        bmi +
        inc color_count
        bne +
        inc color_count+1
+       pla
        rts

; uncount_color - A = a byte taken out of the text: one fewer if it is a
; color code. Keeps A.
uncount_color
        pha
        tax
        lda ctype,x
        bmi +
        jsr color_gone
+       pla
        rts

; color_gone - one color code fewer (never below 0)
color_gone
        lda color_count
        ora color_count+1
        beq +
        lda color_count
        bne ++
        dec color_count+1
++      dec color_count
+       rts

; count_colors - count all the color codes in the text
!zone count_colors
count_colors
        lda #0
        sta color_count
        sta color_count+1
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
        jsr count_color
        inc ptr
        bne .loop
        inc ptr+1
        jmp .loop
.done   rts

; rvs_before - A = $80 if reverse is on just before address ptr (at or
; before the cursor), else 0. A line end turns reverse off. Keeps ptr.
!zone rvs_before
rvs_before
        lda ptr
        sta ptr2
        lda ptr+1
        sta ptr2+1
-       lda ptr2
        cmp #<BUF_START
        bne +
        lda ptr2+1
        cmp #>BUF_START
        beq .off
+       lda ptr2
        bne +
        dec ptr2+1
+       dec ptr2
        ldy #0
        lda (ptr2),y
        tax
        lda ctype,x
        cmp #CT_RVSON
        beq .on
        cmp #CT_RVSOFF
        beq .off
        cmp #CT_EOL
        beq .off
        bne -
.on     lda #$80
        rts
.off    lda #0
        rts

;============================================================================
; Finding rows
;============================================================================

; line_start - ptr = an address before the gap. Moves ptr back to the
; start of the line holding the byte at ptr: just after the line end before
; it, or the start of the text.
!zone line_start
line_start
-       lda ptr
        cmp #<BUF_START
        bne +
        lda ptr+1
        cmp #>BUF_START
        beq .done
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
        inc ptr                 ; the line starts after the line end
        bne .done
        inc ptr+1
.done   rts

; row_next - ptr = the start of a screen row (an address; it may be at the
; gap). Walks over the row, split the way redraw_from splits rows, and
; returns ptr = the start of the next row. Carry set if the text ends in
; this row, so there is no next row.
; (For speed it checks one address per byte: .seg, the end of the stretch
; of text it is in - the gap, or the end of the text.)
!zone row_next
row_next
        lda #0
        sta .chars
        sta .brk_col
        jsr .stretch
.loop   lda ptr                 ; the end of the stretch?
        cmp .seg
        bne .byte
        lda ptr+1
        cmp .seg+1
        bne .byte
        lda .seg                ; the end of the text: this row is the last
        cmp text_end
        bne +
        lda .seg+1
        cmp text_end+1
        beq .end                ; (carry set: equal)
+       jsr .stretch            ; the gap: jump over it
        jmp .loop
.byte   ldy #0
        lda (ptr),y
        inc ptr
        bne +
        inc ptr+1
+       tax
        lda ctype,x
        cmp #CT_EOL
        beq .next               ; a line end ends the row
        cmp #CT_CHAR
        bne .loop               ; codes take no place
        inc .chars
        lda wrap_on             ; word wrap: after a space the row may end
        beq +
        cpx #$20
        bne +
        lda .chars
        sta .brk_col
        lda ptr
        sta .brk
        lda ptr+1
        sta .brk+1
+       lda .chars
        cmp #40
        bcc .loop
        lda .brk_col            ; full: it ends after its last space ...
        beq .next               ; (no space, or wrap off: cut at 40)
        cmp #40
        bcs .next               ; (the 40th character is the space)
        lda .brk
        sta ptr
        lda .brk+1
        sta ptr+1
.next   clc
.end    rts

; .stretch - if ptr is at the gap, jump over it. .seg = where the stretch
; of text that ptr is in ends: the gap, or the end of the text.
.stretch
        lda ptr
        cmp gap_start
        bne +
        lda ptr+1
        cmp gap_start+1
        bne +
        lda gap_end
        sta ptr
        lda gap_end+1
        sta ptr+1
+       lda ptr+1               ; before the gap?
        cmp gap_start+1
        bcc .before
        bne .after
        lda ptr
        cmp gap_start
        bcc .before
.after  lda text_end
        sta .seg
        lda text_end+1
        sta .seg+1
        rts
.before lda gap_start
        sta .seg
        lda gap_start+1
        sta .seg+1
        rts

.chars  !byte 0
.brk_col !byte 0
.brk    !word 0
.seg    !word 0

; find_row_start - ptr = the start of the screen row that holds the place
; at address "limit" (which is at or before the cursor, so before the
; gap): the last row start at or before it.
!zone find_row_start
find_row_start
        lda limit
        sta ptr
        lda limit+1
        sta ptr+1
        jsr ptr_to_off          ; the limit as an offset
        lda off
        sta .lim
        lda off+1
        sta .lim+1
        jsr line_start          ; the line holding it
.row    lda ptr                 ; a row starts here
        sta .start
        lda ptr+1
        sta .start+1
        jsr row_next
        bcs .found              ; the text ends in it: this is the one
        jsr ptr_to_off          ; the next row starts at "off": after the
        lda .lim                ; limit?
        cmp off
        lda .lim+1
        sbc off+1
        bcs .row                ; no: on to the next row
.found  lda .start
        sta ptr
        lda .start+1
        sta ptr+1
        rts
.start  !word 0
.lim    !word 0

limit           !word 0         ; argument of find_row_start

; set_top_ptr - make the screen row that starts at address ptr (at or
; before the cursor) the top row: its offset, and the color and reverse
; state there.
; The color there is set by the last color code before it. Looking back
; for that can take a second in a big document, so where it can, this
; works it out from the old top row instead (whose state is known, unless
; top_known is 0): only the codes between the old top and the new one
; matter. (With no color codes in the text at all, color_before is quick.)
!zone set_top_ptr
set_top_ptr
        lda ptr                 ; the new top
        sta .new
        lda ptr+1
        sta .new+1
        jsr ptr_to_off
        lda off
        sta .off
        lda off+1
        sta .off+1
        jsr rvs_before          ; reverse: from the start of the line
        sta .rvs
        lda top_known
        beq .look_back
        lda color_count
        ora color_count+1
        beq .look_back          ; (quick then anyway)
        lda row_off_lo          ; the old top, as an address
        sta off
        lda row_off_hi
        sta off+1
        jsr set_ptr
        lda .off                ; new top before the old one?
        cmp row_off_lo
        lda .off+1
        sbc row_off_hi
        bcs .down
        lda ptr                 ; up: codes from the new top to the old one
        sta .stop               ; don't change the color at the new top;
        lda ptr+1               ; if there are none, it is the old top's
        sta .stop+1
        lda .new
        sta ptr
        lda .new+1
        sta ptr+1
        jsr .colors
        cmp #$ff
        bne .look_back          ; there are: look back after all
        lda row_color
        jmp .store
.down   lda .new                ; down: the old top's color, changed by the
        sta .stop               ; codes between it and the new top
        lda .new+1
        sta .stop+1
        jsr .colors
        cmp #$ff
        bne .store
        lda row_color
        jmp .store
.look_back
        lda .new
        sta ptr
        lda .new+1
        sta ptr+1
        jsr color_before
.store  sta row_color
        lda .rvs
        sta row_rvs
        lda .off
        sta row_off_lo
        lda .off+1
        sta row_off_hi
        lda .new                ; (ptr back as it came)
        sta ptr
        lda .new+1
        sta ptr+1
        lda #1
        sta top_known
        rts

; .colors - look at the bytes from ptr up to address .stop (jumping the
; gap): A = the color of the last color code among them, $ff if none.
.colors lda #$ff
        sta .last
-       lda ptr
        cmp .stop
        bne +
        lda ptr+1
        cmp .stop+1
        beq .c_done
+       lda ptr                 ; at the gap? jump over it
        cmp gap_start
        bne +
        lda ptr+1
        cmp gap_start+1
        bne +
        lda gap_end
        sta ptr
        lda gap_end+1
        sta ptr+1
        jmp -
+       ldy #0
        lda (ptr),y
        tax
        lda ctype,x
        bmi +
        sta .last
+       inc ptr
        bne -
        inc ptr+1
        jmp -
.c_done lda .last
        rts

.new    !word 0
.off    !word 0
.rvs    !byte 0
.stop   !word 0
.last   !byte 0

top_known       !byte 1         ; 1 = row_color/row_rvs of the top row are
                                ; right (see set_top_ptr)

; rows_back - move the top of the screen up A rows (1-255), or as far as
; the start of the text allows. Does not redraw. Carry set if it could not
; move at all (the top is the start of the text already). The top must be
; at or before the cursor.
; It works back a line at a time: it counts the rows of the line before
; the top that lie above the top. If they are enough, the new top is one
; of them; if not, it takes them all and goes on with the line before.
; (So a long paragraph is walked once, not once for every row.)
!zone rows_back
rows_back
        sta .need
        lda row_off_lo          ; .top: how far up it has got so far (the
        sta .top                ; top row itself stays as it is until the
        lda row_off_hi          ; end: set_top_ptr works from it)
        sta .top+1
        ora .top
        bne .line
        sec                     ; the start of the text already
        rts
.line   lda .top
        sta off
        lda .top+1
        sta off+1
        ora .top
        bne +
        jmp .at_start           ; reached the start of the text
+       jsr set_ptr
        lda ptr                 ; the line holding the byte before the top
        bne +
        dec ptr+1
+       dec ptr
        jsr line_start
        lda ptr
        sta .lstart
        lda ptr+1
        sta .lstart+1
        lda #0                  ; count its rows above the top, noting the
        sta .k                  ; starts of the last RING of them
        sta .k+1
        sta .ri
-       ldx .ri                 ; (a row starts at ptr)
        lda ptr
        sta .ring_lo,x
        lda ptr+1
        sta .ring_hi,x
        inx
        cpx #RING
        bcc +
        ldx #0
+       stx .ri
        inc .k
        bne +
        inc .k+1
+       jsr row_next
        bcs +                   ; (the text cannot end before the top)
        jsr ptr_to_off
        lda off                 ; does the next row start before the top?
        cmp .top
        lda off+1
        sbc .top+1
        bcc -                   ; yes: one more row
+       lda .k+1                ; enough rows?
        bne .enough
        lda .k
        cmp .need
        bcs .enough
        lda .need               ; no: take them all, and go on with the
        sec                     ; line before
        sbc .k
        sta .need
        lda .lstart
        sta ptr
        lda .lstart+1
        sta ptr+1
        jsr ptr_to_off
        lda off
        sta .top
        lda off+1
        sta .top+1
        jmp .line
.enough lda .need                ; yes: the new top is row k - need of it,
        cmp #RING               ; noted in the ring: RING slots after row k
        bcs .walk               ; would go, minus need
        lda .ri
        sec
        sbc .need
        bcs +
        adc #RING
+       tax
        lda .ring_lo,x
        sta ptr
        lda .ring_hi,x
        sta ptr+1
        jmp .set
.walk   sec                     ; (need is too big for the ring: walk to
        lda .k                  ; that row from the line start)
        sbc .need
        sta .k
        lda .k+1
        sbc #0
        sta .k+1
        lda .lstart
        sta ptr
        lda .lstart+1
        sta ptr+1
-       lda .k
        ora .k+1
        beq .set
        jsr row_next
        lda .k
        bne +
        dec .k+1
+       dec .k
        jmp -
.at_start
        jsr set_ptr             ; (off = 0: the start of the text)
.set    jsr set_top_ptr         ; the color and reverse state there too
        clc
        rts
.need   !byte 0
.top    !word 0
.lstart !word 0
.k      !word 0
RING    = 25                    ; row starts noted (one more than 24 rows)
.ri     !byte 0                 ; the next slot
.ring_lo !fill RING, 0
.ring_hi !fill RING, 0

;----------------------------------------------------------------------------
; Scrolling one row: what is on the screen moves over by a row, and only
; the new row is drawn - far quicker than drawing all 25 rows again.
;----------------------------------------------------------------------------

; view_down - the text moves up a row on the screen (row 1 becomes the top
; row). The row below the screen (row 25) must exist: the text goes on.
!zone view_down
view_down
        ldx #0                  ; the row tables move up a row
-       lda row_off_lo+1,x
        sta row_off_lo,x
        lda row_off_hi+1,x
        sta row_off_hi,x
        lda row_color+1,x
        sta row_color,x
        lda row_rvs+1,x
        sta row_rvs,x
        lda row_len+1,x
        sta row_len,x
        inx
        cpx #MROWS-1
        bne -
        lda #0                  ; and so do the screen rows
        sta .r
-       ldx .r                  ; row r+1 to row r, from the top down
        ldy .r
        inx
        jsr copy_row
        inc .r
        lda .r
        cmp #ROWS-1
        bne -
        ldx #ROWS-1             ; draw the new bottom row (and measure the
        jmp redraw_from         ; one below it)
.r      !byte 0

; view_up - the text moves down a row on the screen (the row above the top
; becomes the top row). Carry set if the top is the start of the text
; already (then nothing happens).
!zone view_up
view_up
        lda row_off_lo
        ora row_off_hi
        bne +
        sec
        rts
+       lda row_off_lo          ; the old top: from here on the rows are
        sta edit_end            ; as they were (for redraw_from, below)
        lda row_off_hi
        sta edit_end+1
        ldx #MROWS-2            ; the row tables move down a row (row 0
-       lda row_off_lo,x        ; stays for now: rows_back works from it)
        sta row_off_lo+1,x
        lda row_off_hi,x
        sta row_off_hi+1,x
        lda row_color,x
        sta row_color+1,x
        lda row_rvs,x
        sta row_rvs+1,x
        lda row_len,x
        sta row_len+1,x
        dex
        bpl -
        lda #ROWS-2             ; and so do the screen rows
        sta .r
-       ldx .r                  ; row r to row r+1, from the bottom up
        ldy .r
        iny
        jsr copy_row
        dec .r
        bpl -
        lda eof_row             ; the end of the text: a row lower, too
        cmp #MROWS-1
        bcs +
        inc eof_row
        bne ++                  ; (always)
+       lda #$ff                ; (was in row 25: now below it)
        sta eof_row
++      lda #1                  ; the new top row
        jsr rows_back
        lda #0                  ; draw it; redraw_from stops at the next
        sta edit_delta          ; row that starts where it did before (the
        sta edit_delta+1        ; old top), with nothing moved
        lda #1
        sta can_stop
        ldx #0
        jsr redraw_from
        lda #0
        sta can_stop
        clc
        rts
.r      !byte 0

; copy_row - copy screen row X to row Y: characters and colors
!zone copy_row
copy_row
        lda row_lo,x
        sta ptr
        lda row_hi,x
        sta ptr+1
        lda row_lo,y
        sta ptr2
        lda row_hi,y
        sta ptr2+1
        ldy #39
-       lda (ptr),y
        sta (ptr2),y
        dey
        bpl -
        lda ptr+1               ; the same for the colors
        clc
        adc #>(COLOR_RAM - SCREEN)
        sta ptr+1
        lda ptr2+1
        clc
        adc #>(COLOR_RAM - SCREEN)
        sta ptr2+1
        ldy #39
-       lda (ptr),y
        sta (ptr2),y
        dey
        bpl -
        rts

;============================================================================
; Drawing the screen
;============================================================================

; redraw_all - draw the whole screen from the top.
redraw_all
        lda #0
        sta can_stop
        ldx #0
        ; (falls into redraw_from)

; redraw_from - draw screen rows X to 24, and measure row 25. The start of
; row X must be known (row_off, row_color, row_rvs).
; If can_stop is 1, it stops early once the rest of the screen is known to
; be the same as before: a row after the edit (old offset >= edit_end)
; that starts where it did before, moved by edit_delta, in the same state.
; The rows below it then only need their offsets moved by edit_delta.
; Afterwards the page marker shows the new position.
!zone redraw_from
redraw_from
        jsr .rows
        jmp update_marker

.rows   stx .row
        lda #0                  ; marked text: reversed on the screen
        sta .in_sel
        lda sel_on
        beq .no_sel
        jsr sel_range           ; the marked part, as addresses
        lda sel_s
        sta off
        lda sel_s+1
        sta off+1
        jsr set_ptr
        lda ptr
        sta .sel_a
        lda ptr+1
        sta .sel_a+1
        lda sel_e
        sta off
        lda sel_e+1
        sta off+1
        jsr set_ptr
        lda ptr
        sta .sel_b
        lda ptr+1
        sta .sel_b+1
        ldx .row                ; does the first row start inside it?
        lda row_off_lo,x        ; (sel_s <= row start < sel_e)
        cmp sel_s
        lda row_off_hi,x
        sbc sel_s+1
        bcc .no_sel
        lda row_off_lo,x
        cmp sel_e
        lda row_off_hi,x
        sbc sel_e+1
        bcs .no_sel
        lda #$80
        sta .in_sel
.no_sel ldx .row
        lda row_off_lo,x
        sta off
        lda row_off_hi,x
        sta off+1
        jsr set_ptr
        ldx .row
        lda row_color,x
        sta .color
        lda row_rvs,x
        sta .rvs
        lda eof_row             ; (needed if it stops early)
        sta .old_eof
        lda #$ff
        sta eof_row

.new_row
        jsr ptr_to_off          ; where this row starts
        ldx .row
        lda can_stop
        beq .no_stop
        cpx .old_eof            ; the old row must exist (at or above the
        beq +                   ; old end of the text) ...
        bcs .no_stop
+       lda row_off_hi,x        ; ... start at or after edit_end ...
        cmp edit_end+1
        bcc .no_stop
        bne +
        lda row_off_lo,x
        cmp edit_end
        bcc .no_stop
+       clc                     ; ... and now start at old + edit_delta ...
        lda row_off_lo,x        ; (add both bytes first: CMP would spoil
        adc edit_delta          ; the carry between them)
        sta .moved
        lda row_off_hi,x
        adc edit_delta+1
        cmp off+1
        bne .no_stop
        lda .moved
        cmp off
        bne .no_stop
        lda row_color,x         ; ... in the same state
        cmp .color
        bne .no_stop
        lda row_rvs,x
        cmp .rvs
        bne .no_stop
        jmp .stop

.no_stop
        lda off
        sta row_off_lo,x
        lda off+1
        sta row_off_hi,x
        lda .color
        sta row_color,x
        lda .rvs
        sta row_rvs,x
        jsr .row_ptrs
        lda #0
        sta .col
        sta .brk_col            ; no space seen yet

.pos    lda sel_on              ; the start or end of the marked part?
        beq .gap
        lda ptr
        cmp .sel_a
        bne +
        lda ptr+1
        cmp .sel_a+1
        bne +
        lda #$80
        sta .in_sel
+       lda ptr
        cmp .sel_b
        bne .gap
        lda ptr+1
        cmp .sel_b+1
        bne .gap
        lda #0
        sta .in_sel
.gap    lda ptr                 ; at the gap? jump over it
        cmp gap_start
        bne .read
        lda ptr+1
        cmp gap_start+1
        bne .read
        lda gap_end
        sta ptr
        lda gap_end+1
        sta ptr+1
.read   lda ptr+1               ; the end of the text?
        cmp text_end+1
        bcc +                   ; (quick: a whole page before it)
        bne .to_eof
        lda ptr
        cmp text_end
        bcc +
.to_eof jmp .eof
+       ldy #0
        lda (ptr),y
        inc ptr
        bne +
        inc ptr+1
+       tax
        lda ctype,x
        bmi .not_color
        sta .color              ; a color code
        jmp .pos
.not_color
        cmp #CT_CHAR
        beq .char
        jmp .not_char

.char   ldy .col                ; a character (X = it)
        stx .ch
        lda scrcode,x           ; put it on the screen
        ora .rvs
        eor .in_sel             ; (marked: shown the other way round)
        sta (scr),y
        lda .color
        sta (clr),y
        iny
        sty .col
        lda wrap_on             ; word wrap: after a space the row may
        beq +                   ; end, so remember how things are there
        lda .ch
        cmp #$20
        bne +
        sty .brk_col
        lda ptr
        sta .brk
        lda ptr+1
        sta .brk+1
        lda .color
        sta .brk_color
        lda .rvs
        sta .brk_rvs
        lda .in_sel
        sta .brk_sel
+       cpy #40
        bcs .full
        jmp .pos

.full   lda .brk_col            ; 40 characters: the row is full. It ends
        beq .cut                ; after its last space, if it has one
        cmp #40                 ; (none, or word wrap off: cut at 40; or
        bcs .cut                ; the 40th character is the space itself)
        sta .col                ; The word after the space starts the next
        lda .brk                ; row: blank it here, and go back to it.
        sta ptr
        lda .brk+1
        sta ptr+1
        lda .brk_color
        sta .color
        lda .brk_rvs
        sta .rvs
        lda .brk_sel
        sta .in_sel
        jsr .fill
.cut    ldx .row
        lda .col
        sta row_len,x
        jmp .next_row

.not_char
        cmp #CT_EOL
        bne .not_eol
        jsr .line_end           ; line end: one more cursor place, then
                                ; blank to the end of the row
        lda .in_sel             ; a marked line end: a reversed space
        beq +
        ldy .col
        lda #$a0
        sta (scr),y
+       lda #0                  ; a line end also ends reverse
        sta .rvs
        jmp .next_row
.not_eol
        cmp #CT_RVSON
        bne +
        lda #$80
        sta .rvs
        jmp .pos
+       cmp #CT_RVSOFF
        beq +
        jmp .pos                ; other codes: nothing to do
+       lda #0
        sta .rvs
        jmp .pos

.next_row
        inc .row
        lda .row
        cmp redraw_stop         ; (normally MROWS: all the rows)
        bcs +
        jmp .new_row
+       cmp #MROWS              ; all rows done: eof_row is right as it is
        bcs +
        lda eof_row             ; stopped early (redraw_stop) before the end
        cmp #$ff                ; of the text: it is where it was
        bne +
        lda .old_eof
        sta eof_row
+       rts

.eof    ldx .row                ; end of the text, in this row
        stx eof_row
        jsr .line_end           ; (one cursor place after the last byte)
-       inc .row                ; the rows below are empty
        ldx .row
        cpx #MROWS
        bcs +
        lda #0
        sta row_len,x
        jsr .row_ptrs
        lda #0
        sta .col
        jsr .fill
        jmp -
+       rts

.stop   ; The rest of the screen is unchanged; just move the offsets.
        lda .old_eof
        sta eof_row
-       clc
        lda row_off_lo,x
        adc edit_delta
        sta row_off_lo,x
        lda row_off_hi,x
        adc edit_delta+1
        sta row_off_hi,x
        inx
        cpx #MROWS
        bcc -
        rts

; .line_end - the row ends with a line end or the end of the text: its
; cursor places are its characters plus one; blank the rest of the row.
.line_end
        ldx .row
        ldy .col
        iny
        tya
        sta row_len,x
        ; (falls into .fill)

; .fill - blank the row from .col to the end
.fill   ldy .col
-       cpy #40
        bcs +
        lda #$20
        sta (scr),y
        lda .color
        sta (clr),y
        iny
        bne -
+       rts

; .row_ptrs - scr and clr for row .row (row 25 draws into a dummy row)
.row_ptrs
        ldx .row
        cpx #ROWS
        bcs +
        lda row_lo,x
        sta scr
        sta clr
        lda row_hi,x
        sta scr+1
        clc
        adc #>(COLOR_RAM - SCREEN)
        sta clr+1
        rts
+       lda #<dummy_row
        sta scr
        sta clr
        lda #>dummy_row
        sta scr+1
        sta clr+1
        rts

.row    !byte 0
.col    !byte 0
.ch     !byte 0
.color  !byte 0
.rvs    !byte 0
.old_eof !byte 0
.moved  !byte 0
.in_sel !byte 0                 ; $80 while drawing marked text
.sel_a  !word 0                 ; addresses where the marked part starts
.sel_b  !word 0                 ; and ends
.brk_col !byte 0                ; word wrap: the column after the last
.brk    !word 0                 ; space in the row, the address there,
.brk_color !byte 0              ; and the state there
.brk_rvs !byte 0
.brk_sel !byte 0

redraw_stop     !byte MROWS     ; redraw_from draws up to (not including)
                                ; this row

can_stop        !byte 0         ; redraw_from may stop early (see above)
edit_end        !word 0         ; old offset just after the edited part
edit_delta      !word 0         ; how much longer the text got (signed)
old_len         !word 0         ; text length before the edit

; update_marker - the page marker (grey on the side borders) shows which
; part of the document is on the screen: from the offset of the top row to
; the offset just below the bottom row, out of the whole text. (Offsets,
; not lines: they are known already, cost nothing to keep up to date, and
; work the same with and without word wrap.)
!zone update_marker
update_marker
        jsr text_len
        lda work
        sta mk_total
        sta mk_last
        lda work+1
        sta mk_total+1
        sta mk_last+1
        lda row_off_lo
        sta mk_first
        lda row_off_hi
        sta mk_first+1
        lda eof_row             ; the end of the text on the screen?
        cmp #ROWS
        bcc +                   ; yes: the screen goes to the end
        lda row_off_lo+ROWS     ; no: to where row 25 (below it) starts
        sta mk_last
        lda row_off_hi+ROWS
        sta mk_last+1
+       jmp marker_set

;============================================================================
; Where is the cursor on the screen?
;============================================================================

; locate_cursor - find the cursor's row and column, and the typing color
; and reverse state there (cur_row, cur_col, cur_color, cur_rvs).
; Carry set if it is not on the screen: A = 0 above it, 1 below it.
!zone locate_cursor
locate_cursor
        jsr get_cursor_off      ; work = cursor offset
        lda work+1              ; above the top row?
        cmp row_off_hi
        bcc .to_above
        bne +
        lda work
        cmp row_off_lo
        bcs +
.to_above
        jmp .above
+       ldx #0                  ; the last row that starts at or before it
.find   inx
        cpx #MROWS
        bcs .last
        cpx eof_row             ; rows past the end of the text don't count
        beq +
        bcs .last
+       lda row_off_hi,x
        cmp work+1
        bcc .find
        bne .last
        lda work
        cmp row_off_lo,x
        bcs .find
.last   dex
        cpx #ROWS
        bcc +
        jmp .below
+       stx cur_row

        lda row_off_lo,x        ; walk the row up to the cursor
        sta off
        lda row_off_hi,x
        sta off+1
        jsr set_ptr
        ldx cur_row
        lda row_color,x
        sta cur_color
        lda row_rvs,x
        sta cur_rvs
        lda #0
        sta cur_col
.walk   lda ptr
        cmp gap_start
        bne +
        lda ptr+1
        cmp gap_start+1
        beq .done
+       ldy #0
        lda (ptr),y
        inc ptr
        bne +
        inc ptr+1
+       tax
        lda ctype,x
        bmi +
        sta cur_color
        jmp .walk
+       cmp #CT_CHAR
        bne +
        inc cur_col
        jmp .walk
+       cmp #CT_RVSON
        bne +
        lda #$80
        sta cur_rvs
        jmp .walk
+       cmp #CT_RVSOFF
        bne .walk
        lda #0
        sta cur_rvs
        jmp .walk
.done   clc
        rts
.above  lda #0
        sec
        rts
.below  lda #1
        sec
        rts

; ensure_visible - make sure the cursor is on the screen, scrolling (and
; redrawing) if it is not. Then locate it.
!zone ensure_visible
ensure_visible
-       jsr locate_cursor
        bcc .ok
        cmp #0
        bne .below
        ; Above the top: the row holding the cursor becomes the top row.
        jsr .cursor_row
        jsr redraw_all
        jmp -
.ok     rts

.below  ; Just one row below the screen (in row 25)? Then scroll one row.
        lda row_off_lo+ROWS
        sta off
        lda row_off_hi+ROWS
        sta off+1
        jsr set_ptr
        jsr row_next            ; where row 26 would start
        bcs .one                ; (the text ends in row 25)
        jsr ptr_to_off
        jsr get_cursor_off
        lda work                ; the cursor before row 26?
        cmp off
        lda work+1
        sbc off+1
        bcc .one
        ; Further down (a big paste, say): the row holding the cursor
        ; becomes the bottom row, in one go.
        jsr .cursor_row
        lda #ROWS-1
        jsr rows_back
        jsr redraw_all
        jmp -
.one    jsr view_down
        jmp -

; .cursor_row - the row holding the cursor becomes the top row
.cursor_row
        lda gap_start
        sta limit
        lda gap_start+1
        sta limit+1
        jsr find_row_start
        jmp set_top_ptr

;============================================================================
; The cursor on the screen
;
; Overwrite mode: the character under the cursor flashes in reverse, like
; the BASIC editor. Insert mode: a flashing thick underline (screen code
; 121). Either way it is drawn in the typing color. It flashes from the
; main loop, so it can never get in the way of drawing the screen.
;============================================================================
cursor_shown    !byte 0         ; 1 = the cursor is on the screen
cursor_phase    !byte 0         ; 1 = drawn now, 0 = the flash is "off"
blink_timer     !byte 0
blink_frames    !byte 0         ; from the timing table
blink_frame     !byte 0         ; last frame_count seen
under_char      !byte 0         ; what the cursor covers
under_color     !byte 0

; cursor_show - draw the cursor (solid, the flash starts over).
!zone cursor_show
cursor_show
        jsr cursor_hide
        ldx cur_row
        cpx #ROWS
        bcs +                   ; not on the screen
        lda row_lo,x
        clc
        adc cur_col
        sta cptr
        sta ccol
        lda row_hi,x
        adc #0
        sta cptr+1
        clc
        adc #>(COLOR_RAM - SCREEN)
        sta ccol+1
        ldy #0
        lda (cptr),y
        sta under_char
        lda (ccol),y
        and #$0f                ; (color RAM has only 4 bits)
        sta under_color
        lda #1
        sta cursor_shown
        sta cursor_phase
        lda blink_frames
        sta blink_timer
        jmp cursor_draw
+       rts

; cursor_hide - take the cursor off the screen.
cursor_hide
        lda cursor_shown
        beq +
        jsr cursor_undraw
        lda #0
        sta cursor_shown
+       rts

; cursor_draw - the "on" look
cursor_draw
        ldy #0
        lda edit_mode
        bne +
        lda #CURSOR_INSERT
        bne ++
+       lda under_char
        eor #$80
++      sta (cptr),y
        lda cur_color
        sta (ccol),y
        rts

; cursor_undraw - put back what the cursor covers
cursor_undraw
        ldy #0
        lda under_char
        sta (cptr),y
        lda under_color
        sta (ccol),y
        rts

; cursor_blink - called from the main loop: flash the cursor.
!zone cursor_blink
cursor_blink
        lda cursor_shown
        beq +
        lda frame_count         ; one more frame gone by?
        cmp blink_frame
        beq +
        sta blink_frame
        dec blink_timer
        bne +
        lda blink_frames
        sta blink_timer
        lda cursor_phase
        eor #1
        sta cursor_phase
        beq ++
        jmp cursor_draw
++      jmp cursor_undraw
+       rts

;============================================================================
; Editing
;============================================================================

; insert_byte - put A in the text at the cursor (before the gap).
; Carry set if the buffer is full.
!zone insert_byte
insert_byte
        tax
        lda gap_start
        cmp gap_end
        bne +
        lda gap_start+1
        cmp gap_end+1
        bne +
        sec                     ; no room
        rts
+       txa
        ldy #0
        sta (gap_start),y
        jsr count_color
        inc gap_start
        bne +
        inc gap_start+1
+       lda #1
        sta modified
        clc
        rts

; insert_after - put A in the text just after the cursor (the cursor stays
; in front of it). Carry set if the buffer is full.
!zone insert_after
insert_after
        tax
        lda gap_start
        cmp gap_end
        bne +
        lda gap_start+1
        cmp gap_end+1
        bne +
        sec
        rts
+       lda gap_end
        bne +
        dec gap_end+1
+       dec gap_end
        txa
        ldy #0
        sta (gap_end),y
        jsr count_color
        lda #1
        sta modified
        clc
        rts

; begin_edit - note the text length and cursor offset before an edit, for
; after_edit's quick redraw.
!zone begin_edit
begin_edit
        jsr text_len
        lda work
        sta old_len
        lda work+1
        sta old_len+1
        jsr get_cursor_off
        lda work
        sta edit_end
        lda work+1
        sta edit_end+1
        rts

; after_edit - redraw what the edit changed, keep the cursor on the screen.
!zone after_edit
after_edit
        jsr text_len            ; edit_delta = new length - old length
        sec
        lda work
        sbc old_len
        sta edit_delta
        lda work+1
        sbc old_len+1
        sta edit_delta+1
        lda #1
        sta can_stop
        ldx cur_row             ; from the row above the cursor: a deletion
        beq +                   ; can pull text back onto it
        dex
+       jsr redraw_from
        lda #0
        sta can_stop
        jsr ensure_visible
        jmp set_want_col

; set_want_col - aim for the cursor's column when moving up and down
set_want_col
        lda cur_col
        sta want_col
        rts

; leave_cursor - tidy the codes at the cursor before it moves away.
!zone leave_cursor
leave_cursor
        lda no_cleanup          ; (not while marking text)
        bne +
        jsr begin_edit
        jsr cleanup
        bcc +
        jmp after_edit          ; codes were removed: redraw
+       rts

; type_char - A = PETSCII of a character (or CR) to type at the cursor.
!zone type_char
type_char
        sta .ch
        jsr begin_edit
        lda edit_mode
        beq +
        lda .ch
        cmp #$0d
        beq +                   ; RETURN never overwrites
        jsr overwrite_next
+       lda .ch
        jsr insert_byte
        jmp after_edit
.ch     !byte 0

; overwrite_next - overwrite mode: take out the character after the cursor
; (not a line end), keeping any codes in front of it.
!zone overwrite_next
overwrite_next
        lda gap_end
        sta ptr
        lda gap_end+1
        sta ptr+1
-       jsr ptr_at_end          ; find the next visible byte
        bcs .none
        ldy #0
        lda (ptr),y
        tax
        lda ctype,x
        cmp #CT_CHAR
        beq .found
        cmp #CT_EOL
        beq .none               ; never overwrite a line end
        inc ptr
        bne -
        inc ptr+1
        bne -
.found  jsr ptr_to_off          ; the edit reaches past this byte
        clc
        lda off
        adc #1
        sta edit_end
        lda off+1
        adc #0
        sta edit_end+1
-       lda ptr                 ; move the codes in front of it up by one,
        cmp gap_end             ; over it
        bne +
        lda ptr+1
        cmp gap_end+1
        beq .moved
+       lda ptr
        bne +
        dec ptr+1
+       dec ptr
        ldy #0
        lda (ptr),y
        iny
        sta (ptr),y
        jmp -
.moved  inc gap_end
        bne .none
        inc gap_end+1
.none   rts

; delete_left - INST/DEL: delete the visible byte left of the cursor. The
; codes around it stay (then get tidied). At the start of a line this
; joins it to the line above.
!zone delete_left
delete_left
        lda cur_row             ; at the top left of the screen? show the
        ora cur_col             ; row above first, so what gets deleted is
        bne +                   ; on the screen
        jsr view_up
        bcs .none               ; nothing above: the start of the text
        jsr locate_cursor
+       jsr begin_edit
-       jsr gap_left            ; bring the byte to delete next to the gap
        bcs .restore            ; (nothing visible before the cursor)
        jsr is_visible
        bcs -
        lda gap_end             ; the byte went after the gap: drop it
        clc
        adc #1
        sta gap_end
        bcc +
        inc gap_end+1
+       lda #1
        sta modified
        jsr cleanup             ; tidy the codes around the cursor
        jmp after_edit
.restore
        jsr skip_codes
.none   rts

; insert_space - SHIFT + INST/DEL: a space at the cursor; the cursor stays.
!zone insert_space
insert_space
        jsr begin_edit
        lda #$20
        jsr insert_after
        jmp after_edit

; color_key - A = a color (0-15) from a color key. Inserts its code at the
; cursor, plus a code after the cursor that brings back the color the text
; after it had, so only what is typed next changes color.
!zone color_key
color_key
        cmp cur_color
        beq .done               ; that color already
        sta .new
        jsr begin_edit
        lda #0                  ; does the text after the cursor set its
        jsr codes_after         ; own color already?
        php
        ldx .new
        lda color_codes,x
        jsr insert_byte
        plp
        bcs +
        ldx cur_color           ; no: add a code that restores the color
        lda color_codes,x
        jsr insert_after
+       jmp after_edit
.done   rts
.new    !byte 0

; rvs_key - A = $80 for RVS ON (CTRL-9), 0 for RVS OFF (CTRL-0).
!zone rvs_key
rvs_key
        cmp cur_rvs
        beq .done
        sta .new
        jsr begin_edit
        lda #1                  ; is there an RVS code after the cursor
        jsr codes_after         ; already?
        php
        lda #$12                ; RVS ON
        ldx .new
        bne +
        lda #$92                ; RVS OFF
+       jsr insert_byte
        plp
        bcs +
        lda #$12                ; no: add one that restores the old state
        ldx cur_rvs
        bne ++
        lda #$92
++      jsr insert_after
+       jmp after_edit
.done   rts
.new    !byte 0

; codes_after - look at the codes between the cursor and the next visible
; byte. A = 0: carry set if one of them is a color code. A = 1: carry set
; if one of them is an RVS code.
!zone codes_after
codes_after
        sta .kind
        lda gap_end
        sta ptr
        lda gap_end+1
        sta ptr+1
-       jsr ptr_at_end
        bcs .no
        ldy #0
        lda (ptr),y
        tax
        lda ctype,x
        bpl .color
        cmp #CT_RVSON
        beq .rvs
        cmp #CT_RVSOFF
        beq .rvs
        cmp #CT_OTHER
        bne .no                 ; a visible byte: the run ends
.next   inc ptr
        bne -
        inc ptr+1
        bne -
.color  lda .kind
        bne .next               ; looking for RVS codes
        sec
        rts
.rvs    lda .kind
        beq .next               ; looking for color codes
        sec
        rts
.no     clc
        rts
.kind   !byte 0

;============================================================================
; Cursor keys
;============================================================================

; cursor_right, cursor_left - one place along the text.
!zone cursor_right
cursor_right
        jsr leave_cursor
        jsr move_right
        jmp moved

cursor_left
        jsr leave_cursor
        jsr move_left
        ; (falls into moved)

; moved - after a sideways move: keep the cursor on the screen, and aim
; for this column when moving up and down.
moved   jsr ensure_visible
        jmp set_want_col

; cursor_down, cursor_up - one screen row down or up, aiming for want_col.
!zone cursor_down
cursor_down
        jsr leave_cursor
        ldx cur_row
        cpx eof_row
        beq .none               ; already on the last row of the text
        cpx #ROWS-1
        bcc +
        jsr view_down           ; on the bottom row: scroll first
        ldx #ROWS-2
+       inx
        jmp goto_row
.none   rts

cursor_up
        jsr leave_cursor
        ldx cur_row
        bne +
        jsr view_up             ; on the top row: scroll first
        bcs .none               ; the start of the text
        ldx #1
+       dex
        jmp goto_row

; goto_row - put the cursor on screen row X, as close to want_col as the
; row allows.
!zone goto_row
goto_row
        stx .row
        lda row_len,x           ; last place in the row: len - 1
        sec
        sbc #1
        cmp want_col
        bcc +
        lda want_col
+       sta .col
        lda row_off_lo,x        ; walk the row to that column
        sta off
        lda row_off_hi,x
        sta off+1
        jsr set_ptr
        lda #0
        sta .n
.walk   lda .n
        cmp .col
        beq .there
        lda ptr                 ; (jump over the gap)
        cmp gap_start
        bne +
        lda ptr+1
        cmp gap_start+1
        bne +
        lda gap_end
        sta ptr
        lda gap_end+1
        sta ptr+1
+       ldy #0
        lda (ptr),y
        inc ptr
        bne +
        inc ptr+1
+       tax
        lda ctype,x
        cmp #CT_CHAR
        bne .walk
        inc .n
        jmp .walk
.there  jsr ptr_to_off
        jsr move_gap_to
        jsr skip_codes
        jmp ensure_visible      ; (row 25, below the screen: it scrolls)
.row    !byte 0
.col    !byte 0
.n      !byte 0

; goto_click - the mouse: put the cursor on the text cell clicked
; (click_row, click_col), or as near as the text allows. Dragging past the
; top or bottom of the text (row $ff, or 25): to the top or bottom row,
; then on a row at a time, the screen scrolling.
!zone goto_click
goto_click
        lda click_col
        sta want_col
        ldx click_row
        cpx #ROWS
        bcc .row
        cpx #$ff
        beq .above
        ldx cur_row             ; below the text
        cpx #ROWS-1
        bcs +
        ldx #ROWS-1
        bne .row
+       jmp cursor_down
.above  ldx cur_row             ; above the text
        beq +
        ldx #0
        beq .row
+       jmp cursor_up
.row    txa
        pha
        jsr leave_cursor
        pla
        tax
        cpx eof_row             ; not past the end of the text
        bcc +
        beq +
        ldx eof_row
+       jmp goto_row

; page_down (F5), page_up (F3) - move a screenful: the screen scrolls by
; 24 rows and the cursor keeps its place on the screen.
!zone page_down
page_down
        jsr leave_cursor
        lda eof_row
        bmi +
        tax                     ; the end of the text is on the screen:
        jmp goto_row            ; go to its row
+       ldx #ROWS-1             ; row 24 becomes the top row
        lda row_off_lo,x
        sta row_off_lo
        lda row_off_hi,x
        sta row_off_hi
        lda row_color,x
        sta row_color
        lda row_rvs,x
        sta row_rvs
        jsr redraw_all
        ldx cur_row
        cpx eof_row             ; (if the text ends above that row, go to
        bcc +                   ; its last row instead)
        ldx eof_row
+       jmp goto_row

page_up
        jsr leave_cursor
        lda #ROWS-1             ; 24 rows up (or to the start of the text)
        jsr rows_back
        jsr redraw_all
        ldx cur_row
        cpx eof_row
        bcc +
        ldx eof_row
+       jmp goto_row

; home_key - HOME: to the start of the line; if already there, to the top
; of the document.
!zone home_key
home_key
        jsr leave_cursor
        lda gap_start           ; look back from the cursor past any codes
        sta ptr
        lda gap_start+1
        sta ptr+1
-       lda ptr
        cmp #<BUF_START
        bne +
        lda ptr+1
        cmp #>BUF_START
        beq .at_start           ; start of the text
+       lda ptr
        bne +
        dec ptr+1
+       dec ptr
        ldy #0
        lda (ptr),y
        jsr is_visible
        bcs -                   ; a code: keep looking
        lda ctype,x
        cmp #CT_EOL
        beq .at_start           ; a line end: the cursor is at a line start
        ; Go to the start of this line, in one move (after any codes there).
        lda gap_start
        sta ptr
        lda gap_start+1
        sta ptr+1
        jsr line_start
        jsr ptr_to_off
        jsr move_gap_to
        jsr skip_codes
        jmp moved
.at_start                       ; already at a line start: top of document
        lda #0
        sta off
        sta off+1
        jsr move_gap_to
        jsr skip_codes
        jsr empty_view          ; (the top of the screen at the start)
        jsr redraw_all
        jmp moved

;============================================================================
; Marked text (the selection) and the clipboard
;
; Text is marked from sel_anchor (an offset: where marking started) to the
; cursor, whichever comes first; it shows reversed on the screen. The
; character the cursor was on when marking started is always marked:
; going right it is the first one; going left the marking reaches to just
; after it (sel_anchor_end). (Not a line end, though: marking left from
; the end of a line should not take in the line end.)
; Every operation on marked text moves the
; cursor (the gap) to the start of the marked text first, so the marked
; bytes lie together right after the gap, and then works through them
; there.
;
; The clipboard sits at the top of the buffer, from text_end to BUF_END:
; the text uses the room below it. clip_color and clip_rvs hold the color
; and reverse state at the start of what was copied, so it pastes with the
; same look.
;============================================================================
sel_on          !byte 0         ; 1 = text is marked
sel_anchor      !word 0         ; where the marking started (offset)
sel_anchor_end  !word 0         ; just after the character there
sel_s           !word 0         ; the marked part: from here ...
sel_e           !word 0         ; ... up to (not including) here
sel_len         !word 0
sel_cur_start   !byte 0         ; 1 = the cursor was at its start
sel_old_row     !byte 0         ; the cursor's screen row before
st_color        !byte 0         ; the state at the cursor, for restore_after
st_rvs          !byte 0
clip_color      !byte 0         ; the state at the start of the clipboard
clip_rvs        !byte 0
no_cleanup      !byte 0         ; 1 = leave_cursor leaves the codes alone
blk_count       !word 0         ; bytes for block_copy

; mark_here - start marking at the cursor: sel_anchor = the cursor, and
; sel_anchor_end = just after the character the cursor is on (past any
; codes before it). At a line end or the end of the text there is no
; character: sel_anchor_end = sel_anchor.
!zone mark_here
mark_here
        jsr get_cursor_off
        lda work
        sta sel_anchor
        sta sel_anchor_end
        lda work+1
        sta sel_anchor+1
        sta sel_anchor_end+1
        lda #1
        sta sel_on
        lda gap_end             ; look along the text after the cursor
        sta ptr
        lda gap_end+1
        sta ptr+1
-       jsr ptr_at_end
        bcs .done               ; the end of the text: no character
        ldy #0
        lda (ptr),y
        tax
        inc ptr
        bne +
        inc ptr+1
+       lda ctype,x
        cmp #CT_EOL
        beq .done               ; a line end: not marked
        cmp #CT_CHAR
        bne -                   ; a code: look on
        jsr ptr_to_off          ; a character: just after it
        lda off
        sta sel_anchor_end
        lda off+1
        sta sel_anchor_end+1
.done   rts

; sel_range - sel_s and sel_e: the marked part, in order.
!zone sel_range
sel_range
        jsr get_cursor_off      ; work = cursor
        lda sel_anchor
        cmp work
        lda sel_anchor+1
        sbc work+1
        bcc .anchor_first
        lda work                ; the cursor comes first: up to just after
        sta sel_s               ; the character where marking started
        lda work+1
        sta sel_s+1
        lda sel_anchor_end
        sta sel_e
        lda sel_anchor_end+1
        sta sel_e+1
        lda sel_anchor          ; (unless the cursor is back there: then
        cmp work                ; nothing is marked)
        bne +
        lda sel_anchor+1
        cmp work+1
        bne +
        lda work
        sta sel_e
        lda work+1
        sta sel_e+1
+       rts
.anchor_first
        lda sel_anchor
        sta sel_s
        lda sel_anchor+1
        sta sel_s+1
        lda work
        sta sel_e
        lda work+1
        sta sel_e+1
        rts

; sel_to_gap - get ready to work on the marked text: sel_s, sel_e and
; sel_len; which end the cursor is at; the cursor (gap) moved to the start
; of it, so the marked bytes are right after the gap; and the color and
; reverse state in effect there (st_color, st_rvs).
!zone sel_to_gap
sel_to_gap
        jsr sel_range
        sec
        lda sel_e
        sbc sel_s
        sta sel_len
        lda sel_e+1
        sbc sel_s+1
        sta sel_len+1
        lda cur_row
        sta sel_old_row
        jsr get_cursor_off
        ldx #0
        lda work
        cmp sel_s
        bne +
        lda work+1
        cmp sel_s+1
        bne +
        inx
+       stx sel_cur_start
        lda sel_s
        sta off
        lda sel_s+1
        sta off+1
        jsr move_gap_to
        lda #0                  ; (the marked text may start above the top
        sta top_known           ; of the screen: its state may change)
        lda gap_start
        sta ptr
        lda gap_start+1
        sta ptr+1
        jsr color_before
        sta st_color
        jsr rvs_before
        sta st_rvs
        rts

; take_byte - take the next byte after the gap out of the text (A = it),
; and count sel_len down by one.
!zone take_byte
take_byte
        ldy #0
        lda (gap_end),y
        inc gap_end
        bne +
        inc gap_end+1
+       pha
        lda sel_len
        bne +
        dec sel_len+1
+       dec sel_len
        pla
        jmp uncount_color       ; (keeps A)

; sel_left - Z clear if marked bytes are left to take
sel_left
        lda sel_len
        ora sel_len+1
        rts

; restore_after - make the text after the cursor look as it should: A = its
; color, X = its reverse state ($80 or 0). st_color / st_rvs = the state in
; effect at the cursor now. Adds codes just after the cursor where they
; differ - unless codes there already set them, or nothing follows.
!zone restore_after
restore_after
        sta .c
        stx .r
        jsr gap_at_end
        bcs .done               ; nothing after the cursor: no need
        lda .r
        cmp st_rvs
        beq +
        lda #1                  ; an RVS code there already?
        jsr codes_after
        bcs +
        lda #$92                ; RVS OFF
        ldx .r
        beq ++
        lda #$12                ; RVS ON
++      jsr insert_after
+       lda .c
        cmp st_color
        beq .done
        lda #0                  ; a color code there already?
        jsr codes_after
        bcs .done
        ldx .c
        lda color_codes,x
        jsr insert_after
.done   rts
.c      !byte 0
.r      !byte 0

; show_cursor_at - redraw with the cursor on screen row X (or as near as the
; start of the text allows).
!zone show_cursor_at
show_cursor_at
        stx .n
        lda gap_start
        sta limit
        lda gap_start+1
        sta limit+1
        jsr find_row_start      ; the row the cursor is in goes on top ...
        jsr set_top_ptr
        lda .n                  ; ... then back up X rows
        beq +
        jsr rows_back
+       jsr redraw_all
        jsr locate_cursor
        jmp set_want_col        ; (aim for this column moving up/down)
.n      !byte 0

; gap_size - work = the free space (the gap)
gap_size
        sec
        lda gap_end
        sbc gap_start
        sta work
        lda gap_end+1
        sbc gap_start+1
        sta work+1
        rts

;----------------------------------------------------------------------------
; delete_selection - take out the marked text, codes and all. The cursor
; ends up where it started; codes after it bring back the color and reverse
; state the text after it had.
;----------------------------------------------------------------------------
!zone delete_selection
delete_selection
        jsr sel_to_gap
        lda st_color            ; walk through it for the state at its end
        sta .c
        lda st_rvs
        sta .r
-       jsr sel_left
        beq +
        jsr take_byte
        tax
        lda ctype,x
        bmi .not_color
        sta .c
        jmp -
.not_color
        cmp #CT_RVSON
        bne ++
        lda #$80
        sta .r
        jmp -
++      cmp #CT_RVSOFF
        beq ++
        cmp #CT_EOL             ; (a line end also ends reverse)
        bne -
++      lda #0
        sta .r
        jmp -
+       lda .c
        ldx .r
        jsr restore_after
        lda #0
        sta sel_on
        lda #1
        sta modified
        ldx sel_old_row
        jmp show_cursor_at
.c      !byte 0
.r      !byte 0

;----------------------------------------------------------------------------
; recolor_selection - a color key with text marked: all of it gets that
; color. A = the color. The color codes inside go, the new one goes at the
; start, and one after the end brings back the color the text after it
; had. The text stays marked.
;----------------------------------------------------------------------------
!zone recolor_selection
recolor_selection
        sta .k
        jsr gap_size            ; (room for the two codes)
        lda work+1
        bne +
        lda work
        cmp #2
        bcs +
        jmp no_room
+       jsr sel_to_gap
        ldx .k                  ; the new color at the start
        lda color_codes,x
        jsr insert_byte
        lda st_color            ; the color at the end, before
        sta .c
-       jsr sel_left            ; go through it, dropping color codes
        beq +
        jsr take_byte
        tax
        lda ctype,x
        bmi .keep
        sta .c
        jmp -
.keep   txa
        jsr insert_byte
        jmp -
+       lda .k                  ; the text after it: its old color back
        sta st_color
        lda .c
        ldx st_rvs              ; (reverse: unchanged)
        stx .r
        jsr restore_after
        jmp sel_finish
.k      !byte 0
.c      !byte 0
.r      !byte 0

;----------------------------------------------------------------------------
; reverse_selection - CTRL-9 (A = $80) or CTRL-0 (A = 0) with text marked:
; reverse on or off for all of it. The RVS codes inside go; the new one
; goes at the start, and again after each line end inside it (a line end
; turns reverse off). A code after the end brings back the state the text
; after it had. The text stays marked.
;----------------------------------------------------------------------------
!zone reverse_selection
reverse_selection
        sta .v
        jsr sel_range           ; room: 2 codes + one per line end
        lda sel_s
        sta off
        lda sel_s+1
        sta off+1
        jsr set_ptr
        sec
        lda sel_e
        sbc sel_s
        sta blk_count
        lda sel_e+1
        sbc sel_s+1
        sta blk_count+1
        lda #2
        sta .need
        lda #0
        sta .need+1
-       lda blk_count           ; (count the line ends)
        ora blk_count+1
        beq .counted
        lda ptr                 ; (jump over the gap)
        cmp gap_start
        bne +
        lda ptr+1
        cmp gap_start+1
        bne +
        lda gap_end
        sta ptr
        lda gap_end+1
        sta ptr+1
+       ldy #0
        lda (ptr),y
        tax
        lda ctype,x
        cmp #CT_EOL
        bne +
        inc .need
        bne +
        inc .need+1
+       inc ptr
        bne +
        inc ptr+1
+       lda blk_count
        bne +
        dec blk_count+1
+       dec blk_count
        jmp -
.counted
        jsr gap_size
        lda work
        cmp .need
        lda work+1
        sbc .need+1
        bcs +
        jmp no_room

+       jsr sel_to_gap
        jsr .code               ; the new state at the start
        jsr insert_byte
        lda st_rvs              ; the state at the end, before
        sta .r
        lda #0
        sta .last_eol
-       jsr sel_left            ; go through it
        beq .end
        jsr take_byte
        tax
        lda ctype,x
        cmp #CT_RVSON
        bne +
        lda #$80                ; (dropped)
        sta .r
        bne -
+       cmp #CT_RVSOFF
        bne +
        lda #0                  ; (dropped)
        sta .r
        beq -
+       sta .type
        txa
        jsr insert_byte
        lda #0
        sta .last_eol
        lda .type
        cmp #CT_EOL
        bne -
        lda #0                  ; a line end: reverse is off after it ...
        sta .r
        inc .last_eol
        lda .v                  ; ... so turn it on again, if more of the
        beq -                   ; marked text follows
        jsr sel_left
        beq -
        jsr .code
        jsr insert_byte
        lda #0
        sta .last_eol
        jmp -
.end    lda .v                  ; the state at the cursor now
        ldx .last_eol
        beq +
        lda #0                  ; (after a line end: off)
+       sta st_rvs
        lda st_color            ; the text after it: its old state back
        ldx .r
        jsr restore_after
        jmp sel_finish

; .code - A = RVS ON or RVS OFF, as .v says
.code   lda #$12
        ldx .v
        bne +
        lda #$92
+       rts
.v      !byte 0
.r      !byte 0
.type   !byte 0
.last_eol !byte 0
.need   !word 0

; sel_finish - after recoloring: the text from sel_s up to the cursor is
; marked again, and the cursor goes back to the end it was at. Redraw.
!zone sel_finish
sel_finish
        lda #1
        sta modified
        jsr get_cursor_off
        lda sel_cur_start
        beq .at_end
        lda work                ; the cursor was at the start: mark from
        sta sel_anchor          ; here (the end) back to sel_s
        sta sel_anchor_end
        lda work+1
        sta sel_anchor+1
        sta sel_anchor_end+1
        lda sel_s
        sta off
        lda sel_s+1
        sta off+1
        jsr move_gap_to
        jmp +
.at_end lda sel_s               ; the cursor was at the end: mark from sel_s
        sta sel_anchor
        sta sel_anchor_end
        lda sel_s+1
        sta sel_anchor+1
        sta sel_anchor_end+1
+       ldx sel_old_row
        jmp show_cursor_at

;----------------------------------------------------------------------------
; Copy, cut, paste, mark all
;----------------------------------------------------------------------------

; copy_key - CTRL-C: copy the marked text to the clipboard.
copy_key
        lda sel_on
        beq +
        jsr copy_selection
+       rts

; cut_selection - CTRL-X: copy the marked text, then take it out.
cut_selection
        lda sel_on
        beq +
        jsr copy_selection
        bcs +                   ; (no room)
        jmp delete_selection
+       rts

; copy_selection - copy the marked text (codes and all) to the clipboard,
; with the color and reverse state at its start. Carry set if there is not
; enough room.
!zone copy_selection
copy_selection
        jsr sel_range
        sec                     ; its length
        lda sel_e
        sbc sel_s
        sta .len
        lda sel_e+1
        sbc sel_s+1
        sta .len+1
        lda reu_banks           ; with an REU the clipboard is there, in a
        bne .room               ; bank of its own: always room
        sec                     ; the clipboard's size now
        lda #<BUF_END
        sbc text_end
        sta .old
        lda #>BUF_END
        sbc text_end+1
        sta .old+1
        lda .len                ; the same size: nothing to move
        cmp .old
        bne +
        lda .len+1
        cmp .old+1
        bne +
        jmp .room
+       lda .len                ; bigger than before: is the gap big
        cmp .old                ; enough to give the difference?
        lda .len+1
        sbc .old+1
        bcc .room               ; (smaller: always fits)
        sec
        lda .len
        sbc .old
        sta .d
        lda .len+1
        sbc .old+1
        sta .d+1
        jsr gap_size
        lda work
        cmp .d
        lda work+1
        sbc .d+1
        bcs .room
        jmp no_room

.room   jsr get_cursor_off      ; (come back here afterwards)
        lda work
        sta .cursor
        lda work+1
        sta .cursor+1
        lda sel_e               ; all of the marked text before the gap
        sta off
        lda sel_e+1
        sta off+1
        jsr move_gap_to
        clc                     ; ptr = where it starts
        lda sel_s
        adc #<BUF_START
        sta ptr
        lda sel_s+1
        adc #>BUF_START
        sta ptr+1
        jsr color_before
        sta clip_color
        jsr rvs_before
        sta clip_rvs
        lda reu_banks           ; (with an REU nothing needs moving)
        beq +
        jmp .copy

        ; Make the clipboard exactly .len bytes: move the text after the gap
        ; down (clipboard bigger) or up (smaller).
+       sec                     ; blk_count = text after the gap
        lda text_end
        sbc gap_end
        sta blk_count
        lda text_end+1
        sbc gap_end+1
        sta blk_count+1
        lda .len
        cmp .old
        lda .len+1
        sbc .old+1
        bcc .smaller
        lda .len                ; (the same size: leave it)
        cmp .old
        bne +
        lda .len+1
        cmp .old+1
        bne +
        jmp .copy
+       sec                     ; bigger by .d: move it down .d bytes
        lda .len
        sbc .old
        sta .d
        lda .len+1
        sbc .old+1
        sta .d+1
        lda gap_end
        sta ptr
        sec
        sbc .d
        sta ptr2
        sta gap_end
        lda gap_end+1
        sta ptr+1
        sbc .d+1
        sta ptr2+1
        sta gap_end+1
        jsr block_copy_fwd
        sec
        lda text_end
        sbc .d
        sta text_end
        lda text_end+1
        sbc .d+1
        sta text_end+1
        jmp .copy
.smaller
        sec                     ; smaller by .d: move it up .d bytes
        lda .old
        sbc .len
        sta .d
        lda .old+1
        sbc .len+1
        sta .d+1
        lda text_end            ; (copied from its end back)
        sta ptr
        clc
        adc .d
        sta ptr2
        lda text_end+1
        sta ptr+1
        adc .d+1
        sta ptr2+1
        jsr block_copy_back
        clc
        lda gap_end
        adc .d
        sta gap_end
        lda gap_end+1
        adc .d+1
        sta gap_end+1
        clc
        lda text_end
        adc .d
        sta text_end
        lda text_end+1
        adc .d+1
        sta text_end+1

.copy   clc                     ; the marked text into the clipboard
        lda sel_s
        adc #<BUF_START
        sta ptr
        lda sel_s+1
        adc #>BUF_START
        sta ptr+1
        lda .len
        sta blk_count
        lda .len+1
        sta blk_count+1
        lda reu_banks           ; (with an REU: into its bank 1)
        beq +
        jsr clip_stash
        jmp .back
+       lda text_end
        sta ptr2
        lda text_end+1
        sta ptr2+1
        jsr block_copy_fwd
.back   lda .cursor             ; the cursor back where it was
        sta off
        lda .cursor+1
        sta off+1
        jsr move_gap_to
        clc
        rts
.len    !word 0
.old    !word 0
.d      !word 0
.cursor !word 0

; paste - CTRL-V: put the clipboard in at the cursor (in place of marked
; text, if any). It keeps the look it had where it was copied; codes after
; it bring back the state the text after the cursor had.
!zone paste
paste
        lda reu_banks           ; the clipboard's size: in the REU ...
        beq +
        lda clip_size
        sta .len
        lda clip_size+1
        sta .len+1
        jmp ++
+       sec                     ; ... or at the top of the buffer
        lda #<BUF_END
        sbc text_end
        sta .len
        lda #>BUF_END
        sbc text_end+1
        sta .len+1
++      lda .len
        ora .len+1
        bne +
        rts                     ; empty
+       lda sel_on
        beq +
        jsr delete_selection
+       jsr gap_size            ; room for it and 4 codes?
        sec
        lda work
        sbc #4
        tax
        lda work+1
        sbc #0
        bcc .nr
        cmp .len+1
        bcc .nr
        bne +
        cpx .len
        bcs +
.nr     jmp no_room
+       jsr begin_edit
        lda gap_start           ; the state here
        sta ptr
        lda gap_start+1
        sta ptr+1
        jsr color_before
        sta .c0
        jsr rvs_before
        sta .r0
        lda clip_color          ; the clipboard's look at its start
        sta .c
        cmp .c0
        beq +
        tax
        lda color_codes,x
        jsr insert_byte
+       lda clip_rvs
        sta .r
        cmp .r0
        beq +
        lda #$92
        ldx .r
        beq ++
        lda #$12
++      jsr insert_byte
+       lda reu_banks           ; then the clipboard, byte by byte: from
        bne .from_reu           ; the top of the buffer ...
        lda text_end
        sta ptr
        lda text_end+1
        sta ptr+1
        lda #<BUF_END
        sta .end
        lda #>BUF_END
        sta .end+1
        jmp .bytes
.from_reu                       ; ... or from the REU, fetched first to the
        sec                     ; top of the gap (what goes in stays below
        lda gap_end             ; it: the gap has room for 4 more bytes)
        sbc .len
        sta ptr
        lda gap_end+1
        sbc .len+1
        sta ptr+1
        jsr clip_fetch
        lda gap_end
        sta .end
        lda gap_end+1
        sta .end+1
.bytes
-       lda ptr                 ; up to .end
        cmp .end
        bne +
        lda ptr+1
        cmp .end+1
        beq .done
+       ldy #0
        lda (ptr),y
        pha
        jsr insert_byte
        pla
        tax                     ; (keep track of the state)
        lda ctype,x
        bpl .col                ; 0-15: a color code
        cmp #CT_RVSON
        bne +
        lda #$80
        sta .r
        bne .next
+       cmp #CT_RVSOFF
        beq +
        cmp #CT_EOL
        bne .next
+       lda #0
        sta .r
        beq .next
.col    sta .c
.next   inc ptr
        bne -
        inc ptr+1
        bne -
.done   lda .c                  ; the state at the cursor now
        sta st_color
        lda .r
        sta st_rvs
        lda .c0                 ; the text after it: its state back
        ldx .r0
        jsr restore_after
        lda #1
        sta modified
        jmp after_edit
.len    !word 0
.end    !word 0
.c0     !byte 0
.r0     !byte 0
.c      !byte 0
.r      !byte 0

; select_all - CTRL-A: mark the whole text (the cursor goes to its end).
!zone select_all
select_all
        jsr text_len
        lda work
        ora work+1
        bne +
        rts
+       lda work
        sta off
        lda work+1
        sta off+1
        jsr move_gap_to
        lda #0
        sta sel_anchor
        sta sel_anchor+1
        sta sel_anchor_end      ; (not used: the cursor is after it)
        sta sel_anchor_end+1
        lda #1
        sta sel_on
        ldx #ROWS-1             ; the end of the text on the bottom row
        jmp show_cursor_at

; no_room - tell the user there is not enough room in the buffer.
no_room
        lda #<msg_no_room
        ldx #>msg_no_room
        jsr message_box
        sec
        rts

; block_copy_fwd - copy blk_count bytes from ptr to ptr2, first byte first
; (for moving to lower addresses). Whole pages first, with Y running
; through each page, then the rest. Leaves ptr and ptr2 just after the
; bytes, and blk_count 0.
!zone block_copy_fwd
block_copy_fwd
        lda blk_count+1         ; 256 bytes or more, and an REU: through the
        beq +                   ; REU, which is faster (reu.asm)
        lda reu_banks
        beq +
        lda #0
        jmp reu_copy
+       ldy #0
        ldx blk_count+1         ; whole pages
        beq .rest
.page   lda (ptr),y
        sta (ptr2),y
        iny
        bne .page
        inc ptr+1
        inc ptr2+1
        dex
        bne .page
.rest   ldx blk_count           ; the rest
        beq .done
-       lda (ptr),y
        sta (ptr2),y
        iny
        dex
        bne -
        tya                     ; the pointers past them
        clc
        adc ptr
        sta ptr
        bcc +
        inc ptr+1
+       tya
        clc
        adc ptr2
        sta ptr2
        bcc .done
        inc ptr2+1
.done   lda #0
        sta blk_count
        sta blk_count+1
        rts

; block_copy_back - copy blk_count bytes ending just before ptr to just
; before ptr2, last byte first (for moving to higher addresses). The odd
; bytes at the top first, then whole pages below them. Leaves ptr and ptr2
; at the start of the bytes, and blk_count 0.
!zone block_copy_back
block_copy_back
        lda blk_count+1         ; (the same: through the REU)
        beq +
        lda reu_banks
        beq +
        lda #1
        jmp reu_copy
+       sec                     ; the pointers down by the odd bytes
        lda ptr
        sbc blk_count
        sta ptr
        bcs +
        dec ptr+1
+       sec
        lda ptr2
        sbc blk_count
        sta ptr2
        bcs +
        dec ptr2+1
+       ldy blk_count           ; the odd bytes, top one first
        beq .pages
-       dey
        lda (ptr),y
        sta (ptr2),y
        tya
        bne -
.pages  ldx blk_count+1         ; then whole pages, going down
        beq .done
-       dec ptr+1
        dec ptr2+1
        ldy #0
--      dey                     ; (255 down to 0)
        lda (ptr),y
        sta (ptr2),y
        tya
        bne --
        dex
        bne -
.done   lda #0
        sta blk_count
        sta blk_count+1
        rts

;============================================================================
; Other keys
;============================================================================

; toggle_mode - F7: insert <-> overwrite (the cursor shape shows which).
toggle_mode
        lda edit_mode
        eor #1
        sta edit_mode
        rts

; next_background - SHIFT + F7: the next text background color, through all
; 16. (Text in the same color as the background disappears, as in BASIC;
; the user just steps on.) The top strip IRQ sets $D021 from text_bg.
!zone next_background
next_background
        lda text_bg
        clc
        adc #1
        and #15
        sta text_bg
        rts

; clear_all - SHIFT + CLR/HOME: after asking, start a new document: no
; text, and no file name (so CTRL-S asks for one instead of saving over
; the file that was loaded before).
!zone clear_all
clear_all
        lda #<msg_clear_all
        ldx #>msg_clear_all
        jsr prompt_yes_no
        bcc +
        jsr empty_buffer
        lda #0
        sta file_name_len
        jsr redraw_all
        jsr locate_cursor
+       rts

;============================================================================
; editor_key - what a key does in the editor. A = key code, Y = modifiers
; (from get_key).
;============================================================================
!zone editor_key
editor_key
        sta .code
        sty .mods
        cmp #KEY_CHARSET
        bne +
        lda #1                  ; the character set is saved with the
        sta modified            ; document, so this is a change too
        jmp toggle_charset
+       jsr cursor_hide
        jsr .do_key
        jmp cursor_show

.do_key lda .code
        cmp #KEY_STOP           ; RUN/STOP and RESTORE: the menu
        beq +
        cmp #KEY_RESTORE
        bne ++
+       jmp menu_open
++      cmp #KEY_MOUSE_L        ; the mouse (mouse_frame, in input.asm)
        bcc +
        jmp .mouse
+       lda .mods               ; CTRL + a letter: the commands
        and #MOD_CTRL
        beq .keys
        lda .code
        cmp #KEY_S              ; CTRL-S: save
        bne +
        jmp save_key
+       cmp #KEY_X              ; CTRL-X: cut
        bne +
        jmp cut_selection
+       cmp #KEY_C              ; CTRL-C: copy
        bne +
        jmp copy_key
+       cmp #KEY_V              ; CTRL-V: paste
        bne +
        jmp paste
+       cmp #KEY_F              ; CTRL-F: find
        bne +
        jmp find_key
+       cmp #KEY_A              ; CTRL-A: mark everything
        bne .keys
        jmp select_all
.to_move
        jmp .move

.keys   lda .code
        cmp #KEY_RIGHT          ; the keys that move the cursor
        bne +
        jsr .reverse
        lda #<cursor_right
        ldx #>cursor_right
        bcc .to_move
        lda #<cursor_left
        ldx #>cursor_left
        bcs .to_move
+       cmp #KEY_DOWN
        bne +
        jsr .reverse
        lda #<cursor_down
        ldx #>cursor_down
        bcc .to_move
        lda #<cursor_up
        ldx #>cursor_up
        bcs .to_move
+       cmp #KEY_F3
        bne +
        lda #<page_up
        ldx #>page_up
        bne .to_move
+       cmp #KEY_F5
        bne +
        lda #<page_down
        ldx #>page_down
        bne .to_move
+       cmp #KEY_HOME
        bne +
        lda .mods
        and #MOD_SHIFT
        beq ++
        jmp clear_all           ; SHIFT + CLR/HOME
++      lda #<home_key
        ldx #>home_key
        bne .to_move
+       cmp #KEY_RETURN
        bne +
        lda #$0d                ; RETURN and SHIFT + RETURN both store CR
        jmp .type
+       cmp #KEY_DEL
        bne +
        lda .mods
        and #MOD_SHIFT
        beq ++
        jmp .inst
++      jmp .del
+       cmp #KEY_F7
        bne +
        lda .mods
        and #MOD_SHIFT
        beq ++
        jmp next_background
++      jmp toggle_mode
+       cmp #KEY_F1             ; F1: the menu
        bne +
        jmp menu_open
+       lda .code               ; any other key: what does it type?
        ldy .mods
        jsr key_to_petscii
        bcc +
        rts                     ; types nothing
+       tax
        lda ctype,x
        bmi +
        jmp .color              ; a color key (A = the color)
+       cmp #CT_RVSON
        bne +
        lda #$80
        jmp .rvs
+       cmp #CT_RVSOFF
        bne +
        lda #0
        jmp .rvs
+       cmp #CT_CHAR
        bne .nothing            ; other control codes: ignored
        txa
        jmp .type
.nothing
        rts

; .mouse - A = a mouse event; where it happened is in click_row,
; click_col and click_icon.
.mouse  cmp #KEY_MOUSE_R
        beq .menu               ; right button: the menu, like F1
        cmp #KEY_MOUSE_DRAG
        beq .drag
        lda click_icon          ; left button: on a border icon?
        beq .click
        cmp #ICON_F3
        bne +
        lda #<page_up           ; (with the mark key: marking by page, as
        ldx #>page_up           ; with the F3 key)
        jmp .move
+       cmp #ICON_F5
        bne .menu               ; (the menu icon)
        lda #<page_down
        ldx #>page_down
        jmp .move
.drag   lda mark_key            ; dragging marks, as if the mark key were
        beq +                   ; held (MARK_LSHIFT = 0)
        lda #MOD_CBM
        bne ++
+       lda #MOD_LSHIFT
++      ora .mods
        sta .mods
.click  lda #<goto_click        ; to the place clicked (with the mark key:
        ldx #>goto_click        ; marking up to it)
        jmp .move
.menu   jmp menu_open           ; (the menu icon, the right button, and
                                ; RUN/STOP or RESTORE above)

; .move - a key that moves the cursor (A/X = the routine that moves it).
; With the mark key held it marks text from where the cursor was; without
; it, any marking goes.
.move   sta .target
        stx .target+1
        jsr .marking
        bcc .plain
        lda sel_on              ; start marking here?
        bne +
        jsr mark_here
+       lda cur_row             ; remember where the cursor and the top of
        sta .old_row            ; the screen were
        lda row_off_lo
        sta .old_top
        lda row_off_hi
        sta .old_top+1
        lda #1                  ; (leave the codes alone while marking)
        sta no_cleanup
        jsr .call
        lda #0
        sta no_cleanup
        jsr get_cursor_off      ; back where it started: nothing marked
        lda work
        cmp sel_anchor
        bne +
        lda work+1
        cmp sel_anchor+1
        bne +
        lda #0
        sta sel_on
+       lda row_off_lo          ; did the screen scroll?
        cmp .old_top
        bne .all
        lda row_off_hi
        cmp .old_top+1
        bne .all
        ldx .old_row            ; no: redraw the rows from the old cursor
        lda cur_row             ; row to the new one
        cmp .old_row
        bcs +
        tax                     ; (the new row is the upper one)
        lda .old_row
+       clc
        adc #1
        sta redraw_stop
        jsr redraw_from
        lda #MROWS
        sta redraw_stop
        rts
.all    jmp redraw_all

.plain  lda sel_on              ; a move without the mark key: unmark
        beq .call
        lda #0
        sta sel_on
        jsr redraw_all
.call   jmp (.target)

; .marking - carry set if the mark key is held (left SHIFT, or C=,
; whichever the mark key setting says).
.marking
        lda .mods
        ldx mark_key
        bne +
        and #MOD_LSHIFT
        jmp ++
+       and #MOD_CBM
++      cmp #1
        rts

; What typing does when text is marked: it replaces it.
.type   ldx sel_on              ; A = the character
        beq +
        pha
        jsr delete_selection
        pla
+       jmp type_char
.del    lda sel_on              ; INST/DEL: delete the marked text, or the
        beq +                   ; character left of the cursor
        jmp delete_selection
+       jmp delete_left
.inst   lda sel_on              ; SHIFT + INST/DEL: delete the marked text
        beq +                   ; first, then a space
        jsr delete_selection
+       jmp insert_space
.color  ldx sel_on              ; a color key: color the marked text, or
        beq +                   ; what is typed next
        jmp recolor_selection
+       jmp color_key
.rvs    ldx sel_on              ; CTRL-9/0: reverse for the marked text,
        beq +                   ; or for what is typed next
        jmp reverse_selection
+       jmp rvs_key

; .reverse - carry set if a cursor key should go the other way: right SHIFT
; (mark key = left SHIFT), or either SHIFT (mark key = C=).
.reverse
        lda .mods
        ldx mark_key
        bne +
        and #MOD_RSHIFT
        jmp ++
+       and #MOD_SHIFT
++      cmp #1                  ; carry set if any of those bits
        rts

.code   !byte 0
.mods   !byte 0
.target !word 0                 ; (JMP (.target) must not cross a page:)
!if <.target = $ff {
        !error "editor_key: .target straddles a page (6502 JMP () bug)"
}
.old_row !byte 0
.old_top !word 0
