;============================================================================
; input.asm - keyboard matrix scanner, RESTORE key, 1351 mouse, debug test
; mailbox
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
KEY_X           = 23
KEY_C           = 20
KEY_V           = 31
KEY_A           = 10
KEY_N           = 39
KEY_W           = 9
KEY_F           = 21
KEY_Z           = 12

; Events that are not a single key
KEY_CHARSET     = $40           ; C= and SHIFT pressed and let go alone
KEY_RESTORE     = $41           ; the RESTORE key
KEY_MOUSE_L     = $42           ; mouse: left button pressed (where: see
KEY_MOUSE_R     = $43           ; click_row), right button pressed, or
KEY_MOUSE_DRAG  = $44           ; moved with the left button held

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
        lda key_q_head          ; ... but only if the program has taken all
        cmp key_q_tail          ; the earlier events: when a key's job takes
        bne .no_repeat          ; longer than the repeat (scrolling a big
                                ; document), repeats must not pile up and
                                ; carry on after the key is let go
        lda key_mods
        ora #MOD_REPEAT
        tax
        lda key_last
        jsr queue_event
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
        jsr queue_event
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
        jsr queue_event
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
        jsr queue_event
+
        ; Remember this frame's matrix for the next one.
        ldx #7
-       lda key_now,x
        sta key_before,x
        dex
        bpl -
        rts

; queue_event - add an event: A = key code, X = modifiers. Keeps Y.
; If the queue is full the event is dropped. (The mouse uses it too.)
queue_event
        pha
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
!if DEBUG {
        lda #0                  ; (busy with a key, for the test harness)
        sta MB_IDLE
}
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
.none
!if DEBUG {
        lda #1                  ; (waiting for a key: the test harness may
        sta MB_IDLE             ; look - main loop and wait_key only)
}
        sec
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

;============================================================================
; The 1351 mouse (control port 1)
;
; In its normal ("proportional") mode the 1351 tells how far it moved
; through the SID's two paddle inputs, $D419 (X) and $D41A (Y): each counts
; up or down as the mouse moves, and wraps round. Bits 1-6 carry the count;
; bit 0 is noise. The buttons are joystick lines: left = fire ($DC01 bit
; 4), right = up ($DC01 bit 0).
;
; mouse_frame runs once per frame in the housekeeping IRQ, just before the
; keyboard scan: since the last scan, $DC00 has selected port 1 for the
; SID's paddle inputs (bits 6-7 = %01) - far longer than the 512 cycles the
; SID needs for a fresh reading. It works out where the pointer is, whether
; it shows, which border icon it is over, and turns button presses into
; key events (KEY_MOUSE_...) that the editor handles like keys. What goes
; into the VIC is left in ptr_next_... and icon_colors; irq_frame_top puts
; it in at line 10, where nothing is being drawn.
;
; Where the pointer goes (Jim's choice): over the text area only. The
; border strips above and below it are timed to the exact cycle, and the
; pointer sprite's fetches there would upset that. Moved on past the text,
; the pointer hides and the border icon under it turns white instead; a
; click then works that icon.
;
; The VIC fetches all 21 rows of a sprite from its top line, even blank
; ones, stealing CPU cycles at the end of each of those lines. For the
; pointer those lines must stay within 52-249: line 50 ends with the top
; color split, line 249 with the bottom stable IRQ's check, and the strips
; beyond are exact-timed. So the box's top line stays within 52-242, and
; from line 229 on the pointer uses a second picture, low in its block, so
; that the fetches run above the box instead of below it.
;
; No mouse, no pointer: it only shows once the paddle values have changed
; (a joystick or an empty port never changes them). After 10 seconds
; without use it hides; using the mouse again shows it, and a click then
; only wakes it up.
;============================================================================
SID_POTX        = $d419
SID_POTY        = $d41a

; Where the pointer's 8 x 8 box may be: its left edge in sprite X
; coordinates, its top as a raster line
MOUSE_X_MIN     = 24            ; over the text area: the first column ...
MOUSE_X_MAX     = 24 + 39*8     ; ... to the last
MOUSE_STRIP_X_MAX = 360         ; in the strips: over the right badges too
MOUSE_Y_MIN     = 30            ; in the top strip
MOUSE_Y_TEXT    = 52            ; the first line it shows on (not 51: see
MOUSE_Y_LAST    = 242           ; above) and the last
MOUSE_Y_MAX     = 255           ; in the bottom strip
MOUSE_Y_LOWPIC  = 229           ; from here on, the picture low in its block
MOUSE_X0        = 24 + 19*8     ; where it starts: the middle of the screen
MOUSE_MAX_STEP  = 28            ; a reading moving this far or more: a bad
                                ; one (pot_delta)
MOUSE_Y0        = 51 + 12*8 + 1

; Which border icon a click was on (click_icon)
ICON_NONE       = 0
ICON_MENU       = 1
ICON_F3         = 2
ICON_F5         = 3

AUTOSCROLL      = 4             ; frames per row when dragging past the text

mouse_on        !byte 0         ; 1 = a mouse was found (its values changed)
mouse_first     !byte 1         ; 1 = nothing read yet
mouse_x         !word MOUSE_X0  ; the box's left edge
mouse_y         !byte MOUSE_Y0  ; the box's top line
mouse_dx        !byte 0         ; this frame's movement (signed: + is to
mouse_dy        !byte 0         ; the right, and down)
mouse_btn       !byte 0         ; buttons now: bit 0 left, bit 1 right
mouse_old_btn   !byte 0         ; ... and last frame
mouse_idle      !word 0         ; frames since the mouse was last used
mouse_idle_max  !word 0         ; 10 seconds (timing table)
mouse_accel     !byte 0         ; acceleration threshold (timing table)
mouse_woke      !byte 0         ; 1 = this frame's use woke a hidden pointer
mouse_ignore    !byte 0         ; 1 = the left button only woke it: ignore
                                ; it until it is let go
mouse_drag      !byte 0         ; 1 = the left button went down in the text
mouse_zone      !byte 0         ; 0 text area, 1 top strip, 2 bottom strip
mouse_sprite    !byte 0         ; the icon sprite under it (1-5), 0 none
drag_timer      !byte 0
pot_x           !byte 0         ; the paddle values last used
pot_y           !byte 0

; For the editor: where the last mouse event happened
click_row       !byte 0         ; text row 0-24; $ff above the text, 25 below
click_col       !byte 0         ; column 0-39
click_icon      !byte 0         ; ICON_...: a click on a border icon

; For irq_frame_top: what goes into the VIC at the top of the next frame
ptr_next_x      !byte <MOUSE_X0
ptr_next_msb    !byte ICON_XMSB | (>MOUSE_X0)
ptr_next_y      !byte MOUSE_Y0 - 1
ptr_next_block  !byte SPR_BLOCK_PTR
ptr_next_on     !byte 0         ; 1 = the pointer shows
icon_colors     !fill 5, LIGHT_BLUE ; sprites 1-5

;----------------------------------------------------------------------------
; mouse_sample - read the paddle values and add how far the mouse moved
; since the last reading to mouse_acc_x / mouse_acc_y. Called three times
; a frame, from IRQs at line 10, in the housekeeping (mouse_frame) and at
; the end of the bottom strip. A reading can only tell 63 steps apart
; either way, and in VICE the 1351 can move more than that in one frame;
; three readings keep each one well inside. (Once a frame is enough for a
; real 1351; more often does no harm. Each reading falls in a different
; 512-cycle SID sample, and none within 512 cycles of the keyboard scan,
; which switches the paddle inputs about.)
;----------------------------------------------------------------------------
mouse_sample
        lda SID_POTX
!if DEBUG {
        sta mouse_raw_x         ; (for the trace)
}
        ldy pot_x
        jsr pot_delta
        sty pot_x
        clc
        adc mouse_acc_x
        sta mouse_acc_x
        lda SID_POTY
!if DEBUG {
        sta mouse_raw_y
}
        ldy pot_y
        jsr pot_delta
        sty pot_y
        clc
        adc mouse_acc_y
        sta mouse_acc_y
        rts

mouse_acc_x     !byte 0         ; movement since mouse_frame last took it
mouse_acc_y     !byte 0         ; (signed; y as the paddle counts it)
!if DEBUG {
mouse_raw_x     !byte 0         ; the last paddle values read
mouse_raw_y     !byte 0
}

;----------------------------------------------------------------------------
; mouse_frame - once per frame, from the housekeeping IRQ (see above)
;----------------------------------------------------------------------------
!zone mouse_frame
mouse_frame
        ; 1. How far it moved, and the buttons.
!if DEBUG {
        jsr mailbox_mouse       ; the test harness moving it instead?
        bcs +
        lda #0                  ; (then the readings count for nothing)
        sta mouse_acc_x
        sta mouse_acc_y
        jmp .have
+
}
        jsr mouse_sample        ; this frame's second reading
        ldx mouse_acc_x         ; the movement of all this frame's readings
        lda #0
        sta mouse_acc_x
        txa
        jsr .accel
        sta mouse_dx
        ldx mouse_acc_y
        lda #0
        sta mouse_acc_y
        txa
        jsr .accel
        eor #$ff                ; (the count goes up as the mouse moves away
        clc                     ; from you: then the pointer goes up)
        adc #1
        sta mouse_dy
        lda mouse_first         ; the very first frame only sets the start:
        beq +                   ; the paddle values as they are now
        lda #0
        sta mouse_first
        sta mouse_dx
        sta mouse_dy
        lda SID_POTX            ; (kept without bits 0 and 7: see pot_delta)
        and #%01111110
        sta pot_x
        lda SID_POTY
        and #%01111110
        sta pot_y
+
!ifdef MOUSE_TRACE {
        ; Trace (-DMOUSE_TRACE=1 builds): the last 64 frames' paddle values
        ; (this reading) and the movement worked out for the frame, 4 bytes
        ; a frame, for the harness.
        ldx mouse_trace_i
        lda mouse_raw_x
        sta mouse_trace,x
        lda mouse_raw_y
        sta mouse_trace+1,x
        lda mouse_dx
        sta mouse_trace+2,x
        lda mouse_dy
        sta mouse_trace+3,x
        inx
        inx
        inx
        inx
        stx mouse_trace_i
}
!ifdef MOUSE_SHOW {
        ; -DMOUSE_SHOW=1 builds, for trying a mouse on real hardware: in the
        ; bottom right corner, in hex, the paddle values X and Y, this
        ; frame's move X and Y, and how many readings were thrown away.
        lda SID_POTX
        ldx #0
        jsr .hex
        lda SID_POTY
        ldx #3
        jsr .hex
        lda mouse_dx
        ldx #6
        jsr .hex
        lda mouse_dy
        ldx #9
        jsr .hex
        lda mouse_rejects
        ldx #12
        jsr .hex
}
        lda mouse_dx            ; moved: so there is a mouse
        ora mouse_dy
        beq +
        lda #1
        sta mouse_on
+       lda #$ff                ; the buttons: port 1's lines, read with no
        sta CIA1_PRA            ; keyboard row selected
        lda CIA1_PRB
        eor #$ff                ; (1 = pressed)
        tax
        ldy #0
        and #%00010000          ; fire line: the left button
        beq +
        ldy #1
+       txa
        and #%00000001          ; up line: the right button
        beq +
        iny
        iny
+       sty mouse_btn
        lda mouse_on            ; no mouse found: nothing more to do (and a
        bne .have               ; joystick's fire button is no click)
        sta mouse_btn
        rts

        ; 2. In use, or idle?
.have   lda #0
        sta mouse_woke
        lda mouse_dx
        ora mouse_dy
        bne .used
        lda mouse_btn
        cmp mouse_old_btn
        bne .used
        jsr .is_idle            ; not used: count up to the limit
        bcs .place
        inc mouse_idle
        bne .place
        inc mouse_idle+1
        jmp .place
.used   jsr .is_idle            ; used: if it was hidden, this only wakes it
        bcc +
        lda #1
        sta mouse_woke
+       lda #0
        sta mouse_idle
        sta mouse_idle+1

        ; 3. The new place.
.place  ldx #0                  ; x = x + dx
        lda mouse_dx
        bpl +
        dex
+       clc
        adc mouse_x
        sta mouse_x
        txa
        adc mouse_x+1
        sta mouse_x+1
        bpl +                   ; below 0: 0
        lda #0
        sta mouse_x
        sta mouse_x+1
+       ldx #0                  ; y = y + dy, within MOUSE_Y_MIN-MOUSE_Y_MAX
        lda mouse_dy
        bpl +
        dex
+       clc
        adc mouse_y
        tay
        txa
        adc #0                  ; the high byte: 0 fine, $ff below 0,
        beq +                   ; 1 past 255
        bmi .y_min
        ldy #MOUSE_Y_MAX
        bne .y_set
+       cpy #MOUSE_Y_MIN
        bcs .y_set
.y_min  ldy #MOUSE_Y_MIN
.y_set  sty mouse_y
        ldx #1                  ; which zone: the top strip, ...
        cpy #MOUSE_Y_TEXT
        bcc +
        ldx #2                  ; ... the bottom strip ...
        cpy #MOUSE_Y_LAST+1
        bcs +
        ldx #0                  ; ... or the text area
+       stx mouse_zone
        cpx #0
        bne .strip_x
        lda mouse_x             ; over the text: from its first column ...
        cmp #<MOUSE_X_MIN
        lda mouse_x+1
        sbc #>MOUSE_X_MIN
        bcs +
        lda #<MOUSE_X_MIN
        sta mouse_x
        lda #>MOUSE_X_MIN
        sta mouse_x+1
+       lda #<MOUSE_X_MAX       ; ... to its last
        cmp mouse_x
        lda #>MOUSE_X_MAX
        sbc mouse_x+1
        bcs .x_ok
        lda #<MOUSE_X_MAX
        sta mouse_x
        lda #>MOUSE_X_MAX
        sta mouse_x+1
        jmp .x_ok
.strip_x
        lda #<MOUSE_STRIP_X_MAX ; in a strip: over the right badges too
        cmp mouse_x
        lda #>MOUSE_STRIP_X_MAX
        sbc mouse_x+1
        bcs .x_ok
        lda #<MOUSE_STRIP_X_MAX
        sta mouse_x
        lda #>MOUSE_STRIP_X_MAX
        sta mouse_x+1
.x_ok

        ; 4. The border icon under it (in a strip): a left badge left of
        ; x = 20, a right badge from x = 340, the menu icon (top) below 60.
        ldy #0
        lda mouse_zone
        beq .set_icon
        ldx #2                  ; top strip: F3 badges, sprites 2 and 3
        cmp #1
        beq +
        ldx #4                  ; bottom strip: F5 badges, sprites 4 and 5
+       lda mouse_x+1
        bne .right_side
        lda mouse_x
        cmp #20
        bcs +
        txa                     ; the left badge
        tay
        bne .set_icon
+       cmp #60                 ; the menu icon (top strip only)
        bcs .set_icon
        cpx #2
        bne .set_icon
        ldy #1
        bne .set_icon
.right_side
        lda mouse_x             ; 256 + 84 = 340 and on: the right badge
        cmp #<340
        bcc .set_icon
        inx
        txa
        tay
.set_icon
        sty mouse_sprite
        ldx #4                  ; the icons light blue, the one under the
        lda #LIGHT_BLUE         ; pointer white (while the mouse is in use)
-       sta icon_colors,x
        dex
        bpl -
        ldx mouse_sprite
        beq +
        jsr .is_idle
        bcs +
        lda #WHITE              ; (white: red hardly showed on the blue
        sta icon_colors-1,x     ; strip - Jim, on a real 1702)
+
        ; 5. The pointer sprite, for the next frame.
        lda #0
        sta ptr_next_on
        lda mouse_zone          ; in a strip: hidden
        bne .events
        jsr .is_idle            ; not used for 10 seconds: hidden
        bcs .events
        lda #1
        sta ptr_next_on
        lda mouse_x
        sta ptr_next_x
        lda mouse_x+1
        and #1
        ora #ICON_XMSB
        sta ptr_next_msb
        ldx #SPR_BLOCK_PTR      ; (a sprite's first row shows on line Y+1)
        lda mouse_y
        cmp #MOUSE_Y_LOWPIC
        bcs +
        sbc #0                  ; picture in rows 0-7: Y = top - 1 (the
        jmp ++                  ; carry is clear: that subtracts 1)
+       ldx #SPR_BLOCK_PTR_LOW  ; picture in rows 13-20: Y = top - 14
        sbc #14                 ; (carry set)
++      sta ptr_next_y
        stx ptr_next_block

        ; 6. The buttons, as events for the editor.
.events lda mouse_btn
        and #1
        beq .left_up
        lda mouse_old_btn
        and #1
        bne .left_held
        lda mouse_woke          ; the left button went down - if it only
        bne .ignore             ; woke the pointer, that is all it does
        jsr .where
        lda #0
        sta mouse_drag
        lda mouse_zone
        beq +                   ; in the text: a click there, and dragging
        lda .icon               ; in a strip: only a click on an icon
        beq .right
        bne ++
+       lda #1
        sta mouse_drag
++      lda #AUTOSCROLL
        sta drag_timer
        lda #KEY_MOUSE_L
        jsr .event
        jmp .right
.ignore lda #1
        sta mouse_ignore
        bne .right
.left_up
        lda #0
        sta mouse_ignore
        sta mouse_drag
        beq .right
.left_held
        lda mouse_ignore        ; held down: dragging? (not after a press
        bne .right              ; that only woke the pointer, nor one on
        lda mouse_drag          ; an icon)
        beq .right
        lda key_q_head          ; only when the editor has taken all the
        cmp key_q_tail          ; events before (so they never pile up)
        bne .right
        jsr .where
        lda mouse_zone
        beq +
        dec drag_timer          ; past the top or bottom of the text: a row
        bne .right              ; every few frames
        lda #AUTOSCROLL
        sta drag_timer
        bne .drag
+       lda .row                ; in the text: when it gets to another cell
        cmp click_row
        bne .drag
        lda .col
        cmp click_col
        beq .right
.drag   lda #KEY_MOUSE_DRAG
        jsr .event

.right  lda mouse_btn           ; the right button went down: the menu
        and #2
        beq .done
        lda mouse_old_btn
        and #2
        bne .done
        lda mouse_woke
        bne .done
        jsr .where
        lda #KEY_MOUSE_R
        jsr .event
.done   lda mouse_btn
        sta mouse_old_btn
        rts

; .is_idle - carry set if the mouse has not been used for 10 seconds
.is_idle
        lda mouse_idle
        cmp mouse_idle_max
        lda mouse_idle+1
        sbc mouse_idle_max+1
        rts

; .accel - A = a movement (signed): doubled when it is fast (but not when
; it is so big already that twice would not fit in a byte)
.accel  sta .a
        lda .a                  ; (the flags as A says)
        bpl +
        eor #$ff                ; the size of a move to the left or up
        clc
        adc #1
+       cmp mouse_accel
        bcc .same               ; slow: as it is
        cmp #64
        bcs .same               ; very big: as it is
        lda .a
        asl                     ; fast: twice as far
        rts
.same   lda .a
        rts
.a      !byte 0

; .where - the cell under the pointer (.row, .col), or the icon (.icon)
.where  lda #ICON_NONE
        sta .icon
        lda mouse_zone
        beq .in_text
        ldx #$ff                ; in a strip: row $ff above the text, 25
        cmp #1                  ; below it
        beq +
        ldx #ROWS
+       stx .row
        ldx mouse_sprite        ; and the icon under it
        lda .sprite_icon,x
        sta .icon
        jmp .column
.in_text
        lda mouse_y             ; the nearest row: (y - 51 + 4) / 8
        sec
        sbc #51-4
        lsr
        lsr
        lsr
        sta .row
.column lda mouse_x             ; the nearest column: (x - 24 + 4) / 8
        sec
        sbc #24-4
        sta .t
        lda mouse_x+1
        sbc #0
        bcs +
        lda #0                  ; (left of the text: column 0)
        sta .t
+       lsr
        ror .t
        lsr
        ror .t
        lsr
        ror .t
        lda .t
        cmp #40
        bcc +
        lda #39                 ; (right of the text: the last column)
+       sta .col
        rts
.sprite_icon
        !byte ICON_NONE, ICON_MENU, ICON_F3, ICON_F3, ICON_F5, ICON_F5

; .event - queue event A for the editor, with the place it happened and
; the modifier keys held now (so the mark key works as with the keys)
.event  pha
        lda .row
        sta click_row
        lda .col
        sta click_col
        lda .icon
        sta click_icon
        pla
        ldx key_mods
        jmp queue_event

.row    !byte 0
.col    !byte 0
.icon   !byte 0
.t      !byte 0
!ifdef MOUSE_TRACE {
mouse_trace_i !byte 0           ; the next slot (counts on in 4s, wraps)
}

!ifdef MOUSE_SHOW {
; .hex (mouse_frame's zone) - A in hex at column 26 + X of the bottom row
.hex    pha
        lsr
        lsr
        lsr
        lsr
        tay
        lda .digits,y
        sta SCREEN+24*40+26,x
        pla
        and #15
        tay
        lda .digits,y
        sta SCREEN+24*40+27,x
        lda #WHITE
        sta COLOR_RAM+24*40+26,x
        sta COLOR_RAM+24*40+27,x
        rts
.digits !scr "0123456789", $01, $02, $03, $04, $05, $06
mouse_rejects   !byte 0         ; readings thrown away (pot_delta)
}

;----------------------------------------------------------------------------
; pot_delta - A = a paddle value now, Y = the value kept from before (see
; below). Returns A = how far the mouse moved, in steps (signed), and Y =
; the value to keep for next time.
;
; The paddle value counts in bits 1-6 (one step = 2) and wraps round; bit 0
; is noise. So bit 0 comes off BOTH values first, and only then are they
; subtracted: the steps of all the readings then add up to exactly where
; the mouse is, whatever the noise did in between. (The 1351 manual's
; method, and ours until phase 12, subtracted first and then halved, and
; that rounds down both ways: +3 counts made 1 step but -3 made -2. Every
; time a reading went off by an odd amount and came back, the pointer lost
; a step the negative way - down the screen, as Jim's real 1351 showed.)
;
; A move of MOUSE_MAX_STEP or more between two readings (a third of a frame
; apart, or less) moves nothing, but the new value is kept: a reading half
; the range away can't tell forwards from backwards. It is a bad reading,
; or a swipe faster than the readings can follow; either way the pointer
; stays put rather than jump the wrong way.
;----------------------------------------------------------------------------
!zone pot_delta
pot_delta
        and #%01111110          ; the new value without its noise bit
        sta .new
        sty .old
        sec
        sbc .old
        and #%01111110
        cmp #%01000000          ; half the range or more: backwards
        bcc +
        ora #%10000000
+       cmp #$80                ; halve it, keeping the sign: the steps,
        ror                     ; -32 to 31
        sta .step
        clc                     ; within -(MOUSE_MAX_STEP-1) to
        adc #MOUSE_MAX_STEP-1   ; MOUSE_MAX_STEP-1?
        cmp #2*MOUSE_MAX_STEP-1
        ldy .new                ; (the new value is kept either way; LDY
        bcs .far                ; leaves the carry alone)
        lda .step               ; yes: a move
        rts
.far
!ifdef MOUSE_SHOW {
        inc mouse_rejects
}
        lda #0                  ; no: no move
        rts
.old    !byte 0
.new    !byte 0
.step   !byte 0

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
;  +36    12    harness     mouse queue: 4 events of 3 bytes, one taken
;                           per frame in place of the real mouse:
;                             dx (signed, + = right), dy (signed, + =
;                             down), both in pixels (no acceleration);
;                             buttons (bit 0 left, bit 1 right)
;                           Once the harness has sent one, the buttons stay
;                           as its last event said (so a drag can be sent
;                           in several goes), and the real mouse is not
;                           read any more.
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
MB_BUSY         = MB_BASE-2      ; 1 while the main loop works on a key (the
                                 ; harness waits before it uses the REU)
MB_IDLE         = MB_BASE-3      ; 1 while waiting for a key (get_key found
                                 ; none: the main loop, or a menu or box)
MB_DMA          = MB_BASE-12     ; an REU copy for the harness (8 bytes,
                                 ; below): as reu_move's reu_c64, reu_addr,
                                 ; reu_bank, reu_len, then its command last
MB_SIZE         = 64

;----------------------------------------------------------------------------
; mailbox_ready - start-up is over (after editor_init): the signature, so
; the harness may start. (Not earlier: on real hardware load_defaults takes
; a moment, and a document the harness put in meanwhile was emptied again
; by editor_init - found on the C64 Ultimate.)
;----------------------------------------------------------------------------
!zone mailbox_ready
mailbox_ready
        ldx #3
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
+       lda MB_DMA+7            ; an REU copy for the harness? (One big DMA
        beq +                   ; from the monitor would hold the exact-
        ldx #6                  ; timed IRQs up; reu_move copies in pieces.)
-       lda MB_DMA,x
        sta reu_c64,x           ; (reu_c64, reu_addr, reu_bank, reu_len
        dex                     ; follow each other)
        bpl -
        lda MB_DMA+7
        jsr reu_move
        lda #0
        sta MB_DMA+7
+       lda MB_MK_GO            ; the harness moves the marker: first line
        beq +                   ; and total lines, 25 lines on the screen
        lda MB_MK_FIRST
        sta mk_first
        clc
        adc #25
        sta mk_last
        lda MB_MK_FIRST+1
        sta mk_first+1
        adc #0
        sta mk_last+1
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
        sta modified
        sta sel_on
        jsr empty_view          ; the top of the screen at the start
        jsr count_colors
        jsr skip_codes          ; (the cursor goes after leading codes)
        jsr redraw_all
        jsr locate_cursor
        jmp cursor_show

;----------------------------------------------------------------------------
; mailbox_mouse - called by mouse_frame: the harness's mouse instead of the
; real one? Carry clear if so, with mouse_dx, mouse_dy and mouse_btn set.
;----------------------------------------------------------------------------
!zone mailbox_mouse
mailbox_mouse
!ifdef SPLIT_TEST {
        sec                     ; (timing test builds: no harness mouse -
        rts                     ; they have no room for it since phase 12)
} else {
        ldx MB_MOUSE_TAIL       ; an event waiting?
        cpx MB_MOUSE_HEAD
        bne .event
        lda .used               ; no: once the harness has used the mouse,
        beq .none               ; it stays still with the buttons as the
        lda #0                  ; last event said
        sta mouse_dx
        sta mouse_dy
        lda .btn
        sta mouse_btn
        clc
        rts
.none   sec                     ; (never used: the real mouse)
        rts
.event  txa                     ; 3 bytes per event
        asl
        adc MB_MOUSE_TAIL
        tay
        lda MB_MOUSE_QUEUE,y
        sta mouse_dx
        lda MB_MOUSE_QUEUE+1,y
        sta mouse_dy
        lda MB_MOUSE_QUEUE+2,y
        sta mouse_btn
        sta .btn
        inx                     ; take it off the queue
        txa
        and #3
        sta MB_MOUSE_TAIL
        lda #1
        sta .used
        sta mouse_on            ; (a mouse is there, as far as we know)
        lda #0
        sta mouse_first
        clc
        rts
.used   !byte 0
.btn    !byte 0

}       ; (end of !ifdef SPLIT_TEST)
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
+       lda key_q_head          ; the program's own queue nearly full (it
        sec                     ; is busy with something long)? Then wait:
        sbc key_q_tail          ; a full queue drops events, and no test
        and #KEY_QUEUE_SIZE-1   ; key may get lost.
        cmp #KEY_QUEUE_SIZE-2
        bcc +
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
