# `ass_native.c`: native-algorithm Phase-1 C assembler (first tranche)

This is a **new C assembler source**, separate from the existing
[`ass.c`](ass.c). It is intended to converge on the design of the actual
handwritten 6502 assembler in `ass/`, not to force the existing C assembler
through another increasingly complicated optimiser.

The first tranche deliberately retains the existing C scanner, parsing grammar,
opcode tables, file input and public `ass_assemble` interface. It changes the
*representation and lifetime* of symbols, exceptional fixups and staged output.
It is **not a line-by-line assembly translation**, nor is it complete parity
with the handwritten assembler's memory map or all of its algorithms.

## What's different

| | Original `ass.c` | New `ass_native.c` | Handwritten `ass/` |
| --- | --- | --- | --- |
| Symbols | Five parallel arrays, numeric index | Packed `[length, payload lo, payload hi, kind, name...]`, stable byte-offset handle | Same four-byte header with inline name, stable record address |
| Local labels | Persist through entire assembly with a scope number | Occupy a downward-growing local arena; validated and rewound at next global label | Same lifetime discipline |
| Persistent symbols | Stored in indexed arrays | Append upward into shared arena | Append upward through primary, overflow, hidden ranges |
| Forward word labels | Chain pointer stored in separate symbol payload array | The record's payload word is either the value or the reference-chain head | Same two-byte payload reuse |
| Exceptional fixups | Five parallel arrays | Eight-byte packed records, traversed as records | Small packed fixup records |
| Output staging | Numeric length determines each output address | Persistent byte pointer and separately maintained final assembly PC | Persistent staging pointer and final assembly PC |
| Externally visible length | Updated for every emitted byte | Computed once on return to public `ass_assemble` | Not a C ABI constraint |

The symbol arena is currently a **single 15,616-byte C array**, with global
records growing upward and live local records growing downward. This reproduces
the important lifetime relationship, but **not yet** the handwritten assembler's
physical main/overflow/hidden-RAM range boundaries or its ROM banking.

The original 896-live-symbol limit remains as a conservative bootstrap limit,
even though the packed format can fit a different number of records depending
on name lengths. That cap can be revisited with independent capacity tests.

The public C interface still returns numeric status bytes, not processor flags.
The parser and instruction dispatch also still follow the older C structure.
These are **future source changes**, not issues to handwave away as instruction
selection defects.

## Correctness evidence (2026-10-31)

- Both the original and new C sources compile as host C99 with unsigned `char`.
- `python3 tests/native-ass/test_native.py` compares real source functions
  through the same host I/O adapter: **29 established complete source programs**,
  seven explicit edge cases, 200 independently generated global/local/forward
  reference programs, plus symbol-capacity controls. Exact status and output
  bytes match on successful programs. Failure status matches; partial output
  may differ because unresolved local references are detected earlier.
- The suite directly verifies the four-byte record layout, both arena frontiers,
  the 11,264-byte staging capacity and the 640-record exceptional-fixup limit.
- Separately, the recovered experimental typed-tape front end lowered **52/52
  C functions**. All 52 functions assembled, **53/53** physical segments matched
  their reference encoding, and the experimental complete 6502 interpreter
  assembled **29/29** programs against its host-C oracle. This is **not**
  production `nanoc1`, VICE, or proven C64 ROM/IRQ operation.

## Code-size interpretation

The physically linked **unoutlined** image using the unchanged experimental
backend is **10,575 loaded bytes**, versus **9,936 unoutlined bytes** for the
original C program. These are comparable full-program *pre-outliner* results.
**This source rewrite is not yet a compiler-size win.** There is no post-outliner
measurement for this version; do not compare 10,575 directly to the original
8,945-byte *outlined* result or claim parity with the 6,905-byte native ASM.

This supports the more useful next investigation: when the same native source
algorithm is expressed in Phase-1 C, how efficiently can the compiler lower
small pointer-field accesses and loop-carried cursors? Separately, the existing
C parser and source handling still differ algorithmically from the native ASM.

## Scope and next migrations

1. **Symbol/fixup representation and lifetimes: implemented**, including local
   invalidation, stable handles, dual-use payloads, word chains and packed
   exceptional fixups.
2. **Streaming output staging: implemented**, with a single pointer cursor and
   explicit assembly PC. Public length is a boundary conversion only.
3. **Remaining native-algorithm migration:** adjust value/instruction dispatch
   and error/result paths, port native symbol/fixup access policies including
   hidden memory windows, and review source scanning/recursion semantics.
   Migrate complete dataflow paths; don't add redundant representations.
4. **Target validation:** compile using the actual Phase-1 compiler and run on
   the actual C64/KERNAL/IRQ environment before calling this production ready.

The goal is a clear, teachable C assembler with the **same basic algorithms** as
`ass/`, not a pasted ASM transcription and not a new optimiser framework.
