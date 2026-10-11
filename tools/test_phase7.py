"""Phase 7: the 1351 mouse, through the test mailbox's mouse queue.
Run from the project folder:  python tools/test_phase7.py [c64|ntsc]
Needs a debug build (build.bat)."""
import sys, os, time
from mtest import *

model = sys.argv[1] if len(sys.argv) > 1 else "c64"
vice = start_vice(os.path.join(PROJ, "build/magictypewriter.prg"), model=model)
ok = True
def check(name, cond, info=""):
    global ok
    print(("PASS " if cond else "FAIL ") + name + ("" if cond else "  " + repr(info)[:300]))
    ok = ok and cond

LEFT, RIGHT = 1, 2
RED, LIGHT_BLUE, WHITE, GREEN, LIGHT_GREEN = 2, 14, 1, 5, 13
# the pointer's color on each background (pointer_colors in data.asm)
POINTER = [13, 5, 13, 5, 5, 13, 13, 5, 13, 13, 13, 13, 13, 5, 13, 5]

def load_doc(e, doc):
    te = int.from_bytes(e.peek(0x1a, 2), "little")
    e.m.write(te - len(doc), doc)
    e.m.write(0x08, (0x4000).to_bytes(2, "little") + (te - len(doc)).to_bytes(2, "little"))
    e.m.write(MB + 63, [1])
    e.m.resume()
    for _ in range(100):
        if e.peek(MB + 63)[0] == 0:
            break
        time.sleep(0.1)
    time.sleep(0.5)

def cell_xy(row, col):
    """the pointer box on a text cell (it shows on lines 52-242 only: the
    top and bottom rows' cells are one line off, still the nearest cell)"""
    return 24 + 8 * col, max(52, min(242, 51 + 8 * row))

def cursor(e):
    return e.peek(e.lab["cur_row"])[0], e.peek(e.lab["cur_col"])[0]

def v(e, name, n=1):
    d = e.peek(e.lab[name], n)
    return d[0] if n == 1 else int.from_bytes(d, "little")

def top(e):
    return e.peek(e.lab["row_off_lo"])[0] + 256 * e.peek(e.lab["row_off_hi"])[0]

try:
    e = Editor(Mon())
    e.wait_ready()
    doc = b"".join(b"LINE %02d THE QUICK BROWN FOX\r" % i for i in range(60))
    load_doc(e, doc)

    check("no mouse yet: no pointer", v(e, "mouse_on") == 0 and v(e, "ptr_next_on") == 0)

    # The first movement finds the mouse and shows the pointer
    e.mouse([(4, 0, 0)])
    check("moved: mouse found, pointer shows", v(e, "mouse_on") == 1 and v(e, "ptr_next_on") == 1)

    # Click on a cell: the cursor goes there
    e.move_to(*cell_xy(3, 5))
    e.mouse([(0, 0, LEFT), (0, 0, 0)])
    check("click on row 3, column 5", cursor(e) == (3, 5), cursor(e))
    # Nearest cell: 3 pixels right of column 7 still counts as 7; 5 as 8
    x, y = cell_xy(6, 7)
    e.move_to(x + 3, y)
    e.mouse([(0, 0, LEFT), (0, 0, 0)])
    check("click rounds to the nearest cell (3 pixels over: same cell)", cursor(e) == (6, 7), cursor(e))
    e.move_to(x + 5, y)
    e.mouse([(0, 0, LEFT), (0, 0, 0)])
    check("... (5 pixels over: the next cell)", cursor(e) == (6, 8), cursor(e))
    # Past the end of a line: the line end
    e.move_to(*cell_xy(2, 38))
    e.mouse([(0, 0, LEFT), (0, 0, 0)])
    check("click past the line end: at the line end (27 characters)", cursor(e) == (2, 27), cursor(e))

    # Drag right from row 1, column 0 to column 7: marks "LINE 01"
    e.move_to(*cell_xy(1, 0))
    e.mouse([(0, 0, LEFT)])
    e.move_to(*cell_xy(1, 7), buttons=LEFT)
    e.mouse([(0, 0, 0)])
    check("dragging marks text", v(e, "sel_on") == 1)
    e.keys([(KEY["C"], CTRL)])
    check("drag right: 'LINE 01' copied", e.clipboard() == b"LINE 01", e.clipboard())

    # Drag left from column 12 (the Q) to column 8: the Q is marked too
    e.move_to(*cell_xy(1, 12))
    e.mouse([(0, 0, LEFT)])
    check("a click unmarks", v(e, "sel_on") == 0)
    e.move_to(*cell_xy(1, 8), buttons=LEFT)
    e.mouse([(0, 0, 0)])
    e.keys([(KEY["C"], CTRL)])
    check("drag left: 'THE Q' copied (the starting character included)", e.clipboard() == b"THE Q",
          e.clipboard())

    # Mark key (C=) + click extends the marking
    e.move_to(*cell_xy(3, 0))
    e.mouse([(0, 0, LEFT), (0, 0, 0)])
    e.move_to(*cell_xy(3, 4))
    # hold C= (120 frames) and click meanwhile, all written in one go: the
    # click must come a frame after C= goes down (the mouse is read before
    # the keyboard in each frame)
    head, mhead = e.peek(HEAD)[0], e.peek(MHEAD)[0]
    e.m.write(QUEUE + 2 * head, bytes([0xff, CBM | (15 << 4)]))
    e.m.write(HEAD, bytes([(head + 1) % 8]))
    for i, ev in enumerate([(0, 0, 0), (0, 0, LEFT), (0, 0, 0)]):
        e.m.write(MQUEUE + 3 * ((mhead + i) % 4), bytes(ev))
    e.m.write(MHEAD, bytes([(mhead + 3) % 4]))
    e.m.resume()
    time.sleep(1.0)
    e.keys([(KEY["C"], CTRL)])
    check("mark key + click extends the marking", e.clipboard() == b"LINE", e.clipboard())
    e.keys([(KEY["RIGHT"], 0)])

    # The pointer picture: high in its block, or low near the bottom
    e.move_to(*cell_xy(10, 10))
    check("row 10: picture at the top of block 250, Y = top - 1",
          (v(e, "ptr_next_block"), v(e, "ptr_next_y")) == (250, 51 + 80 - 1),
          (v(e, "ptr_next_block"), v(e, "ptr_next_y")))
    e.move_to(*cell_xy(24, 10))
    check("row 24: the low picture (block 254), Y = top - 14",
          (v(e, "ptr_next_block"), v(e, "ptr_next_y")) == (254, 242 - 14),
          (v(e, "ptr_next_block"), v(e, "ptr_next_y")))
    e.move_to(*cell_xy(0, 10))
    check("row 0: the box starts on line 52 (not 51)", e.mouse_pos()[1] == 52, e.mouse_pos())

    # Up into the top strip: the pointer hides, the icon under it lights up
    # in the pointer's color (light green on black)
    e.move_to(8, 40)
    check("top strip: pointer hidden", v(e, "ptr_next_on") == 0)
    colors = list(e.peek(e.lab["icon_colors"], 5))
    check("over the left F3 badge: it is light green, the rest light blue",
          colors == [LIGHT_BLUE, LIGHT_GREEN, LIGHT_BLUE, LIGHT_BLUE, LIGHT_BLUE], colors)
    e.move_to(40, 40)
    colors = list(e.peek(e.lab["icon_colors"], 5))
    check("over the menu icon: it is light green", colors[0] == LIGHT_GREEN and colors[1] == LIGHT_BLUE, colors)
    e.move_to(350, 40)
    colors = list(e.peek(e.lab["icon_colors"], 5))
    check("over the right F3 badge: it is light green", colors[2] == LIGHT_GREEN, colors)
    # Every background: the badge lights up in the pointer's color, and the
    # line 10 IRQ gives the pointer sprite that color too (2026-10-08)
    for bg in range(16):
        e.poke(e.lab["text_bg"], [bg])
        e.mouse([(1, 0, 0), (-1, 0, 0)], settle=0.1)    # (the nudge: in warp,
        colors = list(e.peek(e.lab["icon_colors"], 5))  # a pause soon adds up
        spr0 = e.peek(0xd027)[0] & 15                    # to the 10-second idle)
        check("background %d: badge and pointer color %d" % (bg, POINTER[bg]),
              colors[2] == POINTER[bg] and spr0 == POINTER[bg], (colors, spr0))
    e.poke(e.lab["text_bg"], [0])
    time.sleep(0.3)

    # F5 badge click: page down; F3 badge click: page up
    e.move_to(350, 255)
    colors = list(e.peek(e.lab["icon_colors"], 5))
    check("over the right F5 badge: it is light green", colors[4] == LIGHT_GREEN, colors)
    t0 = top(e)
    e.mouse([(0, 0, LEFT), (0, 0, 0)])
    t1 = top(e)
    check("click on F5: page down", t1 > t0, (t0, t1))
    e.move_to(8, 40)
    e.mouse([(0, 0, LEFT), (0, 0, 0)])
    check("click on F3: page up", top(e) == t0, (t0, top(e)))

    # Right button: the menu; again: closed
    before = e.text()[0]
    e.move_to(*cell_xy(5, 5))
    e.mouse([(0, 0, RIGHT), (0, 0, 0)])
    check("right button: the menu", "MAGIC TYPEWRITER" in e.screen_rows()[1].upper())
    e.mouse([(0, 0, RIGHT), (0, 0, 0)])
    check("right button again: closed, text as it was",
          "MAGIC TYPEWRITER" not in e.screen_rows()[1].upper() and e.text()[0] == before
          and v(e, "ptr_next_on") == 1)

    # Dragging past the bottom of the text scrolls, marking as it goes
    e.move_to(*cell_xy(20, 0))
    e.mouse([(0, 0, LEFT)])
    t0 = top(e)
    e.move_to(20, 250, buttons=LEFT, settle=2.0)
    e.mouse([(0, 0, 0)])
    check("drag past the bottom: the screen scrolled", top(e) > t0, (t0, top(e)))
    check("... and the text is marked", v(e, "sel_on") == 1)
    e.keys([(KEY["RIGHT"], 0)])

    # 10 seconds unused: hidden; a click only wakes it
    e.move_to(*cell_xy(8, 8))
    e.mouse([(0, 0, LEFT), (0, 0, 0)])
    idle_max = v(e, "mouse_idle_max", 2)
    check("idle limit 10 seconds", idle_max == (500 if model == "c64" else 600), idle_max)
    e.m.write(e.lab["mouse_idle"], (idle_max - 2).to_bytes(2, "little"))
    e.m.resume()
    time.sleep(0.5)
    check("unused for 10 seconds: pointer hidden", v(e, "ptr_next_on") == 0)
    e.move_to(*cell_xy(8, 8))                      # (no move: already there)
    before = cursor(e)
    e.mouse([(0, 0, 0)])
    e.m.write(e.lab["mouse_idle"], (idle_max).to_bytes(2, "little"))
    e.m.resume()
    e.mouse([(0, 0, LEFT), (0, 0, 0)])
    check("a click while hidden only wakes it", v(e, "ptr_next_on") == 1 and cursor(e) == before,
          (v(e, "ptr_next_on"), cursor(e), before))

    # How long the housekeeping takes now (mouse + keyboard)
    hk = e.peek(MB + 15, 1)[0], e.peek(MB + 61, 1)[0]
    print("   housekeeping from line %d to %d" % hk)
    check("housekeeping ends well before the bottom strip", hk[1] < 120, hk)
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
