# Issue #102 — calibrate compiler codegen against a handwritten implementation of the **same** C algorithms

**2026-10-30. Research controls, not production changes.**

## Why this changes the experiment

Comparing a generated `bootstrap/ass.c` assembler against the existing 6,905-byte handwritten `ass` program conflates differences in instruction selection with changes to data structures, control flow and programming interfaces. The native assembler uses variable-length packed symbol records and pointer-traversal conventions; the restricted Phase-1 C source uses parallel arrays and 16-bit indexes. Neither code generator alone can reconcile these different source-level computations.

This experiment asks a narrower, falsifiable question: **how many bytes does the compiler waste on the exact same C algorithm and ABI**, with identical globals, and no source-level program rewrite? Replace just two generated functions with reasonable handwritten 6502 following the original C arrays and call convention. These hand implementations are examples, not proven size optima.

## Controls

1. `find_symbol`: preserve `symbol_scope[896]`, `symbol_name_length[896]`, `symbol_name_offset[896]`, `symbol_name_bytes[9344]`, the signed `-2/-1/index` returns, the static source-name pointer ABI and `scope_for_name` call. The manual 6502 maintains a scope and length cursor, then temporarily repurposes two ZP pointer pairs for a full byte-string comparison, restores cursor state, and advances the 16-bit symbol index. No native packed records. The compiler's source scans the full name even after a mismatch; the manual code exits the comparison early (a semantics-preserving control-flow improvement for immutable input names).
2. `stage_byte`: preserve `ass_image[11264]` and the scalar `ass_image_length`, including its use by unrelated C functions, the byte-argument A calling convention, byte store and increment, and error `ASSEMBLE_WORK_FULL=11`. The manual 6502 calculates `ass_image+ass_image_length`, does a `(zp),Y` store and increments the *same length*. It does **not** introduce the native assembler's persistent output pointer or a different representation.

All surrounding code, the runtime, the initialized tables and the rest of the backend are unchanged. The two replacements are applied **after** existing compiler backend machine-flow, register-home and shared-ZP passes, so these hand implementations use the same final physical symbol/ABI mappings as the generated code. Standard layout and outliner are then run identically.

## Physical results

| Same source/ABI and global arrays | Existing compiler | Hand-coded controls |
| --- | ---: | ---: |
| `find_symbol` physically encoded after outlining | 244 B | **226 B** |
| `stage_byte` physically encoded after outlining | 76 B | **48 B** |
| Whole image before outlining | 9,936 B | **9,878 B** |
| Whole image after outlining | **8,945 B** | **8,895 B** |

The two complete bodies reduce by 46 physical bytes after outlining; changes to shared outlined helpers and layout yield a **50-byte reduction in the final linked image**. The controlled `find_symbol`-only swap was tested separately: linked 8,923 bytes, and it passed full 44/45/29 checks.

## Correctness

- Strictly assembled **44/44** functions, independent **45/45** encoded segments, **29/29** complete 6502-executed assembler programs vs the unchanged host-C oracle and **9,120/9,120** word compare cases.
- Independently machine-executed `find_symbol`: **116** calls with 0, 1, 2, 16, 127, 255, 256, 257, 512, 895 and 896 entries, zero/negative/positive return values, matching and nonmatching strings, local-scope behavior and page-crossing string pointers. Checked against the original C algorithm's result.
- Independently machine-executed `stage_byte`: **60** calls at output indexes 0, 255/256, 511/512, 4,095/4,096 and 11,263/11,264, returning status and confirming the output byte and updated length. All tests use the 6502 research interpreter rather than VICE.

## Interpretation — what follows and what does not

**Meaningful negative result:** two visibly troublesome C functions, when written manually in fairly ordinary 6502 *with their existing algorithms and ABI*, save **only 50 linked bytes combined**. This does not prove the generated code is optimal. In particular the native assembler's symbol records and staging pointer may yield much shorter *different* algorithms, and these hand samples are not certified minima. It establishes that the previous research path of eliminating a couple of LDA/STA sequences in these same routines is unlikely to explain the 2,040-byte program gap.

**New discriminating question:** make an apples-to-apples size decomposition across a representative set of the largest functions. For each function, compare generated C algorithm versus a manually coded 6502 control of **the same algorithm and ABI**. Separately compare the resulting control against the native assembler's *different algorithm*. Where the first gap dominates, fix a compiler convention; where the second dominates, make the 6502-native algorithm expressible and natural in Phase-1 C (or acknowledge the source-program mismatch). Do not resume generic searches or local 10-byte patches without that evidence.

## Reproduction

From the archived issue #102 research branch (`research/issue-102/experiment`, sourced from the original ZIP), put this directory at `research/issue-102/same_algorithm` and run:

```sh
sh reproduce_native_compare.sh  # unchanged control = 8,945 B; from experiment/
sh ../same_algorithm/reproduce_same_algorithm.sh # candidate = 8,895 B; from experiment/
```

No changes are made to production `nanoc1.c`; these files are an independent research artifact. The research emulator does not model all C64 hardware/ROM/IRQ interactions.
