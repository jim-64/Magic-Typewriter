"""Phase 9: the REU. Is it found, and its size right? Do block copies and
the clipboard through it give exactly what they give without one? Is it
quicker? And its copies must never hold up the exact-timed IRQs at lines
25 and 247 (the debug build counts late ones in late_irqs).
Run from the project folder:  python tools/test_phase9.py [c64|ntsc|oldntsc|drean]
Needs a debug build (build.bat)."""
import sys, os, time, random
os.environ.pop("MT_REU", None)          # this test chooses the REU itself
from mtest import *

model = sys.argv[1] if len(sys.argv) > 1 else "c64"
PRG = os.path.join(PROJ, "build/magictypewriter.prg")
ok = True
def check(name, cond, info=""):
    global ok
    print(("PASS " if cond else "FAIL ") + name + ("" if cond else "  " + repr(info)[:300]))
    ok = ok and cond

def session(reu_kb, work):
    """VICE with an REU of reu_kb KB (0: none): run work(e), return its result"""
    extra = ["-reu", "-reusize", str(reu_kb)] if reu_kb else []
    vice = start_vice(PRG, model=model, extra=extra)
    try:
        e = Editor(Mon())
        e.wait_ready()
        return work(e)
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

def load_doc(e, doc):
    """the document in the buffer, all of it before the gap (cursor at its end)"""
    te = int.from_bytes(e.peek(0x1a, 2), "little")
    e.m.write(0x4000, doc)
    e.m.write(0x08, (0x4000 + len(doc)).to_bytes(2, "little") + te.to_bytes(2, "little"))
    e.m.write(MB + 63, [1])
    e.m.resume()
    for _ in range(100):
        if e.peek(MB + 63)[0] == 0:
            break
        time.sleep(0.1)
    time.sleep(0.5)

def v(e, name, n=1):
    return int.from_bytes(e.peek(e.lab[name], n), "little")

# Found, and the right size (banks of 64 KB; 16 MB counts as 255)
def detect(e):
    banks = v(e, "reu_banks")
    docs = v(e, "reu_docs"), v(e, "buf_top", 2)
    e.keys([(KEY["F1"], 0), (KEY["I"], 0)], settle=1.0)  # Stats shows it
    row = e.screen_rows()[8].upper()      # (Stats: the REU line, v0.2 row 8)
    e.keys([(KEY["SPACE"], 0), (KEY["X"], 0)])
    return banks, row, docs

for kb, banks in ((0, 0), (128, 2), (512, 8), (16384, 255)):
    got, row, docs = session(kb, detect)
    check("REU of %d KB: reu_banks = %d" % (kb, banks), got == banks, got)
    want = (1, 0xb800) if banks >= 3 else (0, 0xc800)   # (then CTRL-Z's 1 KB)
    check("... long documents %s (the text buffer to $%04x)" % ("on" if want[0] else "off", want[1]),
          docs == want, docs)
    if banks:
        kb_shown = 16384 if banks == 255 else banks * 64      # (16 MB = 255 banks)
        check("... Stats: REU %d KB" % kb_shown, "REU" in row and "%d KB" % kb_shown in row, row)
    else:
        check("... Stats: no REU line", "REU" not in row, row)

# The same editing with and without an REU
random.seed(9)
WORDS = [b"a", b"to", b"the", b"word", b"quick", b"letter", b"machine", b"keyboard",
         b"character", b"typewriter", b"commodore"]
doc = b""
while len(doc) < 20000:
    doc += b" ".join(random.choice(WORDS) for _ in range(random.randint(20, 150))).upper()
    doc += (b"\x1c" if random.random() < 0.2 else b"") + b"\r"

short = (b"HELLO THERE THIS IS A LINE OF TEXT\r" * 600)[:20000]

def work(e):
    r = {}
    load_doc(e, short)                                    # (short lines: little
    e.keys([(KEY["HOME"], 0), (KEY["HOME"], 0)])         # to draw) to the top:
    r["home frames"] = e.peek(MB - 1)[0]                  # a 20 KB block copy
    load_doc(e, doc)
    e.keys([(KEY["HOME"], 0), (KEY["HOME"], 0)])
    e.keys([(KEY["F5"], 0)] * 3)
    e.keys([(KEY["F5"], CBM)] * 3)                        # mark 3 pages ...
    e.keys([(KEY["C"], CTRL)])                            # ... copy them
    r["marked"] = v(e, "sel_on")
    r["text_end"] = v(e, "text_end", 2)
    r["clip_size"] = v(e, "clip_size", 2)
    e.keys([(KEY["F5"], 0)] * 4)
    e.keys([(KEY["V"], CTRL)])                            # paste it further on
    e.keys([(KEY["F3"], 0)] * 2)
    e.keys([(KEY["V"], CTRL)])                            # and once more
    e.keys([(KEY["F5"], 0)])
    e.keys([(KEY["DOWN"], CBM)] * 5)                      # cut a piece
    e.keys([(KEY["X"], CTRL)])
    e.keys([(KEY["HOME"], 0), (KEY["HOME"], 0)])
    e.keys([(KEY["A"], CTRL)])                            # all: to the end
    r["end frames"] = e.peek(MB - 1)[0]
    e.keys([(KEY["RIGHT"], 0)])
    r["text"] = e.text()[0]
    r["late"] = v(e, "late_irqs")
    r["late line"] = v(e, "late_line")
    return r

a = session(0, work)
b = session(128, work)                  # (128 KB: no long documents, so the
                                        # buffer is the same as without)
print("   without an REU: to the top %d frames, CTRL-A %d" % (a["home frames"], a["end frames"]))
print("   with an REU:    to the top %d frames, CTRL-A %d" % (b["home frames"], b["end frames"]))
check("the same text with and without an REU (%d bytes)" % len(a["text"]),
      a["text"] == b["text"] and len(a["text"]) > len(doc), (len(a["text"]), len(b["text"])))
check("marked text copied (without: the clipboard at the top of the buffer)",
      a["marked"] == 1 and a["text_end"] < 0xc800, hex(a["text_end"]))
check("with an REU: the clipboard is in it (none in the buffer)",
      b["text_end"] == 0xc800 and b["clip_size"] == 0xc800 - a["text_end"] and b["clip_size"] > 1000,
      (hex(b["text_end"]), b["clip_size"], 0xc800 - a["text_end"]))
check("the jump to the top is quicker with the REU",
      b["home frames"] * 3 < a["home frames"] * 2, (a["home frames"], b["home frames"]))
check("no line 25/247 IRQ ever late, without an REU", a["late"] == 0, a["late"])
check("... nor with one (its copies wait for them)", b["late"] == 0,
      "%d late, the last on line %d" % (b["late"], b["late line"]))
print("ALL PASS" if ok else "SOME FAILED")
