#!/usr/bin/env python3
"""Build the crash-catcher version of the game's 27512 program pair.

usage: mkcrash.py <rom dir> <crash.bin> <out_7j.bin> <out_7h.bin>

<rom dir> must hold your own Twin Cobra (World) b30_01.7j and b30_03.7h. The
output is that game code with src/crash.s added in unused ROM space, the
exception vectors pointed at it, and 4 spare bytes per chip adjusted so the
game's own ROM checksum (twincobr $25E54) still passes. The output contains
game code: keep it out of git.
"""
import sys, zlib, struct

BASE = 0x1A400          # where crash.s is linked
FREE = (0x1A370, 0x1B000)   # FF-filled in the World set
COMP = 0x1AFC0          # one 8-byte group (4 bytes per chip) for the checksum fix
STUB = 12               # bytes per vector stub in crash.s
KEEP = {28: 'IRQ4 (VBLANK handler)', 31: 'IRQ7'}
KNOWN = {'b30_01.7j': 0x07F64D13, 'b30_03.7h': 0x41BE6978}


def lane_sum(img, lane):
    """The game's sum: 32-bit words made of 4 bytes of one chip (movep.l),
    over the whole 64 KiB chip, modulo 2^32."""
    s = 0
    for k in range(0x20000 // 8):
        b = img[8 * k + lane: 8 * k + lane + 8: 2]
        s += (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3]
    return s & 0xFFFFFFFF


def main():
    if len(sys.argv) != 5:
        sys.exit(__doc__)
    romdir, crash_path, out_e, out_o = sys.argv[1:]
    roms = {}
    for name, crc in KNOWN.items():
        d = open(f'{romdir}/{name}', 'rb').read()
        if len(d) != 0x10000 or zlib.crc32(d) != crc:
            sys.exit(f'{name}: not the Twin Cobra World ROM (CRC {zlib.crc32(d):08X}, '
                     f'want {crc:08X}); the free space and vectors are only checked for that set')
        roms[name] = d
    even, odd = roms['b30_01.7j'], roms['b30_03.7h']
    img = bytearray(x for pair in zip(even, odd) for x in pair)

    crash = open(crash_path, 'rb').read()
    if BASE + len(crash) > COMP:
        sys.exit(f'handler too big: {len(crash)} bytes, room for {COMP - BASE}')
    if any(b != 0xFF for b in img[FREE[0]:FREE[1]]):
        sys.exit('free space is not empty')
    for n in range(2, 64):
        v = struct.unpack('>I', img[4 * n:4 * n + 4])[0]
        if n not in KEEP and not 0x100 <= v <= 0x108:
            sys.exit(f'vector {n} = {v:06X}, expected the game\'s $100-$108 trap')
        st = crash[(n - 2) * STUB:(n - 2) * STUB + 4]
        if st != bytes([0x33, 0xFC, 0x00, n]):
            sys.exit(f'stub layout in crash.bin is off at vector {n}')

    before = [lane_sum(img, 0), lane_sum(img, 1)]
    img[BASE:BASE + len(crash)] = crash
    for n in range(2, 64):
        if n not in KEEP:
            img[4 * n:4 * n + 4] = struct.pack('>I', BASE + (n - 2) * STUB)
    for lane in (0, 1):
        delta = (lane_sum(img, lane) - before[lane]) & 0xFFFFFFFF
        fix = (0xFFFFFFFF - delta) & 0xFFFFFFFF   # the group was FFFFFFFF
        for j in range(4):
            img[COMP + lane + 2 * j] = (fix >> (24 - 8 * j)) & 0xFF
    after = [lane_sum(img, 0), lane_sum(img, 1)]
    assert after == before, (before, after)

    e, o = bytes(img[0::2]), bytes(img[1::2])
    open(out_e, 'wb').write(e)
    open(out_o, 'wb').write(o)
    print(f'crash handler {len(crash)} bytes at ${BASE:X}; ROM sums unchanged '
          f'({before[0]:08X} / {before[1]:08X})')
    print(f'{out_e}  CRC32 {zlib.crc32(e):08X}')
    print(f'{out_o}  CRC32 {zlib.crc32(o):08X}')


if __name__ == '__main__':
    main()
