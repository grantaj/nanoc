# Contributing to nanoc

nanoc is deliberately a small, C64-native learning project. Changes should make the machine easier to understand, not merely make the source look more like a conventional compiler.

Before changing the assembler, read [Assembler design](docs/assembler.md). For the native test contract, read [Native testing and CI](docs/testing.md).

## Design standard: spiritually 6502

Prefer code that is:

- direct;
- explicit;
- economical;
- understandable from the machine upward;
- small in persistent state and data structures;
- willing to spend insignificant runtime when that removes substantial code or representation complexity.

A conceptual distinction does not automatically deserve a source module, object, table, or intermediate representation. Separate responsibilities where doing so clarifies the implementation; do not manufacture a representation boundary merely to preserve textbook compiler stages.

Likewise, do not abstract repetition merely to satisfy DRY. Two or three explicit pointer increments, comparisons, nibble conversions, or branch sequences can be better 6502 code than a helper routine whose calling convention is harder to follow than the repeated instructions.

Uniformity is not automatically simplicity. The assembler's ordinary 16-bit forward references use their operand bytes as linked-list nodes while exceptional one-byte/expression/relative cases use fixed fixup records. That asymmetry is desirable because each case gets the smallest representation that fits it.

## Assembly style

Use lowercase instruction mnemonics:

```asm
    lda #$00
    sta value
    jsr printString
```

Use `UPPER_SNAKE_CASE` for constants and enumerated values, for example `CHROUT`, `ASSEMBLE_BAD_ORIGIN`, `MODE_RELATIVE`, or fixed memory addresses.

Use descriptive lower-camel-case names for routines and persistent data, for example `skipWhitespace`, `sourceEnd`, `assemblyPtr`, and `fixupFree`.

Use dot-prefixed local labels for control flow inside a routine:

```asm
.loop:
    lda (ZP_PTR1),y
    beq .done
    ...
    jmp .loop
.done:
    rts
```

Short names such as `p`, `q`, or `tmp` are acceptable only where their meaning is genuinely local and obvious. At module boundaries, prefer names that describe the pointer or value's role.

Do not broadly reformat historical code merely to make it match newer conventions. Apply current conventions to new code and improve older code when it is already being changed for a substantive reason.

## Routine contracts

Public or reusable routines should document their machine-level contract. State, where relevant:

- input registers and memory locations;
- output registers and memory locations;
- zero-page pointers borrowed or preserved;
- registers that are clobbered;
- deliberate memory side effects;
- carry or other flag meanings when they form part of the return convention.

Do not preserve every register automatically. Preserve a register only when the routine's contract requires it. On the 6502, unnecessary save/restore code costs bytes, cycles, and stack space.

A useful header is:

```asm
;;; printString
;;;
;;; ZP_PTR1 points to a NUL-terminated string.
;;; ZP_PTR1 is preserved.
;;; A is clobbered. X and Y are preserved.
```

State ownership matters as much as register ownership. If a routine temporarily borrows a shared pointer or parser cursor, either restore it itself or make the borrowing explicit in the caller/callee contract. Avoid hidden temporal dependencies where one routine only works because another happened not to touch a byte of global state.

## Comments

Use the existing comment hierarchy consistently:

- `;;;` for file-level documentation and routine contracts;
- `;;` for block-level intent or an important implementation note;
- `;` for a short inline comment.

Comments should explain contracts, intent, machine constraints, and non-obvious representation decisions. Avoid merely translating an instruction into English.

Prefer:

```asm
    inc ZP_PTR1
    bne .loop
    inc ZP_PTR1+1        ; handle page crossing
```

rather than commenting every instruction individually.

Comments must describe the architecture that exists now. Do not leave historical names such as “hole”, “pass 1”, or “relaxation” after the implementation that gave those terms meaning has been removed.

## Control flow

Keep routines small enough that their control flow can be followed directly from the source.

Remember that 6502 conditional branches have a limited range. When a destination is too far away, use the normal short-branch-over-`jmp` form rather than contorting source layout:

```asm
    bne .continue
    jmp farTarget
.continue:
```

Machine-driven idioms are welcome when they are documented. For example, manually constructing an indirect subroutine call is reasonable when working around the absence of `JSR (addr)`.

Prefer explicit carry/borrow handling and visible page-crossing logic over assembler expressions that obscure the actual 16-bit operation.

## Pointers and fixed memory

Treat zero-page locations as scarce shared resources. Give persistent zero-page pointers symbolic names and make ownership or borrowing clear at routine boundaries.

Fixed caller-owned memory is not something to hide merely because a higher-level program might use an allocator. The standalone assembler intentionally has explicit staging, symbol, line-buffer, and path-buffer regions. If a fixed geometry makes the lifetime and collision rules obvious, preserve that visibility.

Do not introduce a heap or region abstraction unless a concrete requirement makes it simpler than the explicit addresses it replaces.

When two regions grow toward one another, as the staged image and exceptional fixups do, the collision test should remain directly visible in the machine code.

## Reuse knowledge, not architecture

The assembler reuses disassembler instruction metadata because there should be one authoritative description of 6502 opcodes, mnemonics, modes, and widths.

That does **not** mean the assembler should become a generic backend, nor that the future C compiler should be forced through assembler data structures merely because they already exist.

When moving into the C compiler, copy lessons such as zero-copy source views, bounded state, native tests, and shared machine facts. Do not automatically copy assembler architecture.

## Testing

Behavioral tests remain C64-native.

The code under test and its assertions run as 6502 programs under VICE. The host side may assemble programs, start VICE, mount fixture files, impose a timeout, and inspect the agreed test-result byte. It must not duplicate the behavior under test in Python or another host language.

Each test writes `TEST_RESULT` once when it is finished:

```text
TEST_PASS ($ff) = success
other byte      = named test-specific failure
```

Small tests should stay linear when that is clearest. Larger tests may use the existing routine convention:

```text
carry set   = subtest passed
carry clear = subtest failed, A contains FAIL_* code
```

This is a calling convention, not a test framework. Assertions should remain explicit `lda` / `cmp` / branch code. Do not add assertion macros, generated cases, or a shared assertion runtime merely for uniformity.

Ordinary tests start at `TEST_ENTRY` (`$c000`). Tests that include the complete assembler use `ASSEMBLER_TEST_ENTRY` (`$4000`) so the program remains below the `$d000` C64 I/O window. Keep executable code, output, and scratch/workspace ranges visibly separate rather than adding bank switching just to make a test fit.

The host runner reads the PRG's own load address and starts it there.

The canonical interface is:

```sh
make
make test
```

New tests must join that path rather than creating a parallel test framework. See [Native testing and CI](docs/testing.md) for the exact Make target pattern and failure-debugging flow.

## Development setup and CI

Ubuntu 24.04 is the continuously verified host environment.

```sh
make setup
```

calls `scripts/setup-dev.sh`; GitHub Actions calls the same target. Keep setup knowledge there rather than duplicating dependency commands between documentation and CI YAML.

Do not turn the setup script into a package-manager framework. A narrow path that CI actually verifies is more useful than several nominally supported paths that drift silently.

## Scope of changes

Prefer small changes with one clear purpose. Avoid mixing behavioral fixes with broad cosmetic rewrites.

When reviewing a proposed abstraction, ask:

1. What concrete machine state or repeated decision does it remove?
2. Is the resulting call/data contract simpler than the code it replaces?
3. Does it reduce the number of things a reader must hold in their head?
4. Is it solving a current nanoc requirement or preparing for an imagined future compiler?

If the main benefit is architectural symmetry, terminology, or abstract extensibility, leave the direct code alone.

The project should remain understandable by tracing bytes, pointers, flags, and fixed state through the actual 6502 code.
