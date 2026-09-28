"""Phase 5: marking text, copy/cut/paste, recoloring marked text.
Run from the project folder:  python tools/test_phase5.py [c64|ntsc]
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

RED, PURPLE, LGREY = 0x1c, 0x9c, 0x9b
RVSON, RVSOFF = 0x12, 0x92

def load_doc(e, doc):
    """put a document in the buffer through the mailbox (+63)"""
    te = int.from_bytes(e.peek(0x1a, 2), "little")
    start = te - len(doc)
    e.m.write(start, doc)
    e.m.write(0x08, (0x4000).to_bytes(2, "little") + start.to_bytes(2, "little"))
    e.m.write(MB + 63, [1])
    e.m.resume()
    for _ in range(50):
        if e.peek(MB + 63)[0] == 0:
            break
        time.sleep(0.1)
    time.sleep(0.3)

def reversed_cells(e, row):
    raw = e.peek(0x0400 + 40 * row, 40)
    return [i for i, c in enumerate(raw) if c & 0x80]

try:
    e = Editor(Mon())
    e.wait_ready()
    sel_on = e.lab["sel_on"]
    doc = b"ONE TWO THREE\rFOUR FIVE SIX\r"
    load_doc(e, doc)
    check("document loaded", e.text()[0] == doc)

    # Mark "ONE" with C= (the default mark key) + CRSR RIGHT
    e.keys([(KEY["RIGHT"], CBM)] * 3)
    check("marking on", e.peek(sel_on)[0] == 1)
    rc = reversed_cells(e, 0)
    check("ONE shows reversed (cursor at col 3)", rc[:3] == [0, 1, 2], rc)

    # CTRL-C copies; a move without SHIFT unmarks
    e.keys([(KEY["C"], CTRL)])
    check("clipboard = ONE", e.clipboard() == b"ONE", e.clipboard())
    e.keys([(KEY["RIGHT"], 0)])
    check("unmarked after a plain move", e.peek(sel_on)[0] == 0 and reversed_cells(e, 0) in ([], [4]),
          reversed_cells(e, 0))

    # CTRL-V pastes at the cursor (after "ONE ")
    e.keys([(KEY["V"], CTRL)])
    check("paste", e.text()[0] == b"ONE ONETWO THREE\rFOUR FIVE SIX\r", e.text()[0])

    # Recolor: mark the first "ONE", CTRL-3 -> red, then CTRL-5 -> purple
    e.keys([(KEY["HOME"], 0)])
    e.keys([(KEY["RIGHT"], CBM)] * 3)
    e.keys([(KEY["3"], CTRL)])
    check("CTRL-3 colors the marked text red",
          e.text()[0] == bytes([RED]) + b"ONE" + bytes([LGREY]) + b" ONETWO THREE\rFOUR FIVE SIX\r", e.text()[0])
    check("still marked", e.peek(sel_on)[0] == 1)
    colors = e.peek(0xd800, 5)
    check("red on the screen", [c & 15 for c in colors[:3]] == [2, 2, 2] and colors[4] & 15 == 15,
          [c & 15 for c in colors])
    e.keys([(KEY["5"], CTRL)])
    check("CTRL-5 again: purple, no extra codes",
          e.text()[0] == bytes([PURPLE]) + b"ONE" + bytes([LGREY]) + b" ONETWO THREE\rFOUR FIVE SIX\r", e.text()[0])

    # Cut the whole first line (SHIFT + CRSR DOWN from its start)
    e.keys([(KEY["HOME"], 0)])
    e.keys([(KEY["DOWN"], CBM)])
    e.keys([(KEY["X"], CTRL)])
    # (HOME puts the cursor after the line's leading purple code, so the cut
    # starts after it: purple + a restore code stay until the cursor moves on)
    check("cut: first line gone", e.text()[0] == bytes([PURPLE, LGREY]) + b"FOUR FIVE SIX\r", e.text()[0])
    check("clipboard: the line, starting purple",
          e.clipboard() == b"ONE" + bytes([LGREY]) + b" ONETWO THREE\r"
          and e.peek(e.lab["clip_color"])[0] == 4, (e.clipboard(), e.peek(e.lab["clip_color"])))

    # Paste it at the end: it keeps its colors
    e.keys([(KEY["DOWN"], 0)])
    e.keys([(KEY["V"], CTRL)])
    check("paste at the end",
          e.text()[0] == b"FOUR FIVE SIX\r" + bytes([PURPLE]) + b"ONE" + bytes([LGREY]) + b" ONETWO THREE\r",
          e.text()[0])

    # Typing replaces marked text: mark FOUR (from the top), type Z
    e.keys([(KEY["HOME"], 0), (KEY["HOME"], 0)])
    e.keys([(KEY["RIGHT"], CBM)] * 4)
    e.keys([(KEY["Z"], 0)])
    check("typing replaces the marked text", e.text()[0].startswith(b"Z FIVE SIX\r"), e.text()[0][:12])
    check("unmarked after typing", e.peek(sel_on)[0] == 0)

    # INST/DEL deletes marked text: mark " FIVE" leftwards (both SHIFTs).
    # Marking left includes the character the cursor started on (the E).
    e.keys([(KEY["RIGHT"], 0)] * 4)           # cursor on the E of "FIVE"
    e.keys([(KEY["RIGHT"], CBM | RS)] * 4)    # mark back over " FIV" + E (C= + SHIFT)
    e.keys([(KEY["DEL"], 0)])
    check("DEL deletes the marked text (marked leftwards)", e.text()[0].startswith(b"Z SIX\r"), e.text()[0][:10])

    # Reverse over a line end: mark "SIX" + CR + first 4 of next line, CTRL-9
    e.keys([(KEY["RIGHT"], 0)])              # cursor before SIX
    e.keys([(KEY["RIGHT"], CBM)] * 8)          # S I X CR (code) O N E  -> 7 visible + ...
    before = e.text()[0]
    e.keys([(KEY["9"], CTRL)])
    t = e.text()[0]
    print("   after CTRL-9:", t[:30])
    check("RVS ON at the start and again after the line end",
          t.startswith(b"Z " + bytes([RVSON]) + b"SIX\r" + bytes([RVSON])), t[:14])
    check("RVS OFF brings the rest back", bytes([RVSOFF]) in t[:40], t[:40])

    # The other mark key setting: left SHIFT marks, right SHIFT reverses
    e.keys([(KEY["RIGHT"], 0)])               # (unmark)
    check("default mark key is C=", e.peek(e.lab["mark_key"])[0] == 1)
    e.poke(e.lab["mark_key"], [0])
    e.keys([(KEY["HOME"], 0), (KEY["HOME"], 0)])
    e.keys([(KEY["RIGHT"], LS)] * 2)
    check("mark key left SHIFT: left SHIFT marks", e.peek(sel_on)[0] == 1 and reversed_cells(e, 0)[:2] == [0, 1],
          reversed_cells(e, 0))
    e.keys([(KEY["RIGHT"], RS)])              # right SHIFT alone: reverses, unmarks
    check("mark key left SHIFT: right SHIFT only reverses", e.peek(sel_on)[0] == 0)
    e.keys([(KEY["RIGHT"], CBM)])             # C= + CRSR: not marking now
    check("mark key left SHIFT: C= does not mark", e.peek(sel_on)[0] == 0)
    e.poke(e.lab["mark_key"], [1])

    # CTRL-A marks all; CTRL-C copies it all
    e.keys([(KEY["A"], CTRL)])
    check("CTRL-A marks everything", e.peek(sel_on)[0] == 1)
    e.keys([(KEY["C"], CTRL)])
    check("CTRL-C after CTRL-A copies the whole text", e.clipboard() == e.text()[0], (e.clipboard()[:20], e.text()[0][:20]))

    # The character the cursor starts on is marked, whichever way marking
    # goes (Jim, phase 6) - but not a line end
    load_doc(e, b"ONE TWO THREE\r" + bytes([RED]) + b"RED\r")
    def copied(start_right, keys):
        e.keys([(KEY["RIGHT"], 0)])                  # (unmark)
        e.keys([(KEY["HOME"], 0), (KEY["HOME"], 0)])
        e.keys([(KEY["RIGHT"], 0)] * start_right)
        e.keys(keys)
        e.keys([(KEY["C"], CTRL)])
        return e.clipboard()
    c = copied(4, [(KEY["RIGHT"], CBM | RS)] * 2)
    check("from the T of TWO, 2 left: 'E T' (the T included)", c == b"E T", c)
    c = copied(4, [(KEY["RIGHT"], CBM)] * 2)
    check("from the T of TWO, 2 right: 'TW'", c == b"TW", c)
    c = copied(4, [(KEY["RIGHT"], CBM | RS)] + [(KEY["RIGHT"], CBM)] * 3)
    check("1 left, then 3 right, back past the start: 'TW'", c == b"TW", c)
    c = copied(13, [(KEY["RIGHT"], CBM | RS)] * 3)
    check("from the end of a line, 3 left: 'REE' (no line end)", c == b"REE", c)
    c = copied(14, [(KEY["DOWN"], CBM | RS)])
    check("from the R of RED (a color code before it), up: the line and the R",
          c.replace(bytes([RED]), b"") == b"ONE TWO THREE\rR", c)
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
