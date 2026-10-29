# #102 continuing size research: word in-place update test (2026-10-29)

This is **not a production compiler integration**. All changes are confined to a research backend and activated only with `NATIVE_INPLACE=1`. The comparison target remains the **6,905-byte handwritten assembler**, not the 16-KiB feasibility window.

| Whole-image generator | Physically linked loaded bytes | Above handwritten |
| --- | ---: | ---: |
| Recovered, independently reproduced baseline | 8,945 | 2,040 |
| Word-only in-place updates, tested | **8,823** | **1,918** |

General operation selection: if `int`/`unsigned` scalar `x` has a same-block, single-use, effect-free `x = x + 1` or `x = x - 1`, select direct 6502 memory update. Increment is `INC low; BNE done; INC high`; decrement is `LDA low; BNE skip; DEC high; DEC low`. This preserves 16-bit modulo-65536 wraparound. Reject byte destinations and any already Y-carried induction latch or dual-pointer machine plan. This is **not** a function-specific selector.

Reproduction: run `sh reproduce_word_inplace.sh` from `experiment/`; check `FINAL 8823 bytes 44 functions 45 segments 29 cases`. Then run `PYTHONPATH=$PWD/full_corpus:$PWD python test_inplace_words.py` to check 4,034 independent 6502 machine arithmetic cases; `stage_word_edge_cases.log` reports 9,120 word-comparison cases. The 29 full linked machine tests match exact C output bytes and status in the research interpreter, not VICE or native KERNAL.

**Negative control:** enabling this simple in-place rewrite for `char` increment/decrement initially produced 8,829 bytes but timed out in end-to-end assembly tests; even after excluding proven Y-loop/dual-pointer latch blocks a byte-only build still timed out. Byte-only rewriting is therefore rejected, not reported as a size gain. This is evidence that a consumer-directed in-place update cannot be layered over existing machine trajectories without explicit register/state reconciliation.

**Interpretation:** sound word-only gain is 122 B (1.36% from 8,945), not the sought multi-KiB mechanism. Do not turn this into a sequence of 100-byte optimisations. Still unaccounted for: 1,918 B against handwritten, including source-level symbol/fixup representation differences, native pointer traversal, and algorithmic decisions before address/index emission. The 16-byte `$30..$3f` ZP allocation is still hypothetical and no native C64 memory/IRQ check was performed.
