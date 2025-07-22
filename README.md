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

### 64tass
```
	apt-get install 64tass
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

## Step 1: Write a Disassembler

Complete! See `dis/dis.asm`

Build with 
```
	cd dis
	vasm6502_oldstyle -Fbin -cbm-prg -o dis.prg dis.asm
```
### Opcode Table
- There is a many to one mapping between opcodes and mnemonics
- This is due to multiple addressing modes
- Opcode table has 0xff entries
- Each entry consists of

  byte mnemonic_index
  byte mode_index

  By having 0xff entries, we can do a direct lookup based on the opcode without having to search. Table size will be 512 bytes (0x200)

  `mnemonic_index` is an index into the _mnemonic table_
  `mode_index` is an index into _address mode table_
  
  invalid opcodes will map to a sentinel entry

### Mnemonic Table
- This is an array of strings, indexed by the `mnemonic_index`
- Each string is 3 bytes
- Mnemonic outputter writes exactly three bytes from this table
- There are 56 mnemonics - table is 168 bytes
```
ADC AND ASL BCC BCS BEQ BIT BMI BNE BPL BRK BVC BVS
CLC CLD CLI CLV CMP CPX CPY DEC DEX DEY EOR INC INX INY
JMP JSR LDA LDX LDY LSR NOP ORA PHA PHP PLA PLP ROL
ROR RTI RTS SBC SEC SED SEI STA STX STY TAX TAY TSX
TXA TXS TYA
```

### Address Mode Table
- Each entry consists of
  ```
  word formatter
  ```
- `formatter` is the address of the output function for this mode
- disassembler pushes the next width bytes onto stack and `jsr formatter` (actually it does jmp (vector) where vector points to formatter, with return address manually loaded onto the stack)
- Formatter routines output the formatted operand and return the width of the operand in the accumulator (to facilitate incrementing the pointer)

### Outline

1. Set `pointer` to start of disassembly region
2. Read `opcode`
3. Retrieve `mnemonic_index` and `mode_index` (indexing into opcode table)
4. Output mnemonic (from mnemonic index)
5. Call formatter
6. Increment pointer
7. Check if pointer is at end of region (stop)
8. Jump to read `opcode`
