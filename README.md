# nanoc
Learning to write a compiler by writing one for the c64

## Vice
```
	apt install vice

	apt install subversion
	git clone https://github.com/lharsfalvi/vice-roms-deb.git
	cd vice-roms
	./makedeb.sh
	dpkg -i ivce-roms*.deb

	x64
```
## Toolchain
### cc65
`apt install cc65`

### vasm
Not really required, since `cc65` has an assembler (`ca54`) but I wanted to compare...
```
	git clone https://github.com/StarWolf3000/vasm-mirror.git
	cd vasm-mirror
	make CPU=650 SYNTAX=oldstyle
	cp vasm6502_oldstyle /usr/local/bin/.
```	

## Demo
Demo in `examples/border`
Compile from C:
```
	make main.prg
	make run
```
There is also handwritten `demo.asm` . Assembles using `vasm6502_oldstyle`
```
	make demo.prg
	make run_asm
```
Then inside c64: `sys 49152`

Produce `main.s` assembly from C for comparison with `demo.asm`:
```
	make main.s
```




