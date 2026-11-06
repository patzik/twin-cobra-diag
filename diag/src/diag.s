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
    .equ L_HB0,     0x04                /* heartbeat LOW : Q2=0 (VBLANK IRQ enable off) */
    .equ L_HB1,     0x05                /* heartbeat HIGH: Q2=1 (masked by SR, invisible) */
    .equ L_BGBANK0, 0x08
    .equ L_FGBANK0, 0x0a
    .equ L_DSP_OFF, 0x0c                /* Q6=0: DSP DISABLED. The game sets Q6=1 to
                                         * enable the DSP, which hands it the 68000 bus;
                                         * a dead/absent DSP then stalls the 68000. The
                                         * diagnostic does not use the DSP, so keep it off. */
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
    .equ L_ROMH,    (ORG - 5)
    .equ L_ROML,    (ORG - 6)
    .equ L_SPR,     (ORG - 8)
    .equ L_SPRD,    (ORG - 9)
    .equ L_PAL,     (ORG - 11)
    .equ L_PALD,    (ORG - 12)
    .equ L_END,     (ORG - 14)

    /* Stage 3 targets (overridable with --defsym for fault-injection tests) */
.ifndef PROG2
    .equ PROG2,     0x020000               /* the 27256 program pair (game entry $20194) */
.endif
.ifndef SPR_BASE
    .equ SPR_BASE,  0x040000               /* sprite RAM, 4 KiB */
.endif
.ifndef PALT_BASE
    .equ PALT_BASE, PAL_BASE               /* palette RAM under test */
.endif
    .equ SPR_WORDS, 0x0800
    .equ PAL_TMASK, 0x7fff                 /* xBGR_555: bit 15 unused, not compared */
    .equ FLAG,      0x033ffe               /* work-RAM word: nonzero = a stage-3 test failed */

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

/* print a 0-terminated string whose address is in a register. Uses A2,A6,D0,D4. */
.macro PRINTSTRR reg, off
    movea.l \reg,%a2
    lea     asc2tile,%a6
    move.w  #\off,%d4
7:  moveq   #0,%d0
    move.b  (%a2)+,%d0
    beq.s   8f
    move.b  (%a6,%d0.w),%d0
    move.w  %d4,(%a3)
    move.w  %d0,(%a4)
    add.w   #CHARSTEP,%d4
    bra.s   7b
8:
.endm

/* failure detail line: A <addr> E <expected> G <got>, from A5/D5/D6 */
.macro PRINTDET line
    PRINTSTR detlbl, \line
    PRINTHEX %a5, 6, (\line + 2*CHARSTEP)
    PRINTHEX %d5, 4, (\line + 11*CHARSTEP)
    PRINTHEX %d6, 4, (\line + 18*CHARSTEP)
.endm

/* restore the text palette: everything black, text set-0 pens 1-7 white */
.macro TEXTPAL
    FLOOD   C_BLACK
    lea     PAL_TXT0+2,%a1
    moveq   #6,%d0
9:  move.w  #C_WHITE,(%a1)+
    dbra    %d0,9b
.endm

/* CRC32 (standard/zlib, same as MAME's ROM CRCs) of <nbytes> bytes read with
 * a stride of 2 starting at <start>, i.e. one byte lane = one ROM chip.
 * Result in D1. Uses A1,A2,D0-D3. */
.macro CRC32S start, nbytes
    lea     \start,%a1
    lea     crc32tab,%a2
    moveq   #-1,%d1
    move.w  #\nbytes-1,%d0
6:  moveq   #0,%d2
    move.b  (%a1),%d2
    addq.l  #2,%a1
    eor.b   %d1,%d2
    lsl.w   #2,%d2
    lsr.l   #8,%d1
    move.l  (%a2,%d2.w),%d3
    eor.l   %d3,%d1
    dbra    %d0,6b
    not.l   %d1
.endm

/* one ROM chip line: "<label> <crc32> <set name | UNKNOWN>" */
.macro ROMCHK start, line, lbl
    PRINTSTR \lbl, \line
    CRC32S  \start, 0x8000
    move.l  %d1,%d5
    PRINTHEX %d5, 8, (\line + 7*CHARSTEP)
    lea     crcknown,%a1
rk\@:
    move.l  (%a1)+,%d1
    beq.s   ru\@
    move.l  (%a1)+,%d2
    cmp.l   %d5,%d1
    bne.s   rk\@
    movea.l %d2,%a1
    bra.s   rp\@
ru\@:
    lea     s_unknown,%a1
    lea     FLAG,%a2
    move.w  #1,(%a2)
rp\@:
    PRINTSTRR %a1, (\line + 16*CHARSTEP)
.endm

/* generic register-only RAM test: data-bus walk at the base word, address
 * uniqueness, then AAAA and 5555 marches. Only bits in <mask> are compared.
 * On mismatch: A5 = address, D5 = expected, D6 = got, then jump to <fail>.
 * Uses A1,A2,D0-D3. */
.macro RAMTEST base, nwords, mask, fail
    lea     \base,%a2
    move.w  #1,%d2
ta\@:
    move.w  %d2,(%a2)
    move.w  (%a2),%d1
    move.w  %d2,%d3
    and.w   #\mask,%d1
    and.w   #\mask,%d3
    cmp.w   %d3,%d1
    jne     tc\@
    add.w   %d2,%d2
    bne.s   ta\@
    lea     \base,%a1
    move.w  #\nwords-1,%d0
    moveq   #0,%d2
tb\@:
    move.w  %d2,(%a1)+
    addq.w  #1,%d2
    dbra    %d0,tb\@
    lea     \base,%a1
    move.w  #\nwords-1,%d0
    moveq   #0,%d2
td\@:
    move.w  (%a1)+,%d1
    move.w  %d2,%d3
    and.w   #\mask,%d1
    and.w   #\mask,%d3
    cmp.w   %d3,%d1
    jne     tx\@
    addq.w  #1,%d2
    dbra    %d0,td\@
    move.w  #0xaaaa,%d2
    lea     \base,%a1
    move.w  #\nwords-1,%d0
te\@:
    move.w  %d2,(%a1)+
    dbra    %d0,te\@
    lea     \base,%a1
    move.w  #\nwords-1,%d0
tf\@:
    move.w  (%a1)+,%d1
    move.w  %d2,%d3
    and.w   #\mask,%d1
    and.w   #\mask,%d3
    cmp.w   %d3,%d1
    jne     tx\@
    dbra    %d0,tf\@
    move.w  #0x5555,%d2
    lea     \base,%a1
    move.w  #\nwords-1,%d0
tg\@:
    move.w  %d2,(%a1)+
    dbra    %d0,tg\@
    lea     \base,%a1
    move.w  #\nwords-1,%d0
th\@:
    move.w  (%a1)+,%d1
    move.w  %d2,%d3
    and.w   #\mask,%d1
    and.w   #\mask,%d3
    cmp.w   %d3,%d1
    jne     tx\@
    dbra    %d0,th\@
    jra     tz\@
tx\@:
    lea     -2(%a1),%a2
tc\@:
    movea.l %a2,%a5
    move.w  %d3,%d5
    move.w  %d1,%d6
    jra     \fail
tz\@:
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
    move.b  #L_DSP_OFF,(%a0)            /* keep the DSP off the bus */
    move.b  #L_SNDRST0,(%a0)
    move.b  #L_BGBANK0,(%a0)
    move.b  #L_FGBANK0,(%a0)
    move.b  #L_FLIP0,(%a0)              /* flip screen off */
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
    jra     stage3

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

/* ====== STAGE 3: program ROM CRCs, sprite RAM, palette RAM ======
 * Runs only after work RAM passed, so a flag word in work RAM is safe. Every
 * test runs and reports even if an earlier one failed. */
stage3:
    lea     FLAG,%a1
    clr.w   (%a1)

/* 3a. CRC32 of each 27256 program chip at $020000. HI = even bytes (D8-D15),
 *     LO = odd bytes (D0-D7). The game starts executing in these chips. */
    ROMCHK  PROG2,     L_ROMH, romhi
    ROMCHK  (PROG2+1), L_ROML, romlo

/* 3b. sprite RAM $40000-$40FFF */
    RAMTEST SPR_BASE, SPR_WORDS, 0xffff, spr_fail
    PRINTSTR sprok, L_SPR
    jra     spr_done
spr_fail:
    PRINTSTR sprbad, L_SPR
    PRINTDET L_SPRD
    lea     FLAG,%a1
    move.w  #1,(%a1)
spr_done:

/* 3c. palette RAM $50000-$50DFF. This overwrites the palette, so the text
 *     colours are restored straight after. */
    RAMTEST PALT_BASE, PAL_WORDS, PAL_TMASK, pal_fail
    TEXTPAL
    PRINTSTR palok, L_PAL
    jra     pal_done
pal_fail:
    TEXTPAL
    PRINTSTR palbad, L_PAL
    PRINTDET L_PALD
    lea     FLAG,%a1
    move.w  #1,(%a1)
pal_done:

/* summary line + heartbeat pattern */
    lea     FLAG,%a1
    tst.w   (%a1)
    jne     some_fail
    PRINTSTR allok, L_END
    jra     pass_hold
some_fail:
    PRINTSTR somebad, L_END
    jra     fail_hold

/* ===================== liveness on the heartbeat pin ===================== */
pass_hold:
    move.b  #L_HB1,(%a0)
    DELAY   HB_SLOW
    move.b  #L_HB0,(%a0)
    DELAY   HB_SLOW
    jra     pass_hold

fail_hold:
    moveq   #3,%d4
fp:
    move.b  #L_HB1,(%a0)
    DELAY   HB_FAST
    move.b  #L_HB0,(%a0)
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

/* ---- stage 3 strings and tables ---- */
romhi:     .asciz "ROM HI"
romlo:     .asciz "ROM LO"
sprok:     .asciz "SPRITE RAM  PASS"
sprbad:    .asciz "SPRITE RAM  FAIL"
palok:     .asciz "PALETTE RAM PASS"
palbad:    .asciz "PALETTE RAM FAIL"
allok:     .asciz "ALL TESTS PASS"
somebad:   .asciz "SOME TESTS FAILED"
s_unknown: .asciz "UNKNOWN"
t_tcw:     .asciz "TC WORLD"
t_tcu:     .asciz "TC USA"
t_kt:      .asciz "K TIGER"
t_kta:     .asciz "K TIGER ALT"

/* known CRC32s of the 27256 program pair at $020000 (from MAME twincobr.cpp):
 * crc, pointer to set name. Terminated by 0. */
    .even
crcknown:
    .long 0x3a646618, t_tcw     /* twincobr  b30_26_ii.8j (HI) */
    .long 0xd7d1e317, t_tcw     /* twincobr  b30_27_ii.8h (LO) */
    .long 0xbdd00ba4, t_tcu     /* twincobru b30_26_i.8j  (HI) */
    .long 0xed600907, t_tcu     /* twincobru b30_27_i.8h  (LO) */
    .long 0x321e2be6, t_kt      /* ktiger    b30_02.8j    (HI) */
    .long 0xc3f960ff, t_kt      /* ktiger    b30_04.8h    (LO) */
    .long 0x1d63e9c4, t_kta     /* ktigera   b30_02.8j    (HI) */
    .long 0x03957a30, t_kta     /* ktigera   b30_04.8h    (LO) */
    .long 0

/* CRC32 lookup table, polynomial 0xEDB88320 (reflected, zlib) */
    .even
crc32tab:
    .long 0x00000000, 0x77073096, 0xee0e612c, 0x990951ba
    .long 0x076dc419, 0x706af48f, 0xe963a535, 0x9e6495a3
    .long 0x0edb8832, 0x79dcb8a4, 0xe0d5e91e, 0x97d2d988
    .long 0x09b64c2b, 0x7eb17cbd, 0xe7b82d07, 0x90bf1d91
    .long 0x1db71064, 0x6ab020f2, 0xf3b97148, 0x84be41de
    .long 0x1adad47d, 0x6ddde4eb, 0xf4d4b551, 0x83d385c7
    .long 0x136c9856, 0x646ba8c0, 0xfd62f97a, 0x8a65c9ec
    .long 0x14015c4f, 0x63066cd9, 0xfa0f3d63, 0x8d080df5
    .long 0x3b6e20c8, 0x4c69105e, 0xd56041e4, 0xa2677172
    .long 0x3c03e4d1, 0x4b04d447, 0xd20d85fd, 0xa50ab56b
    .long 0x35b5a8fa, 0x42b2986c, 0xdbbbc9d6, 0xacbcf940
    .long 0x32d86ce3, 0x45df5c75, 0xdcd60dcf, 0xabd13d59
    .long 0x26d930ac, 0x51de003a, 0xc8d75180, 0xbfd06116
    .long 0x21b4f4b5, 0x56b3c423, 0xcfba9599, 0xb8bda50f
    .long 0x2802b89e, 0x5f058808, 0xc60cd9b2, 0xb10be924
    .long 0x2f6f7c87, 0x58684c11, 0xc1611dab, 0xb6662d3d
    .long 0x76dc4190, 0x01db7106, 0x98d220bc, 0xefd5102a
    .long 0x71b18589, 0x06b6b51f, 0x9fbfe4a5, 0xe8b8d433
    .long 0x7807c9a2, 0x0f00f934, 0x9609a88e, 0xe10e9818
    .long 0x7f6a0dbb, 0x086d3d2d, 0x91646c97, 0xe6635c01
    .long 0x6b6b51f4, 0x1c6c6162, 0x856530d8, 0xf262004e
    .long 0x6c0695ed, 0x1b01a57b, 0x8208f4c1, 0xf50fc457
    .long 0x65b0d9c6, 0x12b7e950, 0x8bbeb8ea, 0xfcb9887c
    .long 0x62dd1ddf, 0x15da2d49, 0x8cd37cf3, 0xfbd44c65
    .long 0x4db26158, 0x3ab551ce, 0xa3bc0074, 0xd4bb30e2
    .long 0x4adfa541, 0x3dd895d7, 0xa4d1c46d, 0xd3d6f4fb
    .long 0x4369e96a, 0x346ed9fc, 0xad678846, 0xda60b8d0
    .long 0x44042d73, 0x33031de5, 0xaa0a4c5f, 0xdd0d7cc9
    .long 0x5005713c, 0x270241aa, 0xbe0b1010, 0xc90c2086
    .long 0x5768b525, 0x206f85b3, 0xb966d409, 0xce61e49f
    .long 0x5edef90e, 0x29d9c998, 0xb0d09822, 0xc7d7a8b4
    .long 0x59b33d17, 0x2eb40d81, 0xb7bd5c3b, 0xc0ba6cad
    .long 0xedb88320, 0x9abfb3b6, 0x03b6e20c, 0x74b1d29a
    .long 0xead54739, 0x9dd277af, 0x04db2615, 0x73dc1683
    .long 0xe3630b12, 0x94643b84, 0x0d6d6a3e, 0x7a6a5aa8
    .long 0xe40ecf0b, 0x9309ff9d, 0x0a00ae27, 0x7d079eb1
    .long 0xf00f9344, 0x8708a3d2, 0x1e01f268, 0x6906c2fe
    .long 0xf762575d, 0x806567cb, 0x196c3671, 0x6e6b06e7
    .long 0xfed41b76, 0x89d32be0, 0x10da7a5a, 0x67dd4acc
    .long 0xf9b9df6f, 0x8ebeeff9, 0x17b7be43, 0x60b08ed5
    .long 0xd6d6a3e8, 0xa1d1937e, 0x38d8c2c4, 0x4fdff252
    .long 0xd1bb67f1, 0xa6bc5767, 0x3fb506dd, 0x48b2364b
    .long 0xd80d2bda, 0xaf0a1b4c, 0x36034af6, 0x41047a60
    .long 0xdf60efc3, 0xa867df55, 0x316e8eef, 0x4669be79
    .long 0xcb61b38c, 0xbc66831a, 0x256fd2a0, 0x5268e236
    .long 0xcc0c7795, 0xbb0b4703, 0x220216b9, 0x5505262f
    .long 0xc5ba3bbe, 0xb2bd0b28, 0x2bb45a92, 0x5cb36a04
    .long 0xc2d7ffa7, 0xb5d0cf31, 0x2cd99e8b, 0x5bdeae1d
    .long 0x9b64c2b0, 0xec63f226, 0x756aa39c, 0x026d930a
    .long 0x9c0906a9, 0xeb0e363f, 0x72076785, 0x05005713
    .long 0x95bf4a82, 0xe2b87a14, 0x7bb12bae, 0x0cb61b38
    .long 0x92d28e9b, 0xe5d5be0d, 0x7cdcefb7, 0x0bdbdf21
    .long 0x86d3d2d4, 0xf1d4e242, 0x68ddb3f8, 0x1fda836e
    .long 0x81be16cd, 0xf6b9265b, 0x6fb077e1, 0x18b74777
    .long 0x88085ae6, 0xff0f6a70, 0x66063bca, 0x11010b5c
    .long 0x8f659eff, 0xf862ae69, 0x616bffd3, 0x166ccf45
    .long 0xa00ae278, 0xd70dd2ee, 0x4e048354, 0x3903b3c2
    .long 0xa7672661, 0xd06016f7, 0x4969474d, 0x3e6e77db
    .long 0xaed16a4a, 0xd9d65adc, 0x40df0b66, 0x37d83bf0
    .long 0xa9bcae53, 0xdebb9ec5, 0x47b2cf7f, 0x30b5ffe9
    .long 0xbdbdf21c, 0xcabac28a, 0x53b39330, 0x24b4a3a6
    .long 0xbad03605, 0xcdd70693, 0x54de5729, 0x23d967bf
    .long 0xb3667a2e, 0xc4614ab8, 0x5d681b02, 0x2a6f2b94
    .long 0xb40bbe37, 0xc30c8ea1, 0x5a05df1b, 0x2d02ef8d
