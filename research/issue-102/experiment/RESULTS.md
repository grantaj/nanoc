# Experimental register-A argument ABI on the complete assembler

**Date:** 2026-10-29. Research only: not a production Nano C compiler.

## Question

Does making caller/callee agree on a machine-register argument eliminate the large remaining gap from the handwritten 6,905-byte assembler?

## Controlled change

Same 44-function C source, typed tape, previous CFG/state backend and physical linker as the earlier *11,757-byte* A-register + certified-region candidate. Alter only the argument-transport convention at the linked-assembly boundary:

- For every internal C function whose final formal parameter has type `char`, pass that argument in accumulator A.
- The compiler's existing final `STA __call_function_N` is omitted immediately before `JSR function` (81 call sites).
- At callee entry, insert `STA __L_function_last_param` to preserve a proper writable per-function C parameter home (28 functions).
- All earlier arguments retain their existing static ABI slots; the full-width return rules are unchanged. There is no compiler-source-name dispatch.

This is semantically valid for the tested closure because (1) the removed `STA` was adjacent to `JSR`, so A holds precisely the intended byte when control enters the callee; (2) `JSR` and `STA` do not modify A or condition flags, so the callee's entry memory state after its `STA` equals the prior implementation's entry state; (3) the callee still owns its parameter storage and can modify it; (4) no nonstandard callers enter these chosen functions. It is a register calling convention, **not** yet a genuine interprocedural location coalescer.

## Full-image results

| Variant | Complete linked loaded bytes | Difference |
|---|---:|---:|
| Earlier A-state + certified region | **11,757** | baseline |
| Final byte argument in A | **11,562** | **−195** |
| Handwritten native `ass` | **6,905** | benchmark |

New ratio **1.674×** handwritten; remaining difference **4,657 bytes**.

The 81 removed caller-side absolute stores would alone save 243 B; the 28 new callee prologue absolute stores add 84 B. The link/layout effects supply the remaining difference between this nominal 159-byte saving and the **measured 195 B**. The new program still accesses ordinary static locals and arrays as before.

## Verification

- Regenerated from the full C source with `REG_FIRST=1` and the existing region-enabled backend, then applied the general ABI transformation.
- **44/44** functions assembled using the exact original host-built `ass.c` assembler.
- **45/45** complete code segments byte-for-byte identical to its machine encoding, including retained runtime.
- **29/29** complete linked 6502-interpreter vs native-C assembler programs matched assembly status and output bytes.
- The final image includes runtime and initialized globals. No native VICE claim.
- `./reproduce_a_abi.sh` regenerates the complete result and tests and checks exactly 11,562 loaded bytes.

## Interpretation

The new register ABI is semantically sound and makes `JSR` argument staging more like human 6502 code. Yet it saves only 195 bytes on the whole program. There are 111 C call sites total, and 328 stores into argument slots in the starting image. Even the physically unrealistic elimination of **all 328** 3-byte stores would save at most 984 bytes from that precise category (and would demand some callee preparation), far short of the ~4.8 KiB gap.

The next structural test must examine **where live locals and parameters reside throughout their functions**, not merely how their final byte crosses a call instruction. This includes avoiding default memory homes for multiuse values and selecting whole-machine algorithms; source-representation differences remain a separate contributor. Do not extend this ABI tweak into a catalogue of small call-convention optimisations and mistake the small result for a major breakthrough.
