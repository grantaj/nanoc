;;; Add the 16-bit index in NC_TMP to the base in A/X.
;;; The effective address is returned in NC_PTR. Y is unchanged.
__nc_index16:
	clc
	adc NC_TMP
	sta NC_PTR
	txa
	adc NC_TMP+1
	sta NC_PTR+1
	rts
