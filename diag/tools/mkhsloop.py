#!/usr/bin/env python3
"""Patch Twin Cobra's program ROMs 8J / 8H (MAME set twincobr: b30_26_ii.8j,
b30_27_ii.8h) so the attract mode shows only the high score table, over and
over: the game's own code, with two changes.

  $20E5A  addq.w #1,(a1) -> addq.w #2,(a1)
          attract state 0 goes on to state 2 (high score) instead of 1 (title)
  $2102C  move.w #64,$314A2 ; move.w #3,$31836
       -> bclr #3,$314A1    ; move.w #2,$31836
          at the end of the high score, back to state 2 (and clear its
          'set up' flag so it starts over) instead of on to state 3

The game checks its ROMs at power on (sum table at $2FFE8, one long per byte
lane and half); the two entries for $20000-$2FFE7 are recomputed.
Usage: mkhsloop.py b30_26_ii.8j b30_27_ii.8h out_8j.bin out_8h.bin"""
import sys, struct

e = bytearray(open(sys.argv[1], "rb").read())
o = bytearray(open(sys.argv[2], "rb").read())
assert len(e) == len(o) == 0x8000
img = bytearray(0x10000)                       # $20000-$2FFFF
img[0::2], img[1::2] = e, o

def put(addr, words, expect):
    a = addr - 0x20000
    old = struct.unpack(">%dH" % len(expect), img[a:a + 2 * len(expect)])
    assert list(old) == expect, "not the expected ROM version at %X" % addr
    img[a:a + 2 * len(words)] = struct.pack(">%dH" % len(words), *words)

put(0x20E5A, [0x5451], [0x5251])
put(0x2102C, [0x08B9, 0x0003, 0x0003, 0x14A1, 0x33FC, 0x0002, 0x0003, 0x1836],
             [0x33FC, 0x0040, 0x0003, 0x14A2, 0x33FC, 0x0003, 0x0003, 0x1836])

# the game's check: per lane, movep.l over $20000-$2FFE7 in steps of 8,
# summed as longs, plus the table long, must be 0
for lane, slot in ((0, 1), (1, 3)):
    s = 0
    for a in range(lane, 0xFFE8, 8):
        s += (img[a] << 24) | (img[a + 2] << 16) | (img[a + 4] << 8) | img[a + 6]
    t = 0xFFE8 + 4 * slot
    img[t:t + 4] = struct.pack(">I", (-s) & 0xFFFFFFFF)

open(sys.argv[3], "wb").write(bytes(img[0::2]))
open(sys.argv[4], "wb").write(bytes(img[1::2]))
print("patched")
