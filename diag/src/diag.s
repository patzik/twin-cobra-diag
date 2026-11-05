/* ============================================================================
 * Twin Cobra / Kyuukyoku Tiger diagnostic ROM   (main, evolving image)
 *
 * Target : Motorola 68000 on Toaplan TP-011, bootleg + original.
 * Burns to the main-CPU program ROM pair (a 27512 each):
 *     even bytes (D8-D15) -> b30_01.7j      odd bytes (D0-D7) -> b30_03.7h
 * Assembler: m68k-elf-as (GNU binutils), Motorola mnemonics, % register prefix.
 *
 * STAGE 0 (implicit): any heartbeat-pin toggle proves the 68000 reached ROM.
 * STAGE 2 (video): program the HD6845 CRTC and turn the screen on FIRST
 *     (opposite of the stock ROM, which blanks the screen during self-test and
 *     deadlocks on failure). The whole palette is flooded with one colour, so
 *     the entire screen shows that colour regardless of tile/VRAM contents:
 *         BLUE  = video up, tests running
 *         GREEN = all tests so far passed
 *         RED   = a test failed
 * STAGE 1 (work RAM): test the 16 KiB work/DSP-shared RAM at $30000-$33FFF
 *     (also the stack), register-only so it reports even with dead RAM. The
 *     result recolours the screen (green/red) AND sets the heartbeat pin.
 *
 * On failure these registers are frozen for inspection (MAME, or a later
 * on-screen stage): A5 = failing address, D5 = expected word, D6 = read back.
 * ============================================================================ */

.ifndef WORK_BASE                       /* overridable for fault-injection tests */
    .equ WORK_BASE,  0x030000
.endif
    .equ WORK_SIZE,  0x4000
    .equ WORK_WORDS, (WORK_SIZE/2)

    .equ PAL_BASE,   0x050000
    .equ PAL_WORDS,  1792               /* xBGR_555, 1792 entries */
    .equ CRTC_BASE,  0x060000           /* addr reg $60001, data reg $60003 */

    .equ LATCH,     0x07800d
    .equ L_IRQOFF,  0x04
    .equ L_DSPRST0, 0x00
    .equ L_SNDRST0, 0x02
    .equ L_FLIP0,   0x06
    .equ L_FLIP1,   0x07
    .equ L_BGBANK0, 0x08
    .equ L_FGBANK0, 0x0a
    .equ L_DSPINT0, 0x0d
    .equ L_SCRNOFF, 0x0e
    .equ L_SCRNON,  0x0f

    /* xBGR_555 colours: word = x BBBBB GGGGG RRRRR */
    .equ C_BLUE,    0x7c00
    .equ C_GREEN,   0x03e0
    .equ C_RED,     0x001f

    .equ HB_SLOW,   0x00030000
    .equ HB_FAST,   0x00006000

/* register-only busy delay (uses D7) */
.macro DELAY n
    move.l  #\n,%d7
1:  subq.l  #1,%d7
    bne.s   1b
.endm

/* flood the whole palette with one colour (uses A1,D0) */
.macro FLOOD color
    lea     PAL_BASE,%a1
    move.w  #PAL_WORDS-1,%d0
2:  move.w  #\color,(%a1)+
    dbra    %d0,2b
.endm

/* fill work RAM with pattern \p then verify; jump to f_pat on mismatch */
.macro PATTEST p
    lea     WORK_BASE,%a1
    move.w  #WORK_WORDS-1,%d0
    move.w  #\p,%d2
10: move.w  %d2,(%a1)+
    dbra    %d0,10b
    lea     WORK_BASE,%a1
    move.w  #WORK_WORDS-1,%d0
11: move.w  (%a1)+,%d1
    cmp.w   %d2,%d1
    jne     f_pat
    dbra    %d0,11b
.endm

    .text

/* ---- 68000 reset vector ---- */
    .org 0x0000
    .long   0x00032000                  /* initial SSP */
    .long   _start                      /* initial PC  */

/* ---- entry ---- */
    .org 0x0400
    .global _start
_start:
    move.w  #0x2700,%sr
    lea     LATCH,%a0
    move.b  #L_IRQOFF,(%a0)
    move.b  #L_DSPRST0,(%a0)            /* DSP held in reset   */
    move.b  #L_DSPINT0,(%a0)
    move.b  #L_SNDRST0,(%a0)            /* sound Z80 in reset  */
    move.b  #L_BGBANK0,(%a0)
    move.b  #L_FGBANK0,(%a0)
    move.b  #L_SCRNOFF,(%a0)            /* video off while we set up */

/* ===================== STAGE 2: bring the video up ===================== */
/* Program HD6845 registers R0-R9 (values measured from the game ROM). */
    moveq   #9,%d0                      /* 10 registers */
    moveq   #0,%d1                      /* register index */
    lea     crtc_tab,%a1
    lea     CRTC_BASE,%a2
crtc_init:
    move.w  %d1,(%a2)                   /* select register -> $60001 */
    addq.w  #1,%d1
    move.w  (%a1)+,2(%a2)               /* value          -> $60003 */
    dbra    %d0,crtc_init

    FLOOD   C_BLUE                      /* whole palette blue */
    move.b  #L_SCRNON,(%a0)             /* screen ON -> solid blue = "video up" */

/* ===================== STAGE 1: work RAM test ===================== */
/* 1a. data-bus walking-ones at the base word */
    lea     WORK_BASE,%a1
    move.w  #0x0001,%d2
dbus:
    move.w  %d2,(%a1)
    move.w  (%a1),%d0
    cmp.w   %d2,%d0
    jne     f_dbus
    add.w   %d2,%d2
    bne.s   dbus
    move.w  #0x0000,(%a1)
    move.w  (%a1),%d0
    jne     f_zero
    move.w  #0xffff,%d2
    move.w  %d2,(%a1)
    move.w  (%a1),%d0
    cmp.w   %d2,%d0
    jne     f_dbus

/* 1b. address/data uniqueness */
    lea     WORK_BASE,%a1
    move.w  #WORK_WORDS-1,%d0
    moveq   #0,%d3
fillu:
    move.w  %d3,(%a1)+
    addq.w  #1,%d3
    dbra    %d0,fillu
    lea     WORK_BASE,%a1
    move.w  #WORK_WORDS-1,%d0
    moveq   #0,%d3
veru:
    move.w  (%a1)+,%d2
    cmp.w   %d3,%d2
    jne     f_addr
    addq.w  #1,%d3
    dbra    %d0,veru

/* 1c. march patterns */
    PATTEST 0xaaaa
    PATTEST 0x5555

/* ---- PASS ---- */
    FLOOD   C_GREEN                     /* whole screen green */
    jra     pass_hold

/* ---- failure capture then RED ---- */
f_dbus:
    movea.l %a1,%a5
    move.w  %d2,%d5
    move.w  %d0,%d6
    jra     ram_fail
f_zero:
    movea.l %a1,%a5
    moveq   #0,%d5
    move.w  %d0,%d6
    jra     ram_fail
f_addr:
    movea.l %a1,%a5
    subq.l  #2,%a5
    move.w  %d3,%d5
    move.w  %d2,%d6
    jra     ram_fail
f_pat:
    movea.l %a1,%a5
    subq.l  #2,%a5
    move.w  %d2,%d5
    move.w  %d1,%d6
    jra     ram_fail

ram_fail:
    FLOOD   C_RED                       /* whole screen red */
    jra     fail_hold

/* ===================== liveness indicators ===================== */
/* PASS: slow steady square wave on the heartbeat pin (green screen) */
pass_hold:
    move.b  #L_FLIP1,(%a0)
    DELAY   HB_SLOW
    move.b  #L_FLIP0,(%a0)
    DELAY   HB_SLOW
    jra     pass_hold

/* FAIL: bursts of 4 fast pulses, long gap (red screen) */
fail_hold:
    moveq   #3,%d4
fp:
    move.b  #L_FLIP1,(%a0)
    DELAY   HB_FAST
    move.b  #L_FLIP0,(%a0)
    DELAY   HB_FAST
    dbra    %d4,fp
    DELAY   HB_SLOW
    jra     fail_hold

/* ---- data ---- */
    .even
crtc_tab:
    .short  0x00de, 0x00a0, 0x00b0, 0x008f, 0x0022
    .short  0x0006, 0x001e, 0x001f, 0x0000, 0x0007
