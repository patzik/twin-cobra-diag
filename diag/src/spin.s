/* ============================================================================
 * Twin Cobra diagnostic — SPIN ROM (reads only, no writes, no peripherals)
 *
 * The 68000 does nothing but read ROM in a tight loop forever: no writes, no
 * RAM, no I/O, no DSP, no latch. It isolates the read path from the write path.
 *
 *   Continuous activity on /AS and the data pins  -> the CPU, its 7 MHz clock,
 *       reset, ROM fetch and read-side /DTACK all work. If the full diagnostic
 *       then dies, it dies on its first WRITE -> suspect /DTACK generation for
 *       the writable/I-O regions (glue logic), not the CPU.
 *   Only a brief burst then dead -> the problem is on the read side: clock,
 *       /RESET, ROM decode, or /DTACK for ROM. Scope CLK/ /RESET / /HALT / /AS.
 *
 * Burns to the same sockets: even -> b30_01.7j, odd -> b30_03.7h (27512).
 * ============================================================================ */

    .text
    .org 0x0000
    .long   0x00032000                  /* initial SSP (unused) */
    .long   _start                      /* initial PC  */

    .org 0x0400
    .global _start
_start:
    move.w  #0x2700,%sr                 /* mask interrupts; no stack/RAM used */
spin:
    lea     0x000000,%a0                /* read ROM from the bottom... */
    move.w  #0x7fff,%d1                 /* ...32 KiB of it */
1:  tst.b   (%a0)+                      /* a pure read cycle (no write) */
    dbra    %d1,1b
    bra.s   spin                        /* forever */
