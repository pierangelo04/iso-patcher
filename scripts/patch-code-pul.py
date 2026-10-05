#!/usr/bin/env python3
"""
Binary-patch Retro Rewind's Code.pul so it talks to our private server.

What it does (data only, no code changes):
  1. Replaces the WWFC_DOMAIN string "play.rwfc.net" with our domain.
     Our domain MUST be <= 13 chars so it fits in place (null-padded).
     The script verifies every occurrence is null-terminated (standalone
     string, not part of a longer token) before patching.
  2. Replaces the 516-byte official PROD payload public key with our
     516-byte public key (same RSAPublicKey format: n0inv + n[64] + rr[64]).
     The script requires EXACTLY ONE occurrence; otherwise it aborts.

Fail-safe: if any expected pattern is missing (e.g. upstream changed the
domain or the key), the script exits non-zero and Code.pul is left
untouched, so the workflow fails instead of shipping a broken ISO.

Usage:
    patch-code-pul.py Code.pul <our-domain> <official-key.bin> <our-key.bin>

The .bin key files are raw 516-byte blobs. official-key.bin is the Retro
Rewind PROD key (public, from rr-pulsar's WiiLink.hpp); our-key.bin is the
public key matching the private key on our server.
"""

import sys


def fail(msg):
    print(f"ERRORE: {msg}", file=sys.stderr)
    sys.exit(1)


def main():
    if len(sys.argv) != 5:
        fail(f"uso: {sys.argv[0]} Code.pul <dominio> <official-key.bin> <our-key.bin>")

    pul_path, domain, official_key_path, our_key_path = sys.argv[1:5]

    domain_b = domain.encode("ascii")
    if len(domain_b) > 13:
        fail(f"dominio '{domain}' troppo lungo ({len(domain_b)} > 13): "
             "non entra nella patch in-place di 'play.rwfc.net'")

    with open(pul_path, "rb") as f:
        data = bytearray(f.read())
    with open(official_key_path, "rb") as f:
        official_key = f.read()
    with open(our_key_path, "rb") as f:
        our_key = f.read()

    if len(official_key) != 516 or len(our_key) != 516:
        fail("le chiavi devono essere di 516 byte")

    # --- 1. Domain ---
    old_domain = b"play.rwfc.net"
    # null-padded replacement keeps every offset stable
    new_domain = domain_b + b"\x00" * (len(old_domain) - len(domain_b))

    # find all occurrences and verify they are standalone C strings
    idx = 0
    occurrences = []
    while True:
        idx = data.find(old_domain, idx)
        if idx == -1:
            break
        end = idx + len(old_domain)
        if end >= len(data) or data[end] != 0:
            fail(f"'{old_domain.decode()}' a offset {idx:#x} non e' una "
                 "stringa C standalone (byte successivo non nullo)")
        occurrences.append(idx)
        idx = end

    if not occurrences:
        fail(f"'{old_domain.decode()}' non trovato in {pul_path}: "
             "upstream ha cambiato il dominio? Build interrotta.")
    print(f"dominio: {len(occurrences)} occorrenza/e di "
          f"'{old_domain.decode()}' -> '{domain}'")

    for off in occurrences:
        data[off:off + len(old_domain)] = new_domain

    # --- 2. Public key ---
    key_count = data.count(official_key)
    if key_count != 1:
        fail(f"chiave ufficiale trovata {key_count} volte (attesa: 1): "
             "upstream ha cambiato la chiave? Build interrotta.")
    print("chiave: 1 occorrenza della chiave ufficiale -> chiave PierWFC")
    data = data.replace(official_key, our_key)

    with open(pul_path, "wb") as f:
        f.write(data)
    print(f"OK: {pul_path} patchato ({len(data)} byte)")


if __name__ == "__main__":
    main()
