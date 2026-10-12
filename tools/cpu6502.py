"""A small 6502 for the tests that run assembled code without VICE
(test_mouse_delta.py, test_scan_race.py): the documented instructions, no
decimal mode, no interrupts. It counts cycles (without the extra cycle for
crossing a page). Memory is any object with [] for single bytes, so a test
can put fake I/O chips in it (see test_scan_race.py)."""

# (mnemonic, addressing mode, cycles) for each opcode
_MODES = {
    "imp": 0, "acc": 0, "imm": 1, "zp": 1, "zpx": 1, "zpy": 1, "izx": 1, "izy": 1,
    "abs": 2, "abx": 2, "aby": 2, "ind": 2, "rel": 1,
}
_TABLE = {}
def _op(code, name, mode, cyc):
    _TABLE[code] = (name, mode, cyc)
for c, m, cy in [(0x69, "imm", 2), (0x65, "zp", 3), (0x75, "zpx", 4), (0x6d, "abs", 4),
                 (0x7d, "abx", 4), (0x79, "aby", 4), (0x61, "izx", 6), (0x71, "izy", 5)]:
    _op(c, "ADC", m, cy)
for name, base in [("ORA", 0x00), ("AND", 0x20), ("EOR", 0x40), ("STA", 0x80),
                   ("LDA", 0xa0), ("CMP", 0xc0), ("SBC", 0xe0)]:
    for off, m, cy in [(0x09, "imm", 2), (0x05, "zp", 3), (0x15, "zpx", 4), (0x0d, "abs", 4),
                       (0x1d, "abx", 4), (0x19, "aby", 4), (0x01, "izx", 6), (0x11, "izy", 5)]:
        if name == "STA" and m == "imm":
            continue
        _op(base + off, name, m, cy + (1 if name == "STA" and m in ("abx", "aby", "izy") else 0))
for name, base in [("ASL", 0x00), ("ROL", 0x20), ("LSR", 0x40), ("ROR", 0x60)]:
    _op(base + 0x0a, name, "acc", 2)
    _op(base + 0x06, name, "zp", 5)
    _op(base + 0x16, name, "zpx", 6)
    _op(base + 0x0e, name, "abs", 6)
    _op(base + 0x1e, name, "abx", 7)
for code, name, m, cy in [
        (0xa2, "LDX", "imm", 2), (0xa6, "LDX", "zp", 3), (0xb6, "LDX", "zpy", 4),
        (0xae, "LDX", "abs", 4), (0xbe, "LDX", "aby", 4),
        (0xa0, "LDY", "imm", 2), (0xa4, "LDY", "zp", 3), (0xb4, "LDY", "zpx", 4),
        (0xac, "LDY", "abs", 4), (0xbc, "LDY", "abx", 4),
        (0x86, "STX", "zp", 3), (0x96, "STX", "zpy", 4), (0x8e, "STX", "abs", 4),
        (0x84, "STY", "zp", 3), (0x94, "STY", "zpx", 4), (0x8c, "STY", "abs", 4),
        (0xe0, "CPX", "imm", 2), (0xe4, "CPX", "zp", 3), (0xec, "CPX", "abs", 4),
        (0xc0, "CPY", "imm", 2), (0xc4, "CPY", "zp", 3), (0xcc, "CPY", "abs", 4),
        (0xe6, "INC", "zp", 5), (0xf6, "INC", "zpx", 6), (0xee, "INC", "abs", 6),
        (0xfe, "INC", "abx", 7),
        (0xc6, "DEC", "zp", 5), (0xd6, "DEC", "zpx", 6), (0xce, "DEC", "abs", 6),
        (0xde, "DEC", "abx", 7),
        (0x24, "BIT", "zp", 3), (0x2c, "BIT", "abs", 4),
        (0x4c, "JMP", "abs", 3), (0x6c, "JMP", "ind", 5), (0x20, "JSR", "abs", 6),
        (0x60, "RTS", "imp", 6),
        (0x10, "BPL", "rel", 2), (0x30, "BMI", "rel", 2), (0x50, "BVC", "rel", 2),
        (0x70, "BVS", "rel", 2), (0x90, "BCC", "rel", 2), (0xb0, "BCS", "rel", 2),
        (0xd0, "BNE", "rel", 2), (0xf0, "BEQ", "rel", 2),
        (0xaa, "TAX", "imp", 2), (0x8a, "TXA", "imp", 2), (0xa8, "TAY", "imp", 2),
        (0x98, "TYA", "imp", 2), (0xba, "TSX", "imp", 2), (0x9a, "TXS", "imp", 2),
        (0xe8, "INX", "imp", 2), (0xca, "DEX", "imp", 2), (0xc8, "INY", "imp", 2),
        (0x88, "DEY", "imp", 2),
        (0x48, "PHA", "imp", 3), (0x68, "PLA", "imp", 4), (0x08, "PHP", "imp", 3),
        (0x28, "PLP", "imp", 4),
        (0x18, "CLC", "imp", 2), (0x38, "SEC", "imp", 2), (0x58, "CLI", "imp", 2),
        (0x78, "SEI", "imp", 2), (0xb8, "CLV", "imp", 2), (0xd8, "CLD", "imp", 2),
        (0xf8, "SED", "imp", 2), (0xea, "NOP", "imp", 2)]:
    _op(code, name, m, cy)


class CPU:
    """run(pc) runs a subroutine until its RTS; a.x.y and the flags are
    attributes. cyc counts the cycles of the last run; step_hook, if set,
    is called before every instruction (for fake I/O that changes with
    time)."""
    def __init__(self, mem):
        self.m = mem
        self.step_hook = None

    def nz(self, v):
        self.n = v >> 7
        self.z = int(v == 0)
        return v

    def adc(self, v):
        r = self.a + v + self.c
        self.v = int((~(self.a ^ v) & (self.a ^ r) & 0x80) != 0)
        self.c = int(r > 0xff)
        self.a = self.nz(r & 0xff)

    def cmp(self, reg, v):
        self.c = int(reg >= v)
        self.nz((reg - v) & 0xff)

    def flags(self):
        return (self.n << 7 | self.v << 6 | 0x30 | self.d << 3 | self.i << 2
                | self.z << 1 | self.c)

    def run(self, pc, a=0, x=0, y=0, limit=100000):
        self.a, self.x, self.y = a, x, y
        self.c = self.n = self.z = self.v = self.d = self.i = 0
        self.sp = 0xfd
        self.cyc = 0
        m = self.m
        depth = 0
        for _ in range(limit):
            if self.step_hook:
                self.step_hook(self)
            op = m[pc]
            if op not in _TABLE:
                raise RuntimeError("opcode $%02x at $%04x not in the emulator" % (op, pc))
            name, mode, cyc = _TABLE[op]
            self.cyc += cyc
            b1 = m[(pc + 1) & 0xffff]
            ab = b1 | m[(pc + 2) & 0xffff] << 8
            size = 1 + _MODES[mode]
            # the operand's address
            if mode == "zp":
                ea = b1
            elif mode == "zpx":
                ea = (b1 + self.x) & 0xff
            elif mode == "zpy":
                ea = (b1 + self.y) & 0xff
            elif mode == "abs":
                ea = ab
            elif mode == "abx":
                ea = (ab + self.x) & 0xffff
            elif mode == "aby":
                ea = (ab + self.y) & 0xffff
            elif mode == "izx":
                p = (b1 + self.x) & 0xff
                ea = m[p] | m[(p + 1) & 0xff] << 8
            elif mode == "izy":
                ea = ((m[b1] | m[(b1 + 1) & 0xff] << 8) + self.y) & 0xffff
            elif mode == "ind":
                ea = m[ab] | m[(ab & 0xff00) | ((ab + 1) & 0xff)] << 8
            else:
                ea = None
            val = (lambda: b1) if mode == "imm" else (lambda: m[ea])
            nxt = (pc + size) & 0xffff

            if name == "LDA": self.a = self.nz(val())
            elif name == "LDX": self.x = self.nz(val())
            elif name == "LDY": self.y = self.nz(val())
            elif name == "STA": m[ea] = self.a
            elif name == "STX": m[ea] = self.x
            elif name == "STY": m[ea] = self.y
            elif name == "ORA": self.a = self.nz(self.a | val())
            elif name == "AND": self.a = self.nz(self.a & val())
            elif name == "EOR": self.a = self.nz(self.a ^ val())
            elif name == "ADC": self.adc(val())
            elif name == "SBC": self.adc(val() ^ 0xff)
            elif name == "CMP": self.cmp(self.a, val())
            elif name == "CPX": self.cmp(self.x, val())
            elif name == "CPY": self.cmp(self.y, val())
            elif name == "BIT":
                v = val()
                self.n, self.v, self.z = v >> 7, (v >> 6) & 1, int(self.a & v == 0)
            elif name in ("ASL", "ROL", "LSR", "ROR"):
                v = self.a if mode == "acc" else m[ea]
                if name == "ASL": c, v = v >> 7, (v << 1) & 0xff
                elif name == "ROL": c, v = v >> 7, ((v << 1) & 0xff) | self.c
                elif name == "LSR": c, v = v & 1, v >> 1
                else: c, v = v & 1, (v >> 1) | (self.c << 7)
                self.c = c
                if mode == "acc": self.a = self.nz(v)
                else: m[ea] = self.nz(v)
            elif name == "INC": m[ea] = self.nz((m[ea] + 1) & 0xff)
            elif name == "DEC": m[ea] = self.nz((m[ea] - 1) & 0xff)
            elif name == "INX": self.x = self.nz((self.x + 1) & 0xff)
            elif name == "DEX": self.x = self.nz((self.x - 1) & 0xff)
            elif name == "INY": self.y = self.nz((self.y + 1) & 0xff)
            elif name == "DEY": self.y = self.nz((self.y - 1) & 0xff)
            elif name == "TAX": self.x = self.nz(self.a)
            elif name == "TXA": self.a = self.nz(self.x)
            elif name == "TAY": self.y = self.nz(self.a)
            elif name == "TYA": self.a = self.nz(self.y)
            elif name == "TSX": self.x = self.nz(self.sp)
            elif name == "TXS": self.sp = self.x
            elif name == "PHA": self.push(self.a)
            elif name == "PLA": self.a = self.nz(self.pull())
            elif name == "PHP": self.push(self.flags())
            elif name == "PLP":
                f = self.pull()
                self.n, self.v, self.d = f >> 7, (f >> 6) & 1, (f >> 3) & 1
                self.i, self.z, self.c = (f >> 2) & 1, (f >> 1) & 1, f & 1
            elif name == "CLC": self.c = 0
            elif name == "SEC": self.c = 1
            elif name == "CLV": self.v = 0
            elif name in ("CLI", "SEI", "CLD", "SED", "NOP"):
                pass                                    # (no interrupts, no decimal)
            elif name == "JMP": nxt = ea
            elif name == "JSR":
                ret = (pc + 2) & 0xffff
                self.push(ret >> 8)
                self.push(ret & 0xff)
                depth += 1
                nxt = ea
            elif name == "RTS":
                if depth == 0:
                    return self.a, self.x, self.y
                depth -= 1
                lo = self.pull()
                nxt = ((self.pull() << 8 | lo) + 1) & 0xffff
            else:                                       # branches
                take = {"BPL": not self.n, "BMI": self.n, "BVC": not self.v,
                        "BVS": self.v, "BCC": not self.c, "BCS": self.c,
                        "BNE": not self.z, "BEQ": self.z}[name]
                if take:
                    self.cyc += 1
                    nxt = (nxt + (b1 - 256 if b1 > 127 else b1)) & 0xffff
            pc = nxt
        raise RuntimeError("no RTS")

    def push(self, v):
        self.m[0x100 + self.sp] = v
        self.sp = (self.sp - 1) & 0xff

    def pull(self):
        self.sp = (self.sp + 1) & 0xff
        return self.m[0x100 + self.sp]
