# #102 — conventional 6502 code generation: first controlled experiment

**2026-10-30. Research only. Original Phase-1 C source, mature generator, 44-function corpus and native 6502 interpreter tests are unchanged.** This experiment deliberately avoids an extra instruction optimiser, machine-state beam search, or bespoke function/loop recogniser. It implements one rule about how a 6502 programmer normally writes symbols: **a provably immutable scalar belongs in an immediate operand, not a RAM variable**.

## Implementation

The existing C assembler is deliberately written in Phase-1 C (no `const`, `enum`, preprocessing or macros), so declarations such as `char ASSEMBLE_OK = 0;` and `char MODE_ABSOLUTE = 6;` are **legally mutable C globals** even though this complete C program never changes them. The original research code generator treats them as RAM objects, repeatedly emits `LDA ASSEMBLE_OK` or `CMP MODE_ABSOLUTE`, and copies their initialisers to RAM at startup. The native 6502 assembly uses symbolic equates / immediate operands.

`simple6502_constants.py` now performs a deliberately small closed-world proof directly over the original program's C syntax:

1. Find scalar globals with integer constant initialisers.
2. Reject any scalar assigned to, modified by an increment/decrement, or whose address is taken anywhere in the C unit.
3. Before instruction selection, change `load(name)` in the typed semantic tape to `const(value)` while retaining the C value's declared byte/word kind.
4. Never apply the fact to a shadowing local or parameter.
5. Remove the globals' now-unreferenced initialiser bytes from the emitted image.

This makes the **existing ordinary instruction emitter** naturally emit `LDA #$00` / `CMP #$06`; it is not a post-assembly rewrite and does not require special cases for the identifiers. The proof is conservative: ambiguous cases keep ordinary memory semantics.

### Results (physically encoded linked image)

| Measured item | Original | With the rule | Change |
| --- | ---: | ---: | ---: |
| Complete loaded image, no outlining | 9,936 B | 9,679 B | **−257 B** |
| Complete loaded image, with outlining | **8,945 B** | **8,697 B** | **−248 B** |
| Full per-function code before outlining | 10,969 B | 10,755 B | **−214 B** |
| Initialised program data bytes | 741 B | 698 B | **−43 B** |
| Immutable, non-address-taken globals | — | **43** | All proved C constants |
| Functions with reduced initial machine code | — | **32 of 44** | No function-name rules |

The pre-outlining benefit is **257 B**, of which **248 B survives** outlining. This is precisely the opposite of previous indexed-address changes, which generated large pre-outline reductions but only a handful of final bytes. A by-construction immediate operand decision reaches most of the image because it doesn't rely on replacing sequences previously factored into JSR helpers.

The largest unoutlined function improvements are `parse_atom` −29 B, `assemble_instruction` −22 B, `parse_value` −17 B, `stage_data_value` −14 B, `assemble_direct_value` −13 B, `process_symbol` −12 B. Every function still uses the same C algorithms and types.

### Validation

Reproduced from the **exact user-recovered ZIP** with the same host C compiler, 6502 assembler, independent linker, encoding checker and research 6502 interpreter:

- **44/44** strict assembled functions
- **45/45** byte-for-byte encoded machine segments
- **29/29** complete 6502 assembler programs versus host C oracle
- **9,120/9,120** typed wide-comparison cases
- Six independent semantic safety cases for mutable globals, address escapes, shadowing and signed/unsigned widths
- With `SIMPLE_6502` unset, the baseline **8,945 B** image is still exactly byte-identical to the archived PRG (SHA-256 `e155a78e9b7c4a5e68fc4b30ee9e4cb655048bdc2a9377477316ee1dcc813ef2`)

Run:

```sh
sh reproduce_simple6502.sh
```

The option is enabled only with `SIMPLE_6502=1`; without it `reproduce_native_compare.sh` retains its original baseline expectation. This standalone trial can be composed with other rigorously verified source facts, but **should not be merged into production `nanoc1.c`** until a coherent simple emitter and C64 memory map are validated.

## Architectural assessment — do not overclaim

This is a **positive test of a simple machine-first code-generation convention**, not a wholesale new emitter. The 21-layer mature backend still emits the rest of the program, so it would be incorrect to say we have already replaced it. The proof uses a whole-unit read/write check, which is straightforward for Phase-1 C because this is one closed program without address-of escapes; arbitrary C or separate compilation needs a stronger alias/linkage proof.

The natural 6502 principles for the subsequent independent emitter remain A as the expression/result register; X/Y reserved deliberately for indexing; flags consumed directly by branches; pointers kept in zero page for traversal; byte-sized work kept byte-sized when its range is established; direct destination updates rather than unconditional intermediate materialisation. Most individual idioms exist in the previous backend. **They must be consolidated coherently, not stacked as more backend inheritance layers.**

The handwritten assembler is **6,905 B**, whereas this experiment yields **8,697 B**. The remaining **1,792 B** is not yet classified into compiler waste vs differing source algorithms and the research runtime. No arbitrary stopping size is proposed. A successful full redesign must show these conventional rules generating sensible 6502 across *multiple unrelated functions without a sequence of repair passes*; this experiment establishes only the first, broad rule.
