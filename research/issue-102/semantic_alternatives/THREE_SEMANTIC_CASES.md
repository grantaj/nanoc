# Issue #102 — three semantic-to-6502 alternative strategies

**30 October 2026 — controlled machine-code inspection and source-level controls.** This is an investigation of **why the useful 6502 machine algorithms are absent from the search space**, not another production optimizer or arbitrary size target. The reference is the exact archived **8,945-byte** research output compiled from `full_corpus/exact_source/ass.c`, compared against the **6,905-byte** existing native assembler.

Sources inspected: the full 44-function C assembler and its generated `compact_image.asm`, the per-function typed tapes built by `full_corpus/tape_frontend.py`, and existing native `ass/instruction.asm`, `ass/symbols.asm`, `ass/representation.asm` implementations. The recovered archive is preserved byte-for-byte on the parent branch, SHA-256 `3466aa5cf0335340c04e0a87260a572ed7961602475c5aae86a338959597ea30`.

## 1. Guarded suffix accesses in `assemble_instruction` — local relational range

Example from exact C: `argument[argument_length - k]`, with `k` in 1, 2 or 3. The tape emits `load(argument_length):u8`, `const(k):s16`, `subtract:s16`, `read(argument, idx):u8`. The original backend chooses general 16-bit sign-extension and address construction even on guarded paths. The appropriate alternative is a proven byte Y-offset and `LDA (ptr),Y`. The proof is **path-sensitive**: `0 <= argument_length-k <= 255`; it is false for unguarded paths, and the C arithmetic must keep its signed 16-bit semantics.

This is the one case that **was already repaired experimentally** by the separate CFG range pass in [`issue-102-cfg-index-range`](https://github.com/grantaj/nanoc/tree/issue-102-cfg-index-range). It removed **351 B of original unoutlined function code** over `assemble_instruction`, `open_include` and `assemble_string`, but only **47 B** from the complete final image (**8,945 → 8,898 B**), because outlining had already shared the poor 16-bit arithmetic/address sequences. Those numbers are *not* from the source variants below, and must not be summed into a promised combined reduction.

**Missing transformation:** path-sensitive range analysis at the *indexed consumer*, not a different tree-search method.

## 2. `find_symbol` — control-flow equivalence plus an alternative data-structure layout

Actual C scans up to 896 symbols using `symbol_scope[i]`, `symbol_name_length[i]`, `symbol_name_offset[i]` and inner `symbol_name_bytes[offset+j] != name[j]`. A matched native algorithm in `ass/symbols.asm:findSymbolEntry` walks inline-name records via persistent pointer, uses Y for fields and input-name position, and exits its name comparison on the first mismatching byte.

Original C instead sets `same=0` on mismatch but continues scanning the remaining characters, and only tests `same` after the loop. Two controlled, semantically equivalent source alternatives (the **unchanged backend**, not a new recognizer) were run:

| Source control | `find_symbol` pre-outline | Full pre-outline image | Final linked image |
| --- | ---: | ---: | ---: |
| Original | **307 B** | 9,936 B | **8,945 B** |
| Add `break` after `same=0` | 310 B | 9,942 B | 8,948 B |
| Remove `same`; break immediately and use `j == length` | **298 B** | 9,932 B | **8,941 B** |

The third form makes a better *C program* but still saves only 4 B in the final image. It is a valid semantic graph rewrite, not a register-allocation change: after mismatch, subsequent pure, nonvolatile character loads cannot change the final boolean result, so one can exit early. For length zero, `j == length` also preserves a successful empty comparison.

The *larger* machine difference remains: **three or more parallel arrays with a 16-bit index versus a single packed-record cursor**. A register search cannot secretly change C memory layout in general: callers use numeric symbol IDs, other routines read the original arrays, and the program's representation is observable through aliases. Earlier source A/B packed-record rewrite also **grew** the image by 409 B for symbols alone; it retained stable numeric handles at interfaces and is not proof that efficient native-style pointer code is impossible. To offer alternative pointer plans without changing source semantics, one must maintain a relational invariant for each corresponding array address or deliberately transform an entire source abstraction, with verified caller effects.

**Missing transformations:** loop/control simplification for sticky mismatch, *and separately* a costed, legal multi-base cursor/record representation across multiple functions. These cannot be encoded as mere different A/X/Y contents of the same emitted operations.

## 3. `stage_byte` — a cross-function representation choice

Exact C:

```c
if (ass_image_length >= 11264) return ASSEMBLE_WORK_FULL;
ass_image[ass_image_length] = value & 255;
ass_image_length = ass_image_length + 1;
return ASSEMBLE_OK;
```

Its 4-block typed tape contains an indexed `store_index(ass_image, ass_image_length, value)` and an independent 16-bit increment of the length. Original emitted 6502 computes `ass_image+ass_image_length` through `ADC` into `__ap`, stores through `(__ap),Y`, and separately increments length.

Native `ass/representation.asm:stageByte` instead carries a persistent `stagingPtr`, checks it against its fixup limit, writes to it and increments the pointer, while also maintaining a separate assembly target PC. The two programs have **different workspace semantics**: the C version's fixed capacity is 11264 bytes and native checks its dynamic fixup boundary. Do not conflate these algorithms.

To test the simplest pointer alternative without invalidating callers, the research source added a persistent `char *ass_image_cursor`, initialized to `ass_image` when assembly resets. `stage_byte` writes via `ass_image_cursor[0]`, increments it and **still increments `ass_image_length`**. No change to the backend. All original length consumers remain correct: stage/fixup offsets, branch PC calculation, output extraction, resetting. Result:

| Source control | `stage_byte` pre-outline | `reset_assembler` pre-outline | Full pre-outline image | Final linked image |
| --- | ---: | ---: | ---: | ---: |
| Original | **76 B** | **78 B** | 9,936 B | **8,945 B** |
| Add cursor, retain length | **96 B** | **88 B** | 9,966 B | **8,975 B** |

**The +30 B regression is expected:** this adds a second independently updated representation of the same position. A real global alternative would choose either a maintained cursor or a maintained scalar length, plus a precise policy for *rematerializing* the other form at its external consumers. This requires the invariant `cursor = &ass_image[0] + ass_image_length` to hold across **all calls, resets, stores, joins, and pointer-affecting aliases**, with a global cost accounting for each representation's observers. The source has 11 textual occurrences of `ass_image_length`, including the declaration; it is not solely private to `stage_byte`.

**Missing transformation:** interprocedural relational value representation and selective materialization. A byte-level shortest path over `STA/LDA` cannot even express this choice.

## Independently executed checks

All **four** generated versions above (`control`, `early_break_keep_flag`, `early_break_use_index`, `persistent_cursor_plus_count`) were built and linked with the **same** recovered research backend, unchanged register/zero-page policy, layout and outliner, using `PYTHONHASHSEED=0`. Each passed:

- **44/44** strict 6502 function assembly validations;
- **45/45** byte-for-byte independent encoded segment comparisons;
- **29/29** complete assembled-source programs in the 6502 interpreter against the corresponding host C oracle;
- **9,120/9,120** independent wide comparison executions.

A separate *original host C vs modified host C* test ran the same 29 program sources through all four shared libraries and checked **identical status codes and every output byte**, so success is not an artifact of each variant being compared only to itself. This is still bounded research-oracle coverage, not a formal all-input proof or C64/VICE execution.

To reproduce: from this report's directory, run:

```sh
python reproduce_case_variants.py --variant all --output /tmp/nanoc102-alternatives
```

The script reads the parent `nanoc_remaining_gap_codegen_experiment.zip`, applies source changes, reruns the complete instrumented linker/oracle suite for each variant and compares the variants directly against original host C. It makes **no changes** to the archived research backend or production `nanoc1.c`.

## What the examples actually establish

These are three distinct semantic relations that current lowerings discard or never represent:

1. **Range:** `0 <= length-k <= 255` on particular CFG paths.
2. **Loop correspondence:** `array_address = base + index * stride`; for multiple arrays, there are multiple coordinated bases and a common induction index; early-exit control-flow equivalence is a *different* graph transformation.
3. **Cross-call recurrence:** `cursor = base+length`, with updates preserving the equality and materializations needed by external observers.

One generic 6502 `MachineState(A,X,Y,C,Z,ptr0,ptr1)` is insufficient by itself. A meaningful alternative-state search must carry **relational invariants about program variables**, specify both *realisations* of each computation and prove that each boundary (including other functions) preserves C observable results. Ordinary tree covering can select expression instructions, but it cannot produce these loop-/program-level alternatives without prior rewriting/analysis.

A **concrete architecture discriminant** for the next experiment would be a small *semantic relation graph* with (1) pure expressions/address roots, (2) recurrence edges and path guards, and (3) clobber/call-observer edges. Offer alternative plans for **the same full live range** and compare their *whole linked sizes* using the existing backend and its exact tests. If a proposed plan still carries all original state alongside its new state, it is *not* a valid test of representation elimination. If no safe representation can satisfy all observers, report that as a reason for nonselection, not an optimisation failure.

**No new 1-KiB code saving is established** by the three cases. The new measured source variants are `8,948`, `8,941`, and `8,975` B versus `8,945` B. These findings explain why small codegen searches are exhausted without proving that the entire **2,040 B** difference to the handwritten assembler is avoidable.
