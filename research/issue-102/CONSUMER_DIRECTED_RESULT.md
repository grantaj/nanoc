# #102 consumer-directed 6502 selection: tested negative experiment

**Date:** 2026-10-30. **Scope:** recovered *host-Python research generator* for the exact 44-function Phase-1 C assembler. No change to `nanoc1.c`, production semantics or source algorithm. Physical linked image, not a size extrapolation.

## Hypothesis

The generator treats C values as static storage objects too early, rather than selecting an efficient path from value producer to actual consumer. Try concrete new **semantic-tape instruction choices before emission**, not assembly-text peepholes:

1. For a byte-valued call used exactly once as a direct comparison/branch, retain its result in A across the consumer; don't store it in a private compiler value home.
2. For arithmetic immediately returned as a word, keep the high result in X and return with the low result in A (or return the byte directly in A). Don't materialise the full result into private memory and load it back.

Plans require structural use-count, same-block and intervening-effect checks; the existing full-CFG flow, register-home, scratch packing, machine outlining, physical encoder, and oracle tests are **unchanged**. The new selector does not recognise function names. It is available only when `CONSUMER_DIRECTED=1` and implemented in `full_corpus/consumer_directed.py` with `link_model.py` selection.

## Actual result and ablation

All experiments use `PYTHONHASHSEED=0`, the same 16-byte hypothetical ZP budget, the same exact C source and the same greedy machine outliner.

| Selection | Direct call-to-compare sites | Returned arithmetic sites | Bytes of raw per-function code avoided before outlining | Full encoded loaded bytes | Difference versus original |
| --- | ---: | ---: | ---: | ---: | ---: |
| Baseline recovered backend | 0 | 0 | — | **8,945** | — |
| Call-result selection only | **11** | 0 | **22** | **8,945** | **0** |
| Arithmetic-return selection only | 0 | **3** | **9** | **8,946** | **+1** |
| Both selections | **11** | **3** | **31** | **8,946** | **+1** |

The pre-outlining code-size delta comes from backend per-function `instruction_bytes` counters. **It is not an additional linked-image saving.** In the combined trial, the outlining stage selects 35 helpers instead of 36 and saves 951 nominal bytes instead of 961. The changed machine sequences disrupt some shared-code opportunities; the final **correct** full image is one byte larger, despite fewer local instructions. This is precisely why post-outline physical measurements must control the result.

The baseline figure is from a full fresh `reproduce_native_compare.sh` run on the recovered archive. The combined variant was run through the full 44-function, 45-segment, 29-program and 9,120 typed-compare oracles. The call-only variant passed the same complete suite. The arithmetic-return-only variant also passed the full 29-program suite after a separately rerun `parallel_cases.py` (the initial all-in-one invocation was interrupted during that phase and is not counted as a pass).

## How to reproduce on this branch

```sh
# From research/issue-102/experiment/
sh reproduce_native_compare.sh
# Prints FINAL 8945 ...; baseline unchanged.
sh reproduce_consumer_directed.sh
# Prints FINAL 8946 ...; both plans enabled.
CONSUMER_CALL=1 CONSUMER_RETURN=0 sh reproduce_consumer_directed.sh
# Prints FINAL 8945 ...; call-result plan only.
CONSUMER_CALL=0 CONSUMER_RETURN=1 sh reproduce_consumer_directed.sh
# Prints FINAL 8946 ...; return plan only.
```

Each full script recompiles the C oracle, runs code generation, allocates ABI/scratch/register homes, outlines, physically links, checks all 44 functions / 45 encoded segments and runs 29 end-to-end oracle comparisons and 9,120 comparison executions. It enforces *correctness*, rather than hardcoding a desired image size.

## What this **does** and **does not** establish

- **Positive:** An independent, generic producer-to-consumer planner can be inserted at typed-tape lowering, with sound single-use and effect checks. The 11 direct call-to-comparison and three direct arithmetic-return paths are exercised and pass current oracles.
- **Negative, and more important:** This simple extension is **not** the missing kilobyte-scale reduction. The recovered backend **already** contains consumer-aware `PlacementMixin`, `CallArgumentMixin`, `ByteDemandBackend`, `WidthDemandBackend`, read-to-CMP forwarding, A-residency, and CFG-wide machine-flow deduplication. Another layer of result store elimination has near-zero incremental value.
- The full 2,040-byte difference from the **6,905-byte handwritten** assembler is not established as compiler-generated inefficiency. C code uses different symbol/fixup data structures and conventional status return values.
- The 16-byte research ZP pool is not proven KERNAL/IRQ safe; interpreter tests are not VICE. No new C64-native compatibility claim is made.

**Decision:** Keep this experiment as a reproducible **negative architectural control**, not merge it into the native compiler or the research baseline, and **do not** proceed by adding more small producer-to-consumer fusions. The next substantial experiment needs a new *whole-region machine algorithm* (loop carried cursors / native-mode record traversal, or a faithful C source-data-model control) with physical whole-image measurement, not another local value-home substitution.
