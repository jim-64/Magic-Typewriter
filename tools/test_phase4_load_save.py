"""Phase 4: load SAMPLE, edit, CTRL-S, errors (file not found, no device), load LONG.
Run from the project folder:  python tools/test_phase4_load_save.py [c64|ntsc]
Needs a debug build and the .d64 (build.bat)."""
import sys, time, shutil, subprocess, os
from mtest import *

S = WORK
model = sys.argv[1] if len(sys.argv) > 1 else "c64"
disk = os.path.join(S, "p4.d64")
shutil.copy(os.path.join(PROJ, "build/magictypewriter.d64"), disk)
vice = start_vice(os.path.join(PROJ, "build/magictypewriter.prg"), disk=disk, model=model)
ok = True
def check(name, cond, info=""):
    global ok
    print(("PASS " if cond else "FAIL ") + name + ("" if cond else "  " + str(info)))
    ok = ok and cond

try:
    e = Editor(Mon())
    e.wait_ready()
    sample = open(os.path.join(PROJ, "test/sample.seq"), "rb").read()
    # its first byte, $0e, is the character set: it becomes the setting,
    # not text
    assert sample[0] == 0x0e

    # 1. Load SAMPLE
    e.keys([(KEY["L"], CTRL)])
    rows = e.screen_rows()
    check("load box shows LOAD:", "LOAD:" in rows[12], rows[12])
    e.type_text("sample")
    e.keys([(KEY["RETURN"], 0)], settle=0.5)
    for _ in range(100):                      # wait for the load to finish
        txt, cur = e.text()
        if len(txt) == len(sample) - 1:
            break
        time.sleep(0.2)
    time.sleep(0.5)
    txt, cur = e.text()
    check("loaded text = test/sample.seq without its leading $0e", txt == sample[1:], (len(txt), len(sample)))
    check("cursor at the start", cur <= 1, cur)
    check("upper/lower case set chosen by the leading $0e", e.peek(0xd018)[0] & 2 == 2)
    rows = e.screen_rows()
    print("   row 0:", rows[0]); print("   row 2:", rows[2])
    check("text on screen", rows[0][1:].startswith("agic Typewriter"), rows[0])   # (col 0 may show the cursor)

    # 2. Edit and CTRL-S (saves under the same name: scratch, then write)
    e.type_text("x")
    e.keys([(KEY["S"], CTRL)], settle=0.5)
    for _ in range(100):
        if e.peek(e.lab["modified"])[0] == 0:
            break
        time.sleep(0.2)
    saved_ok = e.peek(e.lab["modified"])[0] == 0
    check("saved (modified flag cleared)", saved_ok)
    if not saved_ok:
        print("   key log:", e.peek(MB + 53, 8).hex(), "count", e.count(),
              "name len", e.peek(e.lab["file_name_len"])[0])
        for r in e.screen_rows()[:14]:
            print("   |", r)

    # 3. Load a file that is not there: error box, document unchanged
    before, _ = e.text()
    e.keys([(KEY["L"], CTRL)])
    e.keys([(KEY["DEL"], 0)] * 6)
    e.type_text("nofile")
    e.keys([(KEY["RETURN"], 0)], settle=1.0)
    for _ in range(50):
        rows = e.screen_rows()
        if "NOT FOUND" in rows[12].upper():
            break
        time.sleep(0.2)
    print("   box:", rows[12].strip())
    check("error box: 62, FILE NOT FOUND", "62, FILE NOT FOUND" in rows[12].upper(), rows[12])
    e.keys([(KEY["SPACE"], 0)])               # close the box
    after, _ = e.text()
    check("document unchanged after the error", after == before)

    # 4. Device 9 is not there
    e.poke(e.lab["load_dev"], [9])
    e.keys([(KEY["L"], CTRL)])
    e.keys([(KEY["RETURN"], 0)], settle=1.0)
    for _ in range(50):
        rows = e.screen_rows()
        if "DEVICE" in rows[12].upper():
            break
        time.sleep(0.2)
    print("   box:", rows[12].strip())
    check("error box: DEVICE NOT PRESENT", "DEVICE NOT PRESENT" in rows[12].upper(), rows[12])
    e.keys([(KEY["SPACE"], 0)])
    e.poke(e.lab["load_dev"], [8])

    # 5. Load LONG (60 lines)
    long_ = open(os.path.join(PROJ, "test/long.seq"), "rb").read()
    e.keys([(KEY["L"], CTRL)])
    e.keys([(KEY["DEL"], 0)] * 6)
    e.type_text("long")
    e.keys([(KEY["RETURN"], 0)], settle=0.5)
    for _ in range(100):
        txt, cur = e.text()
        if len(txt) == len(long_):
            break
        time.sleep(0.2)
    txt, cur = e.text()
    check("LONG loaded (no case code: all of it is text)", txt == long_, len(txt))
    rows = e.screen_rows()
    check("LONG on screen", rows[0].strip().lower()[1:] == "ine 01", rows[0])   # (col 0 may show the cursor)

    # 5b. Load UPPER: starts with $8e, so the upper case/graphics set, and
    # the $8e is not text
    upper = open(os.path.join(PROJ, "test/upper.seq"), "rb").read()
    e.keys([(KEY["L"], CTRL)])
    e.keys([(KEY["DEL"], 0)] * 6)
    e.type_text("upper")
    e.keys([(KEY["RETURN"], 0)], settle=0.5)
    for _ in range(100):
        txt, cur = e.text()
        if len(txt) == len(upper) - 1:
            break
        time.sleep(0.2)
    check("UPPER loaded", e.text()[0] == upper[1:])
    check("upper case/graphics set chosen by $8e", e.peek(0xd018)[0] & 2 == 0)

    # 6. Display back to normal after disk use: raster IRQ on, sprites on
    check("raster IRQ back on", e.peek(0xd01a)[0] & 1 == 1)
    # (all five icons, or the F5 badges below the top strip; the pointer,
    # sprite 0, stays off: there is no mouse)
    check("sprites back on", e.peek(0xd015)[0] in (0x3e, 0x30), hex(e.peek(0xd015)[0]))
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

# 7. What did the save write? Read it back from the disk image.
out = "sample_saved.seq"
if os.path.exists(out):
    os.remove(out)
c1541 = r"C:/bin/GTK3VICE-3.9-win64/GTK3VICE-3.9-win64/bin/c1541.exe"
print(subprocess.run([c1541, "-attach", "p4.d64", "-read", "sample,s", out], capture_output=True, text=True, cwd=S).stdout[-200:])
out = os.path.join(S, out)
saved = open(out, "rb").read() if os.path.exists(out) else b""
check("saved file = $0e (upper/lower set) + 'x' typed at the cursor + the rest",
      saved == b"" + b"X" + sample[1:], saved[:8])
listing = subprocess.run([c1541, "-attach", disk, "-list"], capture_output=True, text=True).stdout
print(listing)
print("ALL PASS" if ok else "SOME FAILED")
