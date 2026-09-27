#!/bin/sh
# ======================================================================
# Magic Typewriter build (Linux)
#
#   ./build.sh            debug build (includes the test mailbox)
#   ./build.sh release    release build (no test mailbox)
#
# Needs acme and c1541 on the PATH (Ubuntu: sudo apt install acme vice).
# Output in the build folder, same as build.bat:
#   magictypewriter.prg, magictypewriter.d64, main.vs, main.lbl, main.lst
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

echo "Making disk image..."
c1541 -format "magic typewriter,mt" d64 build/magictypewriter.d64 \
      -write build/magictypewriter.prg "magic typewriter" >/dev/null

# Add every file in test/ as a SEQ file (name without extension).
if [ -d test ]; then
    for f in test/*; do
        [ -f "$f" ] || continue
        name=$(basename "$f"); name=${name%.*}
        c1541 -attach build/magictypewriter.d64 -write "$f" "$name,s" >/dev/null
    done
fi

echo "Done: build/magictypewriter.prg and build/magictypewriter.d64"
