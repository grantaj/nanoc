# Phase 1 evidence from `ass.c`

`ass.c` was deliberately written before the Nano C Phase 1 language was fixed. Its purpose was to make language pressure visible.

The frozen language is now defined in `docs/phase1.md`. This file records how the experiment led there.

## What the assembler actually needed

The candidate assembler remained clear while using only:

- byte and 16-bit scalar values;
- `char *` pointer-plus-length source views;
- fixed one-dimensional arrays;
- global variables and static data;
- ordinary parameters and function locals;
- functions and nested calls between different functions;
- `if` / `else`, `while`, `break` and `return`;
- simple assignment;
- `+`, `-`, `*`, `&`, `|`, `<<`, `>>`;
- equality and relational comparisons;
- array indexing and byte-pointer addition;
- integer, character and string literals;
- block comments;
- a tiny three-function I/O boundary.

The assembler did **not** become awkward without `struct`, `for`, `switch`, `++`, logical operators, local arrays, recursion, preprocessing, allocation or separate compilation. Those features therefore did not earn a place merely by being familiar C.

## Features that clearly earned their place

### Arrays and indexing

Source buffers, staging bytes, opcode metadata, symbol-table columns and bounded fixup records are naturally arrays. Removing arrays would turn the source back into assembly.

### `char *` and pointer addition

The parser naturally works on `pointer + length` views into a source line. This keeps the zero-copy design of the native assembler and avoids token objects or copied strings.

Phase 1 only needs byte pointers. The experiment did not justify general pointer types, address-of or unary dereference.

### Static/global initialisation

Opcode and addressing-mode tables make static initialisation disproportionately valuable. Procedurally filling these tables at startup merely to simplify the compiler would make both source and generated program worse.

### `while`

The assembler is mostly scans. `while` expresses them directly; `for` does not buy enough to justify another statement form in `nanoc0`.

### `break`

Without `break`, scanners need artificial flags or duplicated loop conditions. It is a small feature with a clear readability return.

### Multiplication

The assembler uses multiplication for decimal parsing and fixed-width table indexing. Replacing those operations with source-level shift/add sequences would make the C more machine-like without meaningfully simplifying the language.

### Local initialisation

The candidate assembler itself does not require local initializers, but the compiler-architecture pass showed that forbidding them would be false minimalism.

`nanoc0` must already be able to:

- allocate a fixed slot for a local;
- compile an arbitrary expression into `A/X`;
- store `A/X` into that slot.

Therefore:

```c
int a = expression;
```

costs essentially no new machine machinery beyond:

```c
int a;
a = expression;
```

while removing repetitive source boilerplate. Initializers remain constrained by the one-pass design: all locals are declared before ordinary statements, initializers execute in declaration order, and an initializer may use only parameters, globals and previously declared locals.

This is exactly the kind of convenience Nano C should provide over assembly: less clerical source without hiding the machine.

## The 16-bit integer result

The host validation compiler temporarily hid an important target fact: its `int` is wider than a 6502 Nano C `int`.

The assembler needs both:

- natural negative results such as `-1` and `-2` from searches and I/O;
- the complete 16-bit range for addresses, parsed values, symbol payloads and fixup addends.

Making the only integer type signed would make values above `$7fff` awkward. Making it unsigned would turn ordinary negative status returns into magic values.

The experiment therefore justified one deliberate addition to the first candidate spelling:

- `int`: signed 16-bit;
- `unsigned`: unsigned 16-bit;
- `char`: unsigned 8-bit.

This is a better minimal language than forcing two distinct jobs through one type merely to save one keyword and one signedness bit in the compiler.

That target-width cleanup is now complete in `ass.c`: origins, parsed machine values, symbol payloads, fixup addends and the helper parameters/locals that carry them are explicitly `unsigned`; search/status values remain signed `int`.

The important point is that no wider host integer is now required to express the assembler's logic. The modern host compiler remains only the independent behaviour check.

## Hexadecimal literals

The candidate tables happened to be expressible without C hexadecimal syntax, but the compiler and C64 runtime immediately need readable machine addresses and masks.

`0xc000` is materially better systems C than `49152`. Hexadecimal literals therefore earn Phase 1 despite not being forced by the assembler source alone.

## Storage pressure

Compiling the candidate on the host and assembling the real production assembler closure measured:

```text
symbols:     643
name bytes:  6935
fixups:      575
image bytes: 6905
```

The candidate fixed splits were then chosen so their **target representation**, assuming 16-bit Nano C integer values, fits the same native assembler budgets:

```text
symbols/names: 12 KiB
staging/fixups: 16 KiB
```

The host C object layout is irrelevant; these numbers are target-design evidence only.

The 16 KiB staging region is also a real constraint on the compiler output. `nanoc0` should measure generated assembly/program size from its earliest integration tests. It may emit deliberately conservative code such as branch-over-`JMP`, but it should not wait until the final `ass.c` compile to discover that baseline code generation has exceeded the assembler's staging budget.

## Control-flow and declaration pressure

`ass.c` also shows that the first compiler does not need several expensive generalities:

- globals can appear before all functions;
- C-defined functions can be ordered definition-before-use;
- locals can be declared at function entry;
- no block-local declarations are needed;
- no recursive call is needed.

Those restrictions are now part of Phase 1 because they substantially simplify a direct assembly-written compiler without degrading this real program.

Phase 1 still supports nested calls to different functions. The frozen machine model therefore uses fixed per-function parameter/local/temp storage and caller-owned call staging rather than software stack frames.

Generated control flow follows the same philosophy. `nanoc0` will not retain enough layout state to ask whether a conditional target fits a 6502 relative branch. It always emits a nearby conditional branch over an absolute `JMP`, deliberately spending a few bytes to remove branch-distance bookkeeping and relaxation from the bootstrap compiler.

The C language itself remains a character stream. `nanoc0` may use a small refill buffer, but physical source lines are only whitespace boundaries: declarations, expressions and block comments may cross them. This keeps the language ordinary C-like syntax without requiring the compiler to retain the whole source file.

## Features that remain deferred

### `struct`

Parallel arrays remain clear for the assembler and make bounded storage explicit. Compiler symbols may create stronger pressure later, so `struct` is an obvious Phase 2 question rather than a rejected idea.

### `for`

`while` remains clear throughout the assembler.

### `switch`

Dispatch remains short enough as direct tests. No source-level jump-table construct is justified yet.

### `++` / `--`

They would shorten scanner increments, but `x = x + 1` is still clear. This is convenience, not demonstrated Phase 1 pressure.

### Logical operators

The candidate remains readable using nested tests, so the assembly bootstrap does not yet need short-circuit `&&` / `||` machinery.

### Recursion

The assembler does not use it. Phase 1 is deliberately non-recursive, and the machine model takes advantage of that with fixed static function storage rather than a general software stack.

## Architecture retained by the C experiment

The C rewrite kept the useful machine-oriented shape of `ass`:

- one source line resident at a time;
- parsing in place;
- symbol names copied only when they must survive the line buffer;
- linear bounded symbol lookup;
- final-width bytes staged immediately;
- ordinary unresolved 16-bit label references chained through their own output bytes;
- exceptional byte/expression/relative references kept in bounded fixup state;
- labels patch waiting references when defined;
- fixed include depth;
- no heap, AST, generic IR, object format or linker.

That is the design Phase 1 must be able to express. The language is being fitted to the program, not the program redesigned around a modern compiler architecture.
