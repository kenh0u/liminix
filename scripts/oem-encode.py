#!/usr/bin/env python3
"""
ELECOM WAB-I1750-PS factory image header (de)coder.

Implements OpenWrt's `Build/elx-header` (see openwrt/include/image-commands.mk)
in both directions:

  factory.bin (128B header + XOR'd body) <-> raw uImage payload

Header layout (128 bytes, all raw binary / explicit byte order):

    offset  size  contents
    ------  ----  ---------------------------------------------------------
    0x00    8     \x00\x00\x00\x00\x00\x00\x00\x03   (magic)
    0x08   34     zeros                                (pad to bs=42 block)
    0x2A    4     HWID as 4 raw bytes                 e.g. \x01\x07\x00\x0d
                                                        (big-endian when read
                                                        as uint32 = displayed
                                                        HWID)
    0x2E   16     zeros                                (pad to bs=20 block)
    0x3E    4     payload size, 32-bit big-endian      (PRE-XOR body size)
    0x42    4     zeros                                (pad to bs=8 block)
    0x46   16     raw MD5 digest (binary, 16B)        (PRE-XOR body MD5)
    0x56   42     zeros                                (pad to bs=58 block)
                                                       (so 0x56 + 42 = 0x80)

After the 128B header, the body is XOR'd with the cycling 8-byte pattern
(for WAB-I1750-PS: `8844A2D168B45A2D`, same as `ELECOM_HWID xor_pattern` in
target/linux/ath79/image/generic.mk).

Important: the size and MD5 in the header describe the **PRE-XOR** body.
On encode, this means we hash the raw input. On decode, this means we
must XOR-decode the body before comparing MD5 (since the body in the
file is post-XOR).

References:
  openwrt/include/image-commands.mk   Build/elx-header, Build/xor-image
  openwrt/target/linux/ath79/image/generic.mk  Device/elecom_wab-i1750-ps
  openwrt commit b18edb1b             porting commit (full procedure text)

Usage:
  scripts/oem-encode.py decode <factory.bin> [out.bin]
  scripts/oem-encode.py encode <raw.bin>    <out.bin>  <hw_id> <xor_pattern>
  scripts/oem-encode.py selftest
"""
from __future__ import annotations

import argparse
import hashlib
import os
import struct
import sys
import tempfile
import urllib.request
from pathlib import Path

HEADER_SIZE = 0x80  # 128 bytes

# WAB-I1750-PS constants from openwrt/target/linux/ath79/image/generic.mk
DEFAULT_HWID_WAB = "0107000d"
DEFAULT_XOR_WAB = "8844A2D168B45A2D"

# OpenWrt factory image URL (used by selftest)
FACTORY_URL_WAB = (
    "https://downloads.openwrt.org/releases/25.12.3/targets/ath79/generic/"
    "openwrt-25.12.3-ath79-generic-elecom_wab-i1750-ps-squashfs-factory.bin"
)


def xor_pattern(pattern_hex: str) -> bytes:
    """Decode the XOR pattern from hex string. Must be a multiple of 2 chars."""
    if len(pattern_hex) % 2 != 0:
        raise ValueError(f"xor pattern {pattern_hex!r} has odd length")
    try:
        return bytes.fromhex(pattern_hex)
    except ValueError as e:
        raise ValueError(f"xor pattern {pattern_hex!r} is not hex: {e}") from None


def decode_header(header: bytes) -> dict:
    """Parse a 128B elx-header. Returns a dict; raises ValueError on malformed input.

    Note: md5_hex returned here is the *raw digest as hex* (32 lowercase hex
    chars), not the bytes directly. The MD5 in the header is the raw 16-byte
    digest; we hex-encode it on the way out for human readability / comparison.
    """
    if len(header) != HEADER_SIZE:
        raise ValueError(f"header length {len(header)} != {HEADER_SIZE}")
    magic = header[0:8]
    if magic != b"\x00\x00\x00\x00\x00\x00\x00\x03":
        raise ValueError(
            f"bad magic: {magic.hex()} (expected 0000000000000003)"
        )
    hwid_bytes = header[0x2A:0x2A + 4]
    size_be = header[0x3E:0x3E + 4]
    payload_size = struct.unpack(">I", size_be)[0]
    md5_raw = header[0x46:0x46 + 16]
    return {
        "hwid_hex": hwid_bytes.hex(),
        "payload_size": payload_size,
        "md5_hex": md5_raw.hex(),  # lowercase 32-char hex of raw 16B digest
    }


def build_header(hwid_hex: str, payload: bytes, xor_pattern_bytes: bytes) -> bytes:
    """Build a 128B header for the given raw (PRE-XOR) body.

    Mirrors OpenWrt's `Build/elx-header`. The size and MD5 in the header
    describe the **pre-XOR body**, not the file payload, because OpenWrt
    builds the header before applying the XOR step.
    """
    if len(hwid_hex) != 8:
        raise ValueError(f"hw_id {hwid_hex!r} must be 8 hex chars")
    try:
        hwid_bytes = bytes.fromhex(hwid_hex)
    except ValueError as e:
        raise ValueError(f"hw_id {hwid_hex!r} is not hex: {e}") from None

    # PRE-XOR body size and MD5 — XOR preserves length so size is also
    # equal to the post-XOR body size, but MD5 must be of the pre-XOR body.
    payload_size = len(payload)
    md5_raw = hashlib.md5(payload).digest()  # 16 raw bytes

    hdr = bytearray(HEADER_SIZE)
    # bytes 0x00-0x07: magic
    hdr[0x00:0x08] = b"\x00\x00\x00\x00\x00\x00\x00\x03"
    # bytes 0x2A-0x2D: HWID (4 raw bytes, stored in the same byte order
    # as the HWID string is written; reading as big-endian uint32 yields
    # the displayed HWID)
    hdr[0x2A:0x2A + 4] = hwid_bytes
    # bytes 0x3E-0x41: payload size (big-endian)
    hdr[0x3E:0x3E + 4] = struct.pack(">I", payload_size)
    # bytes 0x46-0x55: raw MD5 digest (16 bytes)
    hdr[0x46:0x46 + 16] = md5_raw
    return bytes(hdr)


def xor_bytes(data: bytes, pattern: bytes) -> bytes:
    """XOR data with cycling pattern."""
    if not pattern:
        raise ValueError("xor pattern is empty")
    out = bytearray(len(data))
    plen = len(pattern)
    for i, b in enumerate(data):
        out[i] = b ^ pattern[i % plen]
    return bytes(out)


def decode_with_pattern(
    factory_path: Path, out_path: Path, xor_pattern_hex: str
) -> dict:
    """Decode factory.bin -> raw.bin with explicit XOR pattern."""
    raw = factory_path.read_bytes()
    if len(raw) < HEADER_SIZE:
        raise ValueError(
            f"{factory_path}: file too small ({len(raw)} < {HEADER_SIZE})"
        )
    header = raw[:HEADER_SIZE]
    body = raw[HEADER_SIZE:]
    info = decode_header(header)

    if info["payload_size"] != len(body):
        raise ValueError(
            f"{factory_path}: declared payload size {info['payload_size']} "
            f"!= actual body size {len(body)}"
        )

    pattern = xor_pattern(xor_pattern_hex)
    decoded = xor_bytes(body, pattern)
    # The header's MD5 is of the pre-XOR body, so we verify against the
    # XOR-decoded body — that's the original uImage.
    actual_md5 = hashlib.md5(decoded).hexdigest()
    md5_ok = actual_md5 == info["md5_hex"]

    out_path.write_bytes(decoded)

    return {
        "info": info,
        "md5_ok": md5_ok,
        "decoded_size": len(decoded),
    }


def encode_file(
    raw_path: Path, out_path: Path, hwid_hex: str, xor_pattern_hex: str
) -> dict:
    """Encode raw.bin -> factory.bin."""
    raw = raw_path.read_bytes()
    pattern = xor_pattern(xor_pattern_hex)
    header = build_header(hwid_hex, raw, pattern)
    xored = xor_bytes(raw, pattern)
    out_path.write_bytes(header + xored)
    # report PRE-XOR size and MD5 (matching the header bytes)
    return {
        "header": {
            "hwid_hex": hwid_hex,
            "payload_size": len(raw),
            "md5_hex": hashlib.md5(raw).hexdigest(),
        }
    }


def selftest() -> int:
    """Download the official OpenWrt WAB-I1750-PS factory image, decode it,
    and verify the result begins with the uImage magic 0x27051956.

    Exits 0 on success, non-zero on any failure. All artifacts are cleaned up.
    """
    print(f"selftest: downloading {FACTORY_URL_WAB}")
    with tempfile.TemporaryDirectory(prefix="oem-encode-selftest-") as tmp:
        tmpdir = Path(tmp)
        factory_path = tmpdir / "factory.bin"
        decoded_path = tmpdir / "decoded.bin"

        try:
            with urllib.request.urlopen(FACTORY_URL_WAB, timeout=60) as resp:
                factory_path.write_bytes(resp.read())
        except Exception as e:
            print(f"selftest: download failed: {e}", file=sys.stderr)
            return 2

        size = factory_path.stat().st_size
        print(f"selftest: downloaded {size} bytes")

        try:
            result = decode_with_pattern(
                factory_path, decoded_path, DEFAULT_XOR_WAB
            )
        except Exception as e:
            print(f"selftest: decode failed: {e}", file=sys.stderr)
            return 3

        info = result["info"]
        print(
            f"selftest: header HWID={info['hwid_hex']} "
            f"size={info['payload_size']} md5={info['md5_hex']}"
        )
        print(
            f"selftest: md5 check "
            f"{'OK' if result['md5_ok'] else 'MISMATCH'}"
        )
        if not result["md5_ok"]:
            print("selftest: header MD5 does not match body", file=sys.stderr)
            return 4

        decoded = decoded_path.read_bytes()
        if len(decoded) < 64:
            print(
                f"selftest: decoded payload too small ({len(decoded)}B)",
                file=sys.stderr,
            )
            return 5
        magic = decoded[0:4]
        # U-Boot uImage magic: 0x27051956, big-endian
        expected_magic = b"\x27\x05\x19\x56"
        if magic != expected_magic:
            print(
                f"selftest: uImage magic mismatch "
                f"(got {magic.hex()}, expected 27051956)",
                file=sys.stderr,
            )
            return 6
        # uImage header (per U-Boot): crc(4) + time(4) + size(4) + load(4) +
        # ep(4) + dcr(4) + os(1) + arch(1) + type(1) + comp(1) + name(32) = 64B
        # load/entry point at offset 0x10/0x14
        load = struct.unpack(">I", decoded[0x10:0x14])[0]
        entry = struct.unpack(">I", decoded[0x14:0x18])[0]
        type_ = decoded[0x1F]
        # 2 = standalone kernel, 3 = multi-file (kernel+rootfs combined).
        # OpenWrt factory.bin is built as a multi-file image (append-kernel |
        # pad-to | append-rootfs), so type 3 is the expected case.
        type_name = {2: "kernel", 3: "multi-file"}.get(type_, f"unknown({type_})")
        print(
            f"selftest: uImage load=0x{load:08x} "
            f"entry=0x{entry:08x} type={type_} ({type_name})"
        )
        if type_ not in (2, 3):
            print(
                f"selftest: uImage type {type_} unexpected (expected 2 or 3)",
                file=sys.stderr,
            )
            return 7
        if load != 0x80060000:
            print(
                f"selftest: WARNING load=0x{load:08x} != 0x80060000 "
                f"(PLAN §6.2 prediction)",
                file=sys.stderr,
            )

    print("selftest: OK")
    return 0


def main(argv: list[str]) -> int:
    p = argparse.ArgumentParser(
        prog="oem-encode.py",
        description="ELECOM WAB factory image (de)coder (elx-header + XOR)",
    )
    sub = p.add_subparsers(dest="cmd", required=True)

    pd = sub.add_parser("decode", help="decode factory.bin -> raw.bin")
    pd.add_argument("factory", type=Path)
    pd.add_argument("out", type=Path)
    pd.add_argument(
        "--xor",
        default=DEFAULT_XOR_WAB,
        help=f"XOR pattern hex (default: {DEFAULT_XOR_WAB} for WAB-I1750-PS)",
    )

    pe = sub.add_parser(
        "encode",
        help="encode raw.bin -> factory.bin (e.g. for OEM revert preparation)",
    )
    pe.add_argument("raw", type=Path)
    pe.add_argument("out", type=Path)
    pe.add_argument(
        "--hwid",
        default=DEFAULT_HWID_WAB,
        help=f"HWID hex (default: {DEFAULT_HWID_WAB} for WAB-I1750-PS)",
    )
    pe.add_argument(
        "--xor",
        default=DEFAULT_XOR_WAB,
        help=f"XOR pattern hex (default: {DEFAULT_XOR_WAB} for WAB-I1750-PS)",
    )

    sub.add_parser("selftest", help="download official factory.bin and verify")

    args = p.parse_args(argv)
    try:
        if args.cmd == "decode":
            r = decode_with_pattern(args.factory, args.out, args.xor)
            print(
                f"decoded: HWID={r['info']['hwid_hex']} "
                f"size={r['info']['payload_size']} "
                f"md5_ok={r['md5_ok']}"
            )
            if not r["md5_ok"]:
                return 1
            return 0
        if args.cmd == "encode":
            r = encode_file(args.raw, args.out, args.hwid, args.xor)
            h = r["header"]
            print(
                f"encoded: HWID={h['hwid_hex']} size={h['payload_size']} "
                f"md5={h['md5_hex']}"
            )
            return 0
        if args.cmd == "selftest":
            return selftest()
    except Exception as e:
        print(f"{args.cmd}: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
