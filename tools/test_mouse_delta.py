"""The 1351 reading (mouse_sample and pot_delta in src/input.asm), without
VICE: the assembled code runs in a small 6502 emulator (the documented
instructions, tools/cpu6502.py), checked against a Python model; then long runs of
made-up 1351 readings go through the real code: like those of Jim's real
mouse - a count of wobble either way, and now and then, while it moves, one
reading way off - looking for what he saw: drift, a pointer that twitches
while the mouse rests, and jumps; and like VICE's 1351, which moves up to
63 counts between two readings (VICE's mouse.c), looking for moves the
wrong way (the pointer ran into a corner). Three older methods are run
alongside (as models) for comparison: the one before phase 12 (it drifted
down), the first phase 12 fix (bit 0 off first: it twitched) and the
second (the middle of three measured from where the pointer settled: fine
on a real 1351, lost in VICE).
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
STILL = int(re.search(r"^MOUSE_STILL\s*=\s*(\d+)", src, re.M).group(1))
MAX = 28                # the older methods' MOUSE_MAX_STEP
POTX, POTY = 0xd419, 0xd41a

# The 6502 (tools/cpu6502.py)
from cpu6502 import CPU

cpu = CPU(mem)

def s8(v):
    return v - 256 if v > 127 else v

# --- The real code: mouse_sample, both axes ------------------------------
class Real:
    """mouse_sample as assembled. start() is what mouse_frame does on the
    first frame; sample() is one reading of both paddles."""
    def start(self, rx, ry):
        for i, r in enumerate((rx, ry)):
            for name in ("pot_c", "pot_p1", "pot_p2"):
                mem[lab[name] + i] = r
            mem[lab["pot_rest"] + i] = 0
    def sample(self, rx, ry):
        mem[POTX], mem[POTY] = rx, ry
        mem[lab["mouse_acc_x"]] = mem[lab["mouse_acc_y"]] = 0
        cpu.run(lab["mouse_sample"])
        return s8(mem[lab["mouse_acc_x"]]), s8(mem[lab["mouse_acc_y"]])

# --- Models: the method as built and three older ones, one axis ----------
FAR = int(re.search(r"^MOUSE_FAR\s*=\s*(\d+)", src, re.M).group(1))

def sg(v):
    """bits 0-6 as a signed number"""
    v &= 0x7f
    return v - 128 if v >= 64 else v

class New:
    def __init__(self, r):
        self.c = self.p1 = self.p2 = r & 0x7f
        self.rest = 0
    def step(self, r):
        r &= 0x7f
        mid, old = self.p1, self.p2
        self.p2, self.p1 = mid, r
        dnew, dold = sg(r - mid), sg(old - mid)
        if abs(dnew) >= FAR or abs(dold) >= FAR:
            self.c = r                                 # way off: catch up
            return 0
        chosen = mid + sorted((dnew, 0, dold))[1]
        self.rest += sg(chosen - self.c)
        self.c = chosen & 0x7f
        if abs(self.rest) <= STILL:
            return 0
        steps = int(self.rest / 2)                     # rounded towards 0
        self.rest -= 2 * steps
        return steps

class Med3:
    """the second phase 12 fix: the middle of three, from where it settled"""
    def __init__(self, r):
        self.k = self.p1 = self.p2 = r & 0x7f
    def step(self, r):
        r &= 0x7f
        dist = lambda v: ((v - self.k) & 0x7f) ^ 0x40
        mid = sorted((dist(r), dist(self.p1), dist(self.p2)))[1]
        self.p2, self.p1 = self.p1, r
        if 64 - STILL <= mid <= 64 + STILL:
            return 0
        if mid < 64:
            mid += 1
        twice = (mid & 0xfe) - 64
        self.k = (self.k + twice) & 0x7f
        return twice >> 1

class Old:
    """before phase 12: subtract, then halve (rounds down both ways)"""
    def __init__(self, r):
        self.y = r
    def step(self, a):
        d = (a - self.y) & 0x7f
        if d < 0x40:
            s = d >> 1
            if s == 0:
                return 0
            self.y = a
            return 0 if s >= MAX else s
        v = d | 0xc0
        if v == 0xff:
            return 0
        self.y = a
        s = s8(v) >> 1
        return 0 if s < -(MAX - 1) else s

class Bit0:
    """the first phase 12 fix: bit 0 off both, then subtract"""
    def __init__(self, r):
        self.y = r & 0x7e
    def step(self, a):
        new = a & 0x7e
        d = (new - self.y) & 0x7e
        if d >= 0x40:
            d |= 0x80
        self.y = new
        s = s8(d) >> 1
        return s if -(MAX - 1) <= s <= MAX - 1 else 0

# 1. The real code against the model: random readings, both axes
rnd = random.Random(64)
real, mx, my = Real(), None, None
bad = []
for i in range(20000):
    if i % 500 == 0:                                   # now and then, a fresh start
        rx, ry = rnd.randint(0, 255), rnd.randint(0, 255)
        real.start(rx, ry)
        mx, my = New(rx), New(ry)
    rx = (rx + rnd.randint(-12, 12)) & 0xff if rnd.random() < 0.9 else rnd.randint(0, 255)
    ry = (ry + rnd.randint(-12, 12)) & 0xff if rnd.random() < 0.9 else rnd.randint(0, 255)
    got = real.sample(rx, ry)
    want = (mx.step(rx), my.step(ry))
    if got != want:
        bad.append((i, rx, ry, got, want))
check("mouse_sample as assembled = the model (20000 readings, both axes)", not bad, bad[:3])

# 2. Made-up 1351 readings. The mouse's real place is k steps; the SID reads
# 2k + c + noise (c = 0 or 1: where its counts sit; noise -1..+1 or 0..1),
# in bits 0-6, plus $40 as VICE has it.
def reading(k, c, noise):
    return (((2 * k + c + noise) & 0x7f) + 0x40) & 0xff

def to_and_fro(rnd, n, speed):
    """the hand moving the mouse to and fro and resting; ends at the start.
    Returns (places, resting) per reading."""
    k, path, rest = 0, [0], [True]
    for i in range(n):
        target = rnd.randint(-150, 150) if i < n - 1 else 0
        while k != target:
            k += max(-speed, min(speed, target - k))
            path.append(k)
            rest.append(False)
        for _ in range(rnd.randint(6, 30)):
            path.append(k)
            rest.append(True)
    return path, rest

def ramp(rnd, n, vmax):
    """VICE's 1351 under a quick hand: each move speeds up and slows down
    again, up to vmax steps a reading; then a rest."""
    x, path, rest = 0.0, [0], [True]
    for i in range(n):
        top = rnd.uniform(-1, 1) * vmax
        steps = rnd.randint(3, 20)
        for j in range(steps):
            x += top * (1 - abs(2 * j / steps - 1))
            path.append(round(x))
            rest.append(False)
        for _ in range(rnd.randint(4, 15)):
            path.append(round(x))
            rest.append(True)
    return path, rest

def run(kind, path, rest, rnd, c=0, wobble=(-1, 0, 1), spikes=0.0):
    """Feed the readings to one method (axis X only for the models; the real
    code gets the same on both axes). Returns: final error, the largest
    error while resting (after 3 readings of rest), twitches (moves while
    resting after the first: one move may settle the pointer, when the
    wobble nudges it over MOUSE_STILL), the largest change of the error in
    one reading, and moves the wrong way (more than 2 steps against where
    the mouse went over the last 3 readings)."""
    first = reading(path[0], c, 0)
    if kind == "real":
        real.start(first, first)
        step = lambda r: real.sample(r, r)[0]
    else:
        m = {"new": New, "old": Old, "bit0": Bit0, "med3": Med3}[kind](first)
        step = m.step
    pos, worst_rest, twitches, jump, wrong = 0, 0, 0, 0, 0
    err_before, resting_for, last_spike, rest_moves = 0, 0, False, 0
    for i in range(1, len(path)):
        r = reading(path[i], c, rnd.choice(wobble))
        if spikes and not last_spike and not rest[i] and rnd.random() < spikes:
            r = rnd.randint(0, 255)                    # one reading way off
            last_spike = True
        else:
            last_spike = False
        s = step(r)
        pos += s
        if s * (path[i] - path[max(0, i - 3)]) < 0 and abs(s) > 2:
            wrong += 1
        err = pos - (path[i] - path[0])
        resting_for = resting_for + 1 if rest[i] else 0
        if resting_for == 0:
            rest_moves = 0
        if resting_for > 3:
            worst_rest = max(worst_rest, abs(err))
            if s:
                rest_moves += 1
                twitches += rest_moves > 1 or abs(s) > 2
        jump = max(jump, abs(err - err_before))
        err_before = err
    return pos - (path[-1] - path[0]), worst_rest, twitches, jump, wrong

print()
print("%-34s %-6s %6s %6s %8s %6s %6s" % ("readings", "method", "final", "rest", "twitches",
                                         "jump", "wrong"))
cases = [
    # name, speed (below 0: VICE-like speeding up and slowing down), c,
    # wobble, spikes
    ("resting on an even count, +-1", 0, 0, (-1, 0, 1), 0),
    ("resting on an odd count, +-1", 0, 1, (-1, 0, 1), 0),
    ("to and fro slowly, +-1", 1, 1, (-1, 0, 1), 0),
    ("to and fro, +-1", 4, 0, (-1, 0, 1), 0),
    ("to and fro fast, noise bit 0/1", 12, 0, (0, 1), 0),
    ("to and fro, +-1, 3% way off", 4, 1, (-1, 0, 1), 0.03),
    ("to and fro slowly, +-1, 3% way off", 2, 0, (-1, 0, 1), 0.03),
    ("to and fro, +-1, 10% way off", 6, 0, (-1, 0, 1), 0.10),
    ("to and fro fast, +-1, 3% way off", 10, 0, (-1, 0, 1), 0.03),
    ("VICE: to and fro, 20 steps", 20, 0, (0, 1), 0),
    ("VICE: up to 23 steps", -23, 0, (0, 1), 0),
    ("VICE: up to 31 steps (its limit)", -31, 0, (0, 1), 0),
    ("VICE: to and fro, 28 steps", 28, 0, (0, 1), 0),
]
for name, speed, c, wobble, spikes in cases:
    rnd = random.Random(name)
    if speed == 0:
        path, rest = [0] * 3000, [True] * 3000
    elif speed > 0:
        path, rest = to_and_fro(rnd, 60, speed)
    else:
        path, rest = ramp(rnd, 80, -speed)
    results = {}
    for kind in ("old", "bit0", "med3", "real"):
        results[kind] = run(kind, path, rest, random.Random(name + "x"), c, wobble, spikes)
        f, w, t, j, wr = results[kind]
        print("%-34s %-6s %6d %6d %8d %6d %6d" % (name if kind == "old" else "", kind,
                                                  f, w, t, j, wr))
    f, w, t, j, wr = results["real"]
    fast = abs(speed)
    # Never twitching. The pointer lags one reading (speed steps) behind
    # while moving, and may catch up a reading early (twice the speed at
    # most) - but never jumps off somewhere else. Without readings way off
    # it never goes the wrong way, and, slower than MOUSE_FAR, every count
    # arrives: the pointer may sit up to (MOUSE_STILL + 1) / 2 = 2 steps
    # from the mouse. A reading way off, or VICE faster than MOUSE_FAR,
    # loses the move of a reading or two (not checked); two readings way off
    # close together can send it a little the wrong way (see 3.). Known: at
    # 10 steps a reading (a fling across the screen), a reading way off in
    # the middle can look like a fast move, as VICE makes them, and may
    # count: so a reading's error may reach 3 x the speed there.
    good = t == 0 and j <= (3 * fast if spikes and fast >= 10 else 2 * fast + 2)
    if not spikes:
        good = good and wr == 0
        if 2 * fast < FAR:
            good = good and abs(f) <= 2 and w <= 2
    check("  no drift, no twitching, no jumps" + ("" if spikes else ", never the wrong way"),
          good, results["real"])

# 3. Readings way off, many runs at a real 1351's speeds (the model, which
# 1. showed to be the code): moves the wrong way, against the method Jim
# tried on his C64 (med3) - no more of them, and none bigger.
print()
for speed in (1, 2, 4, 6):
    for rate in (0.01, 0.03):
        res = {}
        for kind in ("med3", "new"):
            wrong, biggest, readings = 0, 0, 0
            for seed in range(30):
                path, rest = to_and_fro(random.Random(seed), 40, speed)
                rnd = random.Random(seed + 1000)
                m = {"med3": Med3, "new": New}[kind](reading(path[0], 0, 0))
                last_spike = False
                for i in range(1, len(path)):
                    r = reading(path[i], 0, rnd.choice((-1, 0, 1)))
                    if not last_spike and not rest[i] and rnd.random() < rate:
                        r = rnd.randint(0, 255)
                        last_spike = True
                    else:
                        last_spike = False
                    st = m.step(r)
                    readings += 1
                    if st * (path[i] - path[max(0, i - 3)]) < 0 and abs(st) > 2:
                        wrong += 1
                        biggest = max(biggest, abs(st))
            res[kind] = (wrong, biggest)
        print("%d steps a reading, %d%% way off, %d readings: med3 %d wrong (up to %d steps), "
              "now %d (up to %d)" % (speed, rate * 100, readings, res["med3"][0], res["med3"][1],
                                      res["new"][0], res["new"][1]))
        check("  no more moves the wrong way than med3, none bigger",
              res["new"][0] <= res["med3"][0] and res["new"][1] <= res["med3"][1], res)


print("ALL PASS" if ok else "SOME FAILED")
