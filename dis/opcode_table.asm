;;; 6502 OPCODE TABLE
;;; Each entry is: .byte mnemonic_index, MODE_*
;;; Undocumented opcodes use mnemonic $38 ('???') and MODE_UNDOCUMENTED.
;;; The MODE_* values are shared with the disassembler in mode_ids.inc.
;;; ----------------------------------------------------------------------
;;; 57 mnemonic entries, indexed in this order:
;;; ADC AND ASL BCC BCS BEQ BIT BMI BNE BPL BRK BVC BVS
;;; CLC CLD CLI CLV CMP CPX CPY DEC DEX DEY EOR INC INX INY
;;; JMP JSR LDA LDX LDY LSR NOP ORA PHA PHP PLA PLP ROL
;;; ROR RTI RTS SBC SEC SED SEI STA STX STY TAX TAY TSX
;;; TXA TXS TYA ???

opcode_table:
	byte $0A, MODE_IMPLIED ; $00: BRK impl
	byte $22, MODE_INDIRECT_X ; $01: ORA indx
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $22, MODE_ZERO_PAGE ; $05: ORA zp
	byte $02, MODE_ZERO_PAGE ; $06: ASL zp
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $24, MODE_IMPLIED ; $08: PHP impl
	byte $22, MODE_IMMEDIATE ; $09: ORA imm
	byte $02, MODE_ACCUMULATOR ; $0A: ASL acc
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $22, MODE_ABSOLUTE ; $0D: ORA abs
	byte $02, MODE_ABSOLUTE ; $0E: ASL abs
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $09, MODE_RELATIVE ; $10: BPL rel
	byte $22, MODE_INDIRECT_Y ; $11: ORA indy
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $22, MODE_ZERO_PAGE_X ; $15: ORA zpx
	byte $02, MODE_ZERO_PAGE_X ; $16: ASL zpx
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $0D, MODE_IMPLIED ; $18: CLC impl
	byte $22, MODE_ABSOLUTE_Y ; $19: ORA absy
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $22, MODE_ABSOLUTE_X ; $1D: ORA absx
	byte $02, MODE_ABSOLUTE_X ; $1E: ASL absx
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $1C, MODE_ABSOLUTE ; $20: JSR abs
	byte $01, MODE_INDIRECT_X ; $21: AND indx
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $06, MODE_ZERO_PAGE ; $24: BIT zp
	byte $01, MODE_ZERO_PAGE ; $25: AND zp
	byte $27, MODE_ZERO_PAGE ; $26: ROL zp
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $26, MODE_IMPLIED ; $28: PLP impl
	byte $01, MODE_IMMEDIATE ; $29: AND imm
	byte $27, MODE_ACCUMULATOR ; $2A: ROL acc
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $06, MODE_ABSOLUTE ; $2C: BIT abs
	byte $01, MODE_ABSOLUTE ; $2D: AND abs
	byte $27, MODE_ABSOLUTE ; $2E: ROL abs
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $07, MODE_RELATIVE ; $30: BMI rel
	byte $01, MODE_INDIRECT_Y ; $31: AND indy
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $01, MODE_ZERO_PAGE_X ; $35: AND zpx
	byte $27, MODE_ZERO_PAGE_X ; $36: ROL zpx
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $2C, MODE_IMPLIED ; $38: SEC impl
	byte $01, MODE_ABSOLUTE_Y ; $39: AND absy
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $01, MODE_ABSOLUTE_X ; $3D: AND absx
	byte $27, MODE_ABSOLUTE_X ; $3E: ROL absx
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $29, MODE_IMPLIED ; $40: RTI impl
	byte $17, MODE_INDIRECT_X ; $41: EOR indx
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $17, MODE_ZERO_PAGE ; $45: EOR zp
	byte $20, MODE_ZERO_PAGE ; $46: LSR zp
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $23, MODE_IMPLIED ; $48: PHA impl
	byte $17, MODE_IMMEDIATE ; $49: EOR imm
	byte $20, MODE_ACCUMULATOR ; $4A: LSR acc
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $1B, MODE_ABSOLUTE ; $4C: JMP abs
	byte $17, MODE_ABSOLUTE ; $4D: EOR abs
	byte $20, MODE_ABSOLUTE ; $4E: LSR abs
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $0B, MODE_RELATIVE ; $50: BVC rel
	byte $17, MODE_INDIRECT_Y ; $51: EOR indy
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $17, MODE_ZERO_PAGE_X ; $55: EOR zpx
	byte $20, MODE_ZERO_PAGE_X ; $56: LSR zpx
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $0F, MODE_IMPLIED ; $58: CLI impl
	byte $17, MODE_ABSOLUTE_Y ; $59: EOR absy
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $17, MODE_ABSOLUTE_X ; $5D: EOR absx
	byte $20, MODE_ABSOLUTE_X ; $5E: LSR absx
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $2A, MODE_IMPLIED ; $60: RTS impl
	byte $00, MODE_INDIRECT_X ; $61: ADC indx
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $00, MODE_ZERO_PAGE ; $65: ADC zp
	byte $28, MODE_ZERO_PAGE ; $66: ROR zp
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $25, MODE_IMPLIED ; $68: PLA impl
	byte $00, MODE_IMMEDIATE ; $69: ADC imm
	byte $28, MODE_ACCUMULATOR ; $6A: ROR acc
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $1B, MODE_INDIRECT ; $6C: JMP ind
	byte $00, MODE_ABSOLUTE ; $6D: ADC abs
	byte $28, MODE_ABSOLUTE ; $6E: ROR abs
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $0C, MODE_RELATIVE ; $70: BVS rel
	byte $00, MODE_INDIRECT_Y ; $71: ADC indy
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $00, MODE_ZERO_PAGE_X ; $75: ADC zpx
	byte $28, MODE_ZERO_PAGE_X ; $76: ROR zpx
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $2E, MODE_IMPLIED ; $78: SEI impl
	byte $00, MODE_ABSOLUTE_Y ; $79: ADC absy
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $00, MODE_ABSOLUTE_X ; $7D: ADC absx
	byte $28, MODE_ABSOLUTE_X ; $7E: ROR absx
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $2F, MODE_INDIRECT_X ; $81: STA indx
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $31, MODE_ZERO_PAGE ; $84: STY zp
	byte $2F, MODE_ZERO_PAGE ; $85: STA zp
	byte $30, MODE_ZERO_PAGE ; $86: STX zp
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $16, MODE_IMPLIED ; $88: DEY impl
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $35, MODE_IMPLIED ; $8A: TXA impl
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $31, MODE_ABSOLUTE ; $8C: STY abs
	byte $2F, MODE_ABSOLUTE ; $8D: STA abs
	byte $30, MODE_ABSOLUTE ; $8E: STX abs
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $03, MODE_RELATIVE ; $90: BCC rel
	byte $2F, MODE_INDIRECT_Y ; $91: STA indy
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $31, MODE_ZERO_PAGE_X ; $94: STY zpx
	byte $2F, MODE_ZERO_PAGE_X ; $95: STA zpx
	byte $30, MODE_ZERO_PAGE_Y ; $96: STX zpy
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $37, MODE_IMPLIED ; $98: TYA impl
	byte $2F, MODE_ABSOLUTE_Y ; $99: STA absy
	byte $36, MODE_IMPLIED ; $9A: TXS impl
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $2F, MODE_ABSOLUTE_X ; $9D: STA absx
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $1F, MODE_IMMEDIATE ; $A0: LDY imm
	byte $1D, MODE_INDIRECT_X ; $A1: LDA indx
	byte $1E, MODE_IMMEDIATE ; $A2: LDX imm
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $1F, MODE_ZERO_PAGE ; $A4: LDY zp
	byte $1D, MODE_ZERO_PAGE ; $A5: LDA zp
	byte $1E, MODE_ZERO_PAGE ; $A6: LDX zp
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $33, MODE_IMPLIED ; $A8: TAY impl
	byte $1D, MODE_IMMEDIATE ; $A9: LDA imm
	byte $32, MODE_IMPLIED ; $AA: TAX impl
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $1F, MODE_ABSOLUTE ; $AC: LDY abs
	byte $1D, MODE_ABSOLUTE ; $AD: LDA abs
	byte $1E, MODE_ABSOLUTE ; $AE: LDX abs
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $04, MODE_RELATIVE ; $B0: BCS rel
	byte $1D, MODE_INDIRECT_Y ; $B1: LDA indy
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $1F, MODE_ZERO_PAGE_X ; $B4: LDY zpx
	byte $1D, MODE_ZERO_PAGE_X ; $B5: LDA zpx
	byte $1E, MODE_ZERO_PAGE_Y ; $B6: LDX zpy
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $10, MODE_IMPLIED ; $B8: CLV impl
	byte $1D, MODE_ABSOLUTE_Y ; $B9: LDA absy
	byte $34, MODE_IMPLIED ; $BA: TSX impl
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $1F, MODE_ABSOLUTE_X ; $BC: LDY absx
	byte $1D, MODE_ABSOLUTE_X ; $BD: LDA absx
	byte $1E, MODE_ABSOLUTE_Y ; $BE: LDX absy
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $13, MODE_IMMEDIATE ; $C0: CPY imm
	byte $11, MODE_INDIRECT_X ; $C1: CMP indx
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $13, MODE_ZERO_PAGE ; $C4: CPY zp
	byte $11, MODE_ZERO_PAGE ; $C5: CMP zp
	byte $14, MODE_ZERO_PAGE ; $C6: DEC zp
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $1A, MODE_IMPLIED ; $C8: INY impl
	byte $11, MODE_IMMEDIATE ; $C9: CMP imm
	byte $15, MODE_IMPLIED ; $CA: DEX impl
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $13, MODE_ABSOLUTE ; $CC: CPY abs
	byte $11, MODE_ABSOLUTE ; $CD: CMP abs
	byte $14, MODE_ABSOLUTE ; $CE: DEC abs
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $08, MODE_RELATIVE ; $D0: BNE rel
	byte $11, MODE_INDIRECT_Y ; $D1: CMP indy
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $11, MODE_ZERO_PAGE_X ; $D5: CMP zpx
	byte $14, MODE_ZERO_PAGE_X ; $D6: DEC zpx
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $0E, MODE_IMPLIED ; $D8: CLD impl
	byte $11, MODE_ABSOLUTE_Y ; $D9: CMP absy
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $11, MODE_ABSOLUTE_X ; $DD: CMP absx
	byte $14, MODE_ABSOLUTE_X ; $DE: DEC absx
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $12, MODE_IMMEDIATE ; $E0: CPX imm
	byte $2B, MODE_INDIRECT_X ; $E1: SBC indx
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $12, MODE_ZERO_PAGE ; $E4: CPX zp
	byte $2B, MODE_ZERO_PAGE ; $E5: SBC zp
	byte $18, MODE_ZERO_PAGE ; $E6: INC zp
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $19, MODE_IMPLIED ; $E8: INX impl
	byte $2B, MODE_IMMEDIATE ; $E9: SBC imm
	byte $21, MODE_IMPLIED ; $EA: NOP impl
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $12, MODE_ABSOLUTE ; $EC: CPX abs
	byte $2B, MODE_ABSOLUTE ; $ED: SBC abs
	byte $18, MODE_ABSOLUTE ; $EE: INC abs
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $05, MODE_RELATIVE ; $F0: BEQ rel
	byte $2B, MODE_INDIRECT_Y ; $F1: SBC indy
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $2B, MODE_ZERO_PAGE_X ; $F5: SBC zpx
	byte $18, MODE_ZERO_PAGE_X ; $F6: INC zpx
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $2D, MODE_IMPLIED ; $F8: SED impl
	byte $2B, MODE_ABSOLUTE_Y ; $F9: SBC absy
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $38, MODE_UNDOCUMENTED ; undocumented
	byte $2B, MODE_ABSOLUTE_X ; $FD: SBC absx
	byte $18, MODE_ABSOLUTE_X ; $FE: INC absx
	byte $38, MODE_UNDOCUMENTED ; undocumented
