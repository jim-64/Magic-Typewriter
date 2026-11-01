"""CTRL-Z (undo.asm): each kind of action, undone, gives back exactly the
text it started from (codes included); a second CTRL-Z has nothing to
undo; a cut of more than the 1 KB log can't be undone; CLEAR ALL can't.
Run from the project folder:  python tools/test_undo.py [c64|ntsc]
Needs a debug build (build.bat)."""
import sys, os, time
from mtest import *

model = sys.argv[1] if len(sys.argv) > 1 else "c64"
CR = b"\r"
RED, LGREY, PURPLE = 0x1c, 0x9b, 0x9c
ok = True
def check(name, cond, info=""):
    global ok
    print(("PASS " if cond else "FAIL ") + name + ("" if cond else "  " + repr(info)[:300]))
    ok = ok and cond

def v(e, name, n=1):
    return int.from_bytes(e.peek(e.lab[name], n), "little")

def box(e):
    return e.screen_rows()[12].upper()

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
    time.sleep(0.4)

def undo(e):
    e.keys([(KEY["Z"], CTRL)], settle=0.6)

def home(e):
    e.keys([(KEY["HOME"], 0), (KEY["HOME"], 0)])

DOC = (b"THE QUICK BROWN FOX" + CR + b"JUMPS " + bytes([RED]) + b"OVER" + bytes([LGREY])
       + b" THE LAZY DOG" + CR + b"LAST LINE HERE" + CR)

vice = start_vice(os.path.join(PROJ, "build/magictypewriter.prg"), model=model)
try:
    e = Editor(Mon())
    e.wait_ready()
    check("the text buffer ends 1 KB lower (the undo log above it)",
          v(e, "text_end", 2) == 0xc800 and v(e, "undo_base", 2) == 0xc800, hex(v(e, "text_end", 2)))
    undo(e)
    check("nothing done yet: 'NOTHING TO UNDO'", "NOTHING TO UNDO" in box(e), box(e))
    e.keys([(KEY["SPACE"], 0)])

    # A run of typing: one action
    e.type_text("hello world")
    undo(e)
    check("typing, undone: the text as before (empty)", e.text()[0] == b"", e.text()[0])
    undo(e)
    check("... again: 'NOTHING TO UNDO' (one undo)", "NOTHING TO UNDO" in box(e), box(e))
    e.keys([(KEY["SPACE"], 0)])

    # Cut: mark "QUICK " and cut it
    load_doc(e, DOC)
    home(e)
    e.keys([(KEY["RIGHT"], 0)] * 4)
    e.keys([(KEY["RIGHT"], CBM)] * 6)
    e.keys([(KEY["X"], CTRL)])
    check("cut", e.text()[0] == DOC.replace(b"QUICK ", b"", 1), e.text()[0][:30])
    undo(e)
    check("cut, undone: all of it back", e.text()[0] == DOC, e.text()[0][:40])
    check("... and the clipboard still holds what was cut", e.clipboard() == b"QUICK ", e.clipboard())

    # Typing over marked text
    home(e)
    e.keys([(KEY["RIGHT"], 0)] * 4)
    e.keys([(KEY["RIGHT"], CBM)] * 5)
    e.type_text("slow")
    check("typed over marked text", e.text()[0].startswith(b"THE SLOW BROWN"), e.text()[0][:20])
    undo(e)
    check("... undone: the marked text back, the typing gone", e.text()[0] == DOC, e.text()[0][:40])

    # DEL on marked text
    home(e)
    e.keys([(KEY["DOWN"], 0)])
    e.keys([(KEY["RIGHT"], CBM)] * 10)
    e.keys([(KEY["DEL"], 0)])
    undo(e)
    check("DEL on marked text (with a color code inside), undone", e.text()[0] == DOC, e.text()[0][:60])

    # Recolor: mark "BROWN", CTRL-5 (purple)
    home(e)
    e.keys([(KEY["RIGHT"], 0)] * 10)
    e.keys([(KEY["RIGHT"], CBM)] * 5)
    e.keys([(KEY["5"], CTRL)])
    check("recolored", bytes([PURPLE]) in e.text()[0], e.text()[0][:30])
    undo(e)
    check("... undone: the codes as they were", e.text()[0] == DOC, e.text()[0][:40])

    # A run of DEL (backspace) through a word
    home(e)
    e.keys([(KEY["DOWN"], 0), (KEY["DOWN"], 0)])
    e.keys([(KEY["RIGHT"], 0)] * 9)
    e.keys([(KEY["DEL"], 0)] * 5)
    check("five DELs", e.text()[0].endswith(b"LAST HERE\r"), e.text()[0][-12:])
    undo(e)
    check("... undone together", e.text()[0] == DOC, e.text()[0][-16:])

    # Typing, moving, typing: CTRL-Z undoes the last run only
    home(e)
    e.type_text("ab")
    e.keys([(KEY["DOWN"], 0)])
    e.type_text("cd")
    undo(e)
    check("two runs of typing: CTRL-Z undoes the last one",
          e.text()[0] == b"AB" + DOC, e.text()[0][:30])
    home(e)
    e.keys([(KEY["DEL"], LS)] * 0)
    e.keys([(KEY["RIGHT"], CBM)] * 2)
    e.keys([(KEY["DEL"], 0)])
    check("(the first run removed by hand)", e.text()[0] == DOC, e.text()[0][:20])

    # A color key, then typing (one action each - both undone in turn)
    home(e)
    e.keys([(KEY["3"], CTRL)])
    e.type_text("xy")
    undo(e)
    t = e.text()[0]
    check("CTRL-3 then typing: the typing undone", bytes([RED]) + bytes([LGREY]) in t or t == DOC, t[:10])
    e.keys([(KEY["RIGHT"], 0)])                     # (the cursor leaves: tidied)
    check("... and the color codes tidied away again", e.text()[0] == DOC, e.text()[0][:10])

    # Overwrite mode
    home(e)
    e.keys([(KEY["F7"], 0)])
    e.type_text("big")
    check("overwrite", e.text()[0].startswith(b"BIG QUICK"), e.text()[0][:12])
    undo(e)
    check("... undone", e.text()[0] == DOC, e.text()[0][:12])
    e.keys([(KEY["F7"], 0)])

    # Paste
    home(e)
    e.keys([(KEY["V"], CTRL)])
    check("pasted", e.text()[0] == b"QUICK " + DOC, e.text()[0][:12])
    undo(e)
    check("... undone", e.text()[0] == DOC, e.text()[0][:12])

    # A cut of more than the log holds
    big = b"".join(b"A LINE OF TEXT NUMBER %03d\r" % i for i in range(80))   # ~2 KB
    load_doc(e, big)
    home(e)
    e.keys([(KEY["A"], CTRL), (KEY["X"], CTRL)])
    check("cut 2 KB", e.text()[0] == b"", len(e.text()[0]))
    undo(e)
    check("... 'TOO BIG TO UNDO', the text left as it is",
          "TOO BIG TO UNDO" in box(e) and e.text()[0] == b"", box(e))
    e.keys([(KEY["SPACE"], 0)])

    # The screen's top row stays put after CTRL-Z (Jim, 2026-11-01); if the
    # cursor ends below the screen, just far enough to show it; above: its
    # row on top
    lines = b"".join(b"LINE %02d OF THE TEST\r" % i for i in range(80))
    load_doc(e, lines)
    e.keys([(KEY["F5"], 0), (KEY["F5"], 0)], settle=0.5)
    top = e.screen_rows()[0][1:]              # (column 0: maybe the cursor)
    e.keys([(KEY["DOWN"], 0)] * 5)
    e.keys([(KEY["DOWN"], CBM)] * 3 + [(KEY["X"], CTRL)], settle=0.5)
    check("a 3-line cut on the screen: the top row the same", e.screen_rows()[0][1:] == top,
          (top, e.screen_rows()[0]))
    undo(e)
    check("... CTRL-Z: the text back, the top row still the same, the cursor 3 rows down",
          e.text()[0] == lines and e.screen_rows()[0][1:] == top and v(e, "cur_row") == 8,
          (e.screen_rows()[0], top, v(e, "cur_row")))
    e.type_text("hello")
    undo(e)
    check("typing, CTRL-Z: the top row the same", e.text()[0] == lines and e.screen_rows()[0][1:] == top
          and v(e, "cur_row") == 8, (e.screen_rows()[0], v(e, "cur_row")))
    home(e)
    e.keys([(KEY["DOWN"], 0)] * 5)
    e.keys([(KEY["DOWN"], CBM)] * 40 + [(KEY["X"], CTRL)], settle=0.5)
    undo(e)
    rows = e.screen_rows()
    check("lines 5-44 cut, CTRL-Z: the cursor (at line 45) on the bottom row",
          e.text()[0] == lines and v(e, "cur_row") == 24 and "INE 45" in rows[24].upper(),
          (rows[0], rows[24], v(e, "cur_row")))
    home(e)
    e.keys([(KEY["DOWN"], 0)] * 5)
    e.type_text("abc")
    e.keys([(KEY["F5"], 0), (KEY["F5"], 0)], settle=0.5)
    undo(e)
    check("typing far above the screen, CTRL-Z: its row on top",
          e.text()[0] == lines and v(e, "cur_row") == 0 and e.screen_rows()[0].upper()[1:].startswith("INE 05"),
          (e.screen_rows()[0], v(e, "cur_row")))

    # CLEAR ALL can't be undone
    load_doc(e, DOC)
    e.type_text("x")
    e.keys([(KEY["HOME"], LS), (KEY["Y"], 0)])
    undo(e)
    check("CLEAR ALL: 'NOTHING TO UNDO'", "NOTHING TO UNDO" in box(e) and e.text()[0] == b"", box(e))
    e.keys([(KEY["SPACE"], 0)])
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
print("ALL PASS" if ok else "SOME FAILED")
