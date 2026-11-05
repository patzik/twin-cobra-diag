# Twin Cobra / Kyuukyoku Tiger / Flying Shark — hardware notes for a diagnostic ROM

Board: Toaplan **TP-011**, Taito game number **B30** (Flying Shark = TP-007 / B02).
Main crystal: **28.000 MHz**, divided by a 74LS163 to 14 / 7 / 3.5 / 1.75 MHz.

## Processors / clocks
| Role | Chip | Clock | Source |
|------|------|-------|--------|
| Main CPU | 68000 (Signetics SCN68000C8N64) | 7 MHz (28/4); export sets have a separate 10 MHz OSC | MAME |
| Sound CPU | Z80 (Z0840004) | 3.5 MHz (28/8) | MAME |
| Co-processor / protection | TMS320C10 DSP (Toaplan custom-badged) | 14 MHz (28/2) | MAME |
| CRTC | Hitachi HD6845SP | 3.5 MHz (28/8) | MAME |
| Sound | Yamaha YM3812 (OPL2) + YM3014B DAC | 3.5 MHz | MAME |

Video: VSync 54.88 Hz, HSync 15.28 kHz, screen rotated 270° (vertical). Custom Toaplan
ULAs: GXL-01 ("T.T-1") and TOAPLAN-02 M70H005 ("T.T-2"). Sprite generator = "SCU".

## 68000 memory map
```
000000-02ffff  ROM (Twin Cobra; Flying Shark only to 01ffff)
030000-033fff  RAM shared with TMS320C10 DSP   (16-bit)
040000-040fff  Sprite RAM
050000-050dff  Palette RAM
060001 / 060003 HD6845 CRTC address / data
070000-070005  text layer scroll + VRAM offset
072000-072005  bg layer scroll + VRAM offset
074000-074005  fg layer scroll + VRAM offset
076000-076003  spare layer scroll (unused)
078000  r DSWA      078002 r DSWB
078004  r P1        078006 r P2
078008  r VBLANK (bit7) + Flying Shark coin/start
07800b  w coinlatch (LS259)  — FShark DSP comms / coin
07800d  w mainlatch (LS259)  — TwinCobra DSP comms / system control
07a000-07afff  RAM shared with Z80 (16-bit here, 8-bit on Z80 side; even bytes)
07e000-07e005  data port into text/bg/fg VRAM (auto-increment via the 070004/072004/074004 offset regs)
```

### mainlatch (LS259 at 07800d), bit selected by data bits 3-1, value = bit0
```
Q2 int_enable   (68000 IRQ4 / VBLANK enable)
Q3 flipscreen
Q4 bg RAM bank  (0x000 / 0x1000)
Q5 fg ROM bank  (0x000 / 0x1000)
Q6 DSP INT line (turn DSP on) -- Twin Cobra
Q7 display on/off
```
Encoded values written as a byte to 07800d: 04/05=IRQ4 off/on, 06/07=flip off/on,
08/09=bg bank 0/1, 0A/0B=fg bank 0/1, **0C/0D=DSP INT on/off**, 0E/0F=screen off/on.
(Flying Shark toggles the DSP INT via 07800a / coinlatch instead.)

## Z80 map
```
0000-7fff ROM
8000-87ff RAM shared with 68000
IN : 00 YM3812 status | 10 coin/start inputs | 40 DSWA | 50 DSWB
OUT: 00 YM3812 ctrl | 01 YM3812 data | 20 coin counters/lockout (LS259)
```

## DSP (TMS320C10) — Harvard, word-addressed
- Program ROM: internal 0x600 words on originals (Toaplan mask MCU); **0x800 words in
  EXTERNAL PROMs on bootlegs**.
- DSP IO ports: `0` = set 68K address (seg+addr), `1` = read/write that 68K word,
  `3` bit15 -> BIO line (polled).
- Address decode: `seg = (data & 0xe000) << 3; addr = (data & 0x1fff) << 1` — only
  segments 0x30000/0x40000/0x50000 are valid (shared RAM, sprite RAM, palette RAM).
- **Handshake / critical for diagnostics:** writing the DSP-INT bit turns the DSP ON and
  **HALTS the 68000**. The DSP runs its routine against shared RAM, then releases BIO and
  the hardware automatically un-halts the 68000. So the DSP and main CPU are mutually
  exclusive; you cannot poll the DSP from a running 68000 the naive way.
- DSP command 68K writes to `$30000`: **01 (TC) / 0C (KT) = run DSP self-test and report
  DSP ROM checksum** — directly reusable as a DSP sanity check in a diagnostic ROM.
  Other commands do enemy AI / collision / shot control. (Flying Shark uses `$30004`,
  cmd 0B = self-test + checksum.)

### Per-game DSP part numbers (interchangeable groups)
```
Hishou Zame  D70011U GXC-01   | Flying/Sky Shark + Wardner  D70012U GXC-02 (interchangeable)
Kyukyoku Tiger D70015U GXC-03 | Twin Cobra  D70016U GXC-04  (Demon's World interchangeable w/ TC)
```

## Bootleg specifics (relevant to this PCB)
- MAME bootleg sets note: *"the difference is the TMS320C10 code which is in external
  PROMs instead of internal."* Twin Cobra bootleg DSP PROMs are `tc1b` + `tc2a`
  (0x800 bytes each, 16-bit split).
- **"A0 and A1 are swapped between the TMS320C10 and these BPROMs on the board."** — watch
  for this address-line swap when reading/verifying the bootleg DSP PROMs.
- Flying Shark "bootleg with 8741": DSP's IO port 2 talks to an extra i8741 MCU
  (startup reads it 3x; 1st and 3rd equal, 2nd different).
- Gulf War II (Comad, 1991) is effectively a Twin Cobra bootleg/hack running the same driver.

## ROM set (twincobr, main set)
- maincpu (68K): b30_01.7j + b30_03.7h (0x00000, /odd-even), b30_26_ii.8j + b30_27_ii.8h (0x20000)
- audiocpu (Z80): b30_05_ii.4f (0x8000)
- dsp: dsp_21.bin + dsp_22.bin (0x800 each) — or decapped d70015u/d70016u mask MCU
- chars: b30_06/07/08 (0x4000 each)
- fg_tiles: b30_13/14/15/16 (0x10000 each)
- bg_tiles: b30_09/10/11/12 (0x8000 each)
- sprites (scu): b30_17/18/19/20 (0x10000 each)
- proms: 82s129 d3,d4 (sprite priority) + 82s123 d2,e18,b24 (sprite/tile control)

## "Test mode"
There is **no real self-test** in the game ROMs — only a cross-hatch colour grid plus a
separate DIP-switch display. This is exactly why a custom diagnostic ROM is worthwhile.

## User's ROM set (twincobr.zip) — VERIFIED
All 27 files match the MAME `twincobr` (World) set by CRC32, including the DSP PROM pair
`dsp_21.bin` (2d135376) + `dsp_22.bin` (79389a71). So the dump is complete and correct and
can be used both as a known-good reference and to burn replacements. Extracted to
research/roms_extracted/.

## SCHEMATIC — FOUND (this is the big one for repair)
`research/schematics/ktiger-bootleg-schematic.pdf` — full hierarchical **KiCad schematic of
the Kyukyoku Tiger BOOTLEG board**, title "Kyukyoku Tiger -Bootleg-", drawn directly from an
original PCB by "Tejada" for the JOTEGO team (2022-04-29), 18 sheets. Source:
https://github.com/jotego/jtbin/blob/master/sch/ktiger.pdf (KiCad source lives in jtcores).
This matches the user's board type (bootleg) and shows the actual glue logic the bootleg uses
in place of Toaplan's custom ULAs, plus the external-PROM DSP wiring.
Sheet hierarchy: main, memories, boardb, boardc, colmix, object, prio, gfxa, misc, sound,
capacitors. Signal names confirm the bus-arbitration DSP model: CPU_A/CPU_D, ~BR, ~BGACK,
~BUSG, ~IPL/~IPL2, ~HALT, ~RESET, ~DTACK, ~BERR, ~AS/~UDS/~LDS, CK14/CK3p5, ~HS/~VS,
EPROM[0..15]. **Use this as the primary wiring reference for probing the dead board.**

## MiSTer ktiger core (jotego/jtcores) — reviewed, adds detail beyond MAME
Public, merged core: jotego/jtcores PR #1653 "ktiger: based on bootleg schematics and mame
reference" by Marc Emmerson (memmerson), GPL-3.0, at `cores/ktiger/`. It reuses the Wardner
core's modules (`cores/wardnr/hdl/`), incl. the DSP `jttoaplan1_dsp.v` and an open TMS320C10
(`jtframe_tms32010`). Built from **Kyukyoku Tiger bootleg schematics** — i.e. the exact board
family you have. Files saved under research/mister/. Key things it reveals that MAME leaves
vague:

1. **mainlatch (07800d) bits 0/1 — MAME marks these "????":**
   `mlatch[0] = DSP reset (active-high-n)`, `mlatch[1] = sound Z80 reset (n)`. So the 68000
   holds both the DSP and the sound CPU in reset at boot and releases them via this latch.
   (Confirmed: `dsp_rstn=mlatch[0]`, `snd_rstn=mlatch[1]`, `video_on=mlatch[7]`,
   `int_enable=mlatch[2]`, `flip=mlatch[3]`, `bg_bank=mlatch[4]`, `fg_bank=mlatch[5]`,
   `dsp_on=mlatch[6]`.)

2. **DSP↔68000 on Twin Cobra/KT is 68000 BUS ARBITRATION (BR/BGACK), not a wholesale CPU
   halt.** The DSP runs freely; port 3 bit15 asserts the 68000 bus request; BIO reads low
   until the bus is granted; the DSP only touches shared/sprite/palette RAM while it holds
   the bus. (Wardner/Flying Shark use the simpler "halt the host" model instead — the same
   RTL module switches behaviour on a TWINCOBR parameter.) MAME models both as a host halt,
   which is functionally equivalent but not how the bootleg board actually wires it.

3. Confirms: 28 MHz → 14/7/3.5 MHz; address decode by A[18:16] (3=work/DSP RAM, 4=obj,
   5=pal); VBLANK IRQ is an edge on VS gated by mlatch[2]; shared Z80 RAM is 0x800 bytes,
   low byte only, accessed via Z80 bus request.

### Black-screen implication (this board)
`video_on` is `mlatch[7]` — the screen stays black until the 68000 runs far enough to set
it. A dead black screen most likely means the **68000 is not executing** (bad main ROM/RAM,
no reset/clock, address/data line fault, or it is stuck waiting on DTACK), rather than a
video-only fault. A diagnostic ROM that lights the screen and drives the layers from the
68000 alone (DSP and Z80 kept in reset via mlatch[0]/[1]) is the right first bring-up step.

## Boot sequence (traced from the real twincobr ROM in MAME 0.289 debugger)
Reset vector: SP=`$00032000` (top of work RAM), PC=`$00020194`. Early flow:
```
02019C  move #$2000,SR        ; supervisor, IRQs masked
0201A0  lea  $32000.l,A7      ; stack = top of WORK RAM (so dead work RAM crashes the CPU)
0201A6  bra  $25B40
025B40  lea  $7800C.l,A0      ; FIRST hardware access: the LS259 control latch
025B46  lea  $25E02.l,A1      ; table of 8 control words
025B4C  moveq #7,D0
025B4E  move.w (A1)+,(A0) / dbra   ; writes 8 words to $7800C/D (IRQ off, banks, DSP off, screen)
025B5C… walking-bit MARCH TEST of WORK RAM $30000-$33FFF (9 passes)
025BAC  bne $25C7A            ; <-- RAM-ERROR exit on any miscompare
```
Full ordered boot (disassembled from ROM via MAME `dasm`):
```
1  $2019C  SR=$2000, A7(SP)=$32000
2  $25B40  write 8 control words (table @$25E02) to the $7800D LS259 latch:
            0D=inhibit DSP INT, 00/01=pulse DSP reset, 02/03=pulse sound-Z80 reset,
            06=flip off, 08=bg bank0, 0A=fg bank0.  (Q7 video-on and Q2 IRQ left 0 -> screen OFF)
3  $25B64  WORK RAM  march test  $30000-$33FFF   (error exit $25C7A)
4  $25BD4  SPRITE RAM test       $40000
5  $25C0A  PALETTE RAM test      $50000
6  $25C18  move.w #$0E,$7800C    -> screen OFF while clearing
7  $25C2C/$25C44/$25C5C  clear TEXT/FG/BG VRAM (offset regs $70004/$74004/$72004 + data ports $7E000/4/2)
8  $25CD2  move.w #$07,$7800C    -> flip latch
9  $25D30  write chars to text VRAM ($70004 offset + $7E000 data) = FIRST on-screen output
           (ROM-checksum reads and the "RAM OK / ROM OK / SOUND" text happen here; CRTC program + screen-on follow)
```
So **three RAM regions (work $30000, sprite $40000, palette $50000) are all tested before the
display is ever turned on**, and the stack lives in work RAM. Any of those failing, or the CPU
not running / not fetching ROM / no DTACK, leaves the board black with no check screen. A
GFX/sound fault is reported as on-screen text, so it cannot be the cause of a *fully black* screen.
**Key point for a black-screen board:** the game tests work RAM and runs its control-latch
setup *before* any video init, so a work-RAM fault (or the CPU not running at all) branches to
the error handler / hangs **before the screen exists** → black, never the check screen. A bad
GFX/sound ROM is caught *after* the display is up, so it would show "NG" text instead. Thus a
fully black screen points at: CPU not executing (clock/reset), can't fetch program ROM at
$20194, **work RAM $30000-$33FFF (also the stack at $32000)**, or DTACK/bus — not the later
subsystems. First scope test: watch for the 8 writes to the `$7800D` latch just after reset.

## Prior art: arcade-museum "Sky Shark TP-007 Black Screen" thread (9 pages, 2022-2024)
Repair thread for a Sky Shark (TP-007, sister board) with a black screen; posters Arcadenut +
tendril traced the self-test in MAME and ended up patching the ROM into a working diagnostic.
Directly cross-validates our Twin Cobra trace and teaches the key design lesson.

Their traced self-test order (TP-007): init `$7800C` latch -> init scroll regs -> flip check ->
**Main RAM test `$30000-$33FFF`** -> **init HD6845 CRTC** -> **Sprite RAM `$40000`** ->
**Palette RAM `$50000`** -> Text/FG/BG RAM -> sound-CPU handshake -> start game. (Note: this
answers where the CRTC is programmed - right after the main-RAM test.) Same family, same order
as our Twin Cobra trace; "no video output until it passes the self test."

**The fatal flaw in the stock self-test (THE key lesson for our ROM):** on ANY failed test the
code jumps to a failure path (`$A1EE` on their set) that **does not turn the screen on and skips
telling the Z80 to start** (`AA` -> `$7A002`); the 68000 then deadlocks waiting for `FF` at
`$7A001`. Result = permanent black screen with zero diagnostic output. Arcadenut: "If it fails
for any reason, it doesn't appear to turn the screen on at all." They fixed it by patching the
ROM to turn the screen on first and handle failures visibly - i.e. they hand-built a diagnostic.
=> OUR generic ROM must: **turn the screen ON before any test, never deadlock (time out on Z80/
DSP handshakes), and report every failure visibly + on the heartbeat pin.** We already specced
this; the thread confirms it is the decisive requirement.

Other useful points:
- tendril: "if the 68000 is running ROM, RAM is probably good" (a RAM/ROM fault usually halts
  it); "a failure on the microcontroller leaves the 68000 running but stuck waiting for a
  response (with video turned off)"; and on his board "the 68000 stalls waiting on DTACK - so it
  may not be bad memory, just bad glue logic."
- Faults they actually found: a 74LS08 (`M19`) holding video disabled; the self-test deadlock
  bug; and broken palette-RAM buffer traces (`L25` palette RAM via `M27`/`K14` LS245s) - several
  trace breaks were self-inflicted under sockets during rework. **The C-01 TMS320C10 DSP was
  never proven faulty** - worth remembering before blaming the DSP on our board.
- Screen bit confirmed: `$7800C` write `0F` = display ON, `0E` = OFF (matches our latch map).
- Shared `$7A000` RAM can't be fully tested by 16-bit tools (8-bit on the Z80 side) - relevant
  to our stage 8.
- Tools they used: Fluke 9010 68000 POD, scope, MAME debugger, HxD for ROM patching.
Thread: https://forums.arcade-museum.com/threads/toaplan-romstar-sky-shark-tp-007-black-screen.506905/

## Sources
- MAME mainline driver: src/mame/toaplan/twincobr.cpp, twincobr.h, twincobr_m.cpp,
  twincobr_v.cpp, toaplan_dsp.cpp/.h, toaplan_scu.cpp, wardner.cpp (downloaded under research/mame/)
- Toaplan.org hardware & Twin Cobra pages (TP-011, memory map)
- Internet Archive: Romstar "Twin Cobra Installation Manual" (JAMMA wiring + DIPs, not a schematic) — research/manuals/
- MiSTer: Toaplan "Twin Cobra platform" FPGA core (Coin-Op Collection, Patreon) uses
  Raki's open-source IKA32010 TMS320C10; referenced TP-007 (Flying Shark) schematics.
  Public GitHub cores (va7deo/zerowing etc.) are Toaplan **V1** hardware — different board.
