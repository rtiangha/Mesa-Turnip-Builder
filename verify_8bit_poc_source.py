#!/usr/bin/env python3
"""Verify the 8-bit SSBO PoC patch took effect in the Mesa source tree.

The patch adds `storage_8bit = True` to the `a6xx_gen4` GPUProps block
in src/freedreno/common/freedreno_devices.py. This script checks that
specific block (not just a file-wide grep, because the stock file
already sets storage_8bit = True once, in a7xx_base).

Usage:  verify_8bit_poc_source.py <path-to-freedreno_devices.py>
Exit 0: a6xx_gen4 has storage_8bit = True (patch is in the source).
Exit 1: it does not (the patch did not apply, or applied to the
        wrong file / a different tree).
Exit 2: the file could not be read or a6xx_gen4 was not found (the
        file layout probably changed upstream).
"""
import re
import sys


def main():
    if len(sys.argv) != 2:
        print("usage: verify_8bit_poc_source.py <freedreno_devices.py>")
        return 2
    path = sys.argv[1]
    try:
        lines = open(path).read().splitlines()
    except OSError as e:
        print(f"ERROR: cannot read {path}: {e}")
        return 2
    start = None
    for i, line in enumerate(lines):
        if re.match(r"a6xx_gen4\s*=\s*GPUProps\(", line):
            start = i
            break
    if start is None:
        print("ERROR: a6xx_gen4 = GPUProps(...) not found in " + path)
        print("  (the file layout probably changed upstream)")
        return 2
    # The block ends at the next top-level assignment.
    end = len(lines)
    for j in range(start + 1, len(lines)):
        if re.match(r"[a-zA-Z_][a-zA-Z0-9_]*\s*=", lines[j]):
            end = j
            break
    block = lines[start:end]
    if any("storage_8bit = True" in line for line in block):
        print(f"OK: a6xx_gen4 has storage_8bit = True in {path}")
        return 0
    print(f"FAIL: a6xx_gen4 does NOT have storage_8bit = True in {path}")
    print("  (the PoC patch did not apply to this file)")
    return 1


if __name__ == "__main__":
    sys.exit(main())
