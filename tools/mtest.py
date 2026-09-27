"""Helpers to drive Magic Typewriter (debug build) through the test mailbox."""
import time, re, os
from vicemon import Mon, start_vice, PROJ, WORK
MB = 0x02c0
HEAD, TAIL, QUEUE, COUNT = MB + 16, MB + 17, MB + 18, MB + 52

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
                raise TimeoutError("keys not handled")
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
        before = self.peek(0x4000, gs - 0x4000) if gs > 0x4000 else b""
        after = self.peek(ge, 0xd000 - ge) if ge < 0xd000 else b""
        return before + after, gs - 0x4000
