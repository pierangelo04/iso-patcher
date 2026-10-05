#!/usr/bin/env python3
"""
Binary-patch Retro Rewind's Code.pul so it talks to our private server.

What it does (data only, no code changes):
  1. Replaces the WWFC_DOMAIN string "play.rwfc.net" with our server address.
     Our address can be a domain (<=13 chars, in-place null-padded) or an
     IPv4 address (14 chars, e.g. "95.135.208.187"): in the latter case the
     script verifies 1 byte of zero padding after the string and uses it.
  2. If our address is an IP, removes the "nas." prefix from the
     "http://nas.%s/..." format strings (payload download + ratings API),
     so the URLs become "http://<IP>/..." (a subdomain of an IP is invalid).
     The strings shrink in place; the tail is null-padded.
  3. Replaces EVERY occurrence of the 516-byte official PROD payload public
     key with our 516-byte public key (same RSAPublicKey format:
     n0inv + n[64] + rr[64]). Code.pul bundles 3 copies; all are patched.

Fail-safe: if any expected pattern is missing (e.g. upstream changed the
domain, the key or the format strings), the script exits non-zero and
Code.pul is left untouched, so the workflow fails instead of shipping a
broken ISO.

Usage:
    patch-code-pul.py Code.pul <our-address> <official-key.bin> <our-key.bin>
"""

import sys


def fail(msg):
    print(f"ERRORE: {msg}", file=sys.stderr)
    sys.exit(1)


def is_ipv4(s):
    parts = s.split(".")
    return len(parts) == 4 and all(p.isdigit() and 0 <= int(p) <= 255 for p in parts)


def main():
    if len(sys.argv) != 5:
        fail(f"uso: {sys.argv[0]} Code.pul <indirizzo> <official-key.bin> <our-key.bin>")

    pul_path, address, official_key_path, our_key_path = sys.argv[1:5]
    addr_b = address.encode("ascii")
    use_ip = is_ipv4(address)

    with open(pul_path, "rb") as f:
        data = bytearray(f.read())
    with open(official_key_path, "rb") as f:
        official_key = f.read()
    with open(our_key_path, "rb") as f:
        our_key = f.read()

    if len(official_key) != 516 or len(our_key) != 516:
        fail("le chiavi devono essere di 516 byte")

    # --- 1. Domain / address ---
    old_domain = b"play.rwfc.net"
    idx = 0
    occurrences = []
    while True:
        idx = data.find(old_domain, idx)
        if idx == -1:
            break
        end = idx + len(old_domain)
        if end >= len(data) or data[end] != 0:
            fail(f"dominio a offset {idx:#x} non e' una stringa C standalone")
        occurrences.append(idx)
        idx = end

    if not occurrences:
        fail(f"'{old_domain.decode()}' non trovato in {pul_path}: "
             "upstream ha cambiato il dominio? Build interrotta.")
    print(f"dominio: {len(occurrences)} occorrenza/e -> '{address}'")

    if len(addr_b) <= len(old_domain):
        new_domain = addr_b + b"\x00" * (len(old_domain) - len(addr_b))
        for off in occurrences:
            data[off:off + len(old_domain)] = new_domain
    elif use_ip and len(addr_b) == len(old_domain) + 1:
        # 14-char IPv4: needs 1 byte of zero padding after the null
        for off in occurrences:
            end = off + len(old_domain)
            if data[end] != 0 or data[end + 1] != 0:
                fail(f"padding insufficiente a offset {off:#x} per l'IP")
            data[off:off + len(addr_b)] = addr_b
            data[off + len(addr_b)] = 0
    else:
        fail(f"indirizzo '{address}' non supportato per la patch in-place")

    # --- 2. Remove "nas." prefix when using a bare IP ---
    if use_ip:
        marker = b"http://nas.%s"
        idx = 0
        nfmt = 0
        while True:
            idx = data.find(marker, idx)
            if idx == -1:
                break
            end = data.find(b"\x00", idx)
            if end == -1:
                fail(f"stringa non terminata a offset {idx:#x}")
            # new = "http://" + rest after "nas." (4 bytes), keep null
            new_str = data[idx:idx + 7] + data[idx + 11:end + 1]
            old_len = end + 1 - idx
            data[idx:idx + len(new_str)] = new_str
            data[idx + len(new_str):idx + old_len] = b"\x00" * (old_len - len(new_str))
            nfmt += 1
            idx = end
        if nfmt == 0:
            fail("format 'http://nas.%s' non trovato: upstream cambiato?")
        print(f"format: {nfmt} stringa/e 'http://nas.%s' -> 'http://%s'")

    # --- 3. Public key (all occurrences) ---
    key_count = data.count(official_key)
    if key_count == 0:
        fail("chiave ufficiale non trovata: upstream ha cambiato la chiave? "
             "Build interrotta.")
    print(f"chiave: {key_count} occorrenza/e della chiave ufficiale -> chiave PierWFC")
    data = data.replace(official_key, our_key)

    with open(pul_path, "wb") as f:
        f.write(data)
    print(f"OK: {pul_path} patchato ({len(data)} byte)")


if __name__ == "__main__":
    main()
