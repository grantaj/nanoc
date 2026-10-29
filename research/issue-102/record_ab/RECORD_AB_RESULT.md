# #102 — Stable-pointer symbol/fixup C source A/B experiment

**Date:** 2026-10-30. **Status:** completed negative result, research prototype; do not merge into production C or treat as a successful size optimisation.

## Research question

The handwritten `ass` assembler is 6,905 loaded bytes. The fully compiled research `ass.c` is 8,945 loaded bytes. Is this difference mainly caused by the C assembler's parallel symbol/fixup arrays and numeric indexes, rather than the quality of the compiler's machine-code selection?

Test the prior proposal **without changing the backend**: a C source alternative based on stable pointers and packed records, compiling through the same existing 44-function typed-tape compiler and 6502 backend. Unlike the prior unsuccessful experiment which packed records but retained numeric indexing in every loop, this variant actually **traverses records through a `char *record` cursor**.

## Variant design

- **A — baseline C:** `symbol_name_offset[896]`, `symbol_name_length`, `symbol_payload`, `symbol_scope`, `symbol_kind`, `symbol_name_bytes[9344]`; five parallel fixed-size fixup arrays, 640 entries. Numeric symbol and fixup indexes.
- **B1 — symbol records only:** `symbol_records[13824]`, with variable-length entries `length, payload_lo, payload_hi, kind, scope, name[]`. `find_symbol` walks a persistent `char *record` pointer, incrementing by the record length. `allocate_symbol` appends one record and returns its stable **byte offset** rather than the old element index. Other symbol consumers read fields by record address. No new helper functions, all 44 interfaces remain.
- **B2 — fixup records only:** `fixup_records[5120]`, eight bytes each: `kind, stage(2), symbol(2), addend(2), prefix`; `fixup_next` is a persistent pointer. Append, scan, resolve and trim traverse through `char *record` pointers instead of independently indexed arrays.
- **B3 — both changes together:** B1 + B2. Symbol handles remain compact 16-bit **byte offsets**, not raw pointers, because the existing parsing/fixup APIs require negative error sentinels and a stored reference identifier. Therefore this is a real **pointer-traversal** test, but *not* a byte-for-byte C translation of the native assembler's entire API or memory geometry.

Memory constraint: the packed symbol area has room for 896 headers × 5 B plus 9,344 name bytes = 13,824 bytes, **1,792 B less than the baseline symbol arrays** (15,616 B). The 640×8 fixup budget remains 5,120 bytes. The original symbols-per-table and name-byte capacity checks are retained; no extra RAM budget is silently introduced.

The backend is untouched, including existing width selection, 16-byte **hypothetical** zero-page pool, CFG/machine-flow passes, 6502 local-home allocator and exact-machine-sequence outliner. All function names and number of functions are unchanged.

## Full executable image measurements

| C source (same compiler) | Before outlining | After outlining | Final delta vs A |
| --- | ---: | ---: | ---: |
| A — original parallel arrays | **9,936 B** | **8,945 B** | — |
| B1 — compact symbol records + pointer traversal | **10,434 B** | **9,354 B** | **+409 B** |
| B2 — compact fixup records + pointer traversal | **10,086 B** | **9,064 B** | **+119 B** |
| B3 — both packed-record subsystems | **10,586 B** | **9,392 B** | **+447 B** |

The outliner saves approximately 991 / 1,080 / 1,022 / 1,194 bytes (gross linked effect; the outliner may also change branch placement and code layout). These results are **whole-image encoded bytes**, not estimates from generated assembly. There is no arbitrary target or minimum acceptable saving: the record alternatives simply generate **more code**.

## Function-level evidence

Values from `sizes.json` (packed pre-outlining function output; they are diagnostic and **not directly additive** to whole-image deltas):

| Function | Original | Both-records | Difference |
| --- | ---: | ---: | ---: |
| `resolve_fixups_for_symbol` | 617 | 834 | **+217** |
| `parse_atom` | 832 | 935 | **+103** |
| `find_symbol` | 307 | 409 | **+102** |
| `define_label` | 311 | 393 | **+82** |
| `stage_plain_word_reference` | 167 | 242 | **+75** |
| `all_symbols_defined` | 97 | 157 | **+60** |
| `allocate_symbol` | 384 | 407 | **+23** |

See `per_function_sizes.csv` for all 44 functions and for B1/B2 separately.

The machine generator repeatedly reconstructs and reads packed byte fields from C pointers. A word payload, for example, now requires two `char` loads and a shift/combination, and the current lowering cannot exploit the pointer-held Y-field access the way `ass/symbols.asm` and `ass/representation.asm` do. Some overhead is genuinely caused by explicitly packing/unpacking the C record; other overhead reflects the compiler's inability to carry efficient machine state through an entire traversal. The experiment alone **does not quantify how much of the remaining 2,040 bytes is removable compiler waste**.

## Correctness

- All B3 code passes **44/44 function assembly**, **45/45 encoded-segment byte matches**, **29/29 complete assembly programs** against B3's independently compiled C oracle, and **9,120/9,120 typed signed/unsigned word-comparison executions**.
- B1 passes **44/44, 45/45, 29/29**. B2 passes **44/44, 45/45**, and an independently repeated **29/29 complete cases** and **9,120/9,120 word comparisons** after an earlier tool run timed out while recording logs.
- More importantly, the **original C oracle and B3 C oracle produce identical status codes and output bytes on all 29 cases**—so testing B3 against itself has not disguised a simple semantic mismatch.
- Additional original-C versus B3-C host differential cases passed: **850 symbols** with reverse lookups and 1,700 output bytes, **590 forward byte fixups**, **645 fixup overflow**, **905 symbol-capacity overflow**, and **100 local-scope resets**. These are host C tests, *not* independent 6502 emulator runs of the large stress inputs.
- This is a research 6502 interpreter, not VICE or real KERNAL/IRQ validation. The hypothetical `$30-$3f` ZP pool is not proven safe in native C64 operation. Packed source and original may diverge on untested error or lifetime corner cases; do not call them formally equivalent.

## Interpretation / next decision

The experiment **falsifies the simple hypothesis that putting the C assembler's symbols and fixups into compact, pointer-walked records makes the present backend emit a smaller executable**. In fact, each subsystem separately makes the image larger. The baseline's source/data-representation difference is a real issue, but **we cannot use it as an explanation that absolves the backend**. A source algorithm close to the native machine algorithm is not naturally translated into native-like 6502 by the current backend.

The higher-level question is now sharper: **why does a cursor held in a C `char *` still become repeated field-address computation, spills and 16-bit arithmetic instead of a persistent machine pointer with small Y offsets?** The tape has no durable address identity; the operation-at-a-time generator does not commit a coherent loop machine plan; subsequent outlining rewards shared bad patterns. Trying another local indexed patch would not address that mechanism.

A future backend architectural trial should compare **machine-region planning over one complete pointer-walk loop**, preserving pointer/Y/A state across its backedge and consumers, rather than adding another cache to the present emitter. That trial should be compared against *both* C sources and measured only after whole-image linking/outlining. **No Phase-1 C production integration is proposed yet.**
