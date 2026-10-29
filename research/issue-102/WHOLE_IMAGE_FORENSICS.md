# #102: inspected-machine-code size forensics (2026-10-30)

**Goal:** understand and remove as much *genuine generated-code waste* as possible versus the existing **6,905-byte handwritten native assembler**. No arbitrary stopping size, no production integration, no priority to VICE. This is an **inspection of actual emitted 6502**, not a claimed new optimisation or estimate of guaranteed savings.

## Compared sources

- Research-linked **8,945-byte** machine image: `research/issue-102/experiment/compact_image.asm` / original ZIP `compact_image.asm`; 44 C function bodies occupy **7,104** bytes (reported by the independent physical encoder). The separately validated word-RMW variant reaches **8,823** B, but is not the baseline for these source-level counts.
- Original C: `bootstrap/ass.c`, retained exactly under the research archive's `full_corpus/exact_source/ass.c`.
- Native assembler: existing `ass/ass.asm` including `ass/parser.asm`, `ass/assembler.asm`, `ass/symbols.asm`, `ass/value.asm`, `ass/instruction.asm`, `ass/representation.asm`, `ass/source.asm`, `ass/data.asm`, `ass/scanner.asm`, `ass/skipws.asm`. Shared mnemonic and opcode tables are present in both implementations.
- Native code **3,210 handwritten machine instructions** counted from all included source modules. The research listing has **3,264 generated function-body machine instructions** plus **325 outlined-helper instructions** and another **212** instructions in retained I/O runtime and startup, **3,801 total**. These totals are not perfectly functionality-equivalent; the C source uses different symbol/fixup representations and the wrapper/runtime boundaries differ. They are *not* an instruction-for-instruction mapping.

## Recoverable code-generation waste: cost of current instructions, NOT saving forecasts

Grouped function-body operands by their resolved 6502 location. The approximate byte totals reflect instruction-width classification of the generated assembly (parser totals within 25 B of independent 7,104 B physical encoded body total); categories are exclusive by opcode operand but **not** hypothetical independent savings:

| Current function-body category | Instructions | Current encoded bytes, approximately |
| --- | ---: | ---: |
| Accesses to private local/formal scalar homes (`__L_*`) | **787** | **1,723** |
| Accesses to shared temporary, pointer and arithmetic scratch (`__tmp`, `__ap`, `__ix`, `__mw`, `__rh`) | **287** | **574** |
| Accesses to C static call argument slots (`__call_*`) | **168** | **409** |
| Accesses to status/mode/kind globals with fixed initialized values | **193** | **579** |
| Calls to outlined duplicate machine sequences | **116** | **348** |
| Ordinary C-function and ROM calls | **111** | **333** |

The constant-like globals are initialized as mutable C objects, so converting them to immediate operands requires proving absence of writes/aliases; even if all 193 uses could become immediate, the **operand-size saving is only ~193 B plus some initialized data**. This is not the multi-kilobyte answer. The 409 B argument category is also not all removable: correct register/call-state coordination would have to eliminate accompanying producer reloads, callee re-materialisations, spills and unnecessary status staging. The 1,723 B local/formal home cost is the largest candidate family but many accesses are semantically necessary; blindly deleting a home or caching X/Y already failed to deliver large gains in earlier experiments.

## Real 6502 strategy differences, verified by reading the listing

1. **C success returns as bytes vs native flags:** `stage_resolved_instruction` emits `JSR stage_byte; STA status; CMP ASSEMBLE_OK; BEQ success; LDA status; RTS` after a fallible operation. In the native `ass/assembler.asm` `stageResolvedInstruction`, `JSR stageByte; BCC full` uses the carry flag directly, and `stageByte` in `ass/representation.asm` already sets carry. The C compiler must preserve the exact C API semantics, so a flag-result lowering needs to be justified across the **producer and consumer** and all joins.
2. **Wide signed index/length loops vs direct machine cursors:** `find_symbol` compares 16-bit signed `i < symbol_count` with high-byte sign XOR and separate low-byte comparison, then reconstructs addresses in `symbol_scope[i]`, `symbol_name_length[i]`, `symbol_name_offset[i]` etc. Native `findSymbolEntry` walks stable inline-name records by a 16-bit pointer and bounds. These *are different source algorithms*, so do not attribute all record savings to codegen. Earlier packed-record-but-numeric-ID C controls grew the image; they did **not** faithfully reproduce stable-pointer traversal.
3. **No consumer-level addressing plan:** `assemble_instruction` repeatedly uses a 16-bit offset construction + `__outline_02` / `__outline_01` to read guarded `argument[argument_length-k]`, instead of retaining a base pointer and deriving a Y-offset known to fit. The backend emitted **61 complete effective-address constructions**, approximately **1,292 instruction bytes before outlining**, in an earlier controlled method audit. That figure is **not recoverable again in full** because outlining has already shared repeated pieces.
4. **Repeated table scan state:** Generated `find_mnemonic` calculates `candidate*3`, builds individual text indexes and repeatedly calls `upper_char`. Native `findMnemonic` carries X/Y through its 3-byte table comparison and folds ASCII with `AND #$df`. This is a particularly clear example of choosing an efficient whole-loop algorithm instead of emitting each source expression independently.
5. **Stage pointer vs offset reconstruction:** Generated `stage_byte` checks a 16-bit length against a constant, constructs `ass_image+ass_image_length` and increments the 16-bit length through temporary bytes. Native `stageByte` uses `stagingPtr` as a persistent cursor, stores through `(ZP_PTR0),Y`, and increments the actual address with carry. These paths also have different workspace and status semantics; use as an algorithm comparison, not a claimed exact substitution.

## Most important correction to earlier strategy advice

The native assembler declares just **4 dedicated ZP bytes** (`ZP_PTR0=$fc/$fd`, `ZP_PTR1=$fe/$ff`) in `ass/zp.inc`. The research generator's **16-byte `$30-$3f` register file is hypothetical and already *more* than native's explicit pointer reservation**, yet the research image is larger. Increasing the ZP pool is therefore **not** a primary explanation. This is principally a question of eliminating value transport and choosing register/flag/address trajectories as part of semantic lowering—not allocating more state.

## What the next discriminating experiment should compare

**Do not design another tiny peephole.** Investigate producer-to-consumer machine algorithms with *actual* emitted code and a matched handwritten method across several functions, including:

- **Failure/result path ABI** across the `stage_byte`, fixup, source and instruction parsers. Measure the entire chain of status byte materialisation, call-argument stores, private-home loads and flags, not only a selected `STA`.
- **Actual pointer/offset strategy** across symbol allocation, search, fixups, output staging and mnemonic/operand parsing. Distinguish the cost of compiling the *same C program better* from the cost of the different source data structures. Use faithful stable-pointer source rewriting only as a **separate control**.
- **Wide-to-byte proof for complete regions** (bounds, aliasing, calls and joins) rather than blindly narrowing C's 16-bit `int`. The real semantics must remain correct, including negative values, 255/256 crossings and page boundaries.

Compare full linked images and regenerate the 44/44 function, 45/45 byte encoding, 29/29 program and 9,120 immediate comparison oracles. Every measured outcome, including regressions, should be committed to an experimental branch.

**No new ≥1-KiB reduction is proved by this audit.** The purpose is to identify the actual sources of bloat and refuse unearned size predictions or arbitrary success gates. The desired reduction is **as large as correct code generation permits**, relative to the handwritten 6,905 B reference, after accounting for program-level differences.
