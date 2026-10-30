# #102 — independent 6502 machine-strategy selector experiment

**Date:** 2026-10-30. **Scope:** research only. Does not modify `nanoc1.c` or production 6502 compiler. Uses the exact same 44-function C source and typed tape as the recovered #102 generator. No arbitrary target image size.

## Hypothesis tested

Can a second backend built around explicit 6502 state and competing machine *recipes*, rather than another subclass in the 21-layer inherited emitter, generate substantially more economical 6502?

The prototype `full_corpus/machine_strategy.py` directly subclasses only the deliberately simple semantic `Backend`; it **does not** subclass `NativeCompareBackend` or any of the 20 intermediate optimisation layers. A `MachineState` tracks A, X, Y, flags, and two pointers. A pre-emission planner proves safe direct consumption of loaded values, chooses a single-consumer producer/store fusion, selects direct-Y indexed access, and emits byte comparisons directly. A separate **whole-function cursor recipe** recognises a *call-free canonical sentinel scan with a signed 16-bit induction index, stable bound, one byte array and early exit* and emits a pointer/end-pointer traversal instead of recalculating `array[index]` each iteration. The canonical CFG recogniser does not check function names. Unrecognised operations fall back to the simple backend's conservative semantic lowering; this remains a serious weakness.

The `link_model.py` A/B driver independently lowers each of the same functions through the original backend and through the new backend, applies the **same scratch allocator**, compares physical instruction bytes, and selects the smaller *complete function* before existing whole-image processing. The old backend is an independent fallback option, **not a superclass** of the new one. `MACHINE_STRATEGY=choose` enables this research-only whole-function cost selection; `MACHINE_STRATEGY=force:upper_char` tests forced integration; `MACHINE_STRATEGY=only` attempts all functions with the new backend.

## Results — complete full-image measurement

| Variant | Loaded bytes | Notes |
|---|---:|---|
| Frozen recovered original backend | **8,945** | Baseline; 44 functions |
| New machine-strategy candidate selector | **8,917** | 44/44 strict functions, 45/45 encoded segments, 29/29 end-to-end programmes, 9,120/9,120 word comparison cases |
| Pre-outlining, original | **9,936** | Physical linked image with all other optimization stages retained |
| Pre-outlining, new selector | **9,908** | New improvements overlap with existing layout/flow simplification and outlining |
| Force only the new `upper_char` routine | **8,953** | Full 29-program suite passed but **8 bytes larger** than baseline |
| Handwritten assembler | **6,905** | Architectural reference, not an arbitrary success threshold |

**Selected new machine recipes:** only `all_symbols_defined` and `all_fixups_resolved`, each **97 → 69 bytes before shared outlining**, 56 bytes of function-code reduction in total, 28 bytes of final linked-image improvement. The two functions were found using one general source/CFG shape, not their names.

**Validation of the new recipes:** 76 additional standalone interpreted 6502 executions of the wide cursor scanner (including negative/zero bounds, a pointer deliberately positioned near a page edge, 255/256/511/640/896 byte cases, first/middle/last early exit), plus 256/256 unsigned-character cases for the independent `upper_char` generator. Full 29-program tests exercise the two selected cursor functions in the linked assembler. These are research-interpreter tests, not VICE or physical C64 KERNAL tests.

## Crucial negative result — the new architecture is not yet competitive

The new independent backend is much *larger* for almost every function. **All 44 candidate generators were evaluated; only two whole-function implementations beat the mature baseline.** Summed pre-outlining individual function instruction bytes: **17,272** for the independent emitter (including the two scanner replacements) versus **10,969** for the recovered backend, before shared physical linking and outlining. `find_mnemonic` is 354 vs 230 function bytes; `parse_atom` is around 1.5 KB vs 832. This is not a new production-ready compiler.

The independent generator's **all-functions mode cannot yet build a legal full image**: its scratch allocator requires 9 bytes (rather than the currently provided 8) in `stage_unresolved_instruction`, `stage_data_value`, `assemble_direct_value`, and `assemble_mode_value`. More important, the new emitter retains conservative per-op materialisation for unrecognised regions. Declaring a `MachineState` and choosing obvious recipes does not by itself reproduce the mature backend's existing width, comparison, call/return, alias, and register placement expertise.

The cursor planner is strictly limited: it knows only call-free, single-array, single-induction scans with one early exit. It does **not** handle the difficult `find_symbol`, `resolve_fixups_for_symbol` or `allocate_symbol` loops. Those have multiple arrays, calls, indirect stores or complex joins. Therefore the experiment has **not solved** the underlying compiler architecture or recovered the remaining kilobytes.

## Engineering conclusion

The positive result demonstrates that a **region recipe selected before instruction emission** can work, and the full-image A/B harness is useful. The negative result is more important: replacing the layered emitter with a simple state record and a sparse recipe catalogue *undoes much of the existing optimisation progress*. A viable replacement architecture must have a **complete, coherent recipe set and a real region-boundary state contract** before it can compete, particularly for multiple-array and call-rich loops. Merely accumulating one more recogniser around this prototype would recreate the previous deadlock.

The next proper comparison is *whole-region machine strategies with explicit entry/exit state* versus the existing backend's complete-region output, not additional per-op peepholes or arbitrary byte targets. Reuse mature machine idioms as **recipes in one orchestrator**, rather than inheriting its chain. Do not promote this prototype to production based on the 28-byte decrease.

## Reproduction

From the recovered ZIP workspace, with these source changes applied:

```sh
PYTHONHASHSEED=0 sh reproduce_native_compare.sh   # recovered baseline, 8,945 B
PYTHONHASHSEED=0 sh reproduce_machine_strategy.sh  # new selector, 8,917 B
```

`reproduce_machine_strategy.sh` asserts the physical 8,917-byte result, 44/44 strict functions, 45/45 exact binary segments, 29/29 end-to-end tests, 76 cursor and 256 char machine tests and exactly two selected complete-function recipes. `MACHINE_STRATEGY=only` is *not* a reproducible full executable yet. `machine_strategy_choices.json` records every candidate, its old/new bytes, the chosen implementation and counted recipes.
