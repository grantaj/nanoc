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
returns use the original static homes, with low-byte results in A and
high-byte results in X. Word plus/minus a literal **or another word scalar**
lowers to a two-byte `CLC/ADC` or `SEC/SBC` carry chain, including in-place
updates and direct expression returns. Full-width comparisons `==`, `!=`,
`<`, `<=`, `>` and `>=` compare high byte first, then low byte only on
a high-byte tie. Signed comparisons bias the high byte by `$80`; the parser
records usual signed/unsigned conversion before lowering. Equality and ordering
branches directly consume the final comparison flags, rather than materialising
a Boolean. A bare word variable condition uses `LDA/ORA` across both bytes.
These are general typed operations, not source-loop patterns. Complex expression
trees, word multiplication, mixed byte/word arithmetic and pointer arithmetic
remain unsupported and are explicitly rejected.

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
Other scratch bytes occupy reserved private RAM `$CF20–$CF23`. The
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
| `two_functions` | 78 B | Two separately streamed functions, static homes, IRQ enabled |

All ten passed in
[the native workflow run](https://github.com/grantaj/nanoc/actions/runs/41769848565).
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
| Original seven | 7 | 1,013 B | 316 B | 68.8% |
| Word scalar | 4 | 162 B | 84 B | 48.1% |
| Word arithmetic/branch | 12 | 610 B | 378 B | 38.0% |
| Complete word-call unit | 13 functions | 459 B | 363 B | 20.9% |
| **Combined** | **36 function bodies** | **2,244 B** | **1,141 B** | **49.2%** |

The new suite has 24 source measurement cases, including the multi-function
unit. For word calls, a single span includes all 13 functions; no runtime,
test caller or entry trampoline is counted. The smaller call and word-branch
reductions reveal a real remaining code-generation quality gap, not a reason
to substitute the arbitrary 16 KiB fit target for the handwritten image. The original four traversal
functions alone total **913 B versus 270 B (70.4% smaller)** after moving
scratch out of KERNAL ZP. The earlier 72% result used an unsafe scratch map
and is **superseded**, not another comparable image.

The size and VICE tests passed together in
[workflow run 41769848565](https://github.com/grantaj/nanoc/actions/runs/41769848565).
These are function-body results, **not** a compiled `ass.c` image and not
proof the new compiler binary itself will fit C64 memory.

## Unfinished work

1. Complete general 16-bit expressions beyond simple word +/- scalar/literal
   (mixed widths, composed arithmetic, unary expressions and comparison
   operands), then remaining pointer expressions, initialized globals, pointer
   arguments and runtime service calls. Formalize pointer-cursor invalidation
   across calls; byte/word scalar calls are already supported.
2. Preserve the one-pass-per-function, bounded-memory design while removing
   remaining old output scaffolding from the inherited parser.
3. Run the full native Phase-1 corpus, self-compile the new compiler and
   measure the exact linked `bootstrap/ass.c` program and compiler image.
4. Compare remaining outliers with idiomatic handwritten 6502, but do not
   assume the handwritten assembler and `ass.c` are the same algorithm.

Production `nanoc1/nanoc1.c` is unchanged. **PR #131 stays draft/unmerged.**
