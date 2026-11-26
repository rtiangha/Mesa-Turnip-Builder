#!/usr/bin/env python3
"""Verify the 8-bit SSBO PoC patch is present in a built Turnip driver .so.

The patch sets storage_8bit=True on the a6xx gen4 base in
src/freedreno/common/freedreno_devices.py. That flips one byte in the
compiled device table: the Adreno 660 (FD660) entry's props.storage_8bit.

This script locates the FD660 entry in the .so by its distinctive
magic_raw register block and reads that one byte. It needs only
python3 -- no readelf, no NDK, no Mesa source.

Usage:  verify_8bit_poc.py <path-to-libvulkan_freedreno.so>
Exit 0: patch is present (storage_8bit=1).  Exit 1: patch is absent.
Exit 2: the entry could not be found (the device-table layout probably
changed upstream; re-derive the offsets with offsetof() and update
MAGIC_RAW_OFF / STORAGE_8BIT_OFF below).

Offsets are from Mesa main 2026-11-25, struct fd_dev_info in
src/freedreno/common/freedreno_dev_info.h:
  offsetof(struct fd_dev_info, magic_raw) = 80
  offsetof(struct fd_dev_info, props.storage_8bit) = 745
"""
import struct
import sys

# FD660 magic_raw: 12 {reg, value} pairs (uint32 each), unique to FD660.
MAGIC_RAW = [
    (38916, 31), (38917, 2), (41208, 2), (46592, 83918848),
    (34304, 0), (44547, 5120), (44544, 16777216), (48644, 0),
    (38400, 33554432), (3602, 1), (36353, 0), (36356, 68157440),
]
MAGIC_RAW_OFF = 80
STORAGE_8BIT_OFF = 745


def main():
    if len(sys.argv) != 2:
        print("usage: verify_8bit_poc.py <libvulkan_freedreno.so>")
        return 2
    path = sys.argv[1]
    try:
        data = open(path, "rb").read()
    except OSError as e:
        print(f"ERROR: cannot read {path}: {e}")
        return 2
    anchor = b"".join(struct.pack("<II", reg, val) for reg, val in MAGIC_RAW)
    idx = data.find(anchor)
    if idx < 0:
        print("ERROR: FD660 device-table entry not found in " + path)
        print("  (the device-table layout probably changed upstream; "
              "re-derive MAGIC_RAW_OFF / STORAGE_8BIT_OFF)")
        return 2
    entry = idx - MAGIC_RAW_OFF
    flag = data[entry + STORAGE_8BIT_OFF]
    if flag == 1:
        print(f"OK: FD660 storage_8bit=1 -- PoC patch is present in {path}")
        return 0
    print(f"FAIL: FD660 storage_8bit={flag} (expected 1) -- "
          f"PoC patch is NOT in {path}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
