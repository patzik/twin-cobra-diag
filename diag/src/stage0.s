/* ============================================================================
 * Twin Cobra / Kyuukyoku Tiger diagnostic ROM
 * STAGE 0 — RAM-less CPU-alive heartbeat
 *
 * Target : Motorola 68000 on Toaplan TP-011 (Twin Cobra / Kyukyoku Tiger),
 *          bootleg + original.
 * Burns to: the main-CPU program ROM pair, a 27512 each:
 *              even bytes (D8-D15) -> b30_01.7j
 *              odd  bytes (D0-D7)  -> b30_03.7h
 * Assembler: m68k-elf-as (GNU binutils), Motorola mnemonics, % register prefix.
 *
 * Design rules carried from research (see ../SPEC.md and ../research/FINDINGS.md):
 *   - Stage 0 must run with NO working RAM: no stack use, no JSR/BSR, no
 *     memory variables. Registers only.
 *   - Never deadlock. (Nothing here waits on the Z80 or DSP.)
 *   - The stock game ROM blanks the screen and freezes on any self-test
 *     failure; we instead prove life on a scope/logic-probe pin from the very
 *     first instruction, independent of RAM/video.
 *
 * What it does: sets a known, safe hardware state (DSP + sound Z80 held in
 * reset, IRQ off, screen off) and then toggles ONE LS259 latch output — Q2,
 * the VBLANK-IRQ enable (LS259 pin 6), masked in the CPU so it has no visible
 * effect — as a steady square wave. A pulse on that pin = "the 68000
 * is alive and executing from ROM," which is exactly the thing a black screen
 * cannot tell you.
 * ============================================================================ */

    .equ WORK_TOP,  0x032000     /* top of work RAM = initial SSP (unused here) */
    .equ LATCH,     0x07800d     /* mainlatch LS259, byte access, odd address   */

    /* LS259 control-byte encoding: bits[3:1] select Q output, bit0 = value.
     * (Latch-bit meanings confirmed from the MiSTer ktiger core RTL.)          */
    .equ L_IRQOFF,  0x04         /* Q2=0  68000 IRQ (VBLANK) disabled           */
    .equ L_DSPRST0, 0x00         /* Q0=0  hold TMS320C10 DSP in reset           */
    .equ L_SNDRST0, 0x02         /* Q1=0  hold sound Z80 in reset               */
    .equ L_FLIP0,   0x06         /* Q3=0  flip screen off                       */
    .equ L_FLIP1,   0x07         /* Q3=1  flip screen on                        */
    .equ L_HB0,     0x04                /* heartbeat LOW : Q2=0 (VBLANK IRQ enable off) */
    .equ L_HB1,     0x05                /* heartbeat HIGH: Q2=1 (masked by SR, invisible) */
    .equ L_BGBANK0, 0x08         /* Q4=0  background RAM bank 0                  */
    .equ L_FGBANK0, 0x0a         /* Q5=0  foreground ROM bank 0                 */
    .equ L_DSP_OFF, 0x0c         /* Q6=0  DSP DISABLED (do not hand it the 68K bus) */
    .equ L_SCRNOFF, 0x0e         /* Q7=0  video off                             */
    .equ L_SCRNON,  0x0f         /* Q7=1  video on                              */

    .equ HB_DELAY,  0x00020000   /* heartbeat half-period (loop iterations)     */

    .text

/* ---- 68000 reset vector (first 8 bytes of the ROM) ---- */
    .org 0x0000
    .long   WORK_TOP             /* 000: initial supervisor stack pointer */
    .long   _start               /* 004: initial program counter          */

/* Exception vector table (0x008-0x3FF) is left as zeros for the stage-0
 * skeleton; a real exception handler goes in here in a later stage. */

/* ---- entry ---- */
    .org 0x0400
    .global _start
_start:
    move.w  #0x2700,%sr          /* supervisor mode, all interrupts masked */
    lea     LATCH,%a0            /* A0 -> control latch (register-indirect writes) */

    /* Force a known, safe state — no RAM touched. */
    move.b  #L_IRQOFF,(%a0)      /* IRQ off           */
    move.b  #L_DSPRST0,(%a0)     /* DSP in reset      */
    move.b  #L_DSP_OFF,(%a0)     /* keep the DSP off the bus */
    move.b  #L_SNDRST0,(%a0)     /* sound Z80 in reset*/
    move.b  #L_BGBANK0,(%a0)     /* bg bank 0         */
    move.b  #L_FGBANK0,(%a0)     /* fg bank 0         */
    move.b  #L_FLIP0,(%a0)              /* flip screen off */
    move.b  #L_SCRNOFF,(%a0)     /* video off         */

    /* ---- heartbeat: steady square wave on latch Q2 (LS259 pin 6) ---- */
hb_loop:
    move.b  #L_HB1,(%a0)       /* pin HIGH */
    move.l  #HB_DELAY,%d0
1:  subq.l  #1,%d0
    bne.s   1b
    move.b  #L_HB0,(%a0)       /* pin LOW  */
    move.l  #HB_DELAY,%d0
2:  subq.l  #1,%d0
    bne.s   2b
    bra.s   hb_loop
