# #102: CFG-proven indexed-address lowering — measured experiment

**30 October 2026.** This is a *research backend experiment*, not production `nanoc1.c`. It deliberately preserves the exact `bootstrap/ass.c` algorithm and the 6,905-byte handwritten assembler reference. There is no arbitrary final-image target.

## Mechanism repaired

The existing indexed emitter already has correct `LDA array,Y` and `LDA (zp),Y` paths for byte indexes, but it decides from the tape **type**, not the index **value range on that control-flow path**. Consequently guarded `argument[argument_length - k]` loads go through a full signed 16-bit address calculation merely because C promotes subtraction to `int`.

The added `IndexRangeBackend` performs forward **may-range** interval propagation over the existing operation CFG. It refines intervals on conditional successors, joins facts conservatively, widens loop changes to unknown rather than assuming convergence, and discards global-variable facts after calls or indirect writes. It retains the same C integer semantics; modular overflow invalidates a proof. Only when the index is **provably within 0–255 at the actual indexed consumer** and the element is a byte does it activate the backend's existing direct-Y emission. If a proved 16-bit `+/-` index result has exactly one use (that indexed access), high-byte arithmetic is no longer demanded.

The extension is generic: it does not inspect function names. It does **not** narrow signed negative indexes, genuinely wide table indexes, word-element indexing, or any index whose control-flow proof is incomplete.

Files:

- `experiment/full_corpus/range_index.py` — CFG range proof and index demand.
- `experiment/full_corpus/backend4.py` and `experiment/full_corpus/backend.py` — respect the certified direct-Y index at byte read/write consumers.
- `experiment/link_model.py` — optional `RANGE_INDEX=1` research backend selector.
- `experiment/test_range_index.py` — direct 6502 execution tests and three negative eligibility controls.
- `experiment/reproduce_range_index.sh` — clean full-image reproduction with deterministic Python hash seed.

The original `reproduce_native_compare.sh` remains unmodified and **still reproduces 8,945 B** with the new files present and `RANGE_INDEX` unset.

## Actual full-image results

| Measurement | Original research backend | CFG-range backend |
| --- | ---: | ---: |
| Final physically linked, outlined image | **8,945 B** | **8,898 B** |
| Delta | — | **−47 B** |
| Strict assembled functions | 44/44 | **44/44** |
| Exact encoded segments | 45/45 | **45/45** |
| End-to-end C-oracle programs | 29/29 | **29/29** |
| Native typed compare edge cases | 9,120/9,120 | **9,120/9,120** |
| Additional 6502 signed/unsigned/page-crossing index executions | — | **20/20** |
| Additional unsafe-eligibility controls | — | **3/3** |

**Crucial observation:** Function-body instruction bytes **before existing repeat-sequence outlining** decrease by **351 B** in three functions: `assemble_instruction` −243 B; `open_include` −81 B; `assemble_string` −27 B. The physically outlined/linker-sized image improves by **only 47 B**. Outlining has already factored most of the duplicated fallback address sequence; **the 351 B must not be presented as a final-image saving**.

The test includes direct 6502 reading with base address `$30ff` (page crossings), lengths 0/1/2/3/127/128/254/255, wide indexes 256/257/511/767, and negative offsets `-1` and `-2`. No unsafe Y truncation was selected.

## Interpretation and remaining blocker

This **fixes and confirms** the first diagnosed problem: lost path-dependent range information. It does **not** solve the second: a *persistent 16-bit cursor or a planned page+Y traversal across actual call-rich, multi-array loops*. The existing `LoopBackend` still refuses most such regions, and the `AddressPlanBackend` loses its address identity at labels and calls. The tests do not certify C64 KERNAL/IRQ ownership of the research zero page and are not VICE tests.

The difference of **2,040 B** to the handwritten assembler at the baseline is **not** addressed by another small direct-Y pattern. The low final-image return from the otherwise strong 351-B raw improvement makes repeated local index-pattern rewrites an unlikely route to the remaining large reduction. A separate, broadly applicable *whole-region pointer/cursor representation with clobber and alias proofs*, and a separately controlled faithful stable-pointer C symbol/fixup algorithm, remain substantially different experiments.

**Keep this proof mechanism as correct research infrastructure, but do not promote it as a breakthrough or begin production integration.**
