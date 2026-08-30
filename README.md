# nanoc

nanoc is a C compiler for the 6502/6510, built as a learning project from the machine upward on the Commodore 64.

The goal is not merely to produce working code. The implementation should be unusually easy to understand for someone who knows C and 6502 assembly but has never written a compiler: direct state changes, fixed memory where that is clearer, few data structures, and no textbook compiler machinery unless the machine actually earns it.

## Current status

The project started with a small native disassembler and then built the assembler needed for the compiler.

The assembler is now a genuine native, self-hosting milestone:

```text
vasm-built assembler A
        |
        | assembles the real nanoc assembler source tree
        v
nanoc-built assembler B
        |
        | B itself executes
        | B assembles known source
        v
verified 6502 machine code
```

This is behavioral self-hosting, not a byte-for-byte comparison with vasm.

The assembler reads source one line at a time, keeps lexemes as transient source views, stages final-size machine bytes, patches forward references as labels appear, validates unresolved state at EOF, and only then commits the finished image to its target address.

The C compiler proper is the next stage.

## Quick start

The continuously tested development environment is Ubuntu 24.04. On a completely fresh install, bootstrap Git and Make, then let the repository set up everything else:

```sh
sudo apt-get update
sudo apt-get install -y git make

git clone https://github.com/grantaj/nanoc.git
cd nanoc
make setup
make
make test
```

`make setup` installs the same host tools, VICE data, and pinned vasm build used by GitHub Actions. It may ask for your `sudo` password. The initial Git/Make install is the only setup that must happen before the repository can invoke its own setup target.

Build products are written to `build/`.

For a guided tour, including other-host prerequisites and a source-reading order, start with **[Getting started](docs/getting-started.md)**.

## The project in one picture

```text
                     shared 6502 metadata
                  mnemonic / opcode / mode
                         /           \
                        v             v
                 disassembler     assembler
                                      |
                        source line -> parse views
                                      |
                                      v
                              final-size staged bytes
                                      |
                         forward refs patched in place
                                      |
                                      v
                               validated 6502 image
                                      |
                                      v
                                  C compiler
                                   (next)
```

The assembler and disassembler share one 256-entry opcode table, mnemonic table, addressing-mode IDs, and operand-width table. The disassembler indexes opcode -> mnemonic/mode directly; the assembler deliberately scans the same table in the reverse direction rather than maintaining another index.

## Why the assembler looks unusual

The implementation follows a few strong rules:

- keep source text in place instead of copying tokens;
- retain only information that must survive the current source line;
- decide final instruction width when the statement is parsed;
- let ordinary unresolved 16-bit label references use their own operand bytes as a linked list;
- use small explicit fixup records only for the exceptional cases that cannot use those two bytes;
- prefer linear scans and bounded fixed storage when they substantially simplify the code;
- do not add an AST, generic assembler IR, relocation framework, object format, heap, linker, or layout-relaxation engine merely because conventional assemblers often have them.

The result is intended to be explainable almost literally as the 6502 executes it:

> Read a line. Turn almost all of it into bytes. Remember only what is not yet knowable. When a label appears, patch what was waiting for it. At EOF, make sure nothing is missing and copy the finished image.

See **[Assembler design](docs/assembler.md)** for the complete machine-level story, including the operand-byte forward-reference chain, memory map, symbol representation, include handling, and self-host proof.

For the technical contrast with period-native tools, **[How native C64 assemblers actually assemble](docs/assembler-comparison.md)** compares nanoc with Supermon64, Commodore MADS, and Turbo Assembler/TMP: source representation, passes, forward-reference handling, zero-page decisions, output strategy, and supported language features.

## C64-native tests

The tests are not host-language models of the 6502 implementation. Each test is itself a C64 program running under VICE.

A native test checks its own behavior and writes one result byte to `$02` when complete:

```text
$ff        pass
other      test-specific failure code
```

The host runner only boots the PRG, watches for that store, reads the byte, and reports it to Make/CI.

```text
6502 test + assertions -> VICE -> $02 -> thin shell -> make
```

The suite includes parser, symbols, data, exact branch-boundary, streamed-file/include, and behavioral self-host tests.

See **[Native testing and CI](docs/testing.md)** for the protocol, test-writing convention, VICE runner, CI setup, and debugging workflow.

## Documentation

There are deliberately only a few main documents:

- **[Getting started](docs/getting-started.md)** — copy/paste setup, first build and test, assembler syntax, guided code tour, and reading order.
- **[Assembler design](docs/assembler.md)** — structure, representation choices, fixed C64 memory contract, and the reasons behind them.
- **[Native assembler comparison](docs/assembler-comparison.md)** — how Supermon64, Commodore MADS, Turbo/TMP, and nanoc represent source, resolve addresses, emit bytes, and trade features against memory.
- **[Native testing and CI](docs/testing.md)** — how the C64 owns behavioral assertions and how CI executes them.
- **[Contributing](CONTRIBUTING.md)** — coding style, routine contracts, state ownership, testing rules, and the project's “spiritually 6502” design standard.

The documentation is intended to point into the real source rather than create a parallel textbook architecture.

## Build interface

The root Makefile is the supported interface:

```sh
make setup    # prepare the Ubuntu 24.04 development environment
make          # build disassembler, assembler, tests, and examples
make test     # execute the full C64-native test suite under VICE
make clean
```

GitHub Actions uses the same `make setup`, `make`, and `make test` path.

## Repository map

```text
ass/        native assembler, source reader, symbols, staging, and tests
dis/        original disassembler and shared 6502 instruction metadata
docs/       onboarding, assembler design/comparison, and native test documentation
examples/   small C/assembly comparison examples
tests/      VICE runner and streamed-source fixtures
```

If you are reading the code to learn how the assembler works, do not start by treating those directories as compiler stages. Follow the guided order in [Getting started](docs/getting-started.md); it tracks actual source bytes and machine state instead.
