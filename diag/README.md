# Twin Cobra / Kyuukyoku Tiger diagnostic ROM

A generic power-on diagnostic for the Toaplan TP-011 PCB family (Twin Cobra /
Kyukyoku Tiger), bootleg and original. Design and rationale: [../SPEC.md](../SPEC.md).
Hardware reference: [../research/FINDINGS.md](../research/FINDINGS.md).

## Status
- **Stage 0** — RAM-less CPU-alive heartbeat (now implicit: any pin toggle = CPU ran).
- **Stage 2** — video bring-up: HD6845 CRTC init (R0-R9 = `DE A0 B0 8F 22 06 1E 1F 00 07`,
  measured from the game ROM), whole-palette flood, screen on. The screen comes up FIRST
  (unlike the stock ROM) and shows a solid status colour. Verified in MAME (screenshots in
  `doc/`).
- **Stage 2b** — on-screen text using the game's own char-ROM font (digits `0x00-0x09`,
  `A-Z` `0x0A-0x23`, blank `0x2D`): white 8x8 text on black. Prints a header and the work-RAM
  result, with the failing address/expected/got in hex on failure. Verified in MAME
  (`doc/stage2b_text_pass.png`, `doc/stage2b_text_fail.png`). Note: text leans on the char
  ROM, text VRAM and palette RAM being good; the heartbeat pin remains the dead-board fallback.
- **Stage 1** — work / DSP-shared RAM test `$30000-$33FFF`, register-only. Done, verified
  in MAME on both a good board (PASS) and a forced fault (FAIL). Verified on a real
  bootleg board (PASS).
- **Stage 3** — CRC32 of each 27256 program chip at `$020000` (identified against the
  known MAME sets), sprite RAM `$40000` and palette RAM `$50000`. Every test runs and
  reports even if an earlier one failed. Verified in MAME (`doc/stage3_pass.png`,
  `doc/stage3_fault.png`).

### On-screen text report (white on black, monitor is vertical/ROT270)
```
TWIN COBRA DIAG
WORK RAM  PASS                    (or WORK RAM FAIL + detail line, then it stops)

ROM HI 3A646618 TC WORLD           CRC32 of the even (D8-D15) 27256 + matched set
ROM LO D7D1E317 TC WORLD           CRC32 of the odd  (D0-D7)  27256 + matched set
SPRITE RAM  PASS                   (or FAIL + "A <addr> E <exp> G <got>")
PALETTE RAM PASS                   (or FAIL + detail line)
ALL TESTS PASS                     (or SOME TESTS FAILED)
```

Source: [src/diag.s](src/diag.s) (the evolving main image). `src/stage0.s` is the
heartbeat-only ROM, `src/spin.s` the reads-only ROM.

Earlier builds showed status as a full-screen colour (blue/green/red, `doc/stage2_*.png`);
the text report replaced that.

Next stages (shared Z80 RAM / sound handshake, DSP self-test, inputs) per
[../SPEC.md](../SPEC.md).

## Heartbeat / result codes (mainlatch LS259 Q2, pin 6, of $7800D)
- **Nothing toggling** → the 68000 is not executing: check 28 MHz clock + divisions,
  `/RESET`, program-ROM fetch at `$000000`, `/DTACK`.
- **Slow steady square wave** → all tests so far PASSED.
- **Bursts of 4 fast pulses + long gap** → a test FAILED. On failure these registers are
  frozen (inspect in MAME, or a later on-screen stage will show them):
  `A5` = failing address, `D5` = expected word, `D6` = word read back.

## Stage 1 — what it tests
Work RAM `$30000-$33FFF` (16 KiB; also holds the 68000 stack), register-only so it reports
even with dead RAM:
1. data-bus walking-ones at the base word (stuck/bridged data lines),
2. address/data uniqueness — every word written its own index, then verified (stuck/shorted
   address lines, aliasing, dead cells),
3. march patterns AAAA then 5555 (each cell must hold both polarities).

## Stage 3 — what it tests
1. **Program ROM CRC32, per chip.** The two 27256s at `$020000-$02FFFF` hold the game's
   entry point (`$20194`), so a bad chip there gives a black screen immediately. Each byte
   lane (one chip) is CRC32'd in circuit with the same algorithm MAME uses, so the number
   on screen can be compared with any MAME set. Known sets are named on screen:
   `TC WORLD`, `TC USA`, `K TIGER`, `K TIGER ALT`; anything else shows `UNKNOWN` and
   counts as a failure. Testing in circuit also catches socket, decode and data-line
   faults that a programmer read would miss.
2. **Sprite RAM** `$40000-$40FFF`: same walk / uniqueness / AAAA / 5555 test as work RAM.
3. **Palette RAM** `$50000-$50DFF`: same test, comparing bits 0-14 only (xBGR_555 bit 15
   is unused and may not be stored). The test overwrites the palette, which is restored
   straight afterwards so the text stays readable.

Takes about a second to run.

## Fault-injection test (how the FAIL path was verified)
Build a variant whose RAM test points at ROM so writes can't stick:
```
m68k-elf-as -m68000 --defsym WORK_BASE=0x0 src/diag.s -o build/fault.o
m68k-elf-ld -T diag.ld build/fault.o -o build/fault.elf
m68k-elf-objcopy -O binary build/fault.elf build/fault.bin
```
It must land in the FAIL burst pattern (it does).

For stage 3, point the tests at ROM the same way:
```
m68k-elf-as -m68000 --defsym PROG2=0x0 --defsym SPR_BASE=0x10000 --defsym PALT_BASE=0x0 \
    src/diag.s -o build/fault.o
```
Expected: both ROM lines `UNKNOWN`, `SPRITE RAM FAIL A 010000 E 0001 G FFFF`,
`PALETTE RAM FAIL A 000000 E 0001 G 0003`, `SOME TESTS FAILED` (it does; the printed
CRCs match Python's `zlib.crc32` for those bytes).

## Important: the diagnostic keeps the DSP OFF
The game enables the TMS320C10 DSP at boot (control latch `$7800D` bit Q6 = 1), which
hands the DSP the 68000 bus. On a board with a dead/absent/non-responding DSP — common on
bootlegs — enabling it **stalls the 68000**, giving a black screen with only a brief burst
of activity at power-up. This diagnostic deliberately keeps the DSP **disabled** (Q6 = 0)
and held in reset, so the 68000 never hands off the bus. If a board runs this diagnostic
but dies on the real game, suspect the **DSP subsystem**.

## Dead-board bring-up order
1. **Heartbeat ROM** (`build/twincobr_hb_7j.bin` / `_7h.bin`, `make hb`): toggles the
   `$7800D` LS259 Q2 output (pin 6) forever, touching nothing but ROM + that latch.
   - Pin toggles ~1-2 Hz  -> the 68000 runs, fetches ROM, and drives the latch. Good.
   - No toggle at all      -> CPU not running: 28 MHz clock + divisions, `/RESET`,
     program-ROM fetch at `$000000`, or `/DTACK` for the ROM/latch.
2. **Full diagnostic** (`build/twincobr_diag_7j.bin` / `_7h.bin`): with the CPU proven
   alive, this brings up the screen and tests work RAM. Colour/text result, or the
   heartbeat-pin fallback, tells you what failed next.

## Build
Needs GNU binutils for `m68k-elf` (`brew install m68k-elf-binutils`), plus `python3`.

```
make            # -> build/twincobr_diag_7j.bin + build/twincobr_diag_7h.bin
make dump       # disassemble for inspection
make clean
```

## Burn
The two output files are 27512 (64 KiB) images that replace the main-CPU program
ROM pair:

| File | Socket | Bytes |
|------|--------|-------|
| `build/twincobr_diag_7j.bin` | `b30_01.7j` | even (D8-D15) |
| `build/twincobr_diag_7h.bin` | `b30_03.7h` | odd  (D0-D7)  |

Leave the other board ROMs in place. The diagnostic lives entirely in the first
program-ROM pair; the second pair (`.8j`/`.8h`) is not used.

**Bootleg boards: check which sockets you use.** Bootlegs label and lay out the ROMs
differently from the original. The diagnostic must go in the two **27512 (64 KB)
program sockets** — the pair that holds the reset vector at `$000000` (on the original,
`b30_01.7j` / `b30_03.7h`). Many bootlegs also carry two **27256** program ROMs (the
original's `.8j`/`.8h` code at `$020000`); putting the diag there gives a board that
does one brief burst of bus activity and then hangs. Confirmed on a bootleg with
TMM24512 mask ROMs in the 512 positions: a 27C512 drops straight in.

## Stage 0 — how to read it
On power-up the ROM sets a safe state (DSP and sound Z80 held in reset, IRQ off,
screen off) and then toggles **one LS259 latch output — Q2, the VBLANK-interrupt
enable** — as a steady square wave, using only CPU registers (no RAM, no stack, no DSP,
no video). Interrupts are masked in the CPU, so this has no visible effect. (Earlier
builds used Q3, the flip-screen bit, which made a working screen flip every second.)

- Put a scope / logic probe on the mainlatch LS259 (the `$7800D` latch) **Q2 output,
  pin 6**, and reset the board. There are two LS259s; only the mainlatch toggles.
- A steady ~square wave there = the 68000 is alive, reached the ROM, and is
  executing. This is the one thing a black screen cannot tell you.
- No toggle at all = the CPU is not running: check the 28 MHz clock and its
  divisions, `/RESET`, that it can fetch the program ROM at `$000000`, and `/DTACK`.

74LS259 pinout for reference: Q0-Q3 = pins 4-7, Q4-Q7 = pins 9-12, D = 13, /LE = 14,
/CLR = 15, GND = 8, VCC = 16.
