;;; 6502 OPCODE TABLE
;;; Each entry is: .byte mnemonic_index, mode_index
;;; Undocumented opcodes filled with $FF, $FF
;;; ----------------------------------------------------------------------
;;; 57 mnemonics, indexed in this order:
;;; ADC AND ASL BCC BCS BEQ BIT BMI BNE BPL BRK BVC BVS 
;;; CLC CLD CLI CLV CMP CPX CPY DEC DEX DEY EOR INC INX INY
;;; JMP JSR LDA LDX LDY LSR NOP ORA PHA PHP PLA PLP ROL
;;; ROR RTI RTS SBC SEC SED SEI STA STX STY TAX TAY TSX
;;; TXA TXS TYA ???
;;; ----------------------------------------------------------------------
;;; Addresing modes
;;; 
;;; | Mode        | Index |
;;; | ----------- | ---- |
;;; | IMPLIED     | 0    |
;;; | ACCUMULATOR | 1    |
;;; | IMMEDIATE   | 2    |
;;; | ZEROPAGE    | 3    |
;;; | ZEROPAGE\_X | 4    |
;;; | ZEROPAGE\_Y | 5    |
;;; | ABSOLUTE    | 6    |
;;; | ABSOLUTE\_X | 7    |
;;; | ABSOLUTE\_Y | 8    |
;;; | INDIRECT    | 9    |
;;; | INDIRECT\_X | a    |
;;; | INDIRECT\_Y | b    |
;;; | RELATIVE    | c    |
;;; | UNDOC       | d    |
;;; Addressing mode formatters are in modes.asm

opcode_table:	
	byte $0A, $00 ; $00: BRK impl
	byte $22, $0A ; $01: ORA indx
	byte $38, $0D ; undocumented
	byte $38, $0D ; undocumented
	byte $38, $0D ; undocumented
	byte $22, $03 ; $05: ORA zp
	byte $02, $03 ; $06: ASL zp
	byte $38, $0D ; undocumented
	byte $24, $00 ; $08: PHP impl
	byte $22, $02 ; $09: ORA imm
	byte $02, $01 ; $0A: ASL acc
	byte $38, $0D ; undocumented
	byte $38, $0D ; undocumented
	byte $22, $06 ; $0D: ORA abs
	byte $02, $06 ; $0E: ASL abs
	byte $38, $0D ; undocumented
	byte $09, $0C ; $10: BPL rel
	byte $22, $0B ; $11: ORA indy
	byte $38, $0D ; undocumented
	byte $38, $0D ; undocumented
	byte $38, $0D ; undocumented
	byte $22, $04 ; $15: ORA zpx
	byte $02, $04 ; $16: ASL zpx
	byte $38, $0D ; undocumented
	byte $0D, $00 ; $18: CLC impl
	byte $22, $08 ; $19: ORA absy
	byte $38, $0D ; undocumented
	byte $38, $0D ; undocumented
	byte $38, $0D ; undocumented
	byte $22, $07 ; $1D: ORA absx
	byte $02, $07 ; $1E: ASL absx
	byte $38, $0D ; undocumented
	byte $1C, $06 ; $20: JSR abs
	byte $01, $0A ; $21: AND indx
	byte $38, $0D ; undocumented
	byte $38, $0D ; undocumented
	byte $06, $03 ; $24: BIT zp
	byte $01, $03 ; $25: AND zp
	byte $27, $03 ; $26: ROL zp
	byte $38, $0D ; undocumented
	byte $26, $00 ; $28: PLP impl
	byte $01, $02 ; $29: AND imm
	byte $27, $01 ; $2A: ROL acc
	byte $38, $0D ; undocumented
	byte $06, $06 ; $2C: BIT abs
	byte $01, $06 ; $2D: AND abs
	byte $27, $06 ; $2E: ROL abs
	byte $38, $0D ; undocumented
	byte $07, $0C ; $30: BMI rel
	byte $01, $0B ; $31: AND indy
	byte $38, $0D ; undocumented
	byte $38, $0D ; undocumented
	byte $38, $0D ; undocumented
	byte $01, $04 ; $35: AND zpx
	byte $27, $04 ; $36: ROL zpx
	byte $38, $0D ; undocumented
	byte $2C, $00 ; $38: SEC impl
	byte $01, $08 ; $39: AND absy
	byte $38, $0D ; undocumented
	byte $38, $0D ; undocumented
	byte $38, $0D ; undocumented
	byte $01, $07 ; $3D: AND absx
	byte $27, $07 ; $3E: ROL absx
	byte $38, $0D ; undocumented
	byte $29, $00 ; $40: RTI impl
	byte $17, $0A ; $41: EOR indx
	byte $38, $0D ; undocumented
	byte $38, $0D ; undocumented
	byte $38, $0D ; undocumented
	byte $17, $03 ; $45: EOR zp
	byte $20, $03 ; $46: LSR zp
	byte $38, $0D ; undocumented
	byte $23, $00 ; $48: PHA impl
	byte $17, $02 ; $49: EOR imm
	byte $20, $01 ; $4A: LSR acc
	byte $38, $0D ; undocumented
	byte $1B, $06 ; $4C: JMP abs
	byte $17, $06 ; $4D: EOR abs
	byte $20, $06 ; $4E: LSR abs
	byte $38, $0D ; undocumented
	byte $0B, $0C ; $50: BVC rel
	byte $17, $0B ; $51: EOR indy
	byte $38, $0D ; undocumented
	byte $38, $0D ; undocumented
	byte $38, $0D ; undocumented
	byte $17, $04 ; $55: EOR zpx
	byte $20, $04 ; $56: LSR zpx
	byte $38, $0D ; undocumented
	byte $0F, $00 ; $58: CLI impl
	byte $17, $08 ; $59: EOR absy
	byte $38, $0D ; undocumented
	byte $38, $0D ; undocumented
	byte $38, $0D ; undocumented
	byte $17, $07 ; $5D: EOR absx
	byte $20, $07 ; $5E: LSR absx
	byte $38, $0D ; undocumented
	byte $2A, $00 ; $60: RTS impl
	byte $00, $0A ; $61: ADC indx
	byte $38, $0D ; undocumented
	byte $38, $0D ; undocumented
	byte $38, $0D ; undocumented
	byte $00, $03 ; $65: ADC zp
	byte $28, $03 ; $66: ROR zp
	byte $38, $0D ; undocumented
	byte $25, $00 ; $68: PLA impl
	byte $00, $02 ; $69: ADC imm
	byte $28, $01 ; $6A: ROR acc
	byte $38, $0D ; undocumented
	byte $1B, $09 ; $6C: JMP ind
	byte $00, $06 ; $6D: ADC abs
	byte $28, $06 ; $6E: ROR abs
	byte $38, $0D ; undocumented
	byte $0C, $0C ; $70: BVS rel
	byte $00, $0B ; $71: ADC indy
	byte $38, $0D ; undocumented
	byte $38, $0D ; undocumented
	byte $38, $0D ; undocumented
	byte $00, $04 ; $75: ADC zpx
	byte $28, $04 ; $76: ROR zpx
	byte $38, $0D ; undocumented
	byte $2E, $00 ; $78: SEI impl
	byte $00, $08 ; $79: ADC absy
	byte $38, $0D ; undocumented
	byte $38, $0D ; undocumented
	byte $38, $0D ; undocumented
	byte $00, $07 ; $7D: ADC absx
	byte $28, $07 ; $7E: ROR absx
	byte $38, $0D ; undocumented
	byte $38, $0D ; undocumented
	byte $2F, $0A ; $81: STA indx
	byte $38, $0D ; undocumented
	byte $38, $0D ; undocumented
	byte $31, $03 ; $84: STY zp
	byte $2F, $03 ; $85: STA zp
	byte $30, $03 ; $86: STX zp
	byte $38, $0D ; undocumented
	byte $16, $00 ; $88: DEY impl
	byte $38, $0D ; undocumented
	byte $35, $00 ; $8A: TXA impl
	byte $38, $0D ; undocumented
	byte $31, $06 ; $8C: STY abs
	byte $2F, $06 ; $8D: STA abs
	byte $30, $06 ; $8E: STX abs
	byte $38, $0D ; undocumented
	byte $03, $0C ; $90: BCC rel
	byte $2F, $0B ; $91: STA indy
	byte $38, $0D ; undocumented
	byte $38, $0D ; undocumented
	byte $31, $04 ; $94: STY zpx
	byte $2F, $04 ; $95: STA zpx
	byte $30, $05 ; $96: STX zpy
	byte $38, $0D ; undocumented
	byte $37, $00 ; $98: TYA impl
	byte $2F, $08 ; $99: STA absy
	byte $36, $00 ; $9A: TXS impl
	byte $38, $0D ; undocumented
	byte $38, $0D ; undocumented
	byte $2F, $07 ; $9D: STA absx
	byte $38, $0D ; undocumented
	byte $38, $0D ; undocumented
	byte $1F, $02 ; $A0: LDY imm
	byte $1D, $0A ; $A1: LDA indx
	byte $1E, $02 ; $A2: LDX imm
	byte $38, $0D ; undocumented
	byte $1F, $03 ; $A4: LDY zp
	byte $1D, $03 ; $A5: LDA zp
	byte $1E, $03 ; $A6: LDX zp
	byte $38, $0D ; undocumented
	byte $33, $00 ; $A8: TAY impl
	byte $1D, $02 ; $A9: LDA imm
	byte $32, $00 ; $AA: TAX impl
	byte $38, $0D ; undocumented
	byte $1F, $06 ; $AC: LDY abs
	byte $1D, $06 ; $AD: LDA abs
	byte $1E, $06 ; $AE: LDX abs
	byte $38, $0D ; undocumented
	byte $04, $0C ; $B0: BCS rel
	byte $1D, $0B ; $B1: LDA indy
	byte $38, $0D ; undocumented
	byte $38, $0D ; undocumented
	byte $1F, $04 ; $B4: LDY zpx
	byte $1D, $04 ; $B5: LDA zpx
	byte $1E, $05 ; $B6: LDX zpy
	byte $38, $0D ; undocumented
	byte $10, $00 ; $B8: CLV impl
	byte $1D, $08 ; $B9: LDA absy
	byte $34, $00 ; $BA: TSX impl
	byte $38, $0D ; undocumented
	byte $1F, $07 ; $BC: LDY absx
	byte $1D, $07 ; $BD: LDA absx
	byte $1E, $08 ; $BE: LDX absy
	byte $38, $0D ; undocumented
	byte $13, $02 ; $C0: CPY imm
	byte $11, $0A ; $C1: CMP indx
	byte $38, $0D ; undocumented
	byte $38, $0D ; undocumented
	byte $13, $03 ; $C4: CPY zp
	byte $11, $03 ; $C5: CMP zp
	byte $14, $03 ; $C6: DEC zp
	byte $38, $0D ; undocumented
	byte $1A, $00 ; $C8: INY impl
	byte $11, $02 ; $C9: CMP imm
	byte $15, $00 ; $CA: DEX impl
	byte $38, $0D ; undocumented
	byte $13, $06 ; $CC: CPY abs
	byte $11, $06 ; $CD: CMP abs
	byte $14, $06 ; $CE: DEC abs
	byte $38, $0D ; undocumented
	byte $08, $0C ; $D0: BNE rel
	byte $11, $0B ; $D1: CMP indy
	byte $38, $0D ; undocumented
	byte $38, $0D ; undocumented
	byte $38, $0D ; undocumented
	byte $11, $04 ; $D5: CMP zpx
	byte $14, $04 ; $D6: DEC zpx
	byte $38, $0D ; undocumented
	byte $0E, $00 ; $D8: CLD impl
	byte $11, $08 ; $D9: CMP absy
	byte $38, $0D ; undocumented
	byte $38, $0D ; undocumented
	byte $38, $0D ; undocumented
	byte $11, $07 ; $DD: CMP absx
	byte $14, $07 ; $DE: DEC absx
	byte $38, $0D ; undocumented
	byte $12, $02 ; $E0: CPX imm
	byte $2B, $0A ; $E1: SBC indx
	byte $38, $0D ; undocumented
	byte $38, $0D ; undocumented
	byte $12, $03 ; $E4: CPX zp
	byte $2B, $03 ; $E5: SBC zp
	byte $18, $03 ; $E6: INC zp
	byte $38, $0D ; undocumented
	byte $19, $00 ; $E8: INX impl
	byte $2B, $02 ; $E9: SBC imm
	byte $21, $00 ; $EA: NOP impl
	byte $38, $0D ; undocumented
	byte $12, $06 ; $EC: CPX abs
	byte $2B, $06 ; $ED: SBC abs
	byte $18, $06 ; $EE: INC abs
	byte $38, $0D ; undocumented
	byte $05, $0C ; $F0: BEQ rel
	byte $2B, $0B ; $F1: SBC indy
	byte $38, $0D ; undocumented
	byte $38, $0D ; undocumented
	byte $38, $0D ; undocumented
	byte $2B, $04 ; $F5: SBC zpx
	byte $18, $04 ; $F6: INC zpx
	byte $38, $0D ; undocumented
	byte $2D, $00 ; $F8: SED impl
	byte $2B, $08 ; $F9: SBC absy
	byte $38, $0D ; undocumented
	byte $38, $0D ; undocumented
	byte $38, $0D ; undocumented
	byte $2B, $07 ; $FD: SBC absx
	byte $18, $07 ; $FE: INC absx
	byte $38, $0D ; undocumented
	
