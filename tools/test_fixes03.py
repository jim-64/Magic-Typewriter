"""v0.3 fixes after Jim's test (2026-10-31):
- the name box: a full name, then DEL, leaves no second cursor block
- the name box clears the screen first (it shows in upper case/graphics),
  and the document comes back afterwards in its own character set
- a cut of text marked downwards: the text above stays where it was and
  the text after the cut moves up (the cursor on the row the marking
  started on; the top row if that was above the screen)
Run from the project folder:  python tools/test_fixes03.py [c64|ntsc]
Needs a debug build and the .d64 (build.bat)."""
import sys, os, time
from mtest import *

model = sys.argv[1] if len(sys.argv) > 1 else "c64"
PRG = os.path.join(PROJ, "build/magictypewriter.prg")
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

vice = start_vice(PRG, disk=os.path.join(PROJ, "build/magictypewriter.d64"), model=model)
try:
    e = Editor(Mon())
    e.wait_ready()
    doc = b"".join(b"LINE %03d OF THE DOCUMENT\r" % i for i in range(120))
    load_doc(e, doc)
    before = rows(e)

    # The name box (CTRL-S, no name yet)
    key(e, "S", CTRL, settle=0.6)
    scr = e.peek(0x0400, 1000)
    others = [scr[r * 40:(r + 1) * 40] for r in range(25) if r not in (11, 12, 13)]
    check("the name box: the rest of the screen is blank", all(set(r) == {0x20} for r in others),
          [bytes(r) for r in others if set(r) != {0x20}][:2])
    check("... in upper case/graphics", e.peek(0xd018)[0] == 0x15, hex(e.peek(0xd018)[0]))
    e.type_text("ABCDEFGHIJKLMNOP")              # 16: the longest name
    r12 = e.peek(0x0400 + 12 * 40, 40)
    check("a full name: one cursor block", r12.count(0xa0) == 1, r12)
    key(e, "DEL")
    r12 = e.peek(0x0400 + 12 * 40, 40)
    check("... DEL: still one cursor block", r12.count(0xa0) == 1, r12)
    check("... after the 15 letters left", r12.find(0xa0) > 0 and r12[r12.find(0xa0) - 1] == 15, r12)
    key(e, "STOP", settle=0.6)
    check("RUN/STOP: the document back as it was", rows(e)[1:] == before[1:] and rows(e)[0][1:] == before[0][1:],
          rows(e)[:4])
    check("... in upper/lower case again", e.peek(0xd018)[0] == 0x17, hex(e.peek(0xd018)[0]))
    check("... the cursor showing", v(e, "cursor_shown") == 1)
    check("... nothing saved, no name", v(e, "file_name_len") == 0)

    # (screen rows without column 0, where the cursor is in these checks)
    def rows1(e):
        return [r[1:] for r in rows(e)]
    UP = (KEY["DOWN"], RS)                        # SHIFT + CRSR DOWN

    # A cut of text marked downwards, all on the screen
    key(e, "F5", settle=0.6)
    e.keys([(KEY["DOWN"], 0)] * 5)
    top = rows1(e)
    check("set up: the cursor on row 5, a page down", v(e, "cur_row") == 5 and top[0] != before[0][1:],
          (v(e, "cur_row"), top[0]))
    e.keys([(KEY["DOWN"], CBM)] * 5)
    check("marked 5 lines downwards: the cursor on row 10", v(e, "cur_row") == 10, v(e, "cur_row"))
    key(e, "X", CTRL, settle=0.6)
    after = rows1(e)
    t, cur = e.text()
    check("CTRL-X: 5 lines gone", len(t) == len(doc) - 5 * 25, len(t))
    check("... the rows above stay where they were", after[:5] == top[:5], (after[:5], top[:5]))
    check("... the text after it moved up to row 5", after[5] == top[10], (after[5], top[10]))
    check("... the cursor on row 5, column 0", v(e, "cur_row") == 5 and v(e, "cur_col") == 0,
          (v(e, "cur_row"), v(e, "cur_col")))

    # Marked upwards (the cursor at the start): the same as before
    e.keys([(KEY["DOWN"], 0)] * 5)
    top = rows1(e)
    e.keys([(KEY["DOWN"], CBM | LS)] * 3)         # C= + SHIFT + CRSR DOWN = marking up
    check("marked 3 lines upwards: the cursor on row 7", v(e, "cur_row") == 7, v(e, "cur_row"))
    key(e, "X", CTRL, settle=0.6)
    after = rows1(e)
    check("CTRL-X: the rows above stay where they were", after[:7] == top[:7], (after[:7], top[:7]))
    check("... the rest of the line it ended on, on row 7", after[7] == top[10][1:], (after[7], top[10]))
    # (marking up takes the character it started on: the L)
    check("... the cursor on row 7", v(e, "cur_row") == 7, v(e, "cur_row"))

    # Marked downwards from above the screen: the text after goes on the top row
    e.keys([UP] * 2)                              # row 5
    check("set up: the cursor on row 5", v(e, "cur_row") == 5, v(e, "cur_row"))
    t0, c0 = e.text()
    want = rows1(e)[5]
    e.keys([(KEY["DOWN"], CBM)] * 30)
    check("marked 30 rows downwards: the start scrolled away", v(e, "cur_row") == 24, v(e, "cur_row"))
    want_after = rows1(e)[24]
    key(e, "X", CTRL, settle=0.6)
    t1, c1 = e.text()
    after = rows1(e)
    n = len(t0) - len(t1)                         # (30 lines, one of them without its L)
    check("CTRL-X: 30 lines gone", n == 30 * 25 - 1 and c1 == c0 and t1 == t0[:c0] + t0[c0 + n:],
          (len(t0), len(t1), c0, c1))
    check("... the line after the cut on the top row", after[0] == want_after, (after[0], want_after))
    check("... the cursor on row 0", v(e, "cur_row") == 0, v(e, "cur_row"))
    key(e, "Z", CTRL, settle=0.6)
    t2, c2 = e.text()
    check("CTRL-Z: the 30 lines back", t2 == t0, (len(t2), len(t0)))
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
