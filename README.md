# nanoc
Learning to write a compiler by writing one for the c64

## Build

The repository has a single root-level build interface:

```
make        # build the disassembler, assembler work-in-progress, and examples
make test   # assemble and execute the C64-native tests under VICE
make clean
```

Build products are written to `build/`.

GitHub Actions runs the same `make` and `make test` commands on pull requests and on pushes to `main`.

## C64-native testing

The testing philosophy for nanoc is deliberately C64-native. The code under test and the assertions about its behaviour run as ordinary 6502 programs, not in a host-language test framework.

Tests include `test.inc`, which reserves `$02` as `TEST_RESULT`. A test writes this byte exactly once, when it is complete:

- `$ff` (`TEST_PASS`) means success.
- Any other value is a test-specific failure code identifying the assertion that failed.

The VICE monitor watches `$02` for a store. When the 6502 program writes its result, the thin shell runner reads that byte and reports it to `make`. The host side does not reproduce the assertions or decide whether pointer arithmetic, register preservation, tokenisation, or any other C64 behaviour is correct; that logic remains in the 6502 test program.

In other words: **the C64 tests itself; CI only turns the machine on and looks at the result.**

`ass/test_skipws.asm` is the first executable test. It checks whitespace skipping, non-whitespace preservation, page-boundary pointer advancement, and register preservation, with distinct failure codes. Future tests follow the same pattern. No Python test framework is used.

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
Not really required, since `cc65` has an assembler (`ca65`) but I wanted to compare...
```
	git clone https://github.com/StarWolf3000/vasm-mirror.git
	cd vasm-mirror
	make CPU=6502 SYNTAX=oldstyle
	cp vasm6502_oldstyle /usr/local/bin/.
```	

CI pins the vasm mirror to a known commit so that builds do not silently change as upstream changes.

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

## Step 2: Write a Assembler
Advantages of starting with an assembler:
- Can work line by line (except for symbols and labels)
- Simple syntax
- Direct translation from mnemonic & addressing mode to opcode &
  operand
  
### Tokeniser
Operate line by line
Assume the line of text is in memory at a given location

**Token structure**
type {label | symbol | directive | mnemomic | operand}
value string

**Supported token syntax:**
```
	; comment
	label:
	symbol = value
	.directive
	LDA
	#$00
```

Tokenizer will operate on the string "in place"

1. skipWhitespace
2. scanLexeme
3. classifyLexeme
4. Comment or EOL? Yes -> Next Line
5 Goto 1.



skipWhitespace
	advance position to first non-whitespace character

scanLexeme
	set lexeme to string from current position to the next whitespace
	or end of line
	
classifyLexeme
	Starts with Semicolon? Comment, Next Line 
	Starts with Dot? type = directive, value = lexeme(1:end), return
	Ends with Colon? type=label, value = lexeme(0:end-1), return
	Followed by = ? type = symbol, value = lexeme else type=mnemnonic,
	value = lexeme, scan operand and return 
	scan operand: type=operand, value = lexeme, return
	
