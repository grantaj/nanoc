VASM ?= vasm6502_oldstyle
CL65 ?= cl65
VICE ?= x64sc

VASMFLAGS = -Fbin -cbm-prg
BUILD_DIR = build

DIS_TARGETS = \
	$(BUILD_DIR)/dis.prg \
	$(BUILD_DIR)/hexdump.prg \
	$(BUILD_DIR)/test_modes.prg

ASS_TARGETS = \
	$(BUILD_DIR)/ass.prg \
	$(BUILD_DIR)/parse.prg \
	$(BUILD_DIR)/test_skipws.prg \
	$(BUILD_DIR)/test_scanner.prg \
	$(BUILD_DIR)/test_parser.prg \
	$(BUILD_DIR)/test_parser_eof.prg \
	$(BUILD_DIR)/test_instruction.prg \
	$(BUILD_DIR)/test_values.prg \
	$(BUILD_DIR)/test_globals.prg \
	$(BUILD_DIR)/test_locals.prg \
	$(BUILD_DIR)/test_assembler.prg \
	$(BUILD_DIR)/test_data.prg \
	$(BUILD_DIR)/test_strings.prg \
	$(BUILD_DIR)/test_streaming.prg \
	$(BUILD_DIR)/test_selfhost.prg

ASSEMBLER_DEPS = \
	ass/assembler.asm ass/representation.asm ass/source.asm ass/data.asm \
	ass/symbols.asm ass/value.asm ass/instruction.asm ass/parser.asm \
	ass/scanner.asm ass/skipws.asm ass/zp.inc dis/kernal.inc dis/mode_ids.inc \
	dis/mode_widths.asm dis/opcode_table.asm dis/mnemonic_table.asm test.inc

STREAM_FIXTURES = \
	tests/stream-src/main.asm \
	tests/stream-src/child.asm \
	tests/stream-src/nested.asm \
	tests/stream-src/tail.asm

SELFHOST_FIXTURES = \
	ass/ass_0800.asm \
	ass/ass.asm \
	ass/selfhost_smoke.asm

EXAMPLE_TARGETS = \
	$(BUILD_DIR)/border-demo.prg \
	$(BUILD_DIR)/border-c.prg

.PHONY: all dis ass examples test test-skipws test-scanner test-parser test-parser-eof test-instruction test-values test-globals test-locals test-assembler test-data test-strings test-streaming test-selfhost clean

all: dis ass examples

dis: $(DIS_TARGETS)

ass: $(ASS_TARGETS)

examples: $(EXAMPLE_TARGETS)

test: test-skipws test-scanner test-parser test-parser-eof test-instruction test-values test-globals test-locals test-assembler test-data test-strings test-streaming test-selfhost

test-skipws: $(BUILD_DIR)/test_skipws.prg
	VICE=$(VICE) BUILD_DIR=$(BUILD_DIR) sh tests/run-test.sh $< skipws

test-scanner: $(BUILD_DIR)/test_scanner.prg
	VICE=$(VICE) BUILD_DIR=$(BUILD_DIR) sh tests/run-test.sh $< scanner

test-parser: $(BUILD_DIR)/test_parser.prg
	VICE=$(VICE) BUILD_DIR=$(BUILD_DIR) sh tests/run-test.sh $< parser

test-parser-eof: $(BUILD_DIR)/test_parser_eof.prg
	VICE=$(VICE) BUILD_DIR=$(BUILD_DIR) sh tests/run-test.sh $< parser-eof

test-instruction: $(BUILD_DIR)/test_instruction.prg
	VICE=$(VICE) BUILD_DIR=$(BUILD_DIR) sh tests/run-test.sh $< instruction

test-values: $(BUILD_DIR)/test_values.prg
	VICE=$(VICE) BUILD_DIR=$(BUILD_DIR) sh tests/run-test.sh $< values

test-globals: $(BUILD_DIR)/test_globals.prg
	VICE=$(VICE) BUILD_DIR=$(BUILD_DIR) sh tests/run-test.sh $< globals

test-locals: $(BUILD_DIR)/test_locals.prg
	VICE=$(VICE) BUILD_DIR=$(BUILD_DIR) sh tests/run-test.sh $< locals

test-assembler: $(BUILD_DIR)/test_assembler.prg
	VICE=$(VICE) BUILD_DIR=$(BUILD_DIR) sh tests/run-test.sh $< assembler

test-data: $(BUILD_DIR)/test_data.prg
	VICE=$(VICE) BUILD_DIR=$(BUILD_DIR) sh tests/run-test.sh $< data

test-strings: $(BUILD_DIR)/test_strings.prg
	VICE=$(VICE) BUILD_DIR=$(BUILD_DIR) sh tests/run-test.sh $< strings

test-streaming: $(BUILD_DIR)/test_streaming.prg $(STREAM_FIXTURES)
	VICE_FS_DIR=$(CURDIR)/tests/stream-src VICE=$(VICE) BUILD_DIR=$(BUILD_DIR) sh tests/run-test.sh $< streaming

test-selfhost: $(BUILD_DIR)/test_selfhost.prg $(SELFHOST_FIXTURES)
	VICE_TIMEOUT=60 VICE_FS_DIR=$(CURDIR) VICE=$(VICE) BUILD_DIR=$(BUILD_DIR) sh tests/run-test.sh $< selfhost

$(BUILD_DIR):
	mkdir -p $@

$(BUILD_DIR)/dis.prg: dis/dis.asm dis/modes.asm dis/mode_ids.inc dis/mode_widths.asm dis/opcode_table.asm dis/mnemonic_table.asm | $(BUILD_DIR)
	cd dis && $(VASM) $(VASMFLAGS) -o ../$@ dis.asm

$(BUILD_DIR)/hexdump.prg: dis/hexdump.asm | $(BUILD_DIR)
	cd dis && $(VASM) $(VASMFLAGS) -o ../$@ hexdump.asm

$(BUILD_DIR)/test_modes.prg: dis/test_modes.asm dis/modes.asm dis/mode_ids.inc | $(BUILD_DIR)
	cd dis && $(VASM) $(VASMFLAGS) -o ../$@ test_modes.asm

$(BUILD_DIR)/ass.prg: ass/ass_4000.asm ass/ass.asm $(ASSEMBLER_DEPS) | $(BUILD_DIR)
	cd ass && $(VASM) $(VASMFLAGS) -o ../$@ ass_4000.asm

$(BUILD_DIR)/parse.prg: ass/parse.asm ass/parser.asm ass/instruction.asm ass/scanner.asm ass/skipws.asm ass/zp.inc dis/mode_ids.inc dis/opcode_table.asm dis/mnemonic_table.asm | $(BUILD_DIR)
	cd ass && $(VASM) $(VASMFLAGS) -o ../$@ parse.asm

$(BUILD_DIR)/test_skipws.prg: ass/test_skipws.asm ass/skipws.asm ass/zp.inc test.inc | $(BUILD_DIR)
	cd ass && $(VASM) $(VASMFLAGS) -o ../$@ test_skipws.asm

$(BUILD_DIR)/test_scanner.prg: ass/test_scanner.asm ass/scanner.asm ass/zp.inc test.inc | $(BUILD_DIR)
	cd ass && $(VASM) $(VASMFLAGS) -o ../$@ test_scanner.asm

$(BUILD_DIR)/test_parser.prg: ass/test_parser.asm ass/parser.asm ass/scanner.asm ass/skipws.asm ass/zp.inc test.inc | $(BUILD_DIR)
	cd ass && $(VASM) $(VASMFLAGS) -o ../$@ test_parser.asm

$(BUILD_DIR)/test_parser_eof.prg: ass/test_parser_eof.asm ass/parser.asm ass/scanner.asm ass/skipws.asm ass/zp.inc test.inc | $(BUILD_DIR)
	cd ass && $(VASM) $(VASMFLAGS) -o ../$@ test_parser_eof.asm

$(BUILD_DIR)/test_instruction.prg: ass/test_instruction.asm ass/instruction.asm ass/parser.asm ass/scanner.asm ass/skipws.asm ass/zp.inc dis/mode_ids.inc dis/opcode_table.asm dis/mnemonic_table.asm test.inc | $(BUILD_DIR)
	cd ass && $(VASM) $(VASMFLAGS) -o ../$@ test_instruction.asm

$(BUILD_DIR)/test_values.prg: ass/test_values.asm $(ASSEMBLER_DEPS) | $(BUILD_DIR)
	cd ass && $(VASM) $(VASMFLAGS) -o ../$@ test_values.asm

$(BUILD_DIR)/test_globals.prg: ass/test_globals.asm $(ASSEMBLER_DEPS) | $(BUILD_DIR)
	cd ass && $(VASM) $(VASMFLAGS) -o ../$@ test_globals.asm

$(BUILD_DIR)/test_locals.prg: ass/test_locals.asm $(ASSEMBLER_DEPS) | $(BUILD_DIR)
	cd ass && $(VASM) $(VASMFLAGS) -o ../$@ test_locals.asm

$(BUILD_DIR)/test_assembler.prg: ass/test_assembler.asm $(ASSEMBLER_DEPS) | $(BUILD_DIR)
	cd ass && $(VASM) $(VASMFLAGS) -o ../$@ test_assembler.asm

$(BUILD_DIR)/test_data.prg: ass/test_data.asm $(ASSEMBLER_DEPS) | $(BUILD_DIR)
	cd ass && $(VASM) $(VASMFLAGS) -o ../$@ test_data.asm

$(BUILD_DIR)/test_strings.prg: ass/test_strings.asm $(ASSEMBLER_DEPS) | $(BUILD_DIR)
	cd ass && $(VASM) $(VASMFLAGS) -o ../$@ test_strings.asm

$(BUILD_DIR)/test_streaming.prg: ass/test_streaming.asm $(ASSEMBLER_DEPS) | $(BUILD_DIR)
	cd ass && $(VASM) $(VASMFLAGS) -o ../$@ test_streaming.asm

$(BUILD_DIR)/test_selfhost.prg: ass/test_selfhost.asm ass/ass.asm $(ASSEMBLER_DEPS) | $(BUILD_DIR)
	cd ass && $(VASM) $(VASMFLAGS) -o ../$@ test_selfhost.asm

$(BUILD_DIR)/border-demo.prg: examples/border/demo.asm | $(BUILD_DIR)
	cd examples/border && $(VASM) $(VASMFLAGS) -o ../../$@ demo.asm

$(BUILD_DIR)/border-c.prg: examples/border/main.c | $(BUILD_DIR)
	cd examples/border && $(CL65) -Oirs -t c64 -o ../../$@ main.c

clean:
	rm -rf $(BUILD_DIR)
