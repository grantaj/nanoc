# nanoc2 — replacement emitter from the original Phase-1 compiler

**Status: working research compiler for a restricted byte-traversal subset.
Draft PR; not a production Phase-1 replacement yet.**

## Architecture

The source begins with the exact, proven scanner, symbol model, bounded
operator stack and structured-control parser from `nanoc1/nanoc1.c`.
The fork lives in `parser_tape.c`. Its statement and expression actions now
construct **semantic nodes and function-local events** instead of directly
lowering arithmetic and addresses to stack-oriented 6502. The large
push/pop, binary arithmetic, comparison and address-reconstruction bodies
have been removed from the fork, not put behind an extra optimiser.

The pipeline is:

```text
original Nano C scanner + semantic parser
  -> typed expression nodes and statement/control events
  -> lower_tape.c: simple machine-state choices
  -> traversal_backend.c: 6502 text emitter
```

For supported loops, the lowerer derives X/Y roles and a reusable zero-page
record pointer from array accesses and recurrence expressions. It does **not**
select a named routine template or search an instruction space. Expressions
are represented only until the complete region is visible.

The former second lexer, independent statement parser and hand-authored tape
test driver have been **deleted**. There is only one source parser on the new
test path.

## Verification

From the repository root:

```sh
python3 nanoc2/test_parser_tape.py
python3 nanoc2/test_lower_tape.py
```

The test driver `parser_tape_driver.c` is host-only. It presents source bytes
through a stub for Nano C's `io_read`, invokes the original compiler's parser,
discards the **old top-level output scaffolding**, then invokes the new C
lowerer and 6502 emitter.

The tests extract the **exact, unmodified** `same_bytes()` and
`find_global()` C functions from `nanoc1/nanoc1.c`. They compare generated
6502 execution in an independent instruction interpreter against those same
functions compiled with GCC, including nested loops, `break`, page crossing
and searches across 176 symbol records. The expanded test set has **6,500**
cases and explicit negative tests for invalid C and unsupported semantics.

These are interpreter/oracle comparisons, **not** a linked C64 image, VICE
execution, or self-hosting. The scalar and pointer zero-page homes are set up
by the host test adapter, not a native ABI.

## What the new compiler intentionally rejects

The current lowerer is limited to byte scalars and read-only traversals,
including an affine power-of-two record stride. General 16-bit arithmetic,
16-bit return values, arbitrary pointer arithmetic, calls, array writes,
unsupported conditions and alias-sensitive operations are not yet lowered.
They must remain errors until proven correct; no silent byte truncation or
fallback to the old stack emitter is acceptable.

## Work remaining for complete replacement

1. Complete the semantic event vocabulary for Phase-1 expressions, pointer
   writes, calls, and full 16-bit arithmetic without rebuilding the old
   stack-machine emitter.
2. Provide a real native register/zero-page/call ABI, and emit BSS and
   function boundaries for **all** functions in a translation unit. The
   host test's dedicated parameter homes are not that ABI.
3. Compile and execute the existing Phase-1 corpus on the C64; then compile
   exact `bootstrap/ass.c`, compare instruction-level differences against
   the handwritten assembler, and measure the complete loaded image.
4. Delete the now-unused assembly-template pool and old output scaffolding
   after the replacement covers those functions. Preserve the small,
   established lexer/symbol/type parser.

This branch must not be merged as a finished compiler until those gates pass.
`nanoc1/nanoc1.c` and the production baseline are unchanged.
