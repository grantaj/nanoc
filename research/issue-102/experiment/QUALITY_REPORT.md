# Nano C experimental machine-code audit — follow-up, 29 October 2026

## Result

This is a **research-only** evolution of the exact whole-`bootstrap/ass.c` typed-tape backend. It does **not** change the production Phase-1 compiler or any PR. The generated image continues to implement the complete 44-function C64 assembler with its original static ABI/runtime, subject to the research interpreter's ROM/I/O limitations.

| Successive experiment | Loaded image bytes | Reduction in that step |
|---|---:|---:|
| Previous general backend | **14,940** | — |
| Backward propagation of byte-width demand | 14,912 | 28 |
| Proof-driven `Y` loop for 256-entry read-only byte arrays | 14,804 | 108 |
| Safe direct indexed-read-to-CMP lowering | 14,728 | 76 |
| Certified two-pointer byte loop, stable zero-page pointer bases | 14,723 | 5 |
| Exact 16-bit constant-folding on the tape | **14,363** | **360** |

**Net: 577 bytes less (3.86%)**, with **2,021 bytes below the 16,384-byte code/BSS limit**. The `CANDIDATE.PRG` is **14,365 bytes including its two-byte `$0800` load address**. This is a physically linked candidate, not a function-only projection.

The table shows a *stepwise*, not additive causal attribution across different function selections. The implementation never recognises function names for machine-plan selection.

## What is now better by construction

* **Backward byte demand (`width_demand.py`)**: A 16-bit semantic `+`, `-`, bit operation, constant multiply, constant left shift, or negation can emit only the low-byte computation when **all** consumers discard the high byte. Full-width uses, compares, addresses, and signed/unsigned semantics remain wide. `upper_char` falls **41→33 B**, but still carries a redundant temporary store before returning.
* **Certified Y-index scan (`y_loop.py`)**: For a natural signed-word `i=0; i<256; ++i` scan of one or more known 256-byte *read-only* arrays, a single `Y` cursor and `absolute,Y` reads replace repeated 16-bit index checks and full address construction. There is a unique preheader, no side entrance, no call/indexed writes, a proven unit step, and no observable post-loop index. Overflow of Y at 255 exits correctly; early return of `i` uses `TYA; LDX #0; RTS`. `find_opcode` ultimately falls **165→40 B** after the additional fixes.
* **Direct compare (`read_compare.py`)**: A one-use 8-bit indexed read feeds the immediately following `CMP` in A when there are no intervening machine-emitting operations and the compared operands are proved byte-valued. A critical **regression was caught** in this experiment: a read with one *explicit* use could still be the physical origin of a later cross-block CSE alias. Skipping its store broke the linked assembler (return status 10 instead of 0). The final proof **rejects all read values appearing in `read_alias.values()`**, not just those appearing as alias keys. The linked tests and a new CSE-origin regression test then pass. **Do not restore the unsafe version.**
* **Two-base loop state (`dual_pointer.py`)**: When a loop has stable, read-only pointer bases and an 8-bit induction variable, retain both pointer bases in `__ap`/`__ix` while Y indexes them. Still increment the actual C scalar `i` in memory each iteration, preserving observable semantics even if a source pointer aliases its storage. `same_text`: **82→73 B**. The static saving is small; this mainly addresses a repeated-address machine-algorithm pathology.
* **Constant tape folding (`const_fold.py`)**: Exact 16-bit modulo arithmetic replaces runtime calculation of `-1`, `-2`, `-3`, and other entirely constant expressions, including additions, bitwise operations, multiplies and constant left shifts. Savings transfer to error-return paths across many functions. This is a semantic operation canonicalisation, not a source-function patch.

## Validation

All tests run through `sh verify_all.sh` in this directory:

- The project's **actual original C assembler** byte-matches the generated 6502 for all 44 functions plus retained runtime (**45/45**).
- The complete physically linked candidate executed under the research MOS 6502 interpreter agrees with independently host-compiled `ass.c` on status and every output byte for **29/29 assembler input programs**, including symbols, labels, forward references, addressing and randomized inputs.
- **2,988 operation-level semantic tests**: both 8-bit and 16-bit arithmetic results; independently specified 256-byte scans with early matches at offsets 0, 1, 127, 254, 255 and no match; array page crossings; dual-pointer scans; six negative loop-proof cases; and 360 targeted cache-origin aliasing regressions.
- **5,600 signed/unsigned 16-bit comparison tests** run against this updated backend.
- The physical image ends below `$4800`, no overlapping globals/parameters/runtime/BSS, eight-byte packed scratch maximum, and the selected ABI is unchanged from the previous research candidate.

**Limitations:** This is **not** a native VICE/ROM run, and the previously identified empty-input KERNAL-prefetch simulation discrepancy remains unresolved. The full-program test corpus does not prove complete correctness. This is **not yet a production compiler integration**; code generation and linking are research-only Python code. The comparison test uses the actual assembler as a strict encoder, not the original compiler as the code generator.

## Largest remaining weak functions (linked instruction sizes)

| Function | Bytes | Dominant machine-code weakness |
|---|---:|---|
| `assemble_instruction` | 1,450 | Repeated static argument staging and indexed address preparation |
| `parse_atom` | 891 | Temporary traffic, two-byte arithmetic and nested scan control |
| `resolve_fixups_for_symbol` | 836 | 16-bit index scaling and repeated effective-address construction |
| `assemble_direct_value` | 659 | Call preparation and word operations |
| `open_include` | 620 | Pointer/index reconstruction and call staging |
| `parse_value` | 588 | Repeated global scalar loads/stores and branching |
| `allocate_symbol` | 542 | Five parallel symbol arrays addressed with repeated wide indexing |
| `process_source_line` | 542 | Nested parser control and call argument preparation |
| `process_instruction_like` | 496 | Multiple calls repeatedly staging identical pointer/length parameters |

The next genuinely structural experiment should attack **a common wide-index/address-mode plan for a group of parallel array accesses**, or **call argument placement** across a safe block, not another function-name-specific rewrite. For `allocate_symbol`, `n=symbol_count` is bounded to `[0,895]`; it cannot simply be truncated to Y. This is exactly where an explicit multi-byte index machine plan matters.

## Files

- `full_corpus/width_demand.py`, `y_loop.py`, `read_compare.py`, `dual_pointer.py`, `const_fold.py`: generic research components.
- `compact_image.asm`, `CANDIDATE.PRG`, `compact_resolved.json`: exact linked candidate and symbol map.
- `QUALITY_COMPARISON.csv`: all 44 function sizes against the previous 14,940-byte image.
- `test_general_machine_rules.py` and `test_word_comparisons_new.py`: adversarial and numerical tests.
- `verify_all.sh`: one-command rebuild/validation.
