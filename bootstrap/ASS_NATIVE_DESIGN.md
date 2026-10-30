# `ass_native.c`: native-algorithm Phase-1 C assembler (first tranche)

This is a **new C assembler source**, separate from the existing
[`ass.c`](ass.c). It is intended to converge on the design of the actual
handwritten 6502 assembler in `ass/`, not to force the existing C assembler
through another increasingly complicated optimiser.

The initial tranche retained the original C scanner, instruction dispatch,
opcode tables, file input and public `ass_assemble` interface. It changed the
*representation and lifetime* of symbols, exceptional fixups and staged output.
The subsequent instruction/value migration now replaces that instruction
dispatch with the native `parseInstruction` → `selectDirectMode` → staging
sequence, while retaining the already native-compatible tiny value grammar.
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
The instruction decoder now follows the native two-stage, zero-copy operand
view and mode-selection algorithm. The scanner, value atom parser and remaining
source and I/O algorithms remain subject to future source-level review.

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
3. **Instruction/value handling: implemented as a follow-up**: classify syntax
   first into a zero-copy view and mode, parse the one-atom-or-two-atom value
   once, then choose direct width and stage the fixed value or forward-reference
   recipe. The value grammar and its captured symbol/addend/prefix were already
   faithful to `ass/value.asm`, so they were retained rather than rewritten.
4. **Remaining native-algorithm migration:** handle native source-file scanner,
   cross-range and hidden-RAM symbol access, and result/carry conventions
   where the C API permits them. Preserve full dataflow paths and do not add
   redundant representations.
5. **Target validation:** compile using the actual Phase-1 compiler and run on
   the actual C64/KERNAL/IRQ environment before calling this production ready.

The goal is a clear, teachable C assembler with the **same basic algorithms** as
`ass/`, not a pasted ASM transcription and not a new optimiser framework.

## Instruction/value translation checkpoint (2026-10-31)

The second tranche follows the assembly source rather than introducing a
compiler optimisation.  `parse_instruction` now processes each operand once:

1. Look up the three-byte mnemonic, leaving the original text untouched.
2. Recognise implied/accumulator, immediate, direct X/Y, `(value,X)`,
   `(value),Y`, and `(value)` syntax by adjusting a pointer/length *view*.
3. For fixed addressing modes, check the mnemonic/mode pair immediately.
   Direct operands defer width selection to `select_instruction_mode`.
4. Call the existing small `parse_value` **once**. That routine already has
   the precise `ass/value.asm` grammar (`[<|>] atom [(+|-) atom]`) and the
   native unresolved recipe: a stable symbol handle, 16-bit addend and byte
   selector. There is no expression tree or recursion to introduce.
5. Choose relative, zero-page or absolute addressing using the actual opcode
   table, then stage the opcode/value or native two-byte reference chain /
   eight-byte exceptional fixup. The fixed-word, byte and relative staging
   helpers from the initial tranche remain unchanged.

This supersedes the previous separate `assemble_mode_value` and
`assemble_direct_value` paths. The initial version mishandled explicit `ASL A`:
its accumulator operand must not be sent through the value parser. An
independent instruction-grammar fixture caught and fixed that case before
commit. A second experiment used one compound C shift-add expression to
replace decimal `*10`; although algebraically valid, the experimental 6502
backend miscompiled it, so the checked-in C retains the known-correct modulo
16-bit multiplication. The handwritten parser's *semantics* are preserved.

### Verified results

| Same native-structured C source architecture | Before outlining | After outlining |
| --- | ---: | ---: |
| First tranche, PR #127 | 10,575 B | 9,553 B |
| With native instruction/value dispatch | **10,378 B** | **9,457 B** |

**197 B** reduction before outlining, **96 B** in the complete linked image.
The new source is still larger than the original flat-array `ass.c` image
(8,945 B after outlining). This is **not** evidence of optimal machine code.

Verification: 53/53 lowered/generated functions, 54/54 independently encoded
segments, all 29 complete interpreted-6502 assembly programs against the host
C oracle, plus 18/18 *new* machine-executed instruction/value examples. The
host-compiled original and new C assemblers agree on 29 established complete
programs, seven local/fixup examples, 200 randomly generated scope/reference
programs, capacity boundaries and **425** separate deterministic/generated
instruction/value programs. Failures are compared on status; successful
programs compare exact output bytes. As before, these are research 6502
interpreter tests, not real C64/VICE or production `nanoc1` execution.

A remaining structural difference is that status/error reporting uses C bytes,
not the handwritten carry flag protocol. The symbol ranges also still lack
hidden-RAM banking. Neither should be silently claimed as translated.
