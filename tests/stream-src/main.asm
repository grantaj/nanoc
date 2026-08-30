CONST = $2a
* = $2200
include "CHILD.ASM"
start:
LDA #CONST
JSR child
include "TAIL.ASM"