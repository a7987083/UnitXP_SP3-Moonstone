#!/usr/bin/env python3
"""Patch a rebuilt UnitXP_SP3.dll PE/COFF timestamp back to the pinned v89 API baseline.

Why:
Some Lua addons use UnitXP("version", "coffTimeDateStamp") as an API feature gate.
This project rebuilds exact UnitXP_SP3 v89 source (commit
3370011e396ccdbf4c9921f6cf2b005bed818b24) with additional AutoRange features.
A fresh linker timestamp makes those addons incorrectly assume post-v89 commands
such as UnitXP("speed", "player") exist. The unknown command then falls through to
legacy UnitXP unit-name handling and raises "Unknown unit name: speed".

This changes only IMAGE_FILE_HEADER.TimeDateStamp. It does not modify executable code.
"""

from pathlib import Path
import argparse
import struct

# Exact pinned upstream v89 source commit time:
# 2026-03-29 02:32:08 UTC
V89_COMPAT_TIMESTAMP = 1774751528


def patch_timestamp(path: Path) -> tuple[int, int]:
    data = bytearray(path.read_bytes())
    if data[:2] != b"MZ":
        raise RuntimeError("not an MZ/PE file")
    pe_off = struct.unpack_from("<I", data, 0x3C)[0]
    if data[pe_off:pe_off + 4] != b"PE\0\0":
        raise RuntimeError("invalid PE signature")
    stamp_off = pe_off + 8
    old = struct.unpack_from("<I", data, stamp_off)[0]
    struct.pack_into("<I", data, stamp_off, V89_COMPAT_TIMESTAMP)
    path.write_bytes(data)
    return old, V89_COMPAT_TIMESTAMP


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("dll", type=Path)
    args = ap.parse_args()
    old, new = patch_timestamp(args.dll)
    print(f"Patched {args.dll}: TimeDateStamp {old} -> {new}")


if __name__ == "__main__":
    main()
