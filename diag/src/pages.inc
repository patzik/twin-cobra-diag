/* ============================================================================
 * Main menu and its pages (input/DIP test, colour test, tile and sprite
 * viewers, sound test). Modelled on the Shinobi test ROM's menu.
 *
 * Reached with P1 button 1 once the tests are done and work RAM passed (the
 * pages use the stack and work RAM). If work RAM failed, button 1 opens the
 * register-only RAM loop menu instead.
 *
 * Register use on every page: A0 = LATCH, A3 = TXOFFS, A4 = TXDATA (set by
 * page_init); D0-D7, A1, A2, A5, A6 are scratch.
 *
 * Text attributes: colour set << 11 | tile. Sets: 0 white (labels),
 * 1 yellow (highlight / active), 2 grey (help / inactive), 3 "plane colours"
 * for the text tile viewer.
 * ============================================================================ */

    .equ MM_SP,     0x033e00               /* stack for the menu pages */
    .equ MM_MARK,   0x4d454e55             /* 'MENU' in USP: main menu is reachable */
    .equ IN_CUR,    0x033f80               /* P1 now */
    .equ IN_PREV,   0x033f82               /* P1 last frame */
    .equ IN_EDGE,   0x033f84               /* P1 newly pressed */
    .equ MSEL,      0x033f86               /* main menu cursor */
    .equ PG,        0x033f88               /* viewer page */
    .equ VLAY,      0x033f8a               /* viewer layer 0 text, 1 fg, 2 bg */
    .equ SCODE,     0x033f8c               /* sound test code */
    .equ VCOL,      0x033f8e               /* viewer colours: game set n, or -1 = planes */
    .equ PRSBG,     0x033fa0               /* nonzero: prs prints spaces as black blocks */
    .equ PANC,      0x033fa2               /* panel shift in text columns (0-63) and */
    .equ PANR,      0x033fa4               /* rows (0-31): keeps the scroll test's panel in
                                            * place while the text layer itself scrolls */
    .equ A_BLACK,   0x2000                 /* text set 4: left all black */
    .equ FG_SOLID,  22                     /* a solid FG tile (one pen everywhere) */
    .equ BG_SOLID,  36                     /* a solid BG tile */
    .equ A_WHITE,   0x0000
    .equ A_YELLOW,  0x0800
    .equ A_GREY,    0x1000
    .equ A_PLANES,  0x1800
    .equ C_YELLOW,  0x03ff
    .equ C_GREY,    0x3def
    .equ K_UP,      0x01
    .equ K_DOWN,    0x02
    .equ K_LEFT,    0x04
    .equ K_RIGHT,   0x08
    .equ K_B1,      0x10
    .equ K_B2,      0x20
    .equ PAL_FG0,   (PAL_BASE + 1280*2)
    .equ PAL_BG0,   (PAL_BASE + 1024*2)
    .equ PAL_SPR0,  (PAL_BASE + 0)
    .equ PAL_TXT3,  (PAL_BASE + (1536 + 3*8)*2)
    .equ BG_BLANK,  0xf3fc                 /* an empty BG tile (all pen 0) in colour set 15,
                                            * which the viewers leave black (BG is opaque) */
    .equ SCR_X,     0x01ca                 /* the text layer's scroll */
    .equ SCR_Y,     0x00e2
    .equ SCR_Y64,   0x01e2                 /* FG/BG are 64 tiles high (text 32): the
                                            * same rows line up 256 pixels further */
    /* a 16x16 sprite whose top-left is text line L, character k (measured in
     * MAME): X register = 326 - 8*L, Y register = 24 + 8*k (both << 7) */

/* text offset of screen line L, character position K */
.macro TXY l, k
    move.w  #(ORG - (\l) + (\k)*CHARSTEP),%d4
.endm
.macro SAY lbl, l, k, attr
    lea     \lbl,%a2
    TXY     \l, \k
    move.w  #\attr,%d2
    bsr     prs
.endm

/* ---------------------------------------------------------------------- */
main_menu:
    move.w  #0x2700,%sr
    movea.l #MM_SP,%sp
    movea.l #MM_MARK,%a1
    move.l  %a1,%usp                    /* tells the RAM loop menu it may come back */
    cmpi.w  #MM_N,MSEL
    jcs     mm_ok
    move.w  #0,MSEL
mm_ok:
    bsr     page_init
    bsr     wait_release                /* a button still held is not a new press */
    SAY     s_mtitle, 0, 0, A_YELLOW
    SAY     s_mhelp, 24, 0, A_GREY
mm_draw:
    bsr     mm_items
mm_loop:
    bsr     wait_frame
    bsr     read_inp
    move.w  IN_EDGE,%d0
    move.w  MSEL,%d1
    btst    #0,%d0
    jeq     mm_1
    subq.w  #1,%d1
    jpl     mm_1
    moveq   #MM_N-1,%d1
mm_1:
    btst    #1,%d0
    jeq     mm_2
    addq.w  #1,%d1
    cmp.w   #MM_N,%d1
    jcs     mm_2
    moveq   #0,%d1
mm_2:
    cmp.w   MSEL,%d1
    jeq     mm_3
    move.w  %d1,MSEL
    jra     mm_draw
mm_3:
    btst    #4,%d0
    jeq     mm_loop
    bsr     wait_release
    move.w  MSEL,%d0
    lsl.w   #2,%d0
    lea     mm_jt,%a1
    movea.l (%a1,%d0.w),%a1
    jsr     (%a1)
    jra     main_menu

    .equ MM_N, 10
mm_items:
    lea     mm_str,%a5
    moveq   #0,%d6                      /* item */
    move.w  #(ORG - 3),%d5              /* line offset: items double-spaced from line 3 */
mi_1:
    movea.l (%a5)+,%a2
    move.w  %d5,%d4
    add.w   #2*CHARSTEP,%d4
    move.w  #A_WHITE,%d2
    cmp.w   MSEL,%d6
    jne     mi_2
    move.w  #A_YELLOW,%d2
mi_2:
    bsr     prs
    /* cursor mark: a solid block in front of the selected item */
    move.w  %d5,(%a3)
    move.w  #0x002d,(%a4)
    cmp.w   MSEL,%d6
    jne     mi_3
    move.w  #(A_YELLOW + 0x07f6),(%a4)
mi_3:
    subq.w  #2,%d5
    addq.w  #1,%d6
    cmp.w   #MM_N,%d6
    jne     mi_1
    rts

/* ---------------------------------------------------------------------- */
/* clear everything and set the standard palette */
page_init:
    move.w  #0,PRSBG
    move.w  #0,PANC
    move.w  #0,PANR
    lea     LATCH,%a0
    lea     TXOFFS,%a3
    lea     TXDATA,%a4
    move.b  #L_SCRNOFF,(%a0)
    move.b  #L_FGBANK0,(%a0)
    move.b  #L_BGBANK0,(%a0)
    FLOOD   C_BLACK
    lea     PAL_TXT0+2,%a1
    moveq   #6,%d0
pi_w:
    move.w  #C_WHITE,(%a1)+
    dbra    %d0,pi_w
    lea     PAL_TXT0+16+2,%a1           /* set 1: yellow */
    moveq   #6,%d0
pi_y:
    move.w  #C_YELLOW,(%a1)+
    dbra    %d0,pi_y
    lea     PAL_TXT0+32+2,%a1           /* set 2: grey */
    moveq   #6,%d0
pi_g:
    move.w  #C_GREY,(%a1)+
    dbra    %d0,pi_g
/* set 3 and the first FG / BG / sprite colour set: "plane colours", so a
 * missing or stuck bitplane shows as a missing or wrong colour:
 * plane 0 = red, 1 = green, 2 = blue, 3 = brighter (4-bit layers) */
    lea     PAL_TXT3,%a1
    moveq   #0,%d0
pi_t:
    move.w  %d0,%d1
    bsr     plane_col3
    move.w  %d1,(%a1)+
    addq.w  #1,%d0
    cmp.w   #8,%d0
    jne     pi_t
    lea     PAL_FG0,%a1
    lea     PAL_BG0,%a2
    lea     PAL_SPR0,%a5
    moveq   #0,%d0
pi_4:
    move.w  %d0,%d1
    bsr     plane_col4
    move.w  %d1,(%a1)+
    move.w  %d1,(%a2)+
    move.w  %d1,(%a5)+
    addq.w  #1,%d0
    cmp.w   #16,%d0
    jne     pi_4
/* layers: text blank, FG tile 0 (empty), BG an empty tile; same scroll */
    move.w  #0x07ff,%d4
pi_tx:
    move.w  %d4,(%a3)
    move.w  #0x002d,(%a4)
    dbra    %d4,pi_tx
    lea     FGOFFS,%a1
    lea     FGDATA,%a2
    move.w  #FG_WORDS-1,%d4
pi_fg:
    move.w  %d4,(%a1)
    move.w  #0x0000,(%a2)
    dbra    %d4,pi_fg
    lea     BGOFFS,%a1
    lea     BGDATA,%a2
    move.w  #BG_WORDS-1,%d4
pi_bg:
    move.w  %d4,(%a1)
    move.w  #BG_BLANK,(%a2)
    dbra    %d4,pi_bg
    lea     TXSCROLL,%a1
    move.w  #SCR_X,(%a1)
    move.w  #SCR_Y,2(%a1)
    move.w  #SCR_X,0x072000
    move.w  #SCR_Y64,0x072002
    move.w  #SCR_X,0x074000
    move.w  #SCR_Y64,0x074002
    moveq   #0,%d2
    SPRWR   0                           /* all sprites off */
    move.b  #L_SCRNON,(%a0)
    lea     TXOFFS,%a3
    lea     TXDATA,%a4
    rts

/* D0 = pen 0-7 -> D1 = xBGR_555 */
plane_col3:
    moveq   #0,%d1
    btst    #0,%d0
    jeq     pc3a
    or.w    #0x001f,%d1
pc3a:
    btst    #1,%d0
    jeq     pc3b
    or.w    #0x03e0,%d1
pc3b:
    btst    #2,%d0
    jeq     pc3c
    or.w    #0x7c00,%d1
pc3c:
    rts
/* D0 = pen 0-15 -> D1: R/G/B 20 each for planes 0/1/2, +11 on all for plane 3 */
plane_col4:
    moveq   #0,%d1
    btst    #0,%d0
    jeq     pc4a
    add.w   #20,%d1
pc4a:
    btst    #1,%d0
    jeq     pc4b
    add.w   #(20<<5),%d1
pc4b:
    btst    #2,%d0
    jeq     pc4c
    add.w   #(20<<10),%d1
pc4c:
    btst    #3,%d0
    jeq     pc4d
    add.w   #(11 + (11<<5) + (11<<10)),%d1
pc4d:
    rts

/* one frame (VBLANK-timed; a delay without a VBLANK input). Uses D7. */
wait_frame:
    tst.w   VBDEAD
    jne     wf_d
    VBWAIT
    rts
wf_d:
    DELAY   0x3000
    rts

/* P1 into IN_CUR, newly pressed buttons into IN_EDGE. Uses D0,D1. */
read_inp:
    move.w  IN_CUR,IN_PREV
    move.w  P1IN,%d0
    and.w   #0x00ff,%d0
    move.w  %d0,IN_CUR
    move.w  IN_PREV,%d1
    not.w   %d1
    and.w   %d1,%d0
    move.w  %d0,IN_EDGE
    rts

/* wait until no P1 direction / button is held */
wait_release:
    bsr     wait_frame
    move.w  P1IN,%d0
    and.w   #0x003f,%d0
    jne     wait_release
    move.w  #0,IN_CUR
    rts

/* print string A2 at text offset D4 with attribute D2. Uses D0,A2,A6. */
prs:
    lea     asc2tile,%a6
prs1:
    moveq   #0,%d0
    move.b  (%a2)+,%d0
    beq.s   prs2
    move.b  (%a6,%d0.w),%d0
    or.w    %d2,%d0
    cmp.b   #0x2d,%d0                   /* blank: see-through, or a black block */
    bne.s   prs3
    tst.w   PRSBG
    beq.s   prs3
    move.w  #(A_BLACK + 0x07f6),%d0
prs3:
    bsr     tx_put
    add.w   #CHARSTEP,%d4
    bra.s   prs1
prs2:
    rts

/* write text tile D0 at offset D4, shifted by PANC columns / PANR rows (both
 * wrap inside the 64 x 32 text map) */
tx_put:
    movem.l %d1-%d2,-(%sp)
    move.w  %d4,%d1
    and.w   #63,%d1
    add.w   PANC,%d1
    and.w   #63,%d1                     /* column */
    move.w  %d4,%d2
    lsr.w   #6,%d2
    add.w   PANR,%d2
    and.w   #31,%d2                     /* row */
    lsl.w   #6,%d2
    or.w    %d2,%d1
    move.w  %d1,(%a3)
    move.w  %d0,(%a4)
    movem.l (%sp)+,%d1-%d2
    rts

/* print the low D3 nibbles of D5 in hex at D4 with attribute D2.
 * Uses D1,D3,D7. */
prh:
    subq.w  #1,%d3
    move.l  %d5,%d1
    move.w  %d3,%d7
    lsl.w   #2,%d7
    lsr.l   %d7,%d1
    and.w   #0x000f,%d1
    or.w    %d2,%d1
    move.l  %d0,-(%sp)
    move.w  %d1,%d0
    bsr     tx_put
    move.l  (%sp)+,%d0
    add.w   #CHARSTEP,%d4
    tst.w   %d3
    bne.s   prh
    rts

/* ====================== input and DIP switch test ====================== */
pg_inputs:
    bsr     page_init
    SAY     s_in_t, 0, 0, A_YELLOW
    SAY     s_zwait, 20, 0, A_GREY
    bsr     z80_start                   /* SYS comes through the Z80 */
    tst.w   %d0
    jeq     pin_up
    SAY     s_zdead, 20, 0, A_YELLOW
    jra     pin_up2
pin_up:
    SAY     s_zok, 20, 0, A_GREY
pin_up2:
    SAY     s_in_p1, 3, 0, A_WHITE
    SAY     s_in_p2, 5, 0, A_WHITE
    SAY     s_in_sy, 7, 0, A_WHITE
    SAY     s_in_sy2, 8, 0, A_GREY
    SAY     s_in_d1, 11, 0, A_WHITE
    SAY     s_in_d2, 13, 0, A_WHITE
    SAY     s_in_sw, 14, 0, A_GREY
    SAY     s_in_h, 24, 0, A_GREY
pin_loop:
    bsr     wait_frame
    move.w  P1IN,%d6
    move.w  #(ORG - 3 + 4*CHARSTEP),%d4
    bsr     in_joy
    move.w  0x078006,%d6                /* P2 */
    move.w  #(ORG - 5 + 4*CHARSTEP),%d4
    bsr     in_joy
    move.w  SHR_BASE+0x0a,%d6           /* Z80 copies its coin/start port to $8005 (low byte) */
    move.w  #(ORG - 7 + 4*CHARSTEP),%d4
    bsr     in_sys
    move.w  0x078000,%d6                /* DSW1 */
    move.w  #(ORG - 11 + 5*CHARSTEP),%d4
    bsr     in_dsw
    move.w  0x078002,%d6                /* DSW2 */
    move.w  #(ORG - 13 + 5*CHARSTEP),%d4
    bsr     in_dsw
    move.w  P1IN,%d0
    and.w   #(K_B1+K_B2),%d0
    cmp.w   #(K_B1+K_B2),%d0
    jne     pin_loop
    bsr     wait_release
    rts

/* "xx" then the names, each yellow when pressed (D6 = port, D4 = offset) */
in_joy:
    lea     in_jn,%a5
    jra     in_named
in_sys:
    lea     in_sn,%a5
in_named:
    moveq   #0,%d5
    move.b  %d6,%d5
    moveq   #2,%d3
    move.w  #A_WHITE,%d2
    bsr     prh
    add.w   #CHARSTEP,%d4
    moveq   #0,%d6                      /* bit number */
inn_1:
    movea.l (%a5)+,%a2
    cmpa.l  #0,%a2
    jeq     inn_3
    move.w  #A_GREY,%d2
    btst    %d6,%d5
    jeq     inn_2
    move.w  #A_YELLOW,%d2
inn_2:
    bsr     prs
    add.w   #CHARSTEP,%d4
    addq.w  #1,%d6
    jra     inn_1
inn_3:
    rts

/* "xx  10010000": switch 1 first */
in_dsw:
    moveq   #0,%d5
    move.b  %d6,%d5
    moveq   #2,%d3
    move.w  #A_WHITE,%d2
    bsr     prh
    add.w   #2*CHARSTEP,%d4
    moveq   #0,%d6
ind_1:
    move.w  #(A_GREY + 0x00),%d0        /* tile 0 = "0" */
    btst    %d6,%d5
    jeq     ind_2
    move.w  #(A_YELLOW + 0x01),%d0      /* tile 1 = "1" */
ind_2:
    move.w  %d4,(%a3)
    move.w  %d0,(%a4)
    add.w   #CHARSTEP,%d4
    addq.w  #1,%d6
    cmp.w   #8,%d6
    jne     ind_1
    rts

/* ============================ colour test ============================== */
/* Text colour sets 1-31 get level 1-31 of red (pen 1), green (pen 2),
 * blue (pen 3) and white (pen 4); characters $7F0-$7F6 are solid pens 1-7. Each line is one level, so every DAC bit shows up as a
 * step in the bars. */
pg_colour:
    bsr     page_init
    move.b  #L_SCRNOFF,(%a0)
    lea     PAL_TXT0+16,%a1             /* set 1 */
    moveq   #1,%d0
pco_p:
    move.w  #0,(%a1)+                   /* pen 0 */
    move.w  %d0,(%a1)+                  /* pen 1 red */
    move.w  %d0,%d1
    lsl.w   #5,%d1
    move.w  %d1,(%a1)+                  /* pen 2 green */
    move.w  %d0,%d1
    lsl.w   #8,%d1
    lsl.w   #2,%d1
    move.w  %d1,(%a1)+                  /* pen 3 blue */
    move.w  %d0,%d1
    move.w  %d0,%d2
    lsl.w   #5,%d2
    or.w    %d2,%d1
    lsl.w   #5,%d2
    or.w    %d2,%d1
    move.w  %d1,(%a1)+                  /* pen 4 white */
    move.w  #0,(%a1)+
    move.w  #0,(%a1)+
    move.w  #0,(%a1)+
    addq.w  #1,%d0
    cmp.w   #32,%d0
    jne     pco_p
    move.b  #L_SCRNON,(%a0)
    SAY     s_co_t, 0, 0, A_WHITE
    move.w  #(ORG - 2),%d6              /* line of level 1 */
    moveq   #1,%d5                      /* level */
pco_l:
    move.w  %d6,%d4
    moveq   #2,%d3
    move.w  #A_WHITE,%d2
    bsr     prh
    move.w  %d5,%d2
    moveq   #11,%d0
    lsl.w   %d0,%d2                     /* attribute = set (level) */
    move.w  %d6,%d4
    add.w   #3*CHARSTEP,%d4
    move.w  #0x07f0,%d0
    bsr     pco_bar
    move.w  #0x07f1,%d0
    bsr     pco_bar
    move.w  #0x07f2,%d0
    bsr     pco_bar
    move.w  #0x07f3,%d0
    bsr     pco_bar
    subq.w  #1,%d6
    addq.w  #1,%d5
    cmp.w   #32,%d5
    jne     pco_l
    SAY     s_exit, 34, 0, A_WHITE
pco_w:
    bsr     wait_frame
    bsr     read_inp
    btst    #5,IN_EDGE+1
    jeq     pco_w
    bsr     wait_release
    rts
/* 6 cells of solid tile D0 with attribute D2 at D4 (D4 moves on) */
pco_bar:
    moveq   #5,%d1
pcb_1:
    move.w  %d4,(%a3)
    move.w  %d0,%d3
    or.w    %d2,%d3
    move.w  %d3,(%a4)
    add.w   #CHARSTEP,%d4
    dbra    %d1,pcb_1
    rts

/* ============================ tile viewers ============================= */
pg_txview:
    move.w  #0,VLAY
    jra     pv_go
pg_fgview:
    move.w  #1,VLAY
    jra     pv_go
pg_bgview:
    move.w  #2,VLAY
pv_go:
    move.w  #0,PG
    move.w  #0,VCOL
    bsr     page_init
    bsr     pv_setcol
pv_draw:
    bsr     pv_page
pv_loop:
    bsr     wait_frame
    bsr     read_inp
    move.w  IN_EDGE,%d0
    btst    #5,%d0
    jne     pv_exit
    btst    #4,%d0
    jeq     pv_nb1
    bsr     pv_nextcol
    jra     pv_draw
pv_nb1:
    move.w  PG,%d1
    btst    #0,%d0
    jeq     pv_1
    subq.w  #1,%d1
pv_1:
    btst    #1,%d0
    jeq     pv_2
    addq.w  #1,%d1
pv_2:
    btst    #2,%d0
    jeq     pv_3
    sub.w   #16,%d1
pv_3:
    btst    #3,%d0
    jeq     pv_4
    add.w   #16,%d1
pv_4:
    bsr     pv_pages                    /* D2 = number of pages (a power of two) */
    subq.w  #1,%d2
    and.w   %d2,%d1                     /* wrap both ways */
    cmp.w   PG,%d1
    jeq     pv_loop
    move.w  %d1,PG
    jra     pv_draw
pv_exit:
    bsr     wait_release
    rts

/* D2 = pages of 256 tiles for the current layer */
pv_pages:
    moveq   #8,%d2                      /* text: 2048 */
    cmpi.w  #1,VLAY
    jne     pvp_1
    moveq   #32,%d2                     /* FG: 8192 (two ROM banks) */
pvp_1:
    cmpi.w  #2,VLAY
    jne     pvp_2
    moveq   #16,%d2                     /* BG: 4096 */
pvp_2:
    rts

/* draw page PG of layer VLAY: 16 rows of 16 tiles, lines 4-19 */
pv_page:
    move.w  VLAY,%d0
    lsl.w   #2,%d0
    lea     pv_titles,%a1
    movea.l (%a1,%d0.w),%a2
    TXY     0, 0
    move.w  #A_YELLOW,%d2
    bsr     prs
    add.w   #CHARSTEP,%d4
    move.w  PG,%d5
    lsl.w   #8,%d5                      /* first tile */
    moveq   #4,%d3
    move.w  #A_WHITE,%d2
    bsr     prh
    SAY     s_pv_h1, 1, 0, A_GREY
    SAY     s_pv_h2, 2, 0, A_GREY
    bsr     pv_colname
/* FG ROM bank for tiles 4096-8191 */
    move.b  #L_FGBANK0,(%a0)
    cmpi.w  #1,VLAY
    jne     pvg_0
    cmpi.w  #16,PG
    jcs     pvg_0
    move.b  #L_FGBANK0+1,(%a0)
pvg_0:
    move.w  PG,%d6
    lsl.w   #8,%d6                      /* D6 = tile number */
    moveq   #0,%d5                      /* row */
pvg_row:
    /* row label */
    move.w  #(ORG - 4),%d4
    sub.w   %d5,%d4
    move.l  %d5,-(%sp)
    move.w  %d6,%d5
    moveq   #4,%d3
    move.w  #A_GREY,%d2
    bsr     prh
    move.l  (%sp)+,%d5
    /* 16 tiles at characters 5-20 */
    move.w  #(ORG - 4 + 5*CHARSTEP),%d4
    sub.w   %d5,%d4
    moveq   #15,%d1
pvg_col:
    move.w  %d6,%d0
    and.w   #0x0fff,%d0
    move.w  VLAY,%d2
    jne     pvg_fgbg
    and.w   #0x07ff,%d0
    or.w    #A_PLANES,%d0
    move.w  %d4,(%a3)
    move.w  %d0,(%a4)
    jra     pvg_next
pvg_fgbg:
    cmp.w   #1,%d2
    jne     pvg_bg
    move.w  %d4,FGOFFS
    move.w  %d0,FGDATA
    jra     pvg_next
pvg_bg:
    move.w  %d4,BGOFFS
    move.w  %d0,BGDATA
pvg_next:
    add.w   #CHARSTEP,%d4
    addq.w  #1,%d6
    dbra    %d1,pvg_col
    addq.w  #1,%d5
    cmp.w   #16,%d5
    jne     pvg_row
    rts

/* --------------------------- viewer colours ---------------------------- */
/* B1: next game colour set of this layer, after the last one the plane
 * colours, then set 0 again */
pv_nextcol:
    bsr     pv_nsets                    /* D2 = sets of this layer */
    move.w  VCOL,%d1
    addq.w  #1,%d1
    cmp.w   %d2,%d1
    jcs     pnc_1
    moveq   #-1,%d1
pnc_1:
    move.w  %d1,VCOL
    bsr     pv_setcol
    rts

/* D2 = colour sets: text 32, FG 16, BG 16, sprites 64 */
pv_nsets:
    moveq   #32,%d2
    move.w  VLAY,%d0
    jeq     pns_1
    moveq   #16,%d2
    cmp.w   #3,%d0
    jne     pns_1
    moveq   #64,%d2
pns_1:
    rts

/* load the viewer's colour set: game set VCOL from gamepal, or plane colours.
 * Text uses its set 3, FG / BG / sprites their set 0. Palette RAM is written
 * with the screen off (as the game does). */
pv_setcol:
    move.b  #L_SCRNOFF,(%a0)
    move.w  VLAY,%d0
    lea     PAL_TXT3,%a1                /* destination */
    move.w  #1536,%d3                   /* first game entry of this layer */
    moveq   #8,%d4                      /* entries per set */
    cmp.w   #1,%d0
    jne     psc_a
    lea     PAL_FG0,%a1
    move.w  #1280,%d3
    moveq   #16,%d4
psc_a:
    cmp.w   #2,%d0
    jne     psc_b
    lea     PAL_BG0,%a1
    move.w  #1024,%d3
    moveq   #16,%d4
psc_b:
    cmp.w   #3,%d0
    jne     psc_c
    lea     PAL_SPR0,%a1
    moveq   #0,%d3
    moveq   #16,%d4
psc_c:
    move.w  VCOL,%d1
    jmi     psc_planes
    mulu.w  %d4,%d1
    add.w   %d1,%d3
    add.w   %d3,%d3
    lea     gamepal,%a2
    adda.w  %d3,%a2
    subq.w  #1,%d4
psc_g:
    move.w  (%a2)+,(%a1)+
    dbra    %d4,psc_g
    jra     psc_done
psc_planes:
    moveq   #0,%d0
psc_p:
    cmp.w   #8,%d4
    jne     psc_p4
    bsr     plane_col3
    jra     psc_p5
psc_p4:
    bsr     plane_col4
psc_p5:
    move.w  %d1,(%a1)+
    addq.w  #1,%d0
    cmp.w   %d4,%d0
    jne     psc_p
psc_done:
    move.b  #L_SCRNON,(%a0)
    rts

/* "COLOUR xx" or "PLANES   " after the title on line 0 */
pv_colname:
    move.w  VCOL,%d5
    jmi     pcn_p
    SAY     s_pv_col, 0, 16, A_WHITE
    moveq   #0,%d5
    move.w  VCOL,%d5
    move.w  #(ORG - 0 + 23*CHARSTEP),%d4
    moveq   #2,%d3
    move.w  #A_WHITE,%d2
    bsr     prh
    rts
pcn_p:
    SAY     s_pv_pl, 0, 16, A_WHITE
    rts

/* =========================== sprite viewer ============================= */
/* 64 sprites per page, 8 x 8, each 16x16 = 2 x 2 text cells; row labels on
 * the left. Sprite RAM is written in bursts right after VBLANK ends. */
pg_sprview:
    move.w  #0,PG
    move.w  #3,VLAY
    move.w  #0,VCOL
    bsr     page_init
    bsr     pv_setcol
psv_draw:
    TXY     0, 0
    lea     s_ps_t,%a2
    move.w  #A_YELLOW,%d2
    bsr     prs
    add.w   #CHARSTEP,%d4
    move.w  PG,%d5
    lsl.w   #6,%d5
    moveq   #4,%d3
    move.w  #A_WHITE,%d2
    bsr     prh
    SAY     s_pv_h1, 1, 0, A_GREY
    SAY     s_pv_h2, 2, 0, A_GREY
    bsr     pv_colname
/* labels: first sprite of each row, at lines 4, 6, ... 18 */
    move.w  PG,%d6
    lsl.w   #6,%d6
    moveq   #0,%d0
psv_lab:
    move.w  %d0,%d4
    add.w   %d4,%d4
    neg.w   %d4
    add.w   #(ORG - 4),%d4
    move.l  %d0,-(%sp)
    move.w  %d6,%d5
    moveq   #4,%d3
    move.w  #A_GREY,%d2
    bsr     prh
    move.l  (%sp)+,%d0
    addq.w  #8,%d6
    addq.w  #1,%d0
    cmp.w   #8,%d0
    jne     psv_lab
/* build the 64 sprite entries: code, attr (priority 3, colour set 0), X, Y */
    bsr     wait_frame
    lea     SPR_BASE,%a1
    move.w  PG,%d6
    lsl.w   #6,%d6                      /* sprite code */
    moveq   #0,%d5                      /* row 0-7 */
psv_r:
    moveq   #0,%d1                      /* column 0-7 */
psv_c:
    move.w  %d6,(%a1)+
    move.w  #0x0c00,(%a1)+
    /* X: top line 4 + 2*row -> 326 - 8*(4 + 2*row) = 294 - 16*row */
    move.w  %d5,%d0
    lsl.w   #4,%d0
    neg.w   %d0
    add.w   #294,%d0
    lsl.w   #7,%d0
    move.w  %d0,(%a1)+
    /* Y: left character 5 + 2*column -> 24 + 8*(5 + 2*column) = 64 + 16*column */
    move.w  %d1,%d0
    lsl.w   #4,%d0
    add.w   #64,%d0
    lsl.w   #7,%d0
    move.w  %d0,(%a1)+
    addq.w  #1,%d6
    addq.w  #1,%d1
    cmp.w   #8,%d1
    jne     psv_c
    addq.w  #1,%d5
    cmp.w   #8,%d5
    jne     psv_r
psv_loop:
    bsr     wait_frame
    bsr     read_inp
    move.w  IN_EDGE,%d0
    btst    #5,%d0
    jne     psv_exit
    btst    #4,%d0
    jeq     psv_nb1
    bsr     pv_nextcol
    bsr     pv_colname
    jra     psv_loop
psv_nb1:
    move.w  PG,%d1
    btst    #0,%d0
    jeq     psv_1
    subq.w  #1,%d1
psv_1:
    btst    #1,%d0
    jeq     psv_2
    addq.w  #1,%d1
psv_2:
    btst    #2,%d0
    jeq     psv_3
    sub.w   #8,%d1
psv_3:
    btst    #3,%d0
    jeq     psv_4
    addq.w  #8,%d1
psv_4:
    and.w   #31,%d1                     /* 32 pages of 64 = 2048 sprites */
    cmp.w   PG,%d1
    jeq     psv_loop
    move.w  %d1,PG
    jra     psv_draw
psv_exit:
    moveq   #0,%d2
    SPRWR   0
    bsr     wait_release
    rts

/* (Re)start the Z80 the way stage 5 does, so it answers commands and copies
 * its inputs: reset, release, wait for its FF, idle FF, start signal AA, then
 * give it time for its own ROM sum. D0 = 0 if it came up, 1 if not.
 * The RAM loop menu leaves it waiting for AA (it must run to grant its bus),
 * which is why the pages that need it call this. Uses D0,D7. */
z80_start:
/* shared RAM may only be touched while the Z80 runs (it must grant its bus),
 * so: restart it, let it reach its wait-for-AA loop (it then only reads
 * $8001), clear $8000, and restart it again to watch its first FF */
    move.b  #L_SNDRST0,(%a0)
    DELAY   0x1000
    move.b  #L_SNDRUN,(%a0)
    DELAY   0x2000
    clr.w   SHR_BASE
    move.b  #L_SNDRST0,(%a0)
    DELAY   0x1000
    move.b  #L_SNDRUN,(%a0)
    move.l  #Z_TMO,%d7
zs_w:
    cmpi.b  #0xff,SHR_BASE+1
    jeq     zs_up
    subq.l  #1,%d7
    jne     zs_w
    moveq   #1,%d0
    rts
zs_up:
    move.w  #0x00ff,SHR_BASE
    move.w  #0x00aa,SHR_BASE+2
    DELAY   Z_SUMDLY
    moveq   #0,%d0
    cmpi.b  #0x00,SHR_BASE+1            /* 00 = its ROM sum failed */
    jne     zs_ok
    moveq   #1,%d0
zs_ok:
    rts

/* ============================= scroll test ============================= */
/* Modelled on the Shinobi test ROM's scroll test. One scroll register at a
 * time: TEXT X, TEXT Y, FG X, FG Y, BG X, BG Y (up/down). The layer under
 * test shows a ruler; the value is shown in hex and binary.
 *   AUTO  +1 pixel every 2 frames: the ruler must glide without steps/jumps
 *   STEP  left/right move exactly 1 pixel (hold to repeat)
 *   BIT   left/right pick a bit; it is switched on and off every half second
 *         and the layer must jump by exactly 2^bit pixels
 * B1 = next mode, B2 = exit. The X registers move the picture up/down on the
 * rotated monitor, the Y registers left/right. X has 9 bits (512 pixels); Y
 * has 9 for FG/BG (64 tiles high) and 8 for text (32 tiles high). */
    .equ SC_SEL,    0x033f90               /* 0-5: layer*2 + axis */
    .equ SC_MODE,   0x033f92               /* 0 auto, 1 step, 2 bit */
    .equ SC_BIT,    0x033f94
    .equ SC_VAL,    0x033f96               /* value written to the register */
    .equ SC_TMR,    0x033f98
    .equ SC_REP,    0x033f9a               /* STEP auto-repeat */
    .equ SC_FLIP,   0x033f9c               /* BIT: bit currently set */

pg_scroll:
    move.w  #2,SC_SEL                   /* start with FG X */
    move.w  #0,SC_MODE
    move.w  #3,SC_BIT
psc_new:
    bsr     page_init
    bsr     sc_rulpal
    bsr     sc_default                  /* SC_VAL = the layer's normal value */
    move.w  SC_SEL,%d0
    lsr.w   #1,%d0                      /* layer */
    move.w  SC_SEL,%d7
    and.w   #1,%d7                      /* axis */
    tst.w   %d0
    jne     psc_nt
/* text under test: digit ruler in the text layer, colour ruler in FG as a
 * fixed reference behind it */
    bsr     sc_txruler
    lea     FGOFFS,%a1
    lea     FGDATA,%a2
    move.w  #FG_SOLID,%d6
    movea.w #FG_LINE,%a5
    bsr     sc_colruler
    jra     psc_panel
psc_nt:
    lea     FGOFFS,%a1
    lea     FGDATA,%a2
    move.w  #FG_SOLID,%d6
    movea.w #FG_LINE,%a5
    cmp.w   #1,%d0
    jeq     psc_nt2
    lea     BGOFFS,%a1
    lea     BGDATA,%a2
    move.w  #BG_SOLID,%d6
    movea.w #BG_LINE,%a5
psc_nt2:
    bsr     sc_colruler
psc_panel:
    bsr     sc_blackout
    move.w  #1,PRSBG
    bsr     sc_static
    move.w  #0,SC_TMR
    move.w  #0,SC_REP
    move.w  #0,SC_FLIP
    move.w  SC_VAL,SC_BASE
psc_loop:
    bsr     wait_frame
    bsr     read_inp
    move.w  IN_EDGE,%d0
    btst    #5,%d0
    jne     psc_exit
/* up/down: next / previous register */
    move.w  SC_SEL,%d1
    btst    #0,%d0
    jeq     psc_u
    subq.w  #1,%d1
    jpl     psc_u
    moveq   #5,%d1
psc_u:
    btst    #1,%d0
    jeq     psc_d
    addq.w  #1,%d1
    cmp.w   #6,%d1
    jcs     psc_d
    moveq   #0,%d1
psc_d:
    cmp.w   SC_SEL,%d1
    jeq     psc_m
    move.w  %d1,SC_SEL
    jra     psc_new
/* B1: next mode */
psc_m:
    btst    #4,%d0
    jeq     psc_run
    move.w  SC_MODE,%d1
    addq.w  #1,%d1
    cmp.w   #3,%d1
    jcs     psc_m2
    moveq   #0,%d1
psc_m2:
    move.w  %d1,SC_MODE
    move.w  SC_VAL,SC_BASE
    move.w  #0,SC_FLIP
    bsr     sc_static
    jra     psc_loop
psc_run:
    move.w  SC_MODE,%d1
    jeq     psc_auto
    cmp.w   #1,%d1
    jeq     psc_step
/* BIT: left/right choose the bit; toggle it every 30 frames */
    bsr     sc_nbits                    /* D2 = bits */
    move.w  SC_BIT,%d1
    btst    #2,%d0
    jeq     psb_1
    addq.w  #1,%d1                      /* left = higher bit (it reads left to right) */
psb_1:
    btst    #3,%d0
    jeq     psb_2
    subq.w  #1,%d1
psb_2:
    tst.w   %d1
    jpl     psb_3
    move.w  %d2,%d1
    subq.w  #1,%d1
psb_3:
    cmp.w   %d2,%d1
    jcs     psb_4
    moveq   #0,%d1
psb_4:
    cmp.w   SC_BIT,%d1
    jeq     psb_5
    move.w  %d1,SC_BIT
    move.w  #0,SC_FLIP
    move.w  #0,SC_TMR
    bsr     sc_static
psb_5:
    addq.w  #1,SC_TMR
    cmpi.w  #30,SC_TMR
    jcs     psb_6
    move.w  #0,SC_TMR
    eori.w  #1,SC_FLIP
psb_6:
    move.w  SC_BASE,%d1
    move.w  SC_BIT,%d2
    bclr    %d2,%d1
    tst.w   SC_FLIP
    jeq     psb_7
    bset    %d2,%d1
psb_7:
    move.w  %d1,SC_VAL
    jra     psc_write
psc_auto:
    addq.w  #1,SC_TMR
    btst    #0,SC_TMR+1
    jne     psc_write
    addq.w  #1,SC_VAL
    jra     psc_write
/* STEP: one pixel per press; held for 20 frames it repeats every 3 */
psc_step:
    move.w  IN_CUR,%d1
    and.w   #(K_LEFT+K_RIGHT),%d1
    jne     pst_held
    move.w  #0,SC_REP
    jra     psc_write
pst_held:
    addq.w  #1,SC_REP
    cmpi.w  #1,SC_REP
    jeq     pst_go
    cmpi.w  #20,SC_REP
    jcs     psc_write
    move.w  #17,SC_REP
pst_go:
    btst    #2,%d1
    jeq     pst_2
    subq.w  #1,SC_VAL
pst_2:
    btst    #3,%d1
    jeq     psc_write
    addq.w  #1,SC_VAL
psc_write:
    bsr     sc_nbits
    moveq   #1,%d1
    lsl.w   %d2,%d1
    subq.w  #1,%d1
    and.w   %d1,SC_VAL
    bsr     sc_reg                      /* A1 = the register */
    move.w  SC_VAL,(%a1)
    cmpi.w  #2,SC_SEL
    jcc     psw_v                       /* not the text layer */
    bsr     sc_follow
psw_v:
    bsr     sc_value
    jra     psc_loop
psc_exit:
    bsr     wait_release
    rts

    .equ SC_BASE,   0x033f9e

/* text tests: when the scroll has moved a whole tile, redraw the ruler and
 * the panel one tile further the other way, so the panel stays in place
 * (apart from the 0-7 pixel fine scroll, which can't be undone in software) */
sc_follow:
/* the shift is the tile the value is in (value / 8) minus the normal one, so
 * the low 3 bits (fine scroll) never move the panel - otherwise BIT mode on
 * bits 0-2 would make it jump a whole tile whenever the toggle crosses a
 * multiple of 8 */
    move.w  SC_VAL,%d0
    move.w  SC_SEL,%d1
    jne     sfl_y
    lsr.w   #3,%d0
    sub.w   #(SCR_X >> 3),%d0
    and.w   #63,%d0
    cmp.w   PANC,%d0
    jeq     sfl_done
    move.w  %d0,PANC
    jra     sfl_redraw
sfl_y:
    lsr.w   #3,%d0
    sub.w   #(SCR_Y >> 3),%d0
    and.w   #31,%d0
    cmp.w   PANR,%d0
    jeq     sfl_done
    move.w  %d0,PANR
sfl_redraw:
    move.w  SC_SEL,%d7
    and.w   #1,%d7
    bsr     sc_txruler
    bsr     sc_blackout
    bsr     sc_static
sfl_done:
    rts

/* D2 = bits of the selected register (text Y: 8, others 9) */
sc_nbits:
    moveq   #9,%d2
    cmpi.w  #1,SC_SEL
    jne     snb_1
    moveq   #8,%d2
snb_1:
    rts

/* A1 = the selected scroll register */
sc_reg:
    move.w  SC_SEL,%d0
    lea     TXSCROLL,%a1
    cmp.w   #2,%d0
    jcs     srg_1
    lea     0x074000,%a1
    cmp.w   #4,%d0
    jcs     srg_1
    lea     0x072000,%a1
srg_1:
    btst    #0,%d0
    jeq     srg_2
    addq.l  #2,%a1
srg_2:
    rts

/* SC_VAL = the normal value of the selected register (the value page_init
 * wrote, so the rulers line up with the panel) */
sc_default:
    move.w  #SCR_X,SC_VAL
    move.w  SC_SEL,%d0
    btst    #0,%d0
    jeq     sdf_1
    move.w  #SCR_Y64,SC_VAL
    cmp.w   #1,%d0
    jne     sdf_1
    move.w  #SCR_Y,SC_VAL
sdf_1:
    rts

/* Ruler colours for FG and BG. Along the tested direction the layer is cut
 * into blocks of 8 tiles; block n has colour n (8 colours, so the pattern
 * repeats only after 64 tiles = 512 pixels), tiles inside a block alternate
 * light / dark, and the first tile of each block is a light grey line. Nothing
 * changes across the other direction, so every jump - 8 px up to 256 px -
 * shows as movement along the tested direction only.
 * Colour set = block*2 + (tile & 1). The main solid tile is one pen, the
 * white-line tile another pen: all pens of a set get the block colour, the
 * line tile's pen gets white. */
    .equ FG_LINE,   31                     /* solid FG tile, pen 4 (main FG_SOLID = pen 7) */
    .equ FG_LPEN,   4
    .equ BG_LINE,   112                    /* solid BG tile, pen 12 (main BG_SOLID = pen 9) */
    .equ BG_LPEN,   12
sc_rulpal:
    move.b  #L_SCRNOFF,(%a0)
    lea     PAL_FG0,%a1
    moveq   #FG_LPEN,%d3
    bsr     srp_one
    lea     PAL_BG0,%a1
    moveq   #BG_LPEN,%d3
    bsr     srp_one
    move.b  #L_SCRNON,(%a0)
    rts
/* 16 sets of 16 pens at A1; D3 = the white-line pen */
srp_one:
    lea     sc_cols,%a2
    moveq   #0,%d1                      /* set */
srp_s:
    move.w  (%a2)+,%d0                  /* colour of this set */
    moveq   #0,%d2                      /* pen */
srp_p:
    cmp.w   %d3,%d2
    jne     srp_c
    move.w  #0x35ad,(%a1)+              /* the line: light grey, so panel text over it still reads */
    jra     srp_n
srp_c:
    move.w  %d0,(%a1)+
srp_n:
    addq.w  #1,%d2
    cmp.w   #16,%d2
    jne     srp_p
    addq.w  #1,%d1
    cmp.w   #16,%d1
    jne     srp_s
    rts

/* fill a 64x64 layer (A1 offset reg, A2 data port) with the ruler for axis
 * D7 (0 X, 1 Y); D6 = main solid tile, A5 = white-line tile */
sc_colruler:
    moveq   #0,%d5
scr_1:
    move.w  %d5,%d1
    and.w   #63,%d1                     /* column */
    tst.w   %d7
    jeq     scr_2
    move.w  %d5,%d1
    lsr.w   #6,%d1                      /* Y: the row is the key */
scr_2:
    move.w  %d1,%d3
    lsr.w   #3,%d3
    and.w   #7,%d3                      /* block */
    add.w   %d3,%d3
    move.w  %d1,%d0
    and.w   #1,%d0
    or.w    %d0,%d3                     /* set = block*2 + (key & 1) */
    moveq   #12,%d0
    lsl.w   %d0,%d3
    move.w  %d1,%d0
    and.w   #7,%d0
    jne     scr_3
    move.w  %a5,%d0                     /* first tile of a block: white line */
    or.w    %d0,%d3
    jra     scr_4
scr_3:
    or.w    %d6,%d3
scr_4:
    move.w  %d5,(%a1)
    move.w  %d3,(%a2)
    addq.w  #1,%d5
    cmp.w   #4096,%d5
    jne     scr_1
    rts

/* digit ruler in the text layer for axis D7: X = every cell shows its
 * column's low digit (even rows) or high digit (odd rows); Y = its row's.
 * Every 8th column / row yellow. */
sc_txruler:
    moveq   #0,%d5
str_1:
    move.w  %d5,%d1
    and.w   #63,%d1                     /* column */
    move.w  %d5,%d2
    lsr.w   #6,%d2                      /* row */
    tst.w   %d7
    jeq     str_2
    exg     %d1,%d2
str_2:
    move.w  %d1,%d0                     /* key */
    btst    #0,%d2
    jeq     str_3
    lsr.w   #4,%d0
str_3:
    and.w   #15,%d0                     /* digit = tile */
    move.w  %d1,%d3
    and.w   #7,%d3
    jne     str_4
    or.w    #A_YELLOW,%d0
str_4:
    move.w  %d5,(%a3)
    move.w  %d0,(%a4)
    addq.w  #1,%d5
    cmp.w   #TX_WORDS,%d5
    jne     str_1
    rts

/* black blocks over the whole width of the panel lines, so the panel reads
 * over the moving ruler */
sc_blackout:
    lea     sc_plines,%a1
sbo_1:
    move.w  (%a1)+,%d4
    jmi     sbo_3
    moveq   #29,%d1
sbo_2:
    move.w  #(A_BLACK + 0x07f6),%d0
    bsr     tx_put
    add.w   #CHARSTEP,%d4
    dbra    %d1,sbo_2
    jra     sbo_1
sbo_3:
    rts

/* the panel: lines 0-5 and the help at the bottom */
sc_static:
    SAY     s_sc_t, 0, 0, A_YELLOW
    SAY     s_sc_l, 1, 0, A_WHITE
    move.w  SC_SEL,%d0
    lsl.w   #2,%d0
    lea     sc_names,%a1
    movea.l (%a1,%d0.w),%a2
    TXY     1, 7
    move.w  #A_YELLOW,%d2
    bsr     prs
    SAY     s_sc_m, 2, 0, A_WHITE
    move.w  SC_MODE,%d0
    lsl.w   #2,%d0
    lea     sc_modes,%a1
    movea.l (%a1,%d0.w),%a2
    TXY     2, 7
    move.w  #A_YELLOW,%d2
    bsr     prs
    SAY     s_sc_v, 3, 0, A_WHITE
    SAY     s_sc_b, 3, 11, A_WHITE
/* bit numbers under the binary value (8 or 9 bits, right-aligned) */
    bsr     sc_nbits
    lea     s_sc_bits9,%a2              /* " 876543210" for 9 bits */
    cmp.w   #9,%d2
    jeq     sst_1
    lea     s_sc_bits8,%a2              /* "  76543210" for 8 bits */
sst_1:
    TXY     4, 17
    move.w  #A_GREY,%d2
    bsr     prs
/* BIT mode: how far it should jump */
    SAY     s_sc_blank, 5, 0, A_WHITE
    cmpi.w  #2,SC_MODE
    jne     sst_2
    SAY     s_sc_bit, 5, 0, A_WHITE
    moveq   #0,%d5
    move.w  SC_BIT,%d5
    TXY     5, 4
    moveq   #1,%d3
    move.w  #A_YELLOW,%d2
    bsr     prh
    SAY     s_sc_jump, 5, 6, A_WHITE
    move.w  SC_BIT,%d0
    lsl.w   #2,%d0
    lea     sc_px,%a1
    movea.l (%a1,%d0.w),%a2
    TXY     5, 19
    move.w  #A_YELLOW,%d2
    bsr     prs
sst_2:
    SAY     s_sc_h1, 35, 0, A_GREY
    SAY     s_sc_h2, 36, 0, A_GREY
    SAY     s_sc_h3, 37, 0, A_GREY
    rts

/* "VALUE 0C8" and the binary, the selected bit yellow in BIT mode */
sc_value:
    moveq   #0,%d5
    move.w  SC_VAL,%d5
    TXY     3, 6
    moveq   #3,%d3
    move.w  #A_YELLOW,%d2
    bsr     prh
    bsr     sc_nbits                    /* D2 = bits */
    move.w  %d2,%d6
    move.w  #(ORG - 3 + (27)*CHARSTEP),%d4   /* right-aligned: ends at character 26 */
    move.w  %d6,%d0
    mulu.w  #CHARSTEP,%d0
    sub.w   %d0,%d4
    subq.w  #1,%d6                      /* highest bit first */
svl_1:
    move.w  #0x0000,%d0                 /* "0" */
    btst    %d6,%d5
    jeq     svl_2
    moveq   #1,%d0                      /* "1" */
svl_2:
    move.w  #A_WHITE,%d1
    cmpi.w  #2,SC_MODE
    jne     svl_3
    cmp.w   SC_BIT,%d6
    jne     svl_3
    move.w  #A_YELLOW,%d1
svl_3:
    or.w    %d1,%d0
    bsr     tx_put
    add.w   #CHARSTEP,%d4
    dbra    %d6,svl_1
    rts

    .even
sc_cols:                                /* per set: block colour, dark / light (dimmed so text reads) */
    .short  0x000a, 0x0012                  /* red */
    .short  0x00aa, 0x0132                  /* orange */
    .short  0x014a, 0x0252                  /* yellow */
    .short  0x0140, 0x0240                  /* green */
    .short  0x2940, 0x4a40                  /* cyan */
    .short  0x2800, 0x4800                  /* blue */
    .short  0x280a, 0x4812                  /* magenta */
    .short  0x14a5, 0x294a                  /* grey */
sc_plines:                              /* text offsets of the panel lines */
    .short  (ORG - 0), (ORG - 1), (ORG - 2), (ORG - 3), (ORG - 4), (ORG - 5)
    .short  (ORG - 35), (ORG - 36), (ORG - 37), -1
sc_names:
    .long   s_scn0, s_scn1, s_scn2, s_scn3, s_scn4, s_scn5
sc_modes:
    .long   s_scm0, s_scm1, s_scm2
sc_px:
    .long   s_px0, s_px1, s_px2, s_px3, s_px4, s_px5, s_px6, s_px7, s_px8

/* ============================= sound test ============================== */
/* Sends a code to the Z80 the way the game does: write it to its $8000
 * ($7A001) and wait for it to answer FF. 01-25 are sounds/music (bits 6-7
 * pick the channel group), FE stops everything. */
pg_sound:
    bsr     page_init
    move.w  #0x0001,SCODE
    SAY     s_so_t, 0, 0, A_YELLOW
    SAY     s_zwait, 12, 0, A_GREY
    bsr     z80_start
    tst.w   %d0
    jeq     pso_up
    SAY     s_zdead, 12, 0, A_YELLOW
    jra     pso_up2
pso_up:
    SAY     s_zok, 12, 0, A_GREY
pso_up2:
    SAY     s_so_c, 3, 0, A_WHITE
    SAY     s_so_h1, 6, 0, A_GREY
    SAY     s_so_h2, 7, 0, A_GREY
    SAY     s_so_h3, 8, 0, A_GREY
pso_show:
    moveq   #0,%d5
    move.w  SCODE,%d5
    move.w  #(ORG - 3 + 5*CHARSTEP),%d4
    moveq   #2,%d3
    move.w  #A_YELLOW,%d2
    bsr     prh
pso_loop:
    bsr     wait_frame
    bsr     read_inp
    move.w  IN_EDGE,%d0
    move.w  SCODE,%d1
    btst    #0,%d0
    jeq     pso_1
    addq.w  #1,%d1
pso_1:
    btst    #1,%d0
    jeq     pso_2
    subq.w  #1,%d1
pso_2:
    btst    #3,%d0
    jeq     pso_3
    add.w   #0x10,%d1
pso_3:
    btst    #2,%d0
    jeq     pso_4
    sub.w   #0x10,%d1
pso_4:
    and.w   #0xff,%d1
    btst    #4,%d0
    jne     pso_play
    btst    #5,%d0
    jne     pso_exit
    cmp.w   SCODE,%d1
    jeq     pso_loop
    move.w  %d1,SCODE
    jra     pso_show
pso_play:
    move.w  SCODE,%d1
    bsr     snd_send
    jra     pso_loop
pso_exit:
    move.w  #0x00fe,%d1                 /* stop all sound */
    bsr     snd_send
    bsr     wait_release
    rts
/* send code D1, show "SENT xx OK" or "SENT xx NO REPLY" on line 10 */
snd_send:
    SAY     s_so_sent, 10, 0, A_WHITE
    moveq   #0,%d5
    move.w  %d1,%d5
    move.w  #(ORG - 10 + 5*CHARSTEP),%d4
    moveq   #2,%d3
    move.w  #A_WHITE,%d2
    bsr     prh
    move.w  %d1,SHR_BASE
    move.l  #0x00020000,%d7
sns_w:
    cmpi.b  #0xff,SHR_BASE+1
    jeq     sns_ok
    subq.l  #1,%d7
    jne     sns_w
    SAY     s_so_none, 10, 8, A_YELLOW
    rts
sns_ok:
    SAY     s_so_ok, 10, 8, A_WHITE
    rts

/* ------------------------------ jump table ----------------------------- */
    .include "gamepal.inc"
    .even
mm_jt:
    .long   pg_rerun, pg_loopmenu, pg_inputs, pg_colour, pg_txview
    .long   pg_fgview, pg_bgview, pg_sprview, pg_scroll, pg_sound
mm_str:
    .long   s_m_rerun, s_m_loop, s_m_in, s_m_col, s_m_tx
    .long   s_m_fg, s_m_bg, s_m_spr, s_m_scr, s_m_snd
pv_titles:
    .long   s_pv_tx, s_pv_fg, s_pv_bg
in_jn:
    .long   s_k_up, s_k_dn, s_k_lt, s_k_rt, s_k_b1, s_k_b2, 0
in_sn:
    .long   s_k_sv, s_k_tl, s_k_ts, s_k_c1, s_k_c2, s_k_s1, s_k_s2, 0

pg_rerun:
    jmp     _start
pg_loopmenu:
    lea     LATCH,%a0
    lea     TXOFFS,%a3
    lea     TXDATA,%a4
    bsr     page_init
    jra     menu                        /* register-only; B2 there comes back */

s_mtitle:  .asciz "TWIN COBRA DIAG  MENU"
s_mhelp:   .asciz "UP DOWN  B1 SELECT"
s_m_rerun: .asciz "RERUN ALL TESTS"
s_m_loop:  .asciz "RAM LOOP TEST"
s_m_in:    .asciz "INPUT AND DIP TEST"
s_m_col:   .asciz "COLOUR TEST"
s_m_tx:    .asciz "TEXT TILE VIEWER"
s_m_fg:    .asciz "FG TILE VIEWER"
s_m_bg:    .asciz "BG TILE VIEWER"
s_m_spr:   .asciz "SPRITE VIEWER"
s_m_scr:   .asciz "SCROLL TEST"
s_m_snd:   .asciz "SOUND TEST"
s_exit:    .asciz "B2 EXIT"
s_in_t:    .asciz "INPUT AND DIP TEST"
s_in_p1:   .asciz "P1"
s_in_p2:   .asciz "P2"
s_in_sy:   .asciz "SYS"
s_in_sy2:  .asciz "SYS IS READ BY THE SOUND CPU"
s_in_d1:   .asciz "DSW1"
s_in_d2:   .asciz "DSW2"
s_in_sw:   .asciz "     SWITCH 1 TO 8"
s_in_h:    .asciz "B1 AND B2 TOGETHER  EXIT"
s_k_up:    .asciz "UP"
s_k_dn:    .asciz "DN"
s_k_lt:    .asciz "LT"
s_k_rt:    .asciz "RT"
s_k_b1:    .asciz "B1"
s_k_b2:    .asciz "B2"
s_k_sv:    .asciz "SV"
s_k_tl:    .asciz "TL"
s_k_ts:    .asciz "TS"
s_k_c1:    .asciz "C1"
s_k_c2:    .asciz "C2"
s_k_s1:    .asciz "S1"
s_k_s2:    .asciz "S2"
s_co_t:    .asciz "COLOUR TEST  R  G  B  W"
s_pv_tx:   .asciz "TEXT TILES"
s_pv_fg:   .asciz "FG TILES"
s_pv_bg:   .asciz "BG TILES"
s_ps_t:    .asciz "SPRITES"
s_pv_h1:   .asciz "UP DOWN PAGE  LEFT RIGHT 16"
s_pv_h2:   .asciz "B1 COLOURS  B2 EXIT"
s_pv_col:  .asciz "COLOUR"
s_pv_pl:   .asciz "PLANES   "
s_so_t:    .asciz "SOUND TEST"
s_sc_t:    .asciz "SCROLL TEST"
s_sc_l:    .asciz "LAYER"
s_sc_m:    .asciz "MODE"
s_sc_v:    .asciz "VALUE"
s_sc_b:    .asciz "BINARY"
s_sc_bits9: .asciz " 876543210"
s_sc_bits8: .asciz "  76543210"
s_sc_blank: .asciz "                            "
s_sc_bit:  .asciz "BIT"
s_sc_jump: .asciz "SHOULD JUMP"
s_sc_h1:   .asciz "UP DOWN  LAYER   B1  MODE"
s_sc_h2:   .asciz "LEFT RIGHT  STEP OR BIT"
s_sc_h3:   .asciz "B2  EXIT"
s_scn0:    .asciz "TEXT X  UP DOWN     "
s_scn1:    .asciz "TEXT Y  LEFT RIGHT  "
s_scn2:    .asciz "FG X  UP DOWN       "
s_scn3:    .asciz "FG Y  LEFT RIGHT    "
s_scn4:    .asciz "BG X  UP DOWN       "
s_scn5:    .asciz "BG Y  LEFT RIGHT    "
s_scm0:    .asciz "AUTO "
s_scm1:    .asciz "STEP "
s_scm2:    .asciz "BIT  "
s_px0:     .asciz "1 PX  "
s_px1:     .asciz "2 PX  "
s_px2:     .asciz "4 PX  "
s_px3:     .asciz "8 PX  "
s_px4:     .asciz "16 PX "
s_px5:     .asciz "32 PX "
s_px6:     .asciz "64 PX "
s_px7:     .asciz "128 PX"
s_px8:     .asciz "256 PX"
s_so_c:    .asciz "CODE"
s_so_h1:   .asciz "UP DOWN 1  LEFT RIGHT 10"
s_so_h2:   .asciz "B1 PLAY"
s_so_h3:   .asciz "B2 STOP AND EXIT"
s_so_sent: .asciz "SENT"
s_so_ok:   .asciz "OK       "
s_so_none: .asciz "NO REPLY "
s_zwait:   .asciz "STARTING SOUND CPU     "
s_zok:     .asciz "SOUND CPU RUNNING      "
s_zdead:   .asciz "SOUND CPU NOT RUNNING  "
    .even
