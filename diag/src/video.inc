/* Shared by diag.s and crash.s: video/text hardware equates, the text
 * printing macros, the screen bring-up, and the font/CRTC tables. */

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

    /* Text layout. The monitor is vertical (ROT270): the game writes text DOWN
     * the framebuffer columns, which reads left-to-right and upright on screen.
     * So one character advances the tilemap offset by a full row (64); each new
     * display line is the adjacent column (offset - 1). */
    .equ ROW,       64
    .equ CHARSTEP,  64                     /* next char = next framebuffer row */

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

/* CRTC, palette (black + white text pens), clear the text layer, centre the
 * text scroll, screen on. A0 = LATCH on entry; leaves A3 = TXOFFS, A4 = TXDATA
 * for the print macros. Uses D0,D1,D4,A1,A2. */
.macro VIDINIT
/* ---- CRTC (R0-R9, values measured from the game ROM) ---- */
    moveq   #9,%d0
    moveq   #0,%d1
    lea     crtc_tab,%a1
    lea     CRTC_BASE,%a2
ci\@:
    move.w  %d1,(%a2)
    addq.w  #1,%d1
    move.w  (%a1)+,2(%a2)
    dbra    %d0,ci\@

/* ---- palette: everything black, then text set-0 pens 1-7 white ---- */
    FLOOD   C_BLACK
    lea     PAL_TXT0+2,%a1              /* pen 1 of text set 0 */
    moveq   #6,%d0
pw\@:
    move.w  #C_WHITE,(%a1)+
    dbra    %d0,pw\@

/* ---- text ports, clear the text layer to blanks ---- */
    lea     TXOFFS,%a3
    lea     TXDATA,%a4
    move.w  #0x07ff,%d4
cx\@:
    move.w  %d4,(%a3)
    move.w  #0x002d,(%a4)
    dbra    %d4,cx\@

/* ---- text scroll to the game's centre values ---- */
    lea     TXSCROLL,%a1
    move.w  #0x01ca,(%a1)               /* y */
    move.w  #0x00e2,2(%a1)              /* x */

    move.b  #L_SCRNON,(%a0)             /* screen on (black) */
.endm

/* CRTC R0-R9 (measured from the game ROM) */
.macro CRTCTAB
crtc_tab:
    .short  0x00de, 0x00a0, 0x00b0, 0x008f, 0x0022
    .short  0x0006, 0x001e, 0x001f, 0x0000, 0x0007
.endm

/* ASCII -> font tile (digits 0x00-0x09, A-Z 0x0A-0x23, else blank 0x2D) */
.macro ASCTAB
asc2tile:
    .byte 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d
    .byte 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d
    .byte 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d
    .byte 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d
    .byte 0x2d, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18
    .byte 0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f, 0x20, 0x21, 0x22, 0x23, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d
    .byte 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d
    .byte 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d, 0x2d
.endm
