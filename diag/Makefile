# Twin Cobra / Kyuukyoku Tiger diagnostic ROM
# Toolchain: GNU binutils for m68k-elf (brew install m68k-elf-binutils)

AS      := m68k-elf-as
LD      := m68k-elf-ld
OBJCOPY := m68k-elf-objcopy
OBJDUMP := m68k-elf-objdump
PYTHON  := python3

ASFLAGS := -m68000
LDFLAGS := -T diag.ld

BUILD   := build
SRC     := src/diag.s

ROM_SIZE := 0x20000          # two 27512 halves
EVEN := $(BUILD)/twincobr_diag_7j.bin   # even bytes (D8-D15)
ODD  := $(BUILD)/twincobr_diag_7h.bin   # odd  bytes (D0-D7)

# Heartbeat-only ROM (stage 0): toggles the LS259 flip pin forever, touches
# nothing but ROM + the control latch. Use it to prove the 68000 is alive on a
# dead board before the full diagnostic.
HB_EVEN := $(BUILD)/twincobr_hb_7j.bin
HB_ODD  := $(BUILD)/twincobr_hb_7h.bin

# Spin ROM: reads ROM forever, no writes. Isolates read path from write path.
SPIN_EVEN := $(BUILD)/twincobr_spin_7j.bin
SPIN_ODD  := $(BUILD)/twincobr_spin_7h.bin

.PHONY: all hb spin clean dump
all: $(EVEN) $(ODD) hb spin
hb: $(HB_EVEN) $(HB_ODD)
spin: $(SPIN_EVEN) $(SPIN_ODD)

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/stage0.o: $(SRC) | $(BUILD)
	$(AS) $(ASFLAGS) $< -o $@

$(BUILD)/hb.o: src/stage0.s | $(BUILD)
	$(AS) $(ASFLAGS) $< -o $@
$(BUILD)/hb.elf: $(BUILD)/hb.o diag.ld
	$(LD) $(LDFLAGS) $< -o $@
$(BUILD)/hb.bin: $(BUILD)/hb.elf
	$(OBJCOPY) -O binary $< $@
$(HB_EVEN) $(HB_ODD): $(BUILD)/hb.bin tools/split.py
	$(PYTHON) tools/split.py $(BUILD)/hb.bin $(HB_EVEN) $(HB_ODD) $(ROM_SIZE)

$(BUILD)/spin.o: src/spin.s | $(BUILD)
	$(AS) $(ASFLAGS) $< -o $@
$(BUILD)/spin.elf: $(BUILD)/spin.o diag.ld
	$(LD) $(LDFLAGS) $< -o $@
$(BUILD)/spin.bin: $(BUILD)/spin.elf
	$(OBJCOPY) -O binary $< $@
$(SPIN_EVEN) $(SPIN_ODD): $(BUILD)/spin.bin tools/split.py
	$(PYTHON) tools/split.py $(BUILD)/spin.bin $(SPIN_EVEN) $(SPIN_ODD) $(ROM_SIZE)

$(BUILD)/diag.elf: $(BUILD)/stage0.o diag.ld
	$(LD) $(LDFLAGS) $< -o $@

$(BUILD)/diag.bin: $(BUILD)/diag.elf
	$(OBJCOPY) -O binary $< $@

$(EVEN) $(ODD): $(BUILD)/diag.bin tools/split.py
	$(PYTHON) tools/split.py $(BUILD)/diag.bin $(EVEN) $(ODD) $(ROM_SIZE)

# Disassemble for inspection
dump: $(BUILD)/diag.elf
	$(OBJDUMP) -d $<

clean:
	rm -rf $(BUILD)
