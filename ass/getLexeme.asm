;;; getlexeme
;;; 
;;; Consume next token
;;; ZP_PTR1, ZP_PTR1+1 points to input data
;;; ZP_PTR0, ZP_PTR0+1 points to token value
;;;
;;; Copy string from ZP_PTR1 to ZP_PTR0
;;; stopping when reaching space, tab or NULL
;;; These pointers are advanced
;;; Stored token value is NULL terminated
;;; 
;;; For now, tokens must be delimited by whitespace
;;;
;;; X, Y preserved
;;; A returns last character in token

getlexeme:
	tya			; save Y
	pha
	
	ldy #$0
	lda (ZP_PTR1),Y
	cmp #' '		; space
	beq .done
	cmp ##09		; tab
	beq .done
	cmp #$0			; NULL
	beq .done
	
	sta (ZP_PTR0),Y		; copy character to ouput
	
	inc ZP_PTR1
	bne .incTokenPtr
	inc ZP_PTR1+1

.incTokenPtr:

	inc ZP_PTR0
	bne .done
	inc ZP_PTR0+1
	
.done:
	;; NULL terminate lexeme value
	lda #$0			; NULL terminate token value
	sta (ZP_PTR0),y

	ldy #$ff		; get last character of token
	lda (ZP_PTR0),y
	sta .lastCharacter
	
	inc ZP_PTR0
	bne .return
	inc ZP_PTR0+1
	
.return:
	
	pla			; restore Y
	tay
	lda .lastCharacter	; Return final character in A
	rts

.lastCharacter:
	byte 0
	
