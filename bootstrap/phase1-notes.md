# Candidate Phase 1 language notes

`ass.c` is deliberately a language-discovery program.

The aim is not to prove that the assembler can be forced into an arbitrarily tiny C-like notation. The aim is to find the smallest subset that still leaves the assembler looking like normal, readable C.

The host compiler is only a behaviour check. Its implementation model and data widths do not define Nano C.

## Constructs used by `ass.c`

The candidate currently uses:

- `char` and `int`;
- `char *`;
- one-dimensional arrays of `char` and `int`;
- global variables;
- scalar global initialisers;
- numeric array initialisers;
- string initialisers for character tables;
- function definitions with typed parameters and integer return values;
- function calls, including nested calls;
- ordinary local variables;
- `if` / `else`;
- `while`;
- `break`;
- `return`;
- assignment;
- `+`, `-`, `*`;
- `&`, `|`, `<<`, `>>`;
- `==`, `!=`, `<`, `<=`, `>`, `>=`;
- unary minus for small status/sentinel values;
- array indexing;
- pointer addition;
- integer, character and string literals;
- `/* ... */` comments.

The core intentionally does not use:

- `struct`, `union`, `enum` or `typedef`;
- `const` or `static`;
- `for`, `switch`, `do`, `goto`, `continue`;
- `++` or `--`;
- `?:`;
- `&&`, `||` or `!`;
- casts;
- `sizeof`;
- function pointers;
- recursion;
- local arrays;
- dynamic allocation;
- standard-library types or calls;
- preprocessing;
- headers;
- multiple source modules as a language feature.

The host adapter uses ordinary host C facilities, but none of those facilities count as evidence for Phase 1.

## What has clearly earned its place

### Arrays and indexing

The assembler naturally consists of source buffers, staging bytes, opcode metadata, symbol-table columns and bounded fixup records. Expressing those without arrays would turn the program back into assembly.

### Pointers and pointer addition

Source views are naturally `pointer + length`. Keeping this model preserves the zero-copy parser and avoids invented token objects.

### Static/global initialisation

The opcode and addressing-mode tables make this disproportionately valuable. Requiring hundreds of procedural stores at startup merely to avoid initialisers would make both the source and generated program worse.

### `while`

The assembler is mostly scans. `while` is sufficient; the current program does not demonstrate a need for `for`.

### `break`

Without `break`, scanners need artificial flags or duplicated tests simply to leave a loop when punctuation is found. This is a small language feature with a clear readability return.

### Multiplication

Only small, obvious cases currently use it: decimal parsing and fixed-width table indexing. Replacing these with shift/add sequences would deliberately make the C source more machine-like. A tiny runtime multiply is likely a better trade, but Phase 1 should make that decision explicitly.

## Features that have not earned their place yet

### `struct`

Parallel arrays are still clear for the symbol table and fixups, and they make the bounded storage cost very explicit. The current assembler therefore does not provide evidence that structure layout/member access belongs in the assembly-written compiler.

This should be revisited while writing the compiler itself: compiler symbols may create stronger pressure than assembler symbols do.

### `for`

The loops remain clear as `while` loops. Omitting `for` has not caused awkward control flow.

### `switch`

Statement and addressing-mode dispatch remain short enough as direct tests. There is no strong pressure for a jump-table/source-level `switch` construct.

### `++` / `--`

They would shorten many scanner increments, but `x = x + 1` is still readable and does not distort the program. They remain a plausible small convenience, not a demonstrated Phase 1 requirement.

### Logical operators

The source is readable with direct nested tests and does not currently require short-circuit `&&` / `||` semantics. This avoids committing the bootstrap compiler to that expression machinery before it is useful.

## Deliberate host-validation differences

The candidate source is compiled by the host with `-funsigned-char` so byte storage behaves like the intended 6502 byte model.

A host `int` is wider than the likely Nano C `int`. The assembler masks values at the places where 16-bit machine arithmetic is observable. The later Phase 1 specification must define the real Nano C widths and wrap rules explicitly; GCC or Clang do not get to define them accidentally.

The host I/O functions are defined before the candidate source is included. That lets `ass.c` call a tiny runtime surface without requiring headers, prototypes or a preprocessor in the candidate language. Nano C will need an equally small explicit rule for such runtime calls.

## Architecture retained

The C version deliberately keeps the important shape of the native assembler:

- one source line is resident at a time;
- statement text is parsed in place;
- symbol names are copied only when they must outlive the line buffer;
- the symbol table is linear and bounded;
- output bytes are staged at their final width as soon as they are known;
- ordinary unresolved 16-bit label references use their own two staged bytes as a forward-reference chain;
- exceptional byte/expression/relative references use a small bounded fixup table;
- labels patch waiting references when they are defined;
- includes use a fixed-depth open-file stack;
- no heap, AST, generic IR, relocation framework, object file or linker appears.

That is intentional: `ass.c` should discover the language needed to express the existing machine-oriented design, not quietly redesign the assembler around a modern host.
