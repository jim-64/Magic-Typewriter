"""Make the manual on the disk: docs/manual.txt -> test/manual.prg, a Magic
Typewriter document (magic format, a PRG file). The build puts it on the
.d64 as MANUAL. Run from the project folder after changing the text:
    python tools/make_manual.py

The source is plain text, one line per paragraph (word wrap does the rest
on the screen), with tags for the codes:
    {white} {red} {cyan} {purple} {green} {blue} {yellow} {orange} {brown}
    {lred} {dgrey} {grey} {lgreen} {lblue} {lgrey} {black}   colors
    {rvs} {off}                    reverse on / off (a line end ends it too)
    {left} {up} {pound}            the arrow and pound characters
    @banner <color> <text>         three reversed lines in columns 1-38, the
                                   text centered
Letters are typed as in the upper/lower case set: capitals stay capitals."""
import os, sys

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(PROJ, "docs", "manual.txt")
OUT = os.path.join(PROJ, "test", "manual.prg")

CODES = {"white": 0x05, "red": 0x1c, "green": 0x1e, "blue": 0x1f, "orange": 0x81,
         "black": 0x90, "brown": 0x95, "lred": 0x96, "dgrey": 0x97, "grey": 0x98,
         "lgreen": 0x99, "lblue": 0x9a, "lgrey": 0x9b, "purple": 0x9c, "yellow": 0x9e,
         "cyan": 0x9f, "rvs": 0x12, "off": 0x92, "left": 0x5f, "up": 0x5e, "pound": 0x5c}
BANNER_WIDTH = 38                       # (a row of 40 would wrap its line end)

# The magic header (see defaults_make in src/fileio.asm): $00 "MTW1", $40 +
# the number of settings, then each setting as $40 + its value, in the order
# of defaults_vars, then a RETURN. These are the built-in defaults; a
# document brings back background, text color, wordwrap, the formats and
# the file type.
SETTINGS = [0,      # background: black
            15,     # text color: light grey
            1,      # character set: upper/lower case
            1,      # wordwrap: on
            0,      # mode: insert
            1,      # mark key: C=
            0, 8,   # Load format magic (v0.2), device 8
            0, 0, 8,  # Save format magic, File type SEQ, device 8
            0, 4]   # Print: no ASCII, device 4
HEADER = bytes([0x00, 0x4d, 0x54, 0x57, 0x31, 0x40 + len(SETTINGS)]) + \
         bytes(0x40 + v for v in SETTINGS) + b"\r"


def pet(text, where):
    """plain text -> PETSCII for the upper/lower case set, with the tags"""
    out = bytearray()
    i = 0
    while i < len(text):
        ch = text[i]
        if ch == "{":
            j = text.index("}", i)
            tag = text[i + 1:j]
            if tag not in CODES:
                sys.exit("%s: unknown tag {%s}" % (where, tag))
            out.append(CODES[tag])
            i = j + 1
            continue
        c = ord(ch)
        if "A" <= ch <= "Z":
            out.append(c | 0x80)         # capitals: $c1-$da
        elif "a" <= ch <= "z":
            out.append(c & 0xdf)         # small letters: $41-$5a
        elif 0x20 <= c <= 0x5d and ch not in "\\":
            out.append(c)                # space, digits, punctuation, @ [ ]
        else:
            sys.exit("%s: no PETSCII for %r" % (where, ch))
        i += 1
    return bytes(out)


text = bytearray()
for n, line in enumerate(open(SRC, encoding="utf-8").read().split("\n"), 1):
    where = "manual.txt line %d" % n
    line = line.rstrip()
    if line.startswith("@banner "):
        _, color, title = line.split(" ", 2)
        for row in ("", title, ""):
            text += pet(" {%s}{rvs}" % color, where) + pet(row.center(BANNER_WIDTH), where) + b"\r"
        continue
    text += pet(line, where) + b"\r"
while text.endswith(b"\r\r"):                       # (no empty lines at the end)
    text = text[:-1]

doc = bytes([0x00, 0x40]) + HEADER + b"\x0e" + bytes(text)   # load address $4000,
open(OUT, "wb").write(doc)                                   # header, case code
print("%s: %d bytes of text, %d bytes in all" % (os.path.relpath(OUT, PROJ), len(text), len(doc)))
