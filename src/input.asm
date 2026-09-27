;============================================================================
; input.asm - keyboard matrix scanner, RESTORE key, debug test mailbox
; (The 1351 mouse comes in phase 7.)
;============================================================================

;============================================================================
; Keyboard
;
; We scan the keyboard matrix ourselves instead of using the KERNAL, because
; the KERNAL turns CTRL-letters into control codes and can't tell the two
; SHIFT keys apart.
;
; The matrix: writing a byte to $DC00 with one bit low selects one "row";
; $DC01 then shows the 8 keys of that row, 0 = pressed. A key's code is
;     row * 8 + bit          (the same numbers the KERNAL uses)
;
;          bit 0    bit 1    bit 2    bit 3    bit 4    bit 5    bit 6    bit 7
; row 0    DEL      RETURN   CRSR RT  F7       F1       F3       F5       CRSR DN
; row 1    3        W        A        4        Z        S        E        L-SHIFT
; row 2    5        R        D        6        C        F        T        X
; row 3    7        Y        G        8        B        H        U        V
; row 4    9        I        J        0        M        K        O        N
; row 5    +        P        L        -        .        :        @        ,
; row 6    pound    *        ;        HOME     R-SHIFT  =        up-arrow /
; row 7    1        <-       CTRL     2        SPACE    C=       Q        RUN/STOP
;
; SHIFT LOCK is wired to the same line as the left SHIFT.
;
; scan_keyboard runs once per frame from the housekeeping IRQ. Each new key
; press becomes a "key event" in a small queue: the key code plus the
; modifier keys held at that moment. Holding a key repeats it. The modifier
; keys (both SHIFTs, CTRL, C=) never make events of their own; get their
; state from key_mods. The main program takes events with get_key and
; turns them into PETSCII with key_to_petscii.
;============================================================================

; Key codes (row * 8 + bit)
KEY_DEL         = 0
KEY_RETURN      = 1
KEY_RIGHT       = 2             ; CRSR left/right
KEY_F7          = 3
KEY_F1          = 4
KEY_F3          = 5
KEY_F5          = 6
KEY_DOWN        = 7             ; CRSR up/down
KEY_LSHIFT      = 15
KEY_HOME        = 51
KEY_RSHIFT      = 52
KEY_ARROW       = 57            ; the left-arrow key
KEY_CTRL        = 58
KEY_SPACE       = 60
KEY_CBM         = 61
KEY_STOP        = 63
KEY_Y           = 25
KEY_S           = 13
KEY_L           = 42
KEY_N           = 39

; Events that are not a single key
KEY_CHARSET     = $40           ; C= and SHIFT pressed and let go alone
KEY_RESTORE     = $41           ; the RESTORE key

; Modifier bits (in key_mods and in each event)
MOD_LSHIFT      = %00000001
MOD_RSHIFT      = %00000010
MOD_SHIFT       = MOD_LSHIFT | MOD_RSHIFT       ; either SHIFT
MOD_CTRL        = %00000100
MOD_CBM         = %00001000
MOD_REPEAT      = %10000000     ; event made by holding the key down

KEY_QUEUE_SIZE  = 16            ; must be a power of 2

; Key repeat, timed like BASIC. The KERNAL counts in "ticks" of 1/60
; second: the first repeat comes 19 ticks after the press, then one every
; 4 ticks (15 per second). We scan once per frame instead (50 per second
; on PAL, 60 on NTSC), so key_timer counts in steps of 1/300 second: each
; frame takes 6 steps off on PAL and 5 on NTSC (timing table), and the
; same numbers give the same speed on every machine.
REPEAT_DELAY    = 19 * 5        ; 19 ticks, in 1/300 second steps
REPEAT_RATE     = 4 * 5         ; 4 ticks

;----------------------------------------------------------------------------
; Keyboard variables
;----------------------------------------------------------------------------
key_now         !fill 8, 0      ; matrix this frame, one byte per row,
                                ; 1 = key down (the opposite of $DC01)
key_before      !fill 8, 0      ; matrix last frame
key_mods        !byte 0         ; modifier keys held now (MOD_... bits)
key_last        !byte $ff       ; key that repeats if held ($ff = none)
key_timer       !byte 0         ; time until it repeats, in 1/300 s steps
key_step        !byte 0         ; 1/300 s steps per frame (timing table)
key_charset     !byte 0         ; C= + SHIFT toggle: 0 = idle, 1 = both held,
                                ; 2 = another key was pressed meanwhile
key_restores    !byte 0         ; counts RESTORE presses (NMI handler)
key_restores_seen !byte 0
key_port1       !byte 0         ; lines held low by port 1 this frame
key_row         !byte 0         ; scratch for the scanner
key_bits        !byte 0
key_code        !byte 0

key_q_code      !fill KEY_QUEUE_SIZE, 0 ; event queue: key codes ...
key_q_mods      !fill KEY_QUEUE_SIZE, 0 ; ... and modifiers
key_q_head      !byte 0         ; next free slot (written by the IRQ)
key_q_tail      !byte 0         ; next event to read (main program)

old_nmi         !word 0         ; the NMI vector before we started

; $DC00 value that selects each row
row_select      !byte $fe, $fd, $fb, $f7, $ef, $df, $bf, $7f
; one bit for each bit number
bit_mask        !byte $01, $02, $04, $08, $10, $20, $40, $80
; per row: the bits that are NOT modifier keys (modifiers make no events)
not_modifier    !byte $ff, $7f, $ff, $ff, $ff, $ff, $ef, $db

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

; restore_keyboard - put the NMI vector back (for Quit). IRQs off.
restore_keyboard
        lda old_nmi
        sta NMI_VECTOR
        lda old_nmi+1
        sta NMI_VECTOR+1
        rts

; nmi_handler - the RESTORE key. Just counts it; scan_keyboard turns it
; into a KEY_RESTORE event (treated like RUN/STOP). INC changes no
; registers, and RTI restores the flags.
nmi_handler
        inc key_restores
        rti

;----------------------------------------------------------------------------
; scan_keyboard - read the matrix and queue key events. Called once per
; frame from the housekeeping IRQ.
;----------------------------------------------------------------------------
!zone scan_keyboard
scan_keyboard
        ; A joystick or mouse in port 1 pulls $DC01 lines low, just like a
        ; key press. With no row selected, anything low on $DC01 comes from
        ; port 1: ignore those lines this frame.
        lda #$ff
        sta CIA1_PRA
        lda CIA1_PRB            ; 1 = line free
        sta key_port1

        ldx #7                  ; read rows 7 down to 0
.row    lda row_select,x
        sta CIA1_PRA
-       lda CIA1_PRB            ; read twice, until two reads agree
        cmp CIA1_PRB
        bne -
        eor #$ff                ; now 1 = key down
        and key_port1           ; drop the port 1 lines
        sta key_now,x
        dex
        bpl .row

        lda #$7f                ; leave row 7 selected, like the KERNAL
        sta CIA1_PRA            ; (this also points the SID's paddle
                                ; inputs at port 1, for the mouse later)
!if DEBUG {
        jsr mailbox_keys        ; add any key the test harness sent
}

        ; Modifier keys
        lda #0
        sta key_mods
        lda key_now+1
        and #%10000000          ; row 1 bit 7: left SHIFT (or SHIFT LOCK)
        beq +
        lda #MOD_LSHIFT
        ora key_mods
        sta key_mods
+       lda key_now+6
        and #%00010000          ; row 6 bit 4: right SHIFT
        beq +
        lda #MOD_RSHIFT
        ora key_mods
        sta key_mods
+       lda key_now+7
        and #%00000100          ; row 7 bit 2: CTRL
        beq +
        lda #MOD_CTRL
        ora key_mods
        sta key_mods
+       lda key_now+7
        and #%00100000          ; row 7 bit 5: C=
        beq +
        lda #MOD_CBM
        ora key_mods
        sta key_mods
+

        ; Key repeat: is the last key pressed still down? (Done before
        ; looking for new presses, so a new key's countdown starts next
        ; frame.)
        lda key_last
        bmi .no_repeat          ; $ff = none
        lsr                     ; row = code / 8
        lsr
        lsr
        tax
        lda key_last
        and #7
        tay
        lda key_now,x
        and bit_mask,y
        bne +
        lda #$ff                ; let go: no more repeats
        sta key_last
        bne .no_repeat
+       lda key_timer           ; count down by one frame's worth
        sec
        sbc key_step
        beq .repeat             ; reached 0 ...
        bcs .wait               ; still above 0
.repeat clc                     ; ... or went past it: repeat now, and
        adc #REPEAT_RATE        ; count the next wait from where this one
        sta key_timer           ; ended (so PAL averages out to 15/second)
        lda key_mods
        ora #MOD_REPEAT
        tax
        lda key_last
        jsr .queue
        jmp .no_repeat
.wait   sta key_timer
.no_repeat

        ; New key presses: down now, not down last frame, not a modifier.
        ldx #7
.new    lda key_before,x
        eor #$ff
        and key_now,x
        and not_modifier,x
        beq .next_row
        stx key_row
        sta key_bits
        ldy #7                  ; check each bit of the row
.bit    lda key_bits
        and bit_mask,y
        beq .next_bit
        txa                     ; key code = row * 8 + bit
        asl
        asl
        asl
        sta key_code
        tya
        ora key_code
        sta key_last            ; the newest key is the one that repeats
        ldx key_mods
        jsr .queue
        lda #REPEAT_DELAY
        sta key_timer
        ldx key_row
.next_bit
        dey
        bpl .bit
.next_row
        dex
        bpl .new

        ; Character set toggle: C= and a SHIFT held together, then let go
        ; without any other key pressed in between.
        lda key_mods
        and #MOD_CBM
        beq .cs_off
        lda key_mods
        and #MOD_SHIFT
        beq .cs_off
        lda #0                  ; both held: is any other key down too?
        sta key_bits
        ldx #7
-       lda key_now,x
        and not_modifier,x
        ora key_bits
        sta key_bits
        dex
        bpl -
        lda key_bits
        beq +
        lda #2                  ; yes: this is not a toggle (for example
        sta key_charset         ; C= + SHIFT + CRSR, marking upward)
        bne .cs_done
+       lda key_charset         ; no: arm the toggle, unless it was
        bne .cs_done            ; spoiled already
        lda #1
        sta key_charset
        bne .cs_done
.cs_off lda key_charset         ; not both held (any more)
        cmp #1
        bne +
        lda #KEY_CHARSET
        ldx #0
        jsr .queue
+       lda #0
        sta key_charset
.cs_done

        ; RESTORE, counted by the NMI handler
        lda key_restores
        cmp key_restores_seen
        beq +
        sta key_restores_seen
        lda #KEY_RESTORE
        ldx key_mods
        jsr .queue
+
        ; Remember this frame's matrix for the next one.
        ldx #7
-       lda key_now,x
        sta key_before,x
        dex
        bpl -
        rts

; .queue - add an event: A = key code, X = modifiers. Keeps Y.
; If the queue is full the event is dropped.
.queue  pha
        txa
        ldx key_q_head
        sta key_q_mods,x
        pla
        sta key_q_code,x
        inx
        txa
        and #KEY_QUEUE_SIZE-1
        cmp key_q_tail
        beq +                   ; full
        sta key_q_head          ; (moved last, so the event is complete
+       rts                     ; before the main program can see it)

;----------------------------------------------------------------------------
; get_key - take the next key event, if there is one.
; Returns carry clear with A = key code and Y = modifiers,
; or carry set if there is no event waiting.
;----------------------------------------------------------------------------
!zone get_key
get_key
        ldx key_q_tail
        cpx key_q_head
        beq .none
        lda key_q_code,x
        ldy key_q_mods,x
        pha
        inx
        txa
        and #KEY_QUEUE_SIZE-1
        sta key_q_tail
        pla
        clc
        rts
.none   sec
        rts

;----------------------------------------------------------------------------
; key_to_petscii - A = key code (0-63), Y = modifiers.
; Returns A = the PETSCII code the key types, as on the BASIC screen:
; CTRL wins, then C=, then SHIFT. Returns carry set if the key types
; nothing (modifier keys, RUN/STOP, CTRL with a key that has no code).
;----------------------------------------------------------------------------
!zone key_to_petscii
key_to_petscii
        cmp #64
        bcs .none               ; not a single key
        tax
        tya
        and #MOD_CTRL
        beq +
        lda keytab_ctrl,x
        jmp .check
+       tya
        and #MOD_CBM
        beq +
        lda keytab_cbm,x
        jmp .check
+       tya
        and #MOD_SHIFT
        beq +
        lda keytab_shift,x
        jmp .check
+       lda keytab_normal,x
.check  cmp #$ff                ; $ff: no code (in the CTRL table)
        beq .none
        cmp #$05                ; $01-$04 stand for the modifier keys and
        bcc .none               ; RUN/STOP; $00 (CTRL-@) types nothing
        clc
        rts
.none   sec
        rts

!if DEBUG {
;============================================================================
; Debug test mailbox (DEBUG=1 builds only)
;
; A fixed block of RAM that the test harness (Claude, through VICE's
; monitor) reads and writes while the editor runs. It sits in $02c0-$02fd,
; which the KERNAL and BASIC never use.
;
; Offset  Size  Who writes  What
;  +0      4    program     signature "MTDB" (ASCII) = mailbox is ready
;  +4      2    program     frame counter (lo/hi), +1 every frame
;  +6      1    program     system type: 0 PAL, 1 NTSC, 2 old NTSC, 3 Drean
;  +7      1    program     load device ($BA at start-up)
;  +8      2    harness     marker test: first visible line (lo/hi)
;  +10     2    harness     marker test: total lines (lo/hi)
;  +12     1    harness     write 1 to apply +8/+10; program sets it to 0
;  +13     1    program     marker result: first grey raster line
;  +14     1    program     marker result: first dark grey line after it
;  +15     1    program     raster line where housekeeping started
;  +16     1    harness     key queue head (next slot the harness fills)
;  +17     1    program     key queue tail (next slot the program reads)
;  +18    16    harness     key queue: 8 key presses of 2 bytes
;                             byte 0: key code (row * 8 + bit, see the
;                                     table at the top of this file),
;                                     or $ff for modifier keys only
;                             byte 1: bits 0-3 modifier keys held:
;                                     1 left SHIFT, 2 right SHIFT, 4 CTRL,
;                                     8 C=; bits 4-7 how long to hold the
;                                     keys, in steps of 8 frames
;                                     (0 = 1 frame)
;                           Each press is held that long, then all keys
;                           are let go for 1 frame. It goes through the
;                           same code as a real key press.
;  +34     1    harness     mouse queue head
;  +35     1    program     mouse queue tail
;  +36    12    harness     mouse queue: 4 events of 3 bytes
;                             dx (signed), dy (signed),
;                             buttons (bit 0 left, bit 1 right)
;  +48     4    program     SPLIT_TEST builds: top split early/late,
;                           bottom split early/late (1 = has happened)
;  +52     1    program     number of key events the main loop has taken
;                           (counts up, wraps at 256)
;  +53     8    program     the last 4 of those events, 2 bytes each
;                           (key code, modifiers), oldest first
;  +61     1    program     raster line where housekeeping ended
;  +62     1    program     raster line (low byte) where the bottom strip
;                           IRQ ended
;  -1      1    program     ($02bf) frames the last key took to handle
;  +63     1    harness     write 1 after putting a test document in the
;                           buffer: the text at the END of the buffer (up
;                           to $cfff), gap_end ($0a/$0b) = its first byte,
;                           gap_start ($08/$09) = $4000. The editor then
;                           shows it from the top, cursor at the start,
;                           and sets this back to 0.
;
; Queues: the harness writes an event at slot "head", then moves head on
; by one (wrapping 7 -> 0 for keys, 3 -> 0 for the mouse). The queue is
; empty when head = tail.
;============================================================================
MB_BASE         = $02c0
MB_SIG          = MB_BASE+0
MB_FRAMES       = MB_BASE+4
MB_SYSTEM       = MB_BASE+6
MB_LOADDEV      = MB_BASE+7
MB_MK_FIRST     = MB_BASE+8
MB_MK_TOTAL     = MB_BASE+10
MB_MK_GO        = MB_BASE+12
MB_MK_TOP       = MB_BASE+13
MB_MK_BOT       = MB_BASE+14
MB_HK_START     = MB_BASE+15
MB_KEY_HEAD     = MB_BASE+16
MB_KEY_TAIL     = MB_BASE+17
MB_KEY_QUEUE    = MB_BASE+18
MB_MOUSE_HEAD   = MB_BASE+34
MB_MOUSE_TAIL   = MB_BASE+35
MB_MOUSE_QUEUE  = MB_BASE+36
MB_TEST_TOP     = MB_BASE+48
MB_TEST_BOT     = MB_BASE+50
MB_KEY_COUNT    = MB_BASE+52
MB_KEY_LOG      = MB_BASE+53
MB_HK_END       = MB_BASE+61
MB_BOT_END      = MB_BASE+62
MB_DOC_READY    = MB_BASE+63
MB_KEY_TIME     = MB_BASE-1      ; (just below the mailbox)
MB_SIZE         = 64

;----------------------------------------------------------------------------
; mailbox_init - clear the mailbox and fill in the program's fields.
;----------------------------------------------------------------------------
!zone mailbox_init
mailbox_init
        lda #0
        ldx #MB_SIZE-1
-       sta MB_BASE,x
        dex
        bpl -
        lda system_type
        sta MB_SYSTEM
        lda load_device
        sta MB_LOADDEV
        ldx #3                  ; signature last: now the harness may start
-       lda .signature,x
        sta MB_SIG,x
        dex
        bpl -
        rts

.signature
        !byte $4d, $54, $44, $42        ; "MTDB" in ASCII

;----------------------------------------------------------------------------
; mailbox_poll - called from the main loop. Handles the marker test.
;----------------------------------------------------------------------------
!zone mailbox_poll
mailbox_poll
!ifdef SPLIT_TEST {
        ; Show the four split test flags as blocks at the start of row 24:
        ; white = has happened, black = not (read from a screenshot).
        ldx #3
-       lda #$a0                ; reversed space = solid block
        sta SCREEN+24*40,x
        lda MB_TEST_TOP,x
        sta COLOR_RAM+24*40,x   ; 1 = white, 0 = black
        dex
        bpl -
        ; Vary the length of the main loop, so the IRQs interrupt it at
        ; every possible point (this makes every jitter case happen).
        inc .vary
        lda .vary
        and #15
        tax
-       dex
        bpl -
}
        lda MB_DOC_READY        ; a test document in the buffer?
        beq +
        jsr test_document
+       lda MB_MK_GO
        beq +
        lda MB_MK_FIRST
        sta mk_first
        lda MB_MK_FIRST+1
        sta mk_first+1
        lda MB_MK_TOTAL
        sta mk_total
        lda MB_MK_TOTAL+1
        sta mk_total+1
        ora mk_total            ; total of 0 would divide by zero:
        beq .done               ; ignore it
        jsr marker_set
.done   lda #0
        sta MB_MK_GO
+       rts

!ifdef SPLIT_TEST {
.vary   !byte 0
}
key_start_frame !byte 0

; test_document - show the document the harness put in the buffer.
test_document
        jsr cursor_hide
        lda #0
        sta MB_DOC_READY
        sta row_off_lo          ; the top of the screen at the start
        sta row_off_hi
        sta row_rvs
        sta modified
        sta want_col
        lda text_color
        sta row_color
        jsr skip_codes          ; (the cursor goes after leading codes)
        jsr redraw_all
        jsr locate_cursor
        jmp cursor_show

;----------------------------------------------------------------------------
; mailbox_log_key - record a key event the main loop took (A = code,
; Y = modifiers) in the mailbox log. Keeps A and Y.
;----------------------------------------------------------------------------
!zone mailbox_log_key
mailbox_log_key
        pha
        ldx #0                  ; move the older entries down by one
-       lda MB_KEY_LOG+2,x
        sta MB_KEY_LOG,x
        inx
        cpx #6
        bne -
        pla
        sta MB_KEY_LOG+6
        sty MB_KEY_LOG+7
        inc MB_KEY_COUNT
        rts

;----------------------------------------------------------------------------
; mailbox_keys - called by scan_keyboard after reading the matrix: presses
; the keys of the next queued test event, by adding them to key_now.
;----------------------------------------------------------------------------
!zone mailbox_keys
mailbox_keys
        lda .frames             ; still holding the last event's keys?
        bne .press
        lda .gap                ; then one frame with nothing pressed
        beq +
        dec .gap
        rts
+       ldx MB_KEY_TAIL         ; anything new in the queue?
        cpx MB_KEY_HEAD
        bne +
        rts
+       txa
        asl                     ; 2 bytes per event
        tay
        lda MB_KEY_QUEUE,y
        sta .code
        lda MB_KEY_QUEUE+1,y
        sta .mods
        lsr                     ; hold time: bits 4-7, in steps of 8 frames
        and #%01111000          ; (= bits 4-7 shifted right once, times 8)
        bne +
        lda #1                  ; 0 = one frame
+       sta .frames
        lda #1
        sta .gap
        inx                     ; take it off the queue
        txa
        and #7
        sta MB_KEY_TAIL

.press  dec .frames
        lda .code
        cmp #$ff                ; modifiers only?
        beq .mods_in
        lsr                     ; row = code / 8
        lsr
        lsr
        tax
        lda .code
        and #7
        tay
        lda bit_mask,y
        ora key_now,x
        sta key_now,x
.mods_in
        lda .mods
        and #MOD_LSHIFT
        beq +
        lda key_now+1
        ora #%10000000          ; left SHIFT: row 1 bit 7
        sta key_now+1
+       lda .mods
        and #MOD_RSHIFT
        beq +
        lda key_now+6
        ora #%00010000          ; right SHIFT: row 6 bit 4
        sta key_now+6
+       lda .mods
        and #MOD_CTRL
        beq +
        lda key_now+7
        ora #%00000100          ; CTRL: row 7 bit 2
        sta key_now+7
+       lda .mods
        and #MOD_CBM
        beq +
        lda key_now+7
        ora #%00100000          ; C=: row 7 bit 5
        sta key_now+7
+       rts

.frames !byte 0
.gap    !byte 0
.code   !byte 0
.mods   !byte 0

}       ; end of !if DEBUG
