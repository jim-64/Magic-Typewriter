;============================================================================
; startup.asm - everything that runs once, at start-up
;
; The PRG file carries this last, after the stored copies of the editor and
; of reudoc.asm: in the text buffer ($4000 on). It runs from there once,
; before any text is typed or loaded, and the document then takes the room
; (so none of it may be called afterwards). That keeps the lower part of
; the program free for code that is needed all the time.
;
; start (main.asm) jumps to startup; startup goes back to start_done.
;============================================================================

startup
        ; Step 1: read $BA before anything else touches it. It holds the
        ; device the program was loaded from (used for MAGIC T DEFAULTS).
        lda LAST_DEVICE
        sta load_device
        ldx #ZP_END-ZP_START-1  ; a copy of BASIC's zero page, for quit
-       lda ZP_START,x
        sta basic_zp,x
        dex
        bpl -

        sei                   ; no interrupts while we set things up
        cld

        jsr copy_high           ; the editor to its place under the KERNAL
        jsr detect_system       ; PAL / NTSC / old NTSC / Drean
        jsr copy_border         ; ... and its border code to its place
        jsr detect_reu          ; an REU? (reu.asm)
        jsr reudoc_install      ; big enough for long documents?
        sec                     ; 1 KB at the top of the text buffer for
        lda buf_top             ; CTRL-Z's log (undo.asm)
        sta undo_end
        sbc #<UNDO_SIZE
        sta buf_top
        sta undo_base
        lda buf_top+1
        sta undo_end+1
        sbc #>UNDO_SIZE
        sta buf_top+1
        sta undo_base+1
        lda #1
        jsr undo_reset
!if DEBUG {
        jsr mailbox_init
}

        ; Switch out the BASIC and KERNAL ROMs: $a000-$bfff becomes RAM for
        ; the text buffer, and the editor at $e000 comes into view. With
        ; the KERNAL ROM out, the CPU takes its NMI and IRQ vectors from the
        ; RAM at $fffa-$ffff, so ours go there first.
        lda #<nmi_handler       ; RESTORE (input.asm)
        sta RAM_NMI_VECTOR
        lda #>nmi_handler
        sta RAM_NMI_VECTOR+1
        lda #<irq_entry         ; a copy of the KERNAL's IRQ entry (irq.asm)
        sta RAM_IRQ_VECTOR
        lda #>irq_entry
        sta RAM_IRQ_VECTOR+1
        lda #ROMS_EDIT
        sta CPU_PORT

        jsr init_screen
        jsr init_sprites
        jsr init_marker
        jsr init_keyboard
        jsr init_mouse
        jsr init_irq
        cli
        jsr load_defaults       ; the settings saved with Save defaults
        lda save_format         ; (a new document's Save format, for
        sta default_save_format ; CLEAR ALL to go back to)
        jmp start_done          ; (the editor: main.asm)

;----------------------------------------------------------------------------
; From main.asm
;----------------------------------------------------------------------------
;----------------------------------------------------------------------------
; init_screen - VIC settings and colors. (The editor draws the text.)
;----------------------------------------------------------------------------
!zone init_screen
init_screen
        lda #CTRL1_25ROWS
        sta VIC_CTRL1
        lda #CSEL_40            ; 40 columns, no X scroll, no multicolor
        sta VIC_CTRL2
        lda #MEMPTR_LOWER       ; default: upper/lower case set
        sta VIC_MEMPTR
        lda #BLUE               ; top strip color until the first split
        sta VIC_BORDER
        lda #STRIP_BG
        sta VIC_BG0
        rts

;----------------------------------------------------------------------------
; copy_high - copy the editor from where the PRG file put it (right after
; the lower part of the program) to $e000, the RAM under the KERNAL ROM.
; A write always reaches the RAM, even while the ROM is switched in (only
; reads see the ROM), so this works before the ROMs are switched out.
; It copies whole pages; the few bytes past the end do no harm (the
; vectors at $fffa are set afterwards).
;----------------------------------------------------------------------------
!zone copy_high
copy_high
        lda #<high_load         ; from
        sta zp_ptr
        lda #>high_load
        sta zp_ptr+1
        lda #<HIGH_CODE         ; to
        sta zp_ptr2
        lda #>HIGH_CODE
        sta zp_ptr2+1
        ldx #>(HIGH_SIZE + 255) ; number of pages
        ldy #0
-       lda (zp_ptr),y
        sta (zp_ptr2),y
        iny
        bne -
        inc zp_ptr+1            ; next page
        inc zp_ptr2+1
        dex
        bne -
        rts

;----------------------------------------------------------------------------
; From system.asm
;----------------------------------------------------------------------------
;----------------------------------------------------------------------------
; detect_system - find out which video system this machine has.
;
; First find the highest raster line: wait for $D012 to change, and stop
; when the new value is lower than the old one (the frame wrapped to line 0).
; The low byte of the last line tells us:
;   $37 = line 311 (PAL or Drean), $06 = line 262 (NTSC), $05 = 261 (old NTSC)
;
; PAL and Drean both have 312 lines, but Drean lines are 65 cycles long
; instead of 63, so we time one whole frame with CIA1 timer B:
;   PAL 312*63 = 19656 cycles, Drean 312*65 = 20280 cycles.
;
; Call with interrupts off. Sets system_type.
;----------------------------------------------------------------------------
!zone detect_system
detect_system
-       lda VIC_RASTER
--      cmp VIC_RASTER          ; wait for the line to change
        beq --
        bmi -                   ; new line is higher: keep going
                                ; (the 255->256 step also lands here, since
                                ; $ff - $00 is negative as a signed byte)
        ldx #SYS_NTSC
        cmp #$06
        beq .found
        ldx #SYS_OLD_NTSC
        cmp #$05
        beq .found

        ; 312 lines: PAL or Drean? Time one frame.
        jsr wait_line0
        lda #$ff                ; timer B counts down from $ffff
        sta CIA1_TBLO
        sta CIA1_TBHI
        lda #%00010001          ; force load, start, count CPU cycles
        sta CIA1_CRB
        jsr wait_line0
        lda #%00000000          ; stop the timer so we can read it safely
        sta CIA1_CRB
        lda CIA1_TBHI           ; cycles used = $ffff - timer, so the
        eor #$ff                ; high byte of the count is (timer hi EOR $ff)
        ldx #SYS_PAL            ; PAL gives $4c, Drean gives $4f
        cmp #$4e
        bcc .found
        ldx #SYS_DREAN
.found  stx system_type
        rts

; wait_line0 - wait for the start of raster line 0.
; (Line 256 also reads 0 in $D012, so check bit 7 of $D011 as well.)
wait_line0
-       lda VIC_RASTER          ; first get off line 0 / 256
        beq -
--      lda VIC_RASTER          ; then wait for it to come round again
        bne --
        lda VIC_CTRL1
        bmi -                   ; that was line 256, not line 0
        rts

;----------------------------------------------------------------------------
; From reu.asm
;----------------------------------------------------------------------------
;----------------------------------------------------------------------------
; detect_reu - is there an REU, and how big? Sets reu_banks (the editor
; needs two banks; an REU always has at least two). Call with interrupts
; off, at start-up.
;
; An REU's address registers keep what is written to them; without an
; REU, $df02-$df05 read back whatever happens to be on the bus. Then the
; size: write each bank's number into its first byte, from bank 255 down
; to 0, and read them back from bank 0 up. A smaller REU wraps round (bank
; 8 of a 512 KB one is bank 0 again), so the first bank that doesn't hold
; its own number is one past the end.
;----------------------------------------------------------------------------
!zone detect_reu
detect_reu
        lda #$55                ; two patterns, to be sure
        jsr .regs
        bne .none
        lda #$aa
        jsr .regs
        bne .none
        lda #0
        sta REU_CONTROL
        sta REU_IRQ_MASK
        ldx #255                ; each bank's number into its first byte
-       stx .byte
        lda #REU_STASH
        jsr .one
        dex
        cpx #255
        bne -
        ldx #0                  ; read back from bank 0 up
-       lda #REU_FETCH
        jsr .one
        cpx .byte
        bne .size               ; not its own number: one past the end
        inx
        bne -
        dex                     ; (all 256 banks: 16 MB, counted as 255)
.size   stx reu_banks
        cpx #2
        bcs +
.none   lda #0
        sta reu_banks
+       rts

; .regs - A = a pattern: write it (changed a little for each) into the 4
; address registers and read them back. Z set if they kept it.
.regs   sta .p
        ldx #3
-       txa
        eor .p
        sta REU_C64,x
        dex
        bpl -
        ldx #3
-       txa
        eor .p
        cmp REU_C64,x
        bne +
        dex
        bpl -
        lda #0                  ; (Z set: all kept)
+       rts

; .one - copy .byte to (A = REU_STASH) or from (A = REU_FETCH) the first
; byte of REU bank X
.one    ldy #<.byte
        sty REU_C64
        ldy #>.byte
        sty REU_C64+1
        ldy #0
        sty REU_ADDR
        sty REU_ADDR+1
        sty REU_LEN+1
        stx REU_BANK
        iny
        sty REU_LEN
        sta REU_COMMAND         ; (the CPU waits until it is done)
        rts

.byte   !byte 0
.p      !byte 0

;----------------------------------------------------------------------------
; reudoc_install - start-up, after detect_reu: with an REU of 3 banks or
; more, long documents: the code for them (reudoc.asm, carried in the PRG
; file after the editor) goes to $c000, and the text buffer ends there.
; Without one, nothing: that RAM stays part of the text buffer.
;----------------------------------------------------------------------------
!zone reudoc_install
reudoc_install
        lda reu_banks
        cmp #3
        bcc .none
        lda #1
        sta reu_docs
        lda #<reudoc_load       ; the copy: page by page, then the rest
        sta zp_ptr
        lda #>reudoc_load
        sta zp_ptr+1
        lda #<REUDOC
        sta zp_ptr2
        lda #>REUDOC
        sta zp_ptr2+1
        ldx #(>REUDOC_SIZE)+1   ; (whole pages, one more to be sure)
        ldy #0
-       lda (zp_ptr),y
        sta (zp_ptr2),y
        iny
        bne -
        inc zp_ptr+1
        inc zp_ptr2+1
        dex
        bne -
        lda #<REUDOC
        sta buf_top
        lda #>REUDOC
        sta buf_top+1
.none   rts

;----------------------------------------------------------------------------
; From irq.asm
;----------------------------------------------------------------------------
; init_marker - start with an empty document: all of it visible. (The
; editor updates the marker after every redraw: update_marker.)
init_marker
        lda #0
        sta mk_total
        sta mk_total+1
        jsr marker_set
        jmp marker_apply

!zone init_sprites
init_sprites
        ; Clear all six blocks ($3e80-$3fff), which also makes $3fff = 0.
        lda #0
        ldx #0
-       sta SPRITE_BASE+$80,x   ; $3f00-$3fff
        inx
        bne -
        ldx #$7f
-       sta SPRITE_BASE,x       ; $3e80-$3eff
        dex
        bpl -

        ; Copy the stored rows into the blocks.
        lda #<spr_pointer
        ldx #>spr_pointer
        ldy #SPR_BLOCK_PTR
        jsr .copy
        lda #<spr_menu
        ldx #>spr_menu
        ldy #SPR_BLOCK_MENU
        jsr .copy
        lda #<spr_f3
        ldx #>spr_f3
        ldy #SPR_BLOCK_F3
        jsr .copy
        lda #<spr_f5
        ldx #>spr_f5
        ldy #SPR_BLOCK_F5
        jsr .copy
        lda #<spr_pointer_low
        ldx #>spr_pointer_low
        ldy #SPR_BLOCK_PTR_LOW
        jsr .copy

        ; Sprite pointers
        lda #SPR_BLOCK_PTR
        sta SPRITE_PTRS+0
        lda #SPR_BLOCK_MENU
        sta SPRITE_PTRS+1
        lda #SPR_BLOCK_F3
        sta SPRITE_PTRS+2
        sta SPRITE_PTRS+3
        lda #SPR_BLOCK_F5
        sta SPRITE_PTRS+4
        sta SPRITE_PTRS+5

        ; Positions (table in data.asm: X low byte, Y for sprites 0-5)
        ldx #0
-       lda spr_positions,x
        sta VIC_SPR0_X,x
        inx
        cpx #12
        bne -
        lda #SPR_XMSB_BITS
        sta VIC_SPR_XMSB

        ; Colors
        lda #RED
        sta VIC_SPR0_COLOR
        lda #LIGHT_BLUE
        ldx #5
-       sta VIC_SPR0_COLOR,x
        dex
        bne -

        lda #0                  ; hi-res, normal size, in front of text
        sta VIC_SPR_MCOLOR
        sta VIC_SPR_EXPX
        sta VIC_SPR_EXPY
        sta VIC_SPR_PRIO
        lda #SPR_ON_ICONS       ; (the pointer shows once a mouse is found)
        sta VIC_SPR_ENABLE
        rts

; .copy - copy sprite rows into a block. A/X = source address, Y = block.
; Source: first row in the block (0-20), byte count, then the bytes.
.copy   sta zp_ptr
        stx zp_ptr+1
        lda #0                  ; destination = block * 64 ...
        sta zp_ptr2+1
        tya
        ldx #6
-       asl
        rol zp_ptr2+1
        dex
        bne -
        sta zp_ptr2
        ldy #0                  ; ... + first row * 3
        lda (zp_ptr),y
        sta zp_tmp
        asl
        adc zp_tmp              ; row*2 + row (carry is clear: row < 21)
        adc zp_ptr2             ; block*64 low byte is at most 192, and
        sta zp_ptr2             ; row*3 at most 60: no carry out
        iny
        lda (zp_ptr),y          ; byte count
        tax
        lda zp_ptr              ; skip the two header bytes
        clc
        adc #2
        sta zp_ptr
        bcc +
        inc zp_ptr+1
+       ldy #0
-       lda (zp_ptr),y
        sta (zp_ptr2),y
        iny
        dex
        bne -
        rts

;----------------------------------------------------------------------------
; Sprite images. Only the rows that are used are stored; init_sprites
; copies them into empty 64-byte sprite blocks.
; Header: first row in the block (0-20), then the number of bytes that
; follow (3 bytes per 24-pixel row). See the notes above init_sprites in
; irq.asm for why the top badges and the menu icon sit low in their blocks.
;----------------------------------------------------------------------------

; Mouse pointer: 8x8 box, red
spr_pointer
        !byte 0, 8*3
        !byte %11111111,0,0
        !byte %11000011,0,0
        !byte %11000011,0,0
        !byte %11000011,0,0
        !byte %11000011,0,0
        !byte %11000011,0,0
        !byte %11000011,0,0
        !byte %11111111,0,0

; The same box low in its block (rows 13-20). The VIC fetches all 21 rows
; of a sprite from its top line, and near the bottom of the text area those
; fetches must stay clear of the bottom strip's exact timing: there the
; pointer uses this picture, with its fetches above the box instead.
spr_pointer_low
        !byte 13, 8*3
        !byte %11111111,0,0
        !byte %11000011,0,0
        !byte %11000011,0,0
        !byte %11000011,0,0
        !byte %11000011,0,0
        !byte %11000011,0,0
        !byte %11000011,0,0
        !byte %11111111,0,0

; Menu icon "=F1": the three bars and F1 cut out of a solid box with a
; pixel off each corner (Jim, phase 12: "M1", to go with the badges);
; 23x9, rows 12-20 (lines 41-49, level with the F3 badges)
spr_menu
        !byte 12, 9*3
        !byte $7f,$ff,$fc       ; .XXXXXXXXXXXXXXXXXXXXX..
        !byte $c0,$30,$ce       ; XX........XX....XX..XXX.
        !byte $ff,$f3,$8e       ; XXXXXXXXXXXX..XXX...XXX.
        !byte $ff,$f3,$ce       ; XXXXXXXXXXXX..XXXX..XXX.
        !byte $c0,$31,$ce       ; XX........XX...XXX..XXX.
        !byte $ff,$f3,$ce       ; XXXXXXXXXXXX..XXXX..XXX.
        !byte $ff,$f3,$ce       ; XXXXXXXXXXXX..XXXX..XXX.
        !byte $c0,$33,$86       ; XX........XX..XXX....XX.
        !byte $7f,$ff,$fc       ; .XXXXXXXXXXXXXXXXXXXXX..

; "F3" badge: page up. A solid up arrow with F3 cut out of it (Jim's
; choice, phase 12: "SB3C"); 24x9, rows 12-20 (lines 41-49). The letters
; need a solid row above and below them, so the badge is 9 rows; the
; 13-row badges of the mockup were cut off on Jim's NTSC 1702.
spr_f3
        !byte 12, 9*3
        !byte $03,$ff,$c0       ; ......XXXXXXXXXXXX......
        !byte $06,$18,$e0       ; .....XX....XX...XXX.....
        !byte $0e,$72,$70       ; ....XXX..XXX..X..XXX....
        !byte $1e,$7e,$78       ; ...XXXX..XXXXXX..XXXX...
        !byte $3e,$3c,$fc       ; ..XXXXX...XXXX..XXXXXX..
        !byte $06,$7e,$60       ; .....XX..XXXXXX..XX.....
        !byte $06,$72,$60       ; .....XX..XXX..X..XX.....
        !byte $06,$78,$e0       ; .....XX..XXXX...XXX.....
        !byte $07,$ff,$e0       ; .....XXXXXXXXXXXXXX.....

; "F5" badge: page down. The same arrow upside down, with F5 cut out
; (24x9, rows 0-8: lines 252-260)
spr_f5
        !byte 0, 9*3
        !byte $07,$ff,$e0       ; .....XXXXXXXXXXXXXX.....
        !byte $06,$10,$60       ; .....XX....X.....XX.....
        !byte $06,$73,$e0       ; .....XX..XXX..XXXXX.....
        !byte $06,$70,$e0       ; .....XX..XXX....XXX.....
        !byte $3e,$3e,$7c       ; ..XXXXX...XXXXX..XXXXX..
        !byte $1e,$7e,$78       ; ...XXXX..XXXXXX..XXXX...
        !byte $0e,$72,$70       ; ....XXX..XXX..X..XXX....
        !byte $06,$78,$e0       ; .....XX..XXXX...XXX.....
        !byte $03,$ff,$c0       ; ......XXXXXXXXXXXX......

spr_positions
        !byte <PTR_TEST_X,   PTR_TEST_Y         ; 0 pointer
        !byte <SPR_MENU_X,   SPR_TOP_Y          ; 1 menu icon
        !byte <SPR_LEFT_X,   SPR_TOP_Y          ; 2 F3 left
        !byte <SPR_RIGHT_X,  SPR_TOP_Y          ; 3 F3 right
        !byte <SPR_LEFT_X,   SPR_BOT_Y          ; 4 F5 left
        !byte <SPR_RIGHT_X,  SPR_BOT_Y          ; 5 F5 right

;----------------------------------------------------------------------------
; From input.asm
;----------------------------------------------------------------------------
;----------------------------------------------------------------------------
; init_keyboard - timing values for this system, RESTORE trap.
; Call with IRQs off.
;----------------------------------------------------------------------------
!zone init_keyboard
init_keyboard
        ldx system_type
        lda tab_repeat_step,x
        sta key_step

        ; RESTORE makes an NMI. The KERNAL's NMI handler would warm-start
        ; BASIC on RUN/STOP + RESTORE and lose the document, so send it to
        ; our own handler instead.
        lda NMI_VECTOR
        sta old_nmi
        lda NMI_VECTOR+1
        sta old_nmi+1
        lda #<nmi_handler
        sta NMI_VECTOR
        lda #>nmi_handler
        sta NMI_VECTOR+1
        rts

;----------------------------------------------------------------------------
; init_mouse - timing values for this system
;----------------------------------------------------------------------------
init_mouse
        ldx system_type
        lda tab_mouse_idle_lo,x
        sta mouse_idle_max
        lda tab_mouse_idle_hi,x
        sta mouse_idle_max+1
        lda tab_mouse_accel,x
        sta mouse_accel
        rts

!if DEBUG {
;----------------------------------------------------------------------------
; mailbox_init - clear the mailbox and fill in the program's fields. (The
; signature comes last, from mailbox_ready, once the editor is set up.)
;----------------------------------------------------------------------------
!zone mailbox_init
mailbox_init
        lda #0
        ldx #MB_SIZE-1
-       sta MB_BASE,x
        dex
        bpl -
        sta MB_DMA+7            ; (no REU copy asked for)
        sta MB_BUSY
        sta MB_IDLE
        lda system_type
        sta MB_SYSTEM
        lda load_device
        sta MB_LOADDEV
        rts
}

;----------------------------------------------------------------------------
; From fileio.asm
;----------------------------------------------------------------------------
; load_defaults - start-up: the settings from MAGIC T DEFAULTS on the disk
; the program came from. Anything wrong (no disk, no drive, no file): no
; message at all, the built-in settings stay. Reading the drive's status
; clears its error (and its blinking light).
!zone load_defaults
load_defaults
        lda load_device
        cmp #8
        bcc .done
        cmp #31
        bcs .done
        sta cur_dev
        jsr defaults_file
        lda #<suffix_read
        ldx #>suffix_read
        jsr name_plus
        lda #0
        sta .ok
        jsr io_begin
        ldy #0
        jsr open_cmd
        jsr open_file
        bcs .close
        jsr read_status         ; e.g. 62, FILE NOT FOUND
        bcs .close
        ldx #FILE_LFN
        jsr CHKIN
        bcs .close
        ldx #0
-       jsr CHRIN
        sta defaults_buf,x
        inx
        jsr READST
        bne +
        cpx #DEFAULTS_LEN
        bcc -
+       inc .ok
.close  jsr close_all
        jsr io_end
        lda .ok
        beq .done
        jmp defaults_apply
.done   rts
.ok     !byte 0

;----------------------------------------------------------------------------
; The exact-timed border code (irq.asm: the second IRQs of the two strips),
; one copy per video system, each with its own wait counts. All four are
; assembled to run at border_code (in the tables, after the lower part);
; copy_border puts this system's copy there, and the other three go with
; the rest of the start-up code. (They used to stay in the lower part all
; four, ~870 bytes; Jim chose this to make room for CTRL-Z, phase 12.) The
; code runs the same wherever it is: its loops are kept within a page at
; border_code (same_page), and its other branches go to the next
; instruction.
;----------------------------------------------------------------------------
border_pal
!pseudopc border_code {
border_top_pal     +border_top TOP_PAL_CMP, TOP_PAL_PRE, TOP_PAL_LOOP, TOP_PAL_SPLIT
border_bot_pal     +border_bot BOT_PAL_CMP, BOT_PAL_SPLIT, BOT_PAL_PRE, BOT_PAL_LOOP
}
border_ntsc
!pseudopc border_code {
border_top_ntsc    +border_top TOP_NTSC_CMP, TOP_NTSC_PRE, TOP_NTSC_LOOP, TOP_NTSC_SPLIT
border_bot_ntsc    +border_bot BOT_NTSC_CMP, BOT_NTSC_SPLIT, BOT_NTSC_PRE, BOT_NTSC_LOOP
}
border_oldntsc
!pseudopc border_code {
border_top_oldntsc +border_top TOP_OLDNTSC_CMP, TOP_OLDNTSC_PRE, TOP_OLDNTSC_LOOP, TOP_OLDNTSC_SPLIT
border_bot_oldntsc +border_bot BOT_OLDNTSC_CMP, BOT_OLDNTSC_SPLIT, BOT_OLDNTSC_PRE, BOT_OLDNTSC_LOOP
}
border_drean
!pseudopc border_code {
border_top_drean   +border_top TOP_DREAN_CMP, TOP_DREAN_PRE, TOP_DREAN_LOOP, TOP_DREAN_SPLIT
border_bot_drean   +border_bot BOT_DREAN_CMP, BOT_DREAN_SPLIT, BOT_DREAN_PRE, BOT_DREAN_LOOP
}
border_end

; the room border_code needs: the longest copy
!set BORDER_SIZE = border_ntsc - border_pal
!if border_oldntsc - border_ntsc > BORDER_SIZE {
        !set BORDER_SIZE = border_oldntsc - border_ntsc
}
!if border_drean - border_oldntsc > BORDER_SIZE {
        !set BORDER_SIZE = border_drean - border_oldntsc
}
!if border_end - border_drean > BORDER_SIZE {
        !set BORDER_SIZE = border_end - border_drean
}

; copy_border - this system's copy to border_code (BORDER_SIZE bytes: a
; shorter copy brings the start of the next one along, which is never run)
!zone copy_border
copy_border
        ldx system_type
        lda .from_lo,x
        sta zp_ptr
        lda .from_hi,x
        sta zp_ptr+1
        lda #<border_code
        sta zp_ptr2
        lda #>border_code
        sta zp_ptr2+1
        lda #<BORDER_SIZE
        sta .n
        lda #>BORDER_SIZE
        sta .n+1
        ldy #0
-       lda (zp_ptr),y
        sta (zp_ptr2),y
        inc zp_ptr
        bne +
        inc zp_ptr+1
+       inc zp_ptr2
        bne +
        inc zp_ptr2+1
+       lda .n
        bne +
        dec .n+1
+       dec .n
        lda .n
        ora .n+1
        bne -
        rts
.from_lo !byte <border_pal, <border_ntsc, <border_oldntsc, <border_drean
.from_hi !byte >border_pal, >border_ntsc, >border_oldntsc, >border_drean
.n      !word 0
