"""Phase 12: the editor survives the CPU being held up for a while - an
Ultimate's menu button or its network memory access, a freezer cartridge.
The exact-timed strip IRQs then come too late; before the fix (irq_missed in
irq.asm) the second IRQ of the pair ran a frame later with a stale stack
pointer and the program crashed.
Here the hold-ups are REU copies of 32 KB started from VICE's monitor, C64
to REU (reading the C64's memory changes nothing): the CPU stops for about
520 raster lines each time - more than a frame, so a strip IRQ is always
held up.
Run from the project folder:  python tools/test_freeze.py [ntsc|oldntsc]
(On VICE's PAL models the copies don't seem to hold the CPU up at all.)
Needs a debug build (build.bat)."""
import sys, os, time, random
os.environ.pop("MT_REU", None)
from mtest import *

model = sys.argv[1] if len(sys.argv) > 1 else "c64"
ok = True
def check(name, cond, info=""):
    global ok
    print(("PASS " if cond else "FAIL ") + name + ("" if cond else "  " + repr(info)[:200]))
    ok = ok and cond

def v(e, name):
    return e.peek(e.lab[name])[0]

random.seed(12)
vice = start_vice(os.path.join(PROJ, "build/magictypewriter.prg"), model=model,
                  extra=["-reu", "-reusize", "128"])
try:
    e = Editor(Mon())
    e.wait_ready()
    e.type_text("before")
    for i in range(40):
        # 32 KB from C64 $4000 to REU bank 1 (the clipboard's bank: unused)
        regs = bytes([0x00, 0x40, 0, 0, 1, 0x00, 0x80])    # C64 $4000, REU 1:0000, $8000
        e.m.write(0xdf0a, bytes([0]))
        e.m.write(0xdf02, regs)
        e.m.write(0xdf01, bytes([0x90]))
        e.m.resume()
        time.sleep(random.uniform(0.01, 0.15))
    f1 = int.from_bytes(e.peek(e.lab["frame_count"], 2), "little")
    time.sleep(0.5)
    f2 = int.from_bytes(e.peek(e.lab["frame_count"], 2), "little")
    check("the IRQs still run after 40 hold-ups", f2 != f1, (f1, f2))
    print("   strips left out: %d, late: %d" % (v(e, "missed_irqs"), v(e, "late_irqs")))
    if model in ("ntsc", "oldntsc"):
        check("... some strip IRQs did come too late (so the test means something)", v(e, "missed_irqs") > 0)
    elif v(e, "missed_irqs") == 0:
        # (VICE's PAL models seem to run a monitor-started REU copy without
        # holding the CPU up: no IRQ is ever late here, so nothing is
        # tested. The recovery is the same code on every system; NTSC
        # tests it.)
        print("   (no hold-up reached the strips on this model in VICE: use ntsc)")
    e.type_text(" after")
    check("... and typing still works", e.text()[0] == b"BEFORE AFTER", e.text()[0])
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
