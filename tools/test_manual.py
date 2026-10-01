"""The manual on the disk (MANUAL, made by tools/make_manual.py) loads as a
Magic Typewriter document: the whole text, its settings, the first lines on
the screen. Also writes a screenshot of its first page (build/test/manual.png).
Run from the project folder:  python tools/test_manual.py [c64|ntsc]
Needs a debug build and the .d64 (build.bat)."""
import sys, os, time, shutil
from mtest import *

model = sys.argv[1] if len(sys.argv) > 1 else "c64"
disk = os.path.join(WORK, "manual.d64")
shutil.copy(os.path.join(PROJ, "build/magictypewriter.d64"), disk)
shot = os.path.join(WORK, "manual.png")
if os.path.exists(shot):
    os.remove(shot)
prg = open(os.path.join(PROJ, "test", "manual.prg"), "rb").read()
want = prg[2 + 20 + 1:]                     # (load address, header, case code)
ok = True
def check(name, cond, info=""):
    global ok
    print(("PASS " if cond else "FAIL ") + name + ("" if cond else "  " + repr(info)[:200]))
    ok = ok and cond

def v(e, name):
    return e.peek(e.lab[name])[0]

# (no warp: VICE writes the screenshot when it quits)
vice = start_vice(os.path.join(PROJ, "build/magictypewriter.prg"), disk=disk, model=model,
                  warp=False, extra=["-exitscreenshot", shot])
try:
    e = Editor(Mon())
    e.wait_ready()
    e.poke(e.lab["text_bg"], [6])            # (settings the manual must set back)
    e.poke(e.lab["wrap_on"], [0])
    e.poke(e.lab["modified"], [1])
    e.keys([(KEY["F1"], 0), (KEY["A"], 0), (KEY["A"], 0), (KEY["Y"], 0)])
    e.keys([(KEY["DEL"], 0)] * 16)
    e.type_text("manual")
    e.keys([(KEY["RETURN"], 0)], settle=0.5)
    t0 = time.time()
    while v(e, "modified") and time.time() - t0 < 120:
        time.sleep(0.5)
    time.sleep(1)
    doc, cur = e.text()
    check("MANUAL loads: all of its text (%d bytes)" % len(want), doc == want, (len(doc), len(want)))
    check("... as a magic document (KERNAL LOAD), saving back as magic",
          v(e, "load_fast") == 1 and v(e, "save_format") == 0)
    check("... its settings: black background, word wrap on", v(e, "text_bg") == 0 and v(e, "wrap_on") == 1,
          (v(e, "text_bg"), v(e, "wrap_on")))
    check("... upper/lower case", e.peek(0xd018)[0] & 2 == 2)
    rows = e.screen_rows()
    check("... the title on the second row", "MAGIC TYPEWRITER" in rows[1].upper(), rows[:3])
    check("... reversed (the banner, from column 1)", e.peek(0x0400 + 41, 1)[0] & 0x80 == 0x80)
    check("... in yellow", e.peek(0xd800 + 41, 1)[0] & 15 == 7, e.peek(0xd800 + 41, 1))
    time.sleep(2)                            # (a steady frame for the picture)
finally:
    try:
        e.m.quit()
    except Exception as ex:
        print("quit:", ex)
    try:
        vice.wait(timeout=20)
    except Exception:
        vice.terminate()
    time.sleep(1)
check("screenshot written: " + shot, os.path.exists(shot))
print("ALL PASS" if ok else "SOME FAILED")
