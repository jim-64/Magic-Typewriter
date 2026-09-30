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

    def key_done(self, code, mods=0, timeout=300, settle=0.3):
        """one key, then wait until the editor has finished with it (the
        main loop writes the frames it took just below the mailbox, after
        the key's work and the REU window's moves)"""
        self.poke(MB - 1, [0xff])
        self.keys([(code, mods)], settle=0)
        t0 = time.time()
        while self.peek(MB - 1)[0] == 0xff:
            time.sleep(0.2)
            if time.time() - t0 > timeout:
                raise TimeoutError("key not finished")
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

    def reu_read(self, addr, size):
        """Read size bytes of REU memory from addr (24 bits: bank * 65536 +
        address) by fetching them into the gap a piece at a time (only
        while the editor is idle)."""
        out = b""
        self.idle()
        while size > 0:
            gs = int.from_bytes(self.peek(0x08, 2), "little")
            ge = int.from_bytes(self.peek(0x0a, 2), "little")
            n = min(size, ge - gs)
            if n <= 0:
                raise RuntimeError("no gap to read the REU through")
            # the editor's main loop does the copy (MB_DMA, debug builds):
            # one big DMA straight from the monitor would stop the CPU too
            # long for the exact-timed IRQs; reu_move copies in pieces
            req = bytes([gs & 255, gs >> 8, addr & 255, (addr >> 8) & 255, addr >> 16,
                         n & 255, n >> 8, 0x91])
            self.poke(MB - 12, req)
            t0 = time.time()
            while self.peek(MB - 12 + 7)[0]:
                time.sleep(0.05)
                if time.time() - t0 > 60:
                    raise TimeoutError("REU copy not done")
            out += self.m.read(gs, n)
            self.m.resume()
            addr += n
            size -= n
        return out

    def idle(self, timeout=300):
        """wait until the main loop has finished its last key (debug builds
        set MB_BUSY, just below the key time, while they work on one): the
        harness must not program the REU while the editor uses it"""
        t0 = time.time()
        while self.peek(MB - 2)[0]:
            time.sleep(0.1)
            if time.time() - t0 > timeout:
                raise TimeoutError("editor still busy")

    def val24(self, name):
        d = self.peek(self.lab[name], 3)
        return d[0] | d[1] << 8 | d[2] << 16

    def doc(self):
        """The whole document and the cursor's offset in it: with long
        documents in an REU (reudoc.asm) the head's chunks, the text buffer
        (the window) and the tail."""
        if not self.peek(self.lab["reu_docs"])[0]:
            return self.text()
        head_top = self.val24("head_top")
        win_base = self.val24("win_base")
        tail_len = self.val24("tail_len")
        reu_top = self.val24("reu_top")
        head = b""
        at = 2 << 16                                   # DOC_BANK
        while at < head_top:
            hdr = self.reu_read(at, 6)
            n = hdr[3] | hdr[4] << 8
            head += self.reu_read(at + 6, n)
            at += 6 + n
        if len(head) != win_base:
            raise RuntimeError("head is %d bytes, win_base says %d" % (len(head), win_base))
        window, cur = self.text()
        tail = self.reu_read(reu_top - tail_len, tail_len) if tail_len else b""
        return head + window + tail, win_base + cur

    def reu_clipboard(self):
        """With an REU the clipboard is in its bank 1 (reu.asm): read it
        through the gap (reu_read)."""
        size = int.from_bytes(self.peek(self.lab["clip_size"], 2), "little")
        return self.reu_read(1 << 16, size) if size else b""
