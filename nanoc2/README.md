# nanoc2: replacement compiler, original parser and traversal-first backend

This is a **draft replacement**, not a production-ready compiler. The source
semantic authority is the *existing* Nano C Phase-1 scanner, symbol/type
rules, bounded operator parser and statement parser. The earlier separate C
source adapter, hand-authored tape driver and alternative integrated fork have
been deleted rather than retained as parallel implementations.

## Architecture

1. `parser_tape.c` is currently a fork of the original
   `nanoc1/nanoc1.c`. Its original parsing functions record semantic
   expression nodes and ordered statement events (labels, branches, writes,
   returns, etc.). No second lexer or statement grammar participates in this
   path. This step retains the original Phase-1 syntax/type validation.
2. `lower_tape.c` reads those nodes/events and derives the small byte-index
   and pointer traversal representation, including a scaled-record address
   from an affine C expression. It rejects unsupported semantics rather than
   silently reverting to the old stack code generator.
3. `traversal_backend.c` chooses simple X/Y homes and emits the 6502. Its
   indexed accesses are selected from the relationships recorded by the
   parser, not from source-function names.

The old immediate emitter functions **still exist inside the temporary parser
fork** because the semantic front end has not yet been fully separated from
the original emitter. Their output is ignored by the host bridge; that is
**unfinished deletion work**, not intended architecture. The next substantial
step is to remove this source code and extend the one new lowering path to
full Phase-1 expression and call semantics.

## Reproduce the current tests

From the repository root:

```sh
python3 nanoc2/test_parser_tape.py
python3 nanoc2/test_lower_tape.py
```

The tests extract exact `same_bytes()` and `find_global()` source from the
unchanged production `nanoc1/nanoc1.c`. The first tests original-parser
semantic recording and rejection of invalid C. The second runs the full
original-parser -> C semantic lowerer -> 6502 path in an instruction-level
interpreter, comparing against independently host-compiled C on random test
cases (including nested loops, record stride and pointer page crossings).
The interpreter is `test_6502.py`; it is a test oracle, not another compiler.

The test manually supplies the provisional zero-page argument/pointer homes;
there is **not yet** a linked executable or complete C64 ABI. The code has
not passed native VICE self-hosting or the exact assembler functional oracle.

## What is done and what is not

Implemented: a single original semantic parser to typed nodes/events, a C
lowerer for byte-array/pointer traversals and nested control flow, safe
rejection of unsupported patterns, and end-to-end tests for two real
compiler-source functions.

Not implemented: the full Phase-1 expression/call/16-bit surface in the
replacement emitter; target-native argument and pointer-home setup, complete
linking, full compiler-source self-compilation, removal of the remaining old
emitter functions from the temporary parser fork, and measured whole-program
machine-code quality. Consequently this PR must remain **draft/unmerged**.

**Simplicity criterion:** any extension should remove or replace existing
code-generation machinery. Do not add per-function selectors, a second
semantic parser, or an optimisation layer above the old stack emitter.
