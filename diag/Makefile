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

.PHONY: all clean dump
all: $(EVEN) $(ODD)

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/stage0.o: $(SRC) | $(BUILD)
	$(AS) $(ASFLAGS) $< -o $@

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
