"""RESTORE and quitting back to BASIC.
Run from the project folder:  python tools/test_quit.py [c64|ntsc]
Needs a debug build (build.bat).

RESTORE is fired with a CIA2 timer NMI (the same way into the CPU as the
key). After QUIT, BASIC must work as on a freshly switched-on C64: the
program is gone (NEW), and commands that need BASIC's zero page values
(the RETURN after a command, string expressions) work. (Since v0.2 Quit
resets the C64, so this checks the reset brings BASIC back properly.)"""
import sys, os, time
from mtest import *

model = sys.argv[1] if len(sys.argv) > 1 else "c64"
vice = start_vice(os.path.join(PROJ, "build/magictypewriter.prg"), model=model)
ok = True
def check(name, cond, info=""):
    global ok
    print(("PASS " if cond else "FAIL ") + name + ("" if cond else "  " + repr(info)))
    ok = ok and cond

def screen_text(e):
    raw = e.peek(0x0400, 1000)
    txt = "".join(chr(c + 64) if 1 <= c <= 26 else chr(c) if 32 <= c < 64 else "." for c in raw)
    return [txt[i * 40:(i + 1) * 40].rstrip() for i in range(25)]

def feed(e, text):
    """type at the READY prompt (VICE's keyboard feed: 10 keys at most)"""
    e.m.cmd(0x72, bytes([len(text)]) + text)
    e.m.resume()
    time.sleep(1.5)

try:
    e = Editor(Mon())
    e.wait_ready()
    check("ROMs out while editing ($01 = $35)", e.peek(0x01)[0] == 0x35, hex(e.peek(0x01)[0]))
    e.type_text("hi")

    # RESTORE: one NMI from CIA2 timer A, one-shot
    e.m.write(0xdd04, [0x40, 0x00])
    e.m.write(0xdd0d, [0x81])
    e.m.write(0xdd0e, [0x19])
    e.m.resume()
    time.sleep(1.5)
    e.m.write(0xdd0d, [0x7f]); e.m.read(0xdd0d, 1)   # timer NMI off, cleared
    e.m.resume()
    check("RESTORE opens the menu", "MAGIC TYPEWRITER" in e.screen_rows()[1].upper(), e.screen_rows()[1])
    e.keys([(KEY["Q"], 0)])
    check("Q (with changes) asks first", "QUIT WITHOUT SAVING" in e.screen_rows()[12].upper(),
          e.screen_rows()[12])

    try:                                        # (Y resets the C64, which
        e.keys([(KEY["Y"], 0)], settle=0, timeout=5)    # clears the mailbox:
    except TimeoutError:                        # the key is never counted)
        pass
    time.sleep(3)
    check("Quit resets the C64: the power-up screen (v0.2)",
          any("COMMODORE 64 BASIC V2" in r for r in screen_text(e)[:4]), screen_text(e)[:4])
    check("back in BASIC: ROMs in ($01 = $37)", e.peek(0x01)[0] == 0x37, hex(e.peek(0x01)[0]))
    check("NEW: no program", e.peek(0x0801, 2) == b"\0\0", e.peek(0x0801, 2))
    check("BASIC zero page: $13 = 0, $16 = $19, $18 = 0",
          (e.peek(0x13)[0], e.peek(0x16)[0], e.peek(0x18)[0]) == (0, 0x19, 0),
          (e.peek(0x13)[0], e.peek(0x16)[0], e.peek(0x18)[0]))
    feed(e, b"PRINT 2+3\r")
    feed(e, b'?"A"+"B"\r')
    feed(e, b"LIST\r")
    rows = screen_text(e)
    for r in rows[:14]:
        print("   |" + r)
    check("READY.", "READY." in rows)
    i = rows.index("PRINT 2+3") if "PRINT 2+3" in rows else -1
    check("PRINT 2+3 answers 5 on the next line", i >= 0 and rows[i + 1] == " 5", rows[i:i + 2])
    i = rows.index('?"A"+"B"') if '?"A"+"B"' in rows else -1
    check('?"A"+"B" answers AB', i >= 0 and rows[i + 1] == "AB", rows[i:i + 2])
    i = rows.index("LIST") if "LIST" in rows else -1
    check("LIST shows no program", i >= 0 and rows[i + 1] == "" and rows[i + 2] == "READY.", rows[i:i + 3])
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
