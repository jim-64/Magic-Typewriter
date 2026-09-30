"""Phase 4: new document + CTRL-S asks for a name, load-with-changes question.
Arguments: [c64|ntsc] [ro]  (ro = write-protected disk)
Run from the project folder:  python tools/test_phase4_new_doc.py [c64|ntsc]
Needs a debug build and the .d64 (build.bat)."""
import sys, time, shutil, subprocess, os
from mtest import *

S = WORK
model = sys.argv[1] if len(sys.argv) > 1 else "c64"
readonly = len(sys.argv) > 2 and sys.argv[2] == "ro"
disk = os.path.join(S, "p4b.d64")
shutil.copy(os.path.join(PROJ, "build/magictypewriter.d64"), disk)
extra = ["-attach8ro"] if readonly else []
vice = start_vice(os.path.join(PROJ, "build/magictypewriter.prg"), disk=disk, model=model, extra=extra)
ok = True
def check(name, cond, info=""):
    global ok
    print(("PASS " if cond else "FAIL ") + name + ("" if cond else "  " + str(info)))
    ok = ok and cond

def box():
    return e.screen_rows()[12].strip()

try:
    e = Editor(Mon())
    e.wait_ready()
    check("system", e.peek(MB + 6)[0] == {"c64": 0, "ntsc": 1}[model])

    # A new document: type, then CTRL-S asks for a name
    e.type_text("hello disk")
    e.keys([(KEY["RETURN"], 0)])
    e.keys([(KEY["S"], CTRL)])
    check("CTRL-S on a new document asks for a name", "SAVE:" in box(), box())
    e.keys([(KEY["STOP"], 0)])                          # cancel
    check("RUN/STOP cancels the name box", "SAVE:" not in box() and e.peek(e.lab["modified"])[0] == 1, box())
    e.keys([(KEY["S"], CTRL)])
    e.type_text("note")
    e.keys([(KEY["RETURN"], 0)], settle=1.0)
    for _ in range(100):
        rows = e.screen_rows()
        if readonly and "WRITE PROTECT" in rows[12].upper():
            break
        if not readonly and e.peek(e.lab["modified"])[0] == 0:
            break
        time.sleep(0.2)
    if readonly:
        print("   box:", box())
        check("write protected disk: error box", "26, WRITE PROTECT ON" in box().upper(), box())
        e.keys([(KEY["SPACE"], 0)])
        check("still marked as changed", e.peek(e.lab["modified"])[0] == 1)
    else:
        check("saved as NOTE", e.peek(e.lab["modified"])[0] == 0)

        # Change it, then Load: asks first; N keeps the document
        e.type_text("more")
        doc_before, _ = e.text()
        e.keys([(KEY["F1"], 0), (KEY["A"], 0), (KEY["A"], 0)])   # Load menu: Load
        check("load with changes asks first", "LOAD WITHOUT SAVING Y/N" in box().upper(), box())
        e.keys([(KEY["N"], 0)])
        check("N keeps the document", e.text()[0] == doc_before)
        # Y goes on to the name box, with the last name filled in
        e.keys([(KEY["F1"], 0), (KEY["A"], 0), (KEY["A"], 0)])   # Load menu: Load
        e.keys([(KEY["Y"], 0)])
        check("name box shows the last name", "LOAD: NOTE" in box().upper(), box())
        e.keys([(KEY["RETURN"], 0)], settle=1.0)
        for _ in range(100):
            txt, _ = e.text()
            if txt == b"HELLO DISK\r":
                break
            time.sleep(0.2)
        check("NOTE loaded back", e.text()[0] == b"HELLO DISK\r", e.text()[0])

        # CLEAR ALL starts a new, unnamed document: CTRL-S must ask for a
        # name (not save over NOTE)
        e.keys([(KEY["HOME"], LS)])
        e.keys([(KEY["Y"], 0)])
        e.type_text("other")
        e.keys([(KEY["S"], CTRL)])
        check("after CLEAR ALL, CTRL-S asks for a name", "SAVE:" in box() and "note" not in box(), box())
        e.keys([(KEY["STOP"], 0)])

        # The character set is saved with the document: switch to upper
        # case/graphics (C= + SHIFT), save as OTHER, clear, switch back,
        # load OTHER: it comes back in upper case/graphics
        e.poke(e.lab["modified"], [0])
        e.keys([(0xff, CBM | LS)])
        check("C= + SHIFT: upper case/graphics", e.peek(0xd018)[0] & 2 == 0)
        check("switching the set counts as a change", e.peek(e.lab["modified"])[0] == 1)
        e.keys([(KEY["S"], CTRL)])
        e.type_text("other")
        e.keys([(KEY["RETURN"], 0)], settle=1.0)
        for _ in range(100):
            if e.peek(e.lab["modified"])[0] == 0:
                break
            time.sleep(0.2)
        check("saved as OTHER", e.peek(e.lab["modified"])[0] == 0)
        e.keys([(KEY["HOME"], LS), (KEY["Y"], 0)])      # CLEAR ALL
        e.keys([(0xff, CBM | LS)])                      # back to upper/lower
        check("switched back to upper/lower", e.peek(0xd018)[0] & 2 == 2)
        e.keys([(KEY["F1"], 0), (KEY["A"], 0), (KEY["A"], 0)])   # Load menu: Load
        if "LOAD WITHOUT SAVING" in box().upper():
            e.keys([(KEY["Y"], 0)])
        e.type_text("other")
        e.keys([(KEY["RETURN"], 0)], settle=1.0)
        for _ in range(100):
            if e.text()[0] == b"OTHER":
                break
            time.sleep(0.2)
        check("OTHER loaded back (the case code is not text)", e.text()[0] == b"OTHER", e.text()[0])
        check("... in upper case/graphics", e.peek(0xd018)[0] & 2 == 0)
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

if not readonly:
    c1541 = r"C:/bin/GTK3VICE-3.9-win64/GTK3VICE-3.9-win64/bin/c1541.exe"
    out = "note_saved.seq"
    if os.path.exists(os.path.join(S, out)):
        os.remove(os.path.join(S, out))
    subprocess.run([c1541, "-attach", "p4b.d64", "-read", "note,p", out], capture_output=True, cwd=S)
    saved = open(os.path.join(S, out), "rb").read() if os.path.exists(os.path.join(S, out)) else b""
    if saved[2:6] == b"\x00MTW":                # (a new document saves in
        saved = saved[22:]                      # the magic format, a PRG:
                                                # after its load address and
                                                # header, as PETSCII)
    check("NOTE on disk = $0e (upper/lower) + 'HELLO DISK' + RETURN", saved == b"\x0eHELLO DISK\r", saved)
    out = "other_saved.seq"
    if os.path.exists(os.path.join(S, out)):
        os.remove(os.path.join(S, out))
    subprocess.run([c1541, "-attach", "p4b.d64", "-read", "other,p", out], capture_output=True, cwd=S)
    saved = open(os.path.join(S, out), "rb").read() if os.path.exists(os.path.join(S, out)) else b""
    if saved[2:6] == b"\x00MTW":
        saved = saved[22:]
    check("OTHER on disk = $8e (upper case/graphics) + 'OTHER'", saved == b"\x8eOTHER", saved)
print("ALL PASS" if ok else "SOME FAILED")
