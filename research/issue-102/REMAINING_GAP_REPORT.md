# Whole-assembler gap reduction: machine-code outlining and native word comparison

**Date:** 2026-10-29. **Research backend only.** No production compiler changes. The hard comparison is the repository's **6,905-byte handwritten** `ass` image, not an arbitrary 16 KiB fit gate.

## Validated physical-size bridge

| Physically linked exact `bootstrap/ass.c` experiment | Loaded bytes | Relative to handwritten | Difference |
|---|---:|---:|---:|
| Earlier whole-function value homes + 16 ZP bytes | 10,321 | 1.495x | +3,416 |
| Above plus compiler-native constant word comparisons | 9,936 | 1.439x | +3,031 |
| Earlier homes plus generic repeated-sequence outlining alone | 9,316 | 1.349x | +2,411 |
| **Both independent changes applied** | **8,945** | **1.295x** | **+2,040** |
| Hand-written `ass/ass.asm` | **6,905** | 1.000x | — |

**Combined savings: 1,376 B (13.3%)** from the immediate previous generator. The contributions are not exactly additive because changing comparisons changes which repeated instruction sequences exist and shifts final branch layout.

## Mechanisms

### 1. Native 16-bit constant comparisons

`full_corpus/compare_native.py` is a new generic typed-codegen alternative to the eager signed-word comparator. It exploits that `int x < 0` on the 6502 requires **only the sign bit of x's high byte**; negative/unnegative comparisons return directly through `BMI/BPL`. A full-word equality/inequality to zero uses `LDA low; ORA high; BEQ/BNE`, while general word comparisons against a literal compare the high byte against an *immediate*, and only consult the low byte on equality. Signed bounds flip only the high-byte sign bit and compare the flipped literal—there is no need to materialize the transformed RHS into `__rh`. Handles swapped constant on left and signed/unsigned C promotions, falling back to the old comparison when not proved.

The independent `test_native_compare.py` runs **9,120 generated comparison executions in a 6502 instruction interpreter** across signed/unsigned words, constants on either side, all six relational operations, signed boundaries and randomized operands. It compares each output against Python's corresponding 16-bit signed/unsigned mathematical predicate.

**Net physical improvement on the full original source** (no outlining): **10,321→9,936 B**, saving 385 B. Per-function pre-layout cost improves by 407 B, primarily in `assemble_direct_value` (65 B), `assemble_instruction` (52 B), `parse_atom` (39 B), and other error/limit checks. This is a general comparison rule, not a source-function-specific recognition.

### 2. Exact repeated machine-sequence outlining

`outline_8.py` searches all available label-free, straight-line machine instruction sequences (4–36 instructions). It excludes branches, jumps, calls, returns, processor-stack operations and indirect stack use, and requires that a shared routine plus its call sites **provably encode fewer bytes than the original repeated instructions**. The best-overlap candidate is selected greedily; every replacement is physically `JSR helper`, with each helper containing precisely the original machine instructions followed by `RTS`. Helper routines live in the loaded code/data image, not in a separate ROM.

This factors repeated actual 6502 machine *algorithms* rather than tiny local caches: 14 occurrences of a 27-byte indirect-address sequence produce an estimated **308 B** of saving alone. The combined candidate factors **36** helper bodies and saves about **961 B pre-layout**, translating to a complete-image effect of **991 B** after size comparison against the native-comparison-only image: **9,936→8,945 B**. On the earlier backend the same approach independently saved **1,005 B**, **10,321→9,316**.

**Machine-safety preconditions:** `JSR/RTS` preserve A/X/Y and flags, and are balanced; the generated program must not examine or manipulate the processor's hardware stack in the outlined regions. The research checker rejects explicit stack instructions and `$0100`-page access in the emitted function body. This adds an additional call layer and execution time at the affected sites. The 29 end-to-end suite validates currently tested behavior, but this is **not yet an unrestricted C64 stack-depth/IRQ safety proof**. Consequently do **not** silently integrate the routine-outliner into a compiler that supports recursive calls, stack-visible features or arbitrary inline assembly. Optimize for size versus cycles explicitly.

## Full-program correctness

Run in an independent freshly extracted experiment:

- Exactly **44/44** generated C functions assembled by the original `ass.c` host-built assembler.
- All **45/45** function/runtime code segments matched the original assembler encoding byte-for-byte.
- **29/29 full-program end-to-end** assembly-source cases matched a separately host-compiled C oracle on return status and every emitted machine byte in the linked 6502 interpreter.
- **9,120 adversarial** signed/unsigned constant-comparison executions passed.
- Physical candidate: **8,945 loaded bytes** (`CANDIDATE.PRG` is 8,947 bytes including load address).

Command: `sh reproduce_native_compare.sh` from this folder. The script recompiles the source oracle, relowers the exact C source, reapplies the ABI, whole-CFG/register-home and shared 16-byte ZP location proofs, builds the original machine image, applies typed comparisons and outlining, strictly checks its physical encoding, runs 29 complete assembler tests and 9,120 comparison tests. It does not run a C64 ROM or VICE and does not validate the hypothetical `$30`–`$3f` ZP ownership under actual KERNAL/IRQ operation.

## What is still unaccounted for

With the new rules the complete image has **7,104 B in the 44 compiled functions** (after outlining). The largest are `parse_atom` (557 B), `assemble_instruction` (541), `parse_value` (414), `resolve_fixups_for_symbol` (406), `process_source_line` (380), `open_include` (346), `allocate_symbol` (314). Those seven functions already total **2,958 B**; no single small routine explains the last 2,040 B gap.

Across the 44 function bodies the new image still includes **1,002 LDA + 646 STA instructions**, plus 275 CMP, 227 JSR and 217 RTS. These are mostly not trivially redundant adjacent pairs (14 immediate `STA`→`LDA` pairs observed). The compiler is approaching a point where **algorithmic choices and memory representation** versus the handwritten machine program must be investigated rather than assuming a single register-cache fix will delete 2 KB.

The original native assembler uses compact variable-length inline-name records, stable pointers, arena lifetimes and custom direct staging paths; the Phase-1 C implementation uses parallel arrays and 16-bit symbol indexes. Earlier controlled packed-record experiments *increased* output size with this backend, so simply translating the native layout does not solve the remaining discrepancy. The next high-value control is to measure an **actually native-algorithm C reimplementation** or to introduce a more capable consumer-directed C machine lowering that removes entire full-width expressions and indexed accesses, **not** accumulate 50-byte tricks.

No claim of a proof that the remaining 2,040 B can be eliminated by better codegen alone. There are semantic and structural differences between the two programs, so a fair 1:1 goal requires controlling for them.