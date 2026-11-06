# Twin Cobra / Kyuukyoku Tiger diagnostic ROM

A generic power-on diagnostic ROM for the Toaplan **TP-011** PCB family
(Twin Cobra / Kyukyoku Tiger), bootleg and original, to help repair dead
boards — written for a real black-screen repair, and meant to be shared.

Runs on the main 68000 in place of the program ROM pair, and reports from the
earliest possible point (a scope/probe heartbeat pin) through full-screen
colour status, so it tells you something even on a board too dead to show the
game's own self-test.

## Layout
- [`diag/`](diag/README.md) — the diagnostic: source, Makefile, burn-ready images, build/burn docs.
- [`SPEC.md`](SPEC.md) — design and scope (what each stage does, feedback channels, roadmap).
- [`research/FINDINGS.md`](research/FINDINGS.md) — hardware notes: memory map, boot sequence,
  DSP, latch bits, CRTC values, cross-referenced to MAME / MiSTer / the bootleg schematic.

## Build & burn
See [`diag/README.md`](diag/README.md). In short: `make` (needs `m68k-elf` binutils + python3)
produces two 27512 images — `twincobr_diag_7j.bin` (even, socket `b30_01.7j`) and
`twincobr_diag_7h.bin` (odd, socket `b30_03.7h`). Prebuilt copies are in `diag/build/`.
On bootlegs, use the two **27512** program sockets (the pair holding the reset vector),
not the 27256 program sockets — see `diag/README.md`.

## Status so far
- Stage 0: RAM-less CPU-alive heartbeat on the `$7800D` latch (LS259 Q2, pin 6).
- Stage 2: HD6845 CRTC init + screen on + full-screen colour status.
- Stage 1: work/DSP-shared RAM test `$30000-$33FFF`.
- Stage 3: CRC32 of the two 27256 program ROMs (named against known MAME sets), sprite RAM, palette RAM.

On-screen: white text on black — `TWIN COBRA DIAG`, then `WORK RAM  PASS`, or
`WORK RAM  FAIL` with the failing address / expected / read-back in hex.
No toggle / no picture = CPU not running (clock, reset, ROM fetch, DTACK).
Verified on a real bootleg board (work RAM passes).

## Not included (on purpose)
Original arcade ROMs and third-party sources (MAME drivers, the manual scan, the
jotego GPL schematic/RTL) are git-ignored — this repo is only our own work. For
MAME testing, supply your own `twincobr` ROM set; the diagnostic images replace
`b30_01.7j` / `b30_03.7h`.
