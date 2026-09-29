"""Tiny VICE binary monitor client (API v2) for testing Magic Typewriter.

Starts its own VICE (x64sc) with the binary monitor on port 6510, apart
from the C64 Bridge one (6502), so tests can attach disk images freely.

Usage from other scripts:
    from vicemon import Mon
    m = Mon(port=6510)
    m.read(0x0400, 40); m.write(0x02d2, bytes([...])); m.resume()
"""
import socket, struct, time, subprocess, os

VICE = r"C:/bin/GTK3VICE-3.9-win64/GTK3VICE-3.9-win64/bin/x64sc.exe"
PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK = os.path.join(PROJ, "build", "test")
os.makedirs(WORK, exist_ok=True)


class Mon:
    def __init__(self, port=6510, host="127.0.0.1", timeout=20):
        t0 = time.time()
        while True:
            try:
                self.s = socket.create_connection((host, port), timeout=5)
                break
            except OSError:
                if time.time() - t0 > timeout:
                    raise
                time.sleep(0.3)
        self.s.settimeout(10)
        self.req = 1
        self.buf = b""

    def _recv_exact(self, n):
        while len(self.buf) < n:
            chunk = self.s.recv(65536)
            if not chunk:
                raise ConnectionError("VICE closed the monitor connection")
            self.buf += chunk
        out, self.buf = self.buf[:n], self.buf[n:]
        return out

    def _response(self, want_id):
        while True:
            hdr = self._recv_exact(12)
            stx, api, length, rtype, err, rid = struct.unpack("<BBIBBI", hdr)
            body = self._recv_exact(length)
            if rid == want_id:
                if err:
                    raise RuntimeError(f"monitor error {err:#x} for command {rtype:#x}")
                return rtype, body
            # anything else is an event (stopped/resumed/...) - ignore

    def cmd(self, ctype, body=b""):
        rid = self.req
        self.req += 1
        self.s.sendall(struct.pack("<BBIIB", 0x02, 0x02, len(body), rid, ctype) + body)
        return self._response(rid)

    def bank(self, name):
        """the monitor's bank number for a name like "cpu" or "ram" """
        if not hasattr(self, "banks"):
            _, resp = self.cmd(0x82)
            self.banks, i = {}, 2
            for _ in range(struct.unpack("<H", resp[:2])[0]):
                size = resp[i]
                bid, nlen = struct.unpack("<HB", resp[i + 1:i + 4])
                self.banks[resp[i + 4:i + 4 + nlen].decode()] = bid
                i += 1 + size
        return self.banks[name]

    def _bank_for(self, addr):
        # $e000-$ffff: always the RAM there (the editor lives under the
        # KERNAL ROM, which is switched in during disk work); else what the
        # CPU sees (I/O, color RAM)
        return self.bank("ram") if addr >= 0xe000 else self.bank("cpu")

    def read(self, addr, length):
        body = struct.pack("<BHHBH", 0, addr, addr + length - 1, 0, self._bank_for(addr))
        _, resp = self.cmd(0x01, body)
        n = struct.unpack("<H", resp[:2])[0]
        return resp[2:2 + n]

    def write(self, addr, data):
        data = bytes(data)
        body = struct.pack("<BHHBH", 0, addr, addr + len(data) - 1, 0, self._bank_for(addr)) + data
        self.cmd(0x02, body)

    def resume(self):
        self.cmd(0xaa)

    def quit(self):
        """quit VICE cleanly (it writes disk images back)"""
        rid = self.req
        self.req += 1
        self.s.sendall(struct.pack("<BBIIB", 0x02, 0x02, 0, rid, 0xbb))
        time.sleep(1)
        self.s.close()

    def close(self):
        try:
            self.resume()
        except Exception:
            pass
        self.s.close()


def start_vice(prg, disk=None, model="c64", port=6510, warp=True, extra=()):
    rc = os.path.join(WORK, "vicerc-test")   # scratch settings: never Jim's own
    open(rc, "w").close()
    args = [VICE, "-config", rc, "-model", model, "-sounddev", "dummy",
            "-binarymonitor", "-binarymonitoraddress", f"ip4://127.0.0.1:{port}"]
    if warp:
        args.append("-warp")
    if disk:
        args += ["-8", disk]
    reu = os.environ.get("MT_REU")                # e.g. MT_REU=512: an REU
    if reu and "-reu" not in extra:               # of that many KB for every
        args += ["-reu", "-reusize", reu]         # test run
    args += list(extra)
    args += ["-autostartprgmode", "1", "-autostart", prg]
    return subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
