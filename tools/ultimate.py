"""Run the tests on a C64 Ultimate instead of VICE (phase 12).

Set MT_TARGET=c64u (and MT_C64U=<address>, default 192.168.1.64): mtest
then uses these in place of vicemon's start_vice and Mon. The Ultimate's
REST interface reads and writes memory while the C64 runs (by DMA), so the
test mailbox works as in VICE. Differences:
- real time: no warp, and the CPU never stops between calls;
- no disk images: start_vice refuses a disk (the disk tests check their
  files with c1541 on a local image, which the Ultimate doesn't give back);
- no VICE command line: an REU, a 1351 or another video system have to be
  set on the Ultimate itself.
So for the tests that need nothing else: test_phase3, test_phase5,
test_phase6...

**Never upload to it** (POST with a body: runners:run_prg, writemem with
data attached): firmware 1.1.0 keeps every upload as a file in its /Temp
RAM area and doesn't clear it, and once that is full every upload fails
("Cannot open file"; found in phase 12 - switching the Ultimate off and on
empties it). So writes go as hex in the request (PUT, 128 bytes at a time),
and the program is written into memory and started with RUN typed into the
keyboard buffer."""
import os, time, urllib.request

HOST = os.environ.get("MT_C64U", "192.168.1.64")


def _req(method, path):
    req = urllib.request.Request("http://%s%s" % (HOST, path), method=method)
    with urllib.request.urlopen(req, timeout=20) as r:
        return r.read()


def _read(addr, length):
    out = b""
    while length > 0:
        n = min(length, 4096)
        out += _req("GET", "/v1/machine:readmem?address=%04X&length=%d" % (addr, n))
        addr += n
        length -= n
    return out


def _write(addr, data):
    data = bytes(data)
    for i in range(0, len(data), 128):
        _req("PUT", "/v1/machine:writemem?address=%04X&data=%s" % (addr + i, data[i:i + 128].hex()))


class Mon:
    """vicemon.Mon's read/write/resume/quit, through the Ultimate's REST API"""
    def __init__(self, *args, **kw):
        pass

    def read(self, addr, length):
        return _read(addr, length)

    def write(self, addr, data):
        _write(addr, data)

    def resume(self):
        pass                                # (the C64 never stopped)

    def cmd(self, ctype, body=b""):
        raise NotImplementedError("binary monitor command %#x: VICE only" % ctype)

    def quit(self):
        pass                                # (leave the C64 as it is)


class _Running:
    """stands in for the VICE process the tests wait for at the end"""
    def wait(self, timeout=None):
        return 0

    def terminate(self):
        pass


def start_vice(prg, disk=None, model=None, port=None, warp=True, extra=()):
    """reset, put the PRG at its load address as LOAD would, type RUN"""
    if disk:
        raise RuntimeError("disk tests need VICE (the Ultimate gives no image back)")
    data = open(prg, "rb").read()
    start = data[0] | data[1] << 8
    end = start + len(data) - 2
    _req("PUT", "/v1/machine:reset")
    for _ in range(50):                     # (wait for READY. on the screen
        time.sleep(0.2)                     # and BASIC's cursor on, $cc = 0)
        if _read(0x00cc, 1) == b"\x00" and bytes([18, 5, 1, 4, 25, 46]) in _read(0x0400, 1000):
            break
    else:
        raise RuntimeError("the Ultimate didn't come to READY.")
    _write(start, data[2:])
    _write(0x002d, bytes([end & 255, end >> 8]))       # end of the program
    _write(0x0277, b"RUN\r")                            # typed: RUN, RETURN
    _write(0x00c6, b"\x04")
    return _Running()
