"""Phase 11: magic files always PRG, the spinner while loading and saving,
upper case/graphics for the directory and the file name boxes, the Print
menu, tape.
Run from the project folder:  python tools/test_phase11.py [c64|ntsc]
Needs a debug build and the .d64 (build.bat)."""
import sys, os, time, shutil, subprocess
from mtest import *

model = sys.argv[1] if len(sys.argv) > 1 else "c64"
disk = os.path.join(WORK, "p11.d64")
shutil.copy(os.path.join(PROJ, "build/magictypewriter.d64"), disk)
C1541 = r"C:/bin/GTK3VICE-3.9-win64/GTK3VICE-3.9-win64/bin/c1541.exe"
CR = b"\r"
UPPER, LOWER = 0x15, 0x17          # $d018 (bit 0 reads back as 1)
SPIN = (0x7e, 0x7c, 0x6c, 0x7b)
ok = True
def check(name, cond, info=""):
    global ok
    print(("PASS " if cond else "FAIL ") + name + ("" if cond else "  " + repr(info)[:300]))
    ok = ok and cond

def v(e, name):
    return e.peek(e.lab[name])[0]

def rows(e):
    return [r.upper() for r in e.screen_rows()]

def key(e, name, mods=0, settle=0.4):
    e.keys([(KEY[name], mods)], settle=settle)

def wait_for(cond, timeout=30):
    t0 = time.time()
    while time.time() - t0 < timeout:
        if cond():
            return True
        time.sleep(0.1)
    return False

def load_doc(e, doc):
    te = int.from_bytes(e.peek(0x1a, 2), "little")
    e.m.write(te - len(doc), doc)
    e.m.write(0x08, (0x4000).to_bytes(2, "little") + (te - len(doc)).to_bytes(2, "little"))
    e.m.write(MB + 63, [1])
    e.m.resume()
    wait_for(lambda: e.peek(MB + 63)[0] == 0, 10)
    time.sleep(0.5)

def name_box(e, name):
    e.keys([(KEY["DEL"], 0)] * 7)
    e.keys([(KEY["DEL"], 0)] * 7)
    e.keys([(KEY["DEL"], 0)] * 3)
    e.type_text(name)
    key(e, "RETURN", settle=0.1)

def listing():
    r = subprocess.run([C1541, "-attach", disk, "-list"], capture_output=True, text=True)
    return r.stdout.lower()

big = b"".join(b"LINE %05d OF A DOCUMENT TO SAVE SLOWLY\r" % i for i in range(700))

vice = start_vice(os.path.join(PROJ, "build/magictypewriter.prg"), disk=disk, model=model)
try:
    e = Editor(Mon())
    e.wait_ready()
    check("the character set starts as upper/lower", e.peek(0xd018)[0] == LOWER, e.peek(0xd018))

    # The Save name box: upper case/graphics while it is up
    load_doc(e, b"HELLO" + CR)
    key(e, "F1"); key(e, "B"); key(e, "A")
    check("SAVE: box in upper case/graphics", "SAVE:" in rows(e)[12] and e.peek(0xd018)[0] == UPPER,
          (rows(e)[12], e.peek(0xd018)))
    key(e, "STOP")
    check("... cancelled: upper/lower again", e.peek(0xd018)[0] == LOWER, e.peek(0xd018))

    # The File type, fixed by the format and the device: shown in [ ]
    key(e, "F1"); key(e, "B")
    check("magic: 'C FILE TYPE: [PRG]'", "FILE TYPE: [PRG]" in rows(e)[5], rows(e)[5])
    key(e, "C")
    check("... C changes nothing", v(e, "save_type") == 0 and "[PRG]" in rows(e)[5], rows(e)[5])
    key(e, "B")                                     # format: PETSCII
    check("PETSCII on disk: 'FILE TYPE: SEQ', free to change",
          "FILE TYPE: SEQ" in rows(e)[5] and "[" not in rows(e)[5], rows(e)[5])
    key(e, "D")                                     # device: tape
    check("PETSCII on tape: 'FILE TYPE: [SEQ]'", "FILE TYPE: [SEQ]" in rows(e)[5], rows(e)[5])
    e.poke(e.lab["save_format"], [0]); e.poke(e.lab["save_dev"], [8])
    key(e, "STOP")

    # Magic (a new document's format) always as a PRG, File type SEQ or not
    check("File type SEQ, Save format magic", v(e, "save_type") == 0 and v(e, "save_format") == 0)
    load_doc(e, big)
    e.poke(e.lab["modified"], [1])
    key(e, "F1"); key(e, "B"); key(e, "A")
    name_box(e, "slow1")
    seen = set()
    t0 = time.time()
    while time.time() - t0 < 60 and v(e, "modified"):
        col = v(e, "anim_col")
        if col:
            seen.add(e.peek(0x0400 + 12 * 40 + col)[0])
        time.sleep(0.05)
    check("saved", v(e, "modified") == 0)
    check("the spinner went round while saving", len(seen & set(SPIN)) >= 2, sorted(seen))
    check("... and is gone afterwards", v(e, "anim_col") == 0)

    # The disk directory: upper case/graphics while it shows
    key(e, "F1"); key(e, "A"); key(e, "D", settle=0.3)
    check("directory listed", wait_for(lambda: any("SLOW1" in x for x in rows(e)), 30), rows(e)[:4])
    check("... in upper case/graphics", e.peek(0xd018)[0] == UPPER, e.peek(0xd018))
    for _ in range(10):
        e.m.cmd(0x72, bytes([1]) + b" "); e.m.resume()
        if wait_for(lambda: "LOAD" in rows(e)[1], 3):
            break
    check("... back: upper/lower again", e.peek(0xd018)[0] == LOWER, e.peek(0xd018))
    key(e, "X")
    check("no line 25/247 IRQ late", v(e, "late_irqs") == 0, v(e, "late_irqs"))
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

check("SLOW1 (magic, File type SEQ) is a PRG on the disk", '"slow1"' in listing() and
      [l for l in listing().splitlines() if '"slow1"' in l][0].strip().endswith("prg"), listing()[-300:])

# Printing: VICE's printer 4 with the raw driver writes what it gets to a file
out = os.path.join(WORK, "printer.out")
if os.path.exists(out):
    os.remove(out)
extra = ["-device4", "1", "-iecdevice4", "-pr4drv", "raw", "-pr4output", "text",
         "-pr4txtdev", "0", "-prtxtdev1", out]
doc = b"Plain " + bytes([0x1c]) + b"red" + CR + bytes([0x12]) + b"REV" + bytes([0x92]) + b" end"
vice = start_vice(os.path.join(PROJ, "build/magictypewriter.prg"), model=model, extra=extra)
try:
    e = Editor(Mon())
    e.wait_ready()
    load_doc(e, doc)
    key(e, "F1"); key(e, "C"); key(e, "A", settle=3)          # Print
    key(e, "F1"); key(e, "C"); key(e, "B"); key(e, "A", settle=3)   # ASCII: yes; Print
    e.poke(e.lab["print_dev"], [5])                           # no printer 5
    key(e, "F1"); key(e, "C"); key(e, "A", settle=2)
    check("no printer there: 'DEVICE NOT PRESENT'", "DEVICE NOT PRESENT" in rows(e)[12], rows(e)[12])
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
# Tape: VICE's datasette can't be pressed from here, so the checks are the
# boxes and RUN/STOP while the KERNAL waits for PLAY or RECORD (the KERNAL
# looks at STKEY $91; one monitor stop writes $7f there and goes on). The
# real loading and saving is a Human Test.
def tape_stop(e):
    for _ in range(20):
        e.m.write(0x91, bytes([0x7f]))
        e.m.resume()
        time.sleep(0.2)
        if "BREAK" in rows(e)[12]:
            return True
    return False

vice = start_vice(os.path.join(PROJ, "build/magictypewriter.prg"), model=model)
try:
    e = Editor(Mon())
    e.wait_ready()
    tdoc = b"LINE ONE" + CR + b"LINE TWO" + CR + b"LINE THREE"
    load_doc(e, tdoc)
    e.keys([(KEY["DOWN"], 0), (KEY["RIGHT"], 0), (KEY["RIGHT"], 0)])   # the cursor mid-text
    where = e.text()[1]
    e.poke(e.lab["load_dev"], [1]); e.poke(e.lab["save_dev"], [1])
    for fmt, kind in ((0, "program file"), (1, "data file")):
        e.poke(e.lab["load_format"], [fmt])
        key(e, "F1"); key(e, "A"); key(e, "A")
        key(e, "RETURN", settle=0.5)                # (no name: the next file)
        check("tape load, %s: PRESS PLAY ON TAPE" % kind, "PRESS PLAY ON TAPE" in rows(e)[12], rows(e)[12])
        check("... RUN/STOP: BREAK, the document untouched", tape_stop(e) and e.text()[0] == tdoc,
              (rows(e)[12], e.text()[0][:20]))
        key(e, "SPACE")
    for fmt, kind in ((0, "program file"), (1, "data file")):
        e.poke(e.lab["save_format"], [fmt]); e.poke(e.lab["modified"], [1])
        key(e, "F1"); key(e, "B"); key(e, "A")
        name_box(e, "tapedoc")
        time.sleep(0.5)
        check("tape save, %s: PRESS RECORD & PLAY ON TAPE" % kind,
              "PRESS RECORD & PLAY ON TAPE" in rows(e)[12], rows(e)[12])
        check("... RUN/STOP: BREAK, the text and the cursor as they were",
              tape_stop(e) and e.text() == (tdoc, where), (rows(e)[12], e.text()))
        key(e, "SPACE")
    e.keys([(KEY["DOWN"], 0)])
    check("editing goes on; no line 25/247 IRQ late", v(e, "late_irqs") == 0 and e.text()[1] > where,
          (v(e, "late_irqs"), e.text()[1]))
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

got = open(out, "rb").read() if os.path.exists(out) else b""
pet = b"Plain red" + CR + b"\x12REV\x92 end" + CR
asc = b"pLAIN RED\r\nrev END\r\n"
check("printed for a Commodore printer: no colors, reverse kept, RETURN at the end",
      got[:len(pet)] == pet, got)
check("printed as ASCII: CR LF, no codes, cases swapped", got[len(pet):] == asc, got[len(pet):])
print("ALL PASS" if ok else "SOME FAILED")
