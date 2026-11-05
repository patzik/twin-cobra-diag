# Twin Cobra / Kyuukyoku Tiger diagnostic ROM — specification

A generic, shareable power-on diagnostic for the Toaplan "Twin Cobra" PCB family,
intended to help repair both **bootleg** and **original** boards on a **test bench**
(JAMMA supergun + monitor; no cabinet, so coin-counter solenoid clicks are NOT a usable cue).

Board family reference: Toaplan TP-011 (Twin Cobra / Kyukyoku Tiger), Taito B30.
Hardware details and sources are in `research/FINDINGS.md`.

## Why one ROM can cover bootleg + original
From the 68000's side the memory map is identical across the bootleg and the original (and
largely across the 68000 family incl. Flying/Sky Shark TP-007). Differences are:
- implementation (bootleg uses glue logic instead of the GXL-01 / M70H005 customs; DSP program
  in external PROMs with **A0/A1 swapped** instead of the custom internal-ROM MCU),
- contents (different DSP / GFX / program ROM checksums),
- clock (7 MHz vs 10 MHz export).

The diagnostic therefore **reports measured values** (checksums, read-backs) instead of
hard-coding one board's "correct" answer, and selects the DSP-enable path at runtime.

## Scope — phase 1 (this version)
- Target: **Twin Cobra / Kyukyoku Tiger (TP-011)**, bootleg + original.
- Runs on the **68000**, replacing the main program ROMs `b30_01.7j` / `b30_03.7h`
  (a 27512 pair). Must boot from reset assuming nothing else works.
- Code structured so **TP-007 (Flying/Sky Shark)** can be added later (different ROM map,
  DSP-enable via the coin-latch at `07800b` instead of the main-latch at `07800d`).
- Assembler: **vasm** (Motorola syntax) + linker; reproducible build; prebuilt binaries shipped.

## Feedback channels (phase 1) — layered so there is always *some* signal
1. **Scope / logic-probe heartbeat (works with zero RAM).** The 68000 toggles one harmless
   LS259 latch output (candidate: DSP-INT or flip at `07800d`; final pin chosen against a
   schematic test point) in a **stage-encoded blink pattern**. Steady pulses = CPU alive and
   executing from ROM; the pattern/rate encodes the current stage. **Latched**: if the CPU
   hangs at stage N, the last pattern persists, so a probe on one pin shows where it died even
   with a black screen.
2. **Full-screen colour status (once the video chain is partly alive).** Flood the screen with
   a solid colour via the background layer (needs palette RAM + bg VRAM + bg tile ROM + CRTC)
   as a coarse code (e.g. blue = reached video, red = RAM fail, green = all pass) — visible
   before any readable text.
3. **On-screen text pass/fail (once the text layer works).** Full human-readable results.

Audible beep/error codes are **deferred to phase 2** (see below).

## Test stages (phase 1), each depends on less than the one before
| # | Test | Region / notes |
|---|------|----------------|
| 0 | CPU-alive heartbeat + main-ROM sum | RAM-less; heartbeat pin only |
| 1 | Work/shared RAM march | `030000-033fff` |
| 2 | Palette RAM + CRTC init → colour screen | `050000`, HD6845 at `060001/3` |
| 3 | Text VRAM + char ROM → text output | via `07e000`/`070004` ports |
| 4 | Sprite RAM, bg/fg VRAM | `040000`, `07e002/4` |
| 5 | Main program ROM checksums | compare to built-in table (TC/KT/variants) |
| 6 | GFX ROM + PROM checksums | chars/fg/bg/sprites + 82s129/82s123 |
| 7 | Inputs live display | DIPs, joysticks, coin/service at `078000-078009` |
| 8 | Shared Z80 RAM test | `07a000`, Z80 held in reset via main-latch bit 1 |
| 9 | DSP self-test + comms + checksum | enable via main-latch bit 6; run self-test cmd, report ROM checksum, verify two-way comms |

Reset-state note: at entry the diagnostic holds the **DSP (main-latch bit 0)** and the
**sound Z80 (main-latch bit 1)** in reset, and only releases them at their respective stages.

## Interaction
Auto-run the full suite in a loop on boot (with latched status), **plus** a simple
joystick/DIP menu to re-run or stress individual tests (e.g. RAM burn-in).

## Deliverables (for sharing / reuse)
- Assembler source + reproducible build instructions.
- Prebuilt binaries sized to the real EPROMs (27512 pair for `7j`/`7h`).
- README: socketing/jumpers, how to read the heartbeat pin and colour codes, probe points
  cross-referenced to the ktiger bootleg schematic (`research/schematics/`).
- Checksum table for known ROM sets.

## Phase 2 (later)
- **Companion Z80 ROM** (replaces `b30_05.4f`): audible beep/error codes via YM3812, plus full
  Z80 ROM/RAM and YM3812/sound-path tests, commanded by the 68000 over shared RAM.
- **TP-007 Flying Shark / Sky Shark** support (ROM map + coin-latch DSP-enable path).
- Extended menu: stress/burn-in modes, CRTC timing display, etc.

## Open items to resolve during build
- Final heartbeat pin + an easily reachable test point on both bootleg and original layouts.
- Exact CRTC register values for a stable raster on a bench monitor.
- Known-good checksum table entries (seed from MAME CRCs in `research/FINDINGS.md`).
