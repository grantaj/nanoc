# Issue #102 — cost-based 6502 search experiment (2026-10-30)

## Question

Do standard combinatorial optimisation techniques—shortest-path/dynamic-programming machine-state selection or bounded beam search—resolve the remaining gross 6502 code-size waste that local instruction substitutions have failed to remove?

This experiment **tests two constrained, real parts of that question**. It is **not** a full BURS/IBURG tree-covering selector or a whole-CFG register/pointer allocation search; claiming otherwise would repeat the project's earlier mistake of overstating local optimisation experiments.

- Baseline: recovered exact 44-function `ass.c` research backend, **8,945 loaded bytes**, which was verified against the original `CANDIDATE.PRG` byte-for-byte with `PYTHONHASHSEED=0`.
- Native handwritten assembler comparison: **6,905 loaded bytes**. This reference implements some different C/data algorithms; do not treat the entire difference as compiler waste.
- Production `nanoc1.c` unchanged. No arbitrary image-size target.

## Experiment 1 — beam search over basic-block flow/layout

`block_order_search.py` models each function as linked basic blocks, with state `(visited blocks, final block)` and cost from required JMPs and fallthrough. It retains a beam of up to 48 candidate paths rather than choosing the next source block greedily. Branch inversion is permitted only with explicit predicates, and block reordering is rejected unless a conservative short-branch distance certificate passes.

The search inspects **approximately 280,000 states** across all 44 function graphs. Under conservative branch reachability, 30 function layouts save an estimated 318 pre-layout instruction bytes, but only **two** functions are genuinely reordered. Most improvements are already achieved by the existing `layout_pass.py` and `outline_8.py`.

**Valid clean build:** **9,930 bytes before outlining and 8,945 bytes after outlining**, unchanged from baseline after outlining. The full 44/45/29/9120 tests pass. It is a useful negative result: this stage of global control-flow *layout* search isn't the missing large mechanism.

**Important failed intermediate run:** A preliminary candidate estimated ~867 bytes of fallthrough savings but generated out-of-range conditional branches. A later incorrectly accumulated build measured 8,888 bytes, but **failed complete program execution and was not reproducible as a clean image**. Both numbers are rejected, not research results. The search now refuses these candidates. Only clean-build measurements count.

## Experiment 2 — exact DP over machine-state choices

`copy_state_search.py` implements actual shortest-path dynamic programming for independent straight-line byte-copy regions of the generated C code. Each state is `(writes already performed, identity currently held in A)`. Each transition chooses the next byte-copy operation, optionally emits `LDA source`, then `STA destination`, and pays the **actual opcode byte costs** (2 B zero-page/immediate; 3 B absolute). It retains the best sequence by exact dynamic programming, not a greedy local rule. There is no function-name recognition.

To be semantically sound, it explicitly requires:

1. All destinations are distinct physical machine addresses and cannot alias any source (including shared call ABI slots and ZP scratch).
2. No unknown/indirect or I/O stores, control transfers or calls inside a region.
3. The same final A and N/Z flag values as the original sequence; C/V, X/Y and all other memory values are unchanged.
4. Only legal opcode sequences and known mapped memory addresses. All other code is left untouched.

The search finds 140 eligible runs. It explores **3,452 DP states** on the actual compiler corpus and improves only **two**: a combined **5 bytes saved before outlining**. The full-image result is **8,941 loaded bytes**, just **4 bytes below baseline**. The outline/layout phases erase the fifth byte. This is NOT evidence of a substantial reduction.

Independent tests: **900 differential machine-state executions** of randomized legal runs, plus brute-force optimality checks for smaller runs and explicit alias-refusal controls. These compare final memory, A, Z, N, C and V. Full 6502 generated image checks remain **44/44 strict machine function encodings, 45/45 segment byte checks, 29/29 complete assembly programs, and 9,120/9,120 typed word comparisons**. The 6502 interpreter is still a research interpreter, not VICE.

## Whole-image comparison

| Variant | Pre-outlining image | Outlined linked image | Full program checks |
| --- | ---: | ---: | --- |
| Recovered baseline | **9,936 B** | **8,945 B** | **29/29** |
| Beam-search basic-block ordering | **9,930 B** | **8,945 B** | **29/29** |
| Exact machine-state copy DP | **9,932 B** | **8,941 B** | **29/29** |

The original control's 9,936 pre-outlining and 8,945 final image are from the clean baseline. Use `reproduce_search.py` to regenerate all three with independent strict/link/case tests and per-variant SHA-256 hashes.

## Interpretation: what was and was not tested

This is a real test of standard **search algorithms**, not another guessed instruction substitution. But it searches *after* the existing emitter has committed to a specific sequence of instructions and memory homes. Many costly alternatives—e.g. keeping a 16-bit pointer through the loop instead of representing a scalar index, or choosing byte compare/flags instead of materialising a 16-bit temporary—are simply **not in its search space**. A shortest-path algorithm cannot discover moves it was never offered.

The result therefore **does not falsify** the user's idea of minimisation search. It falsifies the narrower idea that better scheduling and layout of already-selected instructions will expose large remaining savings. It reinforces the need to search **over multiple semantically equivalent 6502 recipes before emission**, with machine-state transitions and loop contracts explicitly represented, preserving the mature backend's proven recipes. Such a planner must account for non-additive final outliner cost rather than merely minimising local raw instruction bytes.

## Reproduction

From the recovered `nanoc_machine_value_home_planner/` workspace, put the three research Python files alongside `link_model.py`, then:

```sh
PYTHONHASHSEED=0 python reproduce_search.py copy
PYTHONHASHSEED=0 python reproduce_search.py layout
PYTHONHASHSEED=0 python reproduce_search.py control
```

Each invocation rebuilds its specified search variant from the exact 44-function C source, runs all physical tests for it, and asserts the physically linked byte total. Running without arguments attempts all three sequentially and may exceed a single tool execution window. `copy_state_search.py` and `block_order_search.py` also work separately when invoked after `link_model.py`, `arg_a_abi.py`, and `machine_flow.py` and before the existing register/home and linker stages. Do not run the outliner twice against a stale `boot.asm`—each build must start with fresh `link_model.py`.
