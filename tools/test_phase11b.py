"""Phase 11b: long documents in an REU of 192 KB or more. A 90 KB document
loads (the REU takes what the text buffer can't hold), and moving through
it, typing, marking, Find, Stats, the page marker and saving all work on
the whole of it. Compared with a Python model of the text throughout.
Run from the project folder:  python tools/test_phase11b.py [c64|ntsc]
Needs a debug build (build.bat). Uses a 1581 disk image (room for 90 KB
files) and an REU of 512 KB."""
import sys, os, re, time, shutil, subprocess, random
os.environ.pop("MT_REU", None)          # this test chooses the REU itself
from mtest import *

model = sys.argv[1] if len(sys.argv) > 1 else "c64"
C1541 = r"C:/bin/GTK3VICE-3.9-win64/GTK3VICE-3.9-win64/bin/c1541.exe"
PRG = os.path.join(PROJ, "build/magictypewriter.prg")
disk = os.path.join(WORK, "p11b.d81")
CR, LF = b"\r", b"\n"
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

def wait_for(cond, timeout=60):
    t0 = time.time()
    while time.time() - t0 < timeout:
        if cond():
            return True
        time.sleep(0.2)
    return False

def name_box(e, name):
    e.keys([(KEY["DEL"], 0)] * 16)
    e.type_text(name)
    key(e, "RETURN", settle=0.5)

def keys_done(e, events, timeout=300):
    """keys, waiting until the last one's work is finished"""
    if len(events) > 1:
        e.keys(events[:-1], timeout=timeout)
    e.key_done(*events[-1], timeout=timeout)

def busy(e):
    r = rows(e)[12]
    return "LOADING" in r or "SAVING" in r or v(e, "anim_col") != 0

def load(e, name):
    e.poke(e.lab["modified"], [1])                  # (loading clears it last)
    key(e, "F1"); key(e, "A"); key(e, "A")
    if "WITHOUT SAVING" in rows(e)[12]:
        key(e, "Y")
    name_box(e, name)
    ok = wait_for(lambda: v(e, "modified") == 0, 300)
    time.sleep(1)
    return ok

def save_as(e, name):
    e.poke(e.lab["modified"], [1])
    key(e, "F1"); key(e, "B"); key(e, "A")
    name_box(e, name)
    ok = wait_for(lambda: v(e, "modified") == 0, 300)
    time.sleep(1)
    return ok

def read_file(name, kind):
    out = os.path.join(WORK, "p11b_" + name + ".out")
    if os.path.exists(out):
        os.remove(out)
    subprocess.run([C1541, "-attach", disk, "-read", name + "," + kind, out], capture_output=True)
    return open(out, "rb").read() if os.path.exists(out) else b""

# The documents -------------------------------------------------------------
random.seed(11)
WORDS = ["a", "to", "the", "word", "quick", "letter", "machine", "keyboard",
         "character", "typewriter", "commodore"]
lines = []
for i in range(2000):
    words = " ".join(random.choice(WORDS) for _ in range(random.randint(3, 12)))
    line = b"LINE %05d " % i + words.upper().encode()
    if i % 97 == 5:
        line += b" \x1cRED PART\x9b"                # (colors, each with an effect)
    lines.append(line)
BIG = CR.join(lines) + CR
while len(BIG) < 90000:
    BIG += b"MORE TEXT AT THE END OF THE DOCUMENT\r"

# ASCII, with a RETURN as the last byte of the text buffer's first fill
# (32 KB) and its line feed the first of the next: the pair is split
asc = b""
n = 0
while len(asc) < 32000:
    asc += b"Ascii line %05d with Mixed Case\r\n" % n
    n += 1
fill = 32767 - len(asc)
asc += b"x" * fill + CR + LF
assert asc[32767] == 13 and asc[32768] == 10
while len(asc) < 45000:
    asc += b"Ascii line %05d with Mixed Case\r\n" % n
    n += 1

def visible(data):
    """the text without its codes (what shows)"""
    return bytes(c for c in data if 0x20 <= c < 0x80 or c >= 0xa0 or c == 13)

def ascii_model(data):
    out = bytearray()
    i = 0
    while i < len(data):
        c = data[i]
        if c == 13:
            out.append(13)
            if i + 1 < len(data) and data[i + 1] == 10:
                i += 1
        elif c == 10:
            out.append(13)
        elif c == 9:
            out.append(32)
        elif c < 32 or c == 127:
            pass
        elif 65 <= c <= 90:
            out.append(c | 0x80)
        elif 97 <= c <= 122:
            out.append(c & 0xdf)
        else:
            out.append(c)
        i += 1
    return bytes(out)

# The disk: a 1581 image with both files
if os.path.exists(disk):
    os.remove(disk)
for name, data in (("big", b"\x0e" + BIG), ("asc", asc)):
    path = os.path.join(WORK, "p11b_" + name + ".in")
    open(path, "wb").write(data)
subprocess.run([C1541, "-format", "p11b,11", "d81", disk,
                "-write", os.path.join(WORK, "p11b_big.in"), "big,s",
                "-write", os.path.join(WORK, "p11b_asc.in"), "asc,s"], capture_output=True)

vice = start_vice(PRG, disk=disk, model=model,
                  extra=["-drive8type", "1581", "-reu", "-reusize", "512"])
try:
    e = Editor(Mon())
    e.wait_ready()
    check("REU of 512 KB: long documents on, the text buffer to $bc00 (then CTRL-Z's 1 KB)",
          v(e, "reu_docs") == 1 and v(e, "buf_top", 2) == 0xb800 and v(e, "text_end", 2) == 0xb800,
          (v(e, "reu_docs"), hex(v(e, "buf_top", 2)), hex(v(e, "text_end", 2))))

    # Load: 90 KB, the rest of it in the REU
    e.poke(e.lab["load_format"], [1])                 # PETSCII
    t0 = time.time()
    check("the 90 KB file loads", load(e, "big"))
    print("   (%.0f s)" % (time.time() - t0))
    doc, cur = e.doc()
    check("... all of it, the cursor at the start", doc == BIG and cur == 0,
          (len(doc), len(BIG), cur, next((i for i in range(min(len(doc), len(BIG))) if doc[i] != BIG[i]), None)))
    check("... the window at the start, the rest in the tail",
          v(e, "win_base", 3) == 0 and v(e, "tail_len", 3) > 50000, (v(e, "win_base", 3), v(e, "tail_len", 3)))
    check("... first line on the screen", rows(e)[0][1:].startswith("INE 00000"), rows(e)[0])

    # Down through it: page by page
    keys_done(e, [(KEY["F5"], 0)] * 60)
    doc, cur = e.doc()
    check("60 pages down: the text unchanged", doc == BIG, len(doc))
    check("... the window has moved on (win_base > 0)", v(e, "win_base", 3) > 0, v(e, "win_base", 3))
    line_no = BIG[:cur].count(CR)
    shown = [r for r in rows(e) if r.startswith("LINE ")]
    want = "LINE %05d" % line_no
    check("... the cursor's line is on the screen", any(r[1:].startswith(want[1:]) for r in rows(e)),
          (want, rows(e)[:3]))
    # the page marker: its top line against the document
    top_off = v(e, "win_base", 3) + v(e, "row_off_lo") + 256 * v(e, "row_off_hi")
    band_top = v(e, "band_top")
    expect = 51 + 200 * top_off // len(BIG)
    check("... the page marker shows where in all of it (line %d, about %d)" % (band_top, expect),
          abs(band_top - expect) <= 3, (band_top, expect))

    # Type in the middle
    e.type_text("xyz")
    model_doc = BIG[:cur] + b"XYZ" + BIG[cur:]
    doc, cur2 = e.doc()
    check("typed in the middle: in the right place", doc == model_doc and cur2 == cur + 3,
          (cur, cur2, len(doc)))
    here = cur2

    # Mark 10 pages down (the window moves meanwhile), copy: the clipboard
    # holds exactly that text
    keys_done(e, [(KEY["F5"], CBM)] * 10)
    doc, cur3 = e.doc()
    check("marked 10 pages: the text unchanged", doc == model_doc, len(doc))
    e.keys([(KEY["C"], CTRL)])
    clip = e.clipboard()
    check("... copied: the clipboard holds the marked text (%d bytes)" % len(clip),
          len(clip) > 5000 and clip.endswith(model_doc[here:cur3]) and len(clip) - (cur3 - here) <= 2,
          (len(clip), cur3 - here))
    key(e, "RIGHT")

    # HOME HOME: the start
    keys_done(e, [(KEY["HOME"], 0), (KEY["HOME"], 0)])
    doc, cur = e.doc()
    check("HOME twice: the start of the document", cur == 0 and v(e, "win_base", 3) == 0 and doc == model_doc,
          (cur, v(e, "win_base", 3)))

    # A bigger piece: mark 25 pages from the start, copy it, paste it far
    # on - more than the gap holds, so the window makes room first
    keys_done(e, [(KEY["F5"], CBM)] * 25)
    e.key_done(KEY["C"], CTRL)
    clip = e.clipboard()
    check("25 pages marked and copied (%d bytes, more than the 8 KB gap)" % len(clip), len(clip) > 12000,
          len(clip))
    e.key_done(KEY["RIGHT"])
    keys_done(e, [(KEY["F5"], 0)] * 30)
    doc, p = e.doc()
    gap = int.from_bytes(e.peek(0x0a, 2), "little") - int.from_bytes(e.peek(0x08, 2), "little")
    e.key_done(KEY["V"], CTRL)
    doc2, p2 = e.doc()
    check("pasted (the gap was %d): all of it, in the right place" % gap,
          visible(doc2) == visible(doc[:p] + clip + doc[p:]) and len(doc2) - len(doc) - len(clip) <= 2,
          (len(doc2), len(doc), len(clip), rows(e)[12]))
    model_doc = doc2
    keys_done(e, [(KEY["HOME"], 0), (KEY["HOME"], 0)])

    # SHIFT + F5: the end (all of the tail comes in); SHIFT + F3: the start
    e.key_done(KEY["F5"], LS)
    doc, cur = e.doc()
    check("SHIFT+F5: the end of the long document", doc == model_doc and cur == len(model_doc)
          and v(e, "tail_len", 3) == 0, (cur, len(model_doc), v(e, "tail_len", 3)))
    check("... the last line on the screen", any("MORE TEXT AT THE END" in r or "LINE 01999" in r
                                                   for r in rows(e)[18:25]), rows(e)[20:25])
    e.key_done(KEY["F3"], LS)
    doc, cur = e.doc()
    check("SHIFT+F3: the start again", doc == model_doc and cur == 0 and v(e, "win_base", 3) == 0,
          (cur, v(e, "win_base", 3)))

    # CTRL-Z far from the change: a page cut in the middle, the window moved
    # on to the end, then undone - the window comes back to it
    keys_done(e, [(KEY["F5"], 0)] * 40)
    doc0, c0 = e.doc()
    keys_done(e, [(KEY["F5"], CBM)])
    e.key_done(KEY["X"], CTRL)
    doc1, c1 = e.doc()
    check("a page cut in the middle (%d bytes)" % (len(doc0) - len(doc1)), 300 < len(doc0) - len(doc1) < 1000,
          len(doc0) - len(doc1))
    e.key_done(KEY["F5"], LS)
    check("... the window away at the end", v(e, "tail_len", 3) == 0, v(e, "tail_len", 3))
    e.key_done(KEY["Z"], CTRL)
    doc2, c2 = e.doc()
    check("... CTRL-Z: the page back, the cursor at it", doc2 == doc0 and abs(c2 - c0) < 1000, (len(doc2), c0, c2))
    keys_done(e, [(KEY["HOME"], 0), (KEY["HOME"], 0)])

    # Find, near the end: the window slides on to it
    key(e, "F", CTRL)
    e.type_text("line 01900")
    e.key_done(KEY["RETURN"])
    doc, cur = e.doc()
    at = model_doc.find(b"LINE 01900")
    check("Find: found near the end, cursor after it", cur == at + 10 and v(e, "sel_on") == 1, (cur, at + 10))
    check("... on the screen", any("INE 01900" in r for r in rows(e)), rows(e)[10:14])
    e.key_done(KEY["RIGHT"])
    doc, cur = e.doc()
    # Find what isn't there: not found, the cursor where it was
    key(e, "F", CTRL)
    e.keys([(KEY["DEL"], 0)] * 10)
    e.type_text("qqqq")
    key(e, "RETURN", settle=0.5)
    wait_for(lambda: "NOT FOUND" in rows(e)[12], 300)
    check("Find: 'NOT FOUND'", "NOT FOUND" in rows(e)[12], rows(e)[12])
    e.key_done(KEY["SPACE"])
    doc2, cur2 = e.doc()
    check("... the cursor where it was, the text unchanged", cur2 == cur and doc2 == model_doc, (cur, cur2))
    # Find from near the end: wraps round to the start
    key(e, "F", CTRL)
    e.keys([(KEY["DEL"], 0)] * 10)
    e.type_text("line 00003")
    e.key_done(KEY["RETURN"])
    doc, cur = e.doc()
    at = model_doc.find(b"LINE 00003")
    check("Find: round from the end to the start", cur == at + 10, (cur, at + 10))
    key(e, "RIGHT")

    # CTRL-A: too long to mark all
    key(e, "A", CTRL)
    check("CTRL-A: 'TOO LONG TO MARK ALL'", "TOO LONG TO MARK ALL" in rows(e)[12], rows(e)[12])
    key(e, "SPACE")

    # Stats: the characters of all of it, free room in the REU too
    key(e, "F1"); key(e, "I", settle=1)
    wait_for(lambda: any("FREE" in x for x in rows(e)), 60)  # (counting 140 KB takes a while)
    r = rows(e)
    chars = next((x for x in r if "CHARACTERS" in x), "")
    free = next((x for x in r if "FREE" in x), "")
    want_chars = sum(1 for c in model_doc if (0x20 <= c < 0x80 or c >= 0xa0 or c == 13))
    check("Stats: the characters of the whole document (%d)" % want_chars, str(want_chars) in chars, chars)
    m = re.search(r"FREE +(\d+)", free)
    nfree = int(m.group(1)) if m else 0
    check("... free room: the REU's too (over 250 000)", nfree > 250000, free)
    key(e, "SPACE"); key(e, "X")

    # Save as PETSCII, and as magic; load the magic one back
    e.poke(e.lab["save_format"], [1]); e.poke(e.lab["save_type"], [0])
    check("saved as PETSCII", save_as(e, "big2"))
    e.poke(e.lab["save_format"], [0])
    check("saved as magic (a PRG)", save_as(e, "bigm"))
    e.keys([(KEY["HOME"], LS)]); key(e, "Y")          # CLEAR ALL
    check("load the magic one back", load(e, "bigm"))
    doc, cur = e.doc()
    check("... the same text", doc == model_doc, (len(doc), len(model_doc)))

    # ASCII, with a RETURN / line feed pair split between two fills
    e.poke(e.lab["load_format"], [2])
    check("load an ASCII file of 45 KB", load(e, "asc"))
    doc, cur = e.doc()
    want = ascii_model(asc)
    check("... converted right, the split RETURN / line feed as one line end", doc == want,
          (len(doc), len(want), next((i for i in range(min(len(doc), len(want))) if doc[i] != want[i]), None)))
    check("no line 25/247 IRQ late", v(e, "late_irqs") == 0, (v(e, "late_irqs"), v(e, "late_line")))
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

# An REU of 256 KB and a 200 KB file: more than it holds. As much as fits
# loads, with "TOO LONG: ONLY PART LOADED"; all of it works as usual.
HUGE = b"".join(b"HUGE LINE %06d OF A VERY LONG DOCUMENT INDEED\r" % i for i in range(4500))
path = os.path.join(WORK, "p11b_huge.in")
open(path, "wb").write(HUGE)
subprocess.run([C1541, "-attach", disk, "-write", path, "huge,s"], capture_output=True)
vice = start_vice(PRG, disk=disk, model=model,
                  extra=["-drive8type", "1581", "-reu", "-reusize", "256"])
try:
    e = Editor(Mon())
    e.wait_ready()
    check("REU of 256 KB: long documents on", v(e, "reu_docs") == 1 and v(e, "reu_banks") == 4)
    e.poke(e.lab["load_format"], [1])
    e.poke(e.lab["modified"], [1])
    key(e, "F1"); key(e, "A"); key(e, "A")
    if "WITHOUT SAVING" in rows(e)[12]:
        key(e, "Y")
    name_box(e, "huge")
    wait_for(lambda: "TOO LONG" in rows(e)[12], 300)
    check("a 200 KB file: 'TOO LONG: ONLY PART LOADED'", "TOO LONG" in rows(e)[12], rows(e)[12])
    e.key_done(KEY["SPACE"])
    doc, cur = e.doc()
    check("... the start of it (%d bytes), the cursor at the start" % len(doc),
          len(doc) > 120000 and HUGE.startswith(doc) and cur == 0, (len(doc), cur))
    keys_done(e, [(KEY["F5"], 0)] * 20)
    e.type_text("abc")
    doc2, cur2 = e.doc()
    check("... paging and typing work", doc2 == doc[:cur2 - 3] + b"ABC" + doc[cur2 - 3:], (cur2, len(doc2)))
    keys_done(e, [(KEY["HOME"], 0), (KEY["HOME"], 0)])
    check("... HOME to the start", e.doc()[1] == 0)
    check("no line 25/247 IRQ late", v(e, "late_irqs") == 0, v(e, "late_irqs"))
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

got = read_file("big2", "s")
check("BIG2 on the disk: the case code, light grey, then the whole text", got == b"\x0e\x9b" + model_doc,
      (len(got), len(model_doc) + 2))
print("ALL PASS" if ok else "SOME FAILED")
