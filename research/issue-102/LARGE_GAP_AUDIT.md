# #102 large-gap machine-code audit — 2026-10-30

## Objective and scope

This audit starts from the **physically linked 8,945-B research generator** (complete exact `bootstrap/ass.c`) and the **6,905-B handwritten native assembler**. It intentionally does **not** treat the 16-KiB execution region as a code-quality target. A separate tested word-RMW experiment on this branch reaches **8,823 B**, but that 122-B improvement is **not** the objective of this audit.

The objective is to find whole-machine algorithm and/or source-representation differences worth **at least ~1,000 B across the complete generated assembler**, without assuming every difference from handwritten code is compiler waste. Research backend only; no production source change or native/V​ICE validation in this audit.

## Exact generated-code census

Source: the recovered archive's `compact_image.asm`, its `full_corpus/whole_corpus/*.c` typed tapes and the **actual** `NativeCompareBackend` address construction method. Counts below deliberately exclude the backend's first-pass CFG/A-analysis probe.

| Measurement | Observation |
| --- | ---: |
| Complete physically loaded image | **8,945 B** |
| Compiled function-body instruction bytes | **7,104 B** |
| Function-body machine instructions | **3,264** |
| `LDA` / `STA` in function bodies | **1,002 / 646** |
| Function-body `LDA` from static locals/params | **495** |
| Function-body `STA` to static locals/params | **193** |
| `STA` to static argument slots | **168** |
| Semantic indexed reads / indexed writes | **97 / 30** |
| Full effective-address constructions actually emitted by final NativeCompareBackend | **61** |
| Of those, named arrays / computed pointers | **47 / 14** |
| Instructions emitted **inside** those address constructions before outlining | **616** |
| Bytes emitted **inside** those constructions **before** outlining (estimated from 6502 addressing widths) | **~1,292 B** |

**Accounting warning:** `~1,292 B` is **pre-outlining** address-construction cost. Exact repeated-sequence outlining has already replaced many original sequences with JSR to shared helpers, saving ~1 KB overall. Therefore this figure is not an additive or independently recoverable 1,292-byte opportunity in the 8,945-byte final image. Likewise the load/store and address categories overlap; do not sum their raw byte counts. A `STA` may be necessary to preserve a C-visible value or an alias boundary.

## Two obvious 6502 strategy failures seen in the actual machine listing

### A. `assemble_instruction`: wide arithmetic for byte-bounded character indexing

The source repeatedly reads `argument[argument_length - 1]`, `-2`, `-3`, `-4`, in branches guarded by minimum `argument_length`. The emitted shape is:

```asm
    lda __L_assemble_instruction_argument_length
    sec
    sbc #$01
    jsr __outline_02    ; create full signed 16-bit offset
    jsr __outline_01    ; generic pointer + 16-bit offset + read
```

`__outline_01` alone contains a **27-byte** 16-bit indirect-address algorithm and is used **14 times** across the program. The prior outline pass saved **308 B nominal** by sharing it. But a competent target-specific *producer-and-consumer* choice is to keep the argument pointer in ZP, use `Y = length - k` for the guarded nonnegative case and then read with `LDA (ptr),Y`. That directly prevents creation of the expensive address expression. Source-level C `char` promotion and subtraction require proving the guard and index range at the use, not just assuming all signed offsets fit in Y.

### B. `allocate_symbol`: parallel arrays reconstruct the same conceptual record

The generated symbol-allocation routine separately builds effective addresses for `symbol_name_offset[n]`, `symbol_name_length[n]`, `symbol_payload[n]`, `symbol_scope[n]`, `symbol_kind[n]`, and copies the name through a further index-based loop. Many addresses use 16-bit `ASL/ROL` for word-table scaling and `ADC #<table / #>table` before `(zp),Y`.

The handwritten `ass/symbols.asm` uses stable pointers to inline-name variable-length records with header `length, payload_lo, payload_hi, kind`, and accesses fields via small fixed Y offsets. That avoids parallel-array index recomputation across **allocation, lookup, label definition and fixup resolution**, not just one function. An earlier *packed-record but still numeric-handle* C rewrite made the image **larger**: that negative result does **not** test the faithful stable-pointer record algorithm. Any control must account for differences in symbol and fixup semantics, C subset and RAM lifetimes.

## Where a 1 KB improvement must live

The seven largest generated C functions after outlining:

| Function | Bytes |
| --- | ---: |
| `parse_atom` | 557 |
| `assemble_instruction` | 541 |
| `parse_value` | 414 |
| `resolve_fixups_for_symbol` | 406 |
| `process_source_line` | 380 |
| `open_include` | 346 |
| `allocate_symbol` | 314 |
| **Total** | **2,958** |

These seven alone occupy ~42% of function-code bytes. A **35%** reduction across these seven would be ~**1,035 B**, but that is a *scale argument*, **not** a measured improvement or claim that 35% is feasible. There are other repeated indexed and argument patterns in smaller functions.

## What not to do next

- Do not pursue a chain of 20–150 B dead-load, fixed-register or source-spelling-specific patches. Multiple such approaches have already shown diminishing returns.
- Do not infer that eliminating a 1,292-B *pre-outline* cost will still save 1,292 B in the final encoded image.
- Do not assume the remaining **2,040 B** is entirely reducible by the backend: native assembler symbol/fixup algorithms and C source representation genuinely differ.
- Do not start Phase-1 C production integration or make VICE the dominant #102 task.

## Discriminating next experiment

**Whole-family machine-plan comparison, not a local patch.** Choose the linked groups `assemble_instruction` + its mode/value helpers and `allocate_symbol` / `find_symbol` / `resolve_fixups_for_symbol` / symbol-fixup consumers. For each:

1. Trace actual 6502 instruction/byte costs from *semantic producer through consumer*, including control, value transport, address formation and calls, versus a clean handwritten strategy.
2. Implement one alternate **general addressing/record-cursor machine strategy**, with explicit machine-state lifetimes across loops, branches and calls; compare an *entire 44-function linked image* against the 8,945-B baseline.
3. In parallel, do a fair source-algorithm control using **stable pointers**, rather than a packed record indexed by the same old numeric ID, so we can separate code-generator inefficiency from a genuine data-structure mismatch.
4. Keep 44/44 strict assembly, 45/45 encoded segments, 29/29 end-to-end C oracle cases and 9,120 compare cases. Require exact whole-image sizes. If neither strategy exposes a kilobyte-scale mechanism, report that as a negative result rather than broadening a local patch series.

This audit **identifies candidate cost families; it has not yet demonstrated a new ≥1-KiB reduction**.
