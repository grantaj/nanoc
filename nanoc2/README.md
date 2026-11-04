# nanoc2 — traversal-first 6502 compiler

**Status: real Phase-1 parser, working C-written emitter for a bounded byte
subset plus basic 16-bit scalar operations. Native multi-function/call execution passes on the 6510. Not yet a
complete Phase-1 or self-hosting compiler. Draft PR #131.**

## Architecture

`parser_tape.c` retains the original `nanoc1` scanner, bounded expression
and statement parser, symbol/type rules and function definitions. Instead of
choosing instructions while parsing, the semantic actions capture bounded
typed expression nodes and ordered function events.

```text
original Nano C Phase-1 scanner / semantic parser
  -> bounded per-function expression and statement tape
  -> lower_tape.c: index, address, call and branch relationships
  -> traversal_backend.c: single 6502 emitter
  -> native_abi.c: Nano C parameter/local/global homes and entry code
```

A completed function is lowered and emitted **before parsing the next one**;
the whole translation unit does not need to retain all histories. Indexed
byte loads, comparisons and stores use one addressing selection: direct arrays
through X/Y or pointers through `(zp),Y`. Fixed-record strides use an explicit
16-bit address computation. Calls are ordered effects, with the caller's
X/Y-carried induction variables synchronized to their existing scalar homes
before `JSR` and reloaded after return.

Two-byte `int`/`unsigned` scalar loads, copies, literal assignments and
returns now use the original static homes, with low-byte results in A and
high-byte results in X. A scalar word plus/minus a literal is lowered directly
to a two-byte `CLC/ADC` or `SEC/SBC` carry chain, both for assignment and
return. Other word expressions are still rejected, rather than quietly
truncated to byte operations. Native tests cover carry, borrow and wraparound.

The current supported calls have **zero, one or two char parameters** and a
char result, with the callee already defined and only simple side-effect-free
argument expressions. The original type and arity checks still apply.
Unsupported constructs fail closed; no second source parser, source-routine
templates, peephole optimiser, instruction search or Python compiler is in
the production path.

## Native ABI and memory map

Static parameter/local homes are `__vFF_SS`, global homes `__gSS`;
byte returns leave the result in A and clear X. Generated functions use
internal `__cFF` labels and a single entry trampoline at `$0800`. The
C64 test caller uses `$1000`, **not** `$0200` (which overlaps IRQ-owned
system buffers). The test enables IRQs for the extended two-function run.

Two indirect pointer cursors occupy the C64's user-reserved `$FB–$FE`.
Other scratch bytes occupy reserved private RAM `$CF20–$CF22`. The
original Nano C runtime also uses `$FC–$FE`; a function with an active
indirect pointer cursor **cannot yet make a call**, and the lowerer
explicitly rejects that case. Full call clobber/save/restore semantics,
especially calls involving pointer arguments, are future work.

This separate memory map change also eliminated borrowing KERNAL IRQ ZP
at `$F0–$F6`. The prior long native test was additionally using the
unsafe `$0200` caller location; do not assume either cause in isolation
without another controlled test.

## Fast correctness tests

Run from the repository root, using host C and the narrow test-only 6502
instruction interpreter:

```sh
python3 nanoc2/test_parser_tape.py
python3 nanoc2/test_lower_tape.py
python3 nanoc2/test_indexed_write.py
```

They feed exact committed C function source to the **original parser**, with
independent GCC execution oracles: 6,500 read/traversal and 3,250 indexed
write comparisons, plus semantic rejection checks. Fast CI also syntax-checks
the native test/benchmark Python harnesses without installing VICE.

Call tests include a **non-identity one-byte callee** to verify that the actual
return value is consumed. An earlier identity-only test concealed a bug in
`nc2_last`, now corrected. The parser tests enforce zero/two-byte arity and
reject incorrect argument counts.

## Target-native tests

After `make setup`, explicitly run:

```sh
python3 nanoc2/test_native.py
```

This compiles source through the **same C path**, assembles generated code
with vasm, preloads it at `$0800` and executes a distinct caller at
`$1000` under VICE. These are native generated-program payloads including
the three-byte entry trampoline, not linked complete applications.

| Native test | Generated payload | Checks |
| --- | ---: | --- |
| `same_bytes` | 72 B | Equal/mismatch/page crossing and A/X return |
| `find_global` | 138 B | Record 175, fixed-record stride, mismatches |
| `copy_pointer` | 45 B | Indirect indexed writes across page boundaries |
| `copy_array` | 27 B | Fixed-array indexed writes |
| `call_index` | 64 B | Non-identity char call inside X-indexed loop |
| `call_arity` | 89 B | Zero/two-arg calls; return and argument values |
| `word_scalar` | 116 B | Word loads, copies, literal add/sub, A/X returns; carry, borrow and wraparound |
| `two_functions` | 78 B | Two separately streamed functions, static homes, IRQ enabled |

All eight passed in
[the native workflow run](https://github.com/grantaj/nanoc/actions/runs/41766489168).
Native smoke remains opt-in through the `native-smoke` PR label or
manual dispatch, not the fast default PR gate.

## Apples-to-apples image-size spot measurements

```sh
python3 nanoc2/test_size_spots.py
```

The script compiles **identical committed C source** with the unmodified
production `nanoc1/nanoc1.c` and the new `nanoc2` path, then has vasm
resolve the actual byte spans from function entry to function end. Both
use Nano C static argument homes; the old shared runtime and both entry
trampolines are excluded.

| Exact C function | nanoc1 body | nanoc2 body | Reduction |
| --- | ---: | ---: | ---: |
| `same_bytes` | 211 B | 69 B | 67.3% |
| `find_global` | 400 B | 135 B | 66.2% |
| `copy_pointer` | 158 B | 42 B | 73.4% |
| `copy_array` | 144 B | 24 B | 83.3% |
| `constant` | 5 B | 5 B | 0.0% |
| `guarded` | 48 B | 21 B | 56.2% |
| `map_byte` | 47 B | 20 B | 57.4% |
| **Total** | **1,013 B** | **316 B** | **68.8%** |

The old emitter generated 84 `PHA` and 84 `PLA` instructions across these
seven functions; the new emitter generated none. The original four traversal
functions alone total **913 B versus 270 B (70.4% smaller)** after moving
scratch out of KERNAL ZP. The earlier 72% result used an unsafe scratch map
and is **superseded**, not another comparable image.

The size and VICE tests passed together in
[workflow run 41766489168](https://github.com/grantaj/nanoc/actions/runs/41766489168).
These are function-body results, **not** a compiled `ass.c` image and not
proof the new compiler binary itself will fit C64 memory.

## Unfinished work

1. Complete Phase-1 16-bit operations beyond word +/- constant, remaining pointer expressions, general
   byte arithmetic, initialized globals, calls with pointer args and runtime
   service calls. Formalize pointer-cursor invalidation across calls.
2. Preserve the one-pass-per-function, bounded-memory design while removing
   remaining old output scaffolding from the inherited parser.
3. Run the full native Phase-1 corpus, self-compile the new compiler and
   measure the exact linked `bootstrap/ass.c` program and compiler image.
4. Compare remaining outliers with idiomatic handwritten 6502, but do not
   assume the handwritten assembler and `ass.c` are the same algorithm.

Production `nanoc1/nanoc1.c` is unchanged. **PR #131 stays draft/unmerged.**
