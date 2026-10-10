"""Phase 12: changes after Jim's tests on real hardware.
- Load/Save Format: MAGIC, PETSCII, ASCII (SpeedScript gone)
- the main menu shows the CTRL keys at its foot
- SHIFT + F3 / F5: the top / the end of the document (with the mark key:
  marking all the way)
- SHIFT + F7: word wrap on/off; SHIFT + F1: the next color for what is
  typed next (like a color key)
- a PRG of ours read as a SEQ file (an SD2IEC opens a PRG whatever type is
  asked for): its load address is not text
- VICE's file system drive answers 62 for a SEQ open of a PRG: then the
  PRG way is tried
Run from the project folder:  python tools/test_phase12.py [c64|ntsc]
Needs a debug build and the .d64 (build.bat)."""
import sys, os, time, shutil, subprocess
from mtest import *

model = sys.argv[1] if len(sys.argv) > 1 else "c64"
C1541 = r"C:/bin/GTK3VICE-3.9-win64/GTK3VICE-3.9-win64/bin/c1541.exe"
PRG = os.path.join(PROJ, "build/magictypewriter.prg")
CR = b"\r"
ok = True
def check(name, cond, info=""):
    global ok
    print(("PASS " if cond else "FAIL ") + name + ("" if cond else "  " + repr(info)[:300]))
    ok = ok and cond

def v(e, name, n=1):
    return int.from_bytes(e.peek(e.lab[name], n), "little")

def rows(e):
    return [r.upper() for r in e.screen_rows()]

def key(e, name, mods=0, settle=0.4):
    e.keys([(KEY[name], mods)], settle=settle)

def load_doc(e, doc):
    te = int.from_bytes(e.peek(0x1a, 2), "little")
    e.m.write(te - len(doc), doc)
    e.m.write(0x08, (0x4000).to_bytes(2, "little") + (te - len(doc)).to_bytes(2, "little"))
    e.m.write(MB + 63, [1])
    e.m.resume()
    for _ in range(50):
        if e.peek(MB + 63)[0] == 0:
            break
        time.sleep(0.1)
    time.sleep(0.5)

def load(e, name):
    e.poke(e.lab["modified"], [1])
    key(e, "F1"); key(e, "A"); key(e, "A")
    if "WITHOUT SAVING" in rows(e)[12]:
        key(e, "Y")
    e.keys([(KEY["DEL"], 0)] * 16)
    e.type_text(name)
    key(e, "RETURN", settle=0.5)
    t0 = time.time()
    while v(e, "modified") and time.time() - t0 < 60:
        time.sleep(0.3)
    time.sleep(1)

manual = open(os.path.join(PROJ, "test", "manual.prg"), "rb").read()
manual_text = manual[2 + 20 + 1:]               # (load address, header, case code)

# A disk with the manual's bytes as a SEQ file: what an SD2IEC hands over
# when a PRG is opened as SEQ
disk = os.path.join(WORK, "p12.d64")
shutil.copy(os.path.join(PROJ, "build/magictypewriter.d64"), disk)
subprocess.run([C1541, "-attach", disk, "-write", os.path.join(PROJ, "test", "manual.prg"), "manseq,s"],
               capture_output=True)

vice = start_vice(PRG, disk=disk, model=model)
try:
    e = Editor(Mon())
    e.wait_ready()

    # The Format setting: three values, no SpeedScript
    key(e, "F1"); key(e, "A")
    seen = []
    for _ in range(4):
        seen.append(v(e, "load_format"))
        key(e, "B")
    check("Load format steps MAGIC, PETSCII, ASCII and round (%s)" % seen,
          sorted(set(seen)) == [0, 1, 2] and seen[0] == seen[3], seen)
    check("... no SPEEDSCRIPT anywhere in the menu", not any("SPEEDSCRIPT" in r for r in rows(e)))
    e.poke(e.lab["load_format"], [1])
    key(e, "X")
    r = rows(e)
    check("the main menu: the CTRL keys at its foot",
          "CTRL+ A MARK ALL" in r[20] and "X CUT" in r[21] and "C COPY" in r[22] and "Z UNDO" in r[23],
          r[19:25])
    key(e, "X")

    # SHIFT + F5: the end, on the bottom row; SHIFT + F3: the top
    doc = b"".join(b"LINE %03d OF THE DOCUMENT\r" % i for i in range(120))
    load_doc(e, doc)
    key(e, "F5", LS)
    t, cur = e.text()
    check("SHIFT+F5: the end of the document", cur == len(doc), (cur, len(doc)))
    check("... on the bottom row", v(e, "cur_row") == 24, v(e, "cur_row"))
    check("... the last line on the screen", "LINE 119 OF THE DOCUMENT" in rows(e)[23], rows(e)[22:25])
    key(e, "F3", LS)
    t, cur = e.text()
    check("SHIFT+F3: the top", cur == 0 and v(e, "row_off_lo") == 0 and v(e, "row_off_hi") == 0, cur)
    # with the mark key (C=): marking to the end, then copying all of it
    key(e, "F5", CBM | LS)
    check("C= + SHIFT + F5: marked to the end", v(e, "sel_on") == 1 and e.text()[1] == len(doc),
          (v(e, "sel_on"), e.text()[1]))
    key(e, "C", CTRL)
    check("... copied: all of it", e.clipboard() == doc, len(e.clipboard()))
    key(e, "F3", CBM | LS)
    check("C= + SHIFT + F3: marked back to the top", v(e, "sel_on") == 0 or e.text()[1] == 0, e.text()[1])
    key(e, "RIGHT")

    # SHIFT + F7: word wrap on/off (it stepped the background before);
    # SHIFT + F1: the next text color (Jim, 2026-10-07). Words of 6 letters
    # and a space: with word wrap the 6th word starts the second row,
    # without it the row is cut after 40 characters, inside that word.
    load_doc(e, b"ABCDEF " * 10 + CR + b"MORE TEXT" + CR)
    bg = v(e, "text_bg")
    check("word wrap on: the 6th word starts row 2", rows(e)[1].startswith("ABCDEF"), rows(e)[:2])
    key(e, "F7", LS)
    check("SHIFT+F7: word wrap off, rows cut at 40",
          v(e, "wrap_on") == 0 and rows(e)[1].startswith("F ABCDEF"), (v(e, "wrap_on"), rows(e)[:2]))
    key(e, "F7", RS)
    check("... SHIFT+F7 again (right SHIFT): on again",
          v(e, "wrap_on") == 1 and rows(e)[1].startswith("ABCDEF"), (v(e, "wrap_on"), rows(e)[:2]))
    check("... the background and the insert mode untouched", v(e, "text_bg") == bg and v(e, "edit_mode") == 0,
          (v(e, "text_bg"), v(e, "edit_mode")))
    # SHIFT + F1: the next color for what is typed next, as if that color's
    # key were pressed (Jim): the default text color stays as it is
    CODES = [0x90, 0x05, 0x1c, 0x9f, 0x9c, 0x1e, 0x1f, 0x9e,
             0x81, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9a, 0x9b]     # colors 0-15
    load_doc(e, b"ONE TWO" + CR)
    c0 = v(e, "text_color")
    e.keys([(KEY["RIGHT"], 0)] * 4)                 # (before TWO)
    key(e, "F1", LS)
    check("SHIFT+F1: the cursor's color steps on, the default stays",
          v(e, "cur_color") == (c0 + 1) & 15 and v(e, "text_color") == c0,
          (v(e, "cur_color"), v(e, "text_color")))
    check("... and no menu", not any("MAGIC TYPEWRITER" in r for r in rows(e)), rows(e)[4:6])
    key(e, "F1", RS)
    check("... again (right SHIFT): the next one", v(e, "cur_color") == (c0 + 2) & 15, v(e, "cur_color"))
    e.type_text("xy")
    col = [e.peek(0xd800 + i)[0] & 15 for i in range(8)]
    check("typed in that color, the text after it as before (col 6: the cursor)",
          col[4:6] == [(c0 + 2) & 15] * 2 and col[7] == c0 and col[0] == c0, col)
    key(e, "RIGHT")                                 # (the cursor leaves: tidied)
    want = b"ONE " + bytes([CODES[(c0 + 2) & 15]]) + b"XY" + bytes([CODES[c0]]) + b"TWO" + CR
    check("... in the text: one color code before, one after (the first press's code replaced)",
          e.text()[0] == want, e.text()[0])
    key(e, "Z", CTRL)
    check("... CTRL-Z: the typing gone", e.text()[0].count(b"XY") == 0, e.text()[0])
    # Any color key right after a color code: that code comes out (the one
    # put after the cursor keeps the word after it red)
    load_doc(e, b"AB" + bytes([CODES[2]]) + b"HELLO" + CR)          # AB [red] HELLO
    e.keys([(KEY["RIGHT"], 0)] * 2)
    key(e, "2", CTRL)
    e.type_text("x")
    key(e, "RIGHT")
    check("CTRL-2 right after a red code: AB [white] X [red] HELLO, nothing left over",
          e.text()[0] == b"AB" + bytes([CODES[1]]) + b"X" + bytes([CODES[2]]) + b"HELLO" + CR, e.text()[0])
    key(e, "F1")
    check("F1 alone: still the menu", "MAGIC TYPEWRITER" in rows(e)[5], rows(e)[5])
    key(e, "X")

    # RETURN in reversed text (Jim, 2026-10-08): the rest of the line moves
    # down still reversed (an RVS ON after the new line end); DEL joins it
    # back up and the RVS ON is tidied away. At the end of a line reverse
    # ends, as in BASIC. (The cursor's own cell is never checked: it blinks.)
    RVS = b"\x12"
    rdoc = RVS + b"HELLO" + CR + b"WORLD" + CR
    def rvs_cells(row, col, n):                 # reversed on the screen?
        return [c >= 0x80 for c in e.peek(0x0400 + row * 40 + col, n)]
    load_doc(e, rdoc)
    key(e, "HOME"); key(e, "HOME")
    key(e, "RETURN")
    check("RETURN at the start of a reversed line: an RVS ON after the line end",
          e.text()[0] == RVS + CR + RVS + b"HELLO" + CR + b"WORLD" + CR, e.text()[0])
    check("... HELLO still reversed, on the next row", rvs_cells(1, 1, 4) == [True] * 4, rvs_cells(1, 0, 5))
    key(e, "DEL")
    check("... DEL joins it back up: the text as it was", e.text()[0] == rdoc, e.text()[0])
    e.keys([(KEY["RIGHT"], 0)] * 2)             # (on the first L)
    key(e, "RETURN")
    check("RETURN in the middle of a reversed line: HE / [RVS ON] LLO",
          e.text()[0] == RVS + b"HE" + CR + RVS + b"LLO" + CR + b"WORLD" + CR, e.text()[0])
    check("... both halves reversed", rvs_cells(0, 0, 2) + rvs_cells(1, 1, 2) == [True] * 4,
          (rvs_cells(0, 0, 2), rvs_cells(1, 0, 3)))
    key(e, "Z", CTRL)
    check("... CTRL-Z: the text as it was", e.text()[0] == rdoc, e.text()[0])
    key(e, "HOME"); key(e, "HOME")
    e.keys([(KEY["RIGHT"], 0)] * 5)             # (after HELLO)
    key(e, "RETURN")
    e.type_text("x")
    check("RETURN at the end of a reversed line: reverse ends (nothing added)",
          e.text()[0] == RVS + b"HELLO" + CR + b"X" + CR + b"WORLD" + CR, e.text()[0])
    check("... X typed on the new line is not reversed", rvs_cells(1, 0, 1) == [False], rvs_cells(1, 0, 1))
    load_doc(e, b"HELLO" + CR)
    e.keys([(KEY["RIGHT"], 0)] * 2)
    key(e, "RETURN")
    check("RETURN in plain text: no codes added", e.text()[0] == b"HE" + CR + b"LLO" + CR, e.text()[0])

    # The manual's PRG bytes in a SEQ file (as an SD2IEC reads a PRG)
    load(e, "manseq")
    t, cur = e.text()
    check("a PRG of ours read as SEQ: the load address is not text, the header is used",
          t == manual_text and v(e, "save_format") == 0, (len(t), t[:24]))

    # Load format MAGIC (Jim, 2026-10-09): straight to the PRG way, no SEQ
    # try first (an SD2IEC hands a PRG over as SEQ, and that was read byte by
    # byte, without the fast loader) - so KERNAL LOAD
    e.poke(e.lab["load_format"], [0])
    load(e, "manual")
    t, cur = e.text()
    check("Load format MAGIC: the manual comes by KERNAL LOAD (fast loaders)",
          t == manual_text and v(e, "load_fast") == 1, (len(t), v(e, "load_fast")))
    # ... a SEQ file with format MAGIC: refused, the document as it was
    e.poke(e.lab["load_format"], [0])
    e.poke(e.lab["modified"], [0])
    before = e.text()[0]
    key(e, "F1"); key(e, "A"); key(e, "A")
    e.keys([(KEY["DEL"], 0)] * 16)
    e.type_text("long")
    key(e, "RETURN", settle=3)
    check("... a SEQ file with format MAGIC: 64, FILE TYPE MISMATCH, the document untouched",
          any("64, FILE TYPE MISMATCH" in r for r in rows(e)) and e.text()[0] == before, rows(e)[10:14])
    key(e, "SPACE")
finally:
    try:
        e.m.quit()
    except Exception as ex:
        print("quit:", ex)
    try:
        vice.wait(timeout=10)
    except Exception:
        vice.terminate()
    time.sleep(1)

# VICE's file system drive (a host folder as drive 8): a SEQ open of a PRG
# answers 62, FILE NOT FOUND
fsdir = os.path.join(WORK, "fsdrive")
shutil.rmtree(fsdir, ignore_errors=True)
os.makedirs(fsdir, exist_ok=True)               # (OneDrive may keep it a moment)
for f in os.listdir(fsdir):
    os.remove(os.path.join(fsdir, f))
shutil.copy(os.path.join(PROJ, "test", "manual.prg"), os.path.join(fsdir, "manual"))
vice = start_vice(PRG, model=model, extra=["-device8", "1", "-fs8", fsdir, "-virtualdev8", "+drive8truedrive"])
try:
    e = Editor(Mon())
    e.wait_ready()
    load(e, "manual")
    t, cur = e.text()
    check("from a file system drive (62 for SEQ): loaded as a PRG", t == manual_text, (len(t), rows(e)[12]))
finally:
    try:
        e.m.quit()
    except Exception as ex:
        print("quit:", ex)
    try:
        vice.wait(timeout=10)
    except Exception:
        vice.terminate()
    time.sleep(1)
print("ALL PASS" if ok else "SOME FAILED")
