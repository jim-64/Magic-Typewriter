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
STOP            = $ffe1
BLNSW           = $cc           ; KERNAL: 0 = blink its cursor
NDX             = $c6           ; KERNAL: keys waiting in its buffer

FILE_LFN        = 2             ; logical file number (and secondary
                                ; address) for the document file
CMD_LFN         = 15            ; the drive's command/error channel

; Settings (the Load and Save menus change them in phase 8)
load_dev        !byte 8
save_dev        !byte 8

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
        cli
        rts

; io_end - KERNAL ROM out, our IRQs and the full display again
io_end  sei
        lda #ROMS_EDIT          ; the KERNAL ROM out: the editor at $e000
        sta CPU_PORT            ; is back
        lda #0                  ; forget keys the KERNAL collected
        sta NDX
        jsr init_irq            ; (switches the timer IRQ off again)
        lda #SPR_ON_ALL
        sta VIC_SPR_ENABLE
        cli
        rts

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

; keep_name - input_buf becomes the document's file name
!zone keep_name
keep_name
        ldx input_len
        stx file_name_len
        dex
-       lda input_buf,x
        sta file_name,x
        dex
        bpl -
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

; load_file - ask for a name and load a PETSCII file in place of the
; document.
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
        lda #<msg_load
        ldx #>msg_load
        jsr prompt_input
        bcc +
        rts                     ; cancelled
+       lda load_dev
        sta cur_dev
        lda #<suffix_read
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
        bcc +
        jmp .fail

        ; The file is there: from here on it replaces the document. Empty
        ; the text: the gap covers the whole buffer below the clipboard.
        ; (Done here, not with the editor's empty_buffer, which is out of
        ; reach while the KERNAL ROM is in; .show does the rest.)
+       lda #<BUF_START
        sta gap_start
        lda #>BUF_START
        sta gap_start+1
        lda text_end
        sta gap_end
        lda text_end+1
        sta gap_end+1
        lda #0
        sta .charset
        ldx #FILE_LFN
        jsr CHKIN
        bcc .byte
        jmp .no_device
.byte   jsr STOP                ; RUN/STOP breaks off
        beq .break
        jsr CHRIN
        sta .b
        lda gap_start           ; room left?
        cmp gap_end
        bne +
        lda gap_start+1
        cmp gap_end+1
        beq .full
+       lda .b
        ldy #0
        sta (gap_start),y
        inc gap_start
        bne +
        inc gap_start+1
+       lda .charset            ; the first $0e or $8e picks the character
        bne +                   ; set to show it in
        lda .b
        cmp #$0e                ; switch to lower case
        beq ++
        cmp #$8e                ; switch to upper case
        bne +
++      sta .charset
+       jsr READST
        beq .byte               ; 0: more to come
        and #%01000000
        beq .read_error         ; not the end: something went wrong
        jsr CLRCHN              ; the end of the file
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

; .show - show the loaded document from the top, cursor at the start
; (after io_end: this uses the editor)
.show   lda #0                  ; nothing marked
        sta sel_on
        jsr gap_to_start
        jsr empty_view
        lda .charset
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

.b              !byte 0
.charset        !byte 0

;============================================================================
; Saving
;============================================================================

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

; save_file - save the document as a PETSCII SEQ file named input_buf.
; An old file of that name is scratched first ("S0:name"), then the new one
; is written. (Not "@0:": some drives have a bug in save-with-replace.)
save_file
        lda save_dev
        sta cur_dev
        lda #<msg_saving
        ldx #>msg_saving
        ldy #0
        jsr box_open
        jsr io_begin

        ; Scratch the old file: "S0:" + name, sent on channel 15.
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
        tay                     ; Y = length
        lda #<name_buf
        ldx #>name_buf
        jsr open_cmd
        jsr read_status         ; 01, FILES SCRATCHED is fine
        bcc +
        jmp .fail
+
        lda #<suffix_write      ; now the file: name + ",S,W"
        ldx #>suffix_write
        jsr name_plus
        jsr open_file
        bcs .no_device
        jsr read_status         ; e.g. 26, WRITE PROTECT ON
        bcs .fail
        ldx #FILE_LFN
        jsr CHKOUT
        bcs .no_device

        ; Write the text before the gap, then the text after it.
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

; .write - send the bytes from ptr up to .end to the file. Carry set if it
; stopped early: A = 0 for RUN/STOP, else a bus error.
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
        jsr CHROUT
        jsr READST
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
.end    !word 0
