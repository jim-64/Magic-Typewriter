# Magic Typewriter — Project Handoff

**Magic Typewriter** is a small, modern-feeling text editor for the Commodore 64, written in 6502
assembly with ACME. Use the name in the main menu title and as the PRG/disk name (`MAGIC TYPEWRITER`).

## Status

- **Phase 1 done** (2026-09-27), on branch `main`. Jim chose the side-border badge layout (see Border
  icons). Branch `phase1` keeps the earlier layout (badges above/below the text area) for reference only.
- **Phase 2 done** (2026-09-27), merged into `main`.
- **Phase 3 done** (2026-09-27; Jim tested PAL and NTSC), merged into `main`. Change after his test:
  no more color skipping (see Menus).
- **Phase 4 done** (2026-09-27; Jim tested in VICE), merged into `main`. Fixed after his test: CLEAR ALL
  kept the old file name, so CTRL-S saved over the loaded file; it now starts an unnamed document.
- **Phase 5 done** (2026-09-28; marking, cut/copy/paste, recolor), merged into `main`. Changed after
  Jim's test: the mark key defaults to C=; marking left includes the character the cursor started on.
- **Phase 6 done** (2026-09-28; word wrap, page marker), merged into `main`. Changed after Jim's test:
  with word wrap off, rows are cut at 40 characters (no sideways scrolling); the marker stays all grey
  when the whole document fits. Also in this phase: **the editor runs under the KERNAL ROM** (Jim's
  "plan D"; see Memory Map), Quit fixed (it left BASIC's zero page broken), the character set saved
  with the document, and speed work for big documents (see Text Model, phase 6).
- **Phase 7 done** (2026-09-28; 1351 mouse), merged into `main`. Jim's choices: the pointer stays over
  the text area, and past it the icon under it turns red (the pointer's color); the right button will
  open the menu (phase 8). **Jim tested it in VICE 2.4: works.** In VICE 3.9 on his laptop the grabbed
  mouse only ever moves right/down (a VICE/host problem, see VICE gotchas). **Still to do: test with a
  real 1351 on real hardware** when Jim is home (feel, speed, Y direction).
- **Phase 8 done** (2026-09-29; menus, Stats, Save defaults, disk directory/command, Find), merged
  into `main`. The temporary keys CTRL-L (load) and CTRL-W (wrap) are gone; the menus do both now.
  **Changed after Jim's test:** the directory ended at once (the key that chose it
  reached the KERNAL too); Stats shows the free share in % and no "any key" line; "QUIT MAGIC
  TYPEWRITER", "EXIT MENU"; C= + SHIFT during the directory no longer changes the document's
  character set; the mouse pointer is black on red, purple, orange and brown backgrounds, and a
  border icon under it lights up in the pointer's color (so black there too); a scratch answered
  with 62 counts as fine (that was Jim's Save "FILE NOT FOUND": **VICE 2.4's host-folder drive
  answers 62 to a scratch of a file that isn't there**; confirmed in his 2.4, see VICE gotchas);
  names with `* ? ,` are refused for saving. His "LOAD: NOT READY YET" came from a MAGIC T DEFAULTS on
  his disk with Load Format = MAGIC (and File Type = PRG).
- **Phase 9, first part done** (2026-09-29; REU detection, block copies and the clipboard through
  it), merged into `main`. Changed after Jim's test: with the mark key, F3/F5 put the cursor on the
  top/bottom row. **Long documents held in the REU: after phase 11** (Jim, 2026-09-29; see REU and
  Build Order 11b).
- **Phase 10 done** (2026-09-30; magic, ASCII, PRG files), merged into `main`. Jim: Epyx FastLoad
  loads a PRG document in 8 s against 18 s for the same as SEQ. **SpeedScript skipped** (and its menu
  values removed in phase 12, Jim).
- **Phase 11 done** (2026-09-30; Jim OK'd moving on), merged into `main`:
  room made (the debug mouse trace is now `-DMOUSE_TRACE=1` only; `find.asm` moved under the
  KERNAL); **magic files always PRG** (Jim); a **spinner** in the LOADING/SAVING/PRINTING box (Jim);
  **upper case/graphics** for the disk directory and the LOAD:/SAVE: name boxes (Jim); the **Print
  menu**; **tape** (magic as program files, PETSCII/ASCII as data files — Jim agreed); a File type
  fixed by the format and device shows in [ ] (Jim). Real tape and printer still to try (Jim).
- **Phase 11b done** (2026-10-01; long documents held in an REU of 192 KB or more; Jim tested it
  and is happy), merged into `main`. Also in 11b: the start-up code moved to `src/startup.asm`,
  which runs once from the text buffer (freed ~900 bytes in the lower part; **Jim: "good idea"**),
  and a 1581 fix for PRG loading (see Formats).
- **Phase 12 started** (2026-10-01), branch `phase12`: the release build checked in VICE on all
  four video systems with 0/128/512 KB REUs (`tools/test_release.py`). (Exomizer came later, see
  below.)
  The hardware tests are Jim's: **`docs/hardware-tests.md`** is his checklist (a common part for
  every machine, then one section per target). **`README.md`** is the user manual (keys, menus,
  files, REU, the VICE notes about Tab = C= and the left SHIFT mark key, SHIFT LOCK, building).
  Fixed: Stats showed a 16 MB REU as 16320 KB (255 banks); it shows 16384 KB now.
  **The manual on the disk** (Jim: a Magic Typewriter file with colors and reverse): source
  `docs/manual.txt` (one line per paragraph, tags `{red}`, `{rvs}`, `{off}`, `@banner`…),
  `python tools/make_manual.py` writes `test/manual.prg` (magic, PRG, $4000; header = the built-in
  defaults); the build scripts now put `test/*.prg` on the .d64 as PRG files (first, so MANUAL
  follows the program) and `test/*.seq` as SEQ. `tools/test_manual.py` loads it and checks text,
  settings and banner, and writes a screenshot (`build/test/manual.png`).
  **Jim's view of the formats:** magic is the *project* file, PETSCII the *deliverable*. JiffyDOS
  speeds up SEQ reading too, so the PRG advantage is mainly for LOAD-only fast loaders (Epyx).
  **Jim will publish GitHub releases** with the .d64 (release build), so users need no ACME.
  **Version 0.1** (2026-10-01): an early release for friends to review before a public one. The
  version shows in the main menu's title (`t_main` in menu.asm, "MAGIC TYPEWRITER V0.1") and in
  the manual (`docs/manual.txt`, then `python tools/make_manual.py`): change both for a release.
  **Version 0.2** (2026-10-10): Jim had sent v0.1 to friends, so the changes below (from the
  2026-10-07/09 block on) go out as 0.2: "MAGIC TYPEWRITER V0.2" and the manual's version line.
  **C64 Ultimate:** 192.168.1.64, firmware 1.1.0, core 1.49, **NTSC**. `.mcp.json` has
  `C64U_HOST` (the bridge keeps VICE as its starting backend; `c64_select_backend` switches;
  needs a Claude Code restart). Its REST API works directly too: `POST /v1/runners:run_prg`
  (body = the PRG), `GET /v1/machine:readmem?address=XXXX&length=N`. The debug build runs there
  (first try 2026-10-01): mailbox signature, NTSC, 59.6 frames/s, `late_irqs` 0, housekeeping to
  line 70, bottom strip to line 6 (as in VICE). Its REU was off; don't change Jim's C64U settings
  without asking.
  **Tests on the C64U:** `MT_TARGET=c64u python tools/test_phase3.py ntsc` (also `MT_C64U=<ip>`):
  `tools/ultimate.py` stands in for vicemon's `start_vice`/`Mon` (reset, write the PRG into memory,
  type RUN into the keyboard buffer; memory by REST while the C64 runs). Only tests without disk
  images or VICE options. **test_phase3, test_phase5 and test_phase6 pass on it** (2026-10-01,
  NTSC; 30 KB: jump to the end 25 frames, F3 near the end 28, as in VICE).
  On the Ultimate the C64 runs on while the harness reads, so `mtest.keys` there also waits until
  the program is waiting for a key again: debug builds set **`MB_IDLE`** ($02BD) in `get_key` (1
  when it finds no key — only the main loop and `wait_key` call it — 0 when it hands one out).
  Not in VICE (the CPU stands still while reading, and a tape's PRESS PLAY wait would block).
  **The mailbox no longer feeds keys into a nearly full key queue** (`mailbox_keys`): during a
  long step (a long document's window move, ~80 frames) queued test keys filled the editor's
  16-event queue and the rest were dropped, so `keys()` waited for keys that never came (a rare
  test_phase11b failure on PAL). A stress run of 960 F5/F3 through 124 KB found no loss since.
  (A real keyboard still drops past 16 events typed ahead, like the KERNAL's 10.)
  **Never upload to the Ultimate** (POST with a body: `runners:run_prg`, `writemem` with data
  attached): firmware 1.1.0 keeps every upload as a file in its `/Temp` RAM area, and once that is
  full every upload fails with "Cannot open file". A first version of ultimate.py filled it
  (~330 files); deleting them was refused here, so Jim power-cycles the Ultimate to empty it.
  Writes go as hex in the request instead (`PUT …machine:writemem?address=…&data=<hex>`, 128
  bytes a time), which makes no file.
  **Found on the C64U — a missed strip IRQ crashed the editor.** The Ultimate's network memory
  access holds the CPU up (as does its menu button, or a freezer cartridge); when the line 25
  (247) IRQ then came after line 27 (249) had begun, the second IRQ fired a frame later with a
  stale `saved_sp` and the program died. Now the NOP wait ends in **`irq_missed`** (irq.asm):
  the chain starts again at line 10 next frame (one frame without strips or keyboard scan), and
  debug builds count it in `missed_irqs`. `tools/test_freeze.py ntsc` holds the CPU up 40 times
  with 32 KB REU copies started from VICE's monitor: the old code hung, the new one types on.
  (On VICE's PAL models those copies never seem to hold the CPU up — no IRQ is ever late — so
  that test only means something on NTSC/old NTSC.)
  **Found on the C64U — the harness started too early:** the mailbox signature came from
  mailbox_init, before load_defaults (slow on real drives) and editor_init, which then emptied a
  document the test had put in. The signature is now written by `mailbox_ready` after
  editor_init (start_done in main.asm).
  Jim turned down a multiple-choice question box (2026-10-01): ask in plain text instead.
  **Jim's first real-hardware test (2026-10-02; real C64, NTSC 1702, real 1351, SD2IEC, a Star
  Gemini printer):** printing to the Commodore printer works; marking with the mouse and the left
  SHIFT mark key work. Changed after it:
  - **Mouse:** the pointer slid down the screen and never hid (10 s). First fix: a reading that
    jumps 28 steps or more (`MOUSE_MAX_STEP`) moves nothing but its value is kept. Jim's second
    test (2026-10-03): it hides after 10 s now, but **still drifts**. **The real cause (found
    then): `pot_delta` subtracted, then halved (the 1351 manual's method), and halving rounds
    down both ways** — +3 counts made 1 step, −3 made −2 — so every reading that went off by an
    odd amount and came back cost a step the negative way (down the screen, Y being turned
    round), three times a frame. Second fix: bit 0 off both values before subtracting. Jim's
    third test (2026-10-03): **no more drift, but the pointer twitched** when the mouse rested
    (his 1351 wobbles a count *either way*, so on an odd count bits 1-6 flip), and **now and
    then it jumped ~7 rows** (a reading way off, just inside the 28-step limit, counted as a
    move, ×2 by the speed-up = 54 pixels; MOUSETEST: the thrown-away count rose only while the
    mouse moved: `00` at rest, `11` after moving it about). **Third fix (as built):** the
    **middle of the last three readings** is used (a single reading way off, of any size, is
    never used; one reading of delay), compared with **`pot_k`, where the pointer last
    settled: within `MOUSE_STILL` (3) counts = noise, no move** (Jim asked to ignore moves
    under 2 pixels); a move takes whole steps and `pot_k` moves exactly as many, the count left
    over staying for next time, so the steps still add up to where the mouse is. After the
    mouse stops, the wobble may nudge the pointer over the threshold once (a single settling
    move), never back and forth. Its working bytes are in BASIC's input buffer (see Memory
    Map). It costs ~270 cycles more a reading: the bottom strip IRQ now ends at line 273 (PAL)
    / 10 (NTSC) / 11 (old NTSC), housekeeping by line 76; `late_irqs` and `missed_irqs` 0 on all
    four systems. `tools/test_mouse_delta.py` runs the assembled code on made-up readings like
    Jim's, beside models of the two older methods. **`-DMOUSE_SHOW=1`** builds show the paddle
    values, the frame's move and how many readings the middle-of-three threw away for being 8
    steps or more off (hex, bottom right); `build/mousetest.d64` has one for Jim.
    **Jim, real 1351 on his NTSC C64 (2026-10-03): "It works really good now!"** — it stays
    still and hides after 10 s, no jumps, and the 2-pixel steps on slow moves feel fine ("helps
    snap to the character outline"). MOUSETEST showed `d6`: 214 readings way off set aside in
    one session, so his 1351 really does send them while it moves. **Mouse: done.**
  - **Jim, 2026-10-11: the mouse no longer worked in VICE 3.8** — the pointer ran into the
    bottom right corner and stuck on the F5 badge. Cause: the third fix above. `pot_k` (where
    the pointer settled) is the middle reading of the one before, so the newest reading is two
    readings' worth of movement away from it; past 64 counts that wraps round and the move
    comes out the wrong way. That happens above 15 steps a reading, and **VICE's 1351 moves up
    to 63 counts (31 steps) a reading** (its `mouse.c`: one count per host mouse unit, capped
    at 63 per POT read), so in VICE the pointer went the wrong way all the time. A real 1351
    is far slower, so Jim's hardware test was fine. **Fourth fix (as built, `pot_delta`):** the
    other two of the last three readings are measured from the **middle one in time**, so even
    VICE's fastest moves stay inside the 63. If either is **`MOUSE_FAR` (48 counts) or more**
    from it, a reading is way off (or VICE moves faster than that): no move, and `pot_c` takes
    up the newest reading. Otherwise the middle one in value is used, as before. How far it is
    from the reading used last time (`pot_c`) goes into **`pot_rest`**, the counts not moved
    yet; the `MOUSE_STILL` dead band works on that, and moves are rounded towards 0 (rounding
    down made the pointer twitch now and then at rest). Checked in test_mouse_delta: never
    the wrong way at any VICE speed (the third fix: wrong 22–88 times a run). With readings way
    off it loses the move of a reading or two each time. At a real 1351's speeds (1–6 steps a
    reading) it makes fewer and smaller wrong-way moves than the third fix over 30 runs. Known
    weakness: at a fling of 10 steps a reading, a reading way off in the middle can look like
    one of VICE's fast moves. Cost: 2 bytes (seven mouse variables moved into the free part of
    BASIC's input buffer to make room) and ~42 cycles a reading: the bottom strip IRQ ends at
    line 274 (PAL, Drean) / 11 (NTSC) / 12 (old NTSC) with the mouse still, about a line later
    while it moves; `late_irqs`/`missed_irqs` 0 on all four. **Recorded in VICE 3.7 (Jim's
    hand, every reading logged): it follows left, up, right and down exactly** (2 counts a
    step, nothing lost, nothing the wrong way; readings up to 44 counts apart, past the 30 the
    third fix could take). **But VICE 3.8 still sticks in the bottom right corner — with the
    old build too: 3.8 (and 3.9) on Jim's laptop only ever count right/down** (see VICE
    gotchas), so that was never ours to fix. **Still to do: Jim tries it on his real 1351**
    (the feel at rest and on slow moves should be as before).
  **Merged into `main` and pushed (2026-10-03), still v0.1** (Jim: no GitHub release was made yet,
  so the version stays). Work goes on on branch `phase12`.
  **Jim, 2026-10-07:**
  - **SHIFT + F7 switches word wrap** (it stepped the background before; the background is now
    only in the menu, G): `toggle_wrap` in editor.asm, redrawing as the menus do when they close
    (`top_known` = 0, `show_cursor_at cur_row`); it doesn't set `modified` (the menu doesn't
    either).
  - **SHIFT + F1 = a color key for the next color** (Jim: "similar to pressing CTRL-3"; a first
    version stepped the *default* text color, which recolored all text without codes — not what
    he wanted): `cur_color` + 1 (round all 16, in color-key order) goes through editor_key's
    `.color`, so it does exactly what that color's key does — the code at the cursor and a
    restore code after it, or with text marked a recolor; one CTRL-Z action per press.
  - **`color_key` takes out a color code right in front of the cursor** before putting in the
    new one (it would have no effect after it): pressing SHIFT + F1 five times, or two color
    keys, used to leave a row of unused codes before the typed text (cleanup only tidies the
    cursor's place when the cursor moves, not when typing follows). If that code colored the
    text after the cursor, the restore code put after the cursor keeps it so
    (`AB[red]HELLO`, CTRL-2 after AB, type X → `AB[white]X[red]HELLO`).
  - **The release disk: the program packed with Exomizer, and only the manual** as an example
    file. `build.bat release` / `./build.sh release`: Exomizer (`exomizer sfx sys -x1`: a BASIC
    SYS line, the border flashing while it unpacks) writes `build/magictypewriter-packed.prg`,
    which goes on the disk as MAGIC TYPEWRITER; without Exomizer on the PATH the unpacked one
    goes on, with a message. 25,458 → 16,090 bytes (101 → 64 blocks). The debug build's disk
    keeps the program unpacked and all the test files (the tests need them). **The unpacker
    (3.1.2, from its own report):** zero page $9E, $9F, $A7, $A8, $AE, $AF, $FD–$FF only, its
    code in the stack page, its table in the tape buffer ($0334–$03D0); $01 = $37 and IRQs on
    throughout; then JMP $080D as RUN would. So **$BA (the load device) and BASIC's zero page
    ($02–$1B, put back on Quit) are untouched** — `tools/test_packed.py` checks both. It is an
    ordinary BASIC program, so it loads from tape too (Jim asked).
  **Merged into `main` and pushed again (2026-10-07; Jim on SHIFT + F1/F7: "works well"), still
  v0.1.** `build/magictypewriter-release.d64` (a copy of the release disk, not in git) is what Jim
  attaches to the GitHub pre-release, which he makes himself. When a session ends, everything is
  committed and `main` = `phase12`.
  **Next (phase 12 goes on; start a new branch from `main`):** Jim's v0.1 pre-release for
  friends; the rest of `docs/hardware-tests.md` — real floppy drives (1541, 1571, 1581; so far
  only the SD2IEC), the Datasette (documents, and the packed program itself from tape), the C64
  Ultimate (Claude can drive it over the network, see above; Jim turns it on), the MEGA65,
  TheC64 and the BlingBox keyboard if he has them at hand.
  **If room runs out:** Jim offered (2026-10-07) that the clean Quit could go — "many programs
  you had to just power off" — which would free its code and the 26-byte copy of BASIC's zero
  page. Not needed so far (see Space under Memory Map).
  - **Badges and menu icon redrawn** (cut off on the 1702). Jim chose from VICE mockups
    (scratch builds, one PRG per design on a .d64 for his TV): **solid shapes with the letters
    cut out** — the F3/F5 badges an arrow ("SB3C"), ≡F1 a box with a pixel off each corner
    ("M1"); 9 rows on lines 41–49 and 252–260; the badges' widest rows touch the text area
    (X = 2 and 342). A badge under the pointer lights up **white** (red hardly showed on blue).
    (All redrawn again on 2026-10-08, see below.)
  - **SpeedScript** gone from the Format values.
  - **SHIFT + F3 / F5:** top / end of the document.
  - **The main menu lists the CTRL keys** at its foot (rows 19–22; the panel is now rows 4–23; v0.2: rows 16–23 with the function keys, the panel rows 0–24).
  - **SD2IEC opens a PRG as SEQ** (no "64, FILE TYPE MISMATCH"), so the manual showed its load
    address and header as text (`@mtw1m@oaa...`). `convert_start` now skips a leading $00 $40 when
    our header or a case code follows. And **VICE's file system drive answers "62, FILE NOT FOUND"**
    to a SEQ open of a PRG (it looks for SEQ only), so load_file tries the PRG way after 62 too
    (before: only after 64, so magic files couldn't load from VICE 2.4's host folder drive).
    Note VICE 3.9's file system drive shows host files with their extension (`MANUAL.PRG`).
  - **CTRL-Z: one undo** (Jim: "giving up 1k for undo seems worth it"; mostly for cuts and
    typing over marked text). See "Undo (CTRL-Z)" under Text Model. No redo, and CLEAR ALL
    can't be undone (Jim, to keep it small).
  - **Room for it (Jim chose option A): only this video system's border code is kept.** The
    four copies of the exact-timed strip code (`border_top_*` / `border_bot_*`, ~870 bytes) are
    assembled to run at `border_code` (in the run-time tables, after `prompt_save`) and stored in
    `startup.asm`; `copy_border` puts this system's there at start-up. Saved ~650 bytes. Checked:
    the SPLIT_TEST build gives both compare results on all four systems, and BORDER_TEST pictures
    show every strip line's side border open on all four. (SPLIT_TEST builds leave out
    `mailbox_mouse`, which they don't need, to fit.)
  **Jim, 2026-10-07/09 (branch `badges`, merged into `main` and pushed 2026-10-09; the Load format MAGIC change after it is on branch `fastload`):**
  - **Badges and menu icon redrawn again.** Jim drew them on a grid in three rounds. Each round
    got a test disk with every version, for his 1702, made from throwaway builds with `main` left
    alone. Chosen:
    - All three icons are 7 rows: ≡F1 and F3 on lines 43–49, F5 on 252–258.
    - The F3/F5 badges are the flat end of an arrow with the letters cut out, their wide side
      facing the text area.
    - The badges sit **2 pixels out from the text area** (X = 1 and 346). He compared touching,
      1 pixel and 2 pixels.

    See Border icons.
  - **Pointer colors:** light green or green, by background (Jim's list, `pointer_colors`), and
    **a badge under the pointer lights up in the pointer's color** (it was white). test_phase7
    checks all 16 backgrounds, the badge and the pointer sprite alike.
  - Tried and dropped: letting the character show through the insert cursor (see Cursor), and
    hanging a space in the margin for word wrap (see Text Model).
  - Space: the lower part grew 4 bytes (debug tables end $3E6C, 20 bytes free).
  - **RETURN in reversed text keeps the rest of the line reversed** (an RVS ON after the new line
    end; see Colors and Reverse). 28 bytes: **7 bytes are left under the KERNAL.** Jim: "works
    good" (2026-10-09).
  - **Menu colors by background** (Jim, 2026-10-09): a fixed 16-entry table, `box_colors` (see
    Menus). That saved 8 bytes in the lower part (debug tables end $3E64, 28 bytes free).
  - **Load format MAGIC goes straight to the PRG way** (Jim's idea): fast loaders now speed up
    magic files on an SD2IEC too (see Formats, as built). 7 bytes.
  - **Mouse speed:** VICE feels too fast and a real 1351 on Jim's C64 a little slow. There is no
    reliable way for the program to tell VICE from a real C64, and VICE's speed depends on the
    PC's mouse anyway. **Jim: keep the speed as it is, a good compromise.** A speed setting in
    the menu would be the way if it comes up again (needs room).
  **Jim, 2026-10-10 - version 0.2 (branch `v0.2`, after `fastload`):**
  - **Stats:** "BYTES FREE" (was "FREE").
  - **The main menu lists the CTRL keys and the function keys** at its foot (Jim's "option A":
    two blocks of two columns, 8 rows). For the room, **the menu panel fills the screen**: rows
    0-24 for every menu (`MENU_TOP` 0, `MENU_ROWS` 25). The lines are one string after another
    in `t_keys` (no pointer table). Three columns side by side, Jim's first idea, would have
    needed ~49 columns.
  - **Quit resets the C64** (`jmp ($fffc)` with the ROMs in): it ends at the power-up screen.
    That replaced the step-by-step restore (restore_irq, restore_keyboard, the copy of BASIC's
    zero page) and freed ~125 bytes. Jim had offered to drop the clean Quit for room.
  - **The Load format starts as MAGIC**, and with it any file loads (Jim's rules): one of ours
    ($4000) the fast way; a PRG with another address as PETSCII text whose first 2 characters
    are those bytes; a SEQ file (the drive refuses the PRG open: 64, or 62 from VICE's folder
    drive) opened as SEQ. A file without the magic header sets the Save format to PETSCII, so a
    BBS file is saved back plain; the Save menu's Format can make it magic. See Formats.
  - **Room:** `name_buf` and `num_text` moved into BASIC's input buffer ($0238-$0258), and the
    run-time tables now put `border_code` right after `ctype`/`scrcode`: there it starts where
    the lower part ends in its page, so its page-bound loops need no padding (240 -> 218
    bytes). The tables after it are defined below `!source "src/startup.asm"` in main.asm,
    where BORDER_SIZE is known (the size check `!if` needs it in ACME's first pass).
  - **Where it stands (2026-10-11):** v0.2 is committed on branch `v0.2` (which has `fastload`
    under it); the whole test suite passes. **Waiting for Jim's real-hardware test** of
    `build\magic-typewriter-v0.2.d64` (packed release disk; also the file for the GitHub
    release): the menu with the key list, BYTES FREE, the Load format MAGIC loading a plain SEQ
    file whole (SD2IEC, and a 1541/1581 if at hand), Quit resetting. **Then:** merge `v0.2` into
    `main`, push, and Jim makes the v0.2 release on GitHub with that disk. (v0.1 was never
    released on GitHub; Jim sent it to friends.)

## Working with Jim

- Jim programs BASIC and 6502 assembly on real Commodore hardware for fun. He knows the C64 well.
- He is **not** experienced with modern tooling (git, shells, package managers, VS Code). When a step
  needs those, give exact commands and explain what they do in plain terms.
- He will read and learn from the source. Favor clear, well-commented, standard 6502 over clever tricks.
  No undocumented opcodes. Keep macros few and simple.
- Build and test one phase at a time (see Build Order). Ask before large structural changes.
- Jim develops mainly on **Windows**, and also uses laptops running **Ubuntu**. Provide `build.bat` for
  Windows and an equivalent `build.sh` for Linux. Keep them doing the same steps.

## Development Workflow (Claude Code + C64 Bridge + VICE)

Claude Code builds, runs, and tests the editor in **VICE** through the **C64 Bridge** MCP server, and only
stops for Jim when a question or human test is needed.

**Develop on VICE only for now.** Testing on the C64 Ultimate and the other targets waits until we have a
working program (Build Order phase 12). C64 Bridge can drive the Ultimate too, so we'll add that setup then.

### Loop for each phase

1. Assemble with ACME (with `--vicelabels`, see Toolchain); build a `.d64` with c1541 (include the test
   files from `test/`).
2. Run the PRG in VICE with `c64_program` → `run_prg` (host path, plus `symbolsFile` for the labels).
   For file I/O phases, attach the `.d64` first with `c64_disk` → `mount`.
3. Drive the editor with injected input (see below), then check results by reading memory
   (screen RAM $0400, color RAM $D800, buffer, state variables) and with screenshots at milestones
   (not after every change). `capture_frame` only returns raw pixels; use a throwaway VICE with
   `-exitscreenshot` instead (see VICE gotchas).
4. Repeat in **PAL, NTSC, old NTSC, and Drean**, and with REU on/off (see C64 Bridge section).
5. When the phase passes automated checks, stop and hand Jim a **Human Test** (below).

### Input injection gotcha

The editor uses its own keyboard matrix scanner, so VICE's "feed keyboard buffer" (which fills the
KERNAL buffer at $0277) **will not reach it**. This is exactly what C64 Bridge's `c64_input` → `key` /
`write_text` use on VICE (Binary Monitor "Keyboard Feed"), so those only help at the READY prompt,
before the editor starts. In debug builds (`DEBUG=1`), include a small **test mailbox**
at a fixed RAM address: a queue of fake key events (matrix row/column + modifier flags) and fake mouse
events that the scanner and mouse driver read before the hardware. Claude writes events into it with
`c64_memory` → `write`. The mailbox is also the only way to test the mouse, since the MCP can't move
VICE's emulated 1351. Release builds leave the mailbox out entirely.
The mailbox lives at **$02C0–$02FE** (unused KERNAL RAM); its layout is documented in
`src/input.asm`. It also reports the frame counter, detected system, and page-marker results, and lets
Claude move the page marker (write first/total lines, then 1 to `+12`; the band shows 25 lines). Since
phase 6 the editor sets the marker after every redraw, so a harness setting lasts until the next key.

### Test builds

Extra ACME `-D` options for Claude's automated checks (never in Jim's builds):

| Option | What it does |
|---|---|
| `-DDEBUG=1` / `0` | Debug build with the test mailbox (default, and what VS64 builds) / release build |
| `-DSPLIT_TEST=1` | Records whether each stable-raster compare saw the old or the next line; shows the flags as four white/black blocks on row 10. Also varies the main loop's length so every IRQ jitter case happens. The right wait count is the only one that gives both results. |
| `-DBORDER_TEST=1` | Strip background green instead of blue, so a debug-borders screenshot shows which side-border lines are open |
| `-DQUIT_TEST=1` | Quits to BASIC by itself after 256 frames (tests the restore path) |
| `-DTOP_PAL_CMP=n` etc. | Override any stable-raster wait count (list and method at the top of `src/irq.asm`) |

## C64 Bridge MCP (VICE)

- Server: **c64bridge 1.0.2** (latest as of 2026-09-25; the old Meshtastic project used 0.9.2).
  Reference: https://github.com/chrisgleissner/c64bridge
- Config: `.mcp.json` in the project root. It starts in VICE mode (`C64_MODE=vice`) with a visible VICE
  window. C64 Bridge starts `x64sc` itself the first time a tool needs it and talks to it over the
  **VICE Binary Monitor on 127.0.0.1:6502**.
- Updating: check the newest version with `npm view c64bridge version`, then change the version in
  `.mcp.json` and restart Claude Code. Pinning a version keeps the setup from changing under us.
- Needs Node.js (`npx`), which is installed.

### Tools we use (VICE)

| Tool | Operations |
|---|---|
| `c64_program` | `run_prg` (host path + optional `symbolsFile`) |
| `c64_memory` | `read`, `write`, `fill_memory`, `search_memory`, `compare_memory`, `disassemble`, `read_screen`, `wait_for_text` |
| `c64_graphics` | `capture_frame` (screenshots), `get_display_state` (VIC-II/CIA2 setup) |
| `c64_debug` | checkpoints (breakpoints), `get_registers`, `set_registers`, `step`, `step_return`, `continue_execution`, `wait_for_state`, `nuclear_reset` |
| `c64_disk` / `c64_drive` | `list_drives`, `mount`, `unmount`; `set_mode` (1541/1571/1581), `reset` |
| `c64_system` | `reset`, `power_cycle` |
| `c64_vice` | `resource_get`, `resource_set` |
| `c64_rag` | `asm` — 6502 reference lookups |

Check `c64://platform/status` if a tool reports `unsupported_platform`.

### VICE gotchas

- **One Binary Monitor client at a time.** VS64's "Launch Vice" / "Attach Vice" debugger also uses port
  6502. Don't run VS64's VICE debugger while Claude is testing.
- **No `c64_system` pause/resume on VICE.** To stop the CPU, set a checkpoint with `c64_debug`; resume
  with `continue_execution`.
- **`read_screen` converts screen codes to ASCII with a fixed table** and ignores the active charset, so
  letter case comes out inverted in upper/lower mode (our default). Check exact characters with
  `c64_memory` → `read` at $0400 instead.
- **`c64_vice` → `resource_set` only accepts names starting with** `C64`, `Machine`, `Sid`, `VIC`,
  `VICII`, `CIA`, `Joy`, `Sound`.
  - PAL/NTSC: `MachineVideoStandard` is allowed (verify the values in VICE; reset after changing).
  - 1351 mouse in port 1: `JoyPort1Device` is allowed.
  - **REU can't be switched this way** (`REU` is not an allowed prefix). Our own harness does it
    instead (phase 9): `start_vice(..., extra=["-reu", "-reusize", "512"])`, or set **`MT_REU=512`**
    in the environment to give every test run an REU of that size.
- **Disk drive names:** run `c64_disk` → `list_drives` to see what `mount` expects for drive 8. On the
  Ultimate it was `"a"`, not `"drive8"`.
- **Use full paths** in PowerShell build commands and MCP calls. The project path contains spaces, so
  quote it.
- **Mouse buttons at the hardware level:** `c64_input` → `joystick` on VICE is meant to use the Binary
  Monitor joyport command, and the 1351 buttons share the port 1 fire/up lines. **Tried in phase 2: it
  had no effect** — $DC01 stayed $FF with fire+up "pressed" on port 1 (JoyPort1Device = 1, joystick).
  So port 1 input (Mouse Gotcha 2) can only be checked by Jim for now (VICE keyset joystick on port 1).
- **Switch PAL/NTSC with `VICIIModel`, not `MachineVideoStandard`.** Setting `MachineVideoStandard`
  back to 1 left VICE on the old NTSC chip. `VICIIModel` values: 0 = 6569 PAL, **1 = 8565 PAL (VICE's
  default here)**, 2 = 6569R1 old PAL, 3 = 6567 NTSC, **4 = 8562 NTSC**, 5 = 6567R56A old NTSC,
  6 = 6572 PAL-N (Drean). The mailbox's system byte (+6) confirms what the program detected.
- **After changing the VIC model, `c64_system` → `reset` (sometimes twice) before `run_prg`**, and check
  the mailbox signature. Otherwise VICE's pending reset cold-starts BASIC after the load, which zeroes
  $0801–$0802, and RUN does nothing.
- **The CPU mostly runs only between MCP calls' monitor sessions**, so frame counts advance slowly while
  Claude polls. Give injected key events time: read the mailbox again rather than assuming they are done.
- **Watchpoints:** since 1.0.1, checkpoints honor the exact load/store/exec mask requested, so a
  store-only watchpoint on a state variable works.
- **VICE's 1351 moves up to 63 counts between two POT reads** (`src/joyport/mouse.c`,
  `MOUSE_MAX_DIFF`; one count per host mouse unit, so ~30–60 counts per reading of ours at a
  normal hand speed). Read by `pot_delta` since 2026-10-11 (see the phase 12 status).
- **VICE's 1351 (from its source, phase 7):** POTX/POTY = `(counter AND $7F) + $40`, plus a random 0/1;
  the counter only moves when the program reads a POT register (`mouse_poll()` is called then, at most
  once per 512 cycles), walking toward the host mouse position. A read within 512 cycles of a change of
  $DC00 bits 6-7 returns a random value. Start VICE with `-controlport1device 3` for a 1351 in port 1.
- **VICE 3.9 (GTK) on Jim's laptop: the grabbed mouse only ever moves right/down**, fast, whatever the
  real direction (seen in recordings of the paddle values; the Windows "high DPI" compatibility setting
  did not help). **VICE 2.4 works** (Jim still likes 2.4's menus). Test the mouse in 2.4, on his desktop
  PC, or on real hardware.
  **2026-10-11, same laptop (the PC Claude runs on):** VICE 3.8 (`G:\My Drive\retro computers
  2\VICE 3.8`, Jim's Start menu VICE) does it too — a recording of every raw paddle reading
  (a throwaway release build logging them to $CB00, polled through the binary monitor) showed X
  only ever counting up and Y only down, ~3:1, whatever way Jim moved: the pointer sticks in the
  bottom right corner (F5 badge lit). **VICE 3.7 works** (same folder, `VICE 3.7`); VICE 3.3's
  mouse doesn't grab at all; 2.4 works. Our automated tests use VICE 3.9 and never the host
  mouse (the mailbox), so they can't see this.
- **Checkpoints were unreliable in phase 1:** after `create_checkpoint` the CPU stayed stopped in the
  monitor (`wait_for_state` timed out), and after a hit the Binary Monitor connection dropped and
  `nuclear_reset` left the old `x64sc` holding port 6502 (had to stop that process by hand). Memory reads
  and writes and `run_prg` work well. `get_registers` does report raster `LIN`/`CYC`.
- **`capture_frame` returns raw pixels only**, which is too big to read. For pictures, run a separate
  throwaway VICE: `x64sc -config <scratch vicerc> -model c64|ntsc|oldntsc|drean -VICIIborders 2
  -warp -autostart <prg> -limitcycles 8000000 -exitscreenshot out.png` (borders mode 2 shows the whole
  raster including blanking; 0 is the normal view). Use a scratch `-config` file so Jim's own VICE
  settings are never changed.
- **Pictures of a state set up through the monitor:** the binary monitor's "display get" (0x84) returns
  an **all-black buffer while VICE runs at warp speed or with `-VICIIborders 2`**. Without warp and
  in the normal border mode it works (scratch `grab.py` wrote it to a PNG). For debug-border pictures,
  start VICE with `-exitscreenshot out.png`, set things up through the monitor, then quit (0xbb): the
  picture is written at exit — one VICE run per picture (phase 7's pointer/strip check did this).

### VICE 2.4 (Jim's favorite; `G:\My Drive\retro computers 2\vice 2.4\x64sc.exe`)

- Jim's 2.4 settings (its `vice.ini`, read only): **AutostartPrgMode=0, DriveTrueEmulation=0,
  VirtualDevices=1** — autostarting a PRG makes **drive 8 the PRG's folder** (VICE's file system
  device), not a disk image. The test files are not there (they are only on the .d64).
- That folder drive answers **"62, FILE NOT FOUND" to scratching a missing file** (VICE 3.9's
  answers 01). Found in Jim's phase 8 test; `scratch_input` accepts it.
- No binary monitor in 2.4, but a throwaway instance can be driven: start it with `-config
  <empty scratch file> -autostartprgmode 0 -virtualdev +truedrive -remotemonitor
  -remotemonitoraddress ip4://127.0.0.1:6511 -autostart <prg>` and talk to the **text** monitor
  (`m a b` to read, `> addr bytes` to write, `x` to go on; it prints its prompt before a command's
  output, so read until it has been quiet a moment). Keys go through the mailbox the same way
  (at most 7 queued at a time). A scratch script (`save24.py`, phase 8) did this; rewrite if needed.
  Never change Jim's own `vice.ini`.

### Notes for later (C64 Ultimate, phase 12)

- c64bridge 1.0.0 added **CIA1-level keyboard and joystick injection** (`c64_input` → `keyboard`) for
  Ultimate firmware that supports it. That goes through the real matrix, so it would reach our scanner.
  Check whether Jim's C64U firmware has it (the old project ran 1.1.0, which lacked some REST features).
- Frame capture on the C64U needs firmware video streaming; firmware 1.1.0 didn't have it.

### Debugging steps

1. Build with `--vicelabels build/main.vs` and pass that file as `symbolsFile` to `run_prg`, so
   `disassemble` shows our label names.
2. `c64_debug` → `create_checkpoint` at a label's address; wait with `wait_for_state`.
3. `get_registers` for PC/A/X/Y; `c64_memory` → `read` for state variables; `disassemble` around PC.
4. `step` / `step_return` to walk through; `continue_execution` to resume.
5. If VICE hangs, `c64_debug` → `nuclear_reset` restarts it.

### Disk tests: tools/ (our own VICE, not the bridge's)

The bridge's `c64_disk` / `c64_drive` operations only work on the Ultimate: on VICE, `mount` and
`power_on` fail ("firmware reported failure"). So disk tests use **`tools/`**: `vicemon.py` starts its own
`x64sc` (scratch settings file, warp, disk image in drive 8, binary monitor on **port 6510** so it never
clashes with the bridge on 6502) and speaks the binary monitor protocol; `mtest.py` drives the editor
through the test mailbox (keys, screen text, buffer text, labels from `build/main.lbl`). Tests:
`python tools/test_phase3.py [c64|ntsc]` (editing regression), `python tools/test_phase4_load_save.py
[c64|ntsc]`, `python tools/test_phase4_new_doc.py [c64|ntsc] [ro]`, `python tools/test_phase5.py [c64|ntsc]`,
`python tools/test_quit.py [c64|ntsc]` (RESTORE, and after Quit - a reset since v0.2 - the power-up
screen and a healthy BASIC),
`python tools/test_phase6.py [c64|ntsc]` (word wrap checked against a Python model of the wrap rule,
paging both ways, reflow, wrap off, marker, and timings in a 30 KB document).
**Run them all after any change to the editor** — test_phase3 caught a real regression in phase 5.
`python tools/test_phase7.py [c64|ntsc]` (the mouse through the mailbox: detection, click to a cell,
dragging both ways, mark key + click, pointer pictures, strips and icon colors, F3/F5 badge clicks,
right button, drag-scrolling, the 10-second hide). `mtest` has `mouse(events)` and `move_to(x, y)`.
`python tools/test_phase8.py [c64|ntsc]` (every menu and setting, clicks on menu rows, closing keys,
Stats against a Python count, Save menu, disk command and directory, Save defaults and reading them
back at a fresh start, Find with a color code inside a match and wrapping, Quit asking first). The
phase 4 tests load through F1 A A now, test_phase6 turns wrap off with F1 D X.
`python tools/test_phase9.py [c64|ntsc|oldntsc|drean]` (the REU: found and sized at 0/128/512/16384 KB
and shown in Stats; the same editing session — big jumps, copy, paste twice, cut — gives exactly the
same text with and without an REU; the clipboard is in the REU; the jump to the top of 20 KB is
quicker; and `late_irqs` stays 0; with 512 KB and 16 MB long documents are on, with 0 and 128 KB
off). **Run the whole suite with `MT_REU=128` too** (every older test then goes through the REU
copies and clipboard). Not 512: from 192 KB on, long documents are on, and the older tests read
and write the text buffer directly, which is then only a window onto the document.
`python tools/test_phase10.py [c64|ntsc]` (formats: magic saved and loaded back with its settings, as
SEQ and as PRG; ASCII saved (after the colors warning) and loaded with mixed line ends; PETSCII;
the Save format following the loaded one and CLEAR ALL going back; the saved bytes checked with
c1541; KERNAL LOAD for our PRGs, the byte reader for too-big and foreign ones).
`python tools/test_phase11.py [c64|ntsc]` (magic always PRG; the spinner turning during a long save;
upper case/graphics in the directory and the name box, and back; tape boxes and RUN/STOP at PRESS
PLAY / PRESS RECORD, document and cursor untouched; printing through VICE's raw printer 4, both
ways, and "DEVICE NOT PRESENT").
`python tools/test_phase11b.py [c64|ntsc]` (long documents, against a Python model: a 124 KB file
from a 1581 image with a 512 KB REU loads whole; 60 pages down; typing; marking 10 and 25 pages
across window moves, copying, and a paste bigger than the gap; HOME; Find far on, not found (cursor
back) and round to the start; CTRL-A refused; Stats over all of it; saved as PETSCII and as magic
and loaded back; a 45 KB ASCII file with a RETURN/LF pair split between two fills; then a 256 KB
REU and a 200 KB file: "TOO LONG", the start of it, editing works; `late_irqs` 0). `mtest` has
`doc()` (the whole document: head, window, tail, read from the REU through the gap), `reu_read()`
and `key_done()` (waits until a key's work, window moves included, is finished: `MB_BUSY`,
set by the main loop before it counts the key and cleared after; `keys()` only waits until keys
are taken. A first version waited for the key-time byte to change from $FF — a key can take 255
frames, so it hung once in a while).
`python tools/test_release.py` (phase 12: assembles a release build into `build/release/` and
starts it on PAL, NTSC, old NTSC and Drean with no REU, 128 KB and 512 KB: the IRQs run, the system
and REU are found, the text buffer has the right size, sprites on, ROMs out, no mailbox — all
that can be seen without typing; then the same with it packed by Exomizer, no REU and 512 KB).
`python tools/test_packed.py [c64|ntsc]` (the debug build packed by Exomizer, on a disk with a
MAGIC T DEFAULTS, started with LOAD"*",8 and RUN: it unpacks, knows it came from device 8, reads
the defaults; typing; Quit, then BASIC answers `PRINT 2+3` and `?"A"+"B"` — the unpacker left
$BA and BASIC's zero page alone).
`python tools/test_undo.py [c64|ntsc]` (CTRL-Z after typing, a cut, typing over and deleting
marked text, a recolor, a run of DELs, two runs of typing, a color key, overwrite mode, a paste —
each gives back exactly the text before; "NOTHING TO UNDO" twice and after CLEAR ALL; "TOO BIG TO
UNDO" after a 2 KB cut). `python tools/test_freeze.py ntsc` (see Mouse/IRQ notes: the CPU held up).
`python tools/test_mouse_delta.py` (no VICE: the assembled `mouse_sample`/`pot_delta` run in a
small 6502 emulator, checked against a Python model; then made-up 1351 readings like Jim's — a
count of wobble either way, resting on even and odd counts, slow and fast to-and-fro, 3% and
10% of readings way off — and like VICE's (up to 31 steps a reading, speeding up and slowing
down) through the real code, beside models of the three older methods: no drift, no
twitching at rest, no jumps, never the wrong way without readings way off; then 30 runs each
at 1–6 steps a reading with 1% and 3% way off: no more wrong-way moves than the third fix,
none bigger).
**Mouse timing:** `MB_BOT_END` (mailbox +62) and `late_irqs`/`missed_irqs` on all four systems
after any change to the mouse reading (a scratch script did it: sample the mailbox while typing).
`python tools/test_phase12.py [c64|ntsc]` (the Format values without SpeedScript, the CTRL keys
under the main menu, SHIFT + F3/F5 with and without marking, SHIFT + F7 switching word wrap (the
screen's rows checked), SHIFT + F1 as a color key (the default color untouched, typed text in
the new color, one code left in the text after two presses, CTRL-Z), a color key right after a
color code (that code moves after the cursor), F1 alone still the menu, a PRG of ours read as a SEQ file as an SD2IEC gives it, and loading from
VICE's file system drive, which answers 62; v0.2: the CTRL and function keys at the main menu's
foot, the Load format starting as MAGIC, the manual by KERNAL LOAD with it, a SEQ file loading
with it (Save format PETSCII), another program's PRG keeping its 2 address bytes as text (dropped
with PETSCII), and a 2-byte PRG).
(Rare unexplained failures: once test_phase4_load_save in ~12 runs during phase 5 and once more in
phase 7 (a monitor time-out; three reruns passed), once "keys not handled" right after start-up in
phase 6; none repeated. `mtest.keys` now reports the key
count and the mailbox's log of the last keys handled when it times out; look there next time.)
`vicemon.py` reads and writes $E000–$FFFF in VICE's **"ram" bank** (the editor lives under the KERNAL
ROM, which is switched in during disk work) and everything else in the "cpu" bank (I/O, color RAM).
They work on a copy of the .d64 in `build/test/`, quit VICE cleanly (so it writes the image back) and check
saved files with c1541 (`-read "name,s"` for SEQ files). Needs Python 3 (installed).

### Human Test protocol

Stop and present Jim with a short checklist when something can't be judged automatically:
look and feel, blink rate, mouse feel, NTSC/PAL visibility on a real TV, real drives, and each hardware
target. Each item: what to do, what should happen, what to report back. Batch questions rather than
asking one at a time. Don't guess on items listed under Open Questions — ask.

## Goals

- Edit text files natively on a C64: **PETSCII SEQ** files are the primary format.
- Stretch formats: **ASCII SEQ** (read/write) and **SpeedScript** documents (read/write).
- Modern comforts: text selection, CTRL-X/C/V, soft word wrap toggle, 1351 mouse, menu.
- **Single small PRG.** Target roughly 6–10 KB before compression (it grew to ~25 KB). The release
  disk has it packed with Exomizer (16 KB).
- Works on **PAL, NTSC, old NTSC, and Drean (PAL-N)** machines.
- Works with 1541/1571/1581, SD2IEC, Pi1541, and Ultimate devices by using KERNAL disk I/O only.
- **REU optional**: auto-detect and use if present; fully functional without one.

## Target Platforms

Development and automated testing happen in VICE. The other targets are tested once we have a
working program (phase 12). Everything must eventually be tested on:

| Target | Things to verify |
|---|---|
| Real C64 (PAL and NTSC) | Everything; real drives; tape; NTSC TV top-border visibility |
| VICE | Primary dev/test platform (via C64 Bridge MCP) |
| Commodore 64 Ultimate (C64U) | REU, Ultimate drives, tape, left/right SHIFT, mouse |
| MEGA65 with C64 core | REU support, 1351 mouse support, keyboard SHIFT mapping |
| TheC64 Mini / Maxi | Keyboard mapping (Mini uses a USB keyboard), whether left/right SHIFT are distinct, mouse, REU, and tape support, SEQ writing on its virtual drives |
| CBMSTUFF BlingBox keyboard | Left/right SHIFT reported separately, CTRL / C= / RUN/STOP / ← / cursor keys |

Features that a platform lacks (e.g. REU or mouse) must fail gracefully: detect and disable, never crash.

## Toolchain

- **ACME** 0.97 cross-assembler (chosen deliberately, for retro charm):
  `C:\bin\acme0.97win\acme\acme.exe` (not on PATH). Use `--vicelabels build/main.vs` for VICE symbols.
- **VICE** 3.9 (`x64sc`): `C:\bin\GTK3VICE-3.9-win64\GTK3VICE-3.9-win64\bin\x64sc.exe`. C64 Bridge
  starts it with the binary monitor enabled. Configure a 1351 mouse in control port 1 and an REU for the
  relevant tests (see C64 Bridge section).
- **c1541** (ships with VICE, same `bin` folder) to build a `.d64` with the PRG and sample test files.
- **C64 Bridge** MCP server (see its section below).
- **Exomizer** 3.1.2 for the release disk's packed program: `C:\bin\exomizer.exe`, on Jim's PATH
  (since 2026-10-07; a Claude session started before that may not see it on its PATH — then use
  the full path). Its documentation and sources: `G:\My Drive\retro computers 2\exomizer-3.1.2`
  (`exo20info.txt`: the sfx options; `exo31info.txt`: what 3.1 changed).
- Editor: VS Code with the **VS64** extension (2.6.2 installed), which supports ACME. VS64 builds from
  `project-config.json`. Its output file is named after the project `name` there, set to
  `magictypewriter` so VS64 and `build.bat` both write `build/magictypewriter.prg` (VS64 makes no .d64).
- The paths above are for Jim's Windows PC. On the Ubuntu laptops, `build.sh` expects `acme` and `c1541`
  on the PATH (e.g. from the `acme` and `vice` packages); confirm versions with Jim when first set up there.

### Source layout

Old on-machine assemblers usually held one source file in memory, and big projects chained several
files together. With ACME, one master file pulls in the others with `!source`. Keep a modest split so
edits and diffs stay easy to follow; merge files if Jim prefers fewer.

```
src/main.asm        entry, BASIC SYS stub, init, main loop, !source the rest
src/system.asm      PAL/NTSC detection, timing tables, REU detection and DMA
src/irq.asm         raster IRQ chain (borders, color splits, page marker, housekeeping)
src/input.asm       keyboard matrix scanner, 1351 mouse, debug test mailbox
src/editor.asm      gap buffer, cursor, selection, clipboard, redraw, wrap
src/menu.asm        boxes, prompts, the menus (table-driven), Stats
src/fileio.asm      KERNAL disk I/O, directory, disk command, MAGIC T DEFAULTS
src/find.asm        CTRL-F Find (assembled with the editor, under the KERNAL, since phase 11)
src/reu.asm         REU detection and sizing, DMA copies, clipboard in the REU
src/reudoc.asm      long documents in the REU (runs at $C000, only with an REU of 192 KB or more)
src/startup.asm     everything that runs once at start-up (runs from the text buffer, see Memory Map)
src/data.asm        menu strings, tables
test/               the manual (manual.prg, from docs/manual.txt) and sample SEQ files (longdoc:
                    60 KB, for REU tests); the debug disk gets them all, the release disk only
                    the manual
docs/               hardware-tests.md: the phase 12 checklist
README.md           the user manual
build.bat           assemble + make d64 (Windows)
build.sh            same steps (Linux)
```

## Memory Map

**As built (2026-09-27, "plan D", Jim's choice):** the editor's code runs in the RAM under the KERNAL
ROM, so the text buffer keeps the full 36 KB on a stock C64.

| Address | What |
|---|---|
| $02–$1B | zero page (list in `src/main.asm`); BASIC's too (Quit resets the C64, v0.2) |
| $0200–$0237 | BASIC's input buffer, used for work bytes that need no starting value (so they take no room in the program): the mouse's `pot_c`/`pot_p1`/`pot_p2`, `.dnew`, `mouse_acc_x/y`, `mouse_dx`, `pot_rest`, `mouse_dy`, `click_row/col/icon` ($0200–$020F; 2026-10-11), `status_raw` ($0210–$0237), `name_buf` ($0238–$024F) and `num_text` ($0250–$0258) (v0.2). Neither we nor the KERNAL's disk and tape routines use it otherwise; BASIC only after Quit. All in use |
| $02C0–$02FE | debug test mailbox (debug builds only) |
| $0400–$07FF | screen |
| $0801– | the lower part of the program: IRQs, keyboard, boxes, menus, disk, undo, data; then the stored copies of the editor and of reudoc.asm, then startup.asm (with the four copies of the border code) |
| after the lower part | run-time tables (ctype, scrcode, `border_code`: this system's strip code, the per-row arrays, prompt save area), **over the stored copy** once it is copied |
| $3E80–$3FFF | sprite blocks 250–255 (**$3FFF must be $00**: the idle-graphics byte drawn in the opened borders) |
| $4000–$CBFF | text buffer (35 KB), clipboard at its top (none with an REU: it is in the REU). `startup.asm` runs from here once (the PRG file carries it there), before the document takes the room |
| $CC00–$CFFF | **the undo log** (1 KB, phase 12: `undo_base`, taken from the top of the buffer at start-up; `buf_top` = $CC00) |
| ($C000–$CEFF) | **with an REU of 192 KB or more:** `reudoc.asm` (long documents), copied there at start-up; the text buffer is then $4000–$BBFF (a 31 KB window) and the undo log $BC00–$BFFF. `RD_PAGE` $CF00: a page for reading the REU's text |
| $D000–$DFFF | I/O (the RAM under it is unused) |
| $E000–$FFF9 | **the editor** (`src/editor.asm`, assembled with `!pseudopc $e000`; `copy_high` puts it there at start-up) |
| $FFFA–$FFFF | NMI → `nmi_handler`, IRQ → `irq_entry`, used while the KERNAL ROM is out |

- **VIC bank 0**, so the VIC sees the **ROM character set** at $1000–$1FFF; no custom font.
- **While editing `$01 = $35`**: BASIC and KERNAL ROMs out, I/O in. The program has its own keyboard
  scanner and screen code, so it only needs the KERNAL for disk work (later printer and tape).
  `io_begin` switches the KERNAL ROM in (`$36`) and `io_end` switches it out again. Quit sets `$37`.
- **The one rule:** between `io_begin` and `io_end` the RAM at $E000 is hidden behind the ROM, so
  **nothing in `editor.asm` (code or variables) may be used there.** Disk code, and everything it calls
  in that stretch, lives in the lower part (`petscii_to_screen` moved to `menu.asm` for this; loading
  empties the buffer itself instead of calling `empty_buffer`). Boxes use the editor's cursor, so they
  open before `io_begin` and close after `io_end`. New printer and tape code (phase 11) follows the same rule.
- With the KERNAL ROM out the CPU takes its vectors from RAM at $FFFA–$FFFF. `irq_entry` (irq.asm) is an
  instruction-for-instruction copy of the KERNAL's IRQ entry at $FF48 (same 29 cycles), so the stable
  raster timing did not change (re-checked on all four systems). RESTORE goes straight to `nmi_handler`
  (through the KERNAL's $FE43 and $0318 while the ROM is in).
- The build stops with an error if the lower part plus its tables reach $3E80, or the editor reaches $FFFA.
- Space (v0.2, 2026-10-10; mouse fix 2026-10-11): debug tables end $3E7E, so **only 2 bytes
  free below the sprite blocks in debug builds** (release: ~580). Debug builds with
  `-DMOUSE_SHOW=1` or `-DMOUSE_TRACE=1` no longer fit (they didn't before the mouse fix
  either); for a MOUSETEST disk use a release build with `-DMOUSE_SHOW=1` (fits, ends $3C95); the editor + find end $FFF3 (**7 bytes free under the
  KERNAL**); reudoc.asm ends $CC93 (~620 free before RD_PAGE). undo.asm is ~1.2 KB. BASIC's
  input buffer $0200-$0258 is all in use now. **The next feature needs room first** — ideas: the
  63 free bytes of sprite block 255 ($3FC0–$3FFE; $3FFF must stay 0), $02A7-$02B3 (unused by the
  KERNAL; the debug mailbox starts at $02B4), or (ask Jim) moving BUF_START up. **Watch the
  border code's padding:** it starts at `high_load` + 512, so if the lower part's end moves past
  ~$xx26 in its page, its loops may need same_page padding again (up to ~20 bytes).
  Earlier: debug build, phase 11b: lower part $0801–$377A, tables to $3B15 (a `-DMOUSE_TRACE=1`
  build adds a 256-byte mouse trace); editor + find $E000–$FEE4; reudoc.asm $C000–$CBAC. Phase 8 took about 4 KB, phase 9's REU part about 0.6 KB, phase 10
  about 0.9 KB, phase 11 about 1.3 KB, 11b ~2.9 KB in reudoc.asm and ~0.3 KB elsewhere (after
  startup.asm gave back ~0.9 KB). Keep new code lean, and tell Jim early if it won't fit. New code
  goes in the lower part; code that runs during disk work must go there anyway.
- **Start-up code runs from the text buffer** (`src/startup.asm`, since 11b): `start` ($080D) jumps
  to `startup` at the end of the PRG file ($6xxx); it does everything that runs once (copy_high,
  detect_system, detect_reu, reudoc_install, init_screen/sprites/marker/keyboard/mouse, the debug
  mailbox, load_defaults) and jumps back to `start_done` (editor_init, main loop). The sprite
  images live there too (init_sprites copies them to $3E80). **Nothing in startup.asm may be
  called later** — the document overwrites it. The build stops if it would start below $4000.
- **Quit resets the C64** (v0.2; before: a BASIC NEW and warm start). Restarting means loading the
  program again.
- Leave the **tape buffer $033C–$03FB** free for KERNAL tape I/O.
- Zero page: we use $02–$1B (`ZP_END` in main.asm; move it up when adding zero page). Leave the KERNAL's
  area alone.

## Display

Reference mockup: `resources/Text Edit Screen 9-25-26.png` (Jim's drawing). The **border sprites in it are pixel-exact**
(1 image pixel = 1 C64 pixel). The text area and text in it are **not** to scale.

- Text area: full **40×25**, ROM character set.
- **Character set toggle: C= + SHIFT** (either SHIFT), exactly like BASIC: switches between
  upper/graphics ($D018 = $15) and upper/lower ($D018 = $17). Default: upper/lower.
  The character set is **saved with the document** (Jim, 2026-09-27; see Formats), so switching it sets
  the "modified" flag.
- **Open the top and bottom borders.** Raster IRQ at line $F9 clears $D011 bit 3 (24 rows); a later
  IRQ (after line $FC) sets it back.
- **Open the side borders on the strip lines** (28–49 and 251–264) so the F3/F5 badges can sit in the
  corners. See Border icons.
- **No text in the borders** other than the key labels drawn into the icon sprites.

### Colors (from the mockup)

| Area | Color |
|---|---|
| Top and bottom border strips (full width, including corners) | Blue (6) |
| Side borders beside the text area | Dark grey (11) |
| Page position marker (side borders) | Grey (12) |
| Text background (default; the menu option changes it — SHIFT-F7 did until 2026-10-07) | Black (0) |
| Default text color (menu option; the document can change text color with color codes) | Light grey (15) |
| Menus, prompts, disk directory | By background (Jim, 2026-10-09; `box_colors` in data.asm): **black** on white, cyan, green, yellow, light red, grey, light green and light grey; **light grey** on the others. Not the text color setting any more. |
| Border icon sprites | Light blue (14) |
| Mouse pointer sprite | By background (Jim, 2026-10-08; `pointer_colors` in data.asm): **light green (13)**, but **green (5)** on white, cyan, purple, yellow, light green and light grey. A border icon under the pointer lights up **in the pointer's color**. (Before: red, black on some backgrounds, and the icon white.) |

### Color splits

The frame is two colors: blue strips top and bottom, dark grey sides next to the text.

- In the opened top/bottom strips the middle area shows **$D021** (background) and the sides show **$D020**.
  So at each boundary **both** registers change:
  - End of line 50 → start of line 51: $D020 = dark grey, $D021 = black.
  - End of line 250 → start of line 251: $D020 = blue, $D021 = blue.
- Both writes must land in **horizontal blanking** (after the right border, before the left border) so
  neither side shows a one-line step. That window is only ~12 cycles, so use a **stable raster**
  (double-IRQ technique) for these two IRQs, with PAL/NTSC delays from the timing table.
- Lines 50 and 250 are not badlines; line 51 is, so the top split must finish before it.
- Sprite DMA (pointer, icons) on those lines steals cycles: account for it, and test with the pointer
  parked on lines 50 and 250.

### Border icons (sprites)

Six hardware sprites, no multiplexer, all hi-res. Border icons (1–5) are light blue (14); the pointer
light green or green (see Colors).

| Sprite | Use | Click action |
|---|---|---|
| 0 | Mouse pointer (highest priority) | — |
| 1 | Menu icon "≡F1" | Open menu (same as F1 / RUN/STOP) |
| 2 | Top-left "F3" badge | Page up |
| 3 | Top-right "F3" badge (same image as 2) | Page up |
| 4 | Bottom-left "F5" badge | Page down |
| 5 | Bottom-right "F5" badge (same image as 4) | Page down |

**Chosen 2026-10-08 (Jim drew them on a grid; three rounds of test disks on his 1702):** all three
images are **7 rows**, solid shapes with the letters cut out (the cut-out letters need a solid row
above and below). Taller ones lost rows on the 1702 (13-row badges at both ends; the 9-row ≡F1 on
41–49 "just a bit"). Sprite 2/3 data (21×7, the flat end of an up arrow with "F3" cut out; the wide
row faces the text area):
```
......XXXXXXXXX.........   $03,$FE,$00
.....X....X...XX........   $04,$23,$00
....XX..XXXXX..XX.......   $0C,$F9,$80
...XXX...XX...XXXX......   $1C,$63,$C0
..XXXX..XXXXX..XXXX.....   $3C,$F9,$E0
.XXXXX..XXX...XXXXXX....   $7C,$E3,$F0
XXXXXXXXXXXXXXXXXXXXX...   $FF,$FF,$F8
```
Sprite 4/5 data (21×7, the same shape upside down with "F5" cut out):
```
XXXXXXXXXXXXXXXXXXXXX...   $FF,$FF,$F8
.XXXXX....X....XXXXX....   $7C,$21,$F0
..XXXX..XXX..XXXXXX.....   $3C,$E7,$E0
...XXX...XX....XXX......   $1C,$61,$C0
....XX..XXXXX...X.......   $0C,$F8,$80
.....X..XXX....X........   $04,$E1,$00
......XXXXXXXXX.........   $03,$FE,$00
```
Sprite 1 data (19×7, "≡F1" cut out of a box with a pixel off each corner):
```
.XXXXXXXXXXXXXXXXX......   $7F,$FF,$C0
XX....XX....XX..XXX.....   $C3,$0C,$E0
XXXXXXXX..XXX...XXX.....   $FF,$38,$E0
XX....XX...XXX..XXX.....   $C3,$1C,$E0
XXXXXXXX..XXXX..XXX.....   $FF,$3C,$E0
XX....XX..XXX....XX.....   $C3,$38,$60
.XXXXXXXXXXXXXXXXX......   $7F,$FF,$C0
```
Store only the rows above (7×3 bytes); expand into 64-byte sprite blocks at init and zero the rest
(the images are in `src/startup.asm` since phase 11b). Earlier designs: the mockup's 13-row badges;
"F3"/"F5" between two arrows and an open "≡F1", 7 rows (phase 1); solid 9-row arrows ("SB3C") and a
9-row ≡F1 box ("M1", phase 12, 2026-10-02 to 10-07). Jim's other tries on 2026-10-07/08: 12-row
pointed arrows (tips cut off on the 1702), 10-row pointed arrows with flat bases.

**Decided (2026-09-27):** the badges sit in the side borders, as in Jim's mockup. (Branch `phase1`
keeps the earlier layout, with the badges above/below the text area.)

Vertical placement (same on PAL and NTSC), as raster lines:
- Top badges and menu icon: raster 43–49 (2026-10-08; the badges were 37–49 in the mockup, then
  41–49).
- Bottom badges: raster 252–258 (2026-10-08; were 252–264, then 252–260).

Why one line away from the text area: showing a sprite in the right border of line 50 means opening
that border, and that also opens the **left** border of line 51, the first text line. There the VIC
shows the text background ($D021, black) instead of the dark grey side color, and line 51 is a
badline, so the CPU can't change the color in time. Same at the bottom with line 250. Matching the
mockup exactly would need two more sprites (6 and 7) as dark grey patches over those two spots.

Found in phase 1 (VICE): a sprite's first row shows on raster line **Y+1**, and the VIC always fetches
all **21 rows** of a sprite, stealing CPU cycles at the end of each of those lines. The top badges and
the menu icon share the same 21 fetched lines (29–49, Y = 28), with their pictures low in their blocks
(badges and icon rows 14–20), so every line of the top strip loses the same cycles and the line
50/51 color split has no sprite fetches. The bottom badges use rows 0–6 with Y = 251. Also, the VIC
compares sprite Y with only the low 8 bits of the raster line, so on PAL the top sprites would appear
again at line 256+Y; sprites 1–3 are switched off after the bottom strip and back on at line 10.
- **NTSC (Jim's 1702):** the old 13-row badges were cut off at both ends, the 9-row ≡F1 on 41–49
  "just a bit". The 7-row icons on 43–49 and 252–258 show whole (Jim, 2026-10-08: "looks great").

**Horizontal placement:**
- Left badges (sprites 2 and 4): X = 1, in the left border; the widest row (columns 0–20) ends at
  X = 21, **2 pixels from the text area** (X = 24) (Jim, 2026-10-08; he compared touching, 1 and
  2 pixels on the 1702).
- Right badges (sprites 3 and 5): X = 346, in the right border; the widest row starts at X = 346,
  2 pixels from the text area (which ends at X = 343). X > 255, so set their bits in the sprite X
  MSB register $D010.
- Menu icon (sprite 1): X = 32, 8 pixels in from the text area's left edge.
- The side borders are opened on lines 28–49 and 251–264 with the 38/40-column trick ($D016 written
  in one exact cycle per line), from the two stable IRQs. An open side border shows $D021 (blue in
  the strips) plus sprites.
- CPU cost: the two strip IRQs run from line 25 to 51 and from 247 to about 265, roughly 14% of the
  CPU on PAL and 17% on NTSC. Jim accepted this.
- Sprites 6 and 7 are still free.

### Page position marker

- The **side border color changes** to grey (12) over a band of raster lines to show the visible part
  of the document. It appears on both left and right borders.
- Two raster IRQs per frame set the marker color at the band's top line and restore dark grey at the
  bottom line.
- Map the band into lines 51–250: `top = 51 + 200*firstLine/totalLines`,
  `height = max(8, 200*25/totalLines)`. 16-bit math.
- **As built (phase 6):** positions are **byte offsets**, not lines: top = 51 + 200 × (offset of the top
  row) / (text length), bottom = 51 + 200 × (offset just below the screen, or the length if the end is
  on the screen) / length, at least 8 lines tall (`update_marker` in editor.asm, called at the end of
  every `redraw_from`; `marker_set` in irq.asm takes first/last/total). Why bytes: they are known
  already and cost nothing to keep up to date (counting lines would need bookkeeping in every edit, and
  with word wrap "lines" means screen rows, which would need a layout of the whole document); they
  work the same with wrap on and off. For ordinary text the difference from lines is small.
  **When the whole document fits on the screen, the band is the whole side (all grey)**, like a
  scrollbar thumb that fills its track — **Jim: keep it that way** (2026-09-28).
- Write $D020 while the beam is in the **text-area part of the line**, and **avoid badlines** for band
  edges (lines $30–$F7 where `(raster & 7) == YSCROLL`). Snap to the nearest safe line.
- Display-only; the pointer can't be seen in the side border beside the text.

### Cursor

The cursor shape shows the typing mode:

- **Overwrite mode: flashing block cursor like the BASIC editor** — the character under the cursor
  toggles reverse video.
- **Insert mode: flashing thick underline using screen code 121 ($79)**, the lower 3/8 block. It looks the
  same in both character sets. The blink alternates the real character and screen code 121, so the
  character under the cursor is hidden during the "on" phase; restore the real character and its color
  when the cursor moves.
- If the 121 cursor proves annoying, a later fallback is a sprite underline (sprite 6, 8×2 pixels) that
  overlays the character instead of replacing it.
- **Tried and dropped (Jim, 2026-10-07): letting the character show through the insert cursor.**
  - **Frame swapping (tested):** in the "on" phase the cell swapped between the character and 121
    every frame (19 bytes in `cursor_blink`). It worked as built, but a 25/30 Hz swap looks like a
    buzzing, half-bright cell. **Jim: "not a good solution, looks annoying"** in VICE and on the C64U.
    Don't try it again.
  - **Sprite underline (assessed, not built):** the only way to show the character and an underline
    together without flicker (no custom font). Estimate: ~90–120 bytes (editor ~50–65, IRQ/lower part
    ~25–40) plus sprite block 255 (the last spare). The catches:
    - Sprite DMA must stay off lines ≤ 51 and ≥ 250, so one image can't serve both the top and the
      bottom text rows. Choose one: a second block, the line-10 IRQ moving the underline inside the
      block, or the 121 cursor on the edge rows.
    - On row 24 the underline sits a line higher (line 250 is the split).
    - Sprite 6 is fetched at the *start* of each line (sprite 0 at the end of the one before), so the
      line 249 stable IRQ needs re-measuring on all four systems.
    - On PAL, a cursor on row 0 (Y ≈ 51) triggers again at line 307 and needs switching off after
      the bottom strip.
    - On reversed cells (marked text too) the underline must be drawn in the background color, or it
      vanishes.

    Needs room first (35 bytes free under the KERNAL, 24 in the debug lower part). The cursor stays as
    it is for now.
- **The cursor is drawn in the current typing color** (see Colors and Reverse). Press CTRL-3 and the
  cursor turns red.
- Blink every ~1/3 second, as the KERNAL does: 17 frames PAL, 20 frames NTSC (timing table).
- Cursor shows solid (not blinking) while a key is held or the cursor is moving, then resumes blinking.

### Raster IRQ chain

Order by raster line each frame; rebuild when the marker moves:
color split at line 50 (stable) → marker top →
marker bottom → color split at line 250 (stable) → open-border IRQ ($F9) → housekeeping (keyboard scan, cursor blink, restore 25-row mode) → mouse read
(separate, see Mouse).

As built (see the table at the top of `src/irq.asm`): line 10 turns
sprites 1–3 on and puts in the pointer and icon colors worked out last frame; line 25 prepares the
stable top IRQ; line 27
stabilizes, opens the side borders on lines 28–49 and does the color split at the end of line 50,
**then runs the housekeeping with IRQs allowed** (sprites 1–3 off, mouse, keyboard scan), so the
page-marker IRQs can cut in on time; marker top/bottom; line 247 prepares the stable
bottom IRQ; line 249 opens the top/bottom border, does the split at the end of line 250, opens the
side borders on lines 251–264, then only short jobs (25 rows back, frame counter, marker update).

Why the housekeeping moved to the top (phase 2): on NTSC the bottom strip IRQ ends around line 1–3 of
the next frame, leaving only ~22 lines before the top strip IRQ at line 25. Measured (debug build):
housekeeping runs from line 52 to about 64 with no key pressed, about 71 in a frame with a key press;
the bottom strip IRQ ends at line 266 on PAL and line 3 on NTSC. The mailbox reports these (+15, +61,
+62). Long jobs belong in the top housekeeping, never at the bottom. All wait
counts are per video system; how they were found (`SPLIT_TEST` and `BORDER_TEST` builds) is described
in `src/irq.asm`. The mouse pointer's sprite fetches never reach the strips (see Mouse, as built);
checked with the pointer at every edge of the text area on all four systems (phase 7). Housekeeping
with the mouse ends by about line 72.

## Startup

1. **Before touching anything**, read $BA (the last device the KERNAL used, i.e. where the PRG was loaded from).
2. System detect (PAL/NTSC, REU), then set up the screen, IRQs, etc.
3. If $BA is a disk device (8–30), try to open `MAGIC T DEFAULTS` on it and read the settings (same header
   format as a magic document, no text). If it's missing, the device isn't present, or anything fails:
   **read the error channel (15) to clear the drive's error and blinking LED, then start silently** with
   built-in defaults. No message. Tape (1) or any other value: skip the config and start with defaults.
   Programs started by an Ultimate/TheC64 "run" menu may leave $BA stale; the silent-failure rule covers it.

## PAL / NTSC

- At startup, find the highest raster line reached: 311 = PAL (or Drean), 262 = NTSC, 261 = old NTSC.
- Per-system **timing tables**: key repeat, cursor blink, mouse idle timeout, mouse acceleration,
  $D021 split delays, REU chunk size.
- Border opening and sprite Y positions use the same lines on all systems.

## Keyboard

Custom **CIA1 matrix scanner** (not SCNKEY/GETIN — the KERNAL turns CTRL-letters into control codes and
can't separate the two SHIFT keys).

Key matrix positions (verify against a matrix chart):
- Left SHIFT: row 1 ($DC00=$FD), $DC01 bit 7. **SHIFT LOCK is the same line.**
- Right SHIFT: row 6 ($BF), bit 4.
- CTRL: row 7 ($7F), bit 2. C=: row 7, bit 5. RUN/STOP: row 7, bit 7. ←: row 7, bit 1.

**RESTORE:** Trap the NMI vector so RUN/STOP+RESTORE can't warm-start BASIC and lose the document.
Ignore it, or treat it like RUN/STOP.

**As built (phase 2, `src/input.asm`):**
- Key codes are `row * 8 + bit` with row = the $DC00 line (the same numbers the KERNAL uses; table at
  the top of `src/input.asm`). The scanner turns each new press into an **event**: key code + the
  modifier bits held at that moment (left SHIFT, right SHIFT, CTRL, C=, plus a repeat flag). Modifier
  keys make no events of their own; their live state is `key_mods`. The main program reads events with
  `get_key` and turns them into PETSCII with `key_to_petscii` (CTRL wins, then C=, then SHIFT).
- The four key tables (normal, SHIFT, C=, CTRL) are copies of the KERNAL's, in `src/data.asm`, so every
  key types what it types in BASIC. The CTRL table gives CTRL-1…8 = color codes, CTRL-9/0 = RVS on/off,
  CTRL-letters = control codes ($01 for CTRL-A …); the C= table gives C= 1…8 = the other 8 colors.
- **All non-modifier keys repeat** (a modern editor habit; the KERNAL only repeats SPACE, INST/DEL and
  the cursor keys), **with BASIC's timing** (Jim's choice, 2026-09-27): the KERNAL repeats 19 ticks
  (1/60 s) after the press, then every 4 ticks (15/s). We scan once per frame, so `key_timer` counts in
  1/300 s steps: 6 per PAL frame, 5 per NTSC frame (timing table), giving the same speed on every system.
  Checked: a 48-frame hold gives 10 repeats on PAL and 8 on NTSC, as calculated.
- **A repeat is only added when the event queue is empty** (phase 6): if a key's job takes longer than
  the repeat time (scrolling a big document), repeats no longer pile up and carry on for seconds after
  the key is let go. At most one step follows the release.
- Port 1 lines held low (joystick, mouse buttons) are read with $DC00 = $FF and masked out of the scan.
  $DC00 is left at $7F afterwards (row 7, and the SID paddles on port 1 for the mouse).
- Character set toggle rule as built: fires when C= and a SHIFT are both let go, provided no other key
  was down at any time while both were held.
- RESTORE: the NMI handler only counts presses; the scanner turns that into a `KEY_RESTORE` event, which
  the program treats like RUN/STOP. Quit puts the original NMI vector back.
- Test mailbox key events (see `src/input.asm`): key code (or $FF for modifiers only), then modifiers in
  bits 0–3 and hold time in bits 4–7 (steps of 8 frames). They go through the same code as real keys.

### Cursor movement and selection

The **mark key** is set in the main menu: **C=** (default, Jim 2026-09-27) or **left SHIFT**.
Why C= is the default: in VICE, PC Up/Left arrive as right SHIFT + CRSR, but with PC Left Shift held VICE
drops that right SHIFT, so left SHIFT + Up marks *downward* (see Open Questions). With C= (**Tab** in VICE)
all four arrow keys mark correctly. **User instructions must say: the left SHIFT mark key doesn't work
for marking up/left in VICE — use C= (Tab).**

With mark key = left SHIFT:
- **Right SHIFT only reverses direction**: CRSR DOWN → up, CRSR RIGHT → left.
- **Left SHIFT held = mark text** with any cursor movement.
- Left SHIFT + right SHIFT + cursor key = mark up/left.

With mark key = C=:
- **Either SHIFT reverses direction**, as on a stock C64.
- **C= held = mark text** with any cursor movement; C= + SHIFT + cursor key = mark up/left.

Both settings:
- Mark key + F3/F5 marks by page. F7 and SHIFT-F7 (F8) are not movement keys, so they never mark.
  **As built (Jim, 2026-09-29):** with the mark key, F3 puts the cursor on the top row and F5 on the
  bottom row (`mark_page_up` / `mark_page_down`), so the page marked fills the screen behind it.
  Plain F3/F5 keep the cursor on its screen row; marking that way looked as if it went the wrong
  way (the cursor seemed to stay put and the text on the other side lit up). The F3/F5 badges
  do the same (`.page_up` / `.page_down` in editor_key).
  **SHIFT + F3 / SHIFT + F5 (F4 / F6): the top / the end of the document** (Jim, phase 12); the SHIFT
  that reverses cursor keys (right SHIFT with the left SHIFT mark key, either SHIFT with C=); with
  the mark key too, marking all the way (`doc_top` / `doc_bottom`; `reu_to_end` for long
  documents, not while marking). **SHIFT + F1 (F2): the color key of the next color after the
  one at the cursor; SHIFT + F7 (F8): word wrap on/off** (Jim, 2026-10-07; either SHIFT).
- Either SHIFT types capitals normally; marking only happens with movement keys.
- Mark key + mouse click extends the selection.
- **Character set toggle (C= + SHIFT):** fires when C= and a SHIFT are both down **and released without any
  other key pressed in between**. This keeps it from triggering while C= + SHIFT + cursor marks upward.

### Key map

| Key | Action |
|---|---|
| RUN/STOP | Open menu. In a menu or prompt: cancel/close |
| F1 | Open menu (same as clicking hamburger) |
| F3 / F5 | Page up / page down (also clicking the F3 / F5 badges) |
| SHIFT-F3 / SHIFT-F5 (F4 / F6) | Top / end of the document (phase 12) |
| F7 | Toggle insert / overwrite mode (cursor changes shape) |
| SHIFT-F1 (F2) | The next color after the one at the cursor, as if its color key were pressed (typing color, or recolor the marked text) |
| SHIFT-F7 (F8) | Word wrap on / off (same as the menu item D; it stepped the background until 2026-10-07) |
| C= + SHIFT | Toggle upper/graphics ↔ upper/lower character set, like BASIC |
| HOME | Start of line; press again = top of document |
| SHIFT + CLR/HOME | Prompt **"CLEAR ALL Y/N"**; Y clears the whole document, N or RUN/STOP cancels |
| INST/DEL | Delete the character left of the cursor; cursor and all following text move back one space. At line start, joins with the previous line |
| SHIFT + INST/DEL | Insert a space at the cursor; cursor stays put |
| CTRL-X / C / V | Cut / copy / paste |
| CTRL-Z | Undo the last change (phase 12) |
| CTRL-A | Select all |
| CTRL-S | Save with the current Save menu settings; asks for a file name if none yet |
| CTRL-F | Find (see Find) |
| CTRL-1 … CTRL-8 | Colors: black, white, red, cyan, purple, green, blue, yellow (as in BASIC) |
| C= 1 … C= 8 | Colors: orange, brown, light red, dark grey, grey, light green, light blue, light grey |
| CTRL-9 / CTRL-0 | Reverse on / reverse off |
| SHIFT + RETURN | Same as RETURN (stores CR) |

Other CTRL-letters are ignored; in BASIC they produce control codes, but here CTRL-A/C/F/S/V/X are
editor shortcuts. The number keys with C= are color keys, so **with mark key = C=, marking only happens on
movement keys** — C= + digit still selects a color.

## Mouse (1351, port 1)

- Read SID POTX/POTY ($D419/$D41A) once per frame; compute signed deltas from bits 1–6 (standard 1351
  method). Buttons: left = $DC01 bit 4, right = $DC01 bit 0.
- **Pointer:** hi-res sprite, **red (2)**, shown as the red box in the mockup (now light green or
  green by background, see Colors). Shape: 8×8 box outline. Top and bottom edges 1 pixel thick; left and right edges 2 pixels wide:
  ```
  11111111
  11000011
  11000011
  11000011
  11000011
  11000011
  11000011
  11111111
  ```
- **Click** moves the text cursor to the **nearest character cell** (round the box position to the nearest
  8-pixel cell). Drag selects.
- **No mouse detected → never show the pointer.** Treat the mouse as present only after the POT values
  change (a joystick or empty port won't do this).
- **Hide the pointer after 10 seconds without mouse input** (frame count from the timing table). Moving the
  mouse shows it again; a click while hidden only reveals it, without moving the cursor.
- Clamp the pointer to the text area plus the opened top/bottom strips. (**Changed in phase 7:** the pointer
  itself stays over the text area; in the strips it hides and the icon under it turns red. See As built.)
- **Gotcha 1 — POT mux:** $DC00 bits 6/7 select which port the SID samples, and the keyboard scan rewrites
  $DC00. After scanning, restore $DC00 to select port 1, and read the POTs in a **later IRQ** (the SID
  needs ~512 cycles to take a fresh sample).
- **Gotcha 2 — port 1 shares keyboard lines:** mouse buttons pull $DC01 lines low and look like key
  presses. Read the port with $DC00=$FF first and mask those bits out of the keyboard scan.

**As built (phase 7, "The 1351 mouse" in `src/input.asm`; read its header comment first):**
- **Where the pointer goes (Jim, 2026-09-28): over the text area only.** A sprite's fetches steal CPU
  cycles on all 21 of its lines, and the strips are exact-timed, so the pointer never enters them.
  Moved on past the text, it **hides and the border icon under it lights up in the pointer's
  color** (`pointer_colors[text_bg]`, 2026-10-08; it was white in phase 12, and the pointer's red or
  black before that);
  a click then works that icon: F3 badges page up, F5 badges page down (with the mark key held: marking
  by page), the menu icon opens the menu. Hit zones in the strips (box left
  edge x): left badges x < 20, right badges x >= 340, menu icon (top only) 20 <= x < 60. (2026-10-08:
  the badges cover X = 1–21 and 346–366, the ≡F1 box X = 32–50, so the zones still fit.)
- The box's top line stays within **52–242** (not 51 or 250: its fetches must stay within lines 52–249,
  clear of the line 50 split, the line 249 stable check and the strips). From line 229 it uses a second
  picture low in its block (block 254, rows 13–20; `spr_pointer_low`), so the fetches run above the box.
  So on the top and bottom text rows the box sits one line off the cell; it still picks that cell.
- **Reading: three times a frame** (`mouse_sample`: at line 10, in the housekeeping just before
  `scan_keyboard`, and at the end of the bottom strip IRQ — after it has set the line 10 IRQ, since on
  NTSC it ends near line 7). Each reading adds its move to `mouse_acc_x/y` (the 1351 manual's method,
  `pot_delta`; phase 12: the middle of the last three readings, a dead band around where the
  pointer settled, and exact step bookkeeping — see the phase 12 status).
  Why three: one reading can only tell 63 steps apart either way, and VICE's 1351 moved
  ~60 steps a frame (a real 1351 is fine with one; more does no harm). None falls within 512 cycles of
  the keyboard scan's $DC00 changes. `mouse_frame` (housekeeping) takes the frame's total, Y inverted,
  doubles it when fast (threshold from the timing table: 4 PAL, 3 NTSC; not when it is 64 or more),
  works out everything else and leaves the VIC values in `ptr_next_...` / `icon_colors`;
  `irq_frame_top` (line 10) puts them in, so the pointer never tears. Buttons read with $DC00 = $FF.
  Measured: housekeeping ends by line 73; the bottom strip IRQ by line 269 (PAL) / line 6-7 (NTSC).
- **Debug recorder:** debug builds keep the last 64 frames' paddle values (the housekeeping reading)
  and the movement worked out, 4 bytes a frame, in `mouse_trace` (index `mouse_trace_i`). A scratch
  script read it live from a visible VICE while Jim moved the mouse; that is how the VICE 3.9 problem
  was found. Rewrite such a script if needed: poll the ring every 0.2 s through `vicemon.py`.
- **Detection:** the pointer shows only after the paddle values change (`mouse_on`); until then
  buttons are ignored (a joystick's fire button is no click). **10 seconds** without use hides it
  (timing table: 500 / 600 frames); a click then only wakes it (`mouse_woke`, `mouse_ignore`).
- **Events:** presses become key events in the normal queue — `KEY_MOUSE_L`, `KEY_MOUSE_R`,
  `KEY_MOUSE_DRAG` ($42–$44) with the modifier keys held — and the place in `click_row` (0–24; $ff
  above the text, 25 below), `click_col`, `click_icon`. The editor (`.mouse` in `editor_key`) sends
  clicks through the same `.move` as the cursor keys, with `goto_click` as the move: so marking, the
  mark key and redrawing work exactly as with keys. A drag is a move with the mark key bits added, so
  it starts with `mark_here` (the character pressed on is marked, as with keys). Drag events come only
  when the pointer reaches another cell and the queue is empty; past the top or bottom of the text, one
  every 4 frames (`AUTOSCROLL`), moving the cursor a row further (the screen scrolls).
- **Right button:** `KEY_MOUSE_R` → `.menu` in editor_key → `menu_open`, like F1. In a menu it closes them all.
- **Test mailbox:** mouse events (dx, dy in pixels, buttons) replace the real mouse, one per frame, no
  acceleration; after the first one the buttons stay as the last event said (a drag can be sent in
  several goes). Holding the mark key during a click: the mouse is read before the keyboard, so the
  click must come a frame after the key event (test_phase7 writes both in one monitor stop).
- **VICE for Jim:** Settings → Input devices → Control port 1: **Mouse (1351)**; then **Alt+Q** (or
  Ctrl+M, depending on the VICE version) grabs the PC mouse, and again to let go.

## Text Model

- **Insert / overwrite mode, toggled with F7.** Default is **insert**: typing pushes following text right.
  In **overwrite** mode typing replaces the character under the cursor, except at the end of a line,
  where it inserts (never overwrite the CR). With a selection active, typing replaces the selection in
  either mode. INST/DEL and SHIFT + INST/DEL behave the same in both modes.
- **With text selected:** typing a character replaces the whole selection with that character, and
  INST/DEL deletes the selection (cursor lands where it started). SHIFT + INST/DEL also first deletes the
  selection. Any cursor move without the mark key clears the selection.
- **Color and RVS keys with text selected recolor the selection** (Jim, 2026-09-27; build in phase 5),
  so colors can be rearranged: e.g. mark a block, press CTRL-3, and all of it turns red.
  - Color key: remove every color code inside the selection, insert the new color code at the
    selection start, and at the selection end insert a code that brings back the color that was in
    effect there before (so the text after the selection keeps its look). Then clean up.
  - CTRL-9 / CTRL-0: the same with RVS ON / RVS OFF. A CR ends reverse, so for a selection over several
    lines RVS ON also goes after each CR inside it; at the end, restore the state that followed.
  - The selection stays marked afterwards, so a second color key simply changes it again.
- **Gap buffer.** Text stored internally as the **PETSCII stream** exactly as it appears in a file: one byte
  per character, lines ending in **CR ($0D)**, with color and reverse codes inline. Compact (1 byte/char).
- Convert PETSCII → screen codes only when drawing.
- **Selection highlight = reverse video** (Jim's choice): selected characters are drawn with screen code
  bit 7 flipped. Text color is untouched, so this works with any colors. Text that is already reversed
  shows normal inside a selection; the overwrite block cursor blinks to normal inside a selection. Accept both.

### Colors and Reverse (WYSIWYG, like the BASIC screen editor)

Jim wants colors and reverse text **shown, not displayed as quote-mode symbols**. Typing works like BASIC:
press CTRL-3 and the cursor turns red and the next characters typed are red.

**Codes are invisible.** Color codes, RVS ON ($12), and RVS OFF ($92) take no screen cell. The screen shows
their effect; the codes stay in the buffer and are saved in the file.

Rendering rules (same as printing the file with CHROUT):
- A color code sets the color of every following character until the next color code. Color carries
  across CRs. At the start of the document the color is the **default text color** (setting, light grey
  unless changed), RVS off. Changing the default text color recolors all text that comes before any color code.
- RVS ON / RVS OFF turn reverse on/off. **CR also turns reverse off**, as CHROUT does. (Kept on
  purpose: PETSCII files everywhere rely on it, so dropping it would show BBS files wrong and make
  our files look different elsewhere. Jim agreed, 2026-10-08.)
- Color codes: $05 white, $1C red, $1E green, $1F blue, $81 orange, $90 black, $95 brown, $96 light red,
  $97 dark grey, $98 grey, $99 light green, $9A light blue, $9B light grey, $9C purple, $9E yellow, $9F cyan.
- $8D (SHIFT-RETURN) is treated as a line end like CR.
- $0E / $8E (lowercase / uppercase switch): **a case code as the very first byte of a file is the
  document's character set**, not text: loading sets the display from it and drops it; saving writes one
  first (see Formats). Otherwise the first one found in the text sets the display character set and
  stays in the text, invisible.
- **All other control codes** (cursor moves, CLR, HOME, INST, DEL, bell, etc.) are kept in the buffer and
  saved, but are invisible and do nothing.
- Text in the same color as the background is invisible, exactly as in BASIC (e.g. CTRL-1 black on black).

The **state at the top of the screen** (color, RVS) must be known before drawing: scan backward from the
first visible character to the nearest color code (and to the line start for RVS). Cache this state and
update it as the view scrolls, so a full backward scan only happens after a jump (Find, page marker,
Load). With an REU-held document the scan may cross into REU memory.

Editing rules:
- **Cursor movement counts visible characters only**; it steps over invisible codes. The cursor always
  sits after any codes that come before the next visible character, so typed text takes the color in effect
  there.
- **Cursor color = the color in effect at the cursor**, like a word processor: move into blue text and the
  cursor turns blue. (Different from BASIC, where the typing color doesn't change as the cursor moves.)
- **Pressing a color key or RVS key** inserts that code at the cursor **plus a code that restores the
  previous state right after it**, with the cursor between them. Typed text goes in the new color; text
  after the cursor keeps its original look. Example: CTRL-3 in the middle of white text inserts
  `[RED][WHITE]` with the cursor between the two.
- **Clean-up:** when the cursor leaves, remove codes that have no effect: a color code followed directly by
  another color code, a color code equal to the color already in effect, an RVS ON directly followed by
  RVS OFF, and so on. This keeps files from filling up with unused codes.
- **RETURN in reversed text** (Jim, 2026-10-08): if reverse is on at the cursor and the line goes on
  after it, RETURN puts an **RVS ON after the new line end**, so the rest of the line moves down
  still reversed (at the start of a reversed line, or in the middle). At the end of a line nothing
  is added: reverse ends there, as in BASIC. DEL at the start of the moved line joins it back up and
  clean-up removes the RVS ON, which then does nothing. (`.return` in `type_char`, 28 bytes;
  checked in test_phase12.) Small leftover, accepted: at the start of a reversed line the line
  left above keeps its own RVS ON, so text typed there later comes out reversed.
- **INST/DEL** deletes the visible character left of the cursor; codes around it stay (then clean-up runs).
  Deleting a selection removes the codes inside it too, then fixes the state after it with a restore code
  if needed.
- **Overwrite mode** replaces the visible character only; codes are kept.
- **Copy / cut** stores the selection with its codes, prefixed by the color and RVS state at the selection
  start. **Paste** inserts it followed by a code that restores the state that was in effect at the paste
  point, so pasted text keeps its look and the text after it is unchanged.
- **Soft wrap** counts visible characters only.
- **Find** searches visible characters only, skipping codes, so a word containing a color change still matches.
- **Soft word wrap**, toggled from the menu. Display-only; never insert CRs into the file. **With wrap
  off, rows are cut at 40 characters, even in the middle of a word, like the BASIC screen. No sideways
  scrolling** (Jim, 2026-09-28; a first version scrolled long lines sideways, and he didn't want it).
- Clipboard in free buffer space (top-down), or in the REU when present.

**Undo (CTRL-Z), as built (phase 12, `src/undo.asm`; read its header first):**
- **What is noted:** every change to the text goes through `insert_byte`, `insert_after` (a byte
  in), `take_byte`, `delete_left`, `overwrite_next` (a byte out) and `cleanup` (codes tidied away).
  Each calls a hook first (`undo_ins`, `undo_del_here`, `undo_del_at`, `undo_run` /
  `undo_run_end`). The log is a list of entries "at document offset P, these A bytes were replaced
  by B bytes" (the A bytes, then a 7-byte header: P 3, A 2, B 2 — header last, so it is read
  from its end). A byte in or out inside or next to the last entry's text makes that entry
  longer, so a run of typing is one entry (no data), a cut is one entry with what went.
- **Actions** (`undo_start`, called from editor_key): a run of typing (`UK_TYPE`) or of INST/DEL
  (`UK_DEL`) goes on in one action; cut, paste, color/RVS keys, SHIFT+INST (`UK_OTHER`) and
  anything done to marked text start a new one. Every key first clears `undo_kind`
  (`undo_key_in`), so any other key ends a run — but codes `cleanup` removes when the cursor
  moves still go into the log (they belong to the text the action left; undoing puts them
  back, which is harmless).
- **CTRL-Z** (`undo_key`): the entries put back, last first — for each, the cursor to P
  (`move_gap_to`; a long document's window there first: `reu_goto`), the B bytes dropped, the A
  bytes inserted with `insert_byte` (recording off: `undo_on`). Then the log is empty: one undo,
  no redo. Nothing marked afterwards; the screen drawn with the cursor on its row.
- **Limits:** the log is 1 KB (`UNDO_SIZE`, taken from the top of the text buffer at start-up:
  `undo_base`/`undo_end`; `buf_top` lower by that much). An action that takes out more → "TOO BIG
  TO UNDO" (`undo_ok` = 0); inserting costs nothing, so a big paste can be undone. CLEAR ALL and
  loading empty the log ("NOTHING TO UNDO").
- Offsets are document offsets (window offset + `win_base` with a long document), so an undo
  works after the window has moved (test_phase11b: a page cut in the middle, SHIFT+F5 to the end,
  CTRL-Z).
- The hooks use `zp_ptr`/`zp_ptr2` (the IRQs only read zp_ptr), not `ptr`/`ptr2`, which the
  callers (paste's loop, cleanup) use.

**As built (phase 5, "Marked text" section of `src/editor.asm`):**
- **The character the cursor is on when marking starts is always marked** (Jim, 2026-09-28): going
  right it is the first marked character; going left the marking reaches to just after it
  (`sel_anchor_end`, set by `mark_here`). Not a line end: marking left from the end of a line does
  not take in the line end. **Phase 7: drag-marking with the mouse must start with `mark_here` too.**
- Marking = `sel_anchor` (offset) to the cursor. Movement keys with the mark key held extend it:
  cursor keys, F3/F5, and HOME **only when the mark key is C=** (SHIFT+HOME stays CLEAR ALL). While
  marking, the cursor's codes are not tidied (`no_cleanup`), so offsets stay put. A move without the
  mark key unmarks (full redraw); a marking move redraws only the rows between the old and new cursor
  rows (`redraw_stop`). Marked characters draw with bit 7 flipped; a marked line end shows as a
  reversed space.
- Every operation on marked text first moves the gap to its start (`sel_to_gap`), so the marked bytes
  lie right after the gap, then works through them there ("take" from after the gap, "insert" before
  it). Codes needed afterwards go just after the cursor (`restore_after`), unless codes there already
  set the same thing or nothing follows.
- **Clipboard at the top of the buffer:** `text_end` (zero page $1A) is the end of the text; the
  clipboard is `text_end`..`BUF_END`. Copying resizes it by moving the text after the gap. It survives
  Load and CLEAR ALL. `clip_color` / `clip_rvs` = the state at the start of what was copied.
- Recolor keeps the text marked (so a second color key simply changes it again) and puts the cursor
  back at the end it was at. RVS recolor adds RVS ON after each line end inside the marked text.
- After an operation on marked text the screen is redrawn with the cursor on the row it was on
  (`show_cursor_at`); CTRL-A puts the end of the text on the bottom row.
- CTRL-S first tidies the codes at the cursor (`leave_cursor`), so no codes without effect are saved.

**As built (phase 3, `src/editor.asm`; read its header comment first):**
- Gap buffer at **$4000–$CFFF** (36 KB), BASIC and KERNAL ROMs banked out. The editor itself runs at
  $E000 (see Memory Map).
- Zero page $08–$1B belongs to the editor (main program only, never the IRQs); it is listed in
  `main.asm` (so ACME knows it is zero page before the lower part uses it). `gap_start` ($08),
  `gap_end` ($0A) and `text_end` ($1A) are fixed addresses the test harness can read.
- Positions are kept as **offsets** (bytes from the start of the text, not counting the gap), so they
  stay valid when the cursor moves. `set_ptr` / `ptr_to_off` convert.
- For each screen row (plus one below the screen) the editor keeps its start offset, the color and RVS
  state there, and its number of cursor places.
- After an edit, the redraw **stops as soon as a row starts where it did before, moved by the size of
  the edit, in the same state** — the rest of the screen is unchanged. (This holds with word wrap too:
  a row's layout depends only on where it starts.)

**As built (phase 6, `src/editor.asm`; its header comment describes the rule):**
- **Word wrap on (default; `wrap_on`):** a row takes up to 40 characters; if the line goes on, the row
  ends after its last space ($20 only — shifted space $A0 does not break) and the next word starts the
  next row; a word longer than 40 is cut at 40. A line end needs a cursor place of its own, so a line of
  exactly 40 characters wraps its last word too. `redraw_from` (drawing) and `row_next` (walking one
  row without drawing) follow the same rule and **must be kept the same**; tools/test_phase6.py checks
  the screen against a Python model of it.
- **Decided against (Jim, 2026-10-07): hanging a space in the margin.** A word that ends exactly at
  column 39 still moves to the next row when a space follows it. "Hanging" that space (taking it into
  the full row without drawing it, so the next word starts at column 0) was assessed:
  - ~40–60 bytes under the KERNAL.
  - Changes to both layout routines and test_phase6's model.
  - A cursor quirk: on the hidden space the cursor would show at column 40, i.e. on the first
    character of the next row, so one CRSR RIGHT seems to do nothing.
  - An off-screen cursor on row 24.

  **Jim: not worth the space or the risk to this critical code.** Don't propose it again unless he
  asks.
- **Word wrap off:** a row is cut after 40 characters, even mid-word (the phase 3 rule). Rows never
  reach past column 39, so all columns fit in a byte.
- Word wrap is switched in the main menu (D); the document is redrawn when the menu closes, with the
  cursor on its row. (Phase 6's temporary CTRL-W is gone.)
- **Finding rows upward:** layout depends on where a paragraph starts, so `find_row_start` walks the
  paragraph from its start (`line_start`). `rows_back` (used for cursor up at the top, F3,
  show_cursor_at, big jumps) goes back a line at a time and notes the last 25 row starts in a ring, so
  each paragraph is walked once. After edits in word wrap mode the top row can start where a fresh
  layout wouldn't (a word could now fit on the hidden row above); scrolling up heals it.
- **Speed work (a 30 KB document of long paragraphs was the test):**
  - `color_count` counts the color codes in the text (kept by insert_byte/insert_after/take_byte/
    cleanup; `count_colors` after loading). With none, `color_before` answers at once. Before, finding
    the color at the top row scanned back through the whole document: 1–3 s per scroll.
  - `set_top_ptr` works the new top's color out from the old top row (`top_known`) and the codes in
    between. **Anything that changes text above the top row must clear `top_known`** (selection
    operations do, in `sel_to_gap`). **Phase 8: changing the default text color also makes
    row_color stale — clear top_known and redraw everything.**
  - `move_gap_to` and the block copies copy a page at a time (HOME to the top of 30 KB: 211 → 46
    frames). Drawing uses a 256-byte `scrcode` table instead of calling petscii_to_screen.
  - Scrolling one row (`view_down` / `view_up`) moves the screen and the row tables by a row and draws
    only the new row. view_up then lets redraw_from check (can_stop) that the old top still starts
    where the layout says, and redraws more if not.
  - Measured (debug, PAL, 30 KB of long paragraphs, frames): type a letter 1, cursor move 0, F5 12,
    F3 26, cursor up at the top 8–10, jump to the end 24, HOME to the top 46. A full screen of dense
    text takes about 8 frames to draw.
  - Still slow in a document with no RETURNs at all (one huge paragraph): every row search walks it
    from the start. Not handled; such files (e.g. ASCII with LF endings) get line ends in phase 10.
- Cursor blink runs from the **main loop** (not the IRQ), so it can never clash with a screen redraw.
  Blink period from the timing table.
- Color keys insert the new color code before the cursor and a restore code after it; typing goes in
  between. `cleanup` runs whenever the cursor leaves a place and removes codes without effect (and all
  color/RVS codes at the very end of the text).
- SHIFT+CLR asks "CLEAR ALL Y/N". `prompt_yes_no` draws the centered box, saves/restores what is
  under it, and shows capitals in either character set. (Until phase 8, RUN/STOP and RESTORE asked
  "QUIT Y/N"; now they open the menu, like F1.)
- HOME goes to the start of the logical line (not the screen row); again = top of the document.
- Debug mailbox additions: `+63` loads a test document placed in the buffer by the harness; `$02BF`
  holds how many frames the last key took.
- Track a "modified" flag; confirm before Load, Clear all, or Quit if unsaved.

## Menus and Prompts

### How menus work

- A **simple text menu box centered on the screen**, drawn with PETSCII box characters. Save and restore
  the characters and colors underneath.
- Items are lettered **A, B, C, …** in order, and **X is always Exit**. Press the letter to choose; mouse
  click on a line also chooses.
- **Setting items show their current value** and **cycle to the next value** each time they're chosen
  (e.g. `D WORDWRAP: ON` → `D WORDWRAP: OFF`).
- **X is Exit on every menu** and backs out one level. RUN/STOP and ← close all levels.
- Build menus from **data tables** (title, items, action / submenu / value list) so nesting costs little code.
- Opened by RUN/STOP, F1, or clicking the menu icon.
- Prompts (file name, disk command, "CLEAR ALL Y/N") use the same centered box. RUN/STOP always cancels.
- **A box that waits for any key does not say so** (Jim, 2026-09-29): no "ANY KEY" lines.

### Menu tree (Jim's design)

**MAGIC TYPEWRITER** (main menu)

| Key | Item | Values |
|---|---|---|
| A | Load → Load menu | |
| B | Save → Save menu | |
| C | Print → Print menu | |
| D | Wordwrap | **on**, off; also SHIFT-F7 |
| E | Mode | **insert**, overwrite (same as F7) |
| F | Mark key | **commodore**, left shift |
| G | Background | 16 C64 colors, default **black** |
| H | Text color | 16 C64 colors, default **light grey** |
| I | Stats → shows a stats box | |
| J | Save defaults (disk only) | |
| Q | Quit Magic Typewriter → back to BASIC | |
| X | Exit Menu | |

**LOAD**

| Key | Item | Values |
|---|---|---|
| A | Load | Asks for a file name. On tape, a blank name loads the next file found |
| B | Format | **magic** (v0.2; was petscii), petscii, ascii |
| C | Device | **8**, tape, 9, 10, 11, 12, 13, 14 |
| D | Disk directory | |
| E | Disk command | |
| X | Exit Menu | |

**SAVE**

| Key | Item | Values |
|---|---|---|
| A | Save | Asks for a file name (pre-fill the last one used) |
| B | Format | magic, petscii, ascii (see default below) |
| C | File type | **seq**, prg |
| D | Device | **8**, tape, 9, 10, 11, 12, 13, 14 |
| E | Disk directory | |
| F | Disk command | |
| X | Exit Menu | |

**PRINT**

| Key | Item | Values |
|---|---|---|
| A | Print | |
| B | Convert to ASCII | **no**, yes |
| C | Device | **4**, 5, 6, 7 |
| X | Exit Menu | |

Bold = default. "tape" is KERNAL device 1 (Datasette); the menu shows the word TAPE, not 1. Load and Save keep their own device and format settings, as the design shows them
separately. "magic" = the Magic Typewriter format (see Formats).

- **Save format default:** follows the format the document was loaded as, so a loaded BBS file is saved
  back as plain PETSCII. A new document (or after Clear all) defaults to **magic**.
- **Load:** whatever the Format setting, if the file starts with the Magic Typewriter signature it is loaded
  as magic and its settings applied.
- **Color items** show the color name (e.g. `G BACKGROUND: BLACK`) and step to the next of the 16 colors
  each time they're chosen. **No colors are skipped** (Jim, 2026-09-27): skipping the text color never
  protected the other colors a document uses, so the user simply steps on if the background hides some
  text. Same for SHIFT-F1. **Menus and prompts have a fixed color for each background** (Jim,
  2026-10-09): black on white, cyan, green, yellow, light red, grey, light green and light grey,
  light grey on the others (`readable_color` / `box_colors`). Before, they followed the text color,
  with black or white when it equaled the background.
- Settings last until the program exits, unless saved with **Save defaults**.

### Menu item behavior

- **Disk directory:** read `$` from the current device, show it a screenful at a time (any key = next
  page, RUN/STOP = back). Display only. Not available for tape — show a short message.
- **Disk command:** prompt for a command, send it on channel 15, and show the drive's reply. An empty
  command just reads and shows the drive status. Not available for tape.
- **Load** confirms before replacing an unsaved document. Load, Save, and Print show errors in a box.
- **Stats:** a box showing **characters, words, sentences, and free characters**. Count on demand when chosen.
  - Characters: visible characters plus line ends; invisible codes are not counted.
  - Words: runs of characters separated by space, CR, or shifted space.
  - Sentences: count `.` `!` `?` followed by a space, CR, or end of document (a run like `...` counts once).
  - Free characters: main RAM free space, plus free REU space when an REU holds the document (see REU).
  - Counts can exceed 65,535 with an REU: use **24-bit counters** and print up to 8 decimal digits.
  - Show "COUNTING..." if a large REU document takes more than a moment.
- **Save defaults (disk only):** write all settings to the config file **`MAGIC T DEFAULTS`** (SEQ) on the
  device the program was loaded from (scratch then write). Saves every setting, exactly the same list as the
  Magic Typewriter header. If the program was not
  loaded from a disk device (tape, cartridge, or unknown), show "DEFAULTS NEED A DISK" and do nothing.
- **Quit:** if modified, ask "QUIT WITHOUT SAVING Y/N". Then restore everything the program changed (IRQ and
  NMI vectors, $01 = $37, VIC registers, sprites off, borders closed, default colors), do a BASIC NEW (the text
  buffer overwrote BASIC memory), clear the screen, and return to BASIC's READY prompt.
  **As built (phase 6 start):** also puts back BASIC's zero page $02–$1B (copied at start-up); BASIC
  keeps values there between commands ($13 = I/O channel, $18 = string stack) and without them forgot
  the RETURN after a command and gave ?FORMULA TOO COMPLEX for `"A"+"B"`. Then NEW (`JSR $A644`) and
  BASIC's warm start (`JMP ($A002)`, as RUN/STOP+RESTORE), which resets the rest and prints READY.
  **v0.2 (Jim): Quit resets the C64 instead** (`quit` in main.asm: SEI, $01 = $37, `JMP ($FFFC)`):
  the reset puts VIC, CIAs, SID, vectors and BASIC back, and shows the power-up screen. It freed
  ~125 bytes. test_quit checks the power-up screen and a working BASIC after it.

### As built (phase 8, "Menus" section of `src/menu.asm`)

- **One fixed panel for every menu:** rows 0–24 (v0.2, for the key list; was 4–23, earlier 4–19),
  columns 5–34, so going from
  one menu to another only redraws the panel. Title, a line, then one row per item: letter, name and,
  for a setting, `: VALUE`. The document is drawn afresh when the menus close (`top_known` = 0,
  `show_cursor_at cur_row`), since a setting may have changed how it looks.
- **Closing keys:** X backs out one level; RUN/STOP, ←, RESTORE, F1, the right mouse button and a click
  on the menu icon close them all. A left click on an item's row inside the panel chooses it.
- **Menus are data tables** (layout in the comment at the top of the section): a title, then per item
  its letter (screen code), kind, name and "what". Kinds: `MI_MENU` (opens a submenu; up to 3 deep),
  `MI_SET` (steps a setting), `MI_RUN` (runs a job, then shows the menu again: Stats, Save defaults,
  directory, disk command), `MI_DO` (closes the menus, then runs a job: Load, Save, Print, Quit),
  `MI_EXIT`. A **setting** is: its variable, how many values, the values in stepping order, and a name
  for each (`set_fields` / `set_name` / `set_next`). Adding a setting = one table entry + its strings.
- Texts are `!scr` with lower-case letters; `box_print` shows them as capitals in either character set.
- **Not built yet** (say "NOT READY YET" via `not_yet` / `check_load` / `check_save`): Print (phase 11),
  tape (phase 11), formats other than PETSCII and the PRG file type (phase 10). The settings exist and
  step already. **The Save format is PETSCII for now**; the "follows the loaded format, magic for a new
  document" rule comes with the magic format in phase 10.
- **Stats** counts on demand (`count_text`) into 24-bit counters (`inc24`, `num24_text`, up to 8
  digits), numbers from column 14; free = the size of the gap, followed by its share of the whole
  36 KB buffer, e.g. `36833 (99%)` (`free_percent`; Jim asked for the %). No "COUNTING..." yet (only
  needed for REU documents, phase 9).
- **Disk directory** (`dir_load` / `dir_save`) runs in the plain disk display (between `io_begin` and
  `io_end`), a screenful at a time with "MORE" on the bottom row; keys come through the KERNAL there.
  **Gotcha:** GETIN reads from the current input channel, so the wait routine does CLRCHN before it and
  CHKIN again after — without that it read a byte of the directory as the key and ended at once.
  **Gotcha 2 (Jim's test):** the key that chose Disk directory is usually still down when the KERNAL's
  IRQ starts scanning, so the KERNAL collects it and the listing ended at once. The wait routine
  (`.let_go`) now waits until no key is held (`SFDX` $CB = 64) and empties the KERNAL buffer before
  waiting, and again before leaving (so RUN/STOP, still held, doesn't then close all the menus).
  The harness can't hold a real key; test_phase8 puts a key in the KERNAL buffer before choosing it.
- **Character set during disk work:** the KERNAL's own C= + SHIFT works while it reads the keyboard
  (Jim switched case to read the directory), so `io_begin` keeps $D018 and `io_end` puts it back.
- **Disk command** (`cmd_load` / `cmd_save`): a "COMMAND:" box (27 characters; an empty answer allowed,
  `input_empty_ok`), sent on channel 15; the drive's answer shows in a box.
- **Save defaults / start-up:** `MAGIC T DEFAULTS` holds the magic header only: `$00 "MTW" "1"`,
  `$40 + 13` (the number of settings), then 13 bytes of `$40 + value` in the order of `defaults_vars`
  in `src/fileio.asm` (background, text color, character set, wordwrap, mode, mark key, load format,
  load device, save format, save type, save device, print ASCII, print device), then CR. Written only
  to the device in $BA at start-up (`load_device`, 8–30), else "DEFAULTS NEED A DISK". `load_defaults`
  runs after `init_irq` and before `editor_init`, silently; reading the status clears a drive error.
- **Quit** (Q) asks "QUIT WITHOUT SAVING Y/N" if there are changes.
- **Scratch before writing** (`scratch_input`, used by Save and Save defaults): "01, FILES SCRATCHED"
  is the usual answer even when there was no file; "62, FILE NOT FOUND" is accepted too (VICE 2.4's
  host-folder drive answers that way).
- **File names with `*`, `?` or `,` can't be saved under** (`name_ok`): the scratch would take other
  files with it (`S0:SA*` = every file starting with SA, `S0:A,B` = A and B). Save shows "NO * ? OR ,
  IN A FILE NAME". Loading with a pattern works, but the pattern is not kept as the document's name
  (`keep_name`), so CTRL-S asks for one.

## Find (CTRL-F)

- CTRL-F opens a centered **"FIND:"** prompt (same box style as other prompts). The last search text is
  shown pre-filled; RETURN searches, RUN/STOP cancels.
- Search runs **forward from the cursor** and **wraps** to the top of the document once.
- On a match: move the cursor there, **select the match** (reverse-video highlight), and scroll so it's visible.
  The page marker updates with the new position.
- No match: show "NOT FOUND" briefly in the prompt box; cursor and document unchanged.
- **Find next:** CTRL-F then RETURN repeats the last search from just past the current match.
- **Case-insensitive by default** (treat the PETSCII letter ranges $41–$5A and $C1–$DA as equal).
  Searches match across soft-wrapped lines, since wrap is display-only. A search string may not contain CR.
- Keep the search string short (e.g. 32 characters) to save RAM.

**As built (phase 8, `src/find.asm`):** up to 26 characters (the box's width). With text marked, the
search starts just past the start of the marked text (usually the last match), else at the cursor.
A match is marked with the cursor at its end; if it is on the screen only the marking is drawn,
otherwise it is shown in the middle row. "NOT FOUND" stays in its box until a key is pressed.
The search walks the buffer with `(zp,X)` through `ptr` or `ptr2`, jumping the gap, and compares only
visible characters (CT_CHAR / CT_EOL in `ctype`); both $C1–$DA and $61–$7A fold to $41–$5A.

## File I/O

### Disk (devices 8–14)

**As built (phase 4, `src/fileio.asm`):**
- CTRL-S saves (asks for a name if the document has none; the Save menu's A is "save as").
  CLEAR ALL makes a new document with no name (so CTRL-S asks again).
  Load is in the Load menu (F1 A A; phase 4's temporary CTRL-L is gone); it asks "LOAD WITHOUT SAVING
  Y/N" first if there are changes. The name box ("LOAD:"/"SAVE:", `prompt_input` in `src/menu.asm`) shows the last
  name; RETURN accepts, RUN/STOP cancels, DEL rubs out.
- Channel 15 stays open while a file is in use; its status line is read after each step and any code
  of 20 or more is shown in a box as the drive sent it (e.g. "62, FILE NOT FOUND,00,00"). A drive that
  doesn't answer gives "DEVICE NOT PRESENT". A failed load leaves the document untouched (the status is
  checked before the buffer is emptied). RUN/STOP during the transfer gives "BREAK".
- **Plain display during disk access:** the KERNAL serial routines keep IRQs off for long stretches
  while they wait for the drive, which our exact-timed strip IRQs cannot survive (a late stable IRQ
  could even corrupt the stack). So `io_begin` stops our raster IRQs, lets the KERNAL's own timer IRQ
  run (its cursor blink off via BLNSW), closes the borders and hides the sprites; the text and a
  "LOADING"/"SAVING" box stay. `io_end` restores everything and empties the KERNAL key buffer.
  **Any new disk or printer code must use io_begin/io_end.** They also switch the KERNAL ROM in and
  out, so code between them must not touch `editor.asm` (see Memory Map, "the one rule").
- Loading reads the file to the start of the buffer, then moves it to the end in one copy
  (`gap_to_start`), so the cursor starts at the top. A file bigger than the buffer loads partly, with
  "TOO LONG: ONLY PART LOADED". A $0E / $8E as the file's first byte picks the character set and is
  not kept as text; without one, the first $0E / $8E in the text picks it (and stays); without any, the
  set on screen stays. Saving writes $0E (upper/lower) or $8E (upper/graphics) first, from $D018.
- Settings `load_dev` / `save_dev` / `load_format` / `save_format` / `save_type` / `print_ascii` /
  `print_dev` are at the top of `src/fileio.asm`; the Load, Save and Print menus step them.
- Test files in `test/` (made once and committed): `sample` (mixed case, $0E, colors, reverse, a long
  line), `upper` ($8E, graphics), `long` (60 lines). build.bat/build.sh put them on the .d64 as SEQ.

- KERNAL only: SETLFS, SETNAM, OPEN, CHKIN/CHKOUT, CHRIN/CHROUT, READST, CLOSE, CLRCHN.
- Read and show drive error channel (15) messages on failure.
- Saving over an existing file: **scratch then write**, not `@0:` (the 1541 save-with-replace bug).
- **File type SEQ:** open with `,S,W` / `,S,R`.
- **File type PRG:** open with `,P,W`; write the 2-byte load address first, then the text. **Changed
  (Jim, 2026-09-30): the load address is $4000, where the text goes** (was $0000), and loading uses
  KERNAL LOAD so fast loaders (Epyx FastLoad and the like; JiffyDOS speeds both kinds) speed it up.
  A stray `LOAD"FILE",8,1` now lands at $4000. (SpeedScript files are PRG by nature — see Formats.)

### Tape (device 1)

- **File type SEQ** → tape **data file**: OPEN 1,1,1,"NAME" to write (secondary address 1; 2 adds an
  end-of-tape marker, not needed), OPEN 1,1,0,"NAME" to read, then CHROUT/CHRIN as with disk.
- **File type PRG** (and SpeedScript) → tape **program file**: use KERNAL SAVE. The tape header must use
  the buffer's real memory address, so the $0000 rule for disk PRGs can't apply on tape. Use KERNAL LOAD
  with secondary address 0 to load into a buffer address we choose. Tape OPEN/CHRIN only reads data files.
  Then convert from the buffer as usual.
- Load with a blank file name takes the next file of the right kind on the tape.
- **The KERNAL tape routines take over interrupts and blank the screen for timing.** Before any tape
  operation: stop the raster IRQ chain, restore the KERNAL IRQ vector, hide the sprites. After it: restore
  our vectors, the IRQ chain, the screen, and sprites. Keyboard and mouse are paused meanwhile.
- The KERNAL's own "PRESS PLAY ON TAPE" messages only print in direct mode. Show our own prompt box
  ("PRESS PLAY ON TAPE" or "PRESS RECORD & PLAY ON TAPE"), then let the KERNAL wait for the button.
  RUN/STOP aborts; report "BREAK" or load errors in a box.
- Keep $01 banking (BASIC out) intact across tape calls; the KERNAL only touches the motor and sense bits.
- Testing: VICE can attach a `.tap` image for automated load/save checks. Real Datasette testing is a
  Human Test. Check which other target platforms support tape at all (see Target Platforms).

**As built (phase 11, `.tape` parts of `load_file` and `save_file`):**
- **Which kind of tape file (Jim agreed, 2026-09-30): the format decides, File type is ignored on
  tape.** Magic documents are **program files** (KERNAL SAVE / LOAD — tape turbos
  speed these up, and Jim wants magic always PRG); PETSCII and ASCII documents are **data files**
  (OPEN 1,1,1 / 1,1,0 and the same byte writer/reader as disk). The tape's LOAD skips data files
  and OPEN skips program files, so loading needs to know which to look for: Load format MAGIC →
  program file, PETSCII/ASCII → data file. A blank name (allowed on tape) takes the next such file.
- **Magic to tape:** KERNAL SAVE writes one piece of memory, so the gap goes to the start (the text
  all after it), the header and case code (21 bytes) go just below the text, and SAVE writes from
  there to `text_end` with secondary address 0 (a program that loads anywhere); then the cursor
  goes back (`move_gap_to`). Needs 21 free bytes ("not enough room" otherwise).
- **Magic from tape:** LOAD with secondary address 0 to BUF_START. **Set EAL ($AE/$AF) to BUF_START
  before LOAD** (`.eal_start`): on tape the KERNAL sets it only once it has found the file, so after
  RUN/STOP at PRESS PLAY it held an old address and the "partial load" looked like garbage (found in
  phase 11). If the file ran past `text_end`, the clipboard is gone (`text_end` = BUF_END). **Not
  guarded: a foreign tape program over 36 KB, or an absolute one (type 3, loads at its own address)
  — only possible with files not made here.** Jim, 2026-10-10: leave it so ("tape can be less
  forgiving"); a guard would need the tape header found and checked before LOAD (~40–60 bytes).
  Disk loads are guarded already: only a PRG at $4000 that fits goes by KERNAL LOAD, any other is
  read byte by byte into the buffer (Jim agreed no magic-header check is needed).
- Our own boxes: "PRESS PLAY ON TAPE" / "PRESS RECORD & PLAY ON TAPE" (with the spinner). The
  KERNAL waits for the button; RUN/STOP there → "BREAK", the document untouched.
- `read_status` knows tape has no drive to ask: it reports the KERNAL's status (short/long block,
  read or checksum error → "TAPE ERROR").
- Testing: VICE's datasette buttons can't be pressed through the binary monitor, and its tape traps
  don't skip the PRESS PLAY wait. test_phase11 checks the boxes and RUN/STOP at them (writing $7F to
  STKEY $91 and resuming in one monitor stop). **Real tape load/save is a Human Test.**

### Printer (devices 4–7)

- Open the printer with the KERNAL and send the document line by line, a line ending after each line.
- **Convert to ASCII = no:** send PETSCII for Commodore printers, CR line endings. Send RVS codes (most
  Commodore printers print reverse); drop color codes. Use **secondary address 7**
  (upper/lower case) when the upper/lower character set is active, 0 otherwise.
- **Convert to ASCII = yes:** apply the same PETSCII→ASCII conversion as saving, with CR+LF line endings, for
  printers or interfaces that expect ASCII.
- The printer does its own line wrapping; print long lines as they are stored.

**As built (phase 11, `print_doc` in `src/fileio.asm`):** OPEN with no name on the Print device and
secondary address 7 or 0 (0 for ASCII), CHKOUT (a missing printer fails here: "DEVICE NOT
PRESENT"), then `write_doc` with `out_mode` = OUT_PRINTER (`.printer`: characters, RVS on/off,
line end → RETURN; colors and other codes dropped) or OUT_ASCII (`.ascii`, as saving), and a last
line end (RETURN, or RETURN + LF). `write_doc` is the save code's text writer, shared (OUT_ASIS for
PETSCII/magic saves). Test: VICE's printer 4 with the raw driver writes what arrives to a file
(`-device4 1 -iecdevice4 -pr4drv raw -pr4output text -pr4txtdev 0 -prtxtdev1 <file>`).

**Also in phase 11 (Jim, 2026-09-30):**
- **Magic files are always PRG files** (`save_file`: `.prg` = File type PRG, or format magic).
- **A spinner while loading, saving and printing:** `busy_box` opens the box with room for it;
  `io_begin` points the KERNAL's IRQ vector at `io_irq`, which turns a quarter block ($7E, $7C, $6C,
  $7B: clockwise) every 8 ticks and then jumps to $EA31. Fast loaders usually keep interrupts off,
  so it may stand still during an Epyx fast load.
- **A setting fixed by other settings shows in [ ]** (Jim): `set_locked` (menu.asm) — only the
  File type: `[PRG]` for magic, `[SEQ]` for PETSCII/ASCII on tape; choosing it then does nothing,
  and the setting itself is kept for when it is free again. (Watch anonymous `+` labels in
  menu_open: a new one captured an older `bne +` there once.)
- **Upper case/graphics** while the disk directory shows (set after `io_begin`; `io_end` restores
  the document's set) and while the LOAD:/SAVE: name boxes are up (`prompt_name` wraps
  `prompt_input`). File names then look as they do on the disk.

## Formats

- **Magic Typewriter (magic):** a short header holding the document's settings, then the normal PETSCII
  text (colors and reverse included). Saved as SEQ or PRG like petscii; works on disk and tape.
  - Header: `$00` `M` `T` `W`, a version character, a header-length character, then one character per setting,
    then CR ($0D). Stores **every setting** (the same set as Save defaults): background, default text color,
    character set, wordwrap, mode, mark key, Load format and device, Save format, file type and device,
    Print convert-to-ASCII and device. Store devices as their number (tape = 1), each as `$40 + value`.
  - **Every header byte after the $00 is a harmless printable character:** store each number as `$40 + value`
    (`@`, `A`, … `O` for 0–15). $00 does nothing when printed. So TYPEing the file elsewhere shows at most a
    short line like `MTW1GAPAB…` and never fires control codes.
  - The length character lets later versions add settings; a reader skips settings it doesn't know and
    uses defaults for ones missing.
  - On load, apply the stored settings, then load the text. Unknown version → load the text, ignore settings.

- **PETSCII SEQ** (primary): load/save bytes as-is, colors and reverse included. **Plus the character
  set** (Jim, 2026-09-27): saving writes the standard PETSCII case code first — $0E for upper/lower,
  $8E for upper/graphics — so the file shows in the right set here and in other programs that print it
  (BBS files commonly start with $0E). Loading takes a case code in the first byte as the setting and
  does not keep it as text, so load/save round trips add nothing. (A program that reads the file as
  data, e.g. with INPUT#, sees that extra first byte.) For the magic format (phase 10) the header holds
  the character set too; decide then whether the text part also starts with the case code (it would
  make TYPEing the file show the right set).
- **ASCII SEQ**: swap upper/lower case ranges on load and save. On load, treat LF or CRLF as a line end.
  On save, write **CR+LF** (Jim's choice; no menu option). ASCII has no colors: drop color, RVS, and other
  control codes on save.
- **SpeedScript**: PRG of **screen codes** with a special character as the return marker. It keeps
  SpeedScript's own load address, not $0000.
  **Verify the return code and load address against real SpeedScript files before implementing.**
- Format chosen in the Load/Save menus; Load default magic (v0.2; was PETSCII), Save default magic (see Menus).
- Saving as plain PETSCII keeps colors but not the background or default text color; text with no color
  code will show in whatever color the reading program uses.
- Saving as ASCII or SpeedScript loses colors (and, for ASCII, reverse). If the document has any, warn:
  "COLORS WILL BE LOST Y/N".
- SpeedScript format is always a PRG; when the Save format is speedscript, ignore the File type setting.

**As built (phase 10, `src/fileio.asm`):**
- **Loading reads the file as it is** into the buffer, then `convert_loaded` makes it text in place
  (nothing gets longer, so writing never overtakes reading): a PRG's load address is off already
  (load_file read it, or KERNAL LOAD took it); a magic
  header ($00 "MTW" at the start) is recognized whatever the Load format says, its bytes go through
  `defaults_buf` and `doc_apply` (so a version other than "1" keeps its settings out), and the text starts after
  its RETURN; a case code first (magic and PETSCII) is the character set; then PETSCII/magic as is
  (the first $0E/$8E picks the set if nothing did), or ASCII converted (A–Z ↔ $C1–$DA, a–z ↔ $41–$5A,
  CR, LF or CR LF → CR, tab → space, other control codes dropped). **The Save format becomes the
  format loaded.**
- **Load format MAGIC skips the SEQ try** (Jim, 2026-10-09): magic files are always PRG files saved
  at $4000, so `load_file` goes straight to the PRG way (`.prg_way`: prg_fits, `name,P,R`, the load
  address, KERNAL LOAD). Why: **an SD2IEC opens a PRG as SEQ**, so the SEQ try succeeded and the
  manual was read byte by byte, without Epyx FastLoad (Jim, real C64 + SD2IEC/Epyx cartridge: the
  program 5 s, the manual 15 s). Measured in VICE (NTSC, 1541 true drive, the Epyx .crt from Jim's
  `G:\My Drive\retro computers 2\Projects\sd2iec cart\freeload\EPYX Fastload-531014.crt`): the
  manual 22 s without the cartridge, 7–8 s with it, either format (a 1541 always reaches the PRG way).
  With another Load format the SD2IEC still reads magic files byte by byte (the header check in
  `convert_start` keeps that right, only slow).
  **v0.2 - MAGIC is the default, and loads any file** (Jim's rules; `load_file`): `.prg_way` first;
  if the drive refuses (`.mismatch`: 64, or 62 from VICE's folder drive) `.seq_way` once (and the
  other formats, which start with `.seq_way`, try `.prg_way` once the same way). A PRG whose
  address isn't $4000: with MAGIC its 2 bytes are text (`.kept`; `.opened` puts them first, and
  ends there if READST said the file ended with them - a 2-byte file); with the other formats
  they are dropped as a load address, as before. On an SD2IEC a SEQ file opens as a PRG, so this
  is what keeps its text whole. `convert_start` reads MAGIC as PETSCII until the header says
  magic, so a file without the header sets the Save format to PETSCII. A plain SEQ file on a
  1541 costs one refused open (and the directory read for the size) before it loads. Tape is
  unchanged: with MAGIC it looks for program files only, so PETSCII data files need PETSCII. **VICE + Epyx:** start with `-cartcrt <crt>`;
  VICE's autostart then doesn't RUN the program (type RUN into the keyboard buffer). Time loads
  with CIA 1's TOD clock: the frame counter stops during disk work (our IRQs are off).
- **SEQ or PRG:** Load opens `name,S,R`; on "64, FILE TYPE MISMATCH" it is a PRG: it opens
  `name,P,R` and reads the load address itself. **Only a file with address $4000 (saved here) that
  fits** is then closed and loaded again with **KERNAL LOAD, secondary address 1** — to its own
  address, as `LOAD"NAME",8,1`, which every fast loader supports. (Secondary address 0 with our own
  target would also work with the real KERNAL, but some simple fast loaders put every relocated
  load at the start of BASIC, $0801: on top of Magic Typewriter. Jim asked whether the header up
  front mattered: it doesn't, LOAD copies the bytes as they are.) Our zero page $02–$1B is kept
  aside around LOAD (`zp_keep`) in case a fast loader borrows some. "Fits": `prg_fits` reads the
  size from the directory (`$:name`, secondary address 0, on its own `DIR_LFN` = 3: skip the load
  address, the first line's link, number and text; then the file's line: link, **blocks**, ≤ 254
  bytes each; **read before the PRG is opened** — found in 11b: a 1581 ended a file that was open
  while the directory was read after 2 blocks; the 1541 didn't mind) and compares with the room between BUF_START and the
  clipboard — KERNAL LOAD has no length limit, and past $CFFF lie the I/O chips. `SETMSG` 0 first;
  the end comes from `EAL` ($AE/$AF); if it got nowhere, the document is untouched. Everything else
  (other PRG files, too-big ones) is read on byte by byte from the open file (stops when full:
  "TOO LONG"). **That is also the way for long REU documents later: KERNAL LOAD can only fill main
  memory.** `load_fast` = 1 when KERNAL LOAD was used (for the tests). Save opens `,S,W` or `,P,W`
  (File type); a PRG starts with $00 $40.
- **Saving** (`save_file`): PRG address, then the magic header (made by `defaults_make` before
  `io_begin`: some settings live in the editor, hidden once the KERNAL ROM is in), then the case code
  (magic, PETSCII), then the text: as is, or ASCII (`.ascii`: the reverse mapping; a line end → CR LF;
  SHIFT-SPACE → space; graphics, colors, RVS and other codes left out). ASCII asks "COLORS WILL BE
  LOST Y/N" first if `has_codes` finds any color or RVS code.
- **The magic text part starts with the case code too** (decided in phase 10): TYPEing the file then
  shows the right character set, and loading treats it as for PETSCII files.
- **Save format for a new document:** `default_save_format` = the Save format after start-up
  (built-in **magic**, or the Save defaults file's); CLEAR ALL goes back to it.
- **What a magic document brings back (Jim, 2026-09-30): wordwrap, background, text color, Load
  format, Save format, File type** (`doc_settings` in fileio.asm; `doc_apply`). Its character set
  comes with the case code at the start of its text. The header still holds all 13 settings, the
  same layout as MAGIC T DEFAULTS (which applies them all); mode, mark key, devices and the Print
  settings stay as they are when a document loads.
## REU (optional)

- Detect by writing and reading back the address registers at $DF02–$DF05. Size by writing marker bytes
  to each 64 KB bank and checking for wrap-around.
- Uses: fast gap moves, large clipboard, and **documents larger than main RAM** (in scope, since Stats
  reports REU free space). Keep the whole document in the REU and page a window of it into the gap buffer
  in main RAM around the cursor. Document positions need **24-bit** offsets. Load, save, find, print,
  stats, and the page marker must all walk the full document, not just the window.
- DMA stalls the CPU and would delay raster IRQs: **split transfers into chunks** (timing table) or run
  them while the beam is in the text area.
- Undo is out of scope for now.

**As built (phase 9, first part; `src/reu.asm`, read its header first):**
- `detect_reu` at start-up (interrupts off, right after `detect_system`): two patterns written to and
  read back from $DF02–$DF05, then each bank's number stashed into its first byte from bank 255 down
  and read back from bank 0 up; the first bank without its own number is the size. `reu_banks` = 64 KB
  banks (16 MB counts as 255; fewer than 2 = none). Stats shows "REU  512 KB" when there is one.
- **Bank 0 = stopover for block copies, bank 1 = the clipboard.** `block_copy_fwd` / `block_copy_back`
  (editor) hand copies of 256 bytes or more to `reu_copy`: stash to bank 0, fetch to the new place
  (overlap doesn't matter). `gap_to_start` (after loading) now uses `block_copy_back` too.
- **Clipboard in the REU:** `copy_selection` stashes the marked text to bank 1 (`clip_size`); the buffer
  keeps no clipboard (`text_end` stays $D000), so the text gets the whole 36 KB. `paste` fetches it to
  the top of the gap (the room check guarantees 4 bytes to spare) and inserts from there as before.
- **IRQ safety (`reu_move`):** pieces of 128 bytes; each starts only when the raster (low 8 bits) is
  not within 8 lines before line 25, line 247 or a page marker line (`irq_mark_top/bot`). It **waits
  with interrupts on** (the first version waited with them mostly off and made IRQs late), confirms
  the beam has moved at most 2 lines since the check — first with interrupts on, then once more with
  them off (so the interrupts-off moment almost never fails and holds an IRQ up) — then starts the
  piece. (A too-long confirm, 4 subroutine calls, made most attempts start over: no faster than the
  CPU. Inline checks fixed that.)
  After a piece the REU's address registers point past it, so only the length is written each time.
- Debug builds count line 25/247 IRQs that start a line late or more in **`late_irqs`** (irq.asm),
  with the line of the last one in `late_line` and where the main program was in `late_pc`;
  test_phase9 requires 0. The check reads the line into Y at entry (4 cycles) and counts only
  after the second IRQ is set up (`late_check` macro, in the NOP wait), so it can't make things
  worse. **Found with it (2026-09-29): `marker_set` handed its values over with `php`/`sei`…`plp`
  (~30 cycles), and a line 25 IRQ due then started on line 26** — rare, since phase 6, harmless on
  its own. A first version of the debug check that did its work *before* setting up line 27 turned
  that into a missed line 27 IRQ and a crash (NTSC, "keys not handled"; `late_pc` pointed into
  marker_set). Now marker_set clears `marker_pending`, writes the values, sets it again — no `sei`.
  **Rule: the main program never turns interrupts off while our IRQs run** (only `reu_move`, for the
  moment of starting a piece, placed well away from the exact IRQs). The stress test (a scratch
  script) repeats test_phase9's editing 20 times on one system and reads `late_irqs` after every
  step; a hang catcher wrapped `Editor.keys` to dump PC/SP, the stack page and `late_pc` on a
  time-out. Rewrite them if needed.
- The harness reads REU memory (`mtest.reu_read()`: the clipboard, a long document's head and
  tail) through the gap, **by asking the editor to copy it**: debug builds have a request at
  `MB_DMA` ($02B4–$02BB: reu_c64, reu_addr, reu_bank, reu_len, then the command, written last),
  which `mailbox_poll` (main loop, idle) hands to `reu_move` and then clears. **Never start a big
  DMA from the monitor:** it stops the CPU for as many cycles as bytes, the exact-timed strip IRQs
  come far too late, and the editor hangs (found in 11b on NTSC; phase 9's one-piece clipboard
  read had the same risk). `MB_BUSY` ($02BE) is 1 while the main loop works on a key;
  `mtest.idle()` waits for 0 before any REU read. Measured (PAL, 20 KB of short lines): jump to the top 35 → 16 frames; the
  rest of the time is drawing.
**As built (phase 11b, long documents; `src/reudoc.asm`, read its header first):**
- **When:** an REU of 3 banks or more (192 KB; in VICE 256 KB and up). `reudoc_install` (start-up)
  copies reudoc.asm to $C000 and the text buffer ends there (`buf_top`, `text_end` = $C000): the
  **window**, 32 KB. With a smaller REU or none nothing changes: 36 KB, and $C000–$CFFF is text
  (Jim, 2026-09-29: same PRG, a stock C64 loses nothing).
- **Layout:** the window is the editor's ordinary gap buffer; the editor sees only it (all its
  offsets count from the window's start, document offset `win_base`, 24 bits). In the REU from
  bank 2 up: the **head** (the text before the window) as chunks, each a 6-byte header (the REU
  address of the chunk before it, its length, the color at its start) and up to 12 KB of text
  ending just after a RETURN, so the window starts at a line start, reverse off, in `win_color`
  ($FF = the default text color; `start_color` in reu.asm, used by color_before and empty_view);
  and the **tail** (the text after the window), one piece growing down from the REU's end
  (`tail_len`, 24 bits). Bank 0 is still the block-copy stopover, bank 1 the clipboard.
- **reu_keep** (main loop, after every key): 1. less than MARGIN (4 KB) before the cursor and a
  head: its last chunk comes back (room made by sending the window's end to the tail); 2. less
  than MARGIN after the cursor and a tail: up to 12 KB of it comes back (a head chunk goes out
  first if the gap can't spare it); 3. a gap under MIN_GAP (8 KB): text goes out from the side
  with more. Then the screen is drawn again with the cursor on its row. **A piece brought in must
  leave MIN_GAP free**, else rule 3 sends it straight back out (found: a 12 KB ping-pong, 120
  frames a key). A move costs ~80 frames (PAL; `count_colors` over the window ~35 of them,
  rewritten as a page loop — it took 135 before); other keys are as fast as ever.
- **Marked text stays inside the window:** a move that would cut it off is left out, and the
  marks' offsets move with the window (`.push`, `.pop`). Marking reaches ~20 KB.
- **RESERVE** (12 KB) stays free in the REU for moves that make its part bigger (loading, room for
  typing: `reu_room_grow`); a swap (head <-> tail) only needs `reu_room`. So going back to the
  start always works, even with the REU full.
- **Loading** (`load_spill`): when the window fills, what came so far is converted
  (`convert_start` / `convert_more`: convert_loaded works in pieces now, with a pending line feed
  for a RETURN/LF pair split between two fills) and 12 KB chunks go to the head until less than
  one is left; no room → "TOO LONG: ONLY PART LOADED". Then `reu_to_start` (every chunk back, the
  window's end to the tail, 8 KB room for typing). KERNAL LOAD (fast loaders) only for PRG files
  that fit the window (`prg_fits` against `text_end`); every load start clears the old REU part
  (`.reu_reset`).
- **Saving, printing, the ASCII colors check, Stats** go through `each_range` (fileio.asm): the
  whole text in order, a piece at a time to a routine (`write_range`, has_codes, count_text); the
  head's chunks and the tail come a page at a time through RD_PAGE ($CF00).
- **Find:** through the window; at its end `rd_slide` moves the window on (the place being tried
  stays); at the document's end `reu_to_start`; not found → the cursor back where it began
  (`rd_find_back`). About 60 cycles a byte.
- **Page marker:** `marker_long` makes update_marker's offsets document-wide and halves them
  together until they fit 16 bits.
- **HOME HOME:** `reu_to_start` (not while marking). **CTRL-A** and **magic to tape** (one piece
  of memory) need all of it in the window: `reu_all_in`, else "TOO LONG TO MARK ALL" / "TOO LONG:
  SAVE IT AS PETSCII". **Paste** bigger than the gap: `reu_room_for` makes room first.
- **Stats:** free = the gap + the REU between head and tail, less RESERVE; the % is of the window
  plus the REU's banks from 2 up.
- **A tape program** (magic) is loaded with KERNAL LOAD, which doesn't stop at $C000 (one saved
  without an REU may be 36 KB): reudoc.asm is stashed to bank 0 at $F000 first (`reudoc_copy`),
  fetched back if the file ran over it, and the text cut at $C000 ("TOO LONG").
- **Found in 11b — the one rule again:** `blk_count` (reu_copy's length) lived in editor.asm under
  the KERNAL; during a long load the copies read their length from the ROM (969 bytes), and the
  loaded text came out garbled after the first 13 KB. It is in reu.asm now. **Everything
  reudoc.asm uses during disk work must be in the lower part or in reudoc.asm.**
- **Limits (tell Jim):** marking ~20 KB at most; a line longer than 12 KB splits a chunk mid-line;
  Find and Stats walk every byte (roughly 10–20 s per MB); a window move takes ~1.6 s.

## Cartridge version (future idea)

Jim may want a cartridge version later, like an earlier 16K cartridge of his: Exomizer-compressed code
that a small loader copies (decompresses) into RAM and starts. The plan-D memory layout suits that:

- The loader decompresses the PRG image to $0801 and jumps to 2061; `copy_high` then works as usual
  (or Exomizer decompresses the editor straight to $E000). A cartridge takes over at reset before the
  KERNAL sets up RAM, I/O, vectors and the screen, so the loader must call those set-up routines first.
- While editing, `$01 = $35` hides any normal 8K or 16K cartridge completely.
- **Catch — a 16K cartridge that can't switch itself off** (EXROM and GAME wired low): its upper 8K
  (ROMH) shows at $A000–$BFFF whenever the KERNAL ROM is in, i.e. in disk mode (`$01 = $36`), in the
  middle of the text buffer. Loading still works (writes reach the RAM), but **saving reads the buffer**
  and would read the cartridge. Fix then: read buffer bytes with the ROMs briefly out (SEI ... CLI), or
  copy through a small buffer in low memory — so keep the disk code's buffer reads in one place. Also
  there is **no BASIC** with such a cartridge (ROMH replaces it), so Quit needs another ending (reset).
- A cartridge that can switch itself off (Magic Desk / Ocean / EasyFlash types, register at $DE00;
  the Ultimate can emulate them) avoids both: switch it off after copying, and everything works as the
  disk version. Quit would then need BASIC's cold start (the cartridge skipped it).
- RESTORE is safe: our NMI trap never reaches the KERNAL's check that jumps into a cartridge.
- Size: ~20 KB finished, ~11–13 KB after Exomizer, so a 16K cartridge with room for the loader.
- VICE's `cartconv` makes a .crt image for testing. The settings file needs a disk: a cartridge start
  (no $BA device) uses the built-in defaults, as already specified.

## Build Order

Each phase passes automated VICE checks (PAL and NTSC), then a Human Test with Jim.

1. System detect + IRQ chain: open top/bottom borders, color splits, 6 sprites from the mockup,
   border-color marker at a fake position. Debug test mailbox. **Done 2026-09-27**, including the
   side-border badges.
2. Keyboard scanner: both SHIFTs, CTRL, C=, RUN/STOP, ←, key repeat, NMI trap. **Done 2026-09-27.**
3. Gap buffer, typing, flashing cursor (both shapes, F7 toggle), colors and reverse (rendering, color
   keys, restore codes, clean-up), INST/DEL and SHIFT-INST, RETURN, cursor movement, redraw,
   SHIFT-CLR "CLEAR ALL Y/N". **Done 2026-09-27.**
4. PETSCII SEQ load/save with device number and error channel. **Done 2026-09-27.**
5. Selection (mark key: left SHIFT or C=) and cut/copy/paste; color and RVS keys recolor a selection.
   **Done 2026-09-28.**
6. Soft word wrap (off = rows cut at 40), marker tracking the real position. **Done 2026-09-28**,
   with the memory change and speed work.
7. 1351 mouse: detection, box pointer, 10-second hide, click-to-cell, drag-select, icon clicks.
   **Done 2026-09-28** (tested by Jim in VICE 2.4; real hardware still to test).
8. Menus and prompts (lettered, nested, table-driven), Disk directory, Disk command, mark-key option,
   background and text color options, Save defaults and startup config loading,
   Stats, Quit, then CTRL-F Find. **Done 2026-09-29.**
9. REU detection, fast moves, clipboard. **Done 2026-09-29.** (Large documents held in the REU moved
   to 11b.)
10. Magic Typewriter format, ASCII, then SpeedScript import/export; PRG file type. (Magic, ASCII and
    PRG done 2026-09-30; SpeedScript skipped for now, Jim may want it later.)
11. Print menu, then tape load/save (device 1). **Done 2026-09-30** (real tape and printer still to
    try).
11b. Long documents held in the REU (same PRG; the REU code's RAM is document space without an REU).
    **Done 2026-10-01.**
12. Test pass on every target platform.

## Open Questions

- Pasting color codes from a loaded BBS file can include cursor-move or CLR codes. They are invisible and
  harmless here, but will take effect if the file is later printed to screen. Leave as is?
- Find: add Replace later? Case-sensitive option?
- SpeedScript return marker and load address (check real files) — skipped for now (Jim, 2026-09-30).
- Emulator arrow keys: VICE and some modern keyboards fake SHIFT + CRSR for Up/Left. **VICE, as tested by
  Jim (phase 5):** PC Up alone = CRSR DOWN + a *virtual right* SHIFT (`!VSHIFT RSHIFT` in every VICE 3.9
  keymap) = cursor up, as designed. But VICE only adds that virtual SHIFT when no SHIFT is held: **PC Left
  Shift + Up arrives as left SHIFT + CRSR DOWN — the same as Shift + Down — so it marks downward**, and the
  editor cannot tell them apart. Two SHIFTs + Down/Right would work but Jim found it awkward, so
  **decided: the mark key defaults to C=** (**Tab** in VICE: Tab + any arrow marks correctly); left SHIFT
  stays a menu choice for real keyboards, with a note in the user instructions that it can't mark
  up/left in VICE. Still check TheC64, MEGA65 and the BlingBox in phase 12.
- SHIFT LOCK engages left SHIFT, so it forces marking. Document this in the user notes.
