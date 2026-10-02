;============================================================================
; fileio.asm - loading and saving documents with the KERNAL
;
; Only the standard KERNAL calls are used (SETLFS, SETNAM, OPEN, CHKIN,
; CHKOUT, CHRIN, CHROUT, READST, CLOSE, CLRCHN), so any drive the KERNAL
; can talk to works: 1541/1571/1581, SD2IEC, Pi1541, Ultimate drives, and
; JiffyDOS or other fast KERNALs speed it up by themselves.
;
; The drive's command channel (15) is kept open while a file is in use.
; After each step its status line ("00, OK,00,00") is read; a code of 20
; or more is an error, and the line is shown in a box.
;
; Phase 4: PETSCII SEQ files on disk (devices 8 and up). The other
; formats, PRG files and tape come in phases 10 and 11.
;============================================================================

; KERNAL routines
SETLFS          = $ffba
SETNAM          = $ffbd
OPEN            = $ffc0
CLOSE           = $ffc3
CHKIN           = $ffc6
CHKOUT          = $ffc9
CLRCHN          = $ffcc
CHRIN           = $ffcf
CHROUT          = $ffd2
READST          = $ffb7
LOAD            = $ffd5
SETMSG          = $ff90
EAL             = $ae           ; KERNAL: where LOAD has got to (lo/hi)
SAVE            = $ffd8
STOP            = $ffe1
BLNSW           = $cc           ; KERNAL: 0 = blink its cursor
NDX             = $c6           ; KERNAL: keys waiting in its buffer
SFDX            = $cb           ; KERNAL: the key held now (64 = none)

FILE_LFN        = 2             ; logical file number (and secondary
                                ; address) for the document file
CMD_LFN         = 15            ; the drive's command/error channel
DIR_LFN         = 3             ; a directory read while a file is open

; Settings (the Load, Save and Print menus change them)
FORMAT_MAGIC    = 0             ; file formats (the Format settings)
FORMAT_PETSCII  = 1
FORMAT_ASCII    = 2
load_dev        !byte 8         ; device (1 = tape)
load_format     !byte FORMAT_PETSCII
save_dev        !byte 8
save_format     !byte FORMAT_MAGIC ; (a loaded document: the format it
                                ; was loaded as, so it saves back the same)
default_save_format !byte 0     ; the Save format for a new document: as
                                ; set at start-up (built in, or Save
                                ; defaults); CLEAR ALL goes back to it
save_type       !byte 0         ; 0 = SEQ, 1 = PRG
print_ascii     !byte 0         ; 1 = convert to ASCII
print_dev       !byte 4

file_name       !fill 16, 0     ; the document's file name (PETSCII) ...
file_name_len   !byte 0         ; ... 0 = none yet

status_raw      !fill 40, 0     ; the drive's status line, as it came
status_buf      !fill 41, 0     ; ... as screen codes, 0 at the end
name_buf        !fill 24, 0     ; a file name plus ",S,R" and the like
name_len        !byte 0

;============================================================================
; Plain display during disk access
;
; The KERNAL's serial bus routines turn interrupts off while they wait for
; the drive, sometimes for a millisecond or more. The strip IRQs must run
; on an exact raster line, and a late one could even upset the stack. So
; while a file is open, our IRQs step aside: the KERNAL's own timer IRQ
; runs instead (with its cursor blink off), the borders close, and the
; sprites go. The text and the box on it stay. io_end puts it all back.
;
; io_begin also switches the KERNAL ROM in, and io_end switches it out.
; While it is in, the editor's code and variables at $e000 are hidden
; behind it, so between io_begin and io_end only lower-part code that does
; not use the editor may run: this file, petscii_to_screen, the messages
; in data.asm, zero page and the text buffer. (The boxes use the editor's
; cursor, so they open before io_begin and close after io_end.) Call
; io_begin and io_end only from the lower part.
;============================================================================

; io_begin - KERNAL ROM in, plain display, KERNAL IRQ
!zone io_begin
io_begin
        sei
        lda #ROMS_KERNAL        ; the KERNAL ROM in (its IRQ handler and
        sta CPU_PORT            ; the disk routines)
        lda #0                  ; no raster IRQs
        sta VIC_IRQ_MASK
        lda #$ff
        sta VIC_IRQ_FLAGS
        lda #<io_irq            ; (the KERNAL's, with a spinner first)
        sta IRQ_VECTOR
        lda #>io_irq
        sta IRQ_VECTOR+1
        lda #1                  ; the KERNAL must not blink its cursor on
        sta BLNSW               ; our screen
        lda #$81                ; the KERNAL's 60 Hz timer IRQ back on
        sta CIA1_ICR
        lda #0                  ; plain screen: sprites off, borders closed
        sta VIC_SPR_ENABLE
        lda #CTRL1_25ROWS
        sta VIC_CTRL1
        lda #CSEL_40
        sta VIC_CTRL2
        lda #BLUE
        sta VIC_BORDER
        lda text_bg
        sta VIC_BG0
        lda VIC_MEMPTR          ; the character set, for io_end: C= + SHIFT
        sta io_memptr           ; works for the KERNAL meanwhile (e.g. in
        cli                     ; the directory), but must not change the
        rts                     ; document's

; io_end - KERNAL ROM out, our IRQs and the full display again
io_end  sei
        lda #0                  ; (no more spinner)
        sta anim_col
        lda #ROMS_EDIT          ; the KERNAL ROM out: the editor at $e000
        sta CPU_PORT            ; is back
        lda #0                  ; forget keys the KERNAL collected
        sta NDX
        lda io_memptr           ; the character set as it was
        sta VIC_MEMPTR
        jsr init_irq            ; (switches the timer IRQ off again)
        lda #SPR_ON_ICONS       ; (the pointer is back from the next frame,
        sta VIC_SPR_ENABLE      ; if it shows)
        cli
        rts
io_memptr       !byte 0         ; the character set during disk work

; io_irq - the KERNAL's timer IRQ during disk work (60 a second), with a
; spinner first: in the "LOADING"/"SAVING" box a quarter block goes round,
; so you can see the work goes on (Jim, 2026-09-30). anim_col = its column
; on the box's text row, 0 for none. (Fast loaders usually keep interrupts
; off while they work: then it waits.) Lower part: the KERNAL ROM is in.
io_irq  lda anim_col
        beq +
        dec anim_timer
        bne +
        lda #8                  ; (a step every 8/60 second)
        sta anim_timer
        ldx anim_phase
        inx
        txa
        and #3
        sta anim_phase
        tax
        lda anim_chars,x
        ldx anim_col
        sta SCREEN+BOX_TEXT_ROW*40,x
+       jmp KERNAL_IRQ          ; (then the KERNAL's own)

; busy_box - A/X = a text ("loading"): a box with room for the spinner
busy_box
        ldy #2                  ; (a space and the spinner)
        jsr box_open
        ldx box_col
        inx
        stx anim_col
        lda anim_chars
        sta SCREEN+BOX_TEXT_ROW*40,x
        lda #1
        sta anim_timer
        rts

anim_col        !byte 0
anim_timer      !byte 0
anim_phase      !byte 0
anim_chars      !byte $7e, $7c, $6c, $7b ; quarter blocks going round

;============================================================================
; Talking to the drive
;============================================================================

; open_cmd - open the command channel (15). A/X = a command to send with
; it (low/high byte of its address), Y = its length (0 = none).
!zone open_cmd
open_cmd
        sta .lo
        stx .hi
        tya                     ; SETNAM wants A = length, X/Y = address
        ldx .lo
        ldy .hi
        jsr SETNAM
        lda #CMD_LFN
        ldx cur_dev
        ldy #15                 ; secondary address 15: the command channel
        jsr SETLFS
        jmp OPEN
.lo     !byte 0
.hi     !byte 0

cur_dev         !byte 8         ; the device of the current load or save

; open_file - open the document file: name_buf/name_len, FILE_LFN.
; Carry set if the KERNAL reports an error (e.g. device not present).
!zone open_file
open_file
        lda name_len
        ldx #<name_buf
        ldy #>name_buf
        jsr SETNAM
        lda #FILE_LFN
        ldx cur_dev
        ldy #FILE_LFN           ; secondary address 2
        jsr SETLFS
        jmp OPEN

; read_status - read the drive's status line from channel 15 into
; status_raw, and as screen codes into status_buf (for a box).
; Carry set if it is an error (code 20 or more) or the drive does not
; answer ("device not present").
!zone read_status
read_status
        lda cur_dev             ; tape: no drive to ask. The KERNAL's
        cmp #1                  ; status tells: a short or long block, a
        bne .disk               ; read or checksum error
        jsr READST
        and #%00111100
        beq +
        lda #<msg_tape_error
        ldx #>msg_tape_error
        jsr copy_message
        sec
        rts
+       clc
        rts
.disk   ldx #CMD_LFN
        jsr CHKIN
        bcs .no_drive
        lda #0
        sta .n
-       jsr CHRIN
        cmp #$0d                ; the line ends with a RETURN
        beq .got
        ldx .n
        sta status_raw,x
        inx
        stx .n
        cpx #39
        bcs .got                ; (never longer than this)
        jsr READST
        and #%11000010          ; end, device gone, or time out
        beq -
.got    jsr CLRCHN
        lda .n
        beq .no_drive           ; nothing came back
        ldx #0                  ; make the screen code copy
-       lda status_raw,x
        jsr petscii_to_screen
        bcc +
        lda #$20                ; (control codes as spaces)
+       sta status_buf,x
        inx
        cpx .n
        bcc -
        lda #0
        sta status_buf,x
        lda status_raw          ; codes 00-19 are fine, 20-99 errors:
        cmp #$32                ; carry set if the first digit is "2"
        rts                     ; or more
.no_drive
        jsr CLRCHN
        lda #<msg_no_device
        ldx #>msg_no_device
        jsr copy_message
        sec
        rts
.n      !byte 0

; copy_message - copy a message (A/X, screen codes, 0 at the end) into
; status_buf
!zone copy_message
copy_message
        sta zp_ptr2
        stx zp_ptr2+1
        ldy #0
-       lda (zp_ptr2),y
        sta status_buf,y
        beq +
        iny
        bne -
+       rts

; close_all - close the file and the command channel
close_all
        jsr CLRCHN
        lda #FILE_LFN
        jsr CLOSE
        lda #CMD_LFN
        jmp CLOSE

; name_plus - name_buf = input_buf + the 4 characters at A/X (e.g. ",S,R")
!zone name_plus
name_plus
        sta zp_ptr2
        stx zp_ptr2+1
        ldx #0
-       cpx input_len
        bcs +
        lda input_buf,x
        sta name_buf,x
        inx
        bne -
+       ldy #0
-       lda (zp_ptr2),y
        sta name_buf,x
        inx
        iny
        cpy #4
        bcc -
        stx name_len
        rts

; keep_name - input_buf becomes the document's file name - unless it holds
; * ? or , (loading takes a pattern like "SAM*", but saving must not use
; one): then the document has no name, and CTRL-S asks for one.
!zone keep_name
keep_name
        jsr name_ok
        bcc +
        lda #0
        sta file_name_len
        rts
+       ldx input_len
        stx file_name_len
        dex
-       lda input_buf,x
        sta file_name,x
        dex
        bpl -
        rts

; name_ok - carry set if input_buf holds * ? or , - not allowed in a name
; to save under: the scratch that comes first would take other files
; with it ("S0:SA*" scratches every file starting with SA, "S0:A,B" both
; A and B).
!zone name_ok
name_ok ldx input_len
-       dex
        bmi .ok                 ; (all checked)
        lda input_buf,x
        cmp #$2a                ; *
        beq .bad
        cmp #$3f                ; ?
        beq .bad
        cmp #$2c                ; ,
        bne -
.bad    sec
        rts
.ok     clc
        rts

; name_to_input - put the document's file name in input_buf (to show it
; in the name box)
!zone name_to_input
name_to_input
        ldx file_name_len
        stx input_len
        dex
        bmi +
-       lda file_name,x
        sta input_buf,x
        dex
        bpl -
+       lda #16
        sta input_max
        rts

;============================================================================
; Loading
;============================================================================

; load_file - ask for a name and load a file in place of the document. It
; is read as it is into the buffer, then made into text (convert_loaded):
; the Load format says how, but a file with the Magic Typewriter header is
; always read as one. SEQ and PRG files both load.
!zone load_file
load_file
        lda modified            ; changes not saved: ask first
        beq +
        lda #<msg_load_unsaved
        ldx #>msg_load_unsaved
        jsr prompt_yes_no
        bcs +
        rts
+       jsr name_to_input
        lda load_dev            ; (tape: no name is fine too - the next
        cmp #1                  ; file on the tape)
        bne +
        sta input_empty_ok
+       lda #<msg_load
        ldx #>msg_load
        jsr prompt_name
        bcc +
        rts                     ; cancelled
+       lda load_dev
        sta cur_dev
        lda #0
        sta load_fast
        lda cur_dev
        cmp #1
        bne +
        jmp .tape
+
        lda #<suffix_read       ; a SEQ file first ...
        ldx #>suffix_read
        jsr name_plus
        lda #<msg_loading
        ldx #>msg_loading
        jsr busy_box
        jsr io_begin

        ldy #0                  ; the command channel, no command
        jsr open_cmd
        jsr open_file
        bcc +
        jmp .no_device
+       jsr read_status         ; e.g. 62, FILE NOT FOUND
        bcs +
        jmp .opened             ; (a SEQ file)
+       lda status_buf          ; ... but "64, FILE TYPE MISMATCH" (a 1541:
        cmp #$36                ; it is a PRG file) or "62, FILE NOT FOUND"
        bne .to_fail            ; (VICE's file system drive looks for a SEQ
        lda status_buf+1        ; file only): open it as a PRG. (If there
        cmp #$34                ; is none, that says 62 again.)
        beq +
        cmp #$32
        bne .to_fail
+       lda #FILE_LFN
        jsr CLOSE
        jsr prg_fits            ; its size, from the directory - now, while
        lda #0                  ; no file is open (a 1581 ended an open
        rol                     ; file after 2 blocks when the directory
        sta .too_big            ; was read meanwhile). 1: too big.
        lda #<suffix_prg_read
        ldx #>suffix_prg_read
        jsr name_plus
        jsr open_file
        bcc +
        jmp .no_device
+       jsr read_status
        bcc +
.to_fail
        jmp .fail
+       ldx #FILE_LFN           ; its load address (read off here: the
        jsr CHKIN               ; bytes after it are the document)
        bcc +
        jmp .no_device
+       jsr CHRIN
        sta .addr
        jsr CHRIN
        sta .addr+1
        jsr CLRCHN
        lda .addr               ; $4000: one saved here. If it fits, it
        cmp #<BUF_START         ; is loaded again with KERNAL LOAD, which
        bne .by_bytes           ; fast loaders speed up. Other PRG files,
        lda .addr+1             ; and ones too big: read on from here,
        cmp #>BUF_START         ; byte by byte.
        bne .by_bytes
        lda .too_big
        bne .by_bytes
        lda #FILE_LFN
        jsr CLOSE
        jmp .kernal_load
.by_bytes
        jmp .opened

        ; A PRG file saved here that fits: loaded with the KERNAL's LOAD,
        ; with secondary address 1 - to its own load address, $4000 - as
        ; every fast loader can (LOAD"NAME",8,1). Our zero page is kept
        ; aside meanwhile, in case a fast loader borrows some of it.
.kernal_load
        ldx #ZP_END-ZP_START-1
-       lda ZP_START,x
        sta zp_keep,x
        dex
        bpl -
        lda #1
        sta load_fast
        jsr .eal_start
        lda #0                  ; (no KERNAL messages)
        jsr SETMSG
        lda input_len
        ldx #<input_buf
        ldy #>input_buf
        jsr SETNAM
        lda #FILE_LFN
        ldx cur_dev
        ldy #1                  ; (secondary address 1: its own address)
        jsr SETLFS
        lda #0                  ; load, not verify
        jsr LOAD
        ldx #ZP_END-ZP_START-1
-       lda zp_keep,x
        sta ZP_START,x
        dex
        bpl -
        lda EAL                 ; where it stopped (the end, if all went
        cmp #<BUF_START         ; well): if it got nowhere, the document
        bne +                   ; is untouched
        lda EAL+1
        cmp #>BUF_START
        bne +
        jsr read_status
        jmp .fail
+       jsr .reu_reset          ; (a long document's REU part goes)
        lda EAL                 ; the text: BUF_START up to there
        sta gap_start
        lda EAL+1
        sta gap_start+1
        lda text_end
        sta gap_end
        lda text_end+1
        sta gap_end+1
        jmp .end                ; (the drive's status, and show it)

        ; The file is there: from here on it replaces the document. Empty
        ; the text: the gap covers the whole buffer below the clipboard.
        ; (Done here, not with the editor's empty_buffer, which is out of
        ; reach while the KERNAL ROM is in; .show does the rest.)
.opened lda #<BUF_START
        sta gap_start
        lda #>BUF_START
        sta gap_start+1
        lda text_end
        sta gap_end
        lda text_end+1
        sta gap_end+1
        lda #0
        sta conv_started
        jsr .reu_reset          ; (and nothing in the REU)
        ldx #FILE_LFN
        jsr CHKIN
        bcc .byte
        jmp .no_device
.byte   jsr STOP                ; RUN/STOP breaks off
        bne +
        jmp .break
+       jsr CHRIN               ; the file as it comes (made into text
        tax                     ; afterwards, by convert_loaded)
        lda gap_start           ; room left?
        cmp gap_end
        bne +
        lda gap_start+1
        cmp gap_end+1
        bne +
        lda reu_docs            ; no: a long document goes on in the REU
        beq .full
        jsr load_spill
        bcs .full
+       txa
        ldy #0
        sta (gap_start),y
        inc gap_start
        bne +
        inc gap_start+1
+       jsr READST
        beq .byte               ; 0: more to come
        and #%01000000
        beq .read_error         ; not the end: something went wrong
.end    jsr CLRCHN              ; the end of the file
        jsr read_status
        php
        jsr close_all
        jsr io_end
        jsr box_close
        jsr .show
        plp
        bcc +
        jmp .error_box          ; (the drive had something to say)
+       jsr keep_name
        rts

.full   jsr close_all           ; more than fits: keep what fitted
        jsr io_end
        jsr box_close
        jsr .show
        lda #<msg_too_long
        ldx #>msg_too_long
        jmp message_box
.break  jsr close_all
        jsr io_end
        jsr box_close
        jsr .show
        lda #<msg_break
        ldx #>msg_break
        jmp message_box
.read_error
        jsr CLRCHN
        jsr read_status
        jsr close_all
        jsr io_end
        jsr box_close
        jsr .show
        jmp .error_box
.no_device
        lda #<msg_no_device
        ldx #>msg_no_device
        jsr copy_message
.fail   jsr close_all           ; the document is untouched
        jsr io_end
        jsr box_close
.error_box
        lda #<status_buf
        ldx #>status_buf
        jmp message_box

; .tape - from tape (device 1), with the KERNAL's own routines; our box
; asks for PLAY (the KERNAL says so only at the READY prompt), and the
; KERNAL waits for it and blanks the screen meanwhile. A magic document
; is a program file (LOAD, to BUF_START); PETSCII and ASCII documents are
; data files, read as from disk. A blank name: the next such file.
.tape   lda #<msg_press_play
        ldx #>msg_press_play
        jsr busy_box
        jsr io_begin
        lda input_len
        ldx #<input_buf
        ldy #>input_buf
        jsr SETNAM
        lda #FILE_LFN
        ldx #1
        ldy #0                  ; (0: read; LOAD: to the address we give)
        jsr SETLFS
        lda load_format
        beq +                   ; (FORMAT_MAGIC is 0)
        jsr OPEN                ; a data file
        bcs .tape_break
        jmp .opened
+       lda #0                  ; a program file
        jsr SETMSG
        jsr .eal_start
        lda #REU_STASH          ; (long documents: reudoc.asm kept aside, in
        jsr reudoc_copy         ; case the file runs on over it)
        lda #0
        ldx #<BUF_START
        ldy #>BUF_START
        jsr LOAD
        lda EAL                 ; got nowhere (RUN/STOP): the document is
        cmp #<BUF_START         ; untouched
        bne +
        lda EAL+1
        cmp #>BUF_START
        beq .tape_break
+       lda #0
        sta .cut
        lda reu_docs            ; long documents: past $c000 (a file saved
        beq .tape_fits          ; without an REU)? reudoc.asm back, and the
        lda #<REUDOC            ; text cut there
        cmp EAL
        lda #>REUDOC
        sbc EAL+1
        bcs .tape_fits
        lda #REU_FETCH
        jsr reudoc_copy
        lda #<REUDOC
        sta EAL
        lda #>REUDOC
        sta EAL+1
        inc .cut
.tape_fits
        jsr .reu_reset
        lda EAL                 ; the text: BUF_START up to there
        sta gap_start
        lda EAL+1
        sta gap_start+1
        lda text_end            ; (past the clipboard? then it is gone)
        cmp EAL
        lda text_end+1
        sbc EAL+1
        bcs +
        lda buf_top
        sta text_end
        lda buf_top+1
        sta text_end+1
+       lda text_end
        sta gap_end
        lda text_end+1
        sta gap_end+1
        lda .cut
        beq +
        jmp .full               ; ("TOO LONG: ONLY PART LOADED")
+       jmp .end
.tape_break
        lda #<msg_break
        ldx #>msg_break
        jsr copy_message
        jmp .fail

; .reu_reset - a long document: nothing in the REU any more (a new
; document is coming)
.reu_reset
        lda reu_docs
        beq +
        jmp reudoc_reset
+       rts

; .eal_start - EAL (where LOAD gets to) = BUF_START before LOAD: on tape
; the KERNAL sets it only once it has found the file, so after RUN/STOP
; at PRESS PLAY it would still hold an old address - "got nowhere" must
; show as BUF_START.
.eal_start
        lda #<BUF_START
        sta EAL
        lda #>BUF_START
        sta EAL+1
        rts

; .show - make the file into text and show it from the top, cursor at the
; start (after io_end: this uses the editor)
.show   lda #0                  ; nothing marked
        sta sel_on
        lda #1                  ; (and nothing to undo)
        jsr undo_reset
        jsr convert_loaded
        jsr gap_to_start
        lda reu_docs            ; (a long document: from its start)
        beq +
        jsr reu_to_start
+       jsr empty_view
        jsr count_colors
        lda load_charset
        beq +
        ldx #MEMPTR_UPPER       ; $8e: upper case/graphics
        cmp #$8e
        beq ++
        ldx #MEMPTR_LOWER       ; $0e: upper/lower case
++      stx VIC_MEMPTR
+       lda #0
        sta modified
        jsr skip_codes
        jsr redraw_all
        jmp locate_cursor

load_charset    !byte 0         ; $0e, $8e, or 0 = none found
load_fast       !byte 0         ; 1: it came with KERNAL LOAD (the tests
                                ; look)
.addr           !word 0         ; a PRG file's load address
.too_big        !byte 0         ; 1: it doesn't fit (prg_fits)
.cut            !byte 0         ; 1: a tape program cut short at $c000
zp_keep         !fill ZP_END-ZP_START, 0 ; our zero page during LOAD

;----------------------------------------------------------------------------
; convert_loaded - the file just read lies at BUF_START..gap_start as it
; came. Take off what is not text - a PRG's load address, the Magic
; Typewriter header (its settings are used), a case code at the very
; start (it picks the character set) - and make the rest PETSCII text as
; the Load format says, in place. The Save format becomes the format it
; was loaded as, so that it saves back the same way.
;   ptr reads the file, ptr2 writes the text (never ahead of ptr: nothing
;   gets longer)
;----------------------------------------------------------------------------
!zone convert_loaded
convert_loaded
        lda conv_started        ; (a long document's load may have done
        bne +                   ; some of it already)
        jsr convert_start
        jmp ++
+       jsr convert_more
++      lda ptr2                ; the text ends here
        sta gap_start
        lda ptr2+1
        sta gap_start+1
        lda .fmt
        sta save_format
        lda #0
        sta conv_started
        rts

; convert_more - go on from where the last part stopped, up to gap_start
; (a long document's load: the file goes to the REU a piece at a time)
convert_more
        lda conv_rd
        sta ptr
        lda conv_rd+1
        sta ptr+1
        lda conv_wr
        sta ptr2
        lda conv_wr+1
        sta ptr2+1
        jmp .copy

; convert_start - from the start of the file (its header, its case code),
; then as far as it goes
convert_start
        lda #<BUF_START
        sta ptr
        sta ptr2
        lda #>BUF_START
        sta ptr+1
        sta ptr2+1
        lda #0
        sta load_charset
        sta .skip_lf
        lda #1
        sta conv_started
        lda load_format         ; how to read it (unless it has the header)
        sta .fmt

        ; A PRG file's load address is off already (load_file read it, or
        ; KERNAL LOAD took it) - unless the drive gave the PRG as a SEQ
        ; file: an SD2IEC opens a file whatever type is asked for, so no
        ; "64, FILE TYPE MISMATCH" told us (Jim's manual started with
        ; "@mtw1..."). So $00 $40 (our load address, $4000) followed by
        ; our header ($00) or a case code is a PRG of ours: skip those 2.
        lda #3
        jsr .has
        bcc .header
        ldy #0
        lda (ptr),y
        bne .header
        iny
        lda (ptr),y
        cmp #>BUF_START
        bne .header
        iny
        lda (ptr),y
        beq +                   ; ($00: the header)
        cmp #$0e
        beq +
        cmp #$8e
        bne .header
+       inc ptr                 ; (ptr is BUF_START here: no page to cross)
        inc ptr

.header ; The Magic Typewriter header: $00 "MTW", its version, the number
        ; of settings, the settings, a RETURN (as MAGIC T DEFAULTS).
        lda #6
        jsr .has
        bcc .text
        ldy #3
-       lda (ptr),y
        cmp defaults_head,y
        bne .text
        dey
        bpl -
        ldy #DEFAULTS_LEN-1     ; the settings a document brings with it
-       lda (ptr),y             ; (doc_settings; another version's are
        sta defaults_buf,y      ; left alone)
        dey
        bpl -
        jsr doc_apply
        lda #FORMAT_MAGIC
        sta .fmt
-       jsr .get                ; the text starts after its RETURN
        bcs .done
        cmp #$0d
        bne -

.text   lda .fmt                ; PETSCII and magic files: a case code
        cmp #FORMAT_ASCII       ; first is the character set (save_file
        bcs .copy               ; writes one), not text
        jsr .get
        bcs .done
        cmp #$0e
        beq +
        cmp #$8e
        bne .keep
+       sta load_charset

.copy   jsr .get                ; then the rest, byte by byte
        bcs .done
.keep   ldx .fmt
        cpx #FORMAT_ASCII
        beq .ascii
        ldx load_charset        ; PETSCII and magic: as it is. If nothing
        bne .put                ; picked the character set yet, the first
        cmp #$0e                ; $0e or $8e in the text does (and stays)
        beq +
        cmp #$8e
        bne .put
+       sta load_charset
.put    ldy #0
        sta (ptr2),y
        inc ptr2
        bne .copy
        inc ptr2+1
        bne .copy               ; (always)

.done   lda ptr                 ; where it got to, for convert_more
        sta conv_rd
        lda ptr+1
        sta conv_rd+1
        lda ptr2
        sta conv_wr
        lda ptr2+1
        sta conv_wr+1
        rts

.ascii  ; ASCII: capitals and small letters change places; a RETURN, a
        ; line feed, or both, is a line end; a tab is a space; other
        ; control codes go.
        ldx .skip_lf            ; (a line feed just after a RETURN that
        beq +                   ; ended the last piece: it goes)
        ldx #0
        stx .skip_lf
        cmp #$0a
        beq .copy
+       cmp #$0d
        bne +
        jsr .lf_after
        lda #$0d
        bne .put
+       cmp #$0a
        bne +
        lda #$0d
        bne .put
+       cmp #$09
        bne +
        lda #$20
        bne .put
+       cmp #$20
        bcc .copy               ; (other control codes)
        cmp #$7f
        beq .copy
        cmp #$41
        bcc .put
        cmp #$5b
        bcs +
        ora #$80                ; A-Z: PETSCII capitals ($c1-$da)
        bne .put
+       cmp #$61
        bcc .put
        cmp #$7b
        bcs .put
        and #$df                ; a-z: PETSCII small letters ($41-$5a)
        bne .put

; .get - A = the next byte of the file, ptr past it. Carry set at the end.
.get    lda ptr
        cmp gap_start
        bne +
        lda ptr+1
        cmp gap_start+1
        bne +
        sec
        rts
+       ldy #0
        lda (ptr),y
        inc ptr
        bne +
        inc ptr+1
+       clc
        rts

; .has - carry set if at least A bytes of the file are left from ptr
.has    clc
        adc ptr
        sta .t
        lda ptr+1
        adc #0
        sta .t+1
        lda gap_start
        cmp .t
        lda gap_start+1
        sbc .t+1
        rts

; .lf_after - after a RETURN: a line feed straight after it goes too
; (if the file goes on in the next piece: look there)
.lf_after
        lda #1
        jsr .has
        bcs ++
        lda #1
        sta .skip_lf
        rts
++      ldy #0
        lda (ptr),y
        cmp #$0a
        bne +
        jsr .get
+       rts

.fmt    !byte 0
.t      !word 0
.skip_lf !byte 0
conv_started    !byte 0         ; 1: convert_start has run for this load
conv_rd         !word 0         ; where convert_more goes on reading ...
conv_wr         !word 0         ; ... and writing

;----------------------------------------------------------------------------
; prg_fits - does the file named in input_buf (a PRG) fit in the room for
; the text (BUF_START up to the clipboard)? KERNAL LOAD doesn't stop at
; the end of the buffer, and past $cfff are the I/O chips. Its size comes
; from the directory ("$:" + the name, read as LOAD"$" would): its blocks,
; at most 254 bytes each. Carry clear if it fits. (Between io_begin and
; io_end, with channel 15 open but no file: a 1581 cut short a file that
; was open while the directory was read.)
;----------------------------------------------------------------------------
!zone prg_fits
prg_fits
        lda #$24                ; "$:" + the name
        sta name_buf
        lda #$3a
        sta name_buf+1
        ldx #0
-       lda input_buf,x
        sta name_buf+2,x
        inx
        cpx input_len
        bcc -
        inx
        inx
        txa
        ldx #<name_buf
        ldy #>name_buf
        jsr SETNAM
        lda #DIR_LFN
        ldx cur_dev
        ldy #0                  ; (secondary address 0: the listing)
        jsr SETLFS
        jsr OPEN
        bcs .no
        ldx #DIR_LFN
        jsr CHKIN
        bcs .no
        ldx #6                  ; the load address, and the first line's
-       jsr CHRIN               ; link and number (the disk's name) ...
        dex
        bne -
-       jsr CHRIN               ; ... and its text, up to a 0
        tax
        jsr READST
        bne .no
        txa
        bne -
        jsr CHRIN               ; the next line is the file's: its link,
        jsr CHRIN               ; then its blocks
        jsr CHRIN
        sta .blocks
        jsr CHRIN
        sta .blocks+1
        jsr READST
        bne .no
        jsr .close
        lda .blocks+1           ; 256 blocks or more: no
        bne .too_big
        lda .blocks             ; blocks * 254 = blocks * 256 - blocks * 2
        sta .size+1
        lda #0
        sta .size
        sta .t+1
        lda .blocks
        asl
        sta .t
        rol .t+1
        sec
        lda .size
        sbc .t
        sta .size
        lda .size+1
        sbc .t+1
        sta .size+1
        sec                     ; the room: BUF_START up to text_end
        lda text_end
        sbc #<BUF_START
        tax
        lda text_end+1
        sbc #>BUF_START
        cpx .size               ; room - size: no borrow if it fits
        sbc .size+1
        bcc .too_big
        clc
        rts
.no     jsr .close
.too_big
        sec
        rts
.close  jsr CLRCHN
        lda #DIR_LFN
        jmp CLOSE

.blocks !word 0
.size   !word 0
.t      !word 0

;============================================================================
; Saving
;============================================================================

; save_as - the Save menu's Save: ask for a name (the last one used is
; filled in) and save under it
save_as jsr leave_cursor        ; (as CTRL-S: no codes without effect)
        jsr name_to_input
        lda #<msg_save
        ldx #>msg_save
        jsr prompt_name
        bcc save_file
        rts                     ; cancelled

; save_key - CTRL-S: save the document under its file name, asking for a
; name if it has none yet.
!zone save_key
save_key
        jsr leave_cursor        ; tidy the codes at the cursor first, so
                                ; none without effect go into the file
        lda file_name_len
        bne +
        jsr name_to_input       ; (empty)
        lda #<msg_save
        ldx #>msg_save
        jsr prompt_name
        bcc save_file
        rts                     ; cancelled
+       jsr name_to_input
        ; (falls into save_file)

; save_file - save the document under the name in input_buf, in the Save
; format and file type. An old file of that name is scratched first
; ("S0:name"), then the new one is written. (Not "@0:": some drives have a
; bug in save-with-replace.) What goes into the file:
;   a PRG file:        (File type PRG, or the magic format, always)
;                      the load address first: $4000, where the text goes
;                      (load_file uses KERNAL LOAD for it, so fast loaders
;                      speed it up; a stray LOAD"NAME",8,1 lands there too)
;   magic:             the header (the settings, as in MAGIC T DEFAULTS)
;   magic and PETSCII: the character set as a case code ($0e / $8e)
;   then the text:     as it is (magic, PETSCII), or made ASCII: small
;                      letters and capitals swapped, a line end as RETURN
;                      and line feed, colors, reverse and other codes left
;                      out (it asks first if there are colors to lose)
save_file
        jsr name_ok             ; no * ? or , in the name
        bcc +
        lda #<msg_bad_name
        ldx #>msg_bad_name
        jmp message_box
+       lda save_format         ; ASCII can't keep colors or reverse: ask
        cmp #FORMAT_ASCII       ; first if there are any
        bne +
        jsr has_codes
        bcc +
        lda #<msg_colors_lost
        ldx #>msg_colors_lost
        jsr prompt_yes_no
        bcs +
        rts
+       jsr defaults_make       ; (the magic header: made now, while the
                                ; editor's settings can be read)
        lda save_dev
        sta cur_dev
        cmp #1
        bne +
        jmp .tape
+       lda #<msg_saving
        ldx #>msg_saving
        jsr busy_box
        jsr io_begin

        jsr scratch_input       ; the old file goes first ("S0:" + name)
        bcc +
        jmp .fail
+       lda save_type           ; a PRG file? File type PRG - and the
        ldx save_format         ; magic format always (Jim, 2026-09-30)
        bne +                   ; (FORMAT_MAGIC is 0)
        lda #1
+       sta .prg
        lda #<suffix_write      ; now the file: name + ",S,W" or ",P,W"
        ldx #>suffix_write
        ldy .prg
        beq +
        lda #<suffix_prg_write
        ldx #>suffix_prg_write
+       jsr name_plus
        jsr open_file
        bcc +
        jmp .no_device
+       jsr read_status         ; e.g. 26, WRITE PROTECT ON
        bcc +
        jmp .fail
+       ldx #FILE_LFN
        jsr CHKOUT
        bcc .body
        jmp .no_device
.to_bus jmp .bus_error          ; (for branches that cannot reach)

.body   lda .prg                ; a PRG: the load address, where the text
        beq +                   ; goes (BUF_START)
        lda #<BUF_START
        jsr .out
        bcs .to_bus
        lda #>BUF_START
        jsr .out
        bcs .to_bus
+       lda save_format         ; magic: the header
        cmp #FORMAT_MAGIC
        bne +
        ldx #0
-       lda defaults_buf,x
        jsr .out
        bcs .bus_error
        inx
        cpx #DEFAULTS_LEN
        bcc -
+       lda save_format         ; magic and PETSCII: the character set, as
        cmp #FORMAT_ASCII       ; the standard PETSCII case code ($0e for
        bcs .text               ; upper/lower case, $8e for upper case/
        jsr .case_code          ; graphics). load_file takes it back as the
        jsr .out                ; setting, and other programs that print
                                ; the file switch to the right set with it.
        bcs .bus_error

.text   lda #OUT_ASIS           ; then the text, as the Save format says
        ldx save_format
        cpx #FORMAT_ASCII
        bne +
        lda #OUT_ASCII
+       sta out_mode
        jsr write_doc
        bcs .stopped

        jsr CLRCHN
        lda #FILE_LFN
        jsr CLOSE
        jsr read_status         ; e.g. 72, DISK FULL
        bcs .fail
        jsr close_all
        jsr io_end
        jsr box_close
        lda #0
        sta modified
        jmp keep_name

.stopped                        ; A = 0: RUN/STOP; else a bus error
        bne .bus_error
        jsr close_all
        jsr io_end
        jsr box_close
        lda #<msg_break
        ldx #>msg_break
        jmp message_box
.bus_error
        jsr CLRCHN
        jsr read_status
        jmp .fail
.no_device
        lda #<msg_no_device
        ldx #>msg_no_device
        jsr copy_message
.fail   jsr close_all
        jsr io_end
        jsr box_close
        lda #<status_buf
        ldx #>status_buf
        jmp message_box

; .tape - to tape (device 1), with the KERNAL's own routines; our box asks
; for RECORD & PLAY (the KERNAL says so only at the READY prompt), and the
; KERNAL waits for it. A magic document goes as a program file: KERNAL
; SAVE, all in one piece (below). PETSCII and ASCII as a data file,
; written as to disk.
.tape   lda save_format
        beq .tape_prg           ; (FORMAT_MAGIC is 0)
        lda #<msg_press_record
        ldx #>msg_press_record
        jsr busy_box
        jsr io_begin
        jsr .tape_name
        ldy #1                  ; (1: write)
        jsr SETLFS
        jsr OPEN
        bcs .tape_break
        ldx #FILE_LFN
        jsr CHKOUT
        bcs .tape_break
        lda #0                  ; (no load address on a data file)
        sta .prg
        jmp .body
.tape_break                     ; (RUN/STOP while it waited)
        jsr close_all
        jsr io_end
        jsr box_close
.tape_stopped
        lda #<msg_break
        ldx #>msg_break
        jmp message_box

.tape_prg
        ; KERNAL SAVE writes one piece of memory: so the gap goes to the
        ; start (the text all after it), and the header and the case code
        ; go just below the text. The cursor goes back afterwards.
        lda reu_docs            ; (a long document: all of it must be in
        beq +                   ; the text buffer)
        lda #<msg_tape_long
        ldx #>msg_tape_long
        jsr reu_all_in
        bcc +
        rts
+       jsr gap_size            ; room for those 21 bytes?
        lda work+1
        bne +
        lda work
        cmp #DEFAULTS_LEN+1
        bcs +
        jmp no_room
+       jsr get_cursor_off
        lda work
        sta .cursor
        lda work+1
        sta .cursor+1
        lda #0
        sta off
        sta off+1
        jsr move_gap_to
        sec                     ; ptr = gap_end - 21
        lda gap_end
        sbc #DEFAULTS_LEN+1
        sta ptr
        lda gap_end+1
        sbc #0
        sta ptr+1
        ldy #DEFAULTS_LEN-1     ; the header ...
-       lda defaults_buf,y
        sta (ptr),y
        dey
        bpl -
        jsr .case_code          ; ... and the case code
        ldy #DEFAULTS_LEN
        sta (ptr),y
        lda #<msg_press_record
        ldx #>msg_press_record
        jsr busy_box
        jsr io_begin
        jsr .tape_name
        ldy #0                  ; (0: a program that loads anywhere)
        jsr SETLFS
        lda #ptr                ; from ptr up to text_end
        ldx text_end
        ldy text_end+1
        jsr SAVE
        php
        jsr io_end
        jsr box_close
        lda .cursor             ; the cursor back where it was
        sta off
        lda .cursor+1
        sta off+1
        jsr move_gap_to
        plp
        bcc +
        jmp .tape_stopped
+       lda #0
        sta modified
        jmp keep_name

; .tape_name - the name (SETNAM) and A/X for SETLFS: the file, tape
.tape_name
        lda input_len
        ldx #<input_buf
        ldy #>input_buf
        jsr SETNAM
        lda #FILE_LFN
        ldx #1
        rts

; .case_code - A = the character set as the PETSCII case code: $0e for
; upper/lower case, $8e for upper case/graphics
.case_code
        lda VIC_MEMPTR
        and #%00000010          ; bit 1 set: upper/lower case
        beq +
        lda #$0e
        rts
+       lda #$8e
        rts

; .out - A to the file. Carry set if the bus reports an error. Keeps X.
.out    jsr CHROUT
        jsr READST
        cmp #1
        rts

; write_doc - send the whole text to the current output (a file or the
; printer, after CHKOUT) as out_mode says: as it is, as ASCII, or for a
; Commodore printer. Carry set if it stopped early: A = 0 for RUN/STOP,
; else a bus error. (Also used by print_doc.)
OUT_ASIS        = 0             ; out_mode: every byte as it is
OUT_ASCII       = 1             ;   ASCII (.ascii)
OUT_PRINTER     = 2             ;   for a Commodore printer (.printer)
write_doc
        lda #<write_range       ; (each piece of it in turn)
        sta range_call
        lda #>write_range
        sta range_call+1
        jmp each_range

; write_range - send the text from ptr up to range_end, as out_mode says
write_range
-       lda ptr
        cmp range_end
        bne +
        lda ptr+1
        cmp range_end+1
        beq .done
+       jsr STOP
        beq .break
        ldy #0
        lda (ptr),y
        ldx out_mode
        bne +
        jsr CHROUT              ; (as it is)
        jmp ++
+       dex
        bne +
        jsr .ascii              ; (as ASCII)
        jmp ++
+       jsr .printer            ; (for the printer)
++      jsr READST
        bne .error
        inc ptr
        bne -
        inc ptr+1
        bne -
.done   clc
        rts
.break  lda #0
        sec
        rts
.error  lda #1
        sec
        rts

; .ascii - A = a byte of the text: send it as ASCII (or nothing)
.ascii  tax
        lda ctype,x
        cmp #CT_EOL
        bne +
        lda #$0d                ; a line end: RETURN and line feed
        jsr CHROUT
        lda #$0a
        jmp CHROUT
+       cmp #CT_CHAR
        bne .none               ; codes: nothing
        txa
        cmp #$a0                ; SHIFT + SPACE: a space
        bne +
        lda #$20
        bne .send
+       cmp #$c1                ; capitals ($c1-$da): A-Z
        bcc +
        cmp #$db
        bcs .none               ; (graphics)
        and #$7f
        bne .send
+       cmp #$80
        bcs .none               ; (graphics)
        cmp #$41
        bcc .send               ; space, digits, punctuation, @
        cmp #$5b
        bcs +
        ora #$20                ; small letters ($41-$5a): a-z
        bne .send
+       cmp #$60                ; [ pound ] up-arrow left-arrow: as
        bcc .send               ; [ \ ] ^ _
        beq .none
        cmp #$7b
        bcs .none               ; (graphics)
        and #$df                ; capitals ($61-$7a) too: A-Z
.send   jmp CHROUT
.none   rts

; .printer - A = a byte of the text, for a Commodore printer: characters
; and reverse on/off as they are, a line end as RETURN, colors and other
; codes left out
.printer
        tax
        lda ctype,x
        cmp #CT_EOL
        bne +
        lda #$0d
        jmp CHROUT
+       cmp #CT_CHAR
        beq +
        cmp #CT_RVSON
        beq +
        cmp #CT_RVSOFF
        bne .none
+       txa
        jmp CHROUT

.prg    !byte 0                 ; 1: a PRG file
.cursor !word 0                 ; (tape: the cursor, to put back)
out_mode        !byte 0         ; how write_doc sends the text: OUT_...

;============================================================================
; Printing (the Print menu's Print)
;
; The whole document goes to the printer (Print device 4-7) as it is
; stored, line by line; the printer does its own wrapping. For a Commodore
; printer (Convert to ASCII: no) as PETSCII: RETURN line ends, reverse on/
; off kept, colors left out, on secondary address 7 (upper/lower case)
; when the upper/lower character set is on, else 0. Converted to ASCII
; (yes): as saving as ASCII does it, RETURN and line feed, secondary
; address 0. A line end at the very end, so the last line prints too.
;============================================================================
!zone print_doc
print_doc
        lda print_dev
        sta cur_dev
        lda #<msg_printing
        ldx #>msg_printing
        jsr busy_box
        ldy #0                  ; ASCII: secondary address 0
        lda #OUT_ASCII
        ldx print_ascii
        bne +
        lda VIC_MEMPTR          ; PETSCII: 7 with the upper/lower set on
        and #%00000010
        beq ++
        ldy #7
++      lda #OUT_PRINTER
+       sta out_mode
        sty .sa
        jsr io_begin
        lda #0                  ; (no name)
        jsr SETNAM
        lda #FILE_LFN
        ldx cur_dev
        ldy .sa
        jsr SETLFS
        jsr OPEN
        bcs .no_device
        ldx #FILE_LFN
        jsr CHKOUT
        bcs .no_device
        jsr write_doc
        bcs .stopped
        lda #$0d                ; the last line ends too
        jsr CHROUT
        lda print_ascii
        beq +
        lda #$0a
        jsr CHROUT
+       jsr .close
        rts
.stopped
        bne .no_device          ; (A = 0: RUN/STOP)
        jsr .close
        lda #<msg_break
        ldx #>msg_break
        jmp message_box
.no_device
        jsr .close
        lda #<msg_no_device
        ldx #>msg_no_device
        jmp message_box
.close  jsr CLRCHN
        lda #FILE_LFN
        jsr CLOSE
        jsr io_end
        jmp box_close
.sa     !byte 0

;----------------------------------------------------------------------------
; each_range - go through the whole text in order, a piece at a time: the
; routine at range_call gets each piece as ptr up to range_end, and answers
; with carry set to stop there (A as it leaves it; carry set comes back).
; The pieces: the text before the gap and after it - and around them a
; long document's head and tail, a page at a time (reudoc.asm).
;----------------------------------------------------------------------------
!zone each_range
each_range
        lda reu_docs            ; (a long document: its head first)
        beq +
        jsr each_head
        bcs .ret
+       lda #<BUF_START         ; the text before the gap ...
        sta ptr
        lda #>BUF_START
        sta ptr+1
        lda gap_start
        sta range_end
        lda gap_start+1
        sta range_end+1
        jsr range_go
        bcs .ret
        lda gap_end             ; ... and after it
        sta ptr
        lda gap_end+1
        sta ptr+1
        lda text_end
        sta range_end
        lda text_end+1
        sta range_end+1
        jsr range_go
        bcs .ret
        lda reu_docs            ; (and its tail last)
        beq .ret
        jmp each_tail
.ret    rts
range_go
        jmp (range_call)

range_end       !word 0         ; each_range: the piece ends here
range_call      !word 0         ;   and goes to this routine

; range_byte - for each_range's routines: A = the next byte of the piece
; (ptr moves on), or carry set at its end
range_byte
        lda ptr
        cmp range_end
        bne +
        lda ptr+1
        cmp range_end+1
        sec
        beq ++
+       ldy #0
        lda (ptr),y
        inc ptr
        bne +
        inc ptr+1
+       clc
++      rts

;----------------------------------------------------------------------------
; has_codes - carry set if the text has color or reverse codes in it
; (which ASCII can't keep)
;----------------------------------------------------------------------------
!zone has_codes
has_codes
        lda #<.range
        sta range_call
        lda #>.range
        sta range_call+1
        jmp each_range
.range  jsr range_byte          ; (each piece)
        bcs .none
        tax
        lda ctype,x
        bpl .yes                ; 0-15: a color code
        cmp #CT_RVSON
        beq .yes
        cmp #CT_RVSOFF
        bne .range
.yes    sec
        rts
.none   clc
        rts

;============================================================================
; Disk directory and disk command (the Load and Save menus)
;============================================================================
GETIN           = $ffe4         ; KERNAL: a key from its buffer (0 = none)

; dir_load, dir_save - Disk directory: the directory of the Load or the
; Save menu's device, a screenful at a time (any key: the next; RUN/STOP:
; back). It shows in the plain display of disk work, and the keys come
; through the KERNAL meanwhile.
!zone disk_directory
dir_load
        lda load_dev
        jmp disk_directory
dir_save
        lda save_dev
disk_directory
        cmp #1
        bne +
        lda #<msg_no_tape       ; (no directory on tape)
        ldx #>msg_no_tape
        jmp message_box
+       sta cur_dev
        lda #$24                ; "$"
        sta name_buf
        lda #1
        sta name_len
        jsr io_begin
        lda #MEMPTR_UPPER       ; in upper case/graphics, as file names are
        sta VIC_MEMPTR          ; meant to look (io_end puts the document's
                                ; set back; C= + SHIFT still switches)
        ldy #0                  ; the command channel, to hear from the drive
        jsr open_cmd
        lda name_len            ; "$" with secondary address 0, as LOAD"$"
        ldx #<name_buf          ; does: the directory as a BASIC program
        ldy #>name_buf
        jsr SETNAM
        lda #FILE_LFN
        ldx cur_dev
        ldy #0
        jsr SETLFS
        jsr OPEN
        bcc +
        jmp .no_device
+       jsr read_status
        bcc +
        jmp .fail
+       ldx #FILE_LFN
        jsr CHKIN
        bcc +
        jmp .no_device
+       jsr readable_color      ; the whole screen, in the box color
        sta box_color
        lda #0
        sta box_left
        lda #40
        sta box_width
        jsr .clear
        jsr CHRIN               ; (the load address)
        jsr CHRIN

.line   jsr CHRIN               ; a line: its link (0 = no more lines) ...
        sta .link
        jsr CHRIN
        ora .link
        beq .end
        jsr READST
        bne .end
        jsr CHRIN               ; ... its number (the blocks) ...
        sta num24
        jsr CHRIN
        sta num24+1
        lda #0
        sta num24+2
        jsr num24_text
        ldx .row
        jsr box_row_ptrs
        ldy #0
        lda #<num_text
        ldx #>num_text
        jsr box_print
        iny
        lda #0                  ; ... then its text, up to a 0
        sta .rvs
.char   jsr CHRIN
        cmp #0
        beq .eol
        cmp #$12                ; RVS ON (the disk's name)
        bne +
        lda #$80
        sta .rvs
        bne .char
+       jsr petscii_to_screen
        bcs .char               ; (other control codes: nothing)
        ora .rvs
        cpy #40
        bcs .char               ; (past the edge: cut)
        jsr box_put
        jmp .char
.eol    inc .row
        lda .row
        cmp #23
        bcc .line
        lda #<m_more            ; a screenful: wait
        ldx #>m_more
        jsr .bottom
        jsr .wait
        cmp #3                  ; RUN/STOP: back
        beq .done
        jsr .clear
        jmp .line
.end    jsr .wait               ; the end: any key goes back
.done   jsr .let_go             ; (so the key is not seen by the menu too)
        jsr close_all
        jsr io_end
        jmp redraw_all          ; (the document again; the menu goes back
                                ; on top of it)
.no_device
        lda #<msg_no_device
        ldx #>msg_no_device
        jsr copy_message
.fail   jsr close_all
        jsr io_end
        lda #<status_buf
        ldx #>status_buf
        jmp message_box

; .clear - a blank screen; the next line goes on row 0
.clear  ldx #0
        stx .row
-       stx .x
        jsr box_row_ptrs
        ldy #0
--      lda #$20
        jsr box_put
        cpy #40
        bcc --
        ldx .x
        inx
        cpx #25
        bcc -
        rts

; .bottom - A/X = a line for the bottom row
.bottom pha
        txa
        pha
        ldx #24
        jsr box_row_ptrs
        pla
        tax
        pla
        ldy #0
        jmp box_print

; .wait - wait for a key (the KERNAL's, while the disk is in use): first
; for the keys held now to be let go, then for a new one. (Otherwise the
; key that chose Disk directory, still down when the KERNAL starts reading
; the keyboard, would count as the key that ends the listing.) GETIN reads
; from the current input, so the keyboard first, and afterwards the
; directory again. Returns A = the key.
.wait   jsr CLRCHN              ; (input from the keyboard)
        jsr .let_go
-       jsr GETIN
        beq -
        pha
        ldx #FILE_LFN           ; (input from the directory again)
        jsr CHKIN
        pla
        rts

; .let_go - wait until no key is held, then forget the keys the KERNAL has
; collected so far
.let_go
-       lda SFDX                ; the key held now (64 = none), from the
        cmp #64                 ; KERNAL's keyboard scan
        bne -
        lda #0
        sta NDX
        rts

.link   !byte 0
.row    !byte 0
.rvs    !byte 0
.x      !byte 0

; cmd_load, cmd_save - Disk command: send a command to the Load or the
; Save menu's device on channel 15 and show its answer. An empty command
; just shows the drive's status.
!zone disk_command
cmd_load
        lda load_dev
        jmp disk_command
cmd_save
        lda save_dev
disk_command
        cmp #1
        bne +
        lda #<msg_no_tape       ; (not for tape)
        ldx #>msg_no_tape
        jmp message_box
+       sta cur_dev
        lda #0                  ; a new command each time
        sta input_len
        lda #27                 ; (the box fills the screen's width)
        sta input_max
        lda #1                  ; (RETURN on its own: the status)
        sta input_empty_ok
        lda #<msg_command
        ldx #>msg_command
        jsr prompt_input
        bcc +
        rts                     ; cancelled
+       jsr io_begin
        lda #<input_buf         ; the command goes with the opening of
        ldx #>input_buf         ; channel 15
        ldy input_len
        jsr open_cmd
        jsr read_status         ; the answer (or "device not present")
        jsr close_all
        jsr io_end
        lda #<status_buf
        ldx #>status_buf
        jmp message_box

;============================================================================
; Settings on disk: MAGIC T DEFAULTS
;
; Save defaults writes every setting to the file MAGIC T DEFAULTS (SEQ) on
; the disk the program was loaded from; start-up reads them back. The
; file is the header of the magic format (phase 10) and nothing else:
;   $00 "MTW" "1"             (the version)
;   $40 + the number of settings that follow
;   one byte per setting, $40 + its value (all of them printable letters)
;   a RETURN
; A reader skips settings it does not know and keeps its own for those
; missing, so later versions can add some.
;============================================================================
DEFAULTS_COUNT  = 13            ; settings in version 1
DEFAULTS_LEN    = 6 + DEFAULTS_COUNT + 1
defaults_buf    !fill DEFAULTS_LEN, 0

; where each setting is kept, in their order in the file (the character
; set, 0 = upper case/graphics and 1 = upper/lower, is the VIC's)
defaults_vars
        !word text_bg, text_color, 0, wrap_on, edit_mode, mark_key
        !word load_format, load_dev, save_format, save_type, save_dev
        !word print_ascii, print_dev

defaults_name   !pet "magic t defaults"
DEFAULTS_NAME_LEN = * - defaults_name

; defaults_make - the settings into defaults_buf
!zone defaults_make
defaults_make
        ldx #5
-       lda defaults_head,x
        sta defaults_buf,x
        dex
        bpl -
        ldx #0
.next   txa
        asl
        tay
        lda defaults_vars,y
        sta zp_ptr2
        lda defaults_vars+1,y
        sta zp_ptr2+1
        ora zp_ptr2
        bne +
        lda VIC_MEMPTR          ; (the character set)
        lsr
        and #1
        bpl ++
+       ldy #0
        lda (zp_ptr2),y
++      clc
        adc #$40
        sta defaults_buf+6,x
        inx
        cpx #DEFAULTS_COUNT
        bcc .next
        lda #$0d
        sta defaults_buf+6,x
        rts

; how the file starts: $00 "MTW1", and $40 + the number of settings
defaults_head   !byte $00, $4d, $54, $57, $31, $40 + DEFAULTS_COUNT

; defaults_apply - the settings from defaults_buf (read from a file),
; if it starts as it should: all of them (MAGIC T DEFAULTS).
; doc_apply - the same for a document's header: only the settings that
; go with a document (doc_settings; Jim, 2026-09-30).
!zone defaults_apply
defaults_apply
        lda #0
        beq +
doc_apply
        lda #1
+       sta .doc
        ldx #4                  ; $00 "MTW1"
-       lda defaults_buf,x
        cmp defaults_head,x
        bne .done               ; not ours, or another version
        dex
        bpl -
        lda defaults_buf+5      ; how many settings it holds
        sec
        sbc #$40
        cmp #DEFAULTS_COUNT+1
        bcc +
        lda #DEFAULTS_COUNT     ; (more than we know: the ones we know)
+       sta .count
        ldx #0
.next   cpx .count
        bcs .done
        lda .doc                ; a document: only its own settings
        beq +
        lda doc_settings,x
        beq .skip
+       txa
        asl
        tay
        lda defaults_vars,y
        sta zp_ptr2
        lda defaults_vars+1,y
        sta zp_ptr2+1
        lda defaults_buf+6,x
        sec
        sbc #$40
        and #$3f                ; (keep a damaged file's values small)
        ldy zp_ptr2
        bne +
        ldy zp_ptr2+1
        bne +
        ldy #MEMPTR_UPPER       ; (the character set)
        cmp #0
        beq ++
        ldy #MEMPTR_LOWER
++      sty VIC_MEMPTR
        jmp ++
+       ldy #0
        sta (zp_ptr2),y
++
.skip   inx
        bne .next
.done   rts
.count  !byte 0
.doc    !byte 0

; The settings a Magic Typewriter document brings with it (1), in the
; order of defaults_vars: background, text color, wordwrap, Load format,
; Save format, File type. (Its character set comes with the case code at
; the start of its text, as with PETSCII files.) The header holds all 13,
; like MAGIC T DEFAULTS; the others are left as they are.
doc_settings
        !byte 1, 1, 0, 1, 0, 0, 1, 0, 1, 1, 0, 0, 0

; defaults_file - input_buf = "MAGIC T DEFAULTS" (for name_plus)
!zone defaults_file
defaults_file
        ldx #DEFAULTS_NAME_LEN-1
-       lda defaults_name,x
        sta input_buf,x
        dex
        bpl -
        lda #DEFAULTS_NAME_LEN
        sta input_len
        rts

; save_defaults - Save defaults (main menu): scratch the old file, write
; the settings. Only onto the disk the program came from.
!zone save_defaults
save_defaults
        lda load_device         ; ($BA at start-up)
        cmp #8
        bcc .no_disk
        cmp #31
        bcc +
.no_disk
        lda #<msg_need_disk
        ldx #>msg_need_disk
        jmp message_box
+       sta cur_dev
        jsr defaults_make
        jsr defaults_file
        lda #<msg_saving
        ldx #>msg_saving
        jsr busy_box
        jsr io_begin
        jsr scratch_input       ; "S0:MAGIC T DEFAULTS"
        bcs .fail
        lda #<suffix_write      ; then the new one
        ldx #>suffix_write
        jsr name_plus
        jsr open_file
        bcs .no_device
        jsr read_status
        bcs .fail
        ldx #FILE_LFN
        jsr CHKOUT
        bcs .no_device
        ldx #0
-       lda defaults_buf,x
        jsr CHROUT
        inx
        cpx #DEFAULTS_LEN
        bcc -
        jsr CLRCHN
        lda #FILE_LFN
        jsr CLOSE
        jsr read_status
        bcs .fail
        jsr close_all
        jsr io_end
        jsr box_close
        lda #<msg_defaults_saved
        ldx #>msg_defaults_saved
        jmp message_box
.no_device
        lda #<msg_no_device
        ldx #>msg_no_device
        jsr copy_message
.fail   jsr close_all
        jsr io_end
        jsr box_close
        lda #<status_buf
        ldx #>status_buf
        jmp message_box

; scratch_input - send "S0:" + input_buf on channel 15 (it is opened for
; that) and read the answer. Carry set on an error. "01, FILES SCRATCHED"
; is the usual answer, even when there was no such file; some drives say
; "62, FILE NOT FOUND" then instead, which is fine too.
!zone scratch_input
scratch_input
        lda #$53                ; S
        sta name_buf
        lda #$30                ; 0
        sta name_buf+1
        lda #$3a                ; :
        sta name_buf+2
        ldx #0
-       lda input_buf,x
        sta name_buf+3,x
        inx
        cpx input_len
        bcc -
        txa
        clc
        adc #3
        tay
        lda #<name_buf
        ldx #>name_buf
        jsr open_cmd
        jsr read_status
        bcc .ok                 ; (01, FILES SCRATCHED)
        lda status_buf          ; 62? (status_buf, not status_raw: when the
        cmp #$36                ; drive does not answer, it holds "device
        bne .error              ; not present" instead)
        lda status_buf+1
        cmp #$32
        bne .error
        clc                     ; nothing to scratch: fine
.ok     rts
.error  sec
        rts

