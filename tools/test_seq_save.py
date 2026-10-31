"""v0.3: what a SEQ file carries (Jim, 2026-10-30).
1. The Text color as a color code right after the case code, in PETSCII and
   magic files (so no text is left to the color of the program that prints
   the file); loading takes it back as the Text color, not as text.
2. The Save menu's WORD WRAP TO RETURN: a RETURN where word wrap ends a row
   at a space (plus RVS ON after it in reversed text), checked against a
   Python model of the editor's wrap rule (as test_phase6's), for PETSCII
   and ASCII; nothing with word wrap off or for magic files; and the file
   loaded back looks exactly as the document did.
Run from the project folder:  python tools/test_seq_save.py [c64|ntsc]
Needs a debug build and the .d64 (build.bat)."""
import sys, os, time, shutil, subprocess, random
from mtest import *

model = sys.argv[1] if len(sys.argv) > 1 else "c64"
disk = os.path.join(WORK, "seqsave.d64")
shutil.copy(os.path.join(PROJ, "build/magictypewriter.d64"), disk)
C1541 = r"C:/bin/GTK3VICE-3.9-win64/GTK3VICE-3.9-win64/bin/c1541.exe"
CR, LF = b"\r", b"\n"
RVS_ON, RVS_OFF, RED, WHITE, LGREY, CLR = 0x12, 0x92, 0x1c, 0x05, 0x9b, 0x93
COLOR_CODES = [0x90, 0x05, 0x1c, 0x9f, 0x9c, 0x1e, 0x1f, 0x9e,
               0x81, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9a, 0x9b]
ok = True
def check(name, cond, info=""):
    global ok
    print(("PASS " if cond else "FAIL ") + name + ("" if cond else "  " + repr(info)[:300]))
    ok = ok and cond

def put_file(data, name, kind):
    f = os.path.join(WORK, "seqsave_in.bin")
    open(f, "wb").write(data)
    subprocess.run([C1541, "-attach", disk, "-write", f, name + "," + kind], capture_output=True)

# Files from elsewhere: a BBS-like one starting [CLR][WHITE], one that
# starts with a color code and no case code
put_file(b"\x0e" + bytes([CLR, WHITE]) + b"HELLO BBS", "bbs", "s")
put_file(bytes([RED]) + b"RED FIRST", "redfirst", "s")
# ... and plain ones, as v0.2 and most programs write them: a case code and
# text, and text alone
put_file(b"\x0eHELLO PLAIN\rSECOND LINE", "plain", "s")
put_file(b"JUST TEXT\rLINE 2", "nocase", "s")

# ---- the wrap rule (as editor.asm's row_next; test_phase6's model) ----
def visible(b):
    return (b & 0x7f) >= 0x20

def layout(text):
    """rows as (start offset, number of characters, how it ended)"""
    rows, i, n = [], 0, len(text)
    while True:
        start, chars, brk = i, [], None
        while True:
            if i >= n:
                rows.append((start, chars, "end"))
                return rows
            b = text[i]
            i += 1
            if b in (0x0d, 0x8d):
                rows.append((start, chars, "eol"))
                break
            if not visible(b):
                continue
            chars.append(b)
            if b == 0x20:
                brk = (i, len(chars))
            if len(chars) == 40:
                if brk and brk[1] < 40:
                    i, chars = brk[0], chars[:brk[1]]
                rows.append((start, chars, "full"))
                break

def wrapped(text):
    """the text as WORD WRAP TO RETURN saves it (before any ASCII change)"""
    rows = layout(text)
    starts = [r[0] for r in rows] + [len(text)]
    out, rvs = bytearray(), False
    for k, (s, chars, how) in enumerate(rows):
        seg = text[s:starts[k + 1]]
        soft = how == "full" and chars and chars[-1] == 0x20
        body = seg[:-1] if soft else seg
        for b in body:
            if b == RVS_ON:
                rvs = True
            elif b in (RVS_OFF, 0x0d, 0x8d):
                rvs = False
        out += body
        if soft:
            out += CR + (bytes([RVS_ON]) if rvs else b"")
    return bytes(out)

def to_ascii(text):
    out = bytearray()
    for b in text:
        if b in (0x0d, 0x8d):
            out += CR + LF
        elif 0x41 <= b <= 0x5a:
            out.append(b | 0x20)
        elif 0x20 <= b < 0x41:
            out.append(b)
    return bytes(out)

WORDS = [b"the", b"quick", b"brown", b"fox", b"jumps", b"over", b"a", b"lazy", b"dog",
         b"commodore", b"typewriter", b"magic", b"is", b"of", b"and", b"keyboard",
         b"x", b"supercalifragilistic"]
random.seed(64)
def paragraph(nwords):
    return b" ".join(random.choice(WORDS) for _ in range(nwords)).upper()

# A document: long paragraphs, a line of exactly 40 with a space at the
# end, a 50-letter word, codes next to spaces, reverse across many rows,
# short lines
DOC = (paragraph(120) + CR
       + b"X" * 39 + b" " + b"NEXT WORD" + CR
       + b"W" * 50 + b" END" + CR
       + paragraph(30) + bytes([RED]) + b" " + bytes([WHITE]) + paragraph(30) + CR
       + bytes([RVS_ON]) + paragraph(50) + bytes([RVS_OFF]) + b" AFTER" + CR
       + b"SHORT" + CR + b"LINES" + CR + CR
       + paragraph(60))

# ---- the editor ----
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
    e.keys([(KEY["DEL"], 0)] * 7)
    e.keys([(KEY["DEL"], 0)] * 7)
    e.keys([(KEY["DEL"], 0)] * 3)
    e.type_text(name)
    key(e, "RETURN", settle=0.5)

def save_as(e, name, fmt, wrap=0, yes=False):
    e.poke(e.lab["save_format"], [fmt])
    e.poke(e.lab["save_wrap"], [wrap])
    e.poke(e.lab["modified"], [1])
    key(e, "F1"); key(e, "B"); key(e, "A")
    name_box(e, name)
    if yes:                                         # COLORS WILL BE LOST Y/N
        wait_for(lambda: "Y/N" in rows(e)[12], 10)
        key(e, "Y")
    return wait_for(lambda: v(e, "modified") == 0, 60)

def load(e, name, fmt=1):
    e.poke(e.lab["load_format"], [fmt])
    key(e, "F1"); key(e, "A"); key(e, "A")
    if "WITHOUT SAVING" in rows(e)[12]:
        key(e, "Y")
    name_box(e, name)
    time.sleep(2)
    e.idle()

def clear_all(e):
    e.keys([(KEY["HOME"], LS)]); key(e, "Y")

def screen(e):
    """the screen and its colors, all but the cursor's cell (top left).
    A space is a space, reversed or not, in any color: where a row ended
    at a space, the RETURN in its place leaves the cell empty (in BASIC
    too), and a reversed space there is no more."""
    chars, colors = e.peek(0x0401, 999), e.peek(0xd801, 999)
    return [(0x20, 0) if c & 0x7f == 0x20 else (c, k & 15) for c, k in zip(chars, colors)]

saved = {}          # name -> (kind, what the file must hold)
vice = start_vice(os.path.join(PROJ, "build/magictypewriter.prg"), disk=disk, model=model)
try:
    e = Editor(Mon())
    e.wait_ready()
    check("WORD WRAP TO RETURN is off at first", v(e, "save_wrap") == 0)

    # ---- 1. the color ----
    load_doc(e, b"HELLO")
    check("saved as PETSCII", save_as(e, "c1", 1))
    saved["c1"] = ("s", b"\x0e" + bytes([LGREY]) + b"HELLO")
    e.poke(e.lab["text_color"], [1])                # white
    check("saved as magic (white)", save_as(e, "c2", 0))
    clear_all(e)
    e.poke(e.lab["text_color"], [2])
    load(e, "c1")
    check("loaded back: the color code is no text", e.text()[0] == b"HELLO", e.text()[0])
    check("... it is the Text color (light grey)", v(e, "text_color") == 15, v(e, "text_color"))
    check("saved again: the same bytes", save_as(e, "c1b", 1))
    saved["c1b"] = saved["c1"]
    clear_all(e)
    load(e, "c2", 0)
    check("magic: the text, the color as the Text color (white)",
          e.text()[0] == b"HELLO" and v(e, "text_color") == 1, (e.text()[0], v(e, "text_color")))
    e.poke(e.lab["text_color"], [7])                # yellow
    load(e, "bbs")
    check("a file starting [CLR][WHITE]: its codes kept, the Text color left alone",
          e.text()[0] == bytes([CLR, WHITE]) + b"HELLO BBS" and v(e, "text_color") == 7,
          (e.text()[0], v(e, "text_color")))
    check("... saved: the Text color's code in front", save_as(e, "bbs2", 1))
    saved["bbs2"] = ("s", b"\x0e" + bytes([COLOR_CODES[7], CLR, WHITE]) + b"HELLO BBS")
    load(e, "plain")
    check("a plain file (case code, no color): all its text, the Text color left alone",
          e.text()[0] == b"HELLO PLAIN\rSECOND LINE" and v(e, "text_color") == 7,
          (e.text()[0], v(e, "text_color")))
    check("... saved: the Text color's code after the case code", save_as(e, "plain2", 1))
    saved["plain2"] = ("s", b"\x0e" + bytes([COLOR_CODES[7]]) + b"HELLO PLAIN\rSECOND LINE")
    load(e, "nocase")
    check("a plain file without a case code: all its text, the Text color left alone",
          e.text()[0] == b"JUST TEXT\rLINE 2" and v(e, "text_color") == 7,
          (e.text()[0], v(e, "text_color")))
    load(e, "redfirst")
    check("a file starting with a color code (no case code): the Text color, not text",
          e.text()[0] == b"RED FIRST" and v(e, "text_color") == 2, (e.text()[0], v(e, "text_color")))
    e.poke(e.lab["text_color"], [15])

    # ---- 2. WORD WRAP TO RETURN ----
    clear_all(e)
    load_doc(e, DOC)
    e.poke(e.lab["save_format"], [1])
    key(e, "F1"); key(e, "B")
    r = rows(e)
    check("the Save menu: G WORD WRAP TO RETURN: NO", any("G WORD WRAP TO RETURN: NO" in x for x in r), r)
    key(e, "G")
    check("... G: YES", any("WORD WRAP TO RETURN: YES" in x for x in rows(e)), rows(e))
    key(e, "B")                                     # Format: ASCII ...
    key(e, "B")                                     # ... then MAGIC
    check("... with Format MAGIC: [NO]", any("WORD WRAP TO RETURN: [NO]" in x for x in rows(e)), rows(e))
    key(e, "X"); key(e, "X")
    before = screen(e)

    check("saved PETSCII, word wrap to return", save_as(e, "w1", 1, wrap=1))
    saved["w1"] = ("s", b"\x0e" + bytes([LGREY]) + wrapped(DOC))
    check("saved ASCII, word wrap to return", save_as(e, "w2", 2, wrap=1, yes=True))
    saved["w2"] = ("s", to_ascii(wrapped(DOC)))
    check("saved magic with the setting on: no RETURNs added", save_as(e, "w3", 0, wrap=1))
    e.poke(e.lab["wrap_on"], [0])
    check("word wrap off: PETSCII with the setting on, nothing added", save_as(e, "w4", 1, wrap=1))
    saved["w4"] = ("s", b"\x0e" + bytes([LGREY]) + DOC)
    e.poke(e.lab["wrap_on"], [1])
    e.poke(e.lab["save_wrap"], [0])

    clear_all(e)
    load(e, "w1")
    after = screen(e)
    check("w1 loaded back: it looks exactly as the document did", after == before,
          [(i + 1, before[i], after[i]) for i in range(len(before)) if after[i] != before[i]][:8])
    lay = layout(e.text()[0])
    check("... every row of it a line of its own (at most 39 characters + RETURN), but for"
          " rows of a word longer than 40 (cut, as the screen does)",
          all(x[2] != "full" or 0x20 not in x[1] for x in lay)
          and sum(1 for x in lay if x[2] == "full") == 1,
          [(len(x[1]), x[2]) for x in lay if x[2] == "full"])
    clear_all(e)
    load(e, "w3", 0)
    check("w3 (magic): the document as it was", e.text()[0] == DOC, e.text()[0][:60])
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
for name, (kind, want) in saved.items():
    out = os.path.join(WORK, "seqsave_" + name + ".out")
    if os.path.exists(out):
        os.remove(out)
    subprocess.run([C1541, "-attach", disk, "-read", name + "," + kind, out], capture_output=True)
    got = open(out, "rb").read() if os.path.exists(out) else b""
    diff = next((i for i in range(min(len(got), len(want))) if got[i] != want[i]), None)
    check("the file %s holds what it should" % name, got == want,
          (len(got), len(want), diff, got[diff - 8:diff + 8] if diff else got[-16:],
           want[diff - 8:diff + 8] if diff else want[-16:]))
out = os.path.join(WORK, "seqsave_w3.out")
subprocess.run([C1541, "-attach", disk, "-read", "w3,p", out], capture_output=True)
got = open(out, "rb").read() if os.path.exists(out) else b""
check("w3 (magic, PRG): the color code after the case code, the text as it is",
      got[23:25] == b"\x0e" + bytes([LGREY]) and got[25:] == DOC, got[:30])
print("ALL PASS" if ok else "SOME FAILED")
sys.exit(0 if ok else 1)
