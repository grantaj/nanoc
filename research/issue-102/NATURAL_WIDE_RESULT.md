# #102 — conventional 6502 emitter extended to words, pointers and calls

**Date:** 2026-10-30. **Status:** validated experimental extension; **not** a net code-size win and not a production `nanoc1.c` change.

## Why

The first small by-construction emitter handles four byte-oriented assembler functions and produces simple 6502 (A result, CMP/flags for decisions, Y indexing, two persistent zero-page pointers in a byte-loop). This experiment extends those **ordinary machine conventions** to the real word-, pointer- and call-heavy C without building a tree search, virtual-register allocator or another layer atop the mature emitter.

## What changed

- `full_corpus/natural6502_wide.py` extends the 255-line independent `natural6502.py` emitter, **not** the 21-layer mature backend.
- **16-bit values:** the established C ABI is low byte in A, high byte in X. Word arithmetic uses explicit low-byte `ADC/SBC` and high-byte carry propagation. Byte-to-word promotion zero-extends. Memory words increment directly with low-byte carry. Word comparisons branch from high/low-byte tests, signedness handled where proven.
- **Pointers and indexing:** pointer[constant] uses `(zp),Y`; full 16-bit array indexing forms the complete effective address with explicit carry into the high byte, scales word elements when required, and loads/stores through `(zp),Y`. Indexes at 255/256 and beyond cannot silently wrap Y. The old generic index fallback remains as a control.
- **Calls:** statically allocated parameter slots match the existing nonrecursive ABI; a returned byte is in A, returned word in A/X. Calls are not permitted inside argument expressions until evaluation order and scratch effects can be proven.
- **Common source constructs:** direct `word >> 8`, `word & 255`, word arithmetic, bounded constant shifts, multiplication by an explicit small constant, `break`, and writes into byte/word arrays. Unsupported expressions are rejected, not guessed.
- Existing `link_model.py` tries the original simple emitter and the extension, choosing a candidate only when its *individual function instruction bytes* are smaller than the mature backend. This is a controlled multi-function research test, **not** an image-global search or a new production pass.

## Coverage

The wide extension can emit **26 of the 44 actual C assembler functions**. The other 18 are deliberately rejected, including `parse_atom`, `find_symbol`, `resolve_fixups_for_symbol`, `assemble_instruction`, `allocate_symbol`, and `ass_assemble`. Some new functions are emitted successfully but *larger* than with the mature backend, so they are not selected for the linked image.

The linked build picks **12 functions** (four existing simple-emitter cases plus eight new wide/call/index cases): `upper_char`, `same_text`, `short_mode_for_index`, `long_mode_for_index`, `hex_nibble`, `trim_fixups`, `scope_for_name`, `parse_value`, `close_source_tree`, `process_symbol`, `all_symbols_defined`, `all_fixups_resolved`.

## Physically encoded size and why it matters

| Same 44 C functions | Full image before outlining | Final physically linked image |
| --- | ---: | ---: |
| Frozen recovered backend | **9,936 B** | **8,945 B** |
| Previous four-function natural emitter | 9,926 B | **8,935 B** |
| New combined natural byte+word emitter | **9,954 B** | **8,961 B** |
| Handwritten native assembler | — | 6,905 B |

**The expanded emitter makes the executable 16 bytes bigger than the unchanged 8,945-B control.** This is a legitimate negative result. Individual function instruction-byte wins are not additive because the mature machine-flow, register-home, ABI and outliner passes change code sharing when function bodies change. The new rules demonstrate coverage and machine correctness, not the sought major size improvement. Do not chase a few bytes by cherry-picking functions.

## Independently rerun

The clean control `sh reproduce_native_compare.sh` still reports **8,945 B**, 44 strict functions, 45 matching segments and 29 complete programs.

The clean wide build `sh reproduce_natural6502_wide.sh` reports **8,961 B**, 44/44 strict functions, 45/45 independent binary matches, 29/29 C-oracle-vs-6502 full assembler programs and 9,120/9,120 signed/unsigned word comparison executions. Every selected generated function therefore participates in a complete interpreted 6502 program test, not just a source-level model.

`PYTHONPATH=full_corpus python full_corpus/test_natural6502_wide.py` independently passes **1,500 interpreted 6502 test cases** for the directly generated functions: signed/unsigned 16-bit relative arithmetic and boundary return codes; 16-bit pointer dereference (`scope_for_name`) at page boundaries; calls from `hex_nibble` with deliberately clobbered scratch and registers; byte extraction from words; 896-symbol and 640-fixup wide table scans across page boundaries; 11,264-byte output buffer writes at 255/256, 511/512, 11,263/11,264. These tests are separate from the 29 full program cases and do **not** establish general memory safety on a C64 or VICE.

## Main conclusion

**We have now handled substantially more complex C by construction, yet we have not found a substantial full-image saving.** The next work should not be another exhaustive recipe-adding exercise. The large remaining programs rely on statement- and data-structure-level flow (`find_symbol`, `parse_atom`, fixup resolution and instruction parsing), not merely the ordinary A/X/Y/CMP/ADC/(zp),Y primitives addressed in this tranche. The handwritten 6,905-B assembler remains the reference, but it uses a different symbol/fixup algorithm. This diagnostic result neither proves the existing backend optimal nor justifies abandoning the simple conventional-machine direction.

The next useful engineering decision is to identify **one consistent machine execution discipline spanning calls, multi-array loops and stateful parsing**, then check that it generates sensible unoutlined machine code for the *large* functions. In the meantime, do not integrate these prototypes into `nanoc1.c` or treat 8,961 B as a code-size advance.
