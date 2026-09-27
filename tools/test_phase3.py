"""Phase 3 regression: typing, color keys and clean-up, DEL, RETURN,
overwrite, cursor keys, paging, and the key timing.
Run from the project folder:  python tools/test_phase3.py [c64|ntsc]
Needs a debug build (build.bat)."""
import sys, os, time
from mtest import *

model = sys.argv[1] if len(sys.argv) > 1 else "c64"
vice = start_vice(os.path.join(PROJ, "build/magictypewriter.prg"), model=model)
ok = True
def check(name, cond, info=""):
    global ok
    print(("PASS " if cond else "FAIL ") + name + ("" if cond else "  " + repr(info)))
    ok = ok and cond

RED, LGREY = 0x1c, 0x9b
try:
    e = Editor(Mon())
    e.wait_ready()

    e.type_text("hello")
    e.keys([(KEY["RETURN"], 0)])
    e.type_text("w")
    check("typing", e.text()[0] == b"HELLO\rW")

    # CTRL-3, type, move left: red text, no leftover restore code at the end
    e.keys([(KEY["3"], CTRL)])
    e.type_text("ab")
    e.keys([(KEY["RIGHT"], RS)])
    check("color key + clean-up", e.text()[0] == b"HELLO\rW" + bytes([RED]) + b"AB", e.text()[0])
    check("red on screen", [c & 15 for c in e.peek(0xd828, 3)] == [15, 2, 2])

    # DEL deletes A (left of the cursor), keeps the red code
    e.keys([(KEY["DEL"], 0)])
    check("DEL", e.text()[0] == b"HELLO\rW" + bytes([RED]) + b"B", e.text()[0])

    # F7 overwrite: X replaces B; F7 back to insert
    e.keys([(KEY["F7"], 0)])
    e.type_text("x")
    e.keys([(KEY["F7"], 0)])
    check("overwrite", e.text()[0] == b"HELLO\rW" + bytes([RED]) + b"X", e.text()[0])

    # HOME twice: top; RETURN in the middle, then DEL joins the line again
    e.keys([(KEY["HOME"], 0), (KEY["HOME"], 0)])
    e.keys([(KEY["RIGHT"], 0)] * 2)
    e.keys([(KEY["RETURN"], 0)])
    check("RETURN splits", e.text()[0].startswith(b"HE\rLLO\r"), e.text()[0])
    e.keys([(KEY["DEL"], 0)])
    check("DEL at the line start joins", e.text()[0].startswith(b"HELLO\rW"), e.text()[0])

    # SHIFT + INST/DEL inserts a space, the cursor stays
    e.keys([(KEY["DEL"], LS)])
    check("SHIFT + INST", e.text()[0].startswith(b"HE LLO\r"), e.text()[0])

    # A long document: F5 / F3 paging, cursor keeps its screen row
    e.keys([(KEY["HOME"], LS), (KEY["Y"], 0)])      # CLEAR ALL
    check("CLEAR ALL", e.text()[0] == b"")
    for n in range(30):
        e.type_text("line%d" % (n // 10)); e.type_text("%d" % (n % 10))
        e.keys([(KEY["RETURN"], 0)], settle=0)
    e.keys([(KEY["HOME"], 0), (KEY["HOME"], 0)])
    e.keys([(KEY["F5"], 0)])
    rows = e.screen_rows()
    check("F5: page down", rows[0][1:].lower().startswith("ine24"), rows[0])
    e.keys([(KEY["F3"], 0)])
    rows = e.screen_rows()
    check("F3: page up", rows[0][1:].lower().startswith("ine00"), rows[0])

    # Speed: a letter at the top of a full screen
    e.type_text("q")
    frames = e.peek(MB - 1)[0]
    check("a letter takes under 2 frames", frames < 2, frames)
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
