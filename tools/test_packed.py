"""The program packed with Exomizer (as on the release disk): started from a
disk the usual way (LOAD"*",8 and RUN), it unpacks itself and starts as the
unpacked one does - it still knows the device it was loaded from ($BA), so
it reads MAGIC T DEFAULTS there - and after Quit BASIC works (the unpacker
leaves $BA alone; since v0.2 Quit resets the C64).
Run from the project folder:  python tools/test_packed.py [c64|ntsc]
Needs a debug build (build.bat; this test packs it itself) and Exomizer
(on the PATH, or C:\\bin\\exomizer.exe)."""
import sys, os, time, shutil, subprocess
from mtest import *

model = sys.argv[1] if len(sys.argv) > 1 else "c64"
EXO = shutil.which("exomizer") or r"C:/bin/exomizer.exe"
if not os.path.exists(EXO) and not shutil.which(EXO):
    sys.exit("Exomizer not found: put it on the PATH")
C1541 = r"C:/bin/GTK3VICE-3.9-win64/GTK3VICE-3.9-win64/bin/c1541.exe"
if not os.path.exists(C1541):
    C1541 = shutil.which("c1541") or "c1541"          # (Linux: on the PATH)

ok = True
def check(name, cond, info=""):
    global ok
    print(("PASS " if cond else "FAIL ") + name + ("" if cond else "  " + repr(info)))
    ok = ok and cond

def v(e, name):
    return e.peek(e.lab[name])[0]

def screen_text(e):
    raw = e.peek(0x0400, 1000)
    txt = "".join(chr(c + 64) if 1 <= c <= 26 else chr(c) if 32 <= c < 64 else "." for c in raw)
    return [txt[i * 40:(i + 1) * 40].rstrip() for i in range(25)]

def feed(e, text):
    """type at the READY prompt (VICE's keyboard feed: 10 keys at most)"""
    e.m.cmd(0x72, bytes([len(text)]) + text)
    e.m.resume()
    time.sleep(1.5)

# Pack the debug build, and make a disk: the packed program first, then a
# MAGIC T DEFAULTS with a cyan background and word wrap off
work = os.path.join(PROJ, "build", "test")
os.makedirs(work, exist_ok=True)
prg = os.path.join(PROJ, "build", "magictypewriter.prg")
packed = os.path.join(work, "packed.prg")
r = subprocess.run([EXO, "sfx", "sys", "-x1", "-q", "-o", packed, prg], capture_output=True, text=True)
check("Exomizer packed it (%d -> %d bytes)" % (os.path.getsize(prg),
      os.path.getsize(packed) if os.path.exists(packed) else 0),
      r.returncode == 0 and os.path.exists(packed), r.stdout + r.stderr)
defaults = os.path.join(work, "defaults.seq")
open(defaults, "wb").write(bytes([0x00, 0x4d, 0x54, 0x57, 0x31, 0x40 + 13]) + bytes(
    0x40 + x for x in [3, 15, 1, 0, 0, 1, 1, 8, 0, 0, 8, 0, 4]) + b"\r")
disk = os.path.join(work, "packed.d64")
if os.path.exists(disk):
    os.remove(disk)
subprocess.run([C1541, "-format", "packed,pk", "d64", disk, "-write", packed, "magic typewriter",
                "-write", defaults, "magic t defaults,s"], capture_output=True)

vice = start_vice(disk, disk=disk, model=model)        # LOAD"*",8 and RUN
try:
    e = Editor(Mon())
    e.wait_ready()
    time.sleep(1)
    check("unpacked and running: loaded from device 8", v(e, "load_device") == 8, v(e, "load_device"))
    check("... MAGIC T DEFAULTS read from it: background cyan, word wrap off",
          v(e, "text_bg") == 3 and v(e, "wrap_on") == 0, (v(e, "text_bg"), v(e, "wrap_on")))
    check("... ROMs out while editing ($01 = $35)", e.peek(0x01)[0] == 0x35, hex(e.peek(0x01)[0]))
    e.type_text("packed")
    check("typing works", e.text()[0] == b"PACKED", e.text()[0])

    # Quit, and BASIC must work
    e.keys([(KEY["F1"], 0)])
    e.keys([(KEY["Q"], 0)])
    check("Q (with changes) asks first", "QUIT WITHOUT SAVING" in e.screen_rows()[12].upper(),
          e.screen_rows()[12])
    try:                                        # (Y resets the C64, which
        e.keys([(KEY["Y"], 0)], settle=0, timeout=5)    # clears the mailbox:
    except TimeoutError:                        # the key is never counted)
        pass
    time.sleep(3)
    check("back in BASIC: ROMs in ($01 = $37)", e.peek(0x01)[0] == 0x37, hex(e.peek(0x01)[0]))
    check("BASIC zero page: $13 = 0, $16 = $19, $18 = 0",
          (e.peek(0x13)[0], e.peek(0x16)[0], e.peek(0x18)[0]) == (0, 0x19, 0),
          (e.peek(0x13)[0], e.peek(0x16)[0], e.peek(0x18)[0]))
    feed(e, b"PRINT 2+3\r")
    feed(e, b'?"A"+"B"\r')
    rows = screen_text(e)
    i = rows.index("PRINT 2+3") if "PRINT 2+3" in rows else -1
    check("PRINT 2+3 answers 5 on the next line", i >= 0 and rows[i + 1] == " 5", rows[i:i + 2])
    i = rows.index('?"A"+"B"') if '?"A"+"B"' in rows else -1
    check('?"A"+"B" answers AB', i >= 0 and rows[i + 1] == "AB", rows[i:i + 2])
finally:
    try:
        e.m.quit()
    except Exception as ex:
        print("quit:", ex)
    try:
        vice.wait(timeout=10)
    except Exception:
        vice.terminate()
print("ALL PASS" if ok else "SOME FAILED")
