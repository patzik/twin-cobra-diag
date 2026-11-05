/* ============================================================================
 * Twin Cobra / Kyuukyoku Tiger diagnostic ROM   (main, evolving image)
 *
 * Target : Motorola 68000 on Toaplan TP-011, bootleg + original.
 * Burns to the main-CPU program ROM pair (27512 each):
 *     even bytes (D8-D15) -> b30_01.7j      odd bytes (D0-D7) -> b30_03.7h
 * Assembler: m68k-elf-as (GNU binutils), Motorola mnemonics, % register prefix.
 *
 * Stages present:
 *   0 (implicit) heartbeat pin proves the 68000 reached ROM.
 *   2 video: HD6845 CRTC init, palette set up, screen ON first (unlike the
 *     stock ROM which blanks the screen and deadlocks on failure).
 *   2b text: white 8x8 text on black, using the game's own font in the char
 *     ROM (digits 0-9 at tiles 0x00-0x09, A-Z at 0x0A-0x23, blank 0x2D).
 *   1 work RAM test $30000-$33FFF (register-only; also the stack). Result is
 *     printed on screen, and shown on the heartbeat pin.
 *
 * Text report, white on black:
 *     TWIN COBRA DIAG
 *     WORK RAM  PASS            (or)   WORK RAM  FAIL
 *                                      A <addr> E <exp> G <got>
 * ============================================================================ */

.ifndef WORK_BASE
    .equ WORK_BASE,  0x030000
.endif
    .equ WORK_SIZE,  0x4000
    .equ WORK_WORDS, (WORK_SIZE/2)

    .equ PAL_BASE,   0x050000
    .equ PAL_WORDS,  1792
    .equ PAL_TXT0,   (PAL_BASE + 1536*2)   /* text colour-set 0, pen 0 */
    .equ CRTC_BASE,  0x060000
    .equ TXSCROLL,   0x070000              /* y at +0, x at +2 */
    .equ TXOFFS,     0x070004              /* text VRAM offset register */
    .equ TXDATA,     0x07e000              /* text VRAM data port */

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

    .equ C_BLACK,   0x0000
    .equ C_WHITE,   0x7fff

    .equ HB_SLOW,   0x00030000
    .equ HB_FAST,   0x00006000

    /* Text layout. The monitor is vertical (ROT270): the game writes text DOWN
     * the framebuffer columns, which reads left-to-right and upright on screen.
     * So one character advances the tilemap offset by a full row (64); each new
     * display line is the adjacent column (offset - 1). */
    .equ ROW,       64
    .equ CHARSTEP,  64                     /* next char = next framebuffer row */
    .equ ORG,       0x0066                 /* first char: row 1, col 38 (top-left-ish) */
    .equ L_HEAD,    (ORG - 0)
    .equ L_RES,     (ORG - 2)
    .equ L_DET,     (ORG - 3)
    .equ OFF_ADDR,  (L_DET + 2*CHARSTEP)
    .equ OFF_EXP,   (L_DET + 11*CHARSTEP)
    .equ OFF_GOT,   (L_DET + 18*CHARSTEP)

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

/* print 0-terminated ASCII string at tilemap offset (stack-free).
 * A3=TXOFFS, A4=TXDATA must be preloaded. Uses A2,A6,D0,D4. */
.macro PRINTSTR strlbl, off
    lea     \strlbl,%a2
    lea     asc2tile,%a6
    move.w  #\off,%d4
3:  moveq   #0,%d0
    move.b  (%a2)+,%d0
    beq.s   4f
    move.b  (%a6,%d0.w),%d0
    move.w  %d4,(%a3)
    move.w  %d0,(%a4)
    add.w   #CHARSTEP,%d4
    bra.s   3b
4:
.endm

/* print the low <ndig> nibbles of a register as hex (nibble value == tile).
 * A3=TXOFFS, A4=TXDATA preloaded. Uses D1,D2,D3,D4,D7. Leaves valreg intact. */
.macro PRINTHEX valreg, ndig, off
    move.w  #\off,%d4
    moveq   #\ndig,%d3
5:  subq.w  #1,%d3
    move.l  \valreg,%d1
    move.w  %d3,%d7
    lsl.w   #2,%d7
    lsr.l   %d7,%d1
    and.w   #0x000f,%d1
    move.w  %d4,(%a3)
    move.w  %d1,(%a4)
    add.w   #CHARSTEP,%d4
    tst.w   %d3
    bne.s   5b
.endm

/* fill work RAM with pattern then verify; jump to f_pat on mismatch */
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
    .long   0x00032000
    .long   _start

/* ---- entry ---- */
    .org 0x0400
    .global _start
_start:
    move.w  #0x2700,%sr
    lea     LATCH,%a0
    move.b  #L_IRQOFF,(%a0)
    move.b  #L_DSPRST0,(%a0)
    move.b  #L_DSPINT0,(%a0)
    move.b  #L_SNDRST0,(%a0)
    move.b  #L_BGBANK0,(%a0)
    move.b  #L_FGBANK0,(%a0)
    move.b  #L_SCRNOFF,(%a0)

/* ---- CRTC (R0-R9, values measured from the game ROM) ---- */
    moveq   #9,%d0
    moveq   #0,%d1
    lea     crtc_tab,%a1
    lea     CRTC_BASE,%a2
crtc_init:
    move.w  %d1,(%a2)
    addq.w  #1,%d1
    move.w  (%a1)+,2(%a2)
    dbra    %d0,crtc_init

/* ---- palette: everything black, then text set-0 pens 1-7 white ---- */
    FLOOD   C_BLACK
    lea     PAL_TXT0+2,%a1              /* pen 1 of text set 0 */
    moveq   #6,%d0
pwhite:
    move.w  #C_WHITE,(%a1)+
    dbra    %d0,pwhite

/* ---- text ports, clear the text layer to blanks ---- */
    lea     TXOFFS,%a3
    lea     TXDATA,%a4
    move.w  #0x07ff,%d4
clrtx:
    move.w  %d4,(%a3)
    move.w  #0x002d,(%a4)
    dbra    %d4,clrtx

/* ---- text scroll to the game's centre values ---- */
    lea     TXSCROLL,%a1
    move.w  #0x01ca,(%a1)               /* y */
    move.w  #0x00e2,2(%a1)              /* x */

    move.b  #L_SCRNON,(%a0)             /* screen on (black) */

    PRINTSTR hdr, L_HEAD

/* ===================== STAGE 1: work RAM test ===================== */
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

    PATTEST 0xaaaa
    PATTEST 0x5555

/* ---- PASS ---- */
    PRINTSTR okmsg, L_RES
    jra     pass_hold

/* ---- failure: capture (A5 addr, D5 exp, D6 got), print, hold ---- */
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
    PRINTSTR failmsg, L_RES
    PRINTSTR detlbl,  L_DET
    PRINTHEX %a5, 6, OFF_ADDR            /* A <addr> */
    PRINTHEX %d5, 4, OFF_EXP             /* E <exp>  */
    PRINTHEX %d6, 4, OFF_GOT             /* G <got>  */
    jra     fail_hold

/* ===================== liveness on the heartbeat pin ===================== */
pass_hold:
    move.b  #L_FLIP1,(%a0)
    DELAY   HB_SLOW
    move.b  #L_FLIP0,(%a0)
    DELAY   HB_SLOW
    jra     pass_hold

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

/* ============================ data ============================ */
    .even
crtc_tab:
    .short  0x00de, 0x00a0, 0x00b0, 0x008f, 0x0022
    .short  0x0006, 0x001e, 0x001f, 0x0000, 0x0007

hdr:     .asciz "TWIN COBRA DIAG"
okmsg:   .asciz "WORK RAM  PASS"
failmsg: .asciz "WORK RAM  FAIL"
detlbl:  .asciz "A        E      G"

    .even
asc2tile:
    .byte 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d
    .byte 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d
    .byte 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d
    .byte 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d
    .byte 0x2d, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18
    .byte 0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f, 0x20, 0x21, 0x22, 0x23, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d
    .byte 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d
    .byte 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d
