"""A mouse button pressed while the keyboard is being scanned (scan_keyboard
in src/input.asm), without VICE: the assembled code runs in a small 6502
emulator (tools/cpu6502.py) with a fake CIA 1 - $DC01 answers from a key
matrix and from port 1, whose lines a mouse button or a joystick pulls low.

Found on Jim's C64 (v0.2, 2026-10-11): clicking the F3/F5 badges over and
over with a 1351 typed "mbcz" or "bcz" now and then and opened the menu.
The left button is the fire line, $DC01 bit 4, the column of M, B, C, Z and
F1: pressed during the scan, it looked like those keys in every row read
after it. scan_keyboard now reads port 1 again after the rows and scans
again if it changed.

Here the left button, the right one (bit 0: DEL, 3, 5, 7, 9, +, POUND, 1)
and a joystick direction go down - and come up again - at every cycle of
the scan in turn: no key event may come of it, that frame or the next. A
key held at the same time must still type, once. And with the new check
taken out, the test must see the old fault.
Run from the project folder:  python tools/test_scan_race.py
Needs a debug build (build.bat): build/magictypewriter.prg, build/main.lbl."""
import os, re, sys
from cpu6502 import CPU

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ok = True
def check(name, cond, info=""):
    global ok
    print(("PASS " if cond else "FAIL ") + name + ("" if cond else "  " + repr(info)[:300]))
    ok = ok and cond

prg = open(os.path.join(PROJ, "build", "magictypewriter.prg"), "rb").read()
load = prg[0] | prg[1] << 8
lab = {}
for line in open(os.path.join(PROJ, "build", "main.lbl")):
    m = re.match(r"\s*(\w+)\s*=\s*\$([0-9a-fA-F]+)", line)
    if m:
        lab[m.group(1)] = int(m.group(2), 16)
src = open(os.path.join(PROJ, "src", "input.asm")).read()
QSIZE = int(re.search(r"^KEY_QUEUE_SIZE\s*=\s*(\d+)", src, re.M).group(1))
CIA1_PRA, CIA1_PRB = 0xdc00, 0xdc01


class Mem(bytearray):
    """64 KB with a fake CIA 1: $DC01 reads the key matrix rows selected
    by $DC00 (a 0 bit selects a row), and port 1's lines (port1)."""
    def __init__(self):
        super().__init__(65536)
        self.matrix = [0] * 8       # per row: 1 bits = keys down
        self.port1 = 0xff           # 0 bits = lines held low
    def __getitem__(self, i):
        if i == CIA1_PRB:
            pra = bytearray.__getitem__(self, CIA1_PRA)
            v = self.port1
            for row in range(8):
                if not pra & (1 << row):
                    v &= ~self.matrix[row] & 0xff
            return v
        return bytearray.__getitem__(self, i)

def fresh(patch_out_rescan=False):
    mem = Mem()
    mem[load:load + len(prg) - 2] = prg[2:]
    if "mailbox_keys" in lab:                     # (no test harness here)
        mem[lab["mailbox_keys"]] = 0x60
    for name, val in (("key_last", 0xff), ("key_timer", 0), ("key_step", 6),
                      ("key_charset", 0), ("key_q_head", 0), ("key_q_tail", 0)):
        mem[lab[name]] = val
    mem[lab["key_restores_seen"]] = mem[lab["key_restores"]]
    for r in range(8):
        mem[lab["key_before"] + r] = 0
    if patch_out_rescan:
        # the new check: CMP key_port1, BNE .port1 - the BNE becomes NOPs
        kp = lab["key_port1"]
        pat = bytes([0xcd, kp & 0xff, kp >> 8, 0xd0])
        at = bytes(mem).find(pat, lab["scan_keyboard"], lab["scan_keyboard"] + 80)
        assert at > 0, "the rescan check is not where it was expected"
        mem[at + 3] = mem[at + 4] = 0xea
    return mem

def frame(mem, change_at=None, port1_after=0xff):
    """one scan_keyboard; port 1 becomes port1_after at cycle change_at.
    Returns the key codes it queued."""
    cpu = CPU(mem)
    if change_at is not None:
        def hook(c):
            if c.cyc >= change_at:
                mem.port1 = port1_after
        cpu.step_hook = hook
    head = mem[lab["key_q_head"]]
    cpu.run(lab["scan_keyboard"])
    codes = []
    i = head
    while i != mem[lab["key_q_head"]]:
        codes.append(mem[lab["key_q_code"] + i])
        i = (i + 1) % QSIZE
    return codes, cpu.cyc

# How long a scan takes (nothing pressed)
mem = fresh()
codes, scan_cycles = frame(mem)
check("nothing pressed: no events", codes == [], codes)
print("   a scan with nothing pressed: %d cycles" % scan_cycles)

def sweep(line_bits, patch_out_rescan=False):
    """port 1 lines line_bits go low at each cycle of the scan in turn (and
    stay low the frame after), or, held from before, come up again at each
    cycle in turn. Returns the events seen: (cycle, press/release, codes)."""
    stray = []
    for t in range(0, scan_cycles + 20):
        for down in (True, False):
            mem = fresh(patch_out_rescan)
            if not down:                               # held from before
                mem.port1 = 0xff & ~line_bits
                frame(mem)
            got = []
            c, _ = frame(mem, t, 0xff & ~line_bits if down else 0xff)
            got += c
            c, _ = frame(mem)                          # the frame after
            got += c
            if got:
                stray.append((t, "press" if down else "release", got))
    return stray

LEFT, RIGHT = 0x10, 0x01               # port 1: fire line, up line
s = sweep(LEFT)
check("left button down or up at any moment of a scan: no key events", not s, s[:4])
s = sweep(RIGHT)
check("right button down or up at any moment of a scan: no key events", not s, s[:4])
s = sweep(LEFT | RIGHT)
check("both buttons at once, at any moment: no key events", not s, s[:4])
s = sweep(0x1f)
check("a joystick pushed (all its lines) at any moment: no key events", not s, s[:4])

# A key held while the button goes down still types - once
A = 10                                                  # row 1, bit 2
mem = fresh()
mem.matrix[1] |= 1 << 2
codes, _ = frame(mem, scan_cycles // 2, 0xff & ~LEFT)
codes2, _ = frame(mem)
check("A held while the left button goes down: A once, nothing else",
      codes + codes2 == [A], codes + codes2)

# Without the new check the test must see the old fault: M, B, C, Z, F1
s = sweep(LEFT, patch_out_rescan=True)
seen = sorted({k for _, _, got in s for k in got})
check("(without the rescan the left button types: %s)" % seen,
      bool(s) and set(seen) <= {4, 12, 20, 28, 36, 44, 60} and {4, 12, 20, 28, 36} <= set(seen),
      seen)

print("ALL PASS" if ok else "SOME FAILED")
sys.exit(0 if ok else 1)
