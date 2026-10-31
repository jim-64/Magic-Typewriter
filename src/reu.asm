;============================================================================
; reu.asm - the REU (RAM Expansion Unit), if there is one
;
; A Commodore 1700/1764/1750 REU - or one that works the same way: the
; Ultimate's, VICE's, the MEGA65's - copies between the C64's memory and
; its own by DMA, one byte a cycle, with the CPU stopped meanwhile: several
; times as fast as a copy loop. The editor uses two of its 64 KB banks:
;   bank 0   a stopover for block copies (block_copy_fwd/back in the
;            editor): the bytes go to the REU and come back to their new
;            place, so it doesn't matter if the two places overlap
;   bank 1   the clipboard (copy_selection, paste), so the clipboard takes
;            no room from the text
;
; While the CPU is stopped it can't answer an IRQ, and the exact-timed
; strip IRQs (irq.asm) must come on time: the line 25 one has only about a
; line to spare. So reu_move copies in pieces of REU_CHUNK bytes (about two
; raster lines) and starts one only when none of those IRQs, nor a page
; marker IRQ, is due within the next REU_WINDOW lines. It waits with
; interrupts on, and turns them off only for the moment of starting.
;
; Lives in the lower part (the editor at $e000 calls it).
;============================================================================
REU_COMMAND     = $df01         ; bit 7: go; bit 4: at once (not on a write
                                ; to $ff00); bits 0-1: 0 = C64 -> REU
                                ; ("stash"), 1 = REU -> C64 ("fetch")
REU_C64         = $df02         ; C64 address (lo/hi)
REU_ADDR        = $df04         ; REU address (lo/hi) ...
REU_BANK        = $df06         ; ... and its 64 KB bank
REU_LEN         = $df07         ; how many bytes (lo/hi)
REU_IRQ_MASK    = $df09         ; 0: no IRQs from the REU
REU_CONTROL     = $df0a         ; 0: both addresses count up
REU_STASH       = $90           ; commands: go at once, C64 -> REU ...
REU_FETCH       = $91           ; ... REU -> C64
REU_CHUNK       = 128           ; bytes per piece (about two raster lines)
REU_WINDOW      = 8             ; lines kept clear before an exact IRQ: up
                                ; to 3 for the checking, up to 3 for a
                                ; piece (a badline and the pointer sprite
                                ; can stretch it), and 2 to spare
REU_BANK_MOVES  = 0             ; the banks the editor uses
REU_BANK_CLIP   = 1

reu_banks       !byte 0         ; the REU's size in 64 KB banks (0 = none)
reu_c64         !word 0         ; for reu_move: the C64 address,
reu_addr        !word 0         ;   the REU address,
reu_bank        !byte 0         ;   the REU bank,
reu_len         !word 0         ;   how many bytes
clip_size       !word 0         ; the clipboard's size, when it is in the REU
blk_count       !word 0         ; bytes for block_copy / reu_copy (here, not
                                ; in the editor: long documents copy during
                                ; disk work too, with the KERNAL ROM in)
reu_docs        !byte 0         ; 1: long documents in the REU (reudoc.asm)
win_color       !byte $ff       ; the color in effect at the text buffer's
                                ; start ($ff: the default text color; with
                                ; a long document, the window's start may
                                ; be further on)
buf_top         !word BUF_END   ; the end of the text buffer ($c000 with
                                ; long documents: reudoc.asm lies above)

;----------------------------------------------------------------------------
; start_color - A = the color in effect at the start of the text buffer:
; the default text color, or with a long document the color where the
; window starts (color_before and empty_view in the editor)
;----------------------------------------------------------------------------
start_color
        lda win_color
        bpl +
        lda text_color
+       rts

;----------------------------------------------------------------------------
; reu_move - copy reu_len bytes between the C64 (from reu_c64 on) and the
; REU (from reu_addr in bank reu_bank on): A = REU_STASH (to the REU) or
; REU_FETCH (from it). In pieces, each started only when it can't hold up
; an IRQ that must come on time (see above). Interrupts are on afterwards.
;----------------------------------------------------------------------------
!zone reu_move
reu_move
        sta .cmd
        lda reu_c64             ; the addresses once: after each piece the
        sta REU_C64             ; REU's registers point just past it
        lda reu_c64+1
        sta REU_C64+1
        lda reu_addr
        sta REU_ADDR
        lda reu_addr+1
        sta REU_ADDR+1
        lda reu_bank
        sta REU_BANK
.piece  ldx #REU_CHUNK          ; this piece: REU_CHUNK bytes, or what is
        lda reu_len+1           ; left if that is less
        bne +
        cpx reu_len
        bcc +
        ldx reu_len
        beq .done
+       stx REU_LEN
        lda #0
        sta REU_LEN+1
.wait   cli                     ; (waiting: interrupts on, so none is late)
        lda VIC_RASTER          ; not within REU_WINDOW lines before an IRQ
        sta .line               ; that must come on time: the strip IRQs at
        lda #TOP_A_LINE         ; lines 25 and 247, and the page marker's
        sec                     ; (0 when it has none: then a few lines
        sbc .line               ; near 0 wait for nothing, which is fine).
        cmp #REU_WINDOW         ; Only the low 8 bits count: on PAL, lines
        bcc .wait               ; 256-311 sometimes wait for nothing too.
        lda #BOT_A_LINE
        sec
        sbc .line
        cmp #REU_WINDOW
        bcc .wait
        lda irq_mark_top
        sec
        sbc .line
        cmp #REU_WINDOW
        bcc .wait
        lda irq_mark_bot
        sec
        sbc .line
        cmp #REU_WINDOW
        bcc .wait
        lda VIC_RASTER          ; clear. Is the beam still at most 2 lines
        sec                     ; on from the line checked? (If an IRQ came
        sbc .line               ; in meanwhile, it has gone on further:
        cmp #3                  ; then check again.)
        bcs .wait
        sei                     ; the same once more with interrupts off,
        lda VIC_RASTER          ; for an IRQ in the last few cycles (then
        sec                     ; they are on again at once, so that one
        sbc .line               ; can hardly hold up another)
        cmp #3
        bcs .wait
        lda .cmd                ; go: the CPU stops until it is done
        sta REU_COMMAND
        cli
        stx .n                  ; that much less to go
        sec
        lda reu_len
        sbc .n
        sta reu_len
        bcs .piece
        dec reu_len+1
        jmp .piece
.done   cli
        rts

.cmd    !byte 0
.line   !byte 0
.n      !byte 0

;----------------------------------------------------------------------------
; reu_copy - a block copy through the REU (bank 0), for block_copy_fwd
; (A = 0: ptr and ptr2 are where the bytes start and will start, and end up
; just after them) and block_copy_back (A = 1: ptr and ptr2 are just after
; the bytes, and end up at their starts). blk_count bytes; it ends up 0.
;----------------------------------------------------------------------------
!zone reu_copy
reu_copy
        sta .back
        tax
        beq +
        jsr .down               ; (back: from the ends to the starts)
+       lda ptr                 ; to the REU ...
        sta reu_c64
        lda ptr+1
        sta reu_c64+1
        jsr .setup
        lda #REU_STASH
        jsr reu_move
        lda ptr2                ; ... and back to the new place
        sta reu_c64
        lda ptr2+1
        sta reu_c64+1
        jsr .setup
        lda #REU_FETCH
        jsr reu_move
        lda .back
        bne +
        jsr .up                 ; (forward: to just after the bytes)
+       lda #0
        sta blk_count
        sta blk_count+1
        rts

; .setup - the REU side: the start of bank 0, blk_count bytes
.setup  lda #0
        sta reu_addr
        sta reu_addr+1
        lda #REU_BANK_MOVES
        sta reu_bank
        lda blk_count
        sta reu_len
        lda blk_count+1
        sta reu_len+1
        rts

; .down / .up - ptr and ptr2 back / on by blk_count
.down   sec
        lda ptr
        sbc blk_count
        sta ptr
        lda ptr+1
        sbc blk_count+1
        sta ptr+1
        sec
        lda ptr2
        sbc blk_count
        sta ptr2
        lda ptr2+1
        sbc blk_count+1
        sta ptr2+1
        rts
.up     clc
        lda ptr
        adc blk_count
        sta ptr
        lda ptr+1
        adc blk_count+1
        sta ptr+1
        clc
        lda ptr2
        adc blk_count
        sta ptr2
        lda ptr2+1
        adc blk_count+1
        sta ptr2+1
        rts

.back   !byte 0

;----------------------------------------------------------------------------
; reudoc_copy - long documents only: reudoc.asm ($bc00-$cbff) to REU bank 0
; at $f000 (A = REU_STASH) or back (A = REU_FETCH). A tape program is
; loaded with the KERNAL's LOAD, which doesn't stop at the window's end;
; one saved without an REU may be longer (fileio.asm, load_file).
;----------------------------------------------------------------------------
reudoc_copy
        ldx reu_docs
        beq +
        pha
        lda #<REUDOC
        sta reu_c64
        lda #>REUDOC
        sta reu_c64+1
        lda #$00
        sta reu_addr
        sta reu_len
        lda #$f0
        sta reu_addr+1
        lda #REU_BANK_MOVES
        sta reu_bank
        lda #$10
        sta reu_len+1
        pla
        jmp reu_move
+       rts

;----------------------------------------------------------------------------
; clip_stash - put blk_count bytes from ptr into the clipboard (REU bank 1)
; clip_fetch - copy the clipboard (clip_size bytes) to ptr
;----------------------------------------------------------------------------
!zone clip_stash
clip_stash
        lda blk_count
        sta clip_size
        lda blk_count+1
        sta clip_size+1
        lda #REU_STASH
        jmp .move
clip_fetch
        lda #REU_FETCH
.move   pha
        lda ptr
        sta reu_c64
        lda ptr+1
        sta reu_c64+1
        lda #0
        sta reu_addr
        sta reu_addr+1
        lda #REU_BANK_CLIP
        sta reu_bank
        lda clip_size
        sta reu_len
        lda clip_size+1
        sta reu_len+1
        pla
        jmp reu_move
