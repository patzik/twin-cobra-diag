#!/usr/bin/env python3
"""Turn palette dumps from tools/capture_pal.lua into src/gamepal.inc.

usage: make_gamepal.py <folder with pal_*.bin> <out.inc>

Each dump is the game's palette RAM (1792 xBGR_555 words, big-endian). Twin
Cobra loads its whole palette once and keeps it through the attract mode; only
a few BG colours are cycled for animation. The tool reports how many entries
change between dumps and uses the last one.
The output is game data: keep it out of a public repository.
"""
import glob, struct, sys

def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    files = sorted(glob.glob(sys.argv[1] + '/pal_*.bin'))
    if not files:
        sys.exit('no pal_*.bin dumps found')
    pals = [open(f, 'rb').read() for f in files]
    if any(len(p) != 1792 * 2 for p in pals):
        sys.exit('a dump is not 1792 words')
    w = struct.unpack('>1792H', pals[-1])
    ws = [struct.unpack('>1792H', p) for p in pals]
    differ = sum(1 for i in range(1792) if any(x[i] != w[i] for x in ws))
    with open(sys.argv[2], 'w') as out:
        out.write('/* Twin Cobra (World) palette, captured in MAME from the running game\n'
                  ' * (tools/capture_pal.lua + tools/make_gamepal.py). GAME DATA: keep it\n'
                  ' * out of a public repository. Layout as palette RAM: sprites 0-1023\n'
                  ' * (64 sets of 16), BG 1024-1279, FG 1280-1535 (16 x 16), text\n'
                  ' * 1536-1791 (32 x 8). */\n    .even\ngamepal:\n')
        for i in range(0, 1792, 8):
            out.write('    .short ' + ', '.join('0x%04x' % v for v in w[i:i + 8]) + '\n')
    print(f'{len(files)} dumps, {differ} of 1792 entries change between them; wrote {sys.argv[2]}')

if __name__ == '__main__':
    main()
