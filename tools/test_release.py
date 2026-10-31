"""Phase 12: the release build (no test mailbox) starts and runs on every
video system - PAL, NTSC, old NTSC, Drean - with no REU, a 128 KB one and a
512 KB one (long documents). It can't be typed into (no mailbox), so it
checks what it can from outside: the IRQs run (the frame counter moves),
the system and the REU are found, the text buffer is the right size, the
sprites are on and the ROMs out. Then the same with the program packed by
Exomizer, as on the release disk (if Exomizer is on the PATH, or at
C:/bin/exomizer.exe), with no REU and a 512 KB one.
Run from the project folder:  python tools/test_release.py
It assembles its own release copy into build/release/, so the debug build
the other tests use stays as it is."""
import sys, os, time, subprocess, shutil
os.environ.pop("MT_REU", None)          # this test chooses the REU itself
from mtest import *
import mtest

OUT = os.path.join(PROJ, "build", "release")
os.makedirs(OUT, exist_ok=True)
PRG = os.path.join(OUT, "magictypewriter.prg")
LBL = os.path.join(OUT, "main.lbl")
ACME = r"C:/bin/acme0.97win/acme/acme.exe"
if not os.path.exists(ACME):
    ACME = shutil.which("acme") or "acme"          # (Linux: on the PATH)
r = subprocess.run([ACME, "-f", "cbm", "-DDEBUG=0", "-o", PRG, "-l", LBL,
                    os.path.join(PROJ, "src", "main.asm")], cwd=PROJ, capture_output=True, text=True)
if r.returncode:
    print(r.stdout, r.stderr)
    sys.exit("release build failed")
lab = {}
for line in open(LBL):
    m = mtest.re.match(r"\s*(\S+)\s*=\s*\$([0-9a-fA-F]+)", line)
    if m:
        lab[m.group(1)] = int(m.group(2), 16)

ok = True
def check(name, cond, info=""):
    global ok
    print(("PASS " if cond else "FAIL ") + name + ("" if cond else "  " + repr(info)))
    ok = ok and cond

def peek(m, addr, n=1):
    d = m.read(addr, n)
    m.resume()
    return d

EXO = shutil.which("exomizer") or r"C:/bin/exomizer.exe"
PACKED = os.path.join(OUT, "magictypewriter-packed.prg")
runs = [(PRG, "", reu) for reu in (0, 128, 512)]
if os.path.exists(EXO) or shutil.which(EXO):
    r = subprocess.run([EXO, "sfx", "sys", "-x1", "-q", "-o", PACKED, PRG], capture_output=True, text=True)
    check("Exomizer packs the release build (%d -> %d bytes)" % (os.path.getsize(PRG),
          os.path.getsize(PACKED) if os.path.exists(PACKED) else 0), r.returncode == 0, r.stdout + r.stderr)
    runs += [(PACKED, "packed, ", reu) for reu in (0, 512)]
else:
    print("(Exomizer not found: the packed program is not tried)")

for model, want_sys in (("c64", 0), ("ntsc", 1), ("oldntsc", 2), ("drean", 3)):
    for prg, kind, reu in runs:
        extra = ["-reu", "-reusize", str(reu)] if reu else []
        vice = start_vice(prg, model=model, extra=extra)
        try:
            m = Mon()
            frames = lambda: int.from_bytes(peek(m, lab["frame_count"], 2), "little")
            t0 = time.time()
            while frames() < 50 and time.time() - t0 < 30:       # started?
                time.sleep(0.3)
            f1 = frames()
            time.sleep(1)
            f2 = frames()
            sysb = peek(m, lab["system_type"])[0]
            banks = peek(m, lab["reu_banks"])[0]
            docs = peek(m, lab["reu_docs"])[0]
            top = int.from_bytes(peek(m, lab["buf_top"], 2), "little")
            te = int.from_bytes(peek(m, 0x1a, 2), "little")
            spr = peek(m, 0xd015)[0]
            cpu = peek(m, 0x01)[0]
            mb = peek(m, MB, 4)
            name = "%s%s, REU %d KB" % (kind, model, reu)
            long_docs = reu >= 192
            check(name + ": runs (frame counter %d -> %d in a second)" % (f1, f2),
                  (f2 - f1) & 0xffff != 0)                  # (16 bits: it wraps)
            check(name + ": system %d, %d REU banks, long documents %s, text to $%04x"
                  % (sysb, banks, "on" if docs else "off", te),
                  sysb == want_sys and banks == {0: 0, 128: 2, 512: 8}[reu]
                  and docs == long_docs and te == top == (0xb800 if long_docs else 0xc800))
            # (between the top strip and line 10 sprites 1-3 are off: $30)
            check(name + ": badges on ($d015 = $%02x), ROMs out ($01 = $%02x), no mailbox" % (spr, cpu),
                  spr & 0x30 == 0x30 and cpu & 7 == 5 and mb != b"MTDB")
        finally:
            try:
                m.quit()
            except Exception:
                pass
            try:
                vice.wait(timeout=10)
            except Exception:
                vice.terminate()
            time.sleep(1)
print("ALL PASS" if ok else "SOME FAILED")
