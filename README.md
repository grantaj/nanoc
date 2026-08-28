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

The VICE monitor watches `$02` for a store. When the 6502 program writes its result, the thin shell runner reads that byte and reports it to `make`. The host side does not reproduce the assertions or decide whether pointer arithmetic, register behaviour, parsing, or any other C64 behaviour is correct; that logic remains in the 6502 test program.

In other words: **the C64 tests itself; CI only turns the machine on and looks at the result.**

The assembler tests cover whitespace scanning, zero-copy lexeme scanning, statement recognition, EOL/EOF handling, and page-boundary pointer advancement. No Python test framework is used.

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

## Step 2: Write an Assembler
Advantages of starting with an assembler:
- Can work line by line (except for symbols and labels)
- Simple syntax
- Direct translation from mnemonic & addressing mode to opcode & operand

### Assembler front end

The assembler walks the source buffer directly. It does not copy lexeme strings or build a persistent token stream between scanning and parsing.

The source buffer has an explicit `[start, end)` contract. `ZP_PTR1` is the current source pointer and `sourceEnd` is the address one byte past the buffer. Lines inside the buffer are NUL terminated:

- NUL means end of line only.
- EOF means `ZP_PTR1 == sourceEnd`.
- Blank and consecutive blank lines are therefore unambiguous.

`scanLexeme` is a small lexical helper. It leaves the text in place, returns `ZP_PTR0` pointing at the lexeme and X containing its length, and advances `ZP_PTR1` to the delimiter.

`nextStatement` consumes source a line at a time and returns one of:

```
STATEMENT_LABEL
STATEMENT_SYMBOL
STATEMENT_DIRECTIVE
STATEMENT_INSTRUCTION
STATEMENT_EOF
```

The current statement is represented only by transient views into the source:

```
statementName + statementNameLength
statementArgument + statementArgumentLength
```

These views are overwritten by the next call. Mnemonics, directives, operands and punctuation therefore do not require allocated strings or persistent token objects. Later assembler state should retain a source reference only when textual identity genuinely has to survive, principally for symbols.

Supported statement forms are deliberately small:

```
; comment
label:
symbol = value
.directive argument
LDA #$00
RTS
```

Conceptually the flow is:

```
source cursor
     |
     +--> skipWhitespace / scanLexeme
     |
     v
nextStatement
     |
     +--> label
     +--> symbol definition
     +--> directive
     +--> instruction
```

Scanning and parsing remain different responsibilities, but there is no intermediate token data structure merely to preserve that conceptual boundary.
