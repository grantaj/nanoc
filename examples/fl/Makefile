TARGET = border
SRC = main.c

.PHONY: all run clean

all: $(TARGET).prg

$(TARGET).prg: $(SRC)
	cl65 -t c64 $(SRC) -o $@

run: $(TARGET).prg
	x64 -autostart $(TARGET).prg

clean:
	rm -f *.o *.prg

