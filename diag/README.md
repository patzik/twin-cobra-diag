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
- **Loop-test menu** — P1 button 1 after the tests: pick work / sprite / palette RAM and
  loop write/read on it for scoping, with a scope trigger on the heartbeat pin and live
  read-backs. Verified in MAME (`doc/loop_menu.png`), also after a work-RAM failure.

### On-screen text report (white on black, monitor is vertical/ROT270)
```
TWIN COBRA DIAG
WORK RAM  PASS                    (or WORK RAM FAIL + detail line, then it stops)

ROM HI 3A646618 TC WORLD           CRC32 of the even (D8-D15) 27256 + matched set
ROM LO D7D1E317 TC WORLD           CRC32 of the odd  (D0-D7)  27256 + matched set
NO VBLANK SIGNAL                   (only if $78009 bit 7 never toggles)
SPRITE RAM  PASS                   (or FAIL + "A <addr> E <exp> G <got>")
PALETTE RAM PASS                   (or FAIL + detail line)
TEXT VRAM   PASS                   stage 4: video RAM behind the offset/data ports
FG VRAM     PASS
BG VRAM     PASS                   (a FAIL adds "A <offset> E <exp> G <got>")
SHARED RAM  PASS                   stage 5: Z80 shared RAM (or FAIL + detail line)
SOUND CPU   OK                     (or NOT RUNNING / ROM SUM BAD / NO REPLY CMD xx)
SOUND ROM   80ECFF66 TC WORLD      CRC32 of sound ROM $4000-$6FFF, read through the Z80
ALL TESTS PASS                     (or SOME TESTS FAILED)
```

Source: [src/diag.s](src/diag.s) (the evolving main image). `src/stage0.s` is the
heartbeat-only ROM, `src/spin.s` the reads-only ROM.

Earlier builds showed status as a full-screen colour (blue/green/red, `doc/stage2_*.png`);
the text report replaced that.

- **Stage 4** — text / foreground / background video RAM. Verified in MAME (pass and a
  forced FG fault).
- **Stage 5** — Z80 shared RAM, Z80 start-up handshake, sound ROM sum and CRC through the
  Z80. Verified in MAME (pass, dead Z80, bad shared RAM, no start signal, bad sound ROM).
  An earlier build hung on real boards right after `BG VRAM PASS` (it tested shared RAM
  with the Z80 in reset); fixed, see the stage 5 section.

Next stages (DSP self-test, inputs) per [../SPEC.md](../SPEC.md).

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

## Loop-test menu (for scoping a failing RAM)
When the tests finish (pass or fail, including a work-RAM failure) the screen shows
`P1 BUTTON 1  LOOP TEST MENU`. Hold P1 button 1 to open it:

```
LOOP TEST  STICK SELECTS
TARGET SPRITE RAM  040000          P1 up/down: WORK RAM / SPRITE RAM / PALETTE RAM
B1 START  B2 STOP

W0000 R 0000  WFFFF R FFFF         live read-backs while looping
```

B1 starts a tight loop on the first word of the chosen RAM: write `0000`, read, write
`FFFF`, read, repeat. Every data line toggles on every cycle, so you can follow one line
with a scope from the 68000 through any 74LS245 buffers to the RAM pins and see where
it stops toggling or gets stuck. The heartbeat pin (mainlatch LS259 **pin 6**) goes high
at the start of each cycle, which makes a clean **scope trigger**. The two values read
back are shown live, so a stuck or floating bit is visible on screen as well (a good
board shows `0000` and `FFFF`). B2 stops the loop and returns to the menu.

The menu and loop use no stack or work RAM, so they still work on a board whose work
RAM failed. Inputs: P1 at `$78004`, active high (bit 0 up, 1 down, 4 B1, 5 B2).

## Stage 3 — what it tests
1. **Program ROM CRC32, per chip.** The two 27256s at `$020000-$02FFFF` hold the game's
   entry point (`$20194`), so a bad chip there gives a black screen immediately. Each byte
   lane (one chip) is CRC32'd in circuit with the same algorithm MAME uses, so the number
   on screen can be compared with any MAME set. Known sets are named on screen:
   `TC WORLD`, `TC USA`, `K TIGER`, `K TIGER ALT`; anything else shows `UNKNOWN` and
   counts as a failure. Testing in circuit also catches socket, decode and data-line
   faults that a programmer read would miss.
2. **Sprite RAM** `$40000-$40FFF`: same walk / uniqueness / AAAA / 5555 test as work RAM,
   but done in short bursts that each start right after VBLANK ends. Afterwards sprite RAM
   is cleared to zero, which turns every sprite off, so test patterns never show on screen.
3. **Palette RAM** `$50000-$50DFF`: same test with the **screen turned off**, comparing
   bits 0-14 only (xBGR_555 bit 15 is unused and may not be stored). The test overwrites
   the palette, which is restored straight afterwards so the text stays readable.

**Why the timing matters (real hardware only).** The video hardware uses sprite RAM and
palette RAM too, and the CPU gets clean access only at certain times. The game's own RAM
test (`$25c0a-$25dd2` in the 27256 pair) shows when: it waits for VBLANK (`$78009` bit 7)
to end before each sprite RAM burst, and it turns the screen off (latch `0x0E`) before
testing palette RAM. Earlier diag builds did neither. On real boards they reported false
SPRITE RAM / PALETTE RAM failures and left black-and-white garbage blocks on screen, while
MAME (which doesn't model the contention) passed. If VBLANK never arrives, the diag prints
`NO VBLANK SIGNAL`, counts it as a failure, and runs the sprite test unsynced.

The loop-test menu follows the same rules: sprite RAM bursts are synced to VBLANK, and the
screen is blanked during each palette RAM burst, so the picture flickers on that target.

Takes about a second to run.

## Stage 4 — video RAM (text / foreground / background)
The game tests these three RAMs before it ever turns the screen on, and **if any of them
fails it never starts the sound CPU and hangs** in the same loop as a dead Z80 (see stage 5).
They are reached through an offset register plus a data port (text `$70004`/`$7E000`, bg
`$72004`/`$7E002`, fg `$74004`/`$7E004`; no auto-increment). Each one gets an
address-uniqueness pass (every word its own offset) and the game's own AAAA / 5555 passes,
with the screen off as the game does. Sizes: text 2048 words, fg 4096, bg 4096 (bank 0).
The text test overwrites the on-screen report, so the text layer is copied to work RAM
first and put back afterwards. The detail line shows the **last** failing layer; its
`A` value is the word offset inside that layer.

## Stage 5 — sound CPU (Z80)
**Why it matters:** right after its RAM tests the game asks the Z80 for blocks of the sound
ROM and waits for an answer with **no timeout** (`$25F4A`: wait for `FF` at `$7A001`).
A dead Z80, bad sound ROM or bad shared RAM gives a permanent black screen with the
screen-enable latch (LS259 pin 12) low, and the sound-reset latch (pin 5) high.

**The 68000 can only reach shared RAM through the Z80's bus.** On the bootleg schematic an
access to `$7Axxx` drives the Z80's `/BUSRQ` (pin 25, from K12 74LS138 output O5) and the
68000 waits until the Z80 answers `/BUSACK` (pin 23, via K4 74LS74 and K5 74LS32 into the
J16 DTACK gate). A Z80 that is held in reset, has no clock, or is dead never answers, and
the 68000 then waits forever; no software timeout can catch that. So before it touches
shared RAM the diag releases the Z80 and prints:

```
SHARED RAM  WAIT Z80 BUS
```

**If the screen stops on that line, the Z80 is not granting its bus.** Check, on the Z80:
clock (pin 6), `/RESET` (26, must be high), `/BUSRQ` (25, goes low and stays low = the
68000 is asking), `/BUSACK` (23, never goes low = the Z80 is not answering), then the
K4 / K5 / J16 path back to the 68000's `/DTACK` (pin 10).

(An earlier build tested shared RAM with the Z80 held in reset: that hangs on real boards
right after `BG VRAM PASS`. MAME doesn't model the bus request, so it passed there.)

1. **Z80 start-up**, using the protocol from the game and its Z80 code (`$2F7B`): out of
   reset its first code writes `FF` to `$8000` (68000 `$7A001`) and `00` to `$8001`, then
   waits for `AA` at `$8001`. No `FF` within ~3.5 s: `SOUND CPU NOT RUNNING` (reported after
   the shared RAM test). Check its clock, `/WAIT` (24), `/HALT` (18) and the sound ROM.
2. **Shared RAM** `$7A000-$7AFFF` (2 KiB, 8-bit: the low byte of each word; Z80 `$8000-$87FF`),
   tested while the Z80 sits waiting for `AA`. The march patterns are `A5`/`5A` rather than
   `AA`/`55`, so the test can't start the Z80 by accident.
3. **Start and ROM check:**
   - write `AA` (start). The Z80 adds up its whole ROM; if the sum is not 0 it writes `00` and
     stops for good: `SOUND CPU ROM SUM BAD` - re-read / replace the sound ROM.
   - send the game's 12 commands `F0`-`FB`: for each the Z80 copies 1 KiB of its ROM
     (`$4000 + n*$400`) into shared RAM and answers `FF`. No answer: `NO REPLY CMD xx`.
4. **Sound ROM CRC32** over those 12 blocks (`$4000-$6FFF`), so the sound ROM is checked
   through the Z80 itself. `80ECFF66` = `b30_05_ii.4f` (Twin Cobra World). Other sets use a
   different sound ROM and show `UNKNOWN`, which is **not** counted as a failure.

The loop-test menu has a fourth target, **SHARED RAM** (`$7A000`). Entering the menu restarts
the Z80 and leaves it waiting for `AA`, so it only reads `$8001` and keeps granting its bus.
Only D0-D7 are real there; D8-D15 read back whatever floats.

![pass](doc/stage5_pass.png)

Left to right: good board, dead Z80, bad shared RAM bit, Z80 never gets the start signal,
bad sound ROM, loop menu on SHARED RAM (`doc/stage5_faults.png`):

![faults](doc/stage5_faults.png)

**MAME note:** MAME does not wire latch Q1 to the Z80 reset (the Z80 always runs), but the
bootleg schematic does (LS259 K17 pin 5 → Z80 `/RESET`). MAME also doesn't model the
`/BUSRQ`-`/BUSACK` handshake. The stage-5 tests in MAME were run with a Lua script that adds
the reset wiring and flags any 68000 access to shared RAM while the Z80 is in reset (a hang
on real hardware).

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
