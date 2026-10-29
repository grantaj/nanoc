# Nano C: certified two-base loop region experiment (2026-10-29)

## Goal and baseline

This is a research-only experimental extension of the full `bootstrap/ass.c` tape-to-6502 compiler. The test deliberately looks for a *region-wide machine algorithm* rather than an adjacent-instruction load cache. The authoritative code-size reference remains the **6,905-byte handwritten assembler**. The exact research baseline is the **11,855-byte loaded C compiler output** (branch and source version held constant); it is not the obsolete 16 KiB size gate.

## What changed

The existing general `DualPointerBackend` recognises a certified natural byte-scan loop. It now also accepts two read-only bases when one is a pointer indexed by an 8-bit induction variable `j` and the other is a named byte-array indexed by `offset+j`, where `offset` is an invariant 16-bit scalar. In a proven region it:

1. Constructs the pointer base in `__ap` and array-base-plus-offset in `__ix` **once** in the preheader;
2. Uses Y for `j` across the loop header, nested branches, and unique latch;
3. Selects `LDA (__ap),Y` / `LDA (__ix),Y` for the two reads, suppressing a now-unneeded `offset+j` machine calculation;
4. Preserves the actual scalar `j` writes for C semantics, and refuses the plan on calls, unknown pointer stores, index/bound/base mutations, nonunit induction, side entries, or another unmodelled scratch/pointer user.

This rule uses only typed operations, CFG predecessors and array/pointer types; it never checks C function names or strings. It selects one eligible hot region: the name-comparison inner loop in `find_symbol`. The other substantial symbol/fixup loops contain mixed-width indexing, effects and calls and therefore correctly remain on the old generic lowering.

## Measured physical result

| Measure | Unchanged backend | Certified region backend | Difference |
|---|---:|---:|---:|
| Exact linked `ass.c` image bytes | 11,855 | **11,834** | **-21** |
| `find_symbol` unlinked function instruction bytes | 340 | 322 | -18 |
| Handwritten `ass.asm` image | 6,905 | 6,905 | — |
| Remaining gap to handwritten | 4,950 | **4,929** | -21 |

The layout effect accounts for the difference between the local 18 B and linked 21 B results. The 21-byte improvement is **not** a meaningful answer to the remaining 4.9 KiB gap; it specifically falsifies the hypothesis that this simple certified two-pointer loop plan will deliver the desired multi-kilobyte reduction.

For an isolated `find_symbol` function call in the experimental linked 6502 interpreter:

| Case | Baseline instructions executed | Region plan | Reduction |
|---|---:|---:|---:|
| 490 three-character symbols, no match | 82,816 | 58,806 | 29.0% |
| 18 sixty-four-character symbols, last matches | 36,042 | 13,200 | 63.4% |

So it **is a good loop machine algorithm** and a strong runtime improvement, but static instructions are shared by all iterations. A faster long-running loop does not imply a comparable static code-size reduction.

## Checks completed

- Strict physical assembly, all 44 functions: **44/44** pass.
- Byte-for-byte comparison with the exact original assembler: **45/45 segments** including runtime.
- Full linked-machine interpreter against independently compiled `ass.c`: **29/29** assembly inputs pass, all returned statuses and output bytes compared. The 29 were executed in parallel with private oracle files to avoid shared-test-path races.
- Direct isolated function execution: **28** cases covering no match, early/late match, 0–490 symbols, page-crossing input pointer, 16-bit IDs beyond 255 and names up to 64 bytes.
- Five explicit plan rejections: modified offset, call inside the loop, mutable bound, pointer rebinding, nonunit step. **5/5** pass.
- All tests use the same research machine interpreter with simulated KERNAL I/O. Native hardware runtime behaviour is not the subject of this experiment.

## Architectural inference

This is a discriminating result, not an optimisation milestone. The loop-region representation permits correct long-lived Y and ZP pointers and can dramatically reduce dynamic instructions. But **it cannot explain most of the static size gap** in the current program: many substantial functions (`resolve_fixups_for_symbol`, `allocate_symbol`, `append_fixup`) span 16-bit induction, calls, multiple arrays, and memory effects; the compiler's generic value transport outside those regions remains expensive.

In the linked assembler the audit counts roughly **1,032 static-local/parameter memory operand instructions, 328 static call-argument-slot accesses, 367 temporary-slot accesses, and 458 address/index-pointer-slot accesses** among about **4,710 total function/runtime machine instructions** (categories disjoint in that first-pass opcode classification, but not claims of removable code). The remaining gap therefore demands an interprocedural or whole-function *location/algorithm choice*, not increasingly specialised two-pointer cache proofs. The previous counterfactual zero-page experiment already quantified that physical homes alone do not explain the final ~3.4 KiB gap even with unrealistic availability.

**Recommendation:** do not continue this narrow dual-pointer-rule family merely to collect tens of static bytes. The next useful design comparison should replace the static argument/value transport model *across call boundaries*, or compare genuinely distinct source algorithms and storage invariants, then remeasure the entire image. The typed tape can remain as a semantic input without obligating any particular machine-location strategy.

## Reproduce

From this directory, set `PYTHONPATH=full_corpus:.` and execute `python link_model.py && python build_image.py && python layout_pass.py && python strict_link_check.py && python byte_match.py`, then `python test_region.py`, `python region_refusals.py`, `python parallel_cases.py`. The run's generated `compact_image.prg` has 11,836 bytes including the two-byte load address. The original research baseline is retained unchanged separately and `REGION_DIFF.patch` shows the backend modification.
