#!/usr/bin/env python3
"""Query the phone's Rethink DNS resolver via adb+nc. Usage: dnsq.py <serial> <qname> [qtype]"""
import socket, struct, subprocess, sys, time

def build(qname: str, qtype: int = 1) -> bytes:
    q = b"".join(bytes([len(l)]) + l.encode() for l in qname.split(".") if l) + b"\x00"
    return struct.pack(">HHHHHH", 0x1234, 0x0100, 1, 0, 0, 0) + q + struct.pack(">HH", qtype, 1)

def parse(pkt: bytes) -> dict:
    flags, qd, an, ns, ar = struct.unpack(">HHHHH", pkt[2:12])
    return {"rcode": flags & 0xF, "flags": hex(flags), "an": an, "ns": ns,
            "has_cname": b"\x00\x00\x05" in pkt[12:], "len": len(pkt)}

def main():
    serial, qname = sys.argv[1], sys.argv[2]
    qtype = int(sys.argv[3]) if len(sys.argv) > 3 else 1
    qfile = "/data/local/tmp/dnsq.bin"
    local = "/tmp/dnsq.bin"
    with open(local, "wb") as f:
        f.write(build(qname, qtype))
    subprocess.run(["adb", "-s", serial, "push", local, qfile], capture_output=True, timeout=10)
    cmd = ["adb", "-s", serial, "shell", f"timeout 4 nc -u -w 2 10.111.222.3 53 < {qfile}"]
    t0 = time.time()
    p = subprocess.run(cmd, capture_output=True, timeout=10)
    ms = (time.time() - t0) * 1000
    if not p.stdout or len(p.stdout) < 12:
        print(f"{qname} qt={qtype} NO-RESPONSE ({ms:.0f}ms) rc={p.returncode}")
        return
    r = parse(p.stdout)
    print(f"{qname} qt={qtype} rcode={r['rcode']} an={r['an']} ns={r['ns']} cname={r['has_cname']} len={r['len']} ({ms:.0f}ms)")

if __name__ == "__main__":
    main()
