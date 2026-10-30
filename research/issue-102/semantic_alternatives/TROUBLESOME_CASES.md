# #102: Three semantic-to-machine failures — inspected examples and controls

**2026-10-30. Research diagnosis, not a production compiler change.** Baseline: the recovered, byte-exact 44-function C assembler at **8,945 loaded bytes**; native handwritten assembler **6,905 bytes**. No arbitrary size target. Original ZIP and research backend remain untouched.

## Finding

The existing typed tape contains valid dependencies and operations, but **does not represent a choice of equivalent *physical representations*** or the equalities that would make those representations interchangeable. Searching its already-selected 6502 instructions cannot invent an alternative loop algorithm or eliminate a redundant representation. In other words, neither a fixed machine-state layout nor a conventional expression tree alone suffices. Candidate representations must encode *relations* between pointers, indexes, live memory and flags and their validity across control flow and calls.

This is supported by **three distinct actual C functions**, plus a related call-status example:

### 1. `assemble_instruction`: guarded suffix indexes

The original typed tape contains **70 blocks, 287 operations, 12 byte-indexed reads**. Nine of those subscript indexes are produced by *signed-16-bit subtraction* (for example `argument_length-1`, `-2`, `-3`), even though the C `argument_length` itself is byte-sized and the relevant accesses occur under guards on length.

- **Generic C scalar strategy:** compute signed 16-bit `length-k`, add it to the 16-bit argument pointer, then load the byte.
- **6502 addressing strategy:** prove `k <= length <= 255` on the predecessor path, load `Y=length-k`, then use `LDA (pointer),Y`. If useful, retain Y and pointer through adjacent consumers, subject to clobber effects.
- **What is missing:** path-sensitive range proofs and a consumer-visible `base + bounded-index` representation rather than a forced `s16` arithmetic result. The separately committed CFG range fix #102 already demonstrated **8,945→8,898 B** on the *complete assembler*. It eliminated 351 bytes of individual instructions pre-outline, but only 47 final bytes because the outliner was already sharing the fallback.
- **Conclusion:** this failure mode is real but no longer a plausible explanation for *all* remaining code-size waste.

### 2. `find_symbol` / `resolve_fixups_for_symbol`: related addresses and array traversal

In actual `find_symbol`, the tape has **22 blocks, 82 operations, 5 indexed reads**. Three separate byte/word-table reads use the same signed-16-bit `i` (`symbol_scope[i]`, `symbol_name_length[i]`, `symbol_name_offset[i]`), then the name comparison reads `symbol_name_bytes[offset+j]` and `name[j]`. Since the source's table contains **896 entries**, a general 8-bit Y index is insufficient. The handwritten assembler uses stable record pointers, but that is a *different C data structure*, not merely a choice of addressing instruction.

A particularly clean **same-source machine-alternative test** exists in the fixup subsystem: the recovered linked addresses of its three 16-bit fields are

```
fixup_stage  = $B594
fixup_symbol = $BA94
fixup_addend = $BF94
```

For any `0 <= i < 640`, the three addresses are `base + 2*i`. Because the bases have identical low bytes and successive high-byte offsets of `$05`, two possible 6502 fragments are:

- **Independent addresses:** scale `i` and add a separate full base three times; load a word at each address.
- **Shared affine relation:** calculate `fixup_stage + 2*i` once, read a word, add `$05` to the pointer **high byte only**, read the next word, repeat. The pointer's low byte remains correct and no loop-index truncation is needed.

[Executable fragment check](address_relation_probe.py) using the actual linked addresses: **57 instructions / 114 bytes → 39 instructions / 78 bytes**, with **1,920 independent 0–639 index/value trials per strategy**. The fragment preserves the three memory results; it does **not** prove that all three fields can be fetched together at the same point in the real C control flow. The result is *not* an extra 36-byte whole-image saving, because calls, alias effects and existing outlining must be accounted for.

**What is missing:** symbolic address equalities, alternative pointer state and physical layout awareness. The source-level C packed-record experiment already gave a **+447-B regression** for the full combined assembler, indicating that a source rewrite alone does not make this backend use the native cursor algorithm efficiently.

A separate negative C-source control inserts an early `break` after a failed character comparison in `find_symbol` (safe because the loop has no side effects and never sets `same` back to 1). The fully linked result was **8,948 B (+3)** rather than 8,945 B; **44/44, 45/45, 29/29** pass and host original/modified status+bytes match on **29/29** cases. This further illustrates that making the source more like a hand-written search loop is not sufficient.

### 3. `stage_byte`: one canonical program state or two redundant states?

Original C implementation:

```c
if (ass_image_length >= 11264) return ASSEMBLE_WORK_FULL;
ass_image[ass_image_length] = value;
ass_image_length = ass_image_length + 1;
return ASSEMBLE_OK;
```

The stage pointer in the handwritten assembler is advanced directly. We tested the corresponding semantic alternative **without changing the compiler**, introducing a global `char *ass_image_cursor`, initially set to `ass_image` in `reset_assembler`, then using `ass_image_cursor[0]=value` and incrementing the cursor alongside the length.

The correct invariant is

`ass_image_cursor = ass_image + ass_image_length`.

**Actual A/B result:** unchanged C **9,936 B pre-outline / 8,945 B after**; pointer-source variant **9,966 B pre-outline / 8,975 B after (+30 B)**. `stage_byte` increases **76→96** unoutlined instruction bytes; `reset_assembler` **78→88**. This is because the program now maintains *both* the cursor and the index. Merely adding a pointer is therefore an anti-optimisation. The real search would need to choose a **canonical state representation** and synthesize other views *only where required by consumers* across the 44 functions, or exploit a proved relationship to remove updates. Other functions reference `ass_image_length` to report offsets/fixups, so simply deleting it from `stage_byte` without a cross-function plan would miscompile.

**Validation:** built and physically linked the full research 6502 image independently, passing **44/44** strict function assembly, **45/45** exact encoded segments, **29/29** complete machine assembler cases and **9,120** constant-comparison tests. Original and modified **host C agree byte-for-byte** on all 29 source fixtures. The ZIP variant and output differ only as specified in [`cursor_source.patch`](cursor_source.patch). The combined-control reproduction script exceeded one runtime limit during its second build; each image was previously built and checked separately. A one-variant-at-a-time reproduction script is included.

### 4. Small contrast: `stage_resolved_instruction` call-result status

Its actual tape has **19 CFG blocks, 60 operations, three calls** to `stage_byte` and two stores to the C `status` variable. Returning a byte in A and branching directly can avoid materialising status, but this needs a callee return/flags contract; a generic JSR does not promise Z corresponds to its returned value. The separate #102 consumer-directed experiment found call-result forwarding **byte-neutral at 8,945 B** after outlining. Hence it is *not* the missing large-scale win.

## What search must actually choose

For each semantic region, generate **equivalent forms** rather than single final instructions:

1. `load(base, index)` versus `load(cursor)` with `cursor=base+stride*index` maintained through its loop backedge.
2. Independent `array_k + stride*i` addresses versus one affine anchor plus **known layout deltas**.
3. `buffer+length` recomputation versus a canonical persistent cursor, tracking readers and writers of the length across calls.
4. Materialised scalar or boolean result versus available A/flags under an explicit ABI and effects proof.

Each representation needs: semantic equivalence conditions, memory-version/alias guards, clobber effects, live-in/live-out requirements and a *costed transition* to/from other representations. Search must evaluate whole regions and joins with these requirements, rather than scheduling instructions emitted by the old backend. Linker layout may affect the cost of symbolic array-delta forms, so pre-layout optimality is not necessarily final-code optimality.

**Strong conclusion:** the failure is not that the 6502 has too few known recipes. The compiler lacks a general mechanism to choose and maintain *relational representations* of a computation. **Unproven claim:** that fixing this will recover 1 KB or all of the 2,040-B gap. These tests establish opportunity and obstacles, not that global saving.

## Reproduction

Start from the exact [recovered original ZIP](../nanoc_remaining_gap_codegen_experiment.zip) and use the scripts in this directory:

```sh
python inspect_tapes.py /path/to/nanoc_machine_value_home_planner
python address_relation_probe.py /path/to/nanoc_machine_value_home_planner
sh reproduce_source_variant.sh /path/to/nanoc_remaining_gap_codegen_experiment.zip baseline
sh reproduce_source_variant.sh /path/to/nanoc_remaining_gap_codegen_experiment.zip cursor
sh reproduce_source_variant.sh /path/to/nanoc_remaining_gap_codegen_experiment.zip early_exit
```

For a direct C-vs-C byte comparison, compile the host ".so" oracle in two separately extracted variants and run `python test_host_equivalence.py BASELINE_PATH VARIANT_PATH`. No production `nanoc1.c` modifications.
