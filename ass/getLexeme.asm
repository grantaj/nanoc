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
;;; X = token type

;;; Token Types
	SYMBOL = 0
	COMMA = 1
	PERIOD = 2
	COLON = 3
	EQUALS = 4
	LPAREN = 5
	RPAREN = 6
	PLUS = 7

getLexeme:
	tya			; save Y
	pha

	ldx #$0			; X=1 - token is string, X=0 - token is special character
	ldy #$0			; Index for pointer
.loop:
	lda (ZP_PTR1),Y
	cmp #' '		; space
	beq .done
	cmp #$09		; tab
	beq .done
	cmp #$0			; NULL
	beq .done

	cmp #','
	bne .tokenIsSymbol
	ldx #COMMA
	jmp .specialCharacter
	
	cmp #'.'
	bne .tokenIsSymbol
	ldx #PERIOD
	jmp .specialCharacter
	cmp #':'
	beq .specialCharacter	
	cmp #'='
	beq .specialCharacter	
	cmp #'('
	beq .specialCharacter	
	cmp #')'
	beq .specialCharacter	
	cmp #'+'
	beq .specialCharacter

.tokenIsSymbol:
	ldx #SYMBOL	   	; token is a string
	jmp .copyCharacter	; no special character - copy the character
	
;;; If we are at the start of a token, the special character IS the token.
;;; Otherwise, the special character terminates the current token and we
;;; Leave it to be toeknised as the next token

.specialCharacter:
	cpx #SYMBOL
	beq .done		; special character ends current token
	;; fall-through: copy the special character as the token
	
.copyCharacter:
	sta (ZP_PTR0),Y		; copy character to ouput
	
	inc ZP_PTR1
	bne .incTokenPtr
	inc ZP_PTR1+1

.incTokenPtr:

	inc ZP_PTR0
	bne .done
	inc ZP_PTR0+1
	
	cpx #$00		; token was a special character - stop
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

	
