#!/bin/sh
# ======================================================================
# Magic Typewriter build (Linux)
#
#   ./build.sh            debug build (includes the test mailbox)
#   ./build.sh release    release build (no test mailbox)
#
# Needs acme and c1541 on the PATH (Ubuntu: sudo apt install acme vice),
# and exomizer for the release disk's packed program (without it the
# release disk gets the program as it is).
# Output in the build folder, same as build.bat:
#   magictypewriter.prg, magictypewriter.d64, main.vs, main.lbl, main.lst
#   (release: magictypewriter-packed.prg; the disk has the packed program
#   and the manual; the debug disk has the program and all the test files)
#
# build.bat does the same steps on Windows. Keep the two in step.
# ======================================================================
set -e
cd "$(dirname "$0")"

DEBUG=1
if [ "$1" = "release" ]; then DEBUG=0; fi

mkdir -p build

echo "Assembling (DEBUG=$DEBUG)..."
acme -f cbm -DDEBUG=$DEBUG -o build/magictypewriter.prg -l build/main.lbl \
     --vicelabels build/main.vs -r build/main.lst src/main.asm

if [ "$DEBUG" = "0" ]; then
    # The release disk: the program packed by Exomizer into a program that
    # unpacks itself (a BASIC SYS line, so LOAD and RUN as usual, from disk
    # or tape; -x1: the border flashes while it unpacks), and the manual.
    PROGRAM=build/magictypewriter.prg
    if command -v exomizer >/dev/null 2>&1; then
        echo "Packing with Exomizer..."
        exomizer sfx sys -x1 -q -o build/magictypewriter-packed.prg \
                 build/magictypewriter.prg
        PROGRAM=build/magictypewriter-packed.prg
    else
        echo "Exomizer is not on the PATH: the disk gets the program unpacked."
    fi
    echo "Making disk image (the program and the manual)..."
    c1541 -format "magic typewriter,mt" d64 build/magictypewriter.d64 \
          -write "$PROGRAM" "magic typewriter" >/dev/null
    c1541 -attach build/magictypewriter.d64 -write test/manual.prg "manual,p" >/dev/null
    echo "Done: build/magictypewriter.prg and build/magictypewriter.d64 (release)"
    exit 0
fi

echo "Making disk image..."
c1541 -format "magic typewriter,mt" d64 build/magictypewriter.d64 \
      -write build/magictypewriter.prg "magic typewriter" >/dev/null

# Add the files in test/ (name without extension): first the .prg files as
# PRG files (the manual, a Magic Typewriter document: made from
# docs/manual.txt by tools/make_manual.py), then the .seq files as SEQ.
for f in test/*.prg; do
    [ -f "$f" ] || continue
    name=$(basename "$f" .prg)
    c1541 -attach build/magictypewriter.d64 -write "$f" "$name,p" >/dev/null
done
for f in test/*.seq; do
    [ -f "$f" ] || continue
    name=$(basename "$f" .seq)
    c1541 -attach build/magictypewriter.d64 -write "$f" "$name,s" >/dev/null
done

echo "Done: build/magictypewriter.prg and build/magictypewriter.d64"
