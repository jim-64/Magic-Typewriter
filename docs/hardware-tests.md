# Phase 12: hardware tests

Test whatever you have at hand, in any order; tick items off as you go and tell me what failed.
For each failure: what you did, what you saw (a photo of the screen helps), and on which machine.

**Which build:** `build.bat release` makes `build\magictypewriter.d64` with the release program
(no test mailbox) plus the sample files: `sample`, `upper`, `long` (short ones) and `longdoc`
(60 KB, for REU tests). Copy the .d64 or its files to whatever the machine reads from.

## A. On every machine (about 15 minutes)

- [ ] **Start:** `LOAD"MAGIC TYPEWRITER",8` (or from the machine's own file menu), `RUN`. Blue
      strips top and bottom, F3/F5 badges in the four corners, ≡F1 near the top left, and the
      sides all grey (the page marker fills them while the document is empty). Type a few
      screens of text: the sides turn dark grey with a grey band that moves as you page.
- [ ] **Typing:** both SHIFT keys give capitals; SHIFT LOCK too. INST/DEL, SHIFT+INST/DEL, RETURN.
- [ ] **Cursor:** blinks about 3 times a second; F7 switches underline ↔ block.
- [ ] **Colors:** CTRL-3 then type: red. C= 5 then type: grey. CTRL-9/CTRL-0: reverse on/off.
- [ ] **Character set:** C= + SHIFT switches upper/lower ↔ upper/graphics.
- [ ] **Cursor keys:** all four directions (SHIFT reverses); HOME, HOME.
- [ ] **Marking (C=):** C= + cursor keys mark; C= + SHIFT + CRSR marks up/left; CTRL-C, move,
      CTRL-V pastes. Then menu F → LEFT SHIFT and try left SHIFT + cursor keys, and left SHIFT +
      right SHIFT + CRSR for up/left (put it back to COMMODORE after).
- [ ] **Menu:** F1, RUN/STOP and RESTORE all open it; X backs out; ← closes.
- [ ] **Disk:** load `sample`; save it under a new name as PETSCII and as MAGIC; CLEAR ALL; load
      both back. Disk directory (Load menu D), Disk command (E, e.g. `I`, or empty for the status).
- [ ] **Save defaults:** change the background (G), Save defaults (J), Quit, load and RUN again:
      the background comes back. (Then put it back and save defaults again, or scratch
      `MAGIC T DEFAULTS`.)
- [ ] **Quit:** Q → READY. `PRINT "A"+"B"` prints AB; the cursor and RETURN work normally.

## B. Real C64 (PAL and/or NTSC)

- [ ] **NTSC TV:** are the tips of the top F3 badges visible, or cut off at the top of the picture?
- [ ] **Drives:** whatever you have: 1541, 1571, 1581, SD2IEC, Pi1541. Load and save on each;
      a write-protected disk gives `26, WRITE PROTECT ON`; no disk/no drive gives an error box,
      not a hang.
- [ ] **Fast loaders:** with Epyx FastLoad / JiffyDOS: a magic document loads faster than the same
      document as PETSCII (you measured 18 s → 8 s in VICE).
- [ ] **1351 mouse** (port 1): the pointer appears when you first move it; speed and acceleration
      feel right; up is up; click puts the cursor on the character; drag marks; over a badge the
      badge lights up and a click pages; ≡F1 click and the right button open the menu; it hides
      after 10 s. A joystick in port 1 must do nothing.
- [ ] **If the pointer still creeps or never hides:** run `MOUSETEST` from `build\mousetest.d64`
      (the same program, showing the mouse's numbers in the bottom right corner, in hex: paddle X,
      paddle Y, this frame's move X, move Y, and how many readings were thrown away). Leave the
      mouse still for a minute, then move it slowly; a photo or short video of the numbers tells
      me what the 1351 really sends.
- [ ] **REU** (1764/1750 or a clone): Stats (menu I) shows its size. Load `longdoc`, page to the
      end with F5 (short pauses now and then), HOME HOME, CTRL-F `paragraph 300`, type something
      in the middle, save under a new name, load it back.
- [ ] **Datasette:** set the Save device to TAPE: save as MAGIC and as PETSCII (two files); rewind;
      load each (Load device TAPE, Format MAGIC for the first, PETSCII for the second). RUN/STOP at
      PRESS PLAY gives BREAK and leaves the document alone.
- [ ] **Printer** (device 4–7): Print with Convert to ASCII NO on a Commodore printer (reverse text
      prints reversed, case right), and YES on an ASCII printer or interface.

## C. Commodore 64 Ultimate

- [ ] Section A, started from the Ultimate's own menu as well as with LOAD/RUN. (Started from the
      menu, Save defaults may say DEFAULTS NEED A DISK; that is expected.)
- [ ] Its drives: a disk image, and its SD card/USB folder if you use them.
- [ ] Its REU at several sizes (e.g. 512 KB and 16 MB): Stats shows the right size; the `longdoc`
      test from section B.
- [ ] Left and right SHIFT are told apart (marking with left SHIFT as the mark key).
- [ ] Mouse (if it can act as a 1351), tape (if it has a Datasette or tape emulation).

## D. MEGA65 (C64 core)

- [ ] Section A.
- [ ] Keyboard: left/right SHIFT, C=, CTRL, RUN/STOP, ←, and the cursor keys — especially the
      separate up/left keys (do they arrive as SHIFT + CRSR? does marking up/left work?).
- [ ] REU and 1351 mouse, if the core supports them.

## E. TheC64 Mini / Maxi

- [ ] Section A, started from its menu.
- [ ] Keyboard (the Mini uses a USB keyboard): are left and right SHIFT separate? C= and CTRL keys?
- [ ] Saving SEQ files to its virtual drive (USB stick), and loading them back.
- [ ] Mouse, REU and tape, if it offers them.

## F. CBMSTUFF BlingBox keyboard

- [ ] Left and right SHIFT reported separately; CTRL, C=, RUN/STOP, ←, cursor keys; marking with
      left SHIFT as the mark key in all four directions.
