	include "../test.inc"

ST_GENERATED_ENTRY = $0800
ST_TEST_ENTRY      = $2c00

ST_FAIL_RETURN_ASSEMBLE    = $10
ST_FAIL_RETURN_VALUE       = $20
ST_FAIL_STATEMENT_ASSEMBLE = $30
ST_FAIL_STATEMENT_VALUE    = $40

;;; Workspace mailbox saved with TEST_RESULT by tests/run-test.sh while the
;;; fixed symbol-table split is being measured. Packed tables need one end
;;; pointer each.
ST_PERSIST_END = $03
ST_LOCAL_END   = $05

;;; Keep the test harness below ass's command block so the production assembler
;;; can occupy its exact $4000 image without extending into $6000 staging.
	* = ST_TEST_ENTRY

main:
	lda #<returnGeneratedName
	sta ASSEMBLER_COMMAND_NAME
	lda #>returnGeneratedName
	sta ASSEMBLER_COMMAND_NAME+1
	lda #returnGeneratedNameEnd-returnGeneratedName
	sta ASSEMBLER_COMMAND_LENGTH
	lda #<ST_GENERATED_ENTRY
	sta ASSEMBLER_COMMAND_TARGET
	lda #>ST_GENERATED_ENTRY
	sta ASSEMBLER_COMMAND_TARGET+1
	jsr assemblerEntry
	cmp #ASSEMBLE_OK
	beq .runReturn
	jsr captureWorkspace
	lda ASSEMBLER_COMMAND_STATUS
	ora #ST_FAIL_RETURN_ASSEMBLE
	jmp .finish

.runReturn:
	jsr ST_GENERATED_ENTRY
	cmp #$5a
	bne .badReturn
	cpx #$00
	bne .badReturn

	lda #<statementGeneratedName
	sta ASSEMBLER_COMMAND_NAME
	lda #>statementGeneratedName
	sta ASSEMBLER_COMMAND_NAME+1
	lda #statementGeneratedNameEnd-statementGeneratedName
	sta ASSEMBLER_COMMAND_LENGTH
	lda #<ST_GENERATED_ENTRY
	sta ASSEMBLER_COMMAND_TARGET
	lda #>ST_GENERATED_ENTRY
	sta ASSEMBLER_COMMAND_TARGET+1
	jsr assemblerEntry
	cmp #ASSEMBLE_OK
	bne .statementAssembleFailed
	jsr captureWorkspace
	jmp .runStatements
.statementAssembleFailed:
	jsr captureWorkspace
	lda ASSEMBLER_COMMAND_STATUS
	ora #ST_FAIL_STATEMENT_ASSEMBLE
	jmp .finish

.runStatements:
	jsr ST_GENERATED_ENTRY
	sta stReturnedLow
	stx stReturnedHigh
	cmp #$34
	bne .badStatements
	cpx #$12
	bne .badStatements
	lda #TEST_PASS
	jmp .finish

.badReturn:
	lda #ST_FAIL_RETURN_VALUE
	jmp .finish
.badStatements:
	lda stReturnedLow
	beq .genericStatementFail
	jmp .finish
.genericStatementFail:
	lda #ST_FAIL_STATEMENT_VALUE
.finish:
	sta TEST_RESULT
.halt:
	jmp .halt

captureWorkspace:
	lda symbolTableEnd
	sta ST_PERSIST_END
	lda symbolTableEnd+1
	sta ST_PERSIST_END+1
	lda localSymbolTableEnd
	sta ST_LOCAL_END
	lda localSymbolTableEnd+1
	sta ST_LOCAL_END+1
	rts

;;; Execution mounts the repository root so generated source can use the same
;;; target-helper include paths emitted by production nanoc0.
returnGeneratedName:
	byte 'T','E','S','T','S','/','N','A','N','O','C','0','-','S','T','M','T','/','R','E','T','8','O','U','T','.','A','S','M'
returnGeneratedNameEnd:
statementGeneratedName:
	byte 'T','E','S','T','S','/','N','A','N','O','C','0','-','S','T','M','T','/','S','T','M','T','O','U','T','.','A','S','M'
statementGeneratedNameEnd:

stReturnedLow:	byte 0
stReturnedHigh:	byte 0

	* = ASSEMBLER_TEST_ENTRY
	include "ass.asm"
