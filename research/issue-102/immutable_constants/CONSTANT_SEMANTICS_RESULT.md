# Issue #102 — a source-language mismatch, not a 6502 instruction-selection failure

**Date:** 2026-10-30. **Research only;** production `nanoc1.c` and the existing mature research backend remain unchanged.

## Question

We have repeatedly tried to reduce the difference between the 8,945-byte compiled Phase-1 C assembler and the 6,905-byte handwritten 6502 assembler by changing instructions, register-state searches, block layouts and simple direct emitters. Are we compiling *the same abstract program*, or do features missing from the C subset force ordinary assembly-time constants to occupy RAM and consume instructions?

## Finding

The original `bootstrap/ass.c` deliberately omits `enum`, `const` and the preprocessor. Consequently 43 apparently constant names (`ASSEMBLE_OK`, `VALUE_BAD`, `MODE_RELATIVE`, `FIXUP_WORD`, etc.) are **mutable global `char` objects** in its C semantics. A frontend cannot simply assume these globals are immediates without proving they are never written or have their address taken. In this complete C translation unit, we checked both properties using the parsed C AST and found all 43 are immutable and have no address-taking use.

We performed a **closed-program semantic source ablation**: remove just those 43 scalar declarations and substitute the corresponding integer literal at their references. Neither the algorithms nor the backend's register/stack/ABI/optimiser code changes. We regenerated the actual per-function typed-tape sources: changing only the top-level file without doing that would be an invalid/stale-build experiment.

| Full 44-function assembler | Before sequence outlining | Final physically linked image | Difference |
| --- | ---: | ---: | ---: |
| Archived unchanged C source and code generator | **9,936 B** | **8,945 B** | — |
| 43 compile-time scalar literal substitutions, same generator | **9,679 B** | **8,697 B** | **−248 B final** |
| Hand-written native assembler (different source algorithms) | — | **6,905 B** | Reference only |

The image still has a **1,792-byte** gap versus handwritten code. This is a real 12.2% reduction *of the original 2,040-byte difference*, but not a solution to it. Of the removed 248 bytes, **43 are initialized global data**; the remainder comes from machine instruction/outline/layout effects, not solely immediate-instruction size. These are *different C semantics under an open-world model*, so this transformation is **not** legal for an independently linked C function that might mutate globals from another translation unit. It is proven only for this closed assembler translation unit.

## Validation

A clean reproduction from the original `nanoc_remaining_gap_codegen_experiment.zip` gives:

- **8,697 actual loaded bytes**, **9,679 pre-outline** (PRG file includes two additional load-address bytes).
- **44/44** original assembler strict function checks, **45/45** encoded binary segment matches.
- **29/29** complete C-oracle-vs-interpreted-6502 assembler programs.
- **9,120/9,120** signed/unsigned word comparison cases.
- Independently compile *both* the original C program and the rewritten C program as host shared libraries. All **29/29** exact program statuses and **every byte** of output agree, not merely each candidate with its own oracle.

## Reproduction

From the repository containing the original issue-102 research ZIP:

```sh
python research/issue-102/immutable_constants/reproduce_immutable_globals.py
```

The script extracts to a temporary directory, proves the source properties, changes the C copy, regenerates all 44 exact function tapes, rebuilds the whole 6502 image, executes tests and compares original vs rewritten host-C output. Use `--workdir /tmp/issue102-constants` to retain all intermediate assembly and logs. It asserts the physical 8,697-byte image, so a change in the archived source or backend is detected rather than silently changing the reported measurement.

## Architectural implication

This is a different kind of failure from the instruction-selection cases. The C subset describes runtime variables where the native source uses assembler equates; no register planner can make a mutable variable into an immediate *without a semantic proof*. We should not try to brute-force that difference out of emitted assembly.

A simple **language-level** improvement is to support named compile-time integral constants (`enum`, `const` where semantics permit it, or a small explicit constant definition form) and have the front end expose them as literals to the ordinary emitter. The example also suggests auditing every other forced mismatch between the actual C algorithm/data structures and the native assembler (parallel indexed arrays versus packed record traversal, output length versus cursor, exceptional fixups). That audit should distinguish **source-algorithm costs** from **machine-code generation costs** before more architectural changes are attempted.

This test does **not** prove that a better general C compiler can always discover these global constants across separate translation units or arbitrary aliasing, nor does it explain the remaining 1,792 bytes. No production integration or VICE claim.
