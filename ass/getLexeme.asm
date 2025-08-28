;;; getlexeme
;;; 
;;; Consume next token
;;; ZP_PTR1, ZP_PTR1+1 points to input data
;;; ZP_PTR0, ZP_PTR0+1 points to token value
;;;
;;; Copy string from ZP_PTR1 to ZP_PTR0
;;; stopping when reaching any one of:
;;; space tab NULL , . : = ( ) +
;;; These pointers are advanced
;;; Stored token value is NULL terminated
;;; 
;;; For now, tokens must be delimited by whitespace
;;;
;;; Y preserved
;;; X = token type: 0 = SYMBOL, 1 = SPECIAL CHARACTER ,.:=()+#$

;;; Token Types
	SYMBOL = 0
	SPECIAL = 1
	UNDEFINED = $FF

getLexeme:
	tya			; save Y
	pha

	ldy #$0			; Index for pointer
	ldx #UNDEFINED		; Default value
.loop:
	lda (ZP_PTR1),Y		; whitespace terminates token
	beq .done		; NULL
	cmp #' '		; space
	beq .done
	cmp #$09		; tab
	beq .done

;;; Check all the special characters
.COMMA:
	cmp #','
	beq .specialCharacter
.PERIOD:	
	cmp #'.'
	beq .specialCharacter
.COLON:	
	cmp #':'
	beq .specialCharacter
.EQUALS:
	cmp #'='
	beq .specialCharacter
.LPAREN:
	cmp #'('
	beq .specialCharacter
.RPAREN:
	cmp #')'
	beq .specialCharacter
.PLUS:
	cmp #'+'
	beq .specialCharacter
.HASH:
	cmp #'#'
	beq .specialCharacter
.DOLLAR:
	cmp #'$'
	beq .specialCharacter
.STAR:
	cmp #'*'
	beq .specialCharacter
	
;;; Default: Not SPECIAL -> SYMBOL
.SYMBOL:
	ldx #SYMBOL	   	; token is a string
	jmp .copyCharacter	
	
;;; If we are at the start of a token, the special character IS the token.
;;; Otherwise, the special character terminates the current token and we
;;; Leave it to be toeknised as the next token

.specialCharacter:
	cpx #SYMBOL
	beq .done		; special character ends SYMBOL
	ldx #SPECIAL		; fall-through: copy special character as the token
	
.copyCharacter:
	sta (ZP_PTR0),Y		; copy character to ouput
	
	inc ZP_PTR1		; increment input pointer
	bne .incTokenPtr
	inc ZP_PTR1+1

.incTokenPtr:

	inc ZP_PTR0		; increment token value pointer
	bne .checkSpecial
	inc ZP_PTR0+1

.checkSpecial:
	cpx #SPECIAL		
	beq .done
	jmp .loop		; otherwise continue
	
.done:
	;; NULL terminate lexeme value
	lda #$0			; NULL terminate token value
	sta (ZP_PTR0),y
	
	inc ZP_PTR0
	bne .return
	inc ZP_PTR0+1
	
.return:
	pla			; restore Y
	tay
	rts

	
