TARGET_C = main
SRC_C = main.c

TARGET_S = main

TARGET_ASM = demo
SRC_ASM = demo.asm

.PHONY: all clean run run_asm

all: $(TARGET_C).prg $(TARGET_ASM).prg

$(TARGET_S).s: $(SRC_C)
	cc65 -Oirs -t c64 $<

$(TARGET_C).prg: $(SRC_C)
	cl65 -Oirs -t c64 -o $@ $<


$(TARGET_ASM).prg: $(SRC_ASM)
	vasm6502_oldstyle -Fbin -cbm-prg -o $@ $<


run: $(TARGET_C).prg
	x64 -autostart $<

run_asm: $(TARGET_ASM).prg
	x64 -autostart $< 

clean:
	rm -f *.o *.prg *.s

