"""Phase 10: file formats. The Magic Typewriter format (header with the
settings, found whatever the Load format says), ASCII (load and save),
PRG files, the Save format following the loaded format, and the warning
before colors are lost.
Run from the project folder:  python tools/test_phase10.py [c64|ntsc]
Needs a debug build and the .d64 (build.bat)."""
import sys, os, time, shutil, subprocess
from mtest import *

model = sys.argv[1] if len(sys.argv) > 1 else "c64"
disk = os.path.join(WORK, "p10.d64")
shutil.copy(os.path.join(PROJ, "build/magictypewriter.d64"), disk)
C1541 = r"C:/bin/GTK3VICE-3.9-win64/GTK3VICE-3.9-win64/bin/c1541.exe"
RED = 0x1c
CR, LF = b"\r", b"\n"
ok = True
def check(name, cond, info=""):
    global ok
    print(("PASS " if cond else "FAIL ") + name + ("" if cond else "  " + repr(info)[:300]))
    ok = ok and cond

# An ASCII file on the test disk: mixed line ends, a tab, both cases
ASCII = b"Hello World" + CR + LF + b"Second line" + LF + b"Third\tTabbed" + CR + LF + b"last {x}"
asc = os.path.join(WORK, "ascii_in.txt")
open(asc, "wb").write(ASCII)
subprocess.run([C1541, "-attach", disk, "-write", asc, "asciin,s"], capture_output=True)

# A PRG document too big for the buffer (40 KB): no KERNAL LOAD for it
BIG = b"".join(b"BIG LINE %05d OF A LONG DOCUMENT\r" % i for i in range(1300))[:40000]
big = os.path.join(WORK, "big.prg")
open(big, "wb").write(b"\x00\x40\x0e" + BIG)
subprocess.run([C1541, "-attach", disk, "-write", big, "big,p"], capture_output=True)
# A PRG from elsewhere: load address $0801
fgn = os.path.join(WORK, "foreign.prg")
open(fgn, "wb").write(b"\x01\x08\x0eHELLO FOREIGN")
subprocess.run([C1541, "-attach", disk, "-write", fgn, "foreign,p"], capture_output=True)

def read_file(name, kind="s"):
    out = os.path.join(WORK, "p10_" + name + ".out")
    if os.path.exists(out):
        os.remove(out)
    subprocess.run([C1541, "-attach", disk, "-read", name + "," + kind, out], capture_output=True)
    return open(out, "rb").read() if os.path.exists(out) else b""

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
        time.sleep(0.2)
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
    """clear the name box and type a name, then RETURN"""
    e.keys([(KEY["DEL"], 0)] * 7)
    e.keys([(KEY["DEL"], 0)] * 7)
    e.keys([(KEY["DEL"], 0)] * 3)
    e.type_text(name)
    key(e, "RETURN", settle=0.5)

def save_as(e, name):
    e.poke(e.lab["modified"], [1])          # (so "saved" shows in modified)
    key(e, "F1"); key(e, "B"); key(e, "A")
    name_box(e, name)
    return wait_for(lambda: v(e, "modified") == 0)

def load(e, name):
    key(e, "F1"); key(e, "A"); key(e, "A")
    if "WITHOUT SAVING" in rows(e)[12]:
        key(e, "Y")
    name_box(e, name)
    time.sleep(2)

def clear_all(e):
    e.keys([(KEY["HOME"], LS)]); key(e, "Y")

doc = (b"PLAIN " + bytes([RED]) + b"RED" + CR + bytes([0x12]) + b"REV" + bytes([0x92])
       + b" Mixed" + CR + b"END")
HEAD = bytes([0x00, 0x4d, 0x54, 0x57, 0x31, 0x40 + 14])
LGREY = b"\x9b"                     # (v0.3: the Text color's code)

vice = start_vice(os.path.join(PROJ, "build/magictypewriter.prg"), disk=disk, model=model)
try:
    e = Editor(Mon())
    e.wait_ready()
    check("a new document saves as magic", v(e, "save_format") == 0 and v(e, "default_save_format") == 0)
    load_doc(e, doc)
    e.poke(e.lab["text_bg"], [6])                   # settings the header keeps
    e.poke(e.lab["wrap_on"], [0])
    check("saved as magic", save_as(e, "magic1"))

    # Clear, change the settings, load it back (Load format PETSCII)
    clear_all(e)
    e.poke(e.lab["text_bg"], [0])
    e.poke(e.lab["wrap_on"], [1])
    mine = {"edit_mode": 1, "mark_key": 0, "save_dev": 10, "print_dev": 5}
    for n, x in mine.items():                       # settings of my own,
        e.poke(e.lab[n], [x])                       # not the document's
    load(e, "magic1")
    check("magic loaded, whatever the Load format", e.text()[0] == doc, e.text()[0][:40])
    check("... its settings applied", v(e, "text_bg") == 6 and v(e, "wrap_on") == 0,
          (v(e, "text_bg"), v(e, "wrap_on")))
    check("... but only a document's: mode, mark key, devices left as they were",
          all(v(e, n) == x for n, x in mine.items()), {n: v(e, n) for n in mine})
    check("... and it saves back as magic", v(e, "save_format") == 0)
    e.poke(e.lab["edit_mode"], [0]); e.poke(e.lab["mark_key"], [1])
    e.poke(e.lab["save_dev"], [8]); e.poke(e.lab["print_dev"], [4])

    # The same as a PRG file
    e.poke(e.lab["save_type"], [1])
    check("saved as a magic PRG", save_as(e, "prg1"))
    e.poke(e.lab["save_type"], [0])
    clear_all(e)
    load(e, "prg1")
    check("the PRG loads back (opened as a PRG after 64, FILE TYPE MISMATCH)",
          e.text()[0] == doc, (e.text()[0][:40], rows(e)[12]))
    check("... with KERNAL LOAD (its address is $4000, and it fits)", v(e, "load_fast") == 1)
    check("... its header's settings applied, File type PRG too", v(e, "save_type") == 1)
    e.poke(e.lab["save_type"], [0])

    # A PRG too big for the room: read byte by byte, as much as fits
    clear_all(e)
    load(e, "big")
    wait_for(lambda: "TOO LONG" in rows(e)[12], 120)
    t = e.text()[0]
    check("a 40 KB PRG: not with KERNAL LOAD", v(e, "load_fast") == 0)
    check("... 'TOO LONG: ONLY PART LOADED'", "TOO LONG" in rows(e)[12], rows(e)[12])
    check("... the part that fits, from the start", t == BIG[:len(t)] and len(t) > 34000, len(t))   # (34 KB: CTRL-Z and the work area take 2)
    key(e, "SPACE")

    # A PRG from elsewhere (load address $0801): read byte by byte, never
    # LOADed to its own address
    clear_all(e)
    e.poke(e.lab["load_format"], [1])           # (Load format PETSCII)
    load(e, "foreign")
    check("a PRG from elsewhere: not with KERNAL LOAD, its text all there",
          v(e, "load_fast") == 0 and e.text()[0] == b"HELLO FOREIGN", (v(e, "load_fast"), e.text()[0]))
    # v0.2: with the Load format MAGIC (the default) it is text from its first
    # byte - its load address bytes too (and the case code after them is text)
    clear_all(e)
    e.poke(e.lab["load_format"], [0])
    load(e, "foreign")
    check("... with the Load format MAGIC: not with KERNAL LOAD, the 2 address bytes kept as text",
          v(e, "load_fast") == 0 and e.text()[0] == b"\x01\x08\x0eHELLO FOREIGN", (v(e, "load_fast"), e.text()[0]))
    load_doc(e, doc)                                # (the document again)

    # ASCII: asks first (colors to lose), then saves without them
    e.poke(e.lab["save_format"], [2])
    e.poke(e.lab["modified"], [1])
    key(e, "F1"); key(e, "B"); key(e, "A")
    name_box(e, "ascii1")
    check("ASCII with colors: asks first", "COLORS WILL BE LOST Y/N" in rows(e)[12], rows(e)[12])
    key(e, "Y")
    check("... Y: saved", wait_for(lambda: v(e, "modified") == 0))

    # PETSCII, for comparison
    e.poke(e.lab["save_format"], [1])
    check("saved as PETSCII", save_as(e, "pet1"))
    clear_all(e)
    check("CLEAR ALL: the Save format back to magic", v(e, "save_format") == 0)

    # Load ASCII (Load format ASCII)
    e.poke(e.lab["load_format"], [2])
    load(e, "asciin")
    t = e.text()[0]
    want = (bytes([0xc8]) + b"ELLO " + bytes([0xd7]) + b"ORLD" + CR + bytes([0xd3]) + b"ECOND LINE" + CR
            + bytes([0xd4]) + b"HIRD " + bytes([0xd4]) + b"ABBED" + CR + b"LAST {X}")
    check("ASCII loaded: cases swapped, line ends, tab as a space", t == want, (t, want))
    check("... and it saves back as ASCII", v(e, "save_format") == 2)
    e.poke(e.lab["load_format"], [1])
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

# The files as the disk has them
m = read_file("magic1", "p")
check("MAGIC1 is a PRG ($4000): magic files always are", m[:2] == b"\x00\x40", m[:4])
m = m[2:]
settings = m[6:20]
check("MAGIC1: the header ($00 MTW1, 14 settings, RETURN), then $0e, the color, then the text",
      m[:6] == HEAD and m[20:23] == CR + b"\x0e" + LGREY and m[23:] == doc and settings[0] == 0x46
      and settings[3] == 0x40, m[:24])
p = read_file("prg1", "p")
check("PRG1: the load address $4000, then the header, $0e and the text",
      p[:2] == b"\x00\x40" and p[2:8] == HEAD and p[22:25] == CR + b"\x0e" + LGREY and p[25:] == doc, p[:26])
a = read_file("ascii1")
check("ASCII1: no codes, CR LF, small letters and capitals as ASCII",
      a == b"plain red" + CR + LF + b"rev mIXED" + CR + LF + b"end", a)
q = read_file("pet1")
check("PET1: $0e (or $8e), the color, then the text as it is",
      q[2:] == doc and q[:1] in (b"\x0e", b"\x8e") and q[1:2] == LGREY, q[:10])
print("ALL PASS" if ok else "SOME FAILED")
