#!/usr/bin/env python3
"""Patch Retro Rewind Code.pul so it talks to a custom WFC server (PierWFC).

Changes, in every region build inside Code.pul:
  1. the hard-coded domain "play.rwfc.net" -> custom domain (max 15 chars,
     the slot in the binary is 16 bytes including the NUL)
  2. the production payload public key (516 bytes, same format that
     wfc-patcher-wii misc/generate-key.py produces) -> public key of the
     custom server (tools/pierwfc/pierwfc-public-key.pem, RSA 2048, e=65537)

Usage: patch_code_pul.py Code.pul DOMAIN PUBLIC_KEY.pem
"""
import re
import struct
import sys

from cryptography.hazmat.primitives import serialization

OLD_DOMAIN = b"play.rwfc.net"
# Production key published in wfc-patcher-wii include/wwfcPayloadPublicKey.hpp
OLD_KEY_HEAD = bytes.fromhex("fab09703e025f455678fa059")  # start of the blob
KEY_BLOB_LEN = 516


def encode_key(pem_path):
    pub = serialization.load_pem_public_key(open(pem_path, "rb").read())
    nums = pub.public_numbers()
    if nums.e != 65537 or nums.n.bit_length() != 2048:
        sys.exit("error: key must be RSA 2048 with e=65537")
    n = nums.n
    n_bytes = int.to_bytes(n, length=0x100, byteorder="big")
    n0inv = -(pow(n, -1, 2**32)) & 0xFFFFFFFF
    data = struct.pack(">I", n0inv)
    for i in range(0x100 >> 2):
        o = 0x100 - i * 4 - 4
        data += n_bytes[o:o + 4]
    r = pow(pow(2, 2048), 2, n)
    r_bytes = int.to_bytes(r, length=0x100, byteorder="big")
    for i in range(0x100 >> 2):
        o = 0x100 - i * 4 - 4
        data += r_bytes[o:o + 4]
    assert len(data) == KEY_BLOB_LEN
    return data


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    path, domain, pem = sys.argv[1:]
    dom = domain.encode()
    if len(dom) > 15 or not re.fullmatch(rb"[a-z0-9.-]+", dom):
        sys.exit("error: domain must be a-z0-9.- and at most 15 chars")
    d = bytearray(open(path, "rb").read())

    # domain slot: 13-char string + NULs = 16 bytes; overwrite the whole slot
    n_dom = 0
    for m in list(re.finditer(re.escape(OLD_DOMAIN) + b"\x00{1,3}", d)):
        s, e = m.start(), m.end()
        slot = 16
        if e - s != slot:
            sys.exit("error: unexpected slot size %d at %d" % (e - s, s))
        d[s:e] = dom.ljust(slot, b"\x00")
        n_dom += 1
    if n_dom == 0:
        sys.exit("error: domain string not found")

    # key
    new_key = encode_key(pem)
    old_key = None
    idx = d.find(OLD_KEY_HEAD)
    if idx < 0:
        sys.exit("error: production key not found")
    old_key = bytes(d[idx:idx + KEY_BLOB_LEN])
    n_key = 0
    pos = 0
    while True:
        i = d.find(old_key, pos)
        if i < 0:
            break
        d[i:i + KEY_BLOB_LEN] = new_key
        pos = i + KEY_BLOB_LEN
        n_key += 1
    if n_key == 0:
        sys.exit("error: key not replaced")

    open(path, "wb").write(d)
    print("patched %d domain slots and %d key blobs in %s" % (n_dom, n_key, path))


if __name__ == "__main__":
    main()
