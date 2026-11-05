#!/usr/bin/env python3
"""Pad a linear 68000 binary to ROM_SIZE and split it into even/odd EPROM images.

The Twin Cobra main program ROMs are a 16-bit pair loaded with MAME's
ROM_LOAD16_BYTE: even bytes (high byte, D8-D15) -> b30_01.7j, odd bytes
(low byte, D0-D7) -> b30_03.7h. Each is a 27512 = 64 KiB.

Usage: split.py <linear.bin> <even_out.bin> <odd_out.bin> [rom_size_hex]
Default rom_size = 0x20000 (two 64 KiB halves).
"""
import sys

def main(argv):
    if len(argv) < 4:
        sys.stderr.write(__doc__)
        return 2
    src, even_out, odd_out = argv[1], argv[2], argv[3]
    rom_size = int(argv[4], 16) if len(argv) > 4 else 0x20000
    half = rom_size // 2

    data = bytearray(open(src, "rb").read())
    if len(data) > rom_size:
        sys.stderr.write(f"error: input {len(data):#x} exceeds rom size {rom_size:#x}\n")
        return 1
    data.extend(b"\xff" * (rom_size - len(data)))   # pad unused ROM with 0xFF

    even = data[0::2]   # high bytes -> b30_01.7j
    odd  = data[1::2]   # low  bytes -> b30_03.7h
    assert len(even) == half and len(odd) == half

    open(even_out, "wb").write(even)
    open(odd_out,  "wb").write(odd)
    print(f"linear {len(data):#x} -> {even_out} ({len(even):#x}) + {odd_out} ({len(odd):#x})")
    return 0

if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
