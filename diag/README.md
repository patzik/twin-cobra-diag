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
  in MAME on both a good board (PASS) and a forced fault (FAIL).

### On-screen text report (white on black, monitor is vertical/ROT270)
```
TWIN COBRA DIAG
WORK RAM  PASS          WORK RAM  FAIL
                        A <addr6> E <exp4> G <got4>
```

### On-screen status colours (whole screen)
- **BLUE**  — video is up, tests running
- **GREEN** — all tests so far passed (`doc/stage2_pass_green.png`)
- **RED**   — a test failed (`doc/stage2_fail_red.png`); A5/D5/D6 hold addr/expected/got

The palette-flood trick (fill all 1792 xBGR_555 entries with one colour) makes the whole
screen that colour regardless of tile-ROM or VRAM contents, so it needs no font/graphics.

Source: [src/diag.s](src/diag.s) (the evolving main image). `src/stage0.s` is kept as the
original minimal skeleton for reference.

Later stages (sprite/palette RAM, video bring-up, inputs, DSP, …) per [../SPEC.md](../SPEC.md).

## Heartbeat / result codes (mainlatch LS259 flip pin, Q3 of $7800D)
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

## Fault-injection test (how the FAIL path was verified)
Build a variant whose RAM test points at ROM so writes can't stick:
```
m68k-elf-as -m68000 --defsym WORK_BASE=0x0 src/diag.s -o build/fault.o
m68k-elf-ld -T diag.ld build/fault.o -o build/fault.elf
m68k-elf-objcopy -O binary build/fault.elf build/fault.bin
```
It must land in the FAIL burst pattern (it does).

## Important: the diagnostic keeps the DSP OFF
The game enables the TMS320C10 DSP at boot (control latch `$7800D` bit Q6 = 1), which
hands the DSP the 68000 bus. On a board with a dead/absent/non-responding DSP — common on
bootlegs — enabling it **stalls the 68000**, giving a black screen with only a brief burst
of activity at power-up. This diagnostic deliberately keeps the DSP **disabled** (Q6 = 0)
and held in reset, so the 68000 never hands off the bus. If a board runs this diagnostic
but dies on the real game, suspect the **DSP subsystem**.

## Dead-board bring-up order
1. **Heartbeat ROM** (`build/twincobr_hb_7j.bin` / `_7h.bin`, `make hb`): toggles the
   `$7800D` LS259 flip pin (Q3) forever, touching nothing but ROM + that latch.
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

## Stage 0 — how to read it
On power-up the ROM sets a safe state (DSP and sound Z80 held in reset, IRQ off,
screen off) and then toggles **one LS259 latch output — the flip bit, Q3** — as a
steady square wave, using only CPU registers (no RAM, no stack, no DSP, no video).

- Put a scope / logic probe on the mainlatch LS259 (the `$7800D` latch) **Q3 output
  pin**, or a point driven by it, and reset the board.
- A steady ~square wave there = the 68000 is alive, reached the ROM, and is
  executing. This is the one thing a black screen cannot tell you.
- No toggle at all = the CPU is not running: check the 28 MHz clock and its
  divisions, `/RESET`, that it can fetch the program ROM at `$000000`, and `/DTACK`.

(The exact pin will be pinned to a convenient board test point against the ktiger
schematic in [../research/schematics/](../research/schematics/) before the first
burn.)
