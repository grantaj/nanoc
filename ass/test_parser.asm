	include "zp.inc"
	include "../test.inc"

	* = TEST_ENTRY

main:
	lda #<input
	sta ZP_PTR1
	lda #>input
	sta ZP_PTR1+1
	lda #<inputEnd
	sta sourceEnd
	lda #>inputEnd
	sta sourceEnd+1

	;; Comment-only and blank lines are skipped before the first statement.
	jsr nextStatement
	cmp #STATEMENT_LABEL
	beq .labelTypeOk
	lda #$01
	jmp .finish
.labelTypeOk:
	lda statementName
	cmp #<labelName
	beq .labelLowOk
	lda #$02
	jmp .finish
.labelLowOk:
	lda statementName+1
	cmp #>labelName
	beq .labelHighOk
	lda #$03
	jmp .finish
.labelHighOk:
	lda statementNameLength
	cmp #$05
	beq .labelLengthOk
	lda #$04
	jmp .finish
.labelLengthOk:
	lda statementArgumentLength
	beq .symbolCase
	lda #$05
	jmp .finish

.symbolCase:
	jsr nextStatement
	cmp #STATEMENT_SYMBOL
	beq .symbolTypeOk
	lda #$06
	jmp .finish
.symbolTypeOk:
	lda statementName
	cmp #<symbolName
	beq .symbolNameLowOk
	lda #$07
	jmp .finish
.symbolNameLowOk:
	lda statementName+1
	cmp #>symbolName
	beq .symbolNameHighOk
	lda #$08
	jmp .finish
.symbolNameHighOk:
	lda statementNameLength
	cmp #$01
	beq .symbolNameLengthOk
	lda #$09
	jmp .finish
.symbolNameLengthOk:
	lda statementArgument
	cmp #<symbolValue
	beq .symbolArgLowOk
	lda #$0a
	jmp .finish
.symbolArgLowOk:
	lda statementArgument+1
	cmp #>symbolValue
	beq .symbolArgHighOk
	lda #$0b
	jmp .finish
.symbolArgHighOk:
	lda statementArgumentLength
	cmp #$05
	beq .directiveCase
	lda #$0c
	jmp .finish

.directiveCase:
	jsr nextStatement
	cmp #STATEMENT_DIRECTIVE
	beq .directiveTypeOk
	lda #$0d
	jmp .finish
.directiveTypeOk:
	lda statementName
	cmp #<directiveName
	beq .directiveNameLowOk
	lda #$0e
	jmp .finish
.directiveNameLowOk:
	lda statementName+1
	cmp #>directiveName
	beq .directiveNameHighOk
	lda #$0f
	jmp .finish
.directiveNameHighOk:
	lda statementNameLength
	cmp #$04
	beq .directiveNameLengthOk
	lda #$10
	jmp .finish
.directiveNameLengthOk:
	lda statementArgument
	cmp #<directiveArgument
	beq .directiveArgLowOk
	lda #$11
	jmp .finish
.directiveArgLowOk:
	lda statementArgument+1
	cmp #>directiveArgument
	beq .directiveArgHighOk
	lda #$12
	jmp .finish
.directiveArgHighOk:
	lda statementArgumentLength
	cmp #$07
	beq .instructionCase
	lda #$13
	jmp .finish

.instructionCase:
	jsr nextStatement
	cmp #STATEMENT_INSTRUCTION
	beq .instructionTypeOk
	lda #$14
	jmp .finish
.instructionTypeOk:
	lda statementName
	cmp #<instructionName
	beq .instructionNameLowOk
	lda #$15
	jmp .finish
.instructionNameLowOk:
	lda statementName+1
	cmp #>instructionName
	beq .instructionNameHighOk
	lda #$16
	jmp .finish
.instructionNameHighOk:
	lda statementNameLength
	cmp #$03
	beq .instructionNameLengthOk
	lda #$17
	jmp .finish
.instructionNameLengthOk:
	lda statementArgument
	cmp #<instructionArgument
	beq .instructionArgLowOk
	lda #$18
	jmp .finish
.instructionArgLowOk:
	lda statementArgument+1
	cmp #>instructionArgument
	beq .instructionArgHighOk
	lda #$19
	jmp .finish
.instructionArgHighOk:
	lda statementArgumentLength
	cmp #$04
	beq .noOperandCase
	lda #$1a
	jmp .finish

.noOperandCase:
	jsr nextStatement
	cmp #STATEMENT_INSTRUCTION
	beq .noOperandTypeOk
	lda #$1b
	jmp .finish
.noOperandTypeOk:
	lda statementName
	cmp #<noOperandName
	beq .noOperandNameLowOk
	lda #$1c
	jmp .finish
.noOperandNameLowOk:
	lda statementName+1
	cmp #>noOperandName
	beq .noOperandNameHighOk
	lda #$1d
	jmp .finish
.noOperandNameHighOk:
	lda statementNameLength
	cmp #$03
	beq .noOperandNameLengthOk
	lda #$1e
	jmp .finish
.noOperandNameLengthOk:
	lda statementArgumentLength
	beq .eofCase
	lda #$1f
	jmp .finish

.eofCase:
	jsr nextStatement
	cmp #STATEMENT_EOF
	beq .eofTypeOk
	lda #$20
	jmp .finish
.eofTypeOk:
	lda ZP_PTR1
	cmp #<inputEnd
	beq .eofLowOk
	lda #$21
	jmp .finish
.eofLowOk:
	lda ZP_PTR1+1
	cmp #>inputEnd
	beq .pass
	lda #$22
	jmp .finish

.pass:
	lda #TEST_PASS
.finish:
	sta TEST_RESULT
.halt:
	jmp .halt

	include "parser.asm"

	* = $c500
input:
	string "; comment-only line"
	byte 0			; blank line

labelName:
	byte 'S','T','A','R','T',':',0

symbolName:
	byte '*',' ','=',' '
symbolValue:
	byte '$','C','0','0','0',0

	byte '.'
directiveName:
	byte 'B','Y','T','E',' '
directiveArgument:
	byte '0',',',' ','1',',',' ','2',0

instructionName:
	byte 'L','D','A',' '
instructionArgument:
	byte '#','$','0','0',' ',' ',';',' ','c','o','m','m','e','n','t',0

noOperandName:
	byte 'R','T','S',0
inputEnd:
