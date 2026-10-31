"""v0.3: CTRL-R, Find and Replace (Jim, 2026-10-31)
- FIND: then WITH:, then REPLACE Y/N/A=ALL at each match, from the
  top of the document to its end; the match marked on row 4, above the box
- Y replaces, N leaves it, A replaces it and the rest; "n REPLACED" at the end
- capitals and small letters the same; a match over a color code; the new
  text in the color where the match began
- CTRL-Z after Y: that one back; after A: all that A replaced
- a replacement holding the search text; an empty replacement; RUN/STOP
  or any other key stops (a held key's repeats don't count);
  no match at all; CTRL-F still as before, the last search text filled in
- with an REU of 512 KB (MT_REU=512): Replace all through a 60 KB document
  held in the REU
Run from the project folder:  python tools/test_replace.py [c64|ntsc]
Needs a debug build and the .d64 (build.bat)."""
import sys, os, time, re
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

def wait_for(cond, timeout=60):
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
    for _ in range(50):
        if e.peek(MB + 63)[0] == 0:
            break
        time.sleep(0.1)
    time.sleep(0.5)

def answer(e, text):
    """a box's answer: what was there rubbed out, then the text (capitals
    typed with SHIFT), RETURN"""
    e.keys([(KEY["DEL"], 0)] * 26)
    if text:
        e.keys([(KEY["SPACE"] if ch == " " else KEY[ch.upper()], LS if ch.isupper() else 0)
                for ch in text])
    key(e, "RETURN", settle=0.6)

def cap(s):
    """PETSCII capitals (upper/lower set): the letters shifted"""
    return bytes(c | 0x80 if 0x41 <= c <= 0x5a else c for c in s.encode())

def asked(e):
    return "REPLACE Y/N/A=ALL" in rows(e)[12]

def replace(e, find, repl):
    key(e, "R", CTRL, settle=0.5)
    r = rows(e)[12]
    check("CTRL-R: FIND: (%s)" % find, "FIND:" in r, r)
    answer(e, find)
    seen = wait_for(lambda: "WITH:" in rows(e)[12], 20)
    check("... then WITH:", seen, rows(e)[12])
    answer(e, repl)
    wait_for(lambda: asked(e) or "REPLACED" in rows(e)[12], 120)

def replaced(e):
    """the count in the last box, then a key closes it"""
    wait_for(lambda: "REPLACED" in rows(e)[12], 300)
    m = re.search(r"(\d+) REPLACED", rows(e)[12])
    key(e, "SPACE", settle=0.5)
    return int(m.group(1)) if m else None

# (control codes and other invisible bytes, for comparing text without them)
CODES = re.compile(b"[" + bytes([0]) + b"-" + bytes([12]) + bytes([14]) + b"-" + bytes([31]) +
                   bytes([128]) + b"-" + bytes([140]) + bytes([142]) + b"-" + bytes([159]) + b"]")
def visible(b):
    return CODES.sub(b"", b)
def fold(b):
    return bytes((x & 0x7f) if 0xc1 <= x <= 0xda else x for x in b)

RED, WHITE = bytes([0x1c]), bytes([0x05])
T = bytes([0xd4])                               # a shifted T
DOC = (b"THE CAT SAT ON THE MAT." + b"\r" +
       T + b"HE DOG AND " + T + b"HE " + RED + b"CAT" + WHITE + b" PLAY." + b"\r" +
       b"A C" + RED + b"AT IS NOT A DOG." + b"\r" +
       b"NOTHING HERE." + b"\r" +
       b"".join(b"LINE %02d OF FILLER TEXT\r" % i for i in range(40)) +
       b"THE END, THE CAT." + b"\r")

vice = start_vice(PRG, disk=os.path.join(PROJ, "build/magictypewriter.d64"), model=model)
try:
    e = Editor(Mon())
    e.wait_ready()
    load_doc(e, DOC)

    # "the" -> "a": Y, N, then A for the rest
    for _ in range(30):                         # (the cursor down: Replace
        key(e, "DOWN", settle=0.1)              # starts at the top all the same)
    replace(e, "the", "a")
    check("the first match marked (on row 0: the top of the text)",
          asked(e) and v(e, "sel_on") == 1 and v(e, "cur_row") == 0, (v(e, "sel_on"), v(e, "cur_row")))
    t, cur = e.text()
    check("... the first THE, from the top", cur == 3, cur)
    key(e, "Y", settle=0.6)
    check("Y: asked again", wait_for(lambda: asked(e), 20))
    check("... the next match on row 4", v(e, "cur_row") == 4 or v(e, "row_off_lo") == 0, v(e, "cur_row"))
    t, cur = e.text()
    check("... the first one replaced", t.startswith(b"A CAT SAT ON THE MAT.\r"), t[:30])
    check("... the second marked", cur == len(b"A CAT SAT ON THE"), cur)
    key(e, "N", settle=0.6)
    t, cur = e.text()
    check("N: left alone", t.startswith(b"A CAT SAT ON THE MAT.\r"), t[:30])
    check("... the next one (with a shifted T) marked", cur == len(b"A CAT SAT ON THE MAT.\r" + T + b"HE"), cur)
    before_a = t
    key(e, "A", settle=0.3)
    n = replaced(e)
    check("A: 4 more, 5 in all", n == 5, n)
    t, cur = e.text()
    want = before_a.replace(T + b"HE DOG AND " + T + b"HE ", cap("A") + b" DOG AND " + cap("A") + b" ").replace(
        b"THE END, THE CAT", b"A END, A CAT")
    check("... the text as expected", t == want, t[20:80])
    check("... nothing marked", v(e, "sel_on") == 0)
    check("... the screen drawn again, the last one on row 4", rows(e)[4].startswith("A END, A") and
          v(e, "cur_row") == 4, rows(e)[:6])
    key(e, "Z", CTRL, settle=0.8)
    t, cur = e.text()
    check("CTRL-Z after A: all that A replaced back", t == before_a, t[20:80])

    # A match over a color code; the new text takes the color where it began
    load_doc(e, DOC)
    replace(e, "cat", "dog")
    key(e, "A", settle=0.3)
    n = replaced(e)
    t, cur = e.text()
    check("cat -> dog: 4", n == 4, n)
    check("... a red CAT: a red DOG", T + b"HE " + RED + b"DOG" + WHITE + b" PLAY" in t, t[40:90])
    check("... C[RED]AT: DOG, then red after it", b"A DOG" + RED + b" IS NOT" in t, t[60:110])
    key(e, "Z", CTRL, settle=0.8)
    check("CTRL-Z: back as it was", e.text()[0] == DOC)

    # Y, then RUN/STOP, then CTRL-Z: that one back
    replace(e, "cat", "lion")
    key(e, "Y", settle=0.6)
    key(e, "STOP", settle=0.3)
    n = replaced(e)
    t, cur = e.text()
    check("Y then RUN/STOP: 1 replaced", n == 1 and t.startswith(b"THE LION SAT") and t.count(b"LION") == 1,
          (n, t[:30]))
    key(e, "Z", CTRL, settle=0.8)
    check("... CTRL-Z: back", e.text()[0] == DOC)

    # Any other key stops too (Jim, 2026-10-31); a key held down (repeating)
    # counts once: N held for 2 s skips one match only, Y then the next
    replace(e, "cat", "lion")
    e.keys([(KEY["N"], 0xF0)], settle=3)
    key(e, "Y", settle=0.6)
    key(e, "SPACE", settle=0.3)
    n = replaced(e)
    t, cur = e.text()
    check("N held, Y, SPACE: the 2nd replaced", n == 1 and t.startswith(b"THE CAT SAT")
          and t.count(b"LION") == 1, (n, t[:60]))
    key(e, "Z", CTRL, settle=0.8)
    check("... CTRL-Z: back", e.text()[0] == DOC)
    replace(e, "cat", "lion")
    key(e, "Q", settle=0.3)
    n = replaced(e)
    check("Q at the first: 0 replaced, nothing changed", n == 0 and e.text()[0] == DOC, n)

    # RUN/STOP at once: nothing
    replace(e, "mat", "rug")
    key(e, "STOP", settle=0.3)
    n = replaced(e)
    check("RUN/STOP at the first: 0 replaced, nothing changed", n == 0 and e.text()[0] == DOC, n)

    # The match's case (Jim, 2026-10-31): a capital first -> the first letter
    # a capital; two capitals first -> all; small -> as typed; capitals typed
    # stay
    CASE = (cap("D") + b"EVICE ONE.\r" + cap("DEVICE") + b" TWO.\r" + b"DEVICE THREE.\r" +
            cap("D") + RED + b"EVICE FOUR.\r" + b"D" + cap("EVICE") + b" FIVE.\r")
    load_doc(e, CASE)
    replace(e, "device", "mechanism")
    key(e, "A", settle=0.3)
    n = replaced(e)
    t, cur = e.text()
    want = (cap("M") + b"ECHANISM ONE.\r" + cap("MECHANISM") + b" TWO.\r" + b"MECHANISM THREE.\r" +
            cap("M") + b"ECHANISM FOUR.\r" + b"MECHANISM FIVE.\r")
    check("case: Device/DEVICE/device -> Mechanism/MECHANISM/mechanism (5)",
          n == 5 and visible(t) == want, (n, visible(t)))
    replace(e, "mechanism", "McIntosh")
    key(e, "A", settle=0.3)
    n = replaced(e)
    t, cur = e.text()
    mc = cap("M") + b"C" + cap("I") + b"NTOSH"
    want = (mc + b" ONE.\r" + cap("MCINTOSH") + b" TWO.\r" + mc + b" THREE.\r" +
            mc + b" FOUR.\r" + mc + b" FIVE.\r")
    check("... capitals typed stay: McIntosh, MCINTOSH", n == 5 and visible(t) == want, (n, visible(t)))
    load_doc(e, cap("I") + b" SAW " + cap("IT") + b".\r")
    replace(e, "i", "we")
    key(e, "A", settle=0.3)
    n = replaced(e)
    t, cur = e.text()
    want = cap("W") + b"E SAW " + cap("W") + b"E" + cap("T") + b".\r"
    check("... a one-letter search: only the first letter (We, WeT)", n == 2 and t == want, (n, t))
    load_doc(e, DOC)

    # The replacement holds the search text: it goes on past it
    replace(e, "a", "aa")
    key(e, "A", settle=0.3)
    n = replaced(e)
    t, cur = e.text()
    want_n = visible(DOC).count(b"A")
    check("a -> aa: every A once (%d)" % want_n, n == want_n and t.count(b"A") == 2 * DOC.count(b"A"),
          (n, want_n))
    key(e, "Z", CTRL, settle=0.8)
    check("... CTRL-Z: back", e.text()[0] == DOC)

    # An empty replacement: the matches go
    replace(e, "line ", "")
    key(e, "A", settle=0.3)
    n = replaced(e)
    t, cur = e.text()
    check("line -> nothing: 40 gone", n == 40 and t == DOC.replace(b"LINE ", b""), n)

    # Nothing found
    replace(e, "zebra", "x")
    n = replaced(e)
    check("no match: 0 replaced", n == 0, n)

    # CTRL-F as before, with the last search text
    load_doc(e, DOC)
    key(e, "F", CTRL, settle=0.5)
    r = rows(e)[12]
    check("CTRL-F: FIND: with the last search text", "FIND: ZEBRA" in r, r)
    answer(e, "sat")
    t, cur = e.text()
    check("... found and marked", v(e, "sel_on") == 1 and cur == len(b"THE CAT SAT"), cur)

    # The main menu lists CTRL-R
    key(e, "F1", settle=0.5)
    check("the main menu: R REPLACE", any("R REPLACE" in r for r in rows(e)), rows(e)[16:20])
    key(e, "X", settle=0.5)

    # A long document in the REU (MT_REU=512)
    if v(e, "reu_docs"):
        e.poke(e.lab["modified"], [0])
        key(e, "F1"); key(e, "A"); key(e, "A")
        e.keys([(KEY["DEL"], 0)] * 16)
        e.type_text("longdoc")
        key(e, "RETURN", settle=0.5)
        wait_for(lambda: "LOADING" not in rows(e)[12], 300)
        time.sleep(1)
        e.idle()
        d0, c0 = e.doc()
        src = open(os.path.join(PROJ, "test", "longdoc.seq"), "rb").read()[1:]
        check("long document: loaded whole (%d)" % len(d0), d0 == src and e.val24("tail_len") > 0, len(d0))
        want_n = fold(visible(src)).count(b"LAZY")
        replace(e, "lazy", "sleepy")
        key(e, "A", settle=0.3)
        n = replaced(e)
        e.idle()
        d1, c1 = e.doc()
        check("long document: all %d replaced" % want_n, n == want_n, n)
        check("... its text (codes aside) as expected",
              fold(visible(d1)) == fold(visible(src)).replace(b"LAZY", b"SLEEPY"), len(d1))
        check("... the late IRQ count still 0", v(e, "late_irqs") == 0, v(e, "late_irqs"))
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
