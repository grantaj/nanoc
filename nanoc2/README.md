# nanoc2 — original Phase-1 parser, traversal-first 6502 emitter

**Status: original-parser source-to-6502 compiler for a restricted byte subset.
Native 6510 execution is proven for four routines. Draft PR, not yet a
complete Phase-1 compiler or self-hosted.**

## The one compiler path

The existing scanner, symbols, type checks, bounded operator parser and
structured-statement parser are inherited from `nanoc1/nanoc1.c` in
`parser_tape.c`. Their expression/statement actions record small semantic
nodes and bounded function events **before target instructions are emitted**.

```text
original Nano C scanner + semantic parser
  -> typed expression nodes / control-flow events
  -> lower_tape.c (simple traversal and X/Y decisions)
  -> traversal_backend.c (one 6502 emitter)
  -> native_abi.c (static Nano C homes and pointer-entry prologue)
```

Indexed byte **loads, comparisons and stores** share the same address
lowering. Pointers use `(zp),Y`, direct arrays use `,X` or `,Y`, and a
scaled record offset may hold a reusable pointer in ZP. There are no named
source-routine recipes, generic search, parallel source parsers, or
post-generation optimiser layers.

## Fast semantic and machine tests

From the repository root (host C compiler and Python only):

```sh
python3 nanoc2/test_parser_tape.py
python3 nanoc2/test_lower_tape.py
python3 nanoc2/test_indexed_write.py
```

The host adapter `parser_tape_driver.c` feeds C source bytes to the original
Nano C semantic parser, then calls the same C lowerer/emitter. The semantic
oracle functions are the **exact original** `same_bytes` and `find_global`
functions from `nanoc1.c`, and byte-indexed write fixtures in
`tests/nanoc2/indexed-write.c`. Independent GCC oracles and a narrow
instruction-level 6502 interpreter compare return values and byte memory
effects: **6,500 + 3,250 = 9,750 tests**. Unsupported expressions fail closed.

The interpreter's manually loaded zero-page homes are **only a test ABI**;
the native test below no longer relies on that setup.

## Native 6510 ABI smoke

Once the normal C64 tools are installed (`make setup`), run:

```sh
python3 nanoc2/test_native.py
```

This uses the **same original parser and C emitter**, but the
`native` output option of `parser_tape_driver.c` writes a complete small
native assembly unit. `native_abi.c` names static homes using the established
Nano C convention:

- Global `__gSS`; local/parameter `__vFF_SS`
- Return byte in **A**, X **zero**
- Function `__cFF`; entry point `__nc_start`
- Zero-page cursor slots `$f0-$f3`, calculation scratch `$f4-$f5`
- Uninitialized global/local BSS starting at `$4800`

On entry, the compiler-generated prologue loads `char *` parameter words
from their **actual static homes** into ZP cursors; the test caller **only
stages ordinary C parameters**, never cursor values. These scratch homes are
safe only for the present call-free subset and require a call clobber
contract before general functions are supported.

The test assembles the **generated** routine using vasm into its own
`$0800` PRG; a separate `$0200` test caller supplies parameters and checks
results, using the repository's standard VICE preload/run-test harness.
Its native checks on a real emulated 6510 passed:

| Routine | Generated native PRG payload | Checks |
| --- | ---: | --- |
| `same_bytes` | 72 B | Equal/different buffers, 200-byte page-crossing, lengths, A/X returns |
| `find_global` | 124 B | 175th record, mismatched record, first record, A/X returns |
| `copy_pointer` | 45 B | 200-byte indirect indexed copy, byte-for-byte effects, A/X return |
| `copy_array` | 27 B | 200-byte fixed array copy, byte-for-byte effects, A/X return |

These sizes **include** a small entry wrapper and pointer prologue where
needed, but **exclude** the caller and do not represent linked `ass.c`.
Native smoke is an **explicit test tier**, separate from default fast CI:
apply the `native-smoke` PR label, or dispatch its workflow when available
on the default branch. A verified run is recorded in PR #131's history.

## Same-C-source function-body size comparison

The opt-in native workflow now runs:

```sh
python3 nanoc2/test_size_spots.py
```

This compiles **identical committed Phase-1 C functions** twice: once using
the unmodified production `nanoc1/nanoc1.c` through the narrow
`production_baseline_driver.c` host I/O shim, and once through nanoc2's
original-parser → semantic-events → traversal-first C emitter and native
ABI. Both are assembled with **vasm**. Each exact body length is calculated
from resolved assembler symbols, not by counting instructions or guessing
instruction sizes. The production runtime and both entry wrappers are excluded
from the function-body comparison; static parameter/local/global homes have
the same contract.

| Function | Original nanoc1 | New nanoc2 | Reduction | Original PHA/PLA | New PHA/PLA |
| --- | ---: | ---: | ---: | ---: | ---: |
| `same_bytes` | 211 B | 69 B | 67.3% | 16/16 | 0/0 |
| `find_global` | 400 B | 121 B | 69.8% | 36/36 | 0/0 |
| `copy_pointer` | 158 B | 42 B | 73.4% | 12/12 | 0/0 |
| `copy_array` | 144 B | 24 B | 83.3% | 12/12 | 0/0 |
| **Four function bodies** | **913 B** | **256 B** | **72.0%** | **76/76** | **0/0** |

Source: [successful targeted native workflow](https://github.com/grantaj/nanoc/actions/runs/41743070650).
The test also writes the two source-level machine bodies under
`build/nanoc2-size-spots/` for inspection and comparison.

**Scope:** this is strong evidence that selecting byte-index and pointer
access *before instruction emission* eliminates structural stack and address
overhead on the represented subset. It is **not** a full linked `ass.c`
benchmark: the current native backend is still single-function, byte-only
and call-free, so shared runtime, general 16-bit arithmetic, call overhead and
remaining parser/compiler binary size are unresolved. The handwritten
assembler is also a different source-level algorithm.

## Boundaries and next steps

1. The current native assembly unit supports **one byte-returning function**,
   uninitialized globals and no C calls. Other function definitions or global
   initializers must be rejected. General source files still need native
   function boundaries, static storage and initialization integrated with
   the existing parser across the *whole* translation unit.
2. Complete Phase-1 arithmetic, word values, function calls, general pointer
   writes, side effects, and control-flow joins in the **one new lowering
   path**. Register/cursor homes must be reconciled across calls/regions.
3. Run the full native Phase-1 correctness corpus, then self-compile and
   measure exact `bootstrap/ass.c` against the handwritten 6,905-byte
   assembler. Current tests **do not establish** these properties.
4. Delete remaining legacy output scaffolding from the parser fork when
   Phase-1 semantic equivalence is achieved. Do not import another parser,
   another register allocator, or research-only Python code generator.

Production `nanoc1/nanoc1.c` remains unchanged. This PR stays **draft**.
