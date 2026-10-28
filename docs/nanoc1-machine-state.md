# #102 — first machine-state experiment

The #101 reference compiler is correct on its native Phase 1 semantic corpus but
lowers every intermediate expression value to the **6502 hardware stack**.
This is not a competent default for a processor whose natural short-lived result
is already in A/X.

## Evidence before changing the emitter

In the baseline `nanoc1` output for `if (value != other)`, the compiler emits
the rough sequence:

```asm
    lda value
    ldx #$00
    pha
    txa
    pha
    lda other
    ldx #$00
    pha
    txa
    pha
    ; pop the right operand into NC_TMP, pop the left back into A/X
    jsr __nc_ne16
    pha
    txa
    pha
    ; pop it back into A/X for the conditional branch
```

The program expresses a *comparison followed by a branch*, but the original
emitter chooses the stack trajectory before that consumer is available.

Measured initial baseline (source blob
`489b31fab7ffc943fc95f7e0f032c66b2004d818`):

| Target | Generated assembly text | Loaded machine image |
| --- | ---: | ---: |
| native `nanoc1` itself, built by `nanoc0` | 189,920 bytes | 24,545 bytes |
| exact `bootstrap/ass.c`, built by `nanoc1` | 182,686 bytes | 33,225 bytes |

The latter has 4,186 `PHA` and 4,186 `PLA` instructions. It exceeds the
16 KiB `ass.c` executable region; this is a size probe, not a semantic failure.

## Bounded retained value

This PR tests the smallest useful form of *semantic* deferral: the most recently
completed value is **not immediately committed to the hardware stack**.
Instead, `ax_pending` records that the newest semantic value is still in A/X.

- A second value that needs A/X forces the previous value onto the stack.
- A binary reduction flushes its right operand, uses the existing proven
  stack prelude, and keeps the result in A/X for the next consumer.
- Scalar stores, returns, branch conditions and index address computation
  consume the pending A/X pair without a hardware-stack round-trip.
- Calls flush the pending final argument before storing parameters; the return
  value becomes pending. Indexed stores flush their RHS because the existing
  store template currently consumes a stacked value.
- The old operator/semantic stacks, source language, native runtime ABI and
  explicit fixed bounds are unchanged.

The *semantic operation* is retained; we do not buffer or rewrite already
selected 6502 instructions. This deliberately handles only one live register
value. It is not a general scheduler or sufficient for loop-cursor optimisation.

## Correctness and observation

CI must compile the exact `nanoc1.c` with native `nanoc0`, assemble it with
native `ass`, then compile and execute the existing Phase 1 fixtures with that
real native `nanoc1`. The added `ax-return.c` fixture asserts a direct
literal return has **no `PHA`/`PLA` in emitted source** and executes it.
`ax-nested.c` adds nested call, binary, index and store interactions.

The physical **24 KiB bootstrap window** is still a hard correctness constraint
for a running compiler, even though the generated `ass.c` 16 KiB size is not a
#102 gate. If the C compiler overflows its own window, this initial shape is
*not viable as submitted*, regardless of apparent generated-program gains.

## Next machine decision, once this base is green

The next experiment should defer a **source index/cursor relation** through a
small region, so a loop can distinguish:

- recomputing `base + i` at every access; versus
- retaining a zero-page cursor and/or Y index across accesses, with explicit
  invalidation at calls, aliasing stores and loop joins.

That requires knowing upcoming uses and loop boundaries, not just the most
recent expression value. Measure the emitted loop *as an algorithm* against
handwritten 6502; do not regard fewer pushes by itself as proof of completion
of #102.


## #102 next step: index-width-aware 6502 addressing

An indexed expression is currently parsed with bounded operator/value stacks.
By the time the closing `] ` is consumed, the parser knows the **complete
index expression's type** and whether the base is a fixed global array or a
stored pointer. This is sufficient forward semantic context to select an
addressing *algorithm*, rather than merely adjust emitted instructions.

For a global `char` array with a `char`-typed index, the index is
zero-extended, 0 through 255. No 16-bit address addition is necessary:

```asm
    ; index already in A, high byte in X is zero
    tay
    lda __gNN,y          ; base + Y, with correct page carry
    ldx #$00             ; canonical 16-bit result
```

The result remains pending in A/X, so a following scalar store or condition
can consume it without a stack round trip. The old lowering instead computes
`base + index` into NC_PTR and loads through `(NC_PTR),y`, introducing
two 16-bit additions and zero-page pointer stores.

The selection occurs at the **semantic index consumer**, after parsing the
whole index, but before emitting any address instructions. This is not a
textual peephole. It applies to repeated reads inside `while` and `if`
regions as well as straight-line reads. The fixture deliberately places a
256-byte array after 220 bytes of padding and accesses offset 200, forcing
an actual page crossing.

The fallback stays unchanged for `int` or `unsigned` index expressions,
wider array elements (which require index scaling), stored pointers, and
indexed *stores* (whose RHS can clobber Y). This conservative split avoids
assuming that a byte-valued index can represent an arbitrary 16-bit offset.

**Limitation:** We still reload Y for every access, and no register state is
kept across a loop back-edge. Retaining one index/cursor *between* independent
expressions requires source-identity tracking, plus conservative invalidation
at calls and loop/control joins. That is the next machine-state problem, not
a claim made for this initial index-algorithm selection.

Both the 24,576-byte native compiler bootstrap limit and full Phase 1 semantic
execution remain hard gates. The exact compiled `ass.c` loaded size is reported
as a measurement, independently of executable fit.


## #102: a source identity held in Y (next straight-line region)

The smallest persistent 6502 state worth testing after the absolute,Y choice is
**which char scalar Y was loaded from**, not another abstract expression form.
With the old direct emitter, each `a[i]` emits an independent `LDA i; LDX #0;
TAY`, including when the immediately previous access left the same `i`
unchanged in Y.

The parser already has one token of forward context: after reading identifier
`i`, it has scanned the next token. If that token is `]` and the current
operator is a *fixed global byte array* index, this is a complete, bounded
semantic operation. The compiler can select `LDY i` directly, without
emitting an unnecessary A/X semantic value, then `LDA array,Y; LDX #0`.

Three bytes of identity and one pending marker suffice:

- `y_known` says Y agrees with an unchanged source char scalar.
- `y_area, y_symbol` identify that scalar, including local/global namespace.
- `y_index_pending` says the topmost indexed expression will consume Y rather
  than a stacked or pending A/X index value.

If the next direct array access indexes the *same* scalar, no new `LDY` is
necessary, even when the array base differs and unrelated scalar stores occur
between accesses. A new scalar source gets a new `LDY`. This chooses a
different sequence of 6502 loads **before** generating the index value.

The current conservative invalidation contract is intentionally strict:

- Assignment to that scalar invalidates the identity after its RHS is read.
- Calls, arbitrary indexed address/write operations, unary/binary reductions,
  and string literal jumps invalidate Y.
- Function entry, `if`/`while` entries, block joins, `break`, and returns
  invalidate it; no assumption is made about loop-back-edge register state.
- Ordinary scalar loads and stores to *other* scalars preserve Y, and `LDA
  array,Y` itself leaves Y intact.

This is **cross-statement straight-line reuse**, not yet loop-carried reuse.
The next step needs a way to reconcile a known Y identity on *both* incoming
edges of a loop head, and to prove where it is still valid through the body,
rather than trusting the value observed while parsing source linearly.

Tests use the actual native-produced compiler. `y-index-identity.c` checks
three distinct regions: reuse over several unrelated scalar stores, a changed
index and if/else join, then invalidation by a function that changes a global
index. A generated-code assertion checks the number of `LDY` reloads
alongside native 6510 execution. The old wide-index regression ensures the
16-bit fallback is unchanged.

The native compiler remains limited to 24,576 loaded bytes. Space for this
bounded state comes from removing repeated output-error branches in the
existing emitter helpers, using their original sticky `compiler_error`
contract. No language rules, assembler source, or private test compiler
implementations have changed.
