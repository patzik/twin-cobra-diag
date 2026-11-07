/* DIP switch meanings per game set, from MAME twincobr.cpp / toaplipt.h
 * (generated). Entry: bank (0 = DSW1, 1 = DSW2), mask, label, value table;
 * value table: value, string ... -1. */
    .even
dl_tcw:
    .short 0, 0x01
    .long dlb_0, dt_nu1
    .short 0, 0x02
    .long dlb_1, dt_off02
    .short 0, 0x04
    .long dlb_2, dt_test
    .short 0, 0x08
    .long dlb_3, dt_demo
    .short 0, 0x30
    .long dlb_4, dt_cawo
    .short 0, 0xc0
    .long dlb_5, dt_cbwo
    .short 1, 0x03
    .long dlb_6, dt_diff
    .short 1, 0x0c
    .long dlb_7, dt_bon
    .short 1, 0x30
    .long dlb_8, dt_liv
    .short 1, 0x40
    .long dlb_9, dt_dsd
    .short 1, 0x80
    .long dlb_10, dt_nu8
    .short -1
dl_tcu:
    .short 0, 0x01
    .long dlb_0, dt_nu1
    .short 0, 0x02
    .long dlb_1, dt_off02
    .short 0, 0x04
    .long dlb_2, dt_test
    .short 0, 0x08
    .long dlb_3, dt_demo
    .short 0, 0x30
    .long dlb_4, dt_caja
    .short 0, 0xc0
    .long dlb_5, dt_cbja
    .short 1, 0x03
    .long dlb_6, dt_diff
    .short 1, 0x0c
    .long dlb_7, dt_bon
    .short 1, 0x30
    .long dlb_8, dt_liv
    .short 1, 0x40
    .long dlb_9, dt_dsd
    .short 1, 0x80
    .long dlb_10, dt_nu8
    .short -1
dl_kt:
    .short 0, 0x01
    .long dlb_11, dt_inv
    .short 0, 0x02
    .long dlb_1, dt_off02
    .short 0, 0x04
    .long dlb_2, dt_test
    .short 0, 0x08
    .long dlb_3, dt_demo
    .short 0, 0x30
    .long dlb_4, dt_caja
    .short 0, 0xc0
    .long dlb_5, dt_cbja
    .short 1, 0x03
    .long dlb_6, dt_diff
    .short 1, 0x0c
    .long dlb_7, dt_bon
    .short 1, 0x30
    .long dlb_8, dt_liv
    .short 1, 0x40
    .long dlb_9, dt_dsd
    .short 1, 0x80
    .long dlb_10, dt_nu8
    .short -1
dl_kta:
    .short 0, 0x01
    .long dlb_12, dt_cab
    .short 0, 0x02
    .long dlb_1, dt_off02
    .short 0, 0x04
    .long dlb_2, dt_test
    .short 0, 0x08
    .long dlb_3, dt_demo
    .short 0, 0x30
    .long dlb_4, dt_caja
    .short 0, 0xc0
    .long dlb_5, dt_cbja
    .short 1, 0x03
    .long dlb_6, dt_diff
    .short 1, 0x0c
    .long dlb_7, dt_bona
    .short 1, 0x30
    .long dlb_8, dt_liv
    .short 1, 0x40
    .long dlb_9, dt_dsd
    .short 1, 0x80
    .long dlb_13, dt_cont
    .short -1
dt_off02:
    .short 0x00
    .long dv_0
    .short 0x02
    .long dv_1
    .short -1
dt_test:
    .short 0x00
    .long dv_0
    .short 0x04
    .long dv_1
    .short -1
dt_demo:
    .short 0x00
    .long dv_1
    .short 0x08
    .long dv_0
    .short -1
dt_nu1:
    .short 0x00
    .long dv_2
    .short 0x01
    .long dv_3
    .short -1
dt_inv:
    .short 0x00
    .long dv_0
    .short 0x01
    .long dv_1
    .short -1
dt_cab:
    .short 0x00
    .long dv_4
    .short 0x01
    .long dv_5
    .short -1
dt_cawo:
    .short 0x00
    .long dv_6
    .short 0x10
    .long dv_7
    .short 0x20
    .long dv_8
    .short 0x30
    .long dv_9
    .short -1
dt_cbwo:
    .short 0x00
    .long dv_10
    .short 0x40
    .long dv_11
    .short 0x80
    .long dv_12
    .short 0xc0
    .long dv_13
    .short -1
dt_caja:
    .short 0x00
    .long dv_6
    .short 0x10
    .long dv_10
    .short 0x20
    .long dv_7
    .short 0x30
    .long dv_14
    .short -1
dt_cbja:
    .short 0x00
    .long dv_6
    .short 0x40
    .long dv_10
    .short 0x80
    .long dv_7
    .short 0xc0
    .long dv_14
    .short -1
dt_diff:
    .short 0x00
    .long dv_15
    .short 0x01
    .long dv_16
    .short 0x02
    .long dv_17
    .short 0x03
    .long dv_18
    .short -1
dt_bon:
    .short 0x00
    .long dv_19
    .short 0x04
    .long dv_20
    .short 0x08
    .long dv_21
    .short 0x0c
    .long dv_22
    .short -1
dt_bona:
    .short 0x00
    .long dv_20
    .short 0x04
    .long dv_19
    .short 0x08
    .long dv_22
    .short 0x0c
    .long dv_23
    .short -1
dt_liv:
    .short 0x00
    .long dv_24
    .short 0x10
    .long dv_25
    .short 0x20
    .long dv_26
    .short 0x30
    .long dv_27
    .short -1
dt_dsd:
    .short 0x00
    .long dv_0
    .short 0x40
    .long dv_1
    .short -1
dt_nu8:
    .short 0x00
    .long dv_2
    .short 0x80
    .long dv_3
    .short -1
dt_cont:
    .short 0x00
    .long dv_28
    .short 0x80
    .long dv_29
    .short -1
dlb_0: .asciz "SW1 1"
dlb_1: .asciz "FLIP SCREEN"
dlb_2: .asciz "TEST MODE"
dlb_3: .asciz "DEMO SOUNDS"
dlb_4: .asciz "COIN A"
dlb_5: .asciz "COIN B"
dlb_6: .asciz "DIFFICULTY"
dlb_7: .asciz "BONUS"
dlb_8: .asciz "LIVES"
dlb_9: .asciz "DSW DISPLAY"
dlb_10: .asciz "SW2 8"
dlb_11: .asciz "INVULNERABLE"
dlb_12: .asciz "CABINET"
dlb_13: .asciz "CONTINUE"
dv_0: .asciz "OFF             "
dv_1: .asciz "ON              "
dv_2: .asciz "NOT USED  OFF   "
dv_3: .asciz "NOT USED  ON    "
dv_4: .asciz "COCKTAIL        "
dv_5: .asciz "UPRIGHT         "
dv_6: .asciz "1 COIN 1 CREDIT "
dv_7: .asciz "2 COINS 1 CREDIT"
dv_8: .asciz "3 COINS 1 CREDIT"
dv_9: .asciz "4 COINS 1 CREDIT"
dv_10: .asciz "1 COIN 2 CREDITS"
dv_11: .asciz "1 COIN 3 CREDITS"
dv_12: .asciz "1 COIN 4 CREDITS"
dv_13: .asciz "1 COIN 6 CREDITS"
dv_14: .asciz "2 COIN 3 CREDITS"
dv_15: .asciz "NORMAL          "
dv_16: .asciz "EASY            "
dv_17: .asciz "HARD            "
dv_18: .asciz "VERY HARD       "
dv_19: .asciz "50K 200K 150K   "
dv_20: .asciz "70K 270K 200K   "
dv_21: .asciz "50K ONLY        "
dv_22: .asciz "100K ONLY       "
dv_23: .asciz "NONE            "
dv_24: .asciz "3               "
dv_25: .asciz "5               "
dv_26: .asciz "4               "
dv_27: .asciz "2               "
dv_28: .asciz "NO              "
dv_29: .asciz "YES             "
    .even
