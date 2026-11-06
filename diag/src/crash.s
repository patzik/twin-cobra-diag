/* ============================================================================
 * Twin Cobra crash catcher - patched into the GAME's own 27512 program pair
 *
 * The stock game points every 68000 exception vector at $100-$108, which hold
 * $4848 (an illegal opcode on a 68000). So any fault - bus error, address
 * error, illegal instruction - turns into an endless exception storm with the
 * screen still off: a black screen with every address line toggling.
 *
 * tools/mkcrash.py builds a copy of the game's 27512 pair with:
 *   - this handler placed in unused (FF) ROM space at $1A400,
 *   - exception vectors 2-63 pointed at it (except IRQ4 = the game's VBLANK
 *     handler and IRQ7, which keep their original targets),
 *   - 4 spare bytes per chip adjusted so the game's own ROM checksum
 *     ($25E54) still passes.
 * The game then runs exactly as before - until it crashes. The handler turns
 * the screen on and shows what happened:
 *
 *     GAME CRASHED
 *     ADDRESS ERROR
 *     PC 0201A6  SR 2700  VEC 03
 *     ACCESS 012345  SSW 0015      (bus / address error only)
 *     D0 xxxxxxxx  A0 xxxxxxxx    ... D7 / A7 (A7 = stack pointer)
 *     CODE xxxx xxxx xxxx xxxx     (the 4 words at PC)
 *     STACK ABOVE THE FRAME        (12 longs: saved registers, return addresses)
 *
 * Saved state lives at the top of work RAM ($33F00-$33F5F).
 * ============================================================================ */

    .include "video.inc"

    .equ SAVE,      0x033f00               /* D0-D7/A0-A6 (60 bytes) */
    .equ SAVE_SP,   0x033f3c               /* A7 at entry = the exception frame */
    .equ VECNO,     0x033f40               /* vector of the latest exception */
    .equ VEC1,      0x033f42               /* vector of the first one */
    .equ MAGIC,     0x033f44               /* 'CRSH' once the first one is saved */
    .equ NESTED,    0x033f48               /* exceptions after the first */
    .equ F_SR,      0x033f4a
    .equ F_PC,      0x033f4c
    .equ F_ACC,     0x033f50               /* bus/address error: access address */
    .equ F_SSW,     0x033f54               /*   special status word (R/W, FC) */
    .equ SAFE_SP,   0x033e00
    .equ CR_MAGIC,  0x43525348             /* 'CRSH' */

    .equ ORG,       0x0066                 /* same text layout as the diag */

    .text
/* ---- one 12-byte stub per vector 2-63; mkcrash.py relies on the layout ---- */
stubs:
    .irp n, 2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,56,57,58,59,60,61,62,63
    move.w  #\n,VECNO
    bra.w   common
    .endr

common:
    move.w  #0x2700,%sr
    cmpi.l  #CR_MAGIC,MAGIC
    jeq     again
/* first exception: keep everything */
    movem.l %d0-%d7/%a0-%a6,SAVE
    move.l  %sp,SAVE_SP
    move.w  VECNO,VEC1
    clr.w   NESTED
    move.l  #CR_MAGIC,MAGIC
    move.l  #0xffffffff,%d0
    move.l  %d0,F_PC
    move.l  %d0,F_ACC
    move.w  %d0,F_SR
    move.w  %d0,F_SSW
/* read the exception frame only if the stack pointer is sane (even, in work
 * RAM), so a wild stack can't fault again */
    move.l  %sp,%d0
    btst    #0,%d0
    jne     frame_done
    cmp.l   #0x030000,%d0
    jcs     frame_done
    cmp.l   #0x033ef0,%d0
    jhi     frame_done
    movea.l %d0,%a1
    move.w  VEC1,%d1
    cmp.w   #3,%d1
    jhi     frame_short
/* bus / address error: SSW, access address, IR, SR, PC */
    move.w  (%a1),F_SSW
    move.l  2(%a1),F_ACC
    move.w  8(%a1),F_SR
    move.l  10(%a1),F_PC
    jra     frame_done
frame_short:
    move.w  (%a1),F_SR
    move.l  2(%a1),F_PC
frame_done:
    jra     show
again:
    addq.w  #1,NESTED
show:
    movea.l #SAFE_SP,%sp

/* ---- bring the screen up the same way the diag does ---- */
    lea     LATCH,%a0
    move.b  #L_IRQOFF,(%a0)
    move.b  #L_DSP_OFF,(%a0)
    move.b  #L_DSPRST0,(%a0)
    move.b  #L_FLIP0,(%a0)
    move.b  #L_SCRNOFF,(%a0)
    VIDINIT

/* sprites are drawn over the text: turn them all off (sprite RAM = 0), in
 * short bursts right after VBLANK ends, as the game and the diag do */
    lea     0x040000,%a1
    moveq   #7,%d2
spc_chunk:
    move.l  #0x8000,%d7                 /* VBLANK wait with timeout */
spc_h:
    btst    #7,0x078009
    jne     spc_l
    subq.l  #1,%d7
    jne     spc_h
    jra     spc_go
spc_l:
    btst    #7,0x078009
    jeq     spc_go
    subq.l  #1,%d7
    jne     spc_l
spc_go:
    move.w  #255,%d0
spc_w:
    clr.w   (%a1)+
    dbra    %d0,spc_w
    dbra    %d2,spc_chunk

/* printing goes through two small subroutines (the stack was just reset to
 * SAFE_SP) to keep the handler inside the ROM's free space */
    .macro S lbl, off
    lea     \lbl,%a2
    move.w  #\off,%d4
    bsr     pstr
    .endm
    .macro H nd, off                    /* value in D5 */
    moveq   #\nd,%d3
    move.w  #\off,%d4
    bsr     phex
    .endm

    S       s_head, (ORG - 0)

/* exception name + vector number */
    move.w  VEC1,%d5
    lea     vnames,%a1
vn_loop:
    move.w  (%a1)+,%d0
    jmi     vn_default
    movea.l (%a1)+,%a2
    cmp.w   %d5,%d0
    jne     vn_loop
    jra     vn_print
vn_default:
    lea     s_exc,%a2
    cmp.w   #32,%d5
    jcs     vn_print
    cmp.w   #47,%d5
    jhi     vn_print
    lea     s_trap,%a2
vn_print:
    move.w  #(ORG - 2),%d4
    bsr     pstr

/* PC and SR */
    S       s_pc, (ORG - 3)
    move.l  F_PC,%d5
    H       6, (ORG - 3 + 3*CHARSTEP)
    S       s_sr, (ORG - 3 + 11*CHARSTEP)
    moveq   #0,%d5
    move.w  F_SR,%d5
    H       4, (ORG - 3 + 14*CHARSTEP)
    S       s_vec, (ORG - 3 + 20*CHARSTEP)
    moveq   #0,%d5
    move.w  VEC1,%d5
    H       2, (ORG - 3 + 24*CHARSTEP)

/* bus / address error extras */
    cmpi.w  #3,VEC1
    jhi     no_acc
    S       s_acc, (ORG - 4)
    move.l  F_ACC,%d5
    H       6, (ORG - 4 + 7*CHARSTEP)
    S       s_ssw, (ORG - 4 + 15*CHARSTEP)
    moveq   #0,%d5
    move.w  F_SSW,%d5
    H       4, (ORG - 4 + 19*CHARSTEP)
no_acc:

/* registers: D0-D7 left column, A0-A7 right column. SAVE holds D0-D7 then
 * A0-A6, and SAVE_SP (A7) follows A6 directly. */
    lea     SAVE,%a5
    move.w  #(ORG - 6),%d6              /* line */
    moveq   #0,%d2                      /* register number */
reg_loop:
    lea     s_d,%a2
    move.w  %d6,%d4
    bsr     pstr                        /* "D" */
    move.l  %d2,%d5
    moveq   #1,%d3
    bsr     phex                        /* n (D4 already moved on) */
    move.l  (%a5),%d5
    moveq   #8,%d3
    move.w  %d6,%d4
    add.w   #3*CHARSTEP,%d4
    bsr     phex
    lea     s_a,%a2
    move.w  %d6,%d4
    add.w   #13*CHARSTEP,%d4
    bsr     pstr                        /* "A" */
    move.l  %d2,%d5
    moveq   #1,%d3
    bsr     phex
    move.l  32(%a5),%d5
    moveq   #8,%d3
    move.w  %d6,%d4
    add.w   #16*CHARSTEP,%d4
    bsr     phex
    addq.l  #4,%a5
    subq.w  #1,%d6
    addq.w  #1,%d2
    cmp.w   #8,%d2
    jne     reg_loop

/* code words at PC (only if PC is even and inside ROM) */
    move.l  F_PC,%d0
    btst    #0,%d0
    jne     no_code
    cmp.l   #0x02fff8,%d0
    jhi     no_code
    S       s_code, (ORG - 15)
    movea.l F_PC,%a5
    move.w  #(ORG - 15 + 5*CHARSTEP),%d6
    moveq   #3,%d2
code_loop:
    moveq   #0,%d5
    move.w  (%a5)+,%d5
    moveq   #4,%d3
    move.w  %d6,%d4
    bsr     phex
    add.w   #5*CHARSTEP,%d6
    dbra    %d2,code_loop
no_code:

/* stack dump: 12 longs from just above the exception frame (what the
 * crashed code had on its stack: saved registers, return addresses), 3 per line.
 * Only if A7 was sane. */
    move.l  SAVE_SP,%d0
    btst    #0,%d0
    jne     no_stack
    cmp.l   #0x030000,%d0
    jcs     no_stack
    cmp.l   #0x033ec0,%d0
    jhi     no_stack
    S       s_stack, (ORG - 17)
    movea.l SAVE_SP,%a5
    lea     6(%a5),%a5                  /* skip the frame (SR + PC) */
    cmpi.w  #3,VEC1
    jhi     stk_go
    lea     8(%a5),%a5                  /* bus/address error frame is 14 bytes */
stk_go:
    move.w  #(ORG - 18),%d6
    moveq   #3,%d2                      /* 4 lines */
stk_line:
    move.w  %d6,%d4
    moveq   #2,%d0                      /* 3 longs per line */
stk_long:
    move.l  (%a5)+,%d5
    moveq   #8,%d3
    move.w  %d0,-(%sp)
    bsr     phex
    move.w  (%sp)+,%d0
    add.w   #CHARSTEP,%d4               /* one blank between longs */
    dbra    %d0,stk_long
    subq.w  #1,%d6
    dbra    %d2,stk_line
no_stack:

    tst.w   NESTED
    jeq     hold
    S       s_nest, (ORG - 23)
    moveq   #0,%d5
    move.w  NESTED,%d5
    H       4, (ORG - 23 + 20*CHARSTEP)
    jra     hold

/* print the 0-terminated string at A2 from offset D4; D4 ends after it.
 * Uses D0,A2,A6. */
pstr:
    lea     asc2tile,%a6
ps1:
    moveq   #0,%d0
    move.b  (%a2)+,%d0
    beq.s   ps2
    move.b  (%a6,%d0.w),%d0
    move.w  %d4,(%a3)
    move.w  %d0,(%a4)
    add.w   #CHARSTEP,%d4
    bra.s   ps1
ps2:
    rts

/* print the low D3 nibbles of D5 as hex from offset D4; D4 ends after it.
 * Uses D1,D3,D7. */
phex:
    subq.w  #1,%d3
    move.l  %d5,%d1
    move.w  %d3,%d7
    lsl.w   #2,%d7
    lsr.l   %d7,%d1
    and.w   #0x000f,%d1
    move.w  %d4,(%a3)
    move.w  %d1,(%a4)
    add.w   #CHARSTEP,%d4
    tst.w   %d3
    bne.s   phex
    rts

/* ---- hold: heartbeat on LS259 pin 6 (the diag's fail pattern) ---- */
hold:
    moveq   #3,%d4
hb:
    move.b  #L_HB1,(%a0)
    DELAY   0x6000
    move.b  #L_HB0,(%a0)
    DELAY   0x6000
    dbra    %d4,hb
    DELAY   0x30000
    jra     hold

/* ============================ data ============================ */
    .even
    CRTCTAB
s_head: .asciz "GAME CRASHED"
s_vec:  .asciz "VEC"
s_pc:   .asciz "PC"
s_sr:   .asciz "SR"
s_acc:  .asciz "ACCESS"
s_ssw:  .asciz "SSW"
s_code: .asciz "CODE"
s_stack: .asciz "STACK ABOVE THE FRAME"
s_nest: .asciz "EXCEPTIONS AFTER IT"
s_d:    .asciz "D"
s_a:    .asciz "A"
s_exc:  .asciz "EXCEPTION"
s_trap: .asciz "TRAP INSTRUCTION"
s_v2:   .asciz "BUS ERROR"
s_v3:   .asciz "ADDRESS ERROR"
s_v4:   .asciz "ILLEGAL INSTRUCTION"
s_v5:   .asciz "DIVIDE BY ZERO"
s_v6:   .asciz "CHK INSTRUCTION"
s_v7:   .asciz "TRAPV INSTRUCTION"
s_v8:   .asciz "PRIVILEGE VIOLATION"
s_v9:   .asciz "TRACE"
s_v10:  .asciz "LINE A OPCODE"
s_v11:  .asciz "LINE F OPCODE"
s_v24:  .asciz "SPURIOUS INTERRUPT"
s_irq:  .asciz "UNEXPECTED INTERRUPT"
    .even
vnames:
    .short 2
    .long s_v2
    .short 3
    .long s_v3
    .short 4
    .long s_v4
    .short 5
    .long s_v5
    .short 6
    .long s_v6
    .short 7
    .long s_v7
    .short 8
    .long s_v8
    .short 9
    .long s_v9
    .short 10
    .long s_v10
    .short 11
    .long s_v11
    .short 24
    .long s_v24
    .irp n, 25,26,27,29,30
    .short \n
    .long s_irq
    .endr
    .short -1
    .even
    ASCTAB
crash_end:
