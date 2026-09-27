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

        # Change it, then CTRL-L: asks first; N keeps the document
        e.type_text("more")
        doc_before, _ = e.text()
        e.keys([(KEY["L"], CTRL)])
        check("load with changes asks first", "LOAD WITHOUT SAVING Y/N" in box().upper(), box())
        e.keys([(KEY["N"], 0)])
        check("N keeps the document", e.text()[0] == doc_before)
        # Y goes on to the name box, with the last name filled in
        e.keys([(KEY["L"], CTRL)])
        e.keys([(KEY["Y"], 0)])
        check("name box shows the last name", "LOAD: note" in box(), box())
        e.keys([(KEY["RETURN"], 0)], settle=1.0)
        for _ in range(100):
            txt, _ = e.text()
            if txt == b"HELLO DISK\r":
                break
            time.sleep(0.2)
        check("NOTE loaded back", e.text()[0] == b"HELLO DISK\r", e.text()[0])
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
    subprocess.run([c1541, "-attach", "p4b.d64", "-read", "note,s", out], capture_output=True, cwd=S)
    saved = open(os.path.join(S, out), "rb").read() if os.path.exists(os.path.join(S, out)) else b""
    check("NOTE on disk = 'HELLO DISK' + RETURN", saved == b"HELLO DISK\r", saved)
print("ALL PASS" if ok else "SOME FAILED")
