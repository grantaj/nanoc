# Nano C machine-code quality audit — 29 October 2026

## Scope

Actual emitted code from the physically linked, **research-only** 44-function `bootstrap/ass.c` prototype (old `compact_image.asm`, 16,311 B) compared to a copy with **three generic backend changes**, including a typed-tape rewrite. No function-specific cases, no edits to production `nanoc1.c`, no VICE tests.

## Reproducible result

- Previously linked image: **16,311 loaded bytes**.
- Revised linked image: **14,940 loaded bytes** (`compact_image.prg`, **14,942 bytes including the two-byte PRG header**).
- **1,371-byte reduction (8.4%) from this audit pass**; 1,444 bytes remain before the 16 KiB code/BSS boundary.
- The 44 linked functions themselves shrink from **15,091 to 13,720 instruction bytes**. Runtime and initialised data unchanged.
- Research 6502 linker generated all symbols and branch offsets, and the **actual `bootstrap/ass.c` assembler byte-matched all 44 function segments and the retained runtime (45/45)**.
- **29/29** end-to-end linked-program interpreter comparisons against host-compiled exact `ass.c` passed. Additionally **5,600** signed/unsigned 16-bit ordering comparisons with variable and fixed right operands were checked, including zero, 255/256, `32767` and `32768`.
- These are executable research-program checks using a research interpreter, *not* production compiler emission or a native machine run. The semantic test corpus is incomplete and the empty-input research KERNAL model issue persists; no claims beyond those checks.

## Three general improvements implemented in the research backend

1. **Byte projections are views of a word, not arithmetic results.** The tape rewrites `x & 65535` into identity, `x & 255` into `low8(x)`, and `((x >> 8) & 255)` into `high8(x)` for word-sized `x`. The backend selects the low/high operand directly; unused shift/mask operations are eliminated by value-demand traversal. It also removes a nonvolatile `x = x & 65535` self-assignment. General applicability: any Phase-1 function/variable, no name tests.
2. **Keep stable source operands when possible.** Byte views are included in the existing safe deferred-load analysis, so a view need not cause an eager full-word snapshot. Existing store/call/indirect-write effect barriers remain. This is essential: ignoring the new view uses during liveness would create unsound scratch reuse, so the liveness allocator was extended to account for them.
3. **Lower all 16-bit ordering comparisons into the actual true/false successors**, comparing high bytes then low on equality, rather than constructing three intermediate less/equal/greater jump destinations. Signed compares bias sign bits; a constant high byte is biased at compile time instead of through a runtime scratch byte. Branch-distance repair and exact assembled opcode checks remain enforced.

The improvements are intended as changes to IR simplification and instruction selection, **not post-assembly peephole passes**. The preexisting generic layout pass still runs unchanged.

## Largest remaining bad machine algorithms (actual linked bodies)

| Function | New bytes | What remains wrong |
|---|---:|---|
| `assemble_instruction` | 1,460 | 220 `LDA` / 205 `STA`; repeated static call-argument staging and pointer/argument rebuilding |
| `parse_atom` | 940 | Many scalar/word temporaries; nested scan branches and full-width arithmetic where low-byte demand would suffice |
| `resolve_fixups_for_symbol` | 836 | Recomputes effective addresses into `__ap/__ix` for multiple arrays repeatedly indexed by the same word |
| `assemble_direct_value` | 659 | Full-width index and call parameter staging; repeated path-dependent loads |
| `open_include` | 630 | Pointer/index reconstruction, call setup and 16-bit arithmetic |
| `allocate_symbol` | 581 | Repeated 16-bit index scaling and address formation for parallel arrays indexed by `n` |
| `process_instruction_like` | 496 | Multi-argument call staging; the same pointer/length values repeatedly copied into callee slots |
| `find_opcode` | 165 | A 16-bit loop counter and two full address calculations per iteration where a Y-indexed byte scan is possible; handwritten ~29 B |
| `same_text` | 82 | Rebuilds `a` and `b` pointer bases in a single `__ap` instead of keeping two live cursor/pointer states |
| `upper_char` | 41 | Computes 16-bit subtraction and stores two temporaries even though return type is `char` and only A's low byte is needed; handwritten 16 B |

**Priority now:** implement (a) **low-byte-only arithmetic for results demanded solely as `char`**, (b) **loop induction/range proofs and register/index residency**, and (c) **multi-access address and call argument residency**. These should be tested as general machine plans against the whole image, not as pattern-matchers for the named functions. Do not confuse 14,940-B fit with a code-quality end condition.

## Files and rerun

- `full_corpus/byte_demand.py` contains all new general source/tape/backend code.
- `full_corpus/scratch_allocator.py` adds the new view operations to liveness source analysis.
- `link_model.py` chooses the experimental backend; **this is not part of production nanoc**.
- `QUALITY_AUDIT.csv` lists exact 44-function old/new linked distances.
- `compact_image.asm` and `compact_image.prg` are the revised fully linked candidate.
- From this bundle: `sh reproduce.sh` regenerates and checks the encoded image, 44/44 actual-assembler byte matching and 29/29 end-to-end research interpreter checks. A separate signed/unsigned comparison test script will be included.
