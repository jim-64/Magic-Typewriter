"""Phase 12: changes after Jim's tests on real hardware.
- Load/Save Format: MAGIC, PETSCII, ASCII (SpeedScript gone)
- the main menu shows the CTRL keys at its foot
- SHIFT + F3 / F5: the top / the end of the document (with the mark key:
  marking all the way)
- SHIFT + F7: word wrap on/off; SHIFT + F1: the next text color
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
    c0 = v(e, "text_color")
    key(e, "F1", LS)
    check("SHIFT+F1: the next text color", v(e, "text_color") == (c0 + 1) & 15, (c0, v(e, "text_color")))
    check("... the text drawn in it", e.peek(0xd805)[0] & 15 == (c0 + 1) & 15, e.peek(0xd805)[0] & 15)
    check("... and no menu", not any("MAGIC TYPEWRITER" in r for r in rows(e)), rows(e)[4:6])
    for _ in range(15):
        key(e, "F1", RS, settle=0.2)
    check("... round all 16 and back", v(e, "text_color") == c0 and e.peek(0xd805)[0] & 15 == c0,
          v(e, "text_color"))
    key(e, "F1")
    check("F1 alone: still the menu", "MAGIC TYPEWRITER" in rows(e)[5], rows(e)[5])
    key(e, "X")

    # The manual's PRG bytes in a SEQ file (as an SD2IEC reads a PRG)
    load(e, "manseq")
    t, cur = e.text()
    check("a PRG of ours read as SEQ: the load address is not text, the header is used",
          t == manual_text and v(e, "save_format") == 0, (len(t), t[:24]))
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
