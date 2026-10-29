# Why indexed-address optimisation has repeatedly stalled (#102)

**2026-10-30. Diagnostic audit of the exact recovered 8,945-byte full-image research backend. No compiler changes or new size claims.**

## Diagnosis

There is not a missing 6502 addressing-mode emitter. The active class resolution order is:

`NativeCompareBackend → RegisterFirstBackend → DirectAddressBackend → AddressPlanBackend → FoldedBackend → DualPointerBackend → DirectReadCompareBackend → YLoopBackend → WidthDemandBackend → ByteDemandBackend → ... → StateBackend → LoopBackend → IndexedBackend → ConsumerBackend → Backend`.

Thus an earlier suspicion that `IndexedBackend` was wholly disconnected was **incorrect**. It is reached for ordinary byte-indexed accesses. The actual barriers are **missing range proofs**, **limited address/cursor lifetime**, and, for wide tables, **a genuinely different source layout/traversal algorithm**.

### Reproduced operation inventory

Enumerated all reachable `read` and `store_index` operations in the 44 typed tapes under `full_corpus/whole_corpus/*.c`, after the backend's existing semantic/constant transformations, using its actual `full_corpus/whole_corpus/arrays.json` data:

| Indexed operations | Count |
| --- | ---: |
| Total reads / writes | **97 / 30** |
| Index type `s16` | **85** |
| Index type `u8` | **42** |
| Element type byte / word | **112 / 15** |
| Syntactically eligible byte-element direct-Y operations (`u8` or 0..255 const) | **60** |
| Eligible reads / writes | **53 / 7** |
| Byte-element accesses *not* syntactically eligible | **52** |
| All accesses not eligible including word elements | **67** |

Of the 85 `s16` index values, the source expression's operation was `load` (44), compile-time `const` (18), `-` (13), or `+` (10). In this tape, all arithmetic promotion retains `s16` even if it originated from a byte-sized value. The active selector in `full_corpus/backend4.py` accepts only explicit `u8/bool` or an in-range literal. It **does** produce `LDY index; LDA (zp),Y` for eligible pointer reads and `LDY index; LDA array,Y` for eligible named-array reads. `Backend.op` already has analogous direct-Y handling for eligible byte writes. Thus repeating the same byte-index pattern substitution cannot solve the remaining wide accesses.

The final emitter's existing address state reports **1 address-cache hit** and **0 scaled-index-cache hits** across the full image. The prior independent instrumented audit counted **61 full effective-address constructions** in the final emission (including 47 named array bases and 14 pointer bases). These are **current work being done**, not an assertion that all its pre-outlining bytes are recoverable.

### Reproduced region-planning coverage

`LoopBackend` accepts **4** loop cursor plans across the 44-function corpus: `all_fixups_resolved`, `all_symbols_defined`, and two `parse_atom` loops. It records **46** rejected loop-candidate headers (some of these are if/other syntactic branch shapes, so 46 must not be called 46 valid optimisable loops). The diagnostic rejection tally is:

| Reason | Number |
| --- | ---: |
| Non-scalar invariant bound / nonloop shape | 27 |
| No unique loop latch | 7 |
| Call or indirect write invalidates machine state | 4 |
| Multiple indexed expressions would clobber Y/pointer | 3 |
| Nonconstant/out-of-range preheader index | 2 |
| Other (mutation, increment, mixed array bases) | 3 |

Specific failures: `find_symbol` is rejected for multiple indexed expressions using Y/pointer; `allocate_symbol` for a call/indirect write; `resolve_fixups_for_symbol` for calls/indirect writes. `AddressPlanBackend.mark()` resets both retained address and index at **every label**; `emit('jsr', ...)` invalidates them; stores to `__ap/__ix` invalidate their state. It is correct to invalidate *unproven* state, but this is why a cache attached to individual addresses fails to behave like a planned loop-carried machine cursor.

## Concrete source/machine examples

### Guarded byte-length indexing: avoid the false-wide fallback

In `full_corpus/whole_corpus/assemble_instruction.c`, `argument_length` is `char` (byte) and guarded by length tests, but `argument_length - 1`, `-2`, `-3` become `s16` tape nodes. The current emitted instruction sequence loads a two-byte arithmetic result and performs full pointer addition through `__ix/__ap`; this is seen at eight 16-bit subtraction READs in that function. Where the actual control-flow path establishes `argument_length >= k`, the index `argument_length-k` is in 0..255 and an 8-bit Y offset is semantically sufficient. The tape does **not record or propagate that path-dependent range fact to instruction selection**. Narrowing such an index without proof is unsound: `char` is promoted to signed 16-bit `int` and the subtraction may be negative on a different path.

### Wide symbol/fixup tables: Y alone is *not* the fix

`find_symbol` walks up to **896** symbols. `resolve_fixups_for_symbol` walks up to **640** fixups; `symbol_name_bytes` has **9,344 bytes**, and `ass_image` **11,264 bytes**. The 16-bit indexes here are not a compiler error. A raw `LDA symbol_scope,Y` with Y in 0..255 would wrap rather than address the next page. The native assembler instead advances stable **16-bit record pointers**, using Y to select fields. The C source instead has several independent parallel arrays, often using the same 16-bit index. The backend has no persistent logical record cursor shared across those arrays; it falls back to repeated full word-index scaling/address calculation.

The prior generic two-pointer loop experiment was *real* and safely recognised one inner `find_symbol` loop, but yielded only ~21 bytes in its historical full-image baseline. The failure is not because (zp),Y is unknown; the strategy's proof rejects almost all substantive wide/call-rich loops, and the SoA C data representation remains.

## Underlying mechanism

1. **Source expression types survive, but derived value ranges do not.** `TapeBuilder` promotes byte arithmetic to word expressions; there is no CFG edge-specific interval/range record that the indexed-access consumer can use.
2. **Memory-address values are recomputed, not represented as a durable traversal choice.** The current address cache models a single short-lived `__ap` and `__ix`, invalidated at all labels and calls. It does not represent a base plus offset and evolving high/low page carry as an invariant across loop backedges.
3. **The loop proof accepts extremely narrow source shapes.** In practice, actual assembler loops mutate storage, call helpers, scan multiple arrays, or use 16-bit limits. Those are not automatically unsafe; they require modelling the affected machine state, and choosing which pointer/index lives across each effect.
4. **Some differences cannot be repaired without changing C algorithms.** Parallel numeric-indexed tables cannot in general turn into native variable-length record pointers merely by choosing a different addressing mode. This should remain a *separate* experimental control, not be hidden inside the compiler savings.

## Discriminating next work (not another small addressing patch)

- First, add **range facts on CFG edges** to the existing typed tape, preserving exact C signed-word semantics. Prove specific `0 <= index <= 255` results at indexed *consumers* (including `char - const` under guarding conditions); emit direct-Y accesses with no unnecessary 16-bit arithmetic when established.
- Separately, plan **complete traversals**, not individual addresses. Carry an abstract 16-bit pointer/page+Y cursor across headers/backedges and multiple accesses, with explicit proofs of alias effects, call clobbers, and page crossing. Select A/X/Y/ZP placement and the cursor's lifetime for the *whole region* before emitting it.
- Reproduce complete linked size with full correctness oracles, and compare all candidate savings **after** the existing sequence outliner. Do not set a made-up stopping byte target, assert that pre-outlining costs are entirely recoverable, or divert to production `nanoc1.c` integration.

This report explains **why previous attempts did not compose**. It does not yet prove that a new range/cursor implementation saves 1 KB, nor that every discrepancy with the 6,905-byte handwritten assembler is compiler waste.
