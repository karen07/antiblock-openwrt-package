#!/usr/bin/env python3
import ipaddress
import socket
import struct
import sys


def encode_name(name: str) -> bytes:
    out = bytearray()
    for label in name.rstrip(".").split("."):
        raw = label.encode("ascii")
        if not 0 < len(raw) <= 63:
            raise ValueError("invalid DNS label")
        out.append(len(raw))
        out.extend(raw)
    out.append(0)
    return bytes(out)


def main() -> int:
    if len(sys.argv) != 5:
        print(f"usage: {sys.argv[0]} NAME IPV4 TARGET_IP TARGET_PORT", file=sys.stderr)
        return 2

    name, ipv4, target_ip, target_port_s = sys.argv[1:]
    target_port = int(target_port_s)
    addr = ipaddress.IPv4Address(ipv4).packed
    qname = encode_name(name)

    header = struct.pack("!HHHHHH", 0xA17B, 0x8180, 1, 1, 0, 0)
    question = qname + struct.pack("!HH", 1, 1)
    answer = b"\xc0\x0c" + struct.pack("!HHIH", 1, 1, 120, 4) + addr
    packet = header + question + answer

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("0.0.0.0", 53))
    sock.sendto(packet, (target_ip, target_port))
    sock.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
