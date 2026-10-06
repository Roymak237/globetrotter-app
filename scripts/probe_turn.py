"""Probe the TURN relay from outside the VPS.

Two questions, answered in order:
  1. Is UDP 3478 reachable from the public internet at all? A STUN binding
     request needs no credentials, so a reply proves the firewall is open.
  2. Does a TURN allocation actually succeed with the deployed credentials?
     That is the thing a phone on mobile data will try to do.

Run with TURN_PASSWORD set in the environment for step 2.
"""
import hashlib
import hmac
import os
import secrets
import socket
import struct
import sys

HOST = "kamer-go.duckdns.org"
PORT = 3478
MAGIC = 0x2112A442

BIND_REQUEST = 0x0001
ALLOCATE_REQUEST = 0x0003
ATTR_USERNAME = 0x0006
ATTR_MESSAGE_INTEGRITY = 0x0008
ATTR_ERROR_CODE = 0x0009
ATTR_REALM = 0x0014
ATTR_NONCE = 0x0015
ATTR_XOR_RELAYED_ADDRESS = 0x0016
ATTR_REQUESTED_TRANSPORT = 0x0019
ATTR_XOR_MAPPED_ADDRESS = 0x0020


def pad4(b: bytes) -> bytes:
    return b + b"\x00" * ((4 - len(b) % 4) % 4)


def build(msg_type: int, txid: bytes, attrs: bytes = b"") -> bytes:
    return struct.pack("!HHI", msg_type, len(attrs), MAGIC) + txid + attrs


def attr(kind: int, value: bytes) -> bytes:
    return struct.pack("!HH", kind, len(value)) + pad4(value)


def parse_attrs(data: bytes) -> dict:
    out, i = {}, 20
    while i + 4 <= len(data):
        kind, length = struct.unpack("!HH", data[i:i + 4])
        value = data[i + 4:i + 4 + length]
        out[kind] = value
        i += 4 + length + ((4 - length % 4) % 4)
    return out


def decode_xor_addr(value: bytes, txid: bytes) -> str:
    family = value[1]
    port = struct.unpack("!H", value[2:4])[0] ^ (MAGIC >> 16)
    if family == 0x01:
        raw = struct.unpack("!I", value[4:8])[0] ^ MAGIC
        ip = socket.inet_ntoa(struct.pack("!I", raw))
    else:
        key = struct.pack("!I", MAGIC) + txid
        ip = socket.inet_ntop(
            socket.AF_INET6,
            bytes(a ^ b for a, b in zip(value[4:20], key)),
        )
    return f"{ip}:{port}"


def send(sock, payload, addr):
    sock.sendto(payload, addr)
    return sock.recvfrom(2048)[0]


def main() -> int:
    try:
        ip = socket.gethostbyname(HOST)
    except OSError as exc:
        print(f"FAIL: cannot resolve {HOST}: {exc}")
        return 1
    print(f"target : {HOST} ({ip}:{PORT})")

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(5)
    addr = (ip, PORT)

    # --- 1. reachability -------------------------------------------------
    txid = secrets.token_bytes(12)
    try:
        data = send(sock, build(BIND_REQUEST, txid), addr)
    except socket.timeout:
        print("FAIL: no STUN reply in 5s.")
        print("      UDP 3478 is blocked. Open it on the host firewall.")
        return 1
    if struct.unpack("!H", data[0:2])[0] != 0x0101:
        print("FAIL: unexpected STUN reply type.")
        return 1
    attrs = parse_attrs(data)
    seen = attrs.get(ATTR_XOR_MAPPED_ADDRESS)
    print("PASS   : UDP 3478 reachable from the public internet")
    if seen:
        print(f"         relay sees this machine as {decode_xor_addr(seen, txid)}")

    # --- 2. allocation ---------------------------------------------------
    password = os.environ.get("TURN_PASSWORD", "")
    username = os.environ.get("TURN_USERNAME", "kamergo")
    if not password:
        print("SKIP   : no TURN_PASSWORD given, allocation not tested")
        return 0

    txid = secrets.token_bytes(12)
    transport = attr(ATTR_REQUESTED_TRANSPORT, b"\x11\x00\x00\x00")
    data = send(sock, build(ALLOCATE_REQUEST, txid, transport), addr)
    attrs = parse_attrs(data)

    realm = attrs.get(ATTR_REALM, b"").decode()
    nonce = attrs.get(ATTR_NONCE, b"")
    if not realm or not nonce:
        print("FAIL: relay did not issue a realm/nonce challenge.")
        return 1

    # Long-term credential: MD5 is mandated by RFC 5389 for this key, not a
    # choice. The password itself never crosses the wire.
    key = hashlib.md5(f"{username}:{realm}:{password}".encode()).digest()
    txid = secrets.token_bytes(12)
    body = (
        transport
        + attr(ATTR_USERNAME, username.encode())
        + attr(ATTR_REALM, realm.encode())
        + attr(ATTR_NONCE, nonce)
    )
    # The integrity hash covers a header whose length already counts the
    # attribute about to be appended.
    header = struct.pack("!HHI", ALLOCATE_REQUEST, len(body) + 24, MAGIC) + txid
    digest = hmac.new(key, header + body, hashlib.sha1).digest()
    data = send(sock, header + body + attr(ATTR_MESSAGE_INTEGRITY, digest), addr)

    kind = struct.unpack("!H", data[0:2])[0]
    attrs = parse_attrs(data)
    if kind == 0x0103:
        relayed = attrs.get(ATTR_XOR_RELAYED_ADDRESS)
        print("PASS   : TURN allocation succeeded")
        if relayed:
            print(f"         relay address handed out: {decode_xor_addr(relayed, txid)}")
        print()
        print("Calls can now traverse carrier-grade NAT.")
        return 0

    err = attrs.get(ATTR_ERROR_CODE, b"")
    if len(err) >= 4:
        code = err[2] * 100 + err[3]
        print(f"FAIL   : allocation refused ({code}: {err[4:].decode(errors='replace')})")
    else:
        print(f"FAIL   : unexpected reply type 0x{kind:04x}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
