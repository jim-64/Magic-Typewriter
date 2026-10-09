# Magic Typewriter

A small, modern-feeling text editor for the Commodore 64, written in 6502 assembly.

Magic Typewriter edits **PETSCII text files** — the kind BBSes, disk magazines and `PRINT#` produce
— with their colors and reverse text shown as they look, not as control symbols. It adds what a
modern editor has: marking text, cut/copy/paste, word wrap, a menu, find, and a 1351 mouse. With a
large REU it edits documents far bigger than the C64's memory.

It runs on PAL, NTSC, old NTSC and Drean (PAL-N) machines, works with any drive that the KERNAL
can talk to (1541, 1571, 1581, SD2IEC, Pi1541, Ultimate…), and also with tape and printers.

## Getting started

Download **`magictypewriter.d64`** from the [Releases](../../releases) page — no need to build
anything. Put it on whatever your C64 loads from (an SD2IEC card, a Pi1541, an Ultimate's USB
stick, a real floppy written with a transfer cable, or just attach it in VICE), then:

```
LOAD"MAGIC TYPEWRITER",8
RUN
```

The program is packed to load faster: after `RUN` it unpacks itself for a moment (the border
flashes). It loads from tape the same way. You get an empty page. Just type. Press **F1** (or
RUN/STOP) for the menu.

The disk also holds `MANUAL`: this manual as a Magic Typewriter document, in color. To read it:
F1, A, A, type `manual`, RETURN.

What you see:

- The text area is the full 40 × 25 screen.
- Blue strips at the top and bottom hold the **F3** (page up) and **F5** (page down) badges and the
  **≡F1** menu icon.
- The grey band in the side borders is the **page marker**: it shows which part of the document
  is on the screen, like a scroll bar. It fills the whole side when all of the document fits.
- The cursor shows the typing mode: a thick underline in **insert** mode, a flashing block in
  **overwrite** mode (F7 switches). It takes the color of the text it is in.

## Keys

| Key | What it does |
|---|---|
| F1, RUN/STOP | The menu |
| SHIFT + F1 | The next color for what you type next, like pressing that color's key (again: the one after) |
| F3 / F5 | Page up / page down |
| SHIFT + F3 / SHIFT + F5 | Top / end of the document |
| F7 | Insert / overwrite |
| SHIFT + F7 | Word wrap on / off |
| C= + SHIFT | Upper case/graphics ↔ upper/lower case, as in BASIC |
| Cursor keys | Move (SHIFT reverses the direction, as usual) |
| HOME | Start of the line; again: top of the document |
| SHIFT + CLR/HOME | "CLEAR ALL Y/N": a new, empty document |
| INST/DEL | Delete the character left of the cursor |
| SHIFT + INST/DEL | Insert a space |
| RETURN | New line |
| CTRL-1 … CTRL-8, C= 1 … C= 8 | Text colors, as in BASIC |
| CTRL-9 / CTRL-0 | Reverse on / off |
| CTRL-A | Mark everything |
| CTRL-X / CTRL-C / CTRL-V | Cut / copy / paste |
| CTRL-Z | Undo the last change |
| CTRL-F | Find |
| CTRL-S | Save (asks for a name the first time) |

RESTORE does no harm: it opens the menu like RUN/STOP, so RUN/STOP + RESTORE can't lose your work.

### Colors and reverse

Colors work as in BASIC: press CTRL-3 and what you type next is red. The color codes are stored
in the text and saved with it, but take no room on the screen. Text after the cursor keeps its
look — pressing a color key in the middle of a line only colors what you type there. Codes that
no longer do anything are tidied away by themselves.

CTRL-9 and CTRL-0 switch reverse on and off. A line end switches it off too, as in BASIC, but
RETURN in the middle of reversed text keeps the rest of the line reversed.

### Marking text

Hold the **mark key** while moving the cursor: the text you pass over is marked (shown reversed).
The mark key is **C=** (the default) or **left SHIFT** (main menu, F).

- C= + cursor keys mark; C= + SHIFT + cursor marks up or left.
- Mark key + F3/F5 marks a page at a time; with SHIFT too, all the way to the top or the end.
- With text marked: typing replaces it, INST/DEL deletes it, CTRL-X/C cut or copy it, and **a
  color or reverse key recolors all of it**.
- Any cursor move without the mark key unmarks.

### Undo

**CTRL-Z** undoes the last change: a cut, typing over or deleting marked text, a recolor, a paste,
or the last run of typing or deleting. It undoes one change (pressing it again says "NOTHING TO
UNDO"). A change that removed more than about 1,000 characters can't be undone ("TOO BIG TO
UNDO"), and neither can CLEAR ALL. Undo keeps its notes in 1 KB at the top of the text buffer.

### Find

CTRL-F asks for a word (up to 26 characters) and finds it from the cursor on, round to the top
once. Capitals and small letters count as the same, and color changes inside a word don't get in
the way. The match is marked; **CTRL-F, RETURN** finds the next one.

## The mouse

A **1351 mouse in port 1** is found by itself the first time you move it; a joystick is ignored.

- Click to put the cursor there; drag to mark (hold the mark key to extend marked text).
- Move past the text onto a badge (it lights up in the pointer's color) and click: F3/F5 page, ≡F1 opens the menu.
- The right button opens the menu.
- The pointer hides after 10 seconds of rest; moving the mouse brings it back.

## The menu

Letters choose; **X** goes back one level; RUN/STOP or ← closes the menu. You can also click a
line. Settings show their value and step to the next each time you choose them. The main menu
also lists the CTRL keys at its foot.

| Main menu | |
|---|---|
| A Load, B Save, C Print | Their own menus (below) |
| D Wordwrap | On (default) or off. Off cuts rows at 40 characters, like the BASIC screen (also SHIFT + F7) |
| E Mode | Insert or overwrite (same as F7) |
| F Mark key | Commodore or left SHIFT |
| G Background, H Text color | Any of the 16 colors (the text color is for text without color codes) |
| I Stats | Characters, words, sentences, room left (and the REU's size) |
| J Save defaults | Keeps all settings in `MAGIC T DEFAULTS` on the disk the program came from; read at every start |
| Q Quit Magic Typewriter | Back to BASIC (asks first if there are unsaved changes) |

**Load:** A Load, B Format, C Device (8–14 or TAPE), D Disk directory, E Disk command.
**Save:** A Save (asks for the name), B Format, C File type, D Device, E Disk directory, F Disk command.
**Print:** A Print, B Convert to ASCII, C Device (4–7).

A setting that other settings decide for you is shown in [brackets] — e.g. the File type of a
magic document, which is always PRG.

## Files

**Formats** (Load and Save menus):

- **Magic** — the *project* format: the PETSCII text plus a short header with the document's
  settings (word wrap, background, text color, formats, file type), so it comes back just as you
  left it. A new document saves as magic. Magic files are always **PRG** files: cartridge fast
  loaders such as Epyx FastLoad only speed up LOAD, and there a magic document loads much faster
  than the same text as a SEQ file (18 s against 8 s in VICE). JiffyDOS speeds up every transfer,
  SEQ files included, so with JiffyDOS the difference is smaller.
- **PETSCII** — the *finished* text, for BBSes, other programs and `PRINT#`: exactly as on the
  C64, colors and reverse included. The first byte says which character set the text uses ($0E
  upper/lower, $8E upper case/graphics), as BBS files do.
- **ASCII** — for files from or for a PC: capitals and small letters swapped, line ends written as
  CR+LF (CR, LF or CR+LF are all read). Colors and reverse can't be kept; it warns you first.

A good habit: work in magic, and save a PETSCII copy when the text is done.

Loading recognises a magic file whatever the Format setting says, and afterwards saves the
document back in the format it came in.

**Saving over a file** scratches the old one first (never the risky `@0:`). Drive errors show as
the drive reports them, e.g. `62, FILE NOT FOUND,00,00`. A spinner turns while the drive works.

**Tape:** choose TAPE as the device. Magic documents are program files; PETSCII and ASCII are data
files. Our own box asks you to press PLAY (or RECORD & PLAY); RUN/STOP gives up. A blank name
loads the next file of the right kind.

**Printing** sends the whole document. For a Commodore printer (Convert to ASCII: no) colors are
left out and reverse is kept; with ASCII on, it goes as ASCII with CR+LF.

## REU

With an REU (1700/1764/1750, or the Ultimate's, VICE's, the MEGA65's) Magic Typewriter uses it by
itself:

- **Any size:** faster big moves, and the clipboard lives in the REU.
- **192 KB or more: long documents.** Only a 31 KB stretch around the cursor is in the C64's
  memory; the rest stays in the REU, so a document can be as long as the REU allows. Loading,
  saving, printing, Find, Stats and the page marker all work on the whole document. When the
  cursor gets near the end of that stretch the next part comes in — a short pause (about
  1½ seconds) now and then while you page through.
  - Marked text can be up to about 20 KB.
  - CTRL-A (mark everything) and saving a magic document **to tape** need the whole document in
    memory (up to 31 KB); longer ones get a message (save to tape as PETSCII instead).
  - A document bigger than the REU can hold loads as far as it fits: "TOO LONG: ONLY PART
    LOADED".

Without an REU, 35 KB of the C64's memory holds the text (1 KB is kept for undo).

## Emulators

**VICE:** turn on Control port 1 → *Mouse (1351)* and grab the PC mouse (Alt+Q or Ctrl+M,
depending on the version). The REU is under Cartridge/IO settings.

- **Tab is the C= key.** Tab + an arrow key marks in every direction.
- With **left SHIFT as the mark key, marking up or left doesn't work in VICE**: VICE sends PC
  Shift + Up as SHIFT + CRSR DOWN, so it marks downward. Use C= (Tab) in VICE.

**SHIFT LOCK** holds left SHIFT down: with left SHIFT as the mark key, every cursor move then marks.

## Building from source

Only needed if you want to change the program. You need
[ACME](https://sourceforge.net/projects/acme-crossass/) 0.97 and `c1541` (part of VICE).

- **Windows:** `build.bat` (debug build) or `build.bat release`. The tool paths are set at the top.
- **Linux:** `./build.sh` or `./build.sh release`, with `acme` and `c1541` on the PATH.

Both write `build/magictypewriter.prg` and a `build/magictypewriter.d64`. The release disk has the
program packed with [Exomizer](https://bitbucket.org/magli143/exomizer/wiki/Home) (3.1; it must be
on the PATH, otherwise the program goes on the disk unpacked) and the manual. The debug build's
disk has the program and all the sample files from `test/` (`sample`, `upper`, `long`, and
`longdoc`, 60 KB, for long documents with an REU). The manual's text is `docs/manual.txt`;
`python tools/make_manual.py` turns it into `test/manual.prg` (a Magic Typewriter document). The debug build includes a small test mailbox that the automated tests
in `tools/` use (Python 3 and VICE 3.9).

The source is in `src/`, one master file (`main.asm`) and one file per part; `CLAUDE.md` describes
the design and memory layout in detail.
