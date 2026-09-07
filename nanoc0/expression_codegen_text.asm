;;; ---------------------------------------------------------------------------
;;; Fixed target-source fragments
;;; ---------------------------------------------------------------------------
;;;
;;; The End labels are retained temporarily because a few focused test/formatter
;;; callers still use the old explicit-length seam. Each End points before the
;;; NUL, so those callers see exactly the same bytes while production uses
;;; emit_string.

exprLdaImm:		byte $09,'l','d','a',' ','#','$'
exprLdaImmEnd:		byte 0
exprLdxImm:		byte $09,'l','d','x',' ','#','$'
exprLdxImmEnd:		byte 0
exprLdaLowImm:		byte $09,'l','d','a',' ','#','<'
exprLdaLowImmEnd:	byte 0
exprLdxHighImm:		byte $09,'l','d','x',' ','#','>'
exprLdxHighImmEnd:	byte 0
exprLdaSpace:		byte $09,'l','d','a',' '
exprLdaSpaceEnd:		byte 0
exprLdxSpace:		byte $09,'l','d','x',' '
exprLdxSpaceEnd:		byte 0
exprStaSpace:		byte $09,'s','t','a',' '
exprStaSpaceEnd:		byte 0
exprStxSpace:		byte $09,'s','t','x',' '
exprStxSpaceEnd:		byte 0
exprLdxZero:		byte $09,'l','d','x',' ','#','$','0','0',$0a
exprLdxZeroEnd:		byte 0
exprPlusOne:		byte '+','1'
exprPlusOneEnd:		byte 0
exprBytePrefix:		byte $09,'b','y','t','e',' '
exprBytePrefixEnd:	byte 0


exprStorePtr:
	byte $09,'s','t','a',' ','N','C','_','P','T','R',$0a
	byte $09,'s','t','x',' ','N','C','_','P','T','R','+','1',$0a,0
exprClc:		byte $09,'c','l','c',$0a,0
exprSec:		byte $09,'s','e','c',$0a,0
exprAdcSpace:		byte $09,'a','d','c',' ',0
exprSbcSpace:		byte $09,'s','b','c',' ',0
exprAndSpace:		byte $09,'a','n','d',' ',0
exprOraSpace:		byte $09,'o','r','a',' ',0
exprAdcTmp:		byte $09,'a','d','c',' ','N','C','_','T','M','P',$0a,0
exprSbcTmp:		byte $09,'s','b','c',' ','N','C','_','T','M','P',$0a,0
exprAndTmp:		byte $09,'a','n','d',' ','N','C','_','T','M','P',$0a,0
exprOraTmp:		byte $09,'o','r','a',' ','N','C','_','T','M','P',$0a,0
exprTayTxa:
	byte $09,'t','a','y',$0a
	byte $09,'t','x','a',$0a,0
exprTaxTya:
	byte $09,'t','a','x',$0a
exprTya:	byte $09,'t','y','a',$0a,0
exprWordAddTmp:
	byte $09,'c','l','c',$0a
	byte $09,'a','d','c',' ','N','C','_','T','M','P',$0a
	byte $09,'t','a','y',$0a
	byte $09,'t','x','a',$0a
	byte $09,'a','d','c',' ','N','C','_','T','M','P','+','1',$0a
	byte $09,'t','a','x',$0a
	byte $09,'t','y','a',$0a,0
exprWordSubTmp:
	byte $09,'s','e','c',$0a
	byte $09,'s','b','c',' ','N','C','_','T','M','P',$0a
	byte $09,'t','a','y',$0a
	byte $09,'t','x','a',$0a
	byte $09,'s','b','c',' ','N','C','_','T','M','P','+','1',$0a
	byte $09,'t','a','x',$0a
	byte $09,'t','y','a',$0a,0
exprWordAndTmp:
	byte $09,'a','n','d',' ','N','C','_','T','M','P',$0a
	byte $09,'t','a','y',$0a
	byte $09,'t','x','a',$0a
	byte $09,'a','n','d',' ','N','C','_','T','M','P','+','1',$0a
	byte $09,'t','a','x',$0a
	byte $09,'t','y','a',$0a,0
exprWordOrTmp:
	byte $09,'o','r','a',' ','N','C','_','T','M','P',$0a
	byte $09,'t','a','y',$0a
	byte $09,'t','x','a',$0a
	byte $09,'o','r','a',' ','N','C','_','T','M','P','+','1',$0a
	byte $09,'t','a','x',$0a
	byte $09,'t','y','a',$0a,0
exprCallMul16:		byte $09,'j','s','r',' ','_','_','n','c','_','m','u','l','1','6',$0a,0
exprShift8:
	byte $09,'t','x','a',$0a
	byte $09,'l','d','x',' ','#','$','0','0',$0a,0

exprNegate:
	byte $09,'s','t','a',' ','N','C','_','T','M','P',$0a
	byte $09,'s','t','x',' ','N','C','_','T','M','P','+','1',$0a
	byte $09,'l','d','a',' ','#','$','0','0',$0a
	byte $09,'s','e','c',$0a
	byte $09,'s','b','c',' ','N','C','_','T','M','P',$0a
	byte $09,'t','a','y',$0a
	byte $09,'l','d','a',' ','#','$','0','0',$0a
	byte $09,'s','b','c',' ','N','C','_','T','M','P','+','1',$0a
	byte $09,'t','a','x',$0a
	byte $09,'t','y','a',$0a
exprNegateEnd:		byte 0

exprSaveRight:
	byte $09,'s','t','a',' ','N','C','_','T','M','P',$0a
	byte $09,'s','t','x',' ','N','C','_','T','M','P','+','1',$0a
exprSaveRightEnd:	byte 0
exprTay:
exprMulSaveLow:		byte $09,'t','a','y',$0a
exprMulSaveLowEnd:	byte 0
exprStaTmp:		byte $09,'s','t','a',' ','N','C','_','T','M','P',$0a
	byte 0
exprCpyZero:		byte $09,'c','p','y',' ','#','$','0','0',$0a
exprCpyZeroEnd:		byte 0
exprShiftLeftBody:
	byte $09,'a','s','l',' ','N','C','_','T','M','P',$0a
	byte $09,'r','o','l',' ','N','C','_','T','M','P','+','1',$0a
	byte $09,'d','e','y',$0a
exprShiftLeftBodyEnd:	byte 0
exprShiftRightBody:
	byte $09,'l','s','r',' ','N','C','_','T','M','P','+','1',$0a
	byte $09,'r','o','r',' ','N','C','_','T','M','P',$0a
	byte $09,'d','e','y',$0a
exprShiftRightBodyEnd:	byte 0
exprLoadTmpResult:
	byte $09,'l','d','a',' ','N','C','_','T','M','P',$0a
	byte $09,'l','d','x',' ','N','C','_','T','M','P','+','1',$0a
exprLoadTmpResultEnd:	byte 0

exprCmpSpace:		byte $09,'c','m','p',' ',0
exprCmpTmp:		byte $09,'c','m','p',' ','N','C','_','T','M','P',$0a,0
exprBne:		byte $09,'b','n','e',' '
exprBneEnd:		byte 0
exprBeq:		byte $09,'b','e','q',' '
exprBeqEnd:		byte 0
exprBcc:		byte $09,'b','c','c',' '
exprBccEnd:		byte 0
exprBcs:		byte $09,'b','c','s',' '
exprBcsEnd:		byte 0
exprJmp:		byte $09,'j','m','p',' '
exprJmpEnd:		byte 0
exprCallEq16:		byte $09
			string "jsr __nc_eq16"
exprCallNe16:		byte $09
			string "jsr __nc_ne16"
exprCallSlt16:		byte $09
			string "jsr __nc_slt16"
exprCallSle16:		byte $09
			string "jsr __nc_sle16"
exprCallSgt16:		byte $09
			string "jsr __nc_sgt16"
exprCallSge16:		byte $09
			string "jsr __nc_sge16"
exprCallUlt16:		byte $09
			string "jsr __nc_ult16"
exprCallUle16:		byte $09
			string "jsr __nc_ule16"
exprCallUgt16:		byte $09
			string "jsr __nc_ugt16"
exprCallUge16:		byte $09
			string "jsr __nc_uge16"
exprCallIndex16:
	byte $09,'j','s','r',' ','_','_','n','c','_','i','n','d','e','x','1','6',$0a,0

exprScaleIndex:
	byte $09,'a','s','l',' ','N','C','_','T','M','P',$0a
	byte $09,'r','o','l',' ','N','C','_','T','M','P','+','1',$0a
exprScaleIndexEnd:	byte 0
exprCharIndirectY:
	byte $09,'l','d','a',' ','(','N','C','_','P','T','R',')',',','y',$0a,0
exprCharIndirectOnly:
	byte $09,'l','d','y',' ','#','$','0','0',$0a
	byte $09,'l','d','a',' ','(','N','C','_','P','T','R',')',',','y',$0a,0
exprCharIndirectEnd:	byte 0
exprIndexYSuffix:	byte ',', 'y', $0a, 0
exprWordIndirect:
	byte $09,'l','d','y',' ','#','$','0','0',$0a
	byte $09,'l','d','a',' ','(','N','C','_','P','T','R',')',',','y',$0a
	byte $09,'s','t','a',' ','N','C','_','T','M','P',$0a
	byte $09,'i','n','y',$0a
	byte $09,'l','d','a',' ','(','N','C','_','P','T','R',')',',','y',$0a
	byte $09,'t','a','x',$0a
	byte $09,'l','d','a',' ','N','C','_','T','M','P',$0a
exprWordIndirectEnd:	byte 0

