"""The 1351 reading (pot_delta in src/input.asm), without VICE: the
assembled routine runs in a small 6502 emulator (just the instructions it
uses), checked against a Python model for every input; then long runs of
made-up 1351 readings - the noise bit, readings off by a step, bad readings -
show whether the pointer drifts. The method before phase 12 (subtract, then
halve) is run alongside for comparison: it drifts the negative way (down the
screen), as Jim's real 1351 did.
Run from the project folder:  python tools/test_mouse_delta.py
Needs a build (build.bat) for build/magictypewriter.prg and build/main.lbl."""
import os, re, random

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ok = True
def check(name, cond, info=""):
    global ok
    print(("PASS " if cond else "FAIL ") + name + ("" if cond else "  " + repr(info)[:300]))
    ok = ok and cond

# The program and its labels
prg = open(os.path.join(PROJ, "build", "magictypewriter.prg"), "rb").read()
load = prg[0] | prg[1] << 8
mem = bytearray(65536)
mem[load:load + len(prg) - 2] = prg[2:]
lab = {}
for line in open(os.path.join(PROJ, "build", "main.lbl")):
    m = re.match(r"\s*(\w+)\s*=\s*\$([0-9a-fA-F]+)", line)
    if m:
        lab[m.group(1)] = int(m.group(2), 16)
src = open(os.path.join(PROJ, "src", "input.asm")).read()
MAX = int(re.search(r"^MOUSE_MAX_STEP\s*=\s*(\d+)", src, re.M).group(1))

# A 6502 with just what pot_delta needs
class CPU:
    def __init__(self, mem):
        self.m = mem
    def nz(self, v):
        self.n = v >> 7
        self.z = int(v == 0)
        return v
    def run(self, pc, a, y, limit=200):
        self.a, self.y, self.c, self.n, self.z = a, y, 0, 0, 0
        m = self.m
        for _ in range(limit):
            op = m[pc]
            b1 = m[(pc + 1) & 0xffff]
            ab = b1 | m[(pc + 2) & 0xffff] << 8
            if op == 0x60:                                  # RTS
                return self.a, self.y
            elif op == 0x29: self.a = self.nz(self.a & b1); pc += 2          # AND #
            elif op == 0x09: self.a = self.nz(self.a | b1); pc += 2          # ORA #
            elif op == 0xa9: self.a = self.nz(b1); pc += 2                   # LDA #
            elif op == 0xad: self.a = self.nz(m[ab]); pc += 3                # LDA abs
            elif op == 0xac: self.y = self.nz(m[ab]); pc += 3                # LDY abs
            elif op == 0x8d: m[ab] = self.a; pc += 3                         # STA abs
            elif op == 0x8c: m[ab] = self.y; pc += 3                         # STY abs
            elif op == 0xee: m[ab] = self.nz((m[ab] + 1) & 0xff); pc += 3    # INC abs
            elif op == 0xa8: self.y = self.nz(self.a); pc += 1               # TAY
            elif op == 0x38: self.c = 1; pc += 1                             # SEC
            elif op == 0x18: self.c = 0; pc += 1                             # CLC
            elif op in (0x69, 0xed):                                         # ADC #, SBC abs
                v = b1 if op == 0x69 else (m[ab] ^ 0xff)
                r = self.a + v + self.c
                self.c = int(r > 0xff)
                self.a = self.nz(r & 0xff)
                pc += 2 if op == 0x69 else 3
            elif op == 0xc9:                                                 # CMP #
                r = (self.a - b1) & 0x1ff
                self.c = int(self.a >= b1)
                self.nz(r & 0xff); pc += 2
            elif op == 0x6a:                                                 # ROR A
                c = self.a & 1
                self.a = self.nz((self.a >> 1) | (self.c << 7))
                self.c = c; pc += 1
            elif op in (0x90, 0xb0, 0x30, 0x10, 0xf0, 0xd0):                 # branches
                take = {0x90: not self.c, 0xb0: self.c, 0x30: self.n, 0x10: not self.n,
                        0xf0: self.z, 0xd0: not self.z}[op]
                pc += 2
                if take:
                    pc += b1 - 256 if b1 > 127 else b1
            else:
                raise RuntimeError("opcode $%02x at $%04x not in the emulator" % (op, pc))
        raise RuntimeError("no RTS")

cpu = CPU(mem)
def asm_delta(a, y):
    return cpu.run(lab["pot_delta"], a, y)

def s8(v):
    return v - 256 if v > 127 else v

# The model of the new method
def new_delta(a, y):
    new = a & 0x7e
    d = (new - y) & 0x7e
    if d >= 0x40:
        d |= 0x80
    step = s8(d) >> 1
    if -(MAX - 1) <= step <= MAX - 1:
        return step & 0xff, new
    return 0, new

# The method before phase 12 (subtract, halve, rounding down both ways)
def old_delta(a, y):
    d = (a - y) & 0x7f
    if d < 0x40:
        s = d >> 1
        if s == 0:
            return 0, y
        if s >= MAX:
            return 0, a
        return s, a
    v = d | 0xc0
    if v == 0xff:
        return 0, y
    s = s8(v) >> 1
    if s < -(MAX - 1):
        return 0, a
    return s & 0xff, a

# 1. The assembled routine against the model, every input
bad = [(a, y) for a in range(256) for y in range(256) if asm_delta(a, y) != new_delta(a, y)]
check("pot_delta as assembled = the model, all 65536 inputs (MOUSE_MAX_STEP %d)" % MAX,
      not bad, [(a, y, asm_delta(a, y), new_delta(a, y)) for a, y in bad[:5]])

# 2. Made-up 1351 readings. The mouse's real place is k steps; the SID reads
# (2k + noise) in bits 0-6, plus $40 (as VICE has it).
def reading(k, noise):
    return ((((2 * k + noise) & 0x7f) + 0x40) & 0xff)

def run(method, moves, rnd, jitter=0.0, glitch=0.0):
    """moves: the real place after each reading. Returns (where the readings
    say it went, where it really went)."""
    k = moves[0]
    kept = reading(k, 0) & 0x7e if method is new_delta else reading(k, 0)
    total = 0
    last_bad = False
    for i, k in enumerate(moves[1:]):
        r = reading(k, rnd.randint(0, 1))
        clean = i >= len(moves) - 5                       # (the last few: good)
        if not clean and rnd.random() < jitter:           # off by a step
            r = reading(k + rnd.choice((-1, 1)), rnd.randint(0, 1))
        if not clean and not last_bad and rnd.random() < glitch:   # a bad one
            r = rnd.randint(0, 255)
            last_bad = True
        else:
            last_bad = False
        step, kept = method(r, kept)
        total += s8(step)
    return total, moves[-1] - moves[0]

def back_and_forth(rnd, n, speed):
    """the hand moving the mouse to and fro, ending where it started"""
    k, path = 0, [0]
    for i in range(n):
        target = rnd.randint(-200, 200) if i < n - 1 else 0
        while k != target:
            k += max(-speed, min(speed, target - k)) if speed else (1 if target > k else -1)
            path.append(k)
        for _ in range(rnd.randint(0, 20)):               # a rest
            path.append(k)
    return path

rnd = random.Random(1351)
cases = [
    ("still, noise bit only", [0] * 20000, 0, 0),
    ("to and fro, slowly, noise bit", back_and_forth(rnd, 300, 1), 0, 0),
    ("to and fro, fast, noise bit", back_and_forth(rnd, 300, 9), 0, 0),
    ("still, 5% of readings off by a step", [0] * 20000, 0.05, 0),
    ("to and fro, 5% off by a step", back_and_forth(rnd, 300, 3), 0.05, 0),
    ("to and fro, 2% bad readings", back_and_forth(rnd, 300, 3), 0, 0.02),
    ("to and fro, both", back_and_forth(rnd, 300, 3), 0.05, 0.02),
]
print()
print("%-38s %10s %10s" % ("readings", "old drift", "new drift"))
for name, path, jit, gl in cases:
    o, real = run(old_delta, path, random.Random(7), jit, gl)
    n, real = run(new_delta, path, random.Random(7), jit, gl)
    print("%-38s %10d %10d   (%d readings)" % (name, o - real, n - real, len(path)))
    if gl == 0:
        check("  new method: no drift at all", n == real, n - real)

# 3. Bad readings: one just inside the limit counts as a move, and if the
# good reading after it is then just outside, nothing takes it back. That
# can leave the pointer off by up to MOUSE_MAX_STEP either way - but it
# must lean neither way: over many runs the average error is near 0 (the
# old method ended up below the true place in every run).
import statistics
errs_new, errs_old = [], []
for seed in range(100):
    path = back_and_forth(random.Random(seed), 100, 3)
    o, real = run(old_delta, path, random.Random(seed + 1000), 0.05, 0.02)
    n, real = run(new_delta, path, random.Random(seed + 1000), 0.05, 0.02)
    errs_new.append(n - real)
    errs_old.append(o - real)
def lean(e):
    return statistics.mean(e) / (statistics.stdev(e) / len(e) ** 0.5)
print("100 runs with bad readings: old method below in %d, average %.0f; new method below in %d,"
      " above in %d, average %.1f" % (sum(x < 0 for x in errs_old), statistics.mean(errs_old),
      sum(x < 0 for x in errs_new), sum(x > 0 for x in errs_new), statistics.mean(errs_new)))
check("  new method: bad readings lean neither way (|t| < 3)", abs(lean(errs_new)) < 3,
      lean(errs_new))

# 4. A swipe faster than the readings: the far reading moves nothing, and
# moves go on from it.
step1, kept = new_delta(reading(30, 0), reading(0, 0) & 0x7e)
step2, kept = new_delta(reading(31, 0), kept)
step3, kept = new_delta(reading(33, 1), kept)
check("a far reading moves nothing; moves go on from it",
      (step1, s8(step2), s8(step3)) == (0, 1, 2), (step1, s8(step2), s8(step3)))

print("ALL PASS" if ok else "SOME FAILED")
