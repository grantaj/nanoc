# Getting started

This guide is for a reader who is comfortable with 6502 assembly but has not necessarily written an assembler or compiler before. The quickest way to understand nanoc is to get the native tests running, then follow one source statement through the real code.

## From a clean Ubuntu machine to a passing self-host test

The development setup used by GitHub Actions is Ubuntu 24.04. A completely fresh machine needs only Git and Make before the repository can take over its own setup:

```sh
sudo apt-get update
sudo apt-get install -y git make

git clone https://github.com/grantaj/nanoc.git
cd nanoc
make setup
make
make test
```

The first two commands are the unavoidable bootstrap: Git is needed to obtain the repository and Make is needed to invoke its setup target. From `make setup` onward, the development environment is repository-owned and is deliberately the same path CI runs. `make setup` may ask for your `sudo` password.

The setup script installs:

- the ordinary host build tools;
- `cc65`, used by the comparison C example;
- VICE and the VICE 3.7.1 ROM data used by CI;
- `vasm6502_oldstyle`, built from the exact pinned vasm commit used by CI.

The setup is intentionally not a cross-platform installer. Ubuntu 24.04 is the path the repository continuously verifies. On another host, install equivalent tools yourself and make sure these commands are on `PATH`:

```text
make
cl65
vasm6502_oldstyle
x64sc
timeout
od
```

The exact VICE data version and vasm commit are recorded in `scripts/setup-dev.sh`; that script is the authoritative setup recipe.

## Build the repository

```sh
make
```

Build products go into `build/`. The important ones are:

```text
build/dis.prg          the original C64 disassembler
build/ass.prg          the standalone native assembler at $4000
build/parse.prg        a small parser/instruction demo
build/test_*.prg       the C64-native test programs
build/border-*.prg     small comparison examples
```

The root `Makefile` is the supported build interface. You should not need to assemble individual source files by hand just to work on the repository.

## Run the native test suite

```sh
make test
```

A successful run prints a sequence of `PASS` lines, ending with the self-host test. The unusual part is where the assertions run: **inside the emulated C64**.

Each test is a 6502 program. It checks its own results and writes one byte to `$02` when finished. VICE stops on that write and the host shell reports the byte. The shell does not reproduce the parser, assembler, pointer arithmetic, or expected machine behavior in Python or another host language.

See [Native testing and CI](testing.md) for the full convention and for how to add a test.

## The assembler language at a glance

nanoc intentionally supports only the source forms required by its own assembler and tests. Pseudo-operations are bare lower-case names, not a separate directive language:

```asm
; comment

* = $2000
SCREEN = $0400

start:
    lda #$00
    sta SCREEN
.loop:
    inc SCREEN
    bne .loop
    jsr later
    rts

byte 1, 2, 'A'
word start
string "hello"
include "other.asm"

later:
    rts
```

The important rules are:

- `* = value` sets the one origin and must appear before labels, code, or data;
- `name = value` defines a constant that must resolve when encountered;
- `.local` names belong to the most recent non-local label;
- `byte` emits one byte per value;
- `word` emits little-endian 16-bit values;
- `string "text"` emits the text followed by a NUL byte;
- `include "file.asm"` is supported by the file-streaming assembler path;
- the value grammar is deliberately only `[< | >] atom [ + atom | - atom ]`.

For instruction syntax, nanoc uses ordinary 6502 forms such as `lda #$20`, `lda $20,x`, `lda ($20),y`, `jsr label`, and `bne label`.

## Follow one line through the assembler

Consider this source:

```asm
    jsr later
```

where `later` has not been defined yet.

### 1. `source.asm` supplies one line

The production entry point is `assembleFile` in `ass/assembler.asm`. It asks `ass/source.asm` for one line at a time. `readSourceLine` places that line in a caller-owned 256-byte buffer and `prepareSourceLine` presents it using the parser's normal `[ZP_PTR1, sourceEnd)` contract.

The rest of the source file is not resident in RAM.

### 2. `parser.asm` returns views, not tokens

`nextStatement` sees `jsr later` and returns `STATEMENT_INSTRUCTION` plus two transient views into that line buffer:

```text
statementName      -> "jsr"
statementArgument  -> "later"
```

No strings are copied and no token list is built. The views only need to live until this statement has been understood.

### 3. `instruction.asm` identifies the machine instruction

`parseInstruction` looks up `JSR` in the shared mnemonic table and checks the shared opcode table for a legal addressing mode. `JSR` has a fixed absolute operand, so its final width is already known even though the target address is not.

The reverse lookup is intentionally a linear scan of the existing 256-entry opcode table. A second inverse table would save insignificant time while adding another structure to understand and maintain.

### 4. `value.asm` records only what is still unknown

`parseValue` looks up `later`. Because the label does not yet exist, `symbols.asm` interns one symbol entry and owns a copy of the name. The line buffer is now free to be reused.

The persistent unresolved value is not source text or an expression tree. It is simply the symbol-table entry plus any small addend and optional `<`/`>` selector required by the tiny value grammar.

### 5. the operand bytes become the forward-reference list

`assembler.asm:stagePlainWordReference` stages the two final operand bytes for the JSR. `symbols.asm:linkWordReference` temporarily uses those two bytes to point to the previous unresolved reference to `later`.

That works because the bytes have no useful final value yet. The symbol entry stores the head of this chain.

### 6. the label patches the waiting bytes immediately

When this appears later:

```asm
later:
```

`defineLabel` now knows the final address from `assemblyPtr`. It changes the symbol entry from “undefined label + reference-chain head” to “defined label + final value”, walks the old chain, and replaces every temporary link with the little-endian address.

Nothing needs to revisit the original `jsr later` source line.

### 7. EOF is validation and commit, not another assembly pass

At EOF `finishAssembly` checks that all labels and exceptional fixups have been resolved. Only then does `copyRepresentation` copy the finished staged image to the target address.

That is the central assembler story:

```text
read a line
understand it
turn it into final-size bytes
remember only what cannot yet be known
reuse the line buffer

when a label appears, patch its waiting references
at EOF, validate and commit
```

For the complete design, including the exceptional fixup records and memory geometry, read [Assembler design](assembler.md).

## A useful source-reading order

If you want to learn the implementation rather than just use it, this order follows the machine-level story:

1. **`ass/parser.asm`** — look for how `nextStatement` classifies a line while leaving all text in place.
2. **`ass/instruction.asm`** — follow how punctuation determines a 6502 addressing form and how `findOpcode` reuses the disassembler table.
3. **`dis/mnemonic_table.asm`, `dis/opcode_table.asm`, `dis/mode_ids.inc`, `dis/mode_widths.asm`** — see the shared description of the instruction set used in both directions.
4. **`ass/value.asm`** — look at how small the value grammar remains and what survives when one label is unresolved.
5. **`ass/symbols.asm`** — focus on the two meanings of the symbol payload and on `linkWordReference` / `resolveWordReferencesForSymbol`.
6. **`ass/representation.asm`** — see staged bytes grow upward while the uncommon eight-byte fixups grow downward.
7. **`ass/assembler.asm`** — now read the orchestration; most of it should map directly onto the pieces you have already seen.
8. **`ass/source.asm`** — follow the bounded include stack and the per-depth EOF state used by the production file path.
9. **`ass/ass.asm`** — see the fixed standalone C64 memory map and the six-byte caller command block.
10. **`ass/test_selfhost.asm`** — finish with the behavioral proof that an assembler built by nanoc is itself executable and can assemble code.

This order is intentional: start with concrete byte and pointer behavior, then read the orchestration after its parts already have meaning.

## Where next

- [Assembler design](assembler.md) explains why the assembler has this exact shape.
- [Native assembler comparison](assembler-comparison.md) contrasts nanoc's representation and forward-reference strategy with Supermon64, Commodore MADS, and Turbo/TMP.
- [Native testing and CI](testing.md) explains the `$02` test protocol, VICE runner, streaming tests, and self-host proof.
- [CONTRIBUTING.md](../CONTRIBUTING.md) records the coding and design rules for extending the project.
