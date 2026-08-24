#!/usr/bin/env python3
"""Small deterministic DNS responder/client for the OpenWrt dnsmasq cache E2E."""

import ipaddress
import socket
import struct
import sys


def encode_name(name):
    return (
        b"".join(
            bytes((len(label),)) + label
            for label in (part.encode("ascii") for part in name.split("."))
        )
        + b"\x00"
    )


def question_end(packet):
    pos = 12
    while pos < len(packet):
        size = packet[pos]
        if size > 63 or pos + 1 + size > len(packet):
            raise ValueError("invalid DNS query name")
        pos += 1 + size
        if size == 0:
            break
    if pos + 4 > len(packet):
        raise ValueError("truncated DNS question")
    return pos + 4


def serve(name, address, counter):
    answer_ip = ipaddress.IPv4Address(address).packed
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("0.0.0.0", 5300))
    while True:
        packet, remote = sock.recvfrom(4096)
        try:
            end = question_end(packet)
            if packet[12:end].lower() != encode_name(name) + struct.pack("!HH", 1, 1):
                continue
            answer = (
                packet[:2]
                + struct.pack("!HHHHH", 0x8180, 1, 1, 0, 0)
                + packet[12:end]
                + b"\xc0\x0c"
                + struct.pack("!HHIH", 1, 1, 120, 4)
                + answer_ip
            )
            with open(counter, "a", encoding="ascii") as file:
                file.write("1\n")
            sock.sendto(answer, remote)
        except (ValueError, IndexError):
            continue


def query(server, name, address):
    req = (
        struct.pack("!HHHHHH", 0x1234, 0x0100, 1, 0, 0, 0)
        + encode_name(name)
        + struct.pack("!HH", 1, 1)
    )
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(5)
    try:
        sock.sendto(req, (server, 53))
        answer, _ = sock.recvfrom(4096)
    finally:
        sock.close()
    if (
        len(answer) < 16
        or answer[:2] != req[:2]
        or answer[-4:] != ipaddress.IPv4Address(address).packed
        or struct.unpack_from("!H", answer, 6)[0] == 0
    ):
        raise ValueError("DNS response did not contain the expected A record")


if __name__ == "__main__":
    if len(sys.argv) != 5 or sys.argv[1] not in ("serve", "query"):
        raise SystemExit(
            f"usage: {sys.argv[0]} serve|query name|server ipv4|name counter|ipv4"
        )
    if sys.argv[1] == "serve":
        serve(sys.argv[2], sys.argv[3], sys.argv[4])
    else:
        query(sys.argv[2], sys.argv[3], sys.argv[4])
