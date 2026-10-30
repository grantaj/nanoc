# #102: extending the conventional 6502 emitter to words, pointers, and calls

**2026-10-30. Experimental research; not a production compiler change.**

## Question

Can the deliberately simple AST-to-6502 compiler of draft PR #120 handle useful
nontrivial Phase-1 C without importing the previous 21-layer optimisation
stack, superoptimisation, or name-specific machine templates?

## By-construction rules

`full_corpus/natural6502_wide.py` extends `Natural6502` with standard 6502
choices, not a second optimiser:

- **16-bit expression/return convention:** low byte in A, high byte in X;
  16-bit locals in little-endian memory. Ordinary low-then-high `CLC/ADC` or
  `SEC/SBC`, with the carry carried through and one temporary for the low result.
  A direct-addressable left operand is loaded straight from memory rather than
  unnecessarily round-tripping both input bytes through scratch.
- **Comparison/branch convention:** direct word high-byte comparison first,
  low-byte comparison only on ties; for signed C `int`, high bytes are biased by
  XOR 0x80. Boolean values are not materialised. Comparisons with direct zero
  use `ORA`/sign-byte checks where valid.
- **Byte and word indexed memory:** `absolute,Y` or `(zp),Y` for suitable byte
  indexes; otherwise construct a real 16-bit effective address (including
  2× scaling for word arrays). No truncation of indexes exceeding 255. Indexed
  stores preserve the value while constructing the destination.
- **Calls:** assign arguments to the existing static parameter slots, using
  A for byte arguments and A/X for words and pointers; `JSR` and receive values
  in A/X. Caller-side `__tmp` storage must not be assumed live through calls.
- **Loop and statement basics:** direct `INC` or low-byte `INC`/high-byte carry
  for `+1` on words, direct byte loop convention from PR #120, and explicit
  `break` exits for ordinary `while` loops. Unsupported cases reject and fall
  back to the mature reference backend, never silently lower incorrectly.

This is still a restricted subset emitter, **not** a production implementation
of all Phase-1 C. In particular, the largest call-rich, multi-array functions
still need a more general machine convention for arithmetic/indexing across
calls and nested expressions.

## Coverage, real code, and final image

The wide emitter now *constructs assembly* for **28/44** original `ass.c`
functions (compared with 4/44 for the first small emitter). These include:
`parse_value`, `stage_byte`, `stage_resolved_instruction`, `append_fixup`,
`find_symbol`, `process_symbol`, `scan_argument`, `assemble_data_list`,
`all_symbols_defined`, `all_fixups_resolved`, and other real word/call routines.
The fact it generates an assembly body **does not prove equivalence for all
possible inputs**; only the individually tested routines and the selected
complete image are validated as described below.

The direct `find_symbol` is 354 B versus the mature backend's 307 B. It is a
correctness demonstration for wide arrays, nested byte reads and calls, **not**
a size improvement. Other direct candidate sizes (before global optimisation):

| Function | Mature | Wide direct |
| --- | ---: | ---: |
| `parse_value` | 592 | **579** |
| `stage_byte` | 76 | **74** |
| `scan_argument` | 246 | 231 |
| `process_symbol` | 208 | 193 |
| `find_symbol` | **307** | 354 |
| `stage_resolved_instruction` | 136 | 130 |
| `append_fixup` | **213** | 291 |

The linker's initial candidate cost compares complete function machine bytes;
**outlining makes the final image non-additive**. Enabling *every* locally
smaller wide candidate yields **9,024 loaded bytes** (regression), despite
running correctly. Individual A/B of promising candidates showed `parse_value`
was profitable after global outlining, and adding `stage_byte` was slightly
better again. The other candidates are kept available for diagnosis, not
implicitly enabled.

| Physically linked complete 44-function image | Bytes |
| --- | ---: |
| Frozen recovered 6502 reference | **8,945** |
| Initial conventional byte emitter (PR #120) | **8,935** |
| **Conventional emitter + selected word/pointer/call routines** | **8,921** |
| All locally smaller wide candidates, indiscriminately selected | 9,024 |
| Original handwritten assembler | 6,905 |

The 8,921-byte experiment selects the four first-version routines (`upper_char`,
`same_text`, `short_mode_for_index`, `long_mode_for_index`) plus the generated
`parse_value` and `stage_byte`. It uses the **identical C source and runtime** as
the reference. Selection of these two functions via `WIDE_ALLOW` is a reproducible
*A/B control*, not a function-specific instruction rule. No production source
is changed. This research result is **not** a large-gap solution.

## Reproducible verification

From the unpacked `nanoc_machine_value_home_planner` experimental workspace:

```sh
sh reproduce_natural6502_wide.sh
PYTHONPATH=full_corpus python full_corpus/test_natural6502_wide.py
PYTHONPATH=full_corpus python full_corpus/test_natural_wide_properties.py
PYTHONPATH=full_corpus python full_corpus/test_natural_wide_symbol.py
```

Observed on a fresh run:

- **8,921 loaded image bytes**, pre-outline **9,950 bytes**.
- **44/44** real function assembly; **45/45** byte-matched encoded segments;
  **29/29** complete 6502-interpreter-vs-host-C assembler programs;
  **9,120/9,120** native word comparison differential tests.
- **1,388** direct interpreted 6502 word/call/pointer cases using real C functions.
- **16,258** additional independent interpreted 6502 executions of generic
  signed/unsigned word comparisons (six operators), word arithmetic (five
  operators), pointer-indexed loads and stores at page and 256-byte boundaries.
- **68** directly interpreted `find_symbol` cases (including up to 896 records)
  over synthetic parallel arrays. `scope_for_name` is stubbed here to isolate
  the traversal; the complete assembler keeps the mature `find_symbol` and is
  verified via the end-to-end suite.

**Limits:** the tests use the research 6502 interpreter, not VICE. The shared
experimental 16-byte ZP region is still hypothetical with respect to C64
ROM/KERNAL/IRQ ownership. The standalone wide emitter has not been proved
complete for arbitrary Phase-1 C and must not replace native `nanoc1.c`.

## Consequence for the compiler architecture

By-construction 6502 conventions **extend cleanly** to words, pointers and calls
without another optimisation framework. In particular, they can compile a
real multi-branch 16-bit parser routine and safely manipulate 16-bit-indexed
memory. Nevertheless, other substantial routines need their normal machine
strategies expressed explicitly, and some correct implementations are still
much bigger than mature emission. The best linked gain at this checkpoint is
24 bytes over the recovered baseline, **not** the missing ~2 KB. Continue
working on coherent word/pointer/call-rich emission *before* making production
integration decisions. Measure linked results and explain regressions, rather
than use arbitrary byte thresholds or assume a small direct-function saving is
worthwhile.
