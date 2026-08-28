VASM ?= vasm6502_oldstyle
CL65 ?= cl65

VASMFLAGS = -Fbin -cbm-prg
BUILD_DIR = build

DIS_TARGETS = \
	$(BUILD_DIR)/dis.prg \
	$(BUILD_DIR)/hexdump.prg \
	$(BUILD_DIR)/test_modes.prg

ASS_TARGETS = \
	$(BUILD_DIR)/tokenise.prg \
	$(BUILD_DIR)/test_skipws.prg

EXAMPLE_TARGETS = \
	$(BUILD_DIR)/border-demo.prg \
	$(BUILD_DIR)/border-c.prg

.PHONY: all dis ass examples test clean

all: dis ass examples

dis: $(DIS_TARGETS)

ass: $(ASS_TARGETS)

examples: $(EXAMPLE_TARGETS)

# Issue #2 will turn these assembled test programs into executable
# headless-VICE tests. For now this target verifies that the test
# programs themselves continue to assemble.
test: $(BUILD_DIR)/test_modes.prg $(BUILD_DIR)/test_skipws.prg

$(BUILD_DIR):
	mkdir -p $@

$(BUILD_DIR)/dis.prg: dis/dis.asm dis/modes.asm dis/opcode_table.asm dis/mnemonic_table.asm | $(BUILD_DIR)
	cd dis && $(VASM) $(VASMFLAGS) -o ../$@ dis.asm

$(BUILD_DIR)/hexdump.prg: dis/hexdump.asm | $(BUILD_DIR)
	cd dis && $(VASM) $(VASMFLAGS) -o ../$@ hexdump.asm

$(BUILD_DIR)/test_modes.prg: dis/test_modes.asm dis/modes.asm | $(BUILD_DIR)
	cd dis && $(VASM) $(VASMFLAGS) -o ../$@ test_modes.asm

$(BUILD_DIR)/tokenise.prg: ass/tokenise.asm ass/getLexeme.asm ass/printString.asm ass/skipws.asm ass/zp.inc | $(BUILD_DIR)
	cd ass && $(VASM) $(VASMFLAGS) -o ../$@ tokenise.asm

$(BUILD_DIR)/test_skipws.prg: ass/test_skipws.asm ass/printString.asm ass/skipws.asm ass/zp.inc | $(BUILD_DIR)
	cd ass && $(VASM) $(VASMFLAGS) -o ../$@ test_skipws.asm

$(BUILD_DIR)/border-demo.prg: examples/border/demo.asm | $(BUILD_DIR)
	cd examples/border && $(VASM) $(VASMFLAGS) -o ../../$@ demo.asm

$(BUILD_DIR)/border-c.prg: examples/border/main.c | $(BUILD_DIR)
	cd examples/border && $(CL65) -Oirs -t c64 -o ../../$@ main.c

clean:
	rm -rf $(BUILD_DIR)
