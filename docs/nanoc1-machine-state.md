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
