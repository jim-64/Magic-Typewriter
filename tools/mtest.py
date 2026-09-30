"""Helpers to drive Magic Typewriter (debug build) through the test mailbox."""
import time, re, os
from vicemon import Mon, start_vice, PROJ, WORK
MB = 0x02c0
HEAD, TAIL, QUEUE, COUNT = MB + 16, MB + 17, MB + 18, MB + 52
MHEAD, MTAIL, MQUEUE = MB + 34, MB + 35, MB + 36

KEY = {c: n for n, c in enumerate(
    ["DEL", "RETURN", "RIGHT", "F7", "F1", "F3", "F5", "DOWN",
     "3", "W", "A", "4", "Z", "S", "E", "LSHIFT",
     "5", "R", "D", "6", "C", "F", "T", "X",
     "7", "Y", "G", "8", "B", "H", "U", "V",
     "9", "I", "J", "0", "M", "K", "O", "N",
     "+", "P", "L", "-", ".", ":", "@", ",",
     "POUND", "*", ";", "HOME", "RSHIFT", "=", "UP", "/",
     "1", "LEFTARROW", "CTRL", "2", "SPACE", "CBM", "Q", "STOP"])}
LS, RS, CTRL, CBM = 1, 2, 4, 8


def labels():
    out = {}
    for line in open(os.path.join(PROJ, "build/main.lbl")):
        m = re.match(r"\s*(\S+)\s*=\s*\$([0-9a-fA-F]+)", line)
        if m:
            out[m.group(1)] = int(m.group(2), 16)
    return out


class Editor:
    def __init__(self, mon):
        self.m = mon
        self.lab = labels()

    def peek(self, addr, n=1):
        d = self.m.read(addr, n)
        self.m.resume()
        return d

    def poke(self, addr, data):
        self.m.write(addr, data)
        self.m.resume()

    def wait_ready(self, timeout=30):
        t0 = time.time()
        while time.time() - t0 < timeout:
            if self.peek(MB, 4) == b"MTDB":
                return
            time.sleep(0.3)
        raise TimeoutError("editor did not start")

    def count(self):
        return self.peek(COUNT)[0]

    def keys(self, events, settle=0.3, timeout=60):
        """events: list of (code, mods) - queue them, wait until all taken"""
        start = self.count()
        pending = list(events)
        t0 = time.time()
        while pending:
            head, tail = self.peek(HEAD, 2)
            free = (tail - head - 1) % 8
            batch = pending[:free]
            if batch:
                for ev in batch:
                    code, mods = ev
                    self.m.write(QUEUE + 2 * head, bytes([code, mods]))
                    head = (head + 1) % 8
                self.m.write(HEAD, bytes([head]))
                self.m.resume()
                pending = pending[len(batch):]
            time.sleep(0.1)
            if time.time() - t0 > timeout:
                raise TimeoutError("keys not taken")
        want = (start + len(events)) % 256
        while self.count() != want:
            time.sleep(0.1)
            if time.time() - t0 > timeout:
                raise TimeoutError("keys not handled: count %d, wanted %d (started at %d); "
                                   "last keys handled (code, mods): %s"
                                   % (self.count(), want, start, self.peek(MB + 53, 8).hex(" ")))
        time.sleep(settle)

    def mouse(self, events, settle=0.3, timeout=30):
        """events: list of (dx, dy, buttons) - dx/dy in pixels (+ = right,
        down), buttons bit 0 left, bit 1 right. One is taken per frame; the
        buttons then stay as the last event said."""
        pending = list(events)
        t0 = time.time()
        while pending:
            head, tail = self.peek(MHEAD, 2)
            free = (tail - head - 1) % 4
            batch = pending[:free]
            if batch:
                for dx, dy, b in batch:
                    self.m.write(MQUEUE + 3 * head, bytes([dx & 255, dy & 255, b]))
                    head = (head + 1) % 4
                self.m.write(MHEAD, bytes([head]))
                self.m.resume()
                pending = pending[len(batch):]
            time.sleep(0.05)
            if time.time() - t0 > timeout:
                raise TimeoutError("mouse events not taken")
        while True:
            head, tail = self.peek(MHEAD, 2)
            if head == tail:
                break
            time.sleep(0.05)
            if time.time() - t0 > timeout:
                raise TimeoutError("mouse events not taken")
        time.sleep(settle)

    def mouse_pos(self):
        x = int.from_bytes(self.peek(self.lab["mouse_x"], 2), "little")
        return x, self.peek(self.lab["mouse_y"])[0]

    def move_to(self, x, y, buttons=0, settle=0.3):
        """move the pointer's box to (x, y), in steps of at most 60 pixels"""
        for _ in range(40):
            cx, cy = self.mouse_pos()
            if (cx, cy) == (x, y):
                break
            dx = max(-60, min(60, x - cx))
            dy = max(-60, min(60, y - cy))
            self.mouse([(dx, dy, buttons)], settle=0.05)
        time.sleep(settle)

    def type_text(self, text):
        ev = []
        for ch in text:
            ev.append((KEY[ch.upper()] if ch != " " else KEY["SPACE"], 0))
        self.keys(ev)

    def screen_rows(self):
        raw = self.peek(0x0400, 1000)
        lower = self.peek(0xd018)[0] & 2
        rows = []
        for r in range(25):
            s = ""
            for c in raw[r * 40:(r + 1) * 40]:
                c &= 0x7f
                if c == 0:
                    s += "@"
                elif 1 <= c <= 26:
                    s += chr(c + 96) if lower else chr(c + 64)
                elif 27 <= c <= 31:
                    s += "[\\]^_"[c - 27]           # [ pound ] up-arrow left-arrow
                elif 32 <= c <= 63:
                    s += chr(c)
                elif 65 <= c <= 90:
                    s += chr(c) if lower else "#"
                else:
                    s += "#"
            rows.append(s.rstrip())
        return rows

    def text(self):
        gs = int.from_bytes(self.peek(0x08, 2), "little")
        ge = int.from_bytes(self.peek(0x0a, 2), "little")
        te = int.from_bytes(self.peek(0x1a, 2), "little")    # text_end
        before = self.peek(0x4000, gs - 0x4000) if gs > 0x4000 else b""
        after = self.peek(ge, te - ge) if ge < te else b""
        return before + after, gs - 0x4000

    def clipboard(self):
        if self.peek(self.lab["reu_banks"])[0]:
            return self.reu_clipboard()
        te = int.from_bytes(self.peek(0x1a, 2), "little")
        return self.peek(te, 0xd000 - te) if te < 0xd000 else b""

    def reu_clipboard(self):
        """With an REU the clipboard is in its bank 1 (reu.asm). Fetch it
        into the free space at the top of the gap by programming the REU
        through the monitor (only while the editor is idle), then read it."""
        size = int.from_bytes(self.peek(self.lab["clip_size"], 2), "little")
        if size == 0:
            return b""
        gs = int.from_bytes(self.peek(0x08, 2), "little")
        ge = int.from_bytes(self.peek(0x0a, 2), "little")
        if ge - gs < size:
            raise RuntimeError("not enough free space to read the REU clipboard")
        dst = ge - size
        regs = bytes([dst & 255, dst >> 8, 0, 0, 1, size & 255, size >> 8])
        self.m.write(0xdf0a, bytes([0]))           # both addresses count up
        self.m.write(0xdf02, regs)                 # C64 addr, REU addr, bank 1,
        self.m.write(0xdf01, bytes([0x91]))        # length; fetch, at once
        self.m.resume()                            # (VICE does the copy as
        time.sleep(0.1)                            # the emulation runs on)
        data = self.m.read(dst, size)
        self.m.resume()
        return data
