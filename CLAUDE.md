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
- **Phase 8 (menus, Stats, Save defaults, disk directory/command, Find):** passes the automated checks
  (2026-09-28); waiting for Jim's Human Test. Work is on branch `phase8`; merge into `main` when Jim
  accepts it. The temporary keys CTRL-L (load) and CTRL-W (wrap) are gone; the menus do both now.
- **Memory:** ~2.1 KB left below the sprite blocks and ~1.1 KB under the KERNAL for phases 9–11
  (see Memory Map). Watch it.

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
  - **REU can't be switched this way** (`REU` is not an allowed prefix). For REU tests, add
    `"VICE_ARGS": "-reu -reusize 512"` to `.mcp.json` and restart. Sort this out in phase 9.
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
- **VICE's 1351 (from its source, phase 7):** POTX/POTY = `(counter AND $7F) + $40`, plus a random 0/1;
  the counter only moves when the program reads a POT register (`mouse_poll()` is called then, at most
  once per 512 cycles), walking toward the host mouse position. A read within 512 cycles of a change of
  $DC00 bits 6-7 returns a random value. Start VICE with `-controlport1device 3` for a 1351 in port 1.
- **VICE 3.9 (GTK) on Jim's laptop: the grabbed mouse only ever moves right/down**, fast, whatever the
  real direction (seen in recordings of the paddle values; the Windows "high DPI" compatibility setting
  did not help). **VICE 2.4 works** (Jim still likes 2.4's menus). Test the mouse in 2.4, on his desktop
  PC, or on real hardware.
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
`python tools/test_quit.py [c64|ntsc]` (RESTORE, and a healthy BASIC after Quit),
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
- **Single small PRG.** Target roughly 6–10 KB before compression. Optional Exomizer crunch for release.
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
- Optional: **Exomizer** for the release PRG.
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
src/find.asm        CTRL-F Find
src/data.asm        sprite data, menu strings, tables
test/               sample SEQ, ASCII, and SpeedScript files
build.bat           assemble + make d64 (Windows)
build.sh            same steps (Linux)
```

## Memory Map

**As built (2026-09-27, "plan D", Jim's choice):** the editor's code runs in the RAM under the KERNAL
ROM, so the text buffer keeps the full 36 KB on a stock C64.

| Address | What |
|---|---|
| $02–$1B | zero page (list in `src/main.asm`); BASIC's too: start-up copies it, Quit puts it back |
| $02C0–$02FE | debug test mailbox (debug builds only) |
| $0400–$07FF | screen |
| $0801– | the lower part of the program: start-up, IRQs, keyboard, boxes, disk, data; then the stored copy of the editor |
| after the lower part | run-time tables (ctype, per-row arrays, prompt save area), **over the stored copy** once it is copied |
| $3E80–$3FFF | sprite blocks 250–255 (**$3FFF must be $00**: the idle-graphics byte drawn in the opened borders) |
| $4000–$CFFF | text buffer (36 KB), clipboard at its top |
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
- Space (debug build, end of phase 8): lower part $0801–$31B3, tables to $364D (debug builds add a
  256-byte mouse trace); editor $E000–$FB80, so **~1.1 KB free under the KERNAL and ~2.1 KB below the
  sprite blocks**. Phase 8 took about 3.7 KB. Phases 9–11 (REU, formats, printer, tape) must fit in
  what is left: keep them lean, and tell Jim early if they won't. New code goes in the lower
  part from now on; code that runs during disk work must
  go in the lower part anyway.
- **Quit ends with a BASIC NEW** (the tables overwrite the stored copy, so RUN would crash) and BASIC's
  warm start. Restarting means loading the program again. (`SYS 2061` after Quit would crash too.)
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
| Text background (default; menu option and SHIFT-F7 change it) | Black (0) |
| Default text color (menu option; also the menu/prompt text color; the document can change text color with color codes) | Light grey (15) |
| Border icon sprites | Light blue (14) |
| Mouse pointer sprite | Red (2) |

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

Six hardware sprites, no multiplexer, all hi-res. Border icons (1–5) are light blue (14); pointer red (2).

| Sprite | Use | Click action |
|---|---|---|
| 0 | Mouse pointer (highest priority) | — |
| 1 | Menu icon "≡F1" | Open menu (same as F1 / RUN/STOP) |
| 2 | Top-left "F3" badge | Page up |
| 3 | Top-right "F3" badge (same image as 2) | Page up |
| 4 | Bottom-left "F5" badge | Page down |
| 5 | Bottom-right "F5" badge (same image as 4) | Page down |

Sprite 2/3 data (24×13, "F3", points up):
```
...........XX...........   $00,$18,$00
.........XXXXXX.........   $00,$7E,$00
.......XXX....XXX.......   $01,$C3,$80
.....XXX........XXX.....   $07,$00,$E0
...XXX............XXX...   $1C,$00,$38
.XXX...XXXX..XXX....XXX.   $71,$E7,$0E
XX.....XX...XX.XX.....XX   $C1,$8D,$83
XX.....XX......XX.....XX   $C1,$81,$83
XX.....XXX....XX......XX   $C1,$C3,$03
XX.....XX......XX.....XX   $C1,$81,$83
XX.....XX...XX.XX.....XX   $C1,$8D,$83
XX.....XX....XXX......XX   $C1,$87,$03
XX....................XX   $C0,$00,$03
```
Sprite 4/5 data (24×13, "F5", points down):
```
XX....................XX   $C0,$00,$03
XX.....XXXX.XXXXX.....XX   $C1,$EF,$83
XX.....XX...XX........XX   $C1,$8C,$03
XX.....XX...XXXX......XX   $C1,$8F,$03
XX.....XXX.....XX.....XX   $C1,$C1,$83
XX.....XX......XX.....XX   $C1,$81,$83
XX.....XX...XX.XX.....XX   $C1,$8D,$83
.XXX...XX....XXX....XXX.   $71,$87,$0E
...XXX............XXX...   $1C,$00,$38
.....XXX........XXX.....   $07,$00,$E0
.......XXX....XXX.......   $01,$C3,$80
.........XXXXXX.........   $00,$7E,$00
...........XX...........   $00,$18,$00
```
Sprite 1 data (23×7, "≡F1"):
```
XXXXXXXX..XXXX..XX......   $FF,$3C,$C0
..........XX...XXX......   $00,$31,$C0
..........XX....XX......   $00,$30,$C0
XXXXXXXX..XXX...XX......   $FF,$38,$C0
..........XX....XX......   $00,$30,$C0
..........XX....XX......   $00,$30,$C0
XXXXXXXX..XX...XXXX.....   $FF,$31,$E0
```
Store only the rows above (13×3 or 7×3 bytes); expand into 64-byte sprite blocks at init and zero the rest.

**Decided (2026-09-27):** the badges sit in the side borders, as in Jim's mockup. (Branch `phase1`
keeps the earlier layout, with the badges above/below the text area.)

Vertical placement (same on PAL and NTSC), as raster lines:
- Top badges: raster 37–49 (the mockup has 38–50, touching the text area; see below).
- Menu icon: raster 42–48 (same as the mockup).
- Bottom badges: raster 252–264 (the mockup has 251–263).

Why one line away from the text area: showing a sprite in the right border of line 50 means opening
that border, and that also opens the **left** border of line 51, the first text line. There the VIC
shows the text background ($D021, black) instead of the dark grey side color, and line 51 is a
badline, so the CPU can't change the color in time. Same at the bottom with line 250. Matching the
mockup exactly would need two more sprites (6 and 7) as dark grey patches over those two spots.

Found in phase 1 (VICE): a sprite's first row shows on raster line **Y+1**, and the VIC always fetches
all **21 rows** of a sprite, stealing CPU cycles at the end of each of those lines. The top badges and
the menu icon share the same 21 fetched lines (29–49, Y = 28), with their pictures low in their blocks
(badges rows 8–20, icon rows 13–19), so every line of the top strip loses the same cycles and the line
50/51 color split has no sprite fetches. The bottom badges use rows 0–12 with Y = 251. Also, the VIC
compares sprite Y with only the low 8 bits of the raster line, so on PAL the top sprites would appear
again at line 256+Y; sprites 1–3 are switched off after the bottom strip and back on at line 10.
- **NTSC caution:** some NTSC TVs start showing around raster 41, so the top badges' 3-row tip may be
  cut off there. Check on a real NTSC TV.

**Horizontal placement (as in the mockup):**
- Left badges (sprites 2 and 4): X = 0, in the left border, touching the text area (X = 24).
- Right badges (sprites 3 and 5): X = 344, in the right border, touching the text area. X > 255, so
  set their bits in the sprite X MSB register $D010.
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
  (No F2/F4/F6 functions.)
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
| F7 | Toggle insert / overwrite mode (cursor changes shape) |
| SHIFT-F7 (F8) | Next text background color (same as the menu item) |
| C= + SHIFT | Toggle upper/graphics ↔ upper/lower character set, like BASIC |
| HOME | Start of line; press again = top of document |
| SHIFT + CLR/HOME | Prompt **"CLEAR ALL Y/N"**; Y clears the whole document, N or RUN/STOP cancels |
| INST/DEL | Delete the character left of the cursor; cursor and all following text move back one space. At line start, joins with the previous line |
| SHIFT + INST/DEL | Insert a space at the cursor; cursor stays put |
| CTRL-X / C / V | Cut / copy / paste |
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
- **Pointer:** hi-res sprite, **red (2)**, shown as the red box in the mockup. Shape: 8×8 box outline. Top and bottom edges 1 pixel thick; left and right edges 2 pixels wide:
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
  Moved on past the text, it **hides and the border icon under it turns red** (the pointer's color);
  a click then works that icon: F3 badges page up, F5 badges page down (with the mark key held: marking
  by page), the menu icon opens the menu. Hit zones in the strips (box left
  edge x): left badges x < 20, right badges x >= 340, menu icon (top only) 20 <= x < 60.
- The box's top line stays within **52–242** (not 51 or 250: its fetches must stay within lines 52–249,
  clear of the line 50 split, the line 249 stable check and the strips). From line 229 it uses a second
  picture low in its block (block 254, rows 13–20; `spr_pointer_low`), so the fetches run above the box.
  So on the top and bottom text rows the box sits one line off the cell; it still picks that cell.
- **Reading: three times a frame** (`mouse_sample`: at line 10, in the housekeeping just before
  `scan_keyboard`, and at the end of the bottom strip IRQ — after it has set the line 10 IRQ, since on
  NTSC it ends near line 7). Each reading adds its move to `mouse_acc_x/y` (the 1351 manual's method,
  `pot_delta`). Why three: one reading can only tell 63 steps apart either way, and VICE's 1351 moved
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
- RVS ON / RVS OFF turn reverse on/off. **CR also turns reverse off**, as CHROUT does.
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

### Menu tree (Jim's design)

**MAGIC TYPEWRITER** (main menu)

| Key | Item | Values |
|---|---|---|
| A | Load → Load menu | |
| B | Save → Save menu | |
| C | Print → Print menu | |
| D | Wordwrap | **on**, off |
| E | Mode | **insert**, overwrite (same as F7) |
| F | Mark key | **commodore**, left shift |
| G | Background | 16 C64 colors, default **black**; also SHIFT-F7 |
| H | Text color | 16 C64 colors, default **light grey**; also the menu text color |
| I | Stats → shows a stats box | |
| J | Save defaults (disk only) | |
| Q | Quit → back to BASIC | |
| X | Exit | |

**LOAD**

| Key | Item | Values |
|---|---|---|
| A | Load | Asks for a file name. On tape, a blank name loads the next file found |
| B | Format | magic, **petscii**, ascii, speedscript |
| C | Device | **8**, tape, 9, 10, 11, 12, 13, 14 |
| D | Disk directory | |
| E | Disk command | |
| X | Exit | |

**SAVE**

| Key | Item | Values |
|---|---|---|
| A | Save | Asks for a file name (pre-fill the last one used) |
| B | Format | magic, petscii, ascii, speedscript (see default below) |
| C | File type | **seq**, prg |
| D | Device | **8**, tape, 9, 10, 11, 12, 13, 14 |
| E | Disk directory | |
| F | Disk command | |
| X | Exit | |

**PRINT**

| Key | Item | Values |
|---|---|---|
| A | Print | |
| B | Convert to ASCII | **no**, yes |
| C | Device | **4**, 5, 6, 7 |
| X | Exit | |

Bold = default. "tape" is KERNAL device 1 (Datasette); the menu shows the word TAPE, not 1. Load and Save keep their own device and format settings, as the design shows them
separately. "magic" = the Magic Typewriter format (see Formats).

- **Save format default:** follows the format the document was loaded as, so a loaded BBS file is saved
  back as plain PETSCII. A new document (or after Clear all) defaults to **magic**.
- **Load:** whatever the Format setting, if the file starts with the Magic Typewriter signature it is loaded
  as magic and its settings applied.
- **Color items** show the color name (e.g. `G BACKGROUND: BLACK`) and step to the next of the 16 colors
  each time they're chosen. **No colors are skipped** (Jim, 2026-09-27): skipping the text color never
  protected the other colors a document uses, so the user simply steps on if the background hides some
  text. Same for SHIFT-F7. To keep menus and prompts readable, they are drawn in the default text color
  unless it equals the background; then in black or white, whichever reads better on that background
  (`readable_color` / `contrast_color`).
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

### As built (phase 8, "Menus" section of `src/menu.asm`)

- **One fixed panel for every menu:** rows 4–19, columns 5–34 (the main menu's size), so going from
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
  digits); free = the size of the gap. No "COUNTING..." yet (only needed for REU documents, phase 9).
- **Disk directory** (`dir_load` / `dir_save`) runs in the plain disk display (between `io_begin` and
  `io_end`), a screenful at a time with "MORE" on the bottom row; keys come through the KERNAL there.
  **Gotcha:** GETIN reads from the current input channel, so the wait routine does CLRCHN before it and
  CHKIN again after — without that it read a byte of the directory as the key and ended at once.
- **Disk command** (`cmd_load` / `cmd_save`): a "COMMAND:" box (27 characters; an empty answer allowed,
  `input_empty_ok`), sent on channel 15; the drive's answer shows in a box.
- **Save defaults / start-up:** `MAGIC T DEFAULTS` holds the magic header only: `$00 "MTW" "1"`,
  `$40 + 13` (the number of settings), then 13 bytes of `$40 + value` in the order of `defaults_vars`
  in `src/fileio.asm` (background, text color, character set, wordwrap, mode, mark key, load format,
  load device, save format, save type, save device, print ASCII, print device), then CR. Written only
  to the device in $BA at start-up (`load_device`, 8–30), else "DEFAULTS NEED A DISK". `load_defaults`
  runs after `init_irq` and before `editor_init`, silently; reading the status clears a drive error.
- **Quit** (Q) asks "QUIT WITHOUT SAVING Y/N" if there are changes.

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
- **File type PRG:** open with `,P,W`; write the 2-byte load address **$0000** first, then the text. $0000
  is deliberately invalid, marking the file as data, not a program. When loading a PRG, skip the first 2 bytes.
  (Anyone doing `LOAD"FILE",8,1` will overwrite zero page and crash the machine. That is expected.) (SpeedScript files are PRG by nature — see Formats.)

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

### Printer (devices 4–7)

- Open the printer with the KERNAL and send the document line by line, a line ending after each line.
- **Convert to ASCII = no:** send PETSCII for Commodore printers, CR line endings. Send RVS codes (most
  Commodore printers print reverse); drop color codes. Use **secondary address 7**
  (upper/lower case) when the upper/lower character set is active, 0 otherwise.
- **Convert to ASCII = yes:** apply the same PETSCII→ASCII conversion as saving, with CR+LF line endings, for
  printers or interfaces that expect ASCII.
- The printer does its own line wrapping; print long lines as they are stored.

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
- Format chosen in the Load/Save menus; default PETSCII.
- Saving as plain PETSCII keeps colors but not the background or default text color; text with no color
  code will show in whatever color the reading program uses.
- Saving as ASCII or SpeedScript loses colors (and, for ASCII, reverse). If the document has any, warn:
  "COLORS WILL BE LOST Y/N".
- SpeedScript format is always a PRG; when the Save format is speedscript, ignore the File type setting.

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
   Stats, Quit, then CTRL-F Find. (Automated checks passed 2026-09-28; Human Test pending.)
9. REU detection, fast moves, clipboard, then large documents held in the REU.
10. Magic Typewriter format, ASCII, then SpeedScript import/export; PRG file type.
11. Print menu, then tape load/save (device 1).
12. Test pass on every target platform.

## Open Questions

- Pasting color codes from a loaded BBS file can include cursor-move or CLR codes. They are invisible and
  harmless here, but will take effect if the file is later printed to screen. Leave as is?
- Find: add Replace later? Case-sensitive option?
- SpeedScript return marker and load address (check real files).
- Emulator arrow keys: VICE and some modern keyboards fake SHIFT + CRSR for Up/Left. **VICE, as tested by
  Jim (phase 5):** PC Up alone = CRSR DOWN + a *virtual right* SHIFT (`!VSHIFT RSHIFT` in every VICE 3.9
  keymap) = cursor up, as designed. But VICE only adds that virtual SHIFT when no SHIFT is held: **PC Left
  Shift + Up arrives as left SHIFT + CRSR DOWN — the same as Shift + Down — so it marks downward**, and the
  editor cannot tell them apart. Two SHIFTs + Down/Right would work but Jim found it awkward, so
  **decided: the mark key defaults to C=** (**Tab** in VICE: Tab + any arrow marks correctly); left SHIFT
  stays a menu choice for real keyboards, with a note in the user instructions that it can't mark
  up/left in VICE. Still check TheC64, MEGA65 and the BlingBox in phase 12.
- SHIFT LOCK engages left SHIFT, so it forces marking. Document this in the user notes.
