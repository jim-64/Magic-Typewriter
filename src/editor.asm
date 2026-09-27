;============================================================================
; editor.asm - text buffer, cursor, typing, drawing the screen
;
; THE TEXT BUFFER
; The document is kept exactly as it is in a PETSCII file: one byte per
; character, lines ending in CR ($0d), color and reverse codes in between.
; It lives in a "gap buffer" from BUF_START to BUF_END:
;
;   BUF_START        gap_start          gap_end             BUF_END
;   | text before the |  (free space)   | text after the     |
;   | cursor          |                 | cursor             |
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
; there, and how many cursor places it has. Rows wrap after 40
; characters (word wrap and sideways scrolling come in phase 6). One extra
; row, below the screen, is measured but not drawn.
;============================================================================

BUF_START       = $4000         ; the text buffer ...
BUF_END         = $d000         ; ... up to here (BASIC ROM banked out)
ROWS            = 25            ; screen rows
MROWS           = 26            ; rows we keep track of: the screen + 1

; Zero page used by the editor (main program only, never the IRQs)
gap_start       = $08           ; first free byte of the gap = the cursor
gap_end         = $0a           ; first byte after the gap
ptr             = $0c           ; walks through the text
ptr2            = $0e           ; a second walking pointer
scr             = $10           ; screen RAM of the row being drawn
clr             = $12           ; color RAM of the row being drawn
cptr            = $14           ; screen RAM of the cursor
ccol            = $16           ; color RAM of the cursor
work            = $18           ; 16-bit scratch

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
mark_key        !byte MARK_LSHIFT ; setting
modified        !byte 0         ; 1 = changed since loaded or saved
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
        lda #<BUF_END
        sta gap_end
        lda #>BUF_END
        sta gap_end+1
        lda #0
        sta modified
        sta want_col
        sta row_off_lo          ; top = offset 0
        sta row_off_hi
        sta row_rvs
        lda text_color          ; the default text color, reverse off
        sta row_color
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
        sec                     ; ... plus after it: BUF_END - gap_end
        lda #<BUF_END
        sbc gap_end
        tax
        lda #>BUF_END
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
        lda gap_end+1
        cmp #>BUF_END
        bcs .end                ; gap_end = BUF_END: nothing after the gap
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
-       lda gap_end+1
        cmp #>BUF_END
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

; move_gap_to - move the cursor to offset "off".
!zone move_gap_to
move_gap_to
-       jsr get_cursor_off
        lda work+1
        cmp off+1
        bcc .right
        bne .left
        lda work
        cmp off
        bcc .right
        beq .done
.left   jsr gap_left
        jmp -
.right  jsr gap_right
        jmp -
.done   rts

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
        lda gap_end+1
        cmp #>BUF_END
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
        beq .skip
        lda ptr                 ; keep only the last color code
        cmp .last_color
        bne .skip
        lda ptr+1
        cmp .last_color+1
        bne .skip
        beq .keep
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
!zone color_before
color_before
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
; Finding rows (for moving up the text)
;============================================================================

; find_row_start - ptr = the start of the screen row that holds the place
; at address "limit" (which is at or before the cursor, so all of this is
; before the gap). That is the last row start at or before it.
!zone find_row_start
find_row_start
        ; The line holding it starts after the last line end before it.
        lda limit
        sta ptr
        lda limit+1
        sta ptr+1
-       lda ptr
        cmp #<BUF_START
        bne +
        lda ptr+1
        cmp #>BUF_START
        beq .line_start
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
        bne .line_start
        inc ptr+1
.line_start
        ; Walk the line row by row, the way redraw splits it, until the
        ; row that holds "limit".
.row    lda ptr                 ; this row starts here
        sta .row_start
        lda ptr+1
        sta .row_start+1
        lda #0
        sta .chars
.walk   lda ptr                 ; reached the limit: it is in this row
        cmp limit
        bne +
        lda ptr+1
        cmp limit+1
        beq .found
+       ldy #0
        lda (ptr),y
        inc ptr
        bne +
        inc ptr+1
+       tax
        lda ctype,x
        cmp #CT_EOL
        beq .row                ; (can't happen before the limit: the line
                                ; ends after it)
        cmp #CT_CHAR
        bne .walk
        inc .chars
        lda .chars
        cmp #40
        bcc .walk
        bcs .row                ; 40 characters: the next row starts here
.found  lda .row_start
        sta ptr
        lda .row_start+1
        sta ptr+1
        rts
.row_start      !word 0
.chars          !byte 0

limit           !word 0         ; argument of find_row_start

; set_top_ptr - make the screen row that starts at address ptr (before the
; cursor) the top row: its offset and the color and reverse state there.
!zone set_top_ptr
set_top_ptr
        jsr ptr_to_off
        lda off
        sta row_off_lo
        lda off+1
        sta row_off_hi
        jsr color_before
        sta row_color
        jsr rvs_before
        sta row_rvs
        rts

; scroll_up_one - move the top of the screen up one row (does not redraw).
; Carry set if the top is already the start of the text.
!zone scroll_up_one
scroll_up_one
        lda row_off_lo
        ora row_off_hi
        bne +
        sec
        rts
+       lda row_off_lo          ; limit = the byte just before the top
        sta off
        lda row_off_hi
        sta off+1
        jsr set_ptr
        lda ptr
        bne +
        dec ptr+1
+       dec ptr
        lda ptr
        sta limit
        lda ptr+1
        sta limit+1
        jsr find_row_start
        jsr set_top_ptr
        clc
        rts

; scroll_down_one - move the top of the screen down one row (row 1 becomes
; row 0; does not redraw).
!zone scroll_down_one
scroll_down_one
        lda row_off_lo+1
        sta row_off_lo
        lda row_off_hi+1
        sta row_off_hi
        lda row_color+1
        sta row_color
        lda row_rvs+1
        sta row_rvs
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
!zone redraw_from
redraw_from
        stx .row
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

.pos    lda ptr                 ; at the gap? jump over it
        cmp gap_start
        bne .read
        lda ptr+1
        cmp gap_start+1
        bne .read
        lda gap_end
        sta ptr
        lda gap_end+1
        sta ptr+1
.read   lda ptr+1
        cmp #>BUF_END
        bcc +
        jmp .eof
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
        bne .not_char
        txa                     ; a character: put it on the screen
        jsr petscii_to_screen
        ora .rvs
        ldy .col
        sta (scr),y
        lda .color
        sta (clr),y
        iny
        sty .col
        cpy #40
        bcc .pos
        ldx .row                ; 40 characters: the row is full
        lda #40
        sta row_len,x
        jmp .next_row
.not_char
        cmp #CT_EOL
        bne .not_eol
        ldx .row                ; line end: one more cursor place, then
        ldy .col                ; blank to the end of the row
        iny
        tya
        sta row_len,x
        jsr .fill
        lda #0                  ; a line end also ends reverse
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
        cmp #MROWS
        bcs +
        jmp .new_row
+       rts

.eof    ldx .row                ; end of the text, in this row
        stx eof_row
        ldy .col
        iny                     ; (one cursor place after the last byte)
        tya
        sta row_len,x
        jsr .fill
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
.color  !byte 0
.rvs    !byte 0
.old_eof !byte 0
.moved  !byte 0

can_stop        !byte 0         ; redraw_from may stop early (see above)
edit_end        !word 0         ; old offset just after the edited part
edit_delta      !word 0         ; how much longer the text got (signed)
old_len         !word 0         ; text length before the edit

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
        bcs .below
        stx cur_row

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
        lda gap_start
        sta limit
        lda gap_start+1
        sta limit+1
        jsr find_row_start
        jsr set_top_ptr
        jsr redraw_all
        jmp -
.below  jsr scroll_down_one     ; below the bottom: scroll down a row
        jsr redraw_all
        jmp -
.ok     rts

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
        lda cur_col
        sta want_col
        rts

; leave_cursor - tidy the codes at the cursor before it moves away.
!zone leave_cursor
leave_cursor
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
-       lda ptr+1               ; find the next visible byte
        cmp #>BUF_END
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
        jsr scroll_up_one
        bcs .none               ; nothing above: the start of the text
        jsr redraw_all
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
-       lda ptr+1
        cmp #>BUF_END
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
        lda cur_col
        sta want_col
        rts

; cursor_down, cursor_up - one screen row down or up, aiming for want_col.
!zone cursor_down
cursor_down
        jsr leave_cursor
        ldx cur_row
        cpx eof_row
        beq .none               ; already on the last row of the text
        cpx #ROWS-1
        bcc +
        jsr scroll_down_one     ; on the bottom row: scroll first
        jsr redraw_all
        ldx #ROWS-2
+       inx
        jmp goto_row
.none   rts

cursor_up
        jsr leave_cursor
        ldx cur_row
        bne +
        jsr scroll_up_one       ; on the top row: scroll first
        bcs .none               ; the start of the text
        jsr redraw_all
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
        jmp locate_cursor
.row    !byte 0
.col    !byte 0
.n      !byte 0

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
        lda #ROWS-1
        sta .count
-       jsr scroll_up_one
        bcs +                   ; reached the start of the text
        dec .count
        bne -
+       jsr redraw_all
        ldx cur_row
        cpx eof_row
        bcc +
        ldx eof_row
+       jmp goto_row
.count  !byte 0

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
        ; Go to the start of this line.
-       jsr move_left
        bcs +
        ldy #0                  ; stop when the byte before is a line end
        jsr .byte_before
        cmp #CT_EOL
        bne -
+       jmp moved
.at_start                       ; already at a line start: top of document
        lda #0
        sta off
        sta off+1
        jsr move_gap_to
        jsr skip_codes
        lda #0
        sta row_off_lo
        sta row_off_hi
        sta row_rvs
        lda text_color
        sta row_color
        jsr redraw_all
        jmp moved

; .byte_before - A = ctype of the last visible byte before the cursor
; (CT_EOL at the start of the text)
.byte_before
        lda gap_start
        sta ptr
        lda gap_start+1
        sta ptr+1
-       lda ptr
        cmp #<BUF_START
        bne +
        lda ptr+1
        cmp #>BUF_START
        beq .eol
+       lda ptr
        bne +
        dec ptr+1
+       dec ptr
        ldy #0
        lda (ptr),y
        jsr is_visible
        bcs -
        lda ctype,x
        rts
.eol    lda #CT_EOL
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

; clear_all - SHIFT + CLR/HOME: after asking, empty the document.
!zone clear_all
clear_all
        lda #<msg_clear_all
        ldx #>msg_clear_all
        jsr prompt_yes_no
        bcc +
        jsr empty_buffer
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
        cmp #KEY_STOP
        beq .quit
        cmp #KEY_RESTORE
        beq .quit
        cmp #KEY_CHARSET
        bne +
        jmp toggle_charset
+       jsr cursor_hide
        jsr .do_key
        jmp cursor_show

.quit   lda #<msg_quit          ; (the menu takes RUN/STOP in phase 8)
        ldx #>msg_quit
        jsr prompt_yes_no
        bcc +
        jmp quit
+       rts

.do_key lda .code
        cmp #KEY_RIGHT
        bne +
        jsr .reverse
        bcs ++
        jmp cursor_right
++      jmp cursor_left
+       cmp #KEY_DOWN
        bne +
        jsr .reverse
        bcs ++
        jmp cursor_down
++      jmp cursor_up
+       cmp #KEY_RETURN
        bne +
        lda #$0d                ; RETURN and SHIFT + RETURN both store CR
        jmp type_char
+       cmp #KEY_DEL
        bne +
        lda .mods
        and #MOD_SHIFT
        beq ++
        jmp insert_space
++      jmp delete_left
+       cmp #KEY_HOME
        bne +
        lda .mods
        and #MOD_SHIFT
        beq ++
        jmp clear_all
++      jmp home_key
+       cmp #KEY_F7
        bne +
        lda .mods
        and #MOD_SHIFT
        beq ++
        jmp next_background
++      jmp toggle_mode
+       cmp #KEY_F3
        bne +
        jmp page_up
+       cmp #KEY_F5
        bne +
        jmp page_down
+       cmp #KEY_F1
        bne +
        rts                     ; (opens the menu in phase 8)
+       lda .code               ; any other key: what does it type?
        ldy .mods
        jsr key_to_petscii
        bcs .nothing
        tax
        lda ctype,x
        bmi +
        jmp color_key           ; a color key (A = the color)
+       cmp #CT_RVSON
        bne +
        lda #$80
        jmp rvs_key
+       cmp #CT_RVSOFF
        bne +
        lda #0
        jmp rvs_key
+       cmp #CT_CHAR
        bne .nothing            ; other control codes: ignored
        txa
        jmp type_char
.nothing
        rts

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

;============================================================================
; Yes/no questions
;============================================================================

; prompt_yes_no - ask a question in a box in the middle of the screen.
; A/X = the question: screen codes ending in 0, written in lower case
; (screen codes 1-26), which shows as capitals in either character set.
; Waits for Y, or N / RUN/STOP. Returns carry set for Y.
; Puts back what was under the box.
PROMPT_ROW      = 11            ; the box uses rows 11-13
!zone prompt_yes_no
prompt_yes_no
        sta zp_ptr2
        stx zp_ptr2+1
        lda cursor_shown        ; show the cursor again afterwards only if
        sta .had_cursor         ; it was showing now
        jsr cursor_hide
        jsr readable_color      ; the box's color
        sta .color
        ldy #0                  ; length of the question
-       lda (zp_ptr2),y
        beq +
        iny
        bne -
+       sty .len
        tya                     ; box width: question + a space each side
        clc                     ; + the two sides
        adc #4
        sta .width
        lda #40                 ; centered
        sec
        sbc .width
        lsr
        sta .left

        jsr .save
        ; Top and bottom edges
        ldx #PROMPT_ROW
        lda #$70                ; top left corner
        ldy #$6e                ; top right corner
        jsr .edge
        ldx #PROMPT_ROW+2
        lda #$6d                ; bottom left corner
        ldy #$7d                ; bottom right corner
        jsr .edge
        ; The middle row: side, space, question, space, side
        ldx #PROMPT_ROW+1
        jsr .row_at_left
        ldy #0
        lda #$5d                ; side
        jsr .put
        lda #$20
        jsr .put
        ldx #0
-       stx .i
        txa
        tay
        lda (zp_ptr2),y
        beq +
        jsr .capitals
        ldy .i
        iny
        iny
        jsr .put
        ldx .i
        inx
        bne -
+       ldy .width              ; a space, then the right side
        dey
        dey
        lda #$20
        jsr .put
        lda #$5d
        jsr .put

.wait
!if DEBUG {
        jsr mailbox_poll
}
        jsr get_key
        bcs .wait
!if DEBUG {
        jsr mailbox_log_key
}
        cmp #KEY_Y
        beq .yes
        cmp #KEY_N
        beq .no
        cmp #KEY_STOP
        beq .no
        cmp #KEY_RESTORE
        beq .no
        bne .wait
.yes    jsr .restore
        jsr .cursor_back
        sec
        rts
.no     jsr .restore
        jsr .cursor_back
        clc
        rts
.cursor_back
        lda .had_cursor
        beq +
        jmp cursor_show
+       rts

; .edge - X = row, A = left corner, Y = right corner: a horizontal edge
.edge   sta .a
        sty .b
        jsr .row_at_left
        ldy #0
        lda .a
        jsr .put
-       lda #$40                ; horizontal line
        jsr .put
        cpy .width
        bcc -
        dey
        lda .b
        ; (falls into .put)

; .put - A at column Y of the box row (zp_ptr, work), in .color;
; Y moves on by one
.put    sta (zp_ptr),y
        lda .color
        sta (work),y
        iny
        rts

; .row_at_left - zp_ptr = screen, work = color RAM at row X, column .left
.row_at_left
        lda row_lo,x
        clc
        adc .left
        sta zp_ptr
        sta work
        lda row_hi,x
        adc #0
        sta zp_ptr+1
        clc
        adc #>(COLOR_RAM - SCREEN)
        sta work+1
        rts

; readable_color - A = the color for prompts and menus: the default text
; color, unless the background is set to that same color - then black or
; white, whichever shows up better on it.
readable_color
        lda text_color
        cmp text_bg
        bne +
        ldx text_bg
        lda contrast_color,x
+       rts

; .capitals - letters (screen codes 1-26) as capitals in the character set
; that is on: in the upper/lower set, capitals are 65-90.
.capitals
        cmp #1
        bcc +
        cmp #27
        bcs +
        tax
        lda VIC_MEMPTR
        and #%00000010
        beq ++                  ; upper/graphics set: 1-26 are capitals
        txa
        ora #$40
        rts
++      txa
+       rts

; .save / .restore - what is under the box (3 rows of .width)
.save   ldx #0                  ; index into prompt_save
        lda #PROMPT_ROW
        sta .r
-       stx .i
        ldx .r
        jsr .row_at_left
        ldx .i
        ldy #0
--      lda (zp_ptr),y
        sta prompt_save,x
        lda (work),y
        sta prompt_save+120,x
        inx
        iny
        cpy .width
        bcc --
        inc .r
        lda .r
        cmp #PROMPT_ROW+3
        bcc -
        rts
.restore
        ldx #0
        lda #PROMPT_ROW
        sta .r
-       stx .i
        ldx .r
        jsr .row_at_left
        ldx .i
        ldy #0
--      lda prompt_save,x
        sta (zp_ptr),y
        lda prompt_save+120,x
        sta (work),y
        inx
        iny
        cpy .width
        bcc --
        inc .r
        lda .r
        cmp #PROMPT_ROW+3
        bcc -
        rts

.had_cursor !byte 0
.color  !byte 0
.len    !byte 0
.width  !byte 0
.left   !byte 0
.i      !byte 0
.r      !byte 0
.a      !byte 0
.b      !byte 0

;============================================================================
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
