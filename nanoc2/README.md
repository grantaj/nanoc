# nanoc2 — traversal-first 6502 compiler

**Status: original Phase-1 parser and one C-written 6502 emitter, now accepting
32 of 44 consecutive original `ass.c` functions. Representative real routines
execute under native VICE. This is not yet a complete Phase-1, self-hosting
compiler or whole-image benchmark. Draft PR #131.**

## Source-driven acceptance: `bootstrap/ass.c`

`python3 nanoc2/test_ass_frontier.py` is a fast-CI gate against the
**complete unmodified** 1,792-line original Phase-1 assembler. It
reports the first failed function, retaining all original global
declarations, and rejects regressions below the verified prefix.

**4 November 2026: 32/44 consecutive original functions compile**,
from `upper_char` through `assemble_string`. The new general
comparison lowering evaluates pure +/− arithmetic on the RHS to a full
16-bit value; this unlocks the original `while (i < length - 1)`.
The next rejected function is #33, `open_include`, at line 1385:
`handle = io_open(source_path, output)`, where the original semantic
parser's builtin-I/O capture is not yet supported (tape fault 11).

Target-native VICE exercises the **verbatim 32-function prefix**,
including string copying, page-crossing input, unterminated strings,
long 255-byte inputs and output-capacity boundaries. The new
`comparison-rhs.c` oracle also verifies all six relations, signed/
unsigned 16-bit values and arithmetic chains. Native tests verify
these specific behaviours; **full assembler runtime and I/O are not yet
implemented**.

The work was driven by real C constructs: typed 16-bit array
loads/stores; `base_word + byte_index` addressing through separate
6502 ZP pointer lanes; char-pointer forwarding and restoration across
JSR; initializing live X/Y from incoming parameter homes; bounded
source-ordered calls with up to eight typed arguments; full-width
negative comparisons; and direct low-byte/high-byte-shifted word
packing. The latter maps the common `lo | (hi << 8)` source idiom to
two reads/stores, without a generic optimizer or IR.

Native tests exercise the original assembler's fixup tables, symbol
lookup/allocation and scope, `intern_label`/`define_constant`,
byte/word linked patches, and `define_label` carrying a pending fixup
through the actual resolver. Boundary tests include byte addresses
255/256, 511/512, end-of-buffer writes, and symbol indexes 255/256
and 895. Unlike source-acceptance testing, these execute on a 6510
in VICE with an independently assembled caller.

Initialized globals are emitted as physical data labels, distinct
from uninitialized `NC_BSS`. The complete `ass.c` runtime, entry
point, self-hosting and whole linked image are **not yet implemented**;
the numbers below are physically assembled function-body spans,
not equivalent to the handwritten assembler's full image.

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
returns use the original static homes, with low-byte results in A and
high-byte results in X. Word plus/minus a literal **or another word scalar**
lowers to a two-byte `CLC/ADC` or `SEC/SBC` carry chain, including in-place
updates and direct expression returns. Full-width comparisons `==`, `!=`,
`<`, `<=`, `>` and `>=` compare high byte first, then low byte only on
a high-byte tie. Signed comparisons bias the high byte by `$80`; the parser
records usual signed/unsigned conversion before lowering. Equality and ordering
branches directly consume the final comparison flags, rather than materialising
a Boolean. A bare word variable condition uses `LDA/ORA` across both bytes.
These are general typed operations, not source-loop patterns.

Mixed byte/word arithmetic now zero-extends byte operands to 16 bits and
uses direct `ADC/SBC` carry chains for two scalar operands. A bounded
non-recursive walk accepts **left-associated chains** such as
`result = left + right - offset + 257`; the compiler evaluates all terms
into a two-byte private accumulator before writing the destination. That
preserves source reads in expressions such as `a = a + b + a` and supports
byte truncation at assignment/return boundaries. Direct byte-pair addition
and reversed word/byte operations use ordinary 6502 instructions without
materialising a scratch accumulator. Conditions now accept full-width signed/unsigned comparisons between
scalars of different widths or against numeric literals in either operand
order. A pure left-associated arithmetic chain may also appear directly
in an `if` or `while` condition, or on the **left** of a comparison;
the two-byte accumulator is tested without writing a source home.
The high/low comparison reuses the same typed numeric lowering, with
no boolean materialization. Right-nested trees, calls inside arithmetic expressions, multiplication,
non-literal unary arithmetic, right-hand arithmetic comparison operands
and general pointer arithmetic still fail closed. Literal unary minus,
word-constant AND and unsigned high-byte extraction (`>> 8`) are now
lowered directly using 6502 idioms.

Calls now accept **zero, one or two byte or word parameters**, and byte or
word results. The callee must already be defined; arguments are evaluated
left-to-right and staged in its original static Nano C homes. Literal, scalar
and direct indexed byte arguments are supported, including byte-to-word zero
extension and word-to-byte truncation. Calls save the return A/X to
`__tret`/`__trethi` before restoring the caller's X/Y-carried loop indices.
There is no extra high-byte save for byte-returning calls. Call expressions
can feed byte/word assignments or direct returns, including widening a byte
result to a word. Nested and side-effectful argument expressions remain
unsupported. The original parser's type and arity checks still apply.
Unsupported constructs fail closed; no second source parser, source-routine
templates, peephole optimiser, instruction search or Python compiler is in
the production path.

## Native ABI and memory map

Static parameter/local homes are `__vFF_SS`, global homes `__gSS`;
byte returns leave the result in A and clear X; word returns use A-low/X-high.
Generated functions use
internal `__cFF` labels and a single entry trampoline at `$0800`. The
C64 test caller uses `$1000`, **not** `$0200` (which overlaps IRQ-owned
system buffers). The test enables IRQs for the extended two-function run.

Two indirect pointer cursors occupy the C64's user-reserved `$FB–$FE`.
Other scratch bytes occupy reserved private RAM `$CF20–$CF25`. The
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
reject incorrect argument counts. The committed `word-ops.c` fixture tests
word arithmetic and signed/unsigned branch lowering, rejects unsupported word
multiplication and checks that no unresolved `INVALID_HOME` operand escapes
the generated assembly. The committed `word-call.c` fixture covers 16-bit
parameter homes, mixed-width arguments, call results assigned to word locals,
direct word returns, incorrect arities and a live X-index across a word call.
The `mixed-arithmetic.c` fixture exercises 174 native results, including
16-bit carry/borrow, signed-range boundaries, byte widening/narrowing,
non-unit byte arithmetic, left-associated chains and destination aliasing.
It also tests `i = i + 2` in a loop using a live X array index, so a
stale static index home cannot conceal an incorrect implementation.
Fast checks reject unsupported right-nested trees and multiplication.

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
| `word_ops` | 804 B | 211 native checks: word+word, aliasing, six signed/unsigned relations, constants and word loop conditions |
| `word_call` | 366 B | Static word parameters/returns, mixed-width conversion and X-register preservation |
| `mixed_arithmetic` | 735 B | 174 checks: mixed widths, composed chains, aliasing, live X non-unit stride |
| `mixed_compare` | 1,114 B | 35 signed/unsigned width, literal-order and live-index comparison functions |
| `expression_condition` | 590 B | 73 arithmetic-condition result checks and indexed memory validation |
| `ass_prefix` | 327 B | First four verbatim `ass.c` functions, initialized globals and pointer/word ABI |
| `ass_wide_index` | 1,497 B | First seven original `ass.c` functions, fixup tables, 16-bit indexes, wraparound |
| `two_functions` | 78 B | Two separately streamed functions, static homes, IRQ enabled |

All **23** native programs passed in
[the native workflow run](https://github.com/grantaj/nanoc/actions/runs/41797378744).
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
seven functions; the new emitter generated none.

The measurement suite has now been **extended**, not replaced. The same
source/ABI/assembler protocol also measures 16-bit scalar functions, word
arithmetic/comparisons and the whole `word-call.c` calling unit (to include
caller and callee costs under the same statically allocated ABI).

| Measured scope | Count | nanoc1 bodies | nanoc2 bodies | Reduction |
| --- | ---: | ---: | ---: | ---: |
| Original seven | 7 | 1,013 B | 331 B | 67.3% |
| Word scalar | 4 | 162 B | 84 B | 48.1% |
| Word arithmetic/branch | 12 | 610 B | 378 B | 38.0% |
| Complete word-call unit | 13 functions | 459 B | 366 B | 20.3% |
| Mixed-width/composed arithmetic | 23 | 1,156 B | 735 B | 36.4% |
| Mixed signed/unsigned comparisons | 35 | 1,831 B | 1,114 B | 39.2% |
| Arithmetic in conditions | 9 | 840 B | 590 B | 29.8% |
| Overlapping real-`ass.c` measurements (11 cases; 31 function bodies) | 31 | 12,279 B | 6,580 B | 46.4% |
| Indexed word-array tests | 4 | 249 B | 263 B | -5.6% |
| Computed comparison RHS | 10 | 793 B | 663 B | 16.4% |\n| **Combined** | **148 function-body measurements** | **19,392 B** | **11,104 B** | **42.7%** |

The complete **first 15 original `ass.c` function bodies** are also
measured together as one exact-source assembled unit: **6,302 B**
with `nanoc1` versus **3,464 B** with `nanoc2` (**45.0% smaller**).
The full **first 32 original `ass.c` function bodies** also assemble
to **9,981 B** with `nanoc2` (10,725 B for the corresponding
native program, including entry and global initialization). Production
`nanoc1` rejects that exact prefix (exit 2), so no fabricated old
byte count or reduction percentage is reported for it. This
new-only physical measurement is **excluded** from the comparable total.

Some other grouped tests remeasure the same original functions; do not
interpret the 148 function-body occurrences as 148 distinct routines.

The suite now has 116 comparable source measurement cases, including the multi-function
unit. For word calls, a single span includes all 13 functions; no runtime,
test caller or entry trampoline is counted. The smaller call, word-branch and chained-expression reductions reveal
remaining code-generation quality gaps, not a reason to substitute the
arbitrary 16 KiB fit target for the handwritten image. Three initial byte
regressions (`reverse_mixed`, `reverse_sub`, `byte_sum_word`) were removed
by direct operand selection; exact-size assertions now prevent recurrence. The original four traversal
functions alone total **913 B versus 270 B (70.4% smaller)** after moving
scratch out of KERNAL ZP. The earlier 72% result used an unsafe scratch map
and is **superseded**, not another comparable image.

The size and VICE tests passed together in
[workflow run 41797378744](https://github.com/grantaj/nanoc/actions/runs/41797378744).
A subsequent general identity-mask change briefly regressed the actual
`ass.c` `apply_byte_prefix` code by 12 bytes; the redundant word
self-copy was removed and an exact **23-byte** size limit added to
the benchmark. All totals above include that correction.
These are function-body results, **not** a compiled `ass.c` image and not
proof the new compiler binary itself will fit C64 memory.

## Unfinished work

1. Advance original `ass.c` from **32/44**. Function 33,
   `open_include`, reaches builtin `io_open(source_path, output)`.
   Capture the original parser's builtin I/O call as a genuine typed
   ordered effect, supply a compatible native runtime boundary and
   test error/handle semantics. Do not substitute a name-specific
   parser recognizer or claim execution before I/O is linked.
   Extend exact-source physical benchmarks whenever a valid baseline exists.
2. Preserve the one-pass-per-function, bounded-memory design while removing
   remaining old output scaffolding from the inherited parser.
3. Run the full native Phase-1 corpus, self-compile the new compiler and
   measure the exact linked `bootstrap/ass.c` program and compiler image.
4. Compare remaining outliers with idiomatic handwritten 6502, but do not
   assume the handwritten assembler and `ass.c` are the same algorithm.

Production `nanoc1/nanoc1.c` is unchanged. **PR #131 stays draft/unmerged.**
