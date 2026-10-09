"""Phase 8: menus, settings, Stats, Load/Save menus, disk directory and
command, Save defaults (and reading them at start-up), Quit, CTRL-F Find.
Run from the project folder:  python tools/test_phase8.py [c64|ntsc]
Needs a debug build and the .d64 (build.bat)."""
import sys, os, re, time, shutil, subprocess
from mtest import *

model = sys.argv[1] if len(sys.argv) > 1 else "c64"
S = WORK
disk = os.path.join(S, "p8.d64")
shutil.copy(os.path.join(PROJ, "build/magictypewriter.d64"), disk)
C1541 = r"C:/bin/GTK3VICE-3.9-win64/GTK3VICE-3.9-win64/bin/c1541.exe"
ok = True
def check(name, cond, info=""):
    global ok
    print(("PASS " if cond else "FAIL ") + name + ("" if cond else "  " + repr(info)[:300]))
    ok = ok and cond

RED = 0x1c
TITLE_ROW, ITEM_ROW = 5, 7

def load_doc(e, doc):
    te = int.from_bytes(e.peek(0x1a, 2), "little")
    e.m.write(te - len(doc), doc)
    e.m.write(0x08, (0x4000).to_bytes(2, "little") + (te - len(doc)).to_bytes(2, "little"))
    e.m.write(MB + 63, [1])
    e.m.resume()
    for _ in range(100):
        if e.peek(MB + 63)[0] == 0:
            break
        time.sleep(0.1)
    time.sleep(0.5)

def v(e, name):
    return e.peek(e.lab[name])[0]

def rows(e):
    return [r.upper() for r in e.screen_rows()]

def key(e, name, mods=0, settle=0.4):
    e.keys([(KEY[name], mods)], settle=settle)

def kernal_key(e, text=b" "):
    """a key for the KERNAL (while the disk is in use our scanner is paused)"""
    e.m.cmd(0x72, bytes([len(text)]) + text)
    e.m.resume()

def wait_for(e, cond, timeout=30):
    t0 = time.time()
    while time.time() - t0 < timeout:
        if cond():
            return True
        time.sleep(0.2)
    return False

def stats_model(doc):
    chars = words = sent = 0
    in_word = ended = False
    for b in doc:
        eol = b in (0x0d, 0x8d)
        if not eol and (b & 0x7f) < 0x20:
            continue                        # a code
        chars += 1
        if eol or b in (0x20, 0xa0):
            in_word = False
            if ended:
                sent += 1
                ended = False
            continue
        if not in_word:
            words += 1
            in_word = True
        ended = b in b".!?"
    if ended:
        sent += 1
    return chars, words, sent

vice = start_vice(os.path.join(PROJ, "build/magictypewriter.prg"), disk=disk, model=model)
try:
    e = Editor(Mon())
    e.wait_ready()
    doc = (b"THE QUICK BROWN FOX. JUMPS OVER\rTHE LAZY DOG!  NOT THE QU" + bytes([RED])
           + b"ICK ONE...\rLAST LINE? YES\r")
    load_doc(e, doc)

    # The main menu
    key(e, "F1")
    r = rows(e)
    check("F1: the main menu", "MAGIC TYPEWRITER" in r[TITLE_ROW] and "A LOAD" in r[ITEM_ROW], r[TITLE_ROW:ITEM_ROW + 2])
    check("settings show their values", "D WORDWRAP: ON" in r[ITEM_ROW + 3]
          and "H TEXT COLOR: LIGHT GREY" in r[ITEM_ROW + 7] and "X EXIT" in r[ITEM_ROW + 11], r[ITEM_ROW + 3:ITEM_ROW + 12])

    # Settings step through their values
    key(e, "D")
    check("D: wordwrap off", v(e, "wrap_on") == 0 and "WORDWRAP: OFF" in rows(e)[ITEM_ROW + 3])
    key(e, "D")
    check("D again: on", v(e, "wrap_on") == 1)
    key(e, "E")
    check("E: overwrite", v(e, "edit_mode") == 1 and "MODE: OVERWRITE" in rows(e)[ITEM_ROW + 4])
    key(e, "E")
    key(e, "F")
    check("F: mark key left shift", v(e, "mark_key") == 0 and "MARK KEY: LEFT SHIFT" in rows(e)[ITEM_ROW + 5])
    key(e, "F")
    key(e, "G")
    check("G: background white", v(e, "text_bg") == 1 and "BACKGROUND: WHITE" in rows(e)[ITEM_ROW + 6])
    # The pointer's color for each background (Jim, 2026-10-08): light green
    # (13), green (5) on white, cyan, purple, yellow, light green, light grey
    POINTER = [13, 5, 13, 5, 5, 13, 13, 5, 13, 13, 13, 13, 13, 5, 13, 5]
    # The menus' color for each background (Jim, 2026-10-09): black on white,
    # cyan, green, yellow, light red, grey, light green and light grey,
    # light grey on the others - whatever the text color
    MENU = [0 if c in (1, 3, 5, 7, 10, 12, 13, 15) else 15 for c in range(16)]
    def menu_color():                           # (the title's color RAM)
        return e.peek(0xd800 + TITLE_ROW * 40 + 12)[0] & 15
    pointer, menu = {}, {}
    for _ in range(16):                         # white, red, ... round to black
        bg = v(e, "text_bg")
        pointer[bg] = e.peek(0xd027)[0] & 15
        menu[bg] = menu_color()
        key(e, "G", settle=0.3)
    check("... round the 16 back to white", v(e, "text_bg") == 1)
    check("... the pointer's color right on every background",
          all(pointer[c] == POINTER[c] for c in range(16)), pointer)
    check("... the menus black or light grey, by background",
          all(menu[c] == MENU[c] for c in range(16)), menu)
    key(e, "H")                                 # another text color: the
    check("... another text color: the menus as they were",  # menus stay so
          v(e, "text_color") != 15 and menu_color() == MENU[1], (v(e, "text_color"), menu_color()))
    for _ in range(15):
        key(e, "H", settle=0.1)
    check("... the text color back to light grey", v(e, "text_color") == 15, v(e, "text_color"))
    for _ in range(15):
        key(e, "G", settle=0.1)
    check("... the background back to black", v(e, "text_bg") == 0, v(e, "text_bg"))

    # Submenus: A opens Load, X backs out
    key(e, "A")
    r = rows(e)
    check("A: the Load menu", "LOAD" in r[TITLE_ROW] and "MAGIC" not in r[TITLE_ROW] and "B FORMAT: PETSCII" in r[ITEM_ROW + 1]
          and "C DEVICE: 8" in r[ITEM_ROW + 2], r[TITLE_ROW:ITEM_ROW + 6])
    check("... no leftovers of the main menu in the panel", r[ITEM_ROW + 7].strip("\u2502 ") == "" or "EXIT" not in r[ITEM_ROW + 11],
          r[ITEM_ROW + 6:ITEM_ROW + 12])
    key(e, "C")
    check("C: device tape", v(e, "load_dev") == 1 and "DEVICE: TAPE" in rows(e)[ITEM_ROW + 2])
    key(e, "C")
    check("C again: device 9", v(e, "load_dev") == 9)
    for _ in range(6):
        key(e, "C", settle=0.1)
    check("... round to 8", v(e, "load_dev") == 8)
    key(e, "X")
    check("X: back to the main menu", "MAGIC TYPEWRITER" in rows(e)[TITLE_ROW])
    key(e, "X")
    check("X again: closed", "MAGIC TYPEWRITER" not in rows(e)[TITLE_ROW] and e.text()[0] == doc)

    # RUN/STOP and <- close all the menus, from a submenu too
    key(e, "F1"); key(e, "B")
    key(e, "STOP")
    check("RUN/STOP closes all (from the Save menu)", "SAVE" not in rows(e)[TITLE_ROW])
    key(e, "STOP")
    check("RUN/STOP in the text: the menu", "MAGIC TYPEWRITER" in rows(e)[TITLE_ROW])
    key(e, "LEFTARROW")
    check("<- closes it", "MAGIC TYPEWRITER" not in rows(e)[TITLE_ROW])

    # The mouse: click on an item's row; the menu icon closes
    e.mouse([(1, 0, 0)])
    key(e, "F1")
    e.move_to(24 + 8 * 8, 51 + 8 * (ITEM_ROW + 3) + 1)
    e.mouse([(0, 0, 1), (0, 0, 0)])
    check("mouse click on D WORDWRAP: off", v(e, "wrap_on") == 0)
    e.mouse([(0, 0, 1), (0, 0, 0)])
    check("... and on again", v(e, "wrap_on") == 1)
    e.move_to(40, 40)                   # the menu icon
    e.mouse([(0, 0, 1), (0, 0, 0)])
    check("click on the menu icon: closed", "MAGIC TYPEWRITER" not in rows(e)[TITLE_ROW])
    e.mouse([(0, 0, 2), (0, 0, 0)])
    check("right button: the menu", "MAGIC TYPEWRITER" in rows(e)[TITLE_ROW])
    e.mouse([(0, 0, 2), (0, 0, 0)])
    check("right button again: closed", "MAGIC TYPEWRITER" not in rows(e)[TITLE_ROW])

    # Stats
    key(e, "F1"); key(e, "I", settle=1.5)
    r = rows(e)
    nums = [int(re.findall(r"(\d+)\s*\S?\s*$", r[ITEM_ROW + i])[0]) for i in range(3)]
    free = re.findall(r"(\d+) \((\d+)%\)", r[ITEM_ROW + 3])
    exp = stats_model(doc)
    gap = int.from_bytes(e.peek(0x0a, 2), "little") - int.from_bytes(e.peek(0x08, 2), "little")
    check("Stats: characters, words, sentences as counted here", tuple(nums) == exp, (nums, exp))
    check("Stats: free = the gap, with its share of the 35 KB buffer",
          free and int(free[0][0]) == gap and int(free[0][1]) == gap * 100 // 0x8c00, (r[ITEM_ROW + 3], gap))
    check("Stats: no 'any key' line", not any("ANY KEY" in x for x in r), r[ITEM_ROW + 4:ITEM_ROW + 10])
    key(e, "SPACE")
    check("any key: back to the menu", "MAGIC TYPEWRITER" in rows(e)[TITLE_ROW])

    # Print: no printer in this test VICE
    key(e, "C"); key(e, "A")
    check("Print, no printer: 'device not present'", "DEVICE NOT PRESENT" in rows(e)[12], rows(e)[12])
    key(e, "SPACE")

    # Save menu: A saves under a name
    key(e, "F1"); key(e, "B"); key(e, "A")
    check("Save menu A: asks for a name", "SAVE:" in rows(e)[12], rows(e)[12])
    e.type_text("phase8")
    key(e, "RETURN", settle=0.5)
    check("saved (modified cleared)", wait_for(e, lambda: v(e, "modified") == 0))

    # A name with * ? or , is refused: the scratch that comes first would
    # take other files with it ("S0:SA*" = every file starting with SA)
    key(e, "F1"); key(e, "B"); key(e, "A")
    e.keys([(KEY["DEL"], 0)] * 6)
    e.type_text("sa*")
    key(e, "RETURN", settle=0.5)
    check("Save as 'SA*': refused", "NO * ? OR , IN A FILE NAME" in rows(e)[12], rows(e)[12])
    key(e, "SPACE")

    # Disk command (empty: the status) and disk directory, from the Load menu
    key(e, "F1"); key(e, "A"); key(e, "E")
    check("Disk command: asks", "COMMAND:" in rows(e)[12], rows(e)[12])
    key(e, "RETURN", settle=0.5)
    check("empty command: the drive's status", wait_for(e, lambda: "00, OK" in rows(e)[12]), rows(e)[12])
    key(e, "SPACE")
    # A key already in the KERNAL's buffer (as the D key, still held when
    # the KERNAL starts reading the keyboard, used to be) must not end it
    memptr = e.peek(0xd018)[0]
    e.poke(0x0277, [0x44]); e.poke(0xc6, [1])
    key(e, "D", settle=0.3)
    check("Disk directory: listed", wait_for(e, lambda: any("PHASE8" in x for x in rows(e))), rows(e)[:5])
    time.sleep(2)
    r = rows(e)
    check("... and it stays (a key collected before it does not end it)",
          any("PHASE8" in x for x in r) and e.peek(0xc6)[0] == 0, (e.peek(0xc6), r[:3]))
    check("... with the disk's name and the program", "MAGIC TYPEWRITER" in r[0] and any("SEQ" in x for x in r), r[:6])
    check("... no 'any key' line at the end", not any("ANY KEY" in x for x in r), r[24])
    e.poke(0xd018, [memptr ^ 2])                   # C= + SHIFT in the listing
    for _ in range(10):                            # any key: back
        kernal_key(e)
        if wait_for(e, lambda: "LOAD" in rows(e)[TITLE_ROW] and "MAGIC" not in rows(e)[TITLE_ROW], 3):
            break
    check("any key: back to the Load menu", "LOAD" in rows(e)[TITLE_ROW]
          and "MAGIC" not in rows(e)[TITLE_ROW], rows(e)[TITLE_ROW])
    check("... the character set as before the listing", e.peek(0xd018)[0] == memptr, (e.peek(0xd018), memptr))
    key(e, "X")

    # Save defaults: needs the disk the program came from
    e.poke(e.lab["load_device"], [0])
    key(e, "J")
    check("Save defaults, not loaded from disk: says so", "DEFAULTS NEED A DISK" in rows(e)[12], rows(e)[12])
    key(e, "SPACE")
    e.poke(e.lab["load_device"], [8])
    key(e, "G"); key(e, "G"); key(e, "G")          # background cyan (3)
    key(e, "D")                                     # wordwrap off
    key(e, "J")
    check("Save defaults: saved", wait_for(e, lambda: "DEFAULTS SAVED" in rows(e)[12]), rows(e)[12])
    key(e, "SPACE")
    key(e, "G")                                     # (then back to black
    for _ in range(12):                             # and wordwrap on, so
        key(e, "G", settle=0.1)                     # start-up must bring
    key(e, "D")                                     # them back)
    key(e, "X")
    check("settings put back", v(e, "text_bg") == 0 and v(e, "wrap_on") == 1)

    # CTRL-F Find
    key(e, "HOME"); key(e, "HOME")
    key(e, "F", CTRL)
    check("CTRL-F: FIND:", "FIND:" in rows(e)[12], rows(e)[12])
    e.type_text("quick")
    key(e, "RETURN", settle=0.5)
    def sel():
        e.keys([(KEY["C"], CTRL)])
        return e.clipboard()
    check("found the first QUICK, marked", v(e, "sel_on") == 1 and sel() == b"QUICK", sel())
    key(e, "F", CTRL); key(e, "RETURN", settle=0.5)
    check("CTRL-F RETURN: the next one, over a color code", sel().replace(bytes([RED]), b"") == b"QUICK"
          and bytes([RED]) in sel(), sel())
    key(e, "F", CTRL); key(e, "RETURN", settle=0.5)
    c = e.text()[0]
    check("again: round to the first one (wrapped)", sel() == b"QUICK" and c.index(b"QUICK") < 10, sel())
    key(e, "F", CTRL)
    for _ in range(5):
        key(e, "DEL", settle=0.1)
    e.type_text("zebra")
    key(e, "RETURN", settle=0.5)
    check("not there: 'not found'", "NOT FOUND" in rows(e)[12], rows(e)[12])
    key(e, "SPACE")

    # Quit from the menu, with changes: asks first
    e.type_text("x")
    key(e, "F1"); key(e, "Q")
    check("Q with changes: asks", "QUIT WITHOUT SAVING Y/N" in rows(e)[12], rows(e)[12])
    key(e, "N")
    check("N: still here", v(e, "modified") == 1 and "QUIT" not in rows(e)[12])
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

def read_seq(name):
    out = os.path.join(S, name.replace(" ", "_") + ".out")
    if os.path.exists(out):
        os.remove(out)
    subprocess.run([C1541, "-attach", disk, "-read", name + ",s", out], capture_output=True)
    return open(out, "rb").read() if os.path.exists(out) else b""

out = os.path.join(S, "phase8.out")
if os.path.exists(out):
    os.remove(out)
subprocess.run([C1541, "-attach", disk, "-read", "phase8,p", out], capture_output=True)
saved = open(out, "rb").read() if os.path.exists(out) else b""
check("PHASE8 on disk: a PRG ($4000), the magic header, the case code, the document",
      saved[:2] == b"\x00\x40" and saved[2:6] == b"\x00MTW" and saved[23:] == doc, saved[:26])
d = read_seq("magic t defaults")
exp = bytes([0x00, 0x4d, 0x54, 0x57, 0x31, 0x40 + 13]) + bytes(0x40 + x for x in
      [3, 15, 1, 0, 0, 1, 1, 8, 0, 0, 8, 0, 4]) + b"\r"
check("MAGIC T DEFAULTS on disk: the header with every setting", d == exp, (d, exp))
check("SAMPLE still on disk (the refused 'SA*' scratched nothing)", len(read_seq("sample")) > 20)

# Start again from the disk: the settings come back
vice = start_vice(disk, disk=disk, model=model)
try:
    e = Editor(Mon())
    e.wait_ready()
    time.sleep(2)
    check("start-up from disk: background cyan again", v(e, "text_bg") == 3, v(e, "text_bg"))
    check("... and wordwrap off", v(e, "wrap_on") == 0, v(e, "wrap_on"))
    check("... loaded from device 8", v(e, "load_device") == 8)

    # Loading with a pattern works, but the pattern is no name to save under
    key(e, "F1"); key(e, "A"); key(e, "A")
    e.type_text("sam*")
    key(e, "RETURN", settle=0.5)
    check("load 'SAM*': SAMPLE loaded", wait_for(e, lambda: len(e.text()[0]) > 20), e.text()[0][:20])
    check("... but no name kept (CTRL-S will ask for one)", v(e, "file_name_len") == 0)
finally:
    try:
        e.m.quit()
    except Exception as ex:
        print("quit:", ex)
    try:
        vice.wait(timeout=10)
    except Exception:
        vice.terminate()
print("ALL PASS" if ok else "SOME FAILED")
