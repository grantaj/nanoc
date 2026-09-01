CC = cc
CFLAGS = -std=c90 -Wall -Wextra -pedantic
VASM = vasm6502_oldstyle
VICE = x64sc
BUILD_DIR = build

.PHONY: all setup doctor clean test test-skipws test-scanner test-parser test-parser-eof test-instruction test-values test-globals test-locals test-assembler test-data test-strings test-streaming test-selfhost test-nanoc0-scanner test-nanoc0-declarations test-nanoc0-bootstrap test-nanoc0-expressions test-nanoc0-statements test-nanoc0-calls test-nanoc0-runtime

all: $(BUILD_DIR)/dis.prg $(BUILD_DIR)/hexdump.prg $(BUILD_DIR)/test_modes.prg \
	$(BUILD_DIR)/ass.prg $(BUILD_DIR)/parse.prg \
	$(BUILD_DIR)/test_skipws.prg $(BUILD_DIR)/test_scanner.prg \
	$(BUILD_DIR)/test_parser.prg $(BUILD_DIR)/test_parser_eof.prg \
	$(BUILD_DIR)/test_instruction.prg $(BUILD_DIR)/test_values.prg \
	$(BUILD_DIR)/test_globals.prg $(BUILD_DIR)/test_locals.prg \
	$(BUILD_DIR)/test_assembler.prg $(BUILD_DIR)/test_data.prg \
	$(BUILD_DIR)/test_strings.prg $(BUILD_DIR)/test_streaming.prg \
	$(BUILD_DIR)/test_selfhost.prg $(BUILD_DIR)/nanoc0-core.prg \
	$(BUILD_DIR)/test_nanoc0_scanner.prg $(BUILD_DIR)/test_nanoc0_declarations.prg \
	$(BUILD_DIR)/test_nanoc0_bootstrap.prg $(BUILD_DIR)/test_nanoc0_expression_compile.prg \
	$(BUILD_DIR)/test_nanoc0_expression_run.prg $(BUILD_DIR)/test_nanoc0_statement_compile.prg \
	$(BUILD_DIR)/test_nanoc0_statement_run.prg $(BUILD_DIR)/test_nanoc0_calls.prg \
	$(BUILD_DIR)/test_nanoc0_runtime_compile.prg $(BUILD_DIR)/test_nanoc0_runtime_run.prg \
	$(BUILD_DIR)/border-demo.prg $(BUILD_DIR)/border-c.prg
	@bytes=$$(wc -c < $(BUILD_DIR)/nanoc0-core.prg); \
	resident=$$((bytes - 2)); \
	symbols=3488; token=192; control=81; calls=13; \
	code=$$((resident - symbols - token - control - calls)); \
	printf '%-31s %5d bytes\n' 'nanoc0 resident core:' $$resident; \
	printf '  %-29s %5d bytes\n' 'symbol/name workspace:' $$symbols; \
	printf '  %-29s %5d bytes\n' 'reusable token text:' $$token; \
	printf '  %-29s %5d bytes\n' 'statement control stack:' $$control; \
	printf '  %-29s %5d bytes\n' 'pending-call stack:' $$calls; \
	printf '  %-29s %5d bytes\n' 'code + other small state:' $$code

setup:
	sh scripts/setup-dev.sh

doctor:
	sh scripts/doctor.sh

$(BUILD_DIR):
	mkdir -p $@

$(BUILD_DIR)/dis.prg: dis/dis.asm | $(BUILD_DIR)
	cd dis && $(VASM) -Fbin -cbm-prg -o ../$@ dis.asm

$(BUILD_DIR)/hexdump.prg: dis/hexdump.asm | $(BUILD_DIR)
	cd dis && $(VASM) -Fbin -cbm-prg -o ../$@ hexdump.asm

$(BUILD_DIR)/test_modes.prg: dis/test_modes.asm | $(BUILD_DIR)
	cd dis && $(VASM) -Fbin -cbm-prg -o ../$@ test_modes.asm

$(BUILD_DIR)/ass.prg: ass/ass_4000.asm | $(BUILD_DIR)
	cd ass && $(VASM) -Fbin -cbm-prg -o ../$@ ass_4000.asm

$(BUILD_DIR)/parse.prg: ass/parse.asm | $(BUILD_DIR)
	cd ass && $(VASM) -Fbin -cbm-prg -o ../$@ parse.asm

$(BUILD_DIR)/test_skipws.prg: ass/test_skipws.asm | $(BUILD_DIR)
	cd ass && $(VASM) -Fbin -cbm-prg -o ../$@ test_skipws.asm

$(BUILD_DIR)/test_scanner.prg: ass/test_scanner.asm | $(BUILD_DIR)
	cd ass && $(VASM) -Fbin -cbm-prg -o ../$@ test_scanner.asm

$(BUILD_DIR)/test_parser.prg: ass/test_parser.asm | $(BUILD_DIR)
	cd ass && $(VASM) -Fbin -cbm-prg -o ../$@ test_parser.asm

$(BUILD_DIR)/test_parser_eof.prg: ass/test_parser_eof.asm | $(BUILD_DIR)
	cd ass && $(VASM) -Fbin -cbm-prg -o ../$@ test_parser_eof.asm

$(BUILD_DIR)/test_instruction.prg: ass/test_instruction.asm | $(BUILD_DIR)
	cd ass && $(VASM) -Fbin -cbm-prg -o ../$@ test_instruction.asm

$(BUILD_DIR)/test_values.prg: ass/test_values.asm | $(BUILD_DIR)
	cd ass && $(VASM) -Fbin -cbm-prg -o ../$@ test_values.asm

$(BUILD_DIR)/test_globals.prg: ass/test_globals.asm | $(BUILD_DIR)
	cd ass && $(VASM) -Fbin -cbm-prg -o ../$@ test_globals.asm

$(BUILD_DIR)/test_locals.prg: ass/test_locals.asm | $(BUILD_DIR)
	cd ass && $(VASM) -Fbin -cbm-prg -o ../$@ test_locals.asm

$(BUILD_DIR)/test_assembler.prg: ass/test_assembler.asm | $(BUILD_DIR)
	cd ass && $(VASM) -Fbin -cbm-prg -o ../$@ test_assembler.asm

$(BUILD_DIR)/test_data.prg: ass/test_data.asm | $(BUILD_DIR)
	cd ass && $(VASM) -Fbin -cbm-prg -o ../$@ test_data.asm

$(BUILD_DIR)/test_strings.prg: ass/test_strings.asm | $(BUILD_DIR)
	cd ass && $(VASM) -Fbin -cbm-prg -o ../$@ test_strings.asm

$(BUILD_DIR)/test_streaming.prg: ass/test_streaming.asm | $(BUILD_DIR)
	cd ass && $(VASM) -Fbin -cbm-prg -o ../$@ test_streaming.asm

$(BUILD_DIR)/test_selfhost.prg: ass/test_selfhost.asm | $(BUILD_DIR)
	cd ass && $(VASM) -Fbin -cbm-prg -o ../$@ test_selfhost.asm

$(BUILD_DIR)/nanoc0-core.prg: nanoc0/core.asm | $(BUILD_DIR)
	cd nanoc0 && $(VASM) -Fbin -cbm-prg -o ../$@ core.asm

$(BUILD_DIR)/test_nanoc0_scanner.prg: nanoc0/test_scanner.asm | $(BUILD_DIR)
	cd nanoc0 && $(VASM) -Fbin -cbm-prg -o ../$@ test_scanner.asm

$(BUILD_DIR)/test_nanoc0_declarations.prg: nanoc0/test_declarations.asm | $(BUILD_DIR)
	cd nanoc0 && $(VASM) -Fbin -cbm-prg -DNANOC0_DECLARATION_BODY_SKIP=1 -o ../$@ test_declarations.asm

$(BUILD_DIR)/test_nanoc0_bootstrap.prg: nanoc0/test_bootstrap.asm | $(BUILD_DIR)
	cd nanoc0 && $(VASM) -Fbin -cbm-prg -DNANOC0_DECLARATION_BODY_SKIP=1 -o ../$@ test_bootstrap.asm

$(BUILD_DIR)/test_nanoc0_expression_compile.prg: nanoc0/test_expression_compile.asm | $(BUILD_DIR)
	cd nanoc0 && $(VASM) -Fbin -cbm-prg -o ../$@ test_expression_compile.asm

$(BUILD_DIR)/test_nanoc0_expression_run.prg: ass/test_nanoc0_expressions.asm | $(BUILD_DIR)
	cd ass && $(VASM) -Fbin -cbm-prg -o ../$@ test_nanoc0_expressions.asm

$(BUILD_DIR)/test_nanoc0_statement_compile.prg: nanoc0/test_statement_compile.asm | $(BUILD_DIR)
	cd nanoc0 && $(VASM) -Fbin -cbm-prg -o ../$@ test_statement_compile.asm

$(BUILD_DIR)/test_nanoc0_statement_run.prg: ass/test_nanoc0_statements.asm | $(BUILD_DIR)
	cd ass && $(VASM) -Fbin -cbm-prg -o ../$@ test_nanoc0_statements.asm

$(BUILD_DIR)/test_nanoc0_calls.prg: nanoc0/test_calls.asm | $(BUILD_DIR)
	cd nanoc0 && $(VASM) -Fbin -cbm-prg -o ../$@ test_calls.asm

$(BUILD_DIR)/test_nanoc0_runtime_compile.prg: nanoc0/test_runtime_compile.asm | $(BUILD_DIR)
	cd nanoc0 && $(VASM) -Fbin -cbm-prg -o ../$@ test_runtime_compile.asm

$(BUILD_DIR)/test_nanoc0_runtime_run.prg: ass/test_nanoc0_runtime.asm | $(BUILD_DIR)
	cd ass && $(VASM) -Fbin -cbm-prg -o ../$@ test_nanoc0_runtime.asm

$(BUILD_DIR)/border-demo.prg: examples/border/demo.asm | $(BUILD_DIR)
	cd examples/border && $(VASM) -Fbin -cbm-prg -o ../../$@ demo.asm

$(BUILD_DIR)/border-c.prg: examples/border/main.c | $(BUILD_DIR)
	cd examples/border && cl65 -Oirs -t c64 -o ../../$@ main.c

NANOC0_EXPRESSION_FIXTURES = tests/nanoc0-expr/expressions.c
NANOC0_STATEMENT_FIXTURES = tests/nanoc0-stmt/return8.c tests/nanoc0-stmt/statements.c
NANOC0_CALL_FIXTURES = tests/nanoc0-call/cntbad.c tests/nanoc0-call/typbad.c tests/nanoc0-call/latbad.c tests/nanoc0-call/depbad.c tests/nanoc0-call/argbad.c
NANOC0_RUNTIME_FIXTURES = tests/nanoc0-runtime/runtime.c tests/nanoc0-runtime/runtime.in

test: test-skipws test-scanner test-parser test-parser-eof test-instruction test-values test-globals test-locals test-assembler test-data test-strings test-streaming test-selfhost test-nanoc0-scanner test-nanoc0-declarations test-nanoc0-bootstrap test-nanoc0-expressions test-nanoc0-statements test-nanoc0-calls test-nanoc0-runtime

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

test-streaming: $(BUILD_DIR)/test_streaming.prg tests/stream-src/main.asm tests/stream-src/child.asm
	VICE_FS_DIR=$(CURDIR)/tests/stream-src VICE=$(VICE) BUILD_DIR=$(BUILD_DIR) sh tests/run-test.sh $< streaming

test-selfhost: $(BUILD_DIR)/test_selfhost.prg $(ASS_PRODUCTION_SOURCES)
	VICE_TIMEOUT=60 VICE_FS_DIR=$(CURDIR) VICE=$(VICE) BUILD_DIR=$(BUILD_DIR) sh tests/run-test.sh $< selfhost

test-nanoc0-scanner: $(BUILD_DIR)/test_nanoc0_scanner.prg
	VICE_FS_DIR=$(CURDIR)/tests/nanoc0-src VICE=$(VICE) BUILD_DIR=$(BUILD_DIR) sh tests/run-test.sh $< nanoc0-scanner

test-nanoc0-declarations: $(BUILD_DIR)/test_nanoc0_declarations.prg
	VICE_FS_DIR=$(CURDIR)/tests/nanoc0-src VICE=$(VICE) BUILD_DIR=$(BUILD_DIR) sh tests/run-test.sh $< nanoc0-declarations

test-nanoc0-bootstrap: $(BUILD_DIR)/test_nanoc0_bootstrap.prg bootstrap/ass.c
	VICE_TIMEOUT=30 VICE_FS_DIR=$(CURDIR)/bootstrap VICE=$(VICE) BUILD_DIR=$(BUILD_DIR) sh tests/run-test.sh $< nanoc0-bootstrap

test-nanoc0-expressions: $(BUILD_DIR)/test_nanoc0_expression_compile.prg $(BUILD_DIR)/test_nanoc0_expression_run.prg $(NANOC0_EXPRESSION_FIXTURES)
	rm -f tests/nanoc0-expr/EXPROUT.ASM tests/nanoc0-expr/exprout.asm
	VICE_TIMEOUT=30 VICE_FS_DIR=$(CURDIR)/tests/nanoc0-expr VICE=$(VICE) BUILD_DIR=$(BUILD_DIR) sh tests/run-test.sh $(BUILD_DIR)/test_nanoc0_expression_compile.prg nanoc0-expression-compile
	VICE_TIMEOUT=30 VICE_FS_DIR=$(CURDIR)/tests/nanoc0-expr VICE=$(VICE) BUILD_DIR=$(BUILD_DIR) sh tests/run-test.sh $(BUILD_DIR)/test_nanoc0_expression_run.prg nanoc0-expressions

test-nanoc0-statements: $(BUILD_DIR)/test_nanoc0_statement_compile.prg $(BUILD_DIR)/test_nanoc0_statement_run.prg $(NANOC0_STATEMENT_FIXTURES)
	rm -f tests/nanoc0-stmt/RET8OUT.ASM tests/nanoc0-stmt/ret8out.asm tests/nanoc0-stmt/STMTOUT.ASM tests/nanoc0-stmt/stmtout.asm
	VICE_TIMEOUT=60 VICE_FS_DIR=$(CURDIR)/tests/nanoc0-stmt VICE=$(VICE) BUILD_DIR=$(BUILD_DIR) sh tests/run-test.sh $(BUILD_DIR)/test_nanoc0_statement_compile.prg nanoc0-statement-compile
	TEST_DEBUG_WORKSPACE=1 VICE_TIMEOUT=60 VICE_FS_DIR=$(CURDIR)/tests/nanoc0-stmt VICE=$(VICE) BUILD_DIR=$(BUILD_DIR) sh tests/run-test.sh $(BUILD_DIR)/test_nanoc0_statement_run.prg nanoc0-statements

test-nanoc0-calls: $(BUILD_DIR)/test_nanoc0_calls.prg $(NANOC0_CALL_FIXTURES)
	VICE_FS_DIR=$(CURDIR)/tests/nanoc0-call VICE=$(VICE) BUILD_DIR=$(BUILD_DIR) sh tests/run-test.sh $< nanoc0-calls

test-nanoc0-runtime: $(BUILD_DIR)/test_nanoc0_runtime_compile.prg $(BUILD_DIR)/test_nanoc0_runtime_run.prg $(NANOC0_RUNTIME_FIXTURES)
	rm -f tests/nanoc0-runtime/RTOUT.ASM tests/nanoc0-runtime/rtout.asm tests/nanoc0-runtime/SMOKE.ASM tests/nanoc0-runtime/smoke.asm tests/nanoc0-runtime/DTEST tests/nanoc0-runtime/dtest
	VICE_TIMEOUT=60 VICE_FS_DIR=$(CURDIR) VICE_FS_DIR_9=$(CURDIR)/tests/nanoc0-runtime VICE=$(VICE) BUILD_DIR=$(BUILD_DIR) sh tests/run-test.sh $(BUILD_DIR)/test_nanoc0_runtime_compile.prg nanoc0-runtime-compile
	VICE_TIMEOUT=60 VICE_FS_DIR=$(CURDIR) VICE_FS_DIR_9=$(CURDIR)/tests/nanoc0-runtime VICE=$(VICE) BUILD_DIR=$(BUILD_DIR) sh tests/run-test.sh $(BUILD_DIR)/test_nanoc0_runtime_run.prg nanoc0-runtime

clean:
	rm -rf $(BUILD_DIR)
	rm -f tests/nanoc0-expr/EXPROUT.ASM tests/nanoc0-expr/exprout.asm
	rm -f tests/nanoc0-stmt/RET8OUT.ASM tests/nanoc0-stmt/ret8out.asm tests/nanoc0-stmt/STMTOUT.ASM tests/nanoc0-stmt/stmtout.asm
	rm -f tests/nanoc0-runtime/RTOUT.ASM tests/nanoc0-runtime/rtout.asm tests/nanoc0-runtime/SMOKE.ASM tests/nanoc0-runtime/smoke.asm tests/nanoc0-runtime/DTEST tests/nanoc0-runtime/dtest