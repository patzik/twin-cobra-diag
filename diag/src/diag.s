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

    .include "video.inc"

    .equ HB_SLOW,   0x00030000
    .equ HB_FAST,   0x00006000

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
    .equ L_PAL,     (ORG - 10)
    .equ L_PALD,    (ORG - 11)
    .equ L_TXV,     (ORG - 12)             /* stage 4: video RAM */
    .equ L_FGV,     (ORG - 13)
    .equ L_BGV,     (ORG - 14)
    .equ L_VRD,     (ORG - 15)             /* detail of the last failing video RAM */
    .equ L_SHR,     (ORG - 17)             /* stage 5: sound CPU */
    .equ L_SHRD,    (ORG - 18)
    .equ L_SND,     (ORG - 19)
    .equ L_SDAT,    (ORG - 20)
    .equ L_IRQ,     (ORG - 22)             /* stage 6: interrupts */
    .equ L_IRQD,    (ORG - 23)
    .equ L_DSP,     (ORG - 25)             /* stage 7: DSP */
    .equ L_DSPD,    (ORG - 26)
    .equ L_END,     (ORG - 28)

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
    .equ VBDEAD,    0x033ffc               /* work-RAM word: nonzero = no VBLANK signal seen */

    /* VBLANK input: $78009 bit 7, active high on TP-011 (MAME twincobr.cpp).
     * Real hardware shares sprite RAM with the sprite generator and palette
     * RAM with the colour output; the CPU only gets clean access at the times
     * the game uses. From the game's own RAM test (twincobr $25c0a-$25dd2):
     *   - sprite RAM: wait for VBLANK to END, then do one short burst;
     *   - palette RAM: tested with the screen turned OFF (latch Q7 = 0).
     * MAME does not model this contention, so the tests pass there either way. */
    .equ VBL_IN,    0x078009
    .equ VB_TMO,    0x00008000             /* ~0.2 s: give up waiting = no VBLANK */
    .equ L_VBL,     (ORG - 7)
    .equ SPR_CHUNK, 256                    /* words per VBLANK-synced burst */
    .equ SPR_NCHUNK,(SPR_WORDS/SPR_CHUNK)

    /* loop-test menu (troubleshooting feature) */
    .equ P1IN,      0x078004               /* P1 inputs, active high: */
                                           /* bit0 up, 1 down, 2 left, 3 right, 4 B1, 5 B2 */
    .equ MENU_DLY,  0x00002000             /* ~20 ms input poll / debounce delay */
    .equ L_HINT,    (ORG - 30)
    .equ L_M0,      (ORG - 32)
    .equ L_M1,      (ORG - 33)
    .equ L_M2,      (ORG - 34)
    .equ L_M3,      (ORG - 36)
    .equ L_M4,      (ORG - 37)

    /* stage 6: interrupt counters (work RAM) */
    .equ IRQON,     0x033fe0               /* nonzero: VBLANK IRQ enabled on purpose */
    .equ IRQC4,     0x033fe2               /* level-4 (VBLANK) interrupts counted */
    .equ IRQCO,     0x033fe4               /* any other level, or spurious */
    .equ IRQ_OFFFR, 300                    /* frames with the IRQ off (~5.5 s: catches
                                            * a gate that only sometimes leaks) */
    .equ IRQ_FR,    50                     /* frames with it on */
    .equ EXCNO,     0x033fe6               /* unexpected exception number */
    .equ SETPTR,    0x033fc0               /* name of the set ROM HI matched, 0 = none */
    .equ SETPTR2,   0x033fc4               /*   (ROM LO, unused) */

    /* stage 4: text / foreground / background video RAM, reached through an
     * offset register + data port (no auto-increment), as the game tests them */
    .equ FGOFFS,    0x074004
    .equ FGDATA,    0x07e004
    .equ BGOFFS,    0x072004
    .equ BGDATA,    0x07e002
    .equ TX_WORDS,  2048
    .equ FG_WORDS,  4096
    .equ BG_WORDS,  4096                   /* bank 0 (latch Q4 = 0), as the game */
    .equ TXSAVE,    0x030000               /* work-RAM copy of the text layer */
    .equ VRBITS,    0x033ff0               /* bit 0/1/2 = text/fg/bg video RAM failed */
    .equ VRA,       0x033ff2               /* detail of the last failure: offset (long) */
    .equ VRE,       0x033ff6               /*   expected */
    .equ VRG,       0x033ff8               /*   got */

    /* stage 5: sound CPU. Shared RAM is 2 KiB, 8-bit on the Z80 side
     * ($8000-$87FF), the low byte of each 68000 word at $7A000-$7AFFF.
     * Protocol (from the game, $25c6e/$25f3c, and its Z80 code at $2F7B):
     *   Z80 out of reset writes FF to its $8000 (68000 $7A001), 00 to $8001;
     *   68000 writes AA to $7A002 (Z80 $8001) = start; the Z80 then sums its
     *   whole ROM and, if the sum is not 0, writes 00 to $8000 and stops;
     *   68000 writes a command F0+n to $7A001; the Z80 copies its ROM
     *   $4000+n*$400 (1 KiB) to its $8200 (68000 $7A401, every 2nd byte)
     *   and writes FF to $8000 when done. The game asks for F0-FB. */
.ifndef SHR_BASE
    .equ SHR_BASE,  0x07a000
.endif
    .equ SHR_WORDS, 2048
    .equ L_SNDRUN,  0x03                   /* latch Q1 = 1: release the Z80 */
    .equ Z_TMO,     0x00080000             /* ~3.5 s per wait */
    .equ Z_SUMDLY,  0x00070000             /* ~1.2 s for the Z80's own ROM sum (~0.4 s) */
    .equ Z_CRC_TC,  0x80ecff66             /* CRC32 of b30_05_ii.4f $4000-$6FFF */





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
.macro ROMCHK start, line, lbl, store
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
    move.l  %d2,\store                  /* remember the set (its name) */
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
.macro RAMTEST base, nwords, mask, fail, p1=0xaaaa, p2=0x5555
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
    move.w  %d2,%d3                     /* index ^ (index >> 8): still unique, and */
    lsr.w   #8,%d3                      /* the low byte alone also changes with    */
    eor.w   %d2,%d3                     /* the high address bits (8-bit RAMs)      */
    move.w  %d3,(%a1)+
    addq.w  #1,%d2
    dbra    %d0,tb\@
    lea     \base,%a1
    move.w  #\nwords-1,%d0
    moveq   #0,%d2
td\@:
    move.w  (%a1)+,%d1
    move.w  %d2,%d3
    lsr.w   #8,%d3
    eor.w   %d2,%d3
    and.w   #\mask,%d1
    and.w   #\mask,%d3
    cmp.w   %d3,%d1
    jne     tx\@
    addq.w  #1,%d2
    dbra    %d0,td\@
    move.w  #\p1,%d2
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
    move.w  #\p2,%d2
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

/* wait for the END of VBLANK (bit 7 high, then low), like the game does before
 * touching sprite RAM. Register-only. D7 = 0 afterwards if it timed out. */
.macro VBWAIT
    move.l  #VB_TMO,%d7
vh\@:
    btst    #7,VBL_IN
    jne     vl\@
    subq.l  #1,%d7
    jne     vh\@
    jra     vz\@
vl\@:
    btst    #7,VBL_IN
    jeq     vz\@
    subq.l  #1,%d7
    jne     vl\@
vz\@:
.endm

/* VBWAIT, skipped once VBLANK is known dead (flag in work RAM). Uses D7. */
.macro VBSYNC
    tst.w   VBDEAD
    jne     vs\@
    VBWAIT
vs\@:
.endm

/* write D2 to all of sprite RAM in VBLANK-synced bursts; inc=1 adds 1 per
 * word (address-uniqueness pattern). Uses A1,D0,D2,D4,D7. */
.macro SPRWR inc
    lea     SPR_BASE,%a1
    moveq   #SPR_NCHUNK-1,%d4
sw\@:
    VBSYNC
    move.w  #SPR_CHUNK-1,%d0
sx\@:
    move.w  %d2,(%a1)+
    .if \inc
    addq.w  #1,%d2
    .endif
    dbra    %d0,sx\@
    dbra    %d4,sw\@
.endm

/* verify sprite RAM against D2 (same pattern rules as SPRWR); on mismatch
 * jump to spr_mis with A1 one word past the bad address, D1 = got. */
.macro SPRRD inc
    lea     SPR_BASE,%a1
    moveq   #SPR_NCHUNK-1,%d4
sr\@:
    VBSYNC
    move.w  #SPR_CHUNK-1,%d0
sy\@:
    move.w  (%a1)+,%d1
    cmp.w   %d2,%d1
    jne     spr_mis
    .if \inc
    addq.w  #1,%d2
    .endif
    dbra    %d0,sy\@
    dbra    %d4,sr\@
.endm

/* video RAM test through an offset register + data port: every word its own
 * index (address lines), then AAAA, then 5555 - the game's own patterns.
 * On mismatch: A5 = offset, D5 = expected, D6 = got, jump to <fail>.
 * Uses A1,A2,D0-D3. */
.macro VRTEST oreg, dport, nwords, fail
    lea     \oreg,%a1
    lea     \dport,%a2
    move.w  #\nwords-1,%d0
vu\@:
    move.w  %d0,(%a1)
    move.w  %d0,(%a2)
    dbra    %d0,vu\@
    move.w  #\nwords-1,%d0
vv\@:
    move.w  %d0,(%a1)
    move.w  (%a2),%d1
    cmp.w   %d0,%d1
    jne     vxu\@
    dbra    %d0,vv\@
    move.w  #0xaaaa,%d2
vp\@:
    move.w  #\nwords-1,%d0
vw\@:
    move.w  %d0,(%a1)
    move.w  %d2,(%a2)
    dbra    %d0,vw\@
    move.w  #\nwords-1,%d0
vr\@:
    move.w  %d0,(%a1)
    move.w  (%a2),%d1
    cmp.w   %d2,%d1
    jne     vx\@
    dbra    %d0,vr\@
    cmp.w   #0x5555,%d2
    jeq     vz\@
    move.w  #0x5555,%d2
    jra     vp\@
vxu\@:
    move.w  %d0,%d2
vx\@:
    moveq   #0,%d3
    move.w  %d0,%d3
    movea.l %d3,%a5
    move.w  %d2,%d5
    move.w  %d1,%d6
    jra     \fail
vz\@:
.endm

/* remember a video RAM failure (bit n) and its detail in work RAM */
.macro SAVEDET n
    bset    #\n,VRBITS+1
    move.l  %a5,VRA
    move.w  %d5,VRE
    move.w  %d6,VRG
.endm

/* "<label>  PASS|FAIL" for video RAM n. Uses A2,A6,D0,D4. */
.macro PRINTVR line, lbl, n
    PRINTSTR \lbl, \line
    btst    #\n,VRBITS+1
    jne     pf\@
    PRINTSTR s_pass, (\line + 12*CHARSTEP)
    jra     pz\@
pf\@:
    PRINTSTR s_fail, (\line + 12*CHARSTEP)
pz\@:
.endm

/* wait (with timeout) for the Z80 to write FF to its $8000 = 68000 $7A001.
 * Jumps to <tmo> on timeout. Uses D7. */
.macro ZWAIT tmo
    move.l  #Z_TMO,%d7
zw\@:
    cmpi.b  #0xff,SHR_BASE+1
    jeq     zk\@
    subq.l  #1,%d7
    jne     zw\@
    jra     \tmo
zk\@:
.endm

/* wait <nfr> frames (VBLANK-timed; ~1 s of delay without a VBLANK input).
 * Uses D3,D7. */
.macro IRQFRAMES nfr
    tst.w   VBDEAD
    jne     if_dly\@
    move.w  #\nfr-1,%d3
if_lp\@:
    VBWAIT
    dbra    %d3,if_lp\@
    jra     if_end\@
if_dly\@:
    DELAY   0x00070000
if_end\@:
.endm

/* jump to <target> if P1 button 1 is held. Uses A2,D0. */
.macro CHKB1 target
    lea     P1IN,%a2
    move.w  (%a2),%d0
    btst    #4,%d0
    jne     \target
.endm

/* HB_SLOW worth of delay, watching P1 button 1 all the while (16 checks).
 * Uses A2,D0,D3,D7. */
.macro DLYCHK target
    moveq   #15,%d3
dc\@:
    DELAY   (HB_SLOW/16)
    CHKB1   \target
    dbra    %d3,dc\@
.endm

/* wait until P1 up/down/B1/B2 are all released. Uses A2,D0,D7. */
.macro WAITREL
wr\@:
    DELAY   MENU_DLY
    lea     P1IN,%a2
    move.w  (%a2),%d0
    and.w   #0x0033,%d0
    jne     wr\@
.endm

    .text

/* ---- 68000 reset vector ---- */
    .org 0x0000
    .long   0x00032000
    .long   _start

/* ---- all other exception vectors: show which one and where, instead of
 * running off into the weeds with a black screen ---- */
    .org 0x0008
    .long   exc_2
    .long   exc_3
    .long   exc_4
    .long   exc_5
    .long   exc_6
    .long   exc_7
    .long   exc_8
    .long   exc_9
    .long   exc_10
    .long   exc_11
    .long   exc_12
    .long   exc_13
    .long   exc_14
    .long   exc_15
    .long   exc_16
    .long   exc_17
    .long   exc_18
    .long   exc_19
    .long   exc_20
    .long   exc_21
    .long   exc_22
    .long   exc_23

/* ---- interrupt vectors (stage 6). Until stage 6 the CPU masks all
 * interrupts, so these are only reached by the interrupt test or by a
 * board that raises an interrupt it shouldn't. ---- */
    .org 0x0060
    .long   irq_other                   /* 24 spurious */
    .long   irq_other                   /* 25 level 1 */
    .long   irq_other                   /* 26 level 2 */
    .long   irq_other                   /* 27 level 3 */
    .long   irq_vbl                     /* 28 level 4 = VBLANK */
    .long   irq_other                   /* 29 level 5 */
    .long   irq_other                   /* 30 level 6 */
    .long   irq_other                   /* 31 level 7 */
    .long   exc_32
    .long   exc_33
    .long   exc_34
    .long   exc_35
    .long   exc_36
    .long   exc_37
    .long   exc_38
    .long   exc_39
    .long   exc_40
    .long   exc_41
    .long   exc_42
    .long   exc_43
    .long   exc_44
    .long   exc_45
    .long   exc_46
    .long   exc_47
    .long   exc_48
    .long   exc_49
    .long   exc_50
    .long   exc_51
    .long   exc_52
    .long   exc_53
    .long   exc_54
    .long   exc_55
    .long   exc_56
    .long   exc_57
    .long   exc_58
    .long   exc_59
    .long   exc_60
    .long   exc_61
    .long   exc_62
    .long   exc_63

/* ---- entry ---- */
    .org 0x0400
    .global _start
_start:
    move.w  #0x2700,%sr
    suba.l  %a1,%a1
    move.l  %a1,%usp                    /* no main-menu marker yet */
    lea     LATCH,%a0
    move.b  #L_IRQOFF,(%a0)
    move.b  #L_DSPRST0,(%a0)
    move.b  #L_DSP_OFF,(%a0)            /* keep the DSP off the bus */
    move.b  #L_SNDRST0,(%a0)
    move.b  #L_BGBANK0,(%a0)
    move.b  #L_FGBANK0,(%a0)
    move.b  #L_FLIP0,(%a0)              /* flip screen off */
    move.b  #L_SCRNOFF,(%a0)

    VIDINIT

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
    jra     wram_hold

/* ====== STAGE 3: program ROM CRCs, sprite RAM, palette RAM ======
 * Runs only after work RAM passed, so a flag word in work RAM is safe. Every
 * test runs and reports even if an earlier one failed. */
stage3:
    lea     FLAG,%a1
    clr.w   (%a1)
    lea     VBDEAD,%a1
    clr.w   (%a1)

/* VBLANK present? The sprite test syncs to it; without it, say so and run
 * unsynced rather than hang. */
    VBWAIT
    tst.l   %d7
    jne     vb_ok
    lea     VBDEAD,%a1
    move.w  #1,(%a1)
    lea     FLAG,%a1
    move.w  #1,(%a1)
    PRINTSTR novbl, L_VBL
vb_ok:

/* 3a. CRC32 of each 27256 program chip at $020000. HI = even bytes (D8-D15),
 *     LO = odd bytes (D0-D7). The game starts executing in these chips. */
    clr.l   SETPTR
    ROMCHK  PROG2,     L_ROMH, romhi, SETPTR
    ROMCHK  (PROG2+1), L_ROML, romlo, SETPTR2

/* 3b. sprite RAM $40000-$40FFF, in short bursts right after VBLANK ends (as the
 *     game does): data-bus walk, address uniqueness, AAAA, 5555. */
    VBSYNC
    lea     SPR_BASE,%a1
    move.w  #1,%d2
spr_walk:
    move.w  %d2,(%a1)
    move.w  (%a1),%d1
    cmp.w   %d2,%d1
    jne     spr_wmis
    add.w   %d2,%d2
    bne.s   spr_walk
    moveq   #0,%d2
    SPRWR   1
    moveq   #0,%d2
    SPRRD   1
    move.w  #0xaaaa,%d2
    SPRWR   0
    SPRRD   0
    move.w  #0x5555,%d2
    SPRWR   0
    SPRRD   0
    PRINTSTR sprok, L_SPR
    jra     spr_done
spr_wmis:
    lea     2(%a1),%a1
spr_mis:
    lea     -2(%a1),%a5
    move.w  %d2,%d5
    move.w  %d1,%d6
spr_fail:
    PRINTSTR sprbad, L_SPR
    PRINTDET L_SPRD
    lea     FLAG,%a1
    move.w  #1,(%a1)
spr_done:
/* leave sprite RAM all zero = every sprite priority 0 = not drawn, so test
 * patterns never show on screen */
    moveq   #0,%d2
    SPRWR   0

/* 3c. palette RAM $50000-$50DFF, with the screen OFF (as the game does). This
 *     overwrites the palette, so the text colours are restored straight after. */
    move.b  #L_SCRNOFF,(%a0)
    RAMTEST PALT_BASE, PAL_WORDS, PAL_TMASK, pal_fail
    TEXTPAL
    move.b  #L_SCRNON,(%a0)
    PRINTSTR palok, L_PAL
    jra     pal_done
pal_fail:
    TEXTPAL
    move.b  #L_SCRNON,(%a0)
    PRINTSTR palbad, L_PAL
    PRINTDET L_PALD
    lea     FLAG,%a1
    move.w  #1,(%a1)
pal_done:

/* ====== STAGE 4: text / foreground / background video RAM ======
 * With the screen off, as the game does. The text test overwrites the text
 * layer, so it is saved to work RAM first and put back afterwards (if the
 * text RAM reads back wrong, that copy is garbled too - the result line,
 * printed after the restore, still tells you). */
    move.b  #L_SCRNOFF,(%a0)
    lea     TXSAVE,%a1
    move.w  #0,%d0
txsv:
    move.w  %d0,(%a3)
    move.w  (%a4),(%a1)+
    addq.w  #1,%d0
    cmp.w   #TX_WORDS,%d0
    jne     txsv
    clr.w   VRBITS
    VRTEST  TXOFFS, TXDATA, TX_WORDS, tx_fail
    jra     tx_done
tx_fail:
    SAVEDET 0
tx_done:
    lea     TXSAVE,%a1
    move.w  #0,%d0
txrs:
    move.w  %d0,(%a3)
    move.w  (%a1)+,(%a4)
    addq.w  #1,%d0
    cmp.w   #TX_WORDS,%d0
    jne     txrs
    VRTEST  FGOFFS, FGDATA, FG_WORDS, fg_fail
    jra     fg_done
fg_fail:
    SAVEDET 1
fg_done:
    VRTEST  BGOFFS, BGDATA, BG_WORDS, bg_fail
    jra     bg_done
bg_fail:
    SAVEDET 2
bg_done:
/* BG video RAM has a second bank (latch Q4): the port then reaches it */
    move.b  #(L_BGBANK0 + 1),(%a0)
    VRTEST  BGOFFS, BGDATA, BG_WORDS, bg1_fail
    jra     bg1_done
bg1_fail:
    adda.w  #0x1000,%a5                 /* report bank 1 as offsets 1000-1FFF */
    SAVEDET 2
bg1_done:
    move.b  #L_BGBANK0,(%a0)
    move.b  #L_SCRNON,(%a0)
    PRINTVR L_TXV, s_txv, 0
    PRINTVR L_FGV, s_fgv, 1
    PRINTVR L_BGV, s_bgv, 2
    tst.w   VRBITS
    jeq     vr_done
    lea     FLAG,%a1
    move.w  #1,(%a1)
    movea.l VRA,%a5
    move.w  VRE,%d5
    move.w  VRG,%d6
    PRINTDET L_VRD
vr_done:

/* ====== STAGE 5: sound CPU (Z80) ======
 * The 68000 reaches shared RAM only by taking the Z80's bus: an access to
 * $7Axxx drives Z80 /BUSRQ and waits for /BUSACK (bootleg schematic: K12
 * 74LS138 O5 -> Z80 pin 25; Z80 pin 23 -> K4 74LS74 -> K5 74LS32 -> DTACK).
 * A Z80 in reset, without clock, or dead never answers, and the 68000 then
 * waits forever - no software timeout can catch that. So the Z80 is released
 * first, and a line on screen says what a hang here means. */
    PRINTSTR shrwait, L_SHR
    move.b  #L_SNDRUN,(%a0)             /* release the Z80 */
    DELAY   0x2000                      /* let it reach its start-up code */
/* 5a. its first code writes FF to $8000 (68000 $7A001) and 00 to $8001, then
 *     waits for AA at $8001. D4 = 1 if FF never came. */
    moveq   #0,%d4
    ZWAIT   z_noff
    jra     z_ff
z_noff:
    moveq   #1,%d4
z_ff:
    move.w  %d4,-(%sp)
/* 5b. shared RAM (8-bit: low byte only), while the Z80 waits for AA. The
 *     march patterns avoid AA so it is not started by accident. */
    RAMTEST SHR_BASE, SHR_WORDS, 0x00ff, shr_fail, 0xa5a5, 0x5a5a
    PRINTSTR shrok, L_SHR
    jra     shr_done
shr_fail:
    PRINTSTR shrbad, L_SHR
    PRINTDET L_SHRD
    lea     FLAG,%a1
    move.w  #1,(%a1)
shr_done:
    move.w  (%sp)+,%d4
    tst.w   %d4
    jne     snd_dead
/* 5c. the Z80 is running and waiting: it must sum its ROM after AA, then
 *     answer the game's 12 ROM-block commands. The blocks are CRC'd, which
 *     checks the sound ROM through the Z80. */
    lea     SHR_BASE,%a1
    move.w  #0x00ff,(%a1)               /* $8000 = FF: idle, no command */
/* AA = start. The Z80 then adds up its whole ROM (~0.4 s); a non-zero sum
 * makes it write 00 to $8000 and stop for good (the game then hangs). */
    lea     SHR_BASE,%a1
    move.w  #0x00aa,2(%a1)
    DELAY   Z_SUMDLY
    cmpi.b  #0x00,SHR_BASE+1
    jeq     snd_sum
    moveq   #-1,%d1                     /* CRC32 running value */
    move.w  #0x00f0,%d4                 /* first command */
snd_cmd:
    lea     SHR_BASE,%a1
    move.w  %d4,(%a1)
    ZWAIT   snd_norep
    lea     SHR_BASE+0x401,%a1
    lea     crc32tab,%a2
    move.w  #1024-1,%d0
snd_crc:
    moveq   #0,%d2
    move.b  (%a1),%d2
    addq.l  #2,%a1
    eor.b   %d1,%d2
    lsl.w   #2,%d2
    lsr.l   #8,%d1
    move.l  (%a2,%d2.w),%d3
    eor.l   %d3,%d1
    dbra    %d0,snd_crc
    addq.w  #1,%d4
    cmp.w   #0x00fc,%d4
    jne     snd_cmd
    not.l   %d1
    move.l  %d1,%d5
    PRINTSTR sndok, L_SND
    PRINTSTR s_sdat, L_SDAT
    PRINTHEX %d5, 8, (L_SDAT + 11*CHARSTEP)
    lea     t_tcw,%a1
    cmp.l   #Z_CRC_TC,%d5
    jeq     snd_name
    lea     s_unknown,%a1               /* other sets: not known, not a failure */
snd_name:
    PRINTSTRR %a1, (L_SDAT + 20*CHARSTEP)
    jra     snd_done
snd_dead:
    PRINTSTR snddead, L_SND
    jra     snd_bad
snd_sum:
    PRINTSTR sndsum, L_SND
    jra     snd_bad
snd_norep:
    move.l  %d4,%d5
    PRINTSTR sndnorep, L_SND
    PRINTHEX %d5, 2, (L_SND + 25*CHARSTEP)
snd_bad:
    lea     FLAG,%a1
    move.w  #1,(%a1)
snd_done:

/* ====== STAGE 6: interrupts ======
 * The VBLANK interrupt (level 4) is gated by mainlatch Q2 (04 = off, 05 = on):
 * on the bootleg schematic Q2 holds the 74LS74 at C1 in reset, which is
 * clocked by VSYNC and drives /IPL2 (68000 pin 23) via the open-collector
 * 74LS03 at J14. The game keeps it OFF during its start-up tests; a board
 * that lets it through anyway crashes the game inside its VBLANK handler.
 * Count interrupts over IRQ_OFFFR frames with Q2 off (expect none), then
 * over IRQ_FR frames with Q2 on (expect one per frame). Any other level is always a failure. */
    PRINTSTR irqwait, L_IRQ
    PRINTSTR irqhang, L_IRQD            /* stays on screen if the CPU hangs */
    clr.w   IRQON
    clr.w   IRQC4
    clr.w   IRQCO
    move.b  #L_IRQOFF,(%a0)             /* VBLANK IRQ off */
    move.w  #0x2000,%sr                 /* CPU accepts all levels */
    IRQFRAMES IRQ_OFFFR
    move.w  #0x2700,%sr
    move.w  IRQC4,%d6                   /* D6 = level 4 while off */
    move.w  #1,IRQON
    clr.w   IRQC4
    move.b  #L_HB1,(%a0)                /* 05: VBLANK IRQ on */
    move.w  #0x2000,%sr
    IRQFRAMES IRQ_FR
    move.w  #0x2700,%sr
    move.b  #L_IRQOFF,(%a0)
    clr.w   IRQON
    move.w  IRQC4,%d5                   /* D5 = level 4 while on */
/* verdict: none while off, none of the other levels, and about one per
 * frame while on (no VBLANK input: just "some") */
    moveq   #0,%d4
    tst.w   %d6
    jne     irq_bad
    tst.w   IRQCO
    jne     irq_bad
    tst.w   VBDEAD
    jne     irq_anyon
    cmp.w   #IRQ_FR-2,%d5
    jcs     irq_bad
    cmp.w   #IRQ_FR+2,%d5
    jhi     irq_bad
    jra     irq_ok
irq_anyon:
    tst.w   %d5
    jeq     irq_bad
irq_ok:
    PRINTSTR irqok, L_IRQ
    jra     irq_det
irq_bad:
    PRINTSTR irqbad, L_IRQ
    lea     FLAG,%a1
    move.w  #1,(%a1)
irq_det:
    PRINTSTR irqdet, L_IRQD
    moveq   #0,%d7
    PRINTHEX %d6, 4, (L_IRQD + 4*CHARSTEP)
    PRINTHEX %d5, 4, (L_IRQD + 12*CHARSTEP)
    moveq   #0,%d6
    move.w  IRQCO,%d6                   /* (PRINTHEX uses D4 itself) */
    PRINTHEX %d6, 4, (L_IRQD + 24*CHARSTEP)

/* ====== STAGE 7: DSP (TMS320C10) ======
 * Runs the game's own DSP self-test (twincobr $23C98): command 1 in $30000,
 * latch 0C then 0D interrupts the DSP, which takes the 68000's bus, does the
 * test, writes the result to $3000E and 0 to $30000, and hands the bus
 * back. The game wants $76. If the DSP takes the bus and never gives it back
 * the 68000 stops for good - hence the "STOPS HERE" line. */
/* first ~4 s (240 frames) with a flashing "HOLD B2 TO SKIP DSP TEST": a board
 * whose DSP holds the bus can then still reach the menu */
    PRINTSTR dspwait, L_DSP
    moveq   #0,%d6                      /* frame */
dsk_1:
    btst    #4,%d6                      /* flash: 16 frames on, 16 off */
    jne     dsk_off
    PRINTSTR dspskp, L_DSPD
    jra     dsk_2
dsk_off:
    PRINTSTR dspblank, L_DSPD
dsk_2:
    tst.w   VBDEAD
    jne     dsk_dly
    VBWAIT
    jra     dsk_3
dsk_dly:
    DELAY   0x3000
dsk_3:
    move.w  P1IN,%d0
    btst    #5,%d0                      /* P1 button 2 */
    jne     dsk_skip
    addq.w  #1,%d6
    cmp.w   #240,%d6
    jcs     dsk_1
    jra     dsp_go
dsk_skip:
    PRINTSTR dspskip, L_DSP
    PRINTSTR dspblank, L_DSPD
    jra     dsp_done
dsp_go:
    PRINTSTR dsptest, L_DSP
    PRINTSTR dsphang, L_DSPD
    bsr     dsp_run                     /* D0 = 0 answered / 1 no reply, D5 = result */
    tst.w   %d0
    jne     dsp_norep
    cmp.w   #DSP_GOOD,%d5
    jne     dsp_bad
    PRINTSTR dspok, L_DSP
    PRINTSTR dspblank, L_DSPD
    jra     dsp_done
dsp_norep:
    PRINTSTR dspnore, L_DSP
    PRINTSTR dspblank, L_DSPD
    jra     dsp_fail
dsp_bad:
    PRINTSTR dspbad, L_DSP
    PRINTSTR dspres, L_DSPD
    PRINTHEX %d5, 4, (L_DSPD + 7*CHARSTEP)
dsp_fail:
    lea     FLAG,%a1
    move.w  #1,(%a1)
dsp_done:

/* summary line + heartbeat pattern */
    lea     FLAG,%a1
    tst.w   (%a1)
    jne     some_fail
    PRINTSTR allok, L_END
    jra     pass_hold
some_fail:
    PRINTSTR somebad, L_END
    jra     fail_hold

/* ===================== liveness on the heartbeat pin =====================
 * Both end states also watch P1 button 1, which opens the loop-test menu. */
pass_hold:
    PRINTSTR m_hintmm, L_HINT
pass_loop:
    move.b  #L_HB1,(%a0)
    DLYCHK  mm_enter
    move.b  #L_HB0,(%a0)
    DLYCHK  mm_enter
    jra     pass_loop

fail_hold:
    PRINTSTR m_hintmm, L_HINT
fail_loop:
    moveq   #3,%d4
fp:
    move.b  #L_HB1,(%a0)
    DELAY   HB_FAST
    move.b  #L_HB0,(%a0)
    DELAY   HB_FAST
    dbra    %d4,fp
    DLYCHK  mm_enter
    jra     fail_loop

/* work RAM failed: same blink, but button 1 opens only the register-only RAM
 * loop menu (the main menu needs work RAM) */
wram_hold:
    PRINTSTR m_hint, L_HINT
wram_loop:
    moveq   #3,%d4
wfp:
    move.b  #L_HB1,(%a0)
    DELAY   HB_FAST
    move.b  #L_HB0,(%a0)
    DELAY   HB_FAST
    dbra    %d4,wfp
    DLYCHK  menu
    jra     wram_loop

mm_enter:
    move.w  #0,MSEL
    jra     main_menu

/* ===================== loop-test menu (troubleshooting) =====================
 * Pick a RAM with the P1 stick, B1 starts a tight loop on its first word:
 * write 0000, read, write FFFF, read - so every data line toggles each cycle.
 * The heartbeat pin (LS259 pin 6) goes high at the start of each cycle as a
 * scope trigger. The two read-backs are shown live. B2 stops.
 * Register-only (no stack, no work RAM), so it also works when work RAM is
 * the thing that failed. D5 = target index (0 work, 1 sprite, 2 palette,
 * 3 Z80 shared RAM; the Z80 is restarted and left waiting for its start
 * signal, because it has to run to hand the 68000 its bus). */
menu:
    move.b  #L_SNDRST0,(%a0)            /* restart the Z80: after reset it */
    DELAY   0x1000                      /* writes $8000/$8001 once, then only */
    move.b  #L_SNDRUN,(%a0)             /* reads $8001 (waits for AA) - and it */
                                        /* must run to grant the bus at $7A000 */
    moveq   #0,%d5
menu_show:
    PRINTSTR m_title, L_M0
    PRINTSTR m_keys,  L_M2
m_target:
    PRINTSTR m_tgt, L_M1
    lea     loop_tab,%a1
    move.w  %d5,%d0
    lsl.w   #3,%d0
    movea.l 0(%a1,%d0.w),%a5            /* base address of the target */
    movea.l 4(%a1,%d0.w),%a1            /* its name */
    PRINTSTRR %a1, (L_M1 + 7*CHARSTEP)
    PRINTHEX %a5, 6, (L_M1 + 19*CHARSTEP)
    WAITREL
m_poll:
    DELAY   MENU_DLY
    lea     P1IN,%a2
    move.w  (%a2),%d0
    PRINTHEX %d0, 2, (L_M2 + 22*CHARSTEP)   /* live P1 inputs (PRINTHEX keeps D0) */
    btst    #0,%d0                      /* up */
    jne     m_up
    btst    #1,%d0                      /* down */
    jne     m_down
    btst    #4,%d0                      /* B1: start */
    jne     loop_go
    btst    #5,%d0                      /* B2: back to the main menu, if we came */
    jeq     m_poll                      /* from there (marker in USP) */
    move.l  %usp,%a1
    cmpa.l  #MM_MARK,%a1
    jne     m_poll
    jra     main_menu
m_up:
    subq.w  #1,%d5
    jpl     m_target
    moveq   #3,%d5
    jra     m_target
m_down:
    addq.w  #1,%d5
    cmp.w   #4,%d5
    jlt     m_target
    moveq   #0,%d5
    jra     m_target

loop_go:
    movea.w %d5,%a1                     /* keep the target index (A1 is free here) */
    WAITREL
    cmpa.l  #SHR_BASE,%a5
    jeq     lp_lbl8
    PRINTSTR m_run,  L_M3
    PRINTSTR m_run2, (L_M3 + 13*CHARSTEP)
    PRINTSTR m_note0, L_M4
    jra     lp_outer
lp_lbl8:
/* shared RAM is 8-bit (D0-D7): show only the byte that exists */
    PRINTSTR m_run8,  L_M3
    PRINTSTR m_run8b, (L_M3 + 13*CHARSTEP)
    PRINTSTR m_note8, L_M4
lp_outer:
/* access rules as in the tests: sprite RAM right after VBLANK, palette RAM
 * with the screen off (it comes back on for the read-back display) */
    cmpa.l  #PAL_BASE,%a5
    jne     lp_notpal
    move.b  #L_SCRNOFF,(%a0)
lp_notpal:
    cmpa.l  #SPR_BASE,%a5
    jne     lp_go
    VBWAIT
lp_go:
    move.w  #0x01ff,%d4                 /* 512 cycles per burst (~6 ms) */
lp:
    move.b  #L_HB1,(%a0)                /* scope trigger: start of cycle */
    move.w  #0x0000,(%a5)
    move.w  (%a5),%d6
    move.w  #0xffff,(%a5)
    move.w  (%a5),%d5
    move.b  #L_HB0,(%a0)
    dbra    %d4,lp
    move.b  #L_SCRNON,(%a0)
    cmpa.l  #SHR_BASE,%a5
    jeq     lp_show8
    PRINTHEX %d6, 4, (L_M3 + 8*CHARSTEP)    /* read-back after writing 0000 */
    PRINTHEX %d5, 4, (L_M3 + 21*CHARSTEP)   /* read-back after writing FFFF */
    jra     lp_keys
lp_show8:
    PRINTHEX %d6, 2, (L_M3 + 6*CHARSTEP)
    PRINTHEX %d5, 2, (L_M3 + 19*CHARSTEP)
lp_keys:
    lea     P1IN,%a2
    move.w  (%a2),%d0
    PRINTHEX %d0, 2, (L_M2 + 22*CHARSTEP)   /* live P1 inputs: B2 = 20, B1 = 10 */
    and.w   #0x0030,%d0                 /* B1 or B2: stop */
    jeq     lp_outer
    WAITREL
    move.w  %a1,%d5                     /* recover the target index */
    jra     menu_show

/* ---- unexpected exceptions: print "EXCEPTION nn PC xxxxxx" and stop ---- */
exc_2:
    move.w  #2,EXCNO
    bra.w   exc_common
exc_3:
    move.w  #3,EXCNO
    bra.w   exc_common
exc_4:
    move.w  #4,EXCNO
    bra.w   exc_common
exc_5:
    move.w  #5,EXCNO
    bra.w   exc_common
exc_6:
    move.w  #6,EXCNO
    bra.w   exc_common
exc_7:
    move.w  #7,EXCNO
    bra.w   exc_common
exc_8:
    move.w  #8,EXCNO
    bra.w   exc_common
exc_9:
    move.w  #9,EXCNO
    bra.w   exc_common
exc_10:
    move.w  #10,EXCNO
    bra.w   exc_common
exc_11:
    move.w  #11,EXCNO
    bra.w   exc_common
exc_12:
    move.w  #12,EXCNO
    bra.w   exc_common
exc_13:
    move.w  #13,EXCNO
    bra.w   exc_common
exc_14:
    move.w  #14,EXCNO
    bra.w   exc_common
exc_15:
    move.w  #15,EXCNO
    bra.w   exc_common
exc_16:
    move.w  #16,EXCNO
    bra.w   exc_common
exc_17:
    move.w  #17,EXCNO
    bra.w   exc_common
exc_18:
    move.w  #18,EXCNO
    bra.w   exc_common
exc_19:
    move.w  #19,EXCNO
    bra.w   exc_common
exc_20:
    move.w  #20,EXCNO
    bra.w   exc_common
exc_21:
    move.w  #21,EXCNO
    bra.w   exc_common
exc_22:
    move.w  #22,EXCNO
    bra.w   exc_common
exc_23:
    move.w  #23,EXCNO
    bra.w   exc_common
exc_32:
    move.w  #32,EXCNO
    bra.w   exc_common
exc_33:
    move.w  #33,EXCNO
    bra.w   exc_common
exc_34:
    move.w  #34,EXCNO
    bra.w   exc_common
exc_35:
    move.w  #35,EXCNO
    bra.w   exc_common
exc_36:
    move.w  #36,EXCNO
    bra.w   exc_common
exc_37:
    move.w  #37,EXCNO
    bra.w   exc_common
exc_38:
    move.w  #38,EXCNO
    bra.w   exc_common
exc_39:
    move.w  #39,EXCNO
    bra.w   exc_common
exc_40:
    move.w  #40,EXCNO
    bra.w   exc_common
exc_41:
    move.w  #41,EXCNO
    bra.w   exc_common
exc_42:
    move.w  #42,EXCNO
    bra.w   exc_common
exc_43:
    move.w  #43,EXCNO
    bra.w   exc_common
exc_44:
    move.w  #44,EXCNO
    bra.w   exc_common
exc_45:
    move.w  #45,EXCNO
    bra.w   exc_common
exc_46:
    move.w  #46,EXCNO
    bra.w   exc_common
exc_47:
    move.w  #47,EXCNO
    bra.w   exc_common
exc_48:
    move.w  #48,EXCNO
    bra.w   exc_common
exc_49:
    move.w  #49,EXCNO
    bra.w   exc_common
exc_50:
    move.w  #50,EXCNO
    bra.w   exc_common
exc_51:
    move.w  #51,EXCNO
    bra.w   exc_common
exc_52:
    move.w  #52,EXCNO
    bra.w   exc_common
exc_53:
    move.w  #53,EXCNO
    bra.w   exc_common
exc_54:
    move.w  #54,EXCNO
    bra.w   exc_common
exc_55:
    move.w  #55,EXCNO
    bra.w   exc_common
exc_56:
    move.w  #56,EXCNO
    bra.w   exc_common
exc_57:
    move.w  #57,EXCNO
    bra.w   exc_common
exc_58:
    move.w  #58,EXCNO
    bra.w   exc_common
exc_59:
    move.w  #59,EXCNO
    bra.w   exc_common
exc_60:
    move.w  #60,EXCNO
    bra.w   exc_common
exc_61:
    move.w  #61,EXCNO
    bra.w   exc_common
exc_62:
    move.w  #62,EXCNO
    bra.w   exc_common
exc_63:
    move.w  #63,EXCNO
    bra.w   exc_common
exc_common:
    move.w  #0x2700,%sr
    move.l  %sp,%d0
    movea.l %d0,%a1
    move.w  EXCNO,%d5
    cmp.w   #3,%d5                      /* bus / address error: PC at +10 */
    jhi     exc_short
    move.l  10(%a1),%d6
    jra     exc_pc
exc_short:
    move.l  2(%a1),%d6
exc_pc:
    movea.l #0x033e00,%sp
    lea     LATCH,%a0
    lea     TXOFFS,%a3
    lea     TXDATA,%a4
    move.b  #L_SCRNON,(%a0)
    PRINTSTR excmsg, L_IRQD
    PRINTHEX %d5, 2, (L_IRQD + 10*CHARSTEP)
    PRINTHEX %d6, 6, (L_IRQD + 19*CHARSTEP)
    lea     FLAG,%a1
    move.w  #1,(%a1)
    jra     fail_hold

/* ---- DSP self-test (stage 7 and the menu's DSP TEST). Leaves the DSP in
 * reset and disabled again. Out: D0 = 0 if it answered (D5 = its result
 * word from $3000E), 1 if it never cleared the command. Uses D0,D5,D7. ---- */
    .equ DSP_CMD,   0x030000               /* command word the DSP reads */
    .equ DSP_RES,   0x03000e               /* its answer */
    .equ DSP_GOOD,  0x0076                 /* what the game expects (command 1) */
dsp_run:
/* start it the way the game does at boot: 0D, then pulse its reset */
    move.b  #0x0d,(%a0)
    move.b  #L_DSPRST0,(%a0)
    DELAY   0x0100
    move.b  #0x01,(%a0)
    DELAY   0x4000                      /* let it reach its idle loop */
    clr.w   DSP_CMD+14
    move.w  #1,DSP_CMD                  /* command 1: self-test */
    move.b  #L_DSP_OFF,(%a0)            /* 0C then 0D: interrupt it */
    move.b  #0x0d,(%a0)
    moveq   #0,%d0
    move.l  #0x00040000,%d7             /* ~1.5 s */
dr_w:
    tst.w   DSP_CMD
    jeq     dr_ok
    subq.l  #1,%d7
    jne     dr_w
    moveq   #1,%d0
dr_ok:
    moveq   #0,%d5
    move.w  DSP_RES,%d5
    move.b  #L_DSP_OFF,(%a0)            /* back to: disabled and held in reset */
    move.b  #L_DSPRST0,(%a0)
    rts

/* ---- interrupt handlers (stage 6). They touch no registers. ---- */
/* VBLANK: count it; re-arm only if it is meant to be on. An interrupt while
 * it is meant to be off is counted once, then the stacked SR is raised to
 * mask everything, so a stuck line cannot lock the test up. */
irq_vbl:
    addq.w  #1,IRQC4
    move.b  #L_IRQOFF,LATCH             /* 04: acknowledge (resets C1) */
    tst.w   IRQON
    jeq     irq_vbl_off
    move.b  #L_HB1,LATCH                /* 05: arm for the next frame */
    rte
irq_vbl_off:
    ori.w   #0x0700,(%sp)
    rte
/* any other level, or spurious: count once, then mask */
irq_other:
    addq.w  #1,IRQCO
    ori.w   #0x0700,(%sp)
    rte

    .include "pages.inc"

/* ============================ data ============================ */
    .even
    CRTCTAB

hdr:     .asciz "TWIN COBRA DIAG"
okmsg:   .asciz "WORK RAM  PASS"
failmsg: .asciz "WORK RAM  FAIL"
detlbl:  .asciz "A        E      G"

    .even
    ASCTAB

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
novbl:     .asciz "NO VBLANK SIGNAL"
s_pass:    .asciz "PASS"
s_fail:    .asciz "FAIL"
s_txv:     .asciz "TEXT VRAM"
s_fgv:     .asciz "FG VRAM"
s_bgv:     .asciz "BG VRAM"
shrok:     .asciz "SHARED RAM  PASS        "
shrbad:    .asciz "SHARED RAM  FAIL        "
sndok:     .asciz "SOUND CPU   OK"
snddead:   .asciz "SOUND CPU   NOT RUNNING"
sndnorep:  .asciz "SOUND CPU   NO REPLY CMD"
sndsum:    .asciz "SOUND CPU   ROM SUM BAD"
irqwait:   .asciz "VBLANK IRQ  TESTING"
dsptest:   .asciz "DSP         TESTING    "
dspskip:   .asciz "DSP         SKIPPED    "
dspwait:   .asciz "DSP         STARTS SOON"
dspskp:    .asciz "HOLD B2 TO SKIP DSP TEST  "
dsphang:   .asciz "STOPS HERE = DSP HOLDS BUS"
dspok:     .asciz "DSP         OK SELFTEST 76"
dspnore:   .asciz "DSP         NO REPLY      "
dspbad:    .asciz "DSP         FAIL          "
dspres:    .asciz "RESULT      EXPECTED 0076     "
dspblank:  .asciz "                          "
irqok:     .asciz "VBLANK IRQ  PASS   "
irqbad:    .asciz "VBLANK IRQ  FAIL   "
irqdet:    .asciz "OFF      ON       OTHER     "
irqhang:   .asciz "STOPS HERE IRQ ACK HANG     "
excmsg:    .asciz "EXCEPTION       PC          "
shrwait:   .asciz "SHARED RAM  WAIT Z80 BUS"
s_sdat:    .asciz "SOUND ROM"
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

/* ---- loop-test menu strings and target table ---- */
m_hint:  .asciz "P1 BUTTON 1  LOOP TEST MENU"   /* work RAM failed: only the loop menu */
m_hintmm: .asciz "P1 BUTTON 1  MAIN MENU     "
m_title: .asciz "LOOP TEST  STICK SELECTS"
m_tgt:   .asciz "TARGET"
m_keys:  .asciz "B1 START  B2 STOP  IN"
m_run:   .asciz "W0000 R "
m_run2:  .asciz "WFFFF R "
m_run8:  .asciz "W00 R       "
m_run8b: .asciz "WFF R       "
m_note8: .asciz "8 BIT RAM  D0 TO D7 ONLY"
m_note0: .asciz "                        "
n_work:  .asciz "WORK RAM   "
n_spr:   .asciz "SPRITE RAM "
n_pal:   .asciz "PALETTE RAM"
n_shr:   .asciz "SHARED RAM "
    .even
loop_tab:
    .long 0x030000, n_work
    .long 0x040000, n_spr
    .long 0x050000, n_pal
    .long 0x07a000, n_shr

/* high score replay data (big, so last: keeps branches in range) */
    .even
    .include "hsdata.inc"
    .even
