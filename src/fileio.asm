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
STOP            = $ffe1
BLNSW           = $cc           ; KERNAL: 0 = blink its cursor
NDX             = $c6           ; KERNAL: keys waiting in its buffer
SFDX            = $cb           ; KERNAL: the key held now (64 = none)

FILE_LFN        = 2             ; logical file number (and secondary
                                ; address) for the document file
CMD_LFN         = 15            ; the drive's command/error channel

; Settings (the Load, Save and Print menus change them)
FORMAT_MAGIC    = 0             ; file formats (the Format settings)
FORMAT_PETSCII  = 1
FORMAT_ASCII    = 2
FORMAT_SPEEDSCRIPT = 3
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
        lda #<KERNAL_IRQ
        sta IRQ_VECTOR
        lda #>KERNAL_IRQ
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
        ldx #CMD_LFN
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
        jsr check_load          ; (tape and SpeedScript: not yet)
        bcc +
        rts
+       lda modified            ; changes not saved: ask first
        beq +
        lda #<msg_load_unsaved
        ldx #>msg_load_unsaved
        jsr prompt_yes_no
        bcs +
        rts
+       jsr name_to_input
        lda #<msg_load
        ldx #>msg_load
        jsr prompt_input
        bcc +
        rts                     ; cancelled
+       lda load_dev
        sta cur_dev
        lda #0
        sta load_prg_skip
        lda #<suffix_read       ; a SEQ file first ...
        ldx #>suffix_read
        jsr name_plus
        lda #<msg_loading
        ldx #>msg_loading
        ldy #0
        jsr box_open
        jsr io_begin

        ldy #0                  ; the command channel, no command
        jsr open_cmd
        jsr open_file
        bcc +
        jmp .no_device
+       jsr read_status         ; e.g. 62, FILE NOT FOUND
        bcc .opened
        lda status_buf          ; ... but "64, FILE TYPE MISMATCH": it is
        cmp #$36                ; a PRG file, so open it as one
        bne .to_fail
        lda status_buf+1
        cmp #$34
        bne .to_fail
        lda #FILE_LFN
        jsr CLOSE
        jsr prg_fits            ; small enough for the room? then KERNAL
        bcs +                   ; LOAD, which fast loaders speed up
        jmp .kernal_load
+       lda #1                  ; (too big: read what fits, byte by byte)
        sta load_prg_skip
        lda #<suffix_prg_read
        ldx #>suffix_prg_read
        jsr name_plus
        jsr open_file
        bcc +
        jmp .no_device
+       jsr read_status
        bcc .opened
.to_fail
        jmp .fail

        ; A PRG file that fits: loaded with the KERNAL's LOAD. With
        ; secondary address 0 it goes where we say (BUF_START), whatever
        ; its own load address, which LOAD takes off.
.kernal_load
        lda #0                  ; (no KERNAL messages)
        jsr SETMSG
        lda input_len
        ldx #<input_buf
        ldy #>input_buf
        jsr SETNAM
        lda #FILE_LFN
        ldx cur_dev
        ldy #0
        jsr SETLFS
        lda #0                  ; load, not verify
        ldx #<BUF_START
        ldy #>BUF_START
        jsr LOAD
        lda EAL                 ; where it stopped (the end, if all went
        cmp #<BUF_START         ; well): if it got nowhere, the document
        bne +                   ; is untouched
        lda EAL+1
        cmp #>BUF_START
        bne +
        jsr read_status
        jmp .fail
+       lda EAL                 ; the text: BUF_START up to there
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
        beq .full
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

; .show - make the file into text and show it from the top, cursor at the
; start (after io_end: this uses the editor)
.show   lda #0                  ; nothing marked
        sta sel_on
        jsr convert_loaded
        jsr gap_to_start
        jsr empty_view
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
load_prg_skip   !byte 0         ; 1: a PRG read byte by byte (its load
                                ; address is still in front)

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
        lda #<BUF_START
        sta ptr
        sta ptr2
        lda #>BUF_START
        sta ptr+1
        sta ptr2+1
        lda #0
        sta load_charset
        lda load_format         ; how to read it (unless it has the header)
        sta .fmt

        ; A PRG file read byte by byte starts with its load address.
        ; (KERNAL LOAD takes it off itself.)
        lda load_prg_skip
        beq .header
        jsr .skip2

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

.ascii  ; ASCII: capitals and small letters change places; a RETURN, a
        ; line feed, or both, is a line end; a tab is a space; other
        ; control codes go.
        cmp #$0d
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

.done   lda ptr2                ; the text ends here
        sta gap_start
        lda ptr2+1
        sta gap_start+1
        lda .fmt
        sta save_format
        rts

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

; .skip2 - ptr on by 2 (a load address)
.skip2  jsr .get
        jmp .get

; .lf_after - after a RETURN: a line feed straight after it goes too
.lf_after
        lda #1
        jsr .has
        bcc +
        ldy #0
        lda (ptr),y
        cmp #$0a
        bne +
        jsr .get
+       rts

.fmt    !byte 0
.t      !word 0

;----------------------------------------------------------------------------
; prg_fits - does the file named in input_buf (a PRG) fit in the room for
; the text (BUF_START up to the clipboard)? KERNAL LOAD doesn't stop at
; the end of the buffer, and past $cfff are the I/O chips. Its size comes
; from the directory ("$:" + the name, read as LOAD"$" would): its blocks,
; at most 254 bytes each. Carry clear if it fits. (Between io_begin and
; io_end; channel 15 stays open.)
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
        lda #FILE_LFN
        ldx cur_dev
        ldy #0                  ; (secondary address 0: the listing)
        jsr SETLFS
        jsr OPEN
        bcs .no
        ldx #FILE_LFN
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
        lda #FILE_LFN
        jmp CLOSE

.blocks !word 0
.size   !word 0
.t      !word 0

;============================================================================
; Saving
;============================================================================

; check_load, check_save - carry set (after saying so) if the Load or Save
; settings ask for something not built yet: tape (phase 11), SpeedScript.
!zone check_load
check_load
        lda load_dev
        cmp #1
        beq .no
        lda load_format
        cmp #FORMAT_SPEEDSCRIPT
        beq .no
        clc
        rts
check_save
        lda save_dev
        cmp #1
        beq .no
        lda save_format
        cmp #FORMAT_SPEEDSCRIPT
        beq .no
        clc
        rts
.no     jsr not_yet
        sec
        rts

; save_as - the Save menu's Save: ask for a name (the last one used is
; filled in) and save under it
save_as jsr check_save
        bcc +
        rts
+       jsr leave_cursor        ; (as CTRL-S: no codes without effect)
        jsr name_to_input
        lda #<msg_save
        ldx #>msg_save
        jsr prompt_input
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
        jsr prompt_input
        bcc save_file
        rts                     ; cancelled
+       jsr name_to_input
        ; (falls into save_file)

; save_file - save the document under the name in input_buf, in the Save
; format and file type. An old file of that name is scratched first
; ("S0:name"), then the new one is written. (Not "@0:": some drives have a
; bug in save-with-replace.) What goes into the file:
;   a PRG file:        the load address first: $4000, where the text goes
;                      (load_file uses KERNAL LOAD for it, so fast loaders
;                      speed it up; a stray LOAD"NAME",8,1 lands there too)
;   magic:             the header (the settings, as in MAGIC T DEFAULTS)
;   magic and PETSCII: the character set as a case code ($0e / $8e)
;   then the text:     as it is (magic, PETSCII), or made ASCII: small
;                      letters and capitals swapped, a line end as RETURN
;                      and line feed, colors, reverse and other codes left
;                      out (it asks first if there are colors to lose)
save_file
        jsr check_save          ; (tape, SpeedScript: not yet)
        bcc +
        rts
+       jsr name_ok             ; no * ? or , in the name
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
        lda #<msg_saving
        ldx #>msg_saving
        ldy #0
        jsr box_open
        jsr io_begin

        jsr scratch_input       ; the old file goes first ("S0:" + name)
        bcc +
        jmp .fail
+       lda #<suffix_write      ; now the file: name + ",S,W" or ",P,W"
        ldx #>suffix_write
        ldy save_type
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
        bcc +
        jmp .no_device
.to_bus jmp .bus_error          ; (for branches that cannot reach)

+       lda save_type           ; a PRG: the load address, where the text
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
        lda VIC_MEMPTR          ; graphics). load_file takes it back as the
        and #%00000010          ; setting, and other programs that print
        beq +                   ; the file switch to the right set with it.
        lda #$0e
        bne ++
+       lda #$8e
++      jsr .out
        bcs .bus_error

.text   ; Then the text before the gap, and the text after it.
        lda #<BUF_START
        sta ptr
        lda #>BUF_START
        sta ptr+1
        lda gap_start
        sta .end
        lda gap_start+1
        sta .end+1
        jsr .write
        bcs .stopped
        lda gap_end
        sta ptr
        lda gap_end+1
        sta ptr+1
        lda text_end
        sta .end
        lda text_end+1
        sta .end+1
        jsr .write
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

; .out - A to the file. Carry set if the bus reports an error. Keeps X.
.out    jsr CHROUT
        jsr READST
        cmp #1
        rts

; .write - send the text from ptr up to .end to the file, in the Save
; format. Carry set if it stopped early: A = 0 for RUN/STOP, else a bus
; error.
.write
-       lda ptr
        cmp .end
        bne +
        lda ptr+1
        cmp .end+1
        beq .done
+       jsr STOP
        beq .break
        ldy #0
        lda (ptr),y
        ldx save_format
        cpx #FORMAT_ASCII
        bne +
        jsr .ascii              ; (ASCII: made so first)
        jmp ++
+       jsr CHROUT
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

.end    !word 0

;----------------------------------------------------------------------------
; has_codes - carry set if the text has color or reverse codes in it
; (which ASCII can't keep)
;----------------------------------------------------------------------------
!zone has_codes
has_codes
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
        bcs .none
        ldy #0
        lda (ptr),y
        tax
        lda ctype,x
        bpl .yes                ; 0-15: a color code
        cmp #CT_RVSON
        beq .yes
        cmp #CT_RVSOFF
        beq .yes
        inc ptr
        bne .loop
        inc ptr+1
        bne .loop
.none   clc
        rts
.yes    sec
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
        ldy #0
        jsr box_open
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

