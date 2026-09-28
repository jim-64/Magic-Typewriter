"""Phase 6: word wrap, word wrap off (rows cut at 40), page marker.
Run from the project folder:  python tools/test_phase6.py [c64|ntsc]
Needs a debug build (build.bat).

The screen is checked against layout(), a model of the wrap rule in
src/editor.asm: a row takes up to 40 characters; with word wrap, if the
line goes on, the row ends after its last space (a word longer than 40 is
cut at 40); without it, the row is cut at 40. A line end needs a place of
its own."""
import sys, os, time, random
from mtest import *

model = sys.argv[1] if len(sys.argv) > 1 else "c64"
vice = start_vice(os.path.join(PROJ, "build/magictypewriter.prg"), model=model)
ok = True
def check(name, cond, info=""):
    global ok
    print(("PASS " if cond else "FAIL ") + name + ("" if cond else "  " + repr(info)[:300]))
    ok = ok and cond

def visible(b):
    return (b & 0x7f) >= 0x20

def layout(text, wrap=True):
    """rows as (start offset, list of characters)"""
    rows, i, n = [], 0, len(text)
    while True:
        start, chars, brk = i, [], None
        while True:
            if i >= n:
                rows.append((start, chars))
                return rows
            b = text[i]
            i += 1
            if b in (0x0d, 0x8d):
                rows.append((start, chars))
                break
            if not visible(b):
                continue
            chars.append(b)
            if wrap and b == 0x20:
                brk = (i, len(chars))
            if len(chars) == 40:
                if brk and brk[1] < 40:
                    i, chars = brk[0], chars[:brk[1]]
                rows.append((start, chars))
                break

def scr(b):
    """PETSCII -> screen code, for the plain characters used here"""
    if 0x40 <= b <= 0x5f:
        return b - 0x40
    return b

def load_doc(e, doc, cursor_at_end=False):
    te = int.from_bytes(e.peek(0x1a, 2), "little")
    if cursor_at_end:              # all of it before the gap
        e.m.write(0x4000, doc)
        gs, ge = 0x4000 + len(doc), te
    else:                          # all of it after the gap
        e.m.write(te - len(doc), doc)
        gs, ge = 0x4000, te - len(doc)
    e.m.write(0x08, gs.to_bytes(2, "little") + ge.to_bytes(2, "little"))
    e.m.write(MB + 63, [1])
    e.m.resume()
    for _ in range(100):
        if e.peek(MB + 63)[0] == 0:
            break
        time.sleep(0.1)
    time.sleep(0.5)

def word(e2, name, n=2):
    return int.from_bytes(e2.peek(e2.lab[name], n), "little")

def table(e2, name):
    lo = e2.peek(e2.lab[name + "_lo"], 26)
    hi = e2.peek(e2.lab[name + "_hi"], 26)
    return [lo[i] + 256 * hi[i] for i in range(26)]

def screen_matches(e2, text, wrap=True, label=""):
    """the rows on the screen = the model's rows from the current top"""
    rows = layout(text, wrap)
    top = table(e2, "row_off")[0]
    starts = [r[0] for r in rows]
    if top not in starts:
        check(label + ": top row is a row start of the model", False, (top, starts[:30]))
        return False
    k = starts.index(top)
    raw = e2.peek(0x0400, 1000)
    offs = table(e2, "row_off")
    bad = []
    for r in range(25):
        if k + r < len(rows):
            chars = rows[k + r][1]
            want = bytes(scr(c) for c in chars) + b" " * (40 - len(chars))
            if offs[r] != rows[k + r][0]:
                bad.append(("row start", r, offs[r], rows[k + r][0]))
        else:
            want = b" " * 40
        got = bytes(c & 0x7f for c in raw[r * 40:(r + 1) * 40])
        if r == word(e2, "cur_row", 1):          # (the cursor cell may show the
            c = e2.peek(e2.lab["cur_col"])[0]    # cursor)
            if c < 40:
                got = got[:c] + want[c:c + 1] + got[c + 1:]
        if got != want:
            bad.append((r, got.decode("latin-1"), want.decode("latin-1")))
    check(label, not bad, bad[:3])
    return not bad

random.seed(6)
WORDS = [b"a", b"to", b"the", b"word", b"quick", b"letter", b"machine", b"keyboard",
         b"character", b"typewriter", b"commodore"]
def paragraph(nwords):
    return b" ".join(random.choice(WORDS) for _ in range(nwords)).upper()

try:
    e = Editor(Mon())
    e.wait_ready()
    check("word wrap is on by default", e.peek(e.lab["wrap_on"])[0] == 1)

    # A document: a long paragraph, a line of exactly 40, a 50-letter word,
    # short lines, another long paragraph with a color code in it
    doc = (paragraph(160) + b"\r" + b"X" * 30 + b" ABCDEFGHI\r" + b"W" * 50 + b" END\r"
           + b"SHORT\rLINES\r\r" + paragraph(40) + b"\x1c" + paragraph(80) + b"\r"
           + b"\r".join(b"LINE %02d" % i for i in range(40)) + b"\r")
    load_doc(e, doc)
    check("document loaded", e.text()[0] == doc)
    screen_matches(e, doc, label="word wrap: first screen")

    # Page down through it all and back up: every screen as the model says
    good = True
    for i in range(6):
        e.keys([(KEY["F5"], 0)])
        good &= screen_matches(e, doc, label="F5 #%d" % (i + 1))
    for i in range(6):
        e.keys([(KEY["F3"], 0)])
        good &= screen_matches(e, doc, label="F3 #%d" % (i + 1))
    check("back at the top after paging", table(e, "row_off")[0] == 0)

    # Cursor over a wrap: right along row 0 ends up on row 1, column 0
    rows = layout(doc)
    n0 = len(rows[0][1])
    e.keys([(KEY["HOME"], 0), (KEY["HOME"], 0)])
    e.keys([(KEY["RIGHT"], 0)] * n0)
    check("right past the end of a wrapped row: row 1, column 0",
          (e.peek(e.lab["cur_row"])[0], e.peek(e.lab["cur_col"])[0]) == (1, 0),
          (e.peek(e.lab["cur_row"])[0], e.peek(e.lab["cur_col"])[0]))
    # Down keeps the column where it can
    e.keys([(KEY["HOME"], 0), (KEY["HOME"], 0)])
    e.keys([(KEY["RIGHT"], 0)] * 30)
    e.keys([(KEY["DOWN"], 0)])
    want = min(30, len(rows[1][1]))
    check("down: same column (or the row's end)",
          (e.peek(e.lab["cur_row"])[0], e.peek(e.lab["cur_col"])[0]) == (1, want),
          (e.peek(e.lab["cur_row"])[0], e.peek(e.lab["cur_col"])[0], want))

    # Typing in the paragraph reflows it (and only the text changes)
    e.keys([(KEY["HOME"], 0), (KEY["HOME"], 0)])
    e.keys([(KEY["RIGHT"], 0)] * 5)
    e.type_text("zzzzzzzzzz ")
    t = e.text()[0]
    check("typed into the paragraph", t[:5] + b"ZZZZZZZZZZ " + t[16:] == t and len(t) == len(doc) + 11)
    screen_matches(e, t, label="reflow after typing")
    e.keys([(KEY["DEL"], 0)] * 11)
    t = e.text()[0]
    check("deleted again", t == doc, t[:30])
    screen_matches(e, t, label="reflow after deleting")

    # Up from the top row in the middle of the paragraph
    e.keys([(KEY["F5"], 0)])
    top1 = table(e, "row_off")[0]
    e.keys([(KEY["HOME"], 0)])                     # (start of the line: scrolls)
    e.keys([(KEY["F3"], 0), (KEY["F5"], 0)])
    e.keys([(KEY["DOWN"], 0)] * 0)
    ksel = [r[0] for r in rows].index(top1)
    # put the cursor on the top row, then press up
    for _ in range(30):
        if e.peek(e.lab["cur_row"])[0] == 0:
            break
        e.keys([(KEY["DOWN"], RS)])
    e.keys([(KEY["DOWN"], RS)])
    check("up on the top row: the screen scrolls one row",
          table(e, "row_off")[0] == rows[ksel - 1][0], (table(e, "row_off")[0], rows[ksel - 1][0]))
    screen_matches(e, doc, label="after scrolling up one row")

    # The page marker: first/last offsets out of the length
    e.keys([(KEY["HOME"], 0), (KEY["HOME"], 0)])
    offs = table(e, "row_off")
    total = len(doc)
    mk_top, mk_bot = e.peek(MB + 13, 2)
    exp_top = 51 + 200 * offs[0] // total
    exp_bot = 51 + 200 * offs[25] // total
    snap = lambda v: v + 1 if v & 7 == 3 else v
    check("marker at the top of the document", (mk_top, mk_bot) == (snap(exp_top), snap(exp_bot)),
          (mk_top, mk_bot, exp_top, exp_bot))
    e.keys([(KEY["F5"], 0)] * 3)
    offs = table(e, "row_off")
    mk_top, mk_bot = e.peek(MB + 13, 2)
    exp_top = 51 + 200 * offs[0] // total
    exp_bot = 51 + 200 * (offs[25] if e.peek(e.lab["eof_row"])[0] >= 25 else total) // total
    check("marker further down", (mk_top, mk_bot) == (snap(exp_top), snap(max(exp_bot, exp_top + 8))),
          (mk_top, mk_bot, exp_top, exp_bot))

    # Word wrap off (main menu, D): rows cut at 40 characters, even mid-word
    e.keys([(KEY["HOME"], 0), (KEY["HOME"], 0)])
    e.keys([(KEY["F1"], 0), (KEY["D"], 0), (KEY["X"], 0)])   # main menu: Wordwrap
    check("menu D: word wrap off", e.peek(e.lab["wrap_on"])[0] == 0)
    screen_matches(e, doc, wrap=False, label="wrap off: rows cut at 40")
    rows_off = layout(doc, wrap=False)
    check("wrap off: the first row has 40 characters", len(rows_off[0][1]) == 40)
    e.keys([(KEY["RIGHT"], 0)] * 45)
    check("right 45 times: row 1, column 5",
          (e.peek(e.lab["cur_row"])[0], e.peek(e.lab["cur_col"])[0]) == (1, 5),
          (e.peek(e.lab["cur_row"])[0], e.peek(e.lab["cur_col"])[0]))
    e.type_text("zz")
    t = e.text()[0]
    screen_matches(e, t, wrap=False, label="wrap off: typing moves the rest along")
    e.keys([(KEY["DEL"], 0)] * 2)
    check("deleted again", e.text()[0] == doc)
    e.keys([(KEY["F5"], 0)])
    screen_matches(e, doc, wrap=False, label="wrap off: F5")
    e.keys([(KEY["F3"], 0)])
    screen_matches(e, doc, wrap=False, label="wrap off: F3")
    e.keys([(KEY["F1"], 0), (KEY["D"], 0), (KEY["X"], 0)])   # main menu: Wordwrap
    check("menu D again: word wrap on", e.peek(e.lab["wrap_on"])[0] == 1)
    screen_matches(e, doc, label="wrap on again")

    # A big document (about 30 KB, no color codes): speed
    big = b""
    while len(big) < 30000:
        big += paragraph(random.randint(20, 150)) + b"\r"
    load_doc(e, big, cursor_at_end=True)
    e.keys([(KEY["RIGHT"], 0)])             # (at the end: it only shows it)
    f = e.peek(MB - 1)[0]
    print("   frames for the jump to the end of 30 KB:", f)
    screen_matches(e, big, label="big document: the end shown")
    check("big document: the cursor on the screen", e.peek(e.lab["cur_row"])[0] < 25)
    e.keys([(KEY["F3"], 0)])
    f = e.peek(MB - 1)[0]
    print("   frames for F3 near the end of 30 KB:", f)
    screen_matches(e, big, label="big document: F3")
    check("F3 in a big document takes under a second", f < 50, f)
    e.keys([(KEY["DOWN"], RS)] * 30)
    f = e.peek(MB - 1)[0]
    print("   frames for the last cursor up (scrolling):", f)
    check("cursor up scrolling in a big document: under half a second", f < 25, f)
    screen_matches(e, big, label="big document: after scrolling up")
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
