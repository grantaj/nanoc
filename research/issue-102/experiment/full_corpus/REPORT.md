# Nano C: exact `bootstrap/ass.c` full-corpus benchmark

**29 October 2026 — exploratory, not a working self-hosted C64 executable.**

## What was tested

The exact 45,375-byte `bootstrap/ass.c` was exported from the `grantaj/nanoc` PR #112 checkout (head `157234ab` at export; source unchanged from successful PR #112 head `a3c0562b`). No C function was chosen or excluded by name.

The research-only `pycparser` adapter mechanically generated independent typed operation tapes for **all 44 functions**, with the entire original translation unit's 81 global declarations and the prototypes of every other function available. The same block-local and cross-block 6502 backends generated instruction streams for every function. The only added generic op classes were indexed lvalue stores, constant right shifts, C string literals, and calls used as statements. A proven infinite terminal loop is terminated by an *unreachable* synthetic return block in the research CFG.

The resulting 6502 functions were relocated into unique namespaces; static-parameter aliases were generated. The symbolic full-program listing has **791 unique instruction/data labels**, no duplicate labels, and only the expected external IO references (`io_open`, `io_read`, `io_close` and their argument slots) unresolved. No complete physical C64 address map, linked runtime, or executable binary has been produced.

## Full-corpus instruction-code results

| Generator | 44 function instruction bytes | Relative to original | 6502 instructions |
| --- | ---: | ---: | ---: |
| Existing Nano C (#112 real emitted assembly) | 25,769 | baseline | 15,649 |
| Typed tape, **block-local** | 17,778 | −31.0% | — |
| Typed tape, **cross-block** | **17,274** | **−33.0%** | **6,899** |
| Cross-block with hypothetical eight-byte zero-page reusable temps | **15,883** | **−38.4%** | — |

The 2,422 `PHA` and 2,422 `PLA` instructions in the existing machine-code baseline are absent from the new function output. This is a real structural improvement in the machine selection method. The cross-block planner saves only **504 bytes** beyond the simpler block-local version across all 44 functions; the evidence still does not make it an indispensable architectural foundation.

The **16,384-byte limit is not met**. The normal cross-block function code alone exceeds it by **890 bytes** before any runtime, initialised data, string literals, or entry point. The source declares **741 bytes of explicitly initialized global objects**, another **25 bytes** of embedded string literals, and **32,548 bytes of uninitialized global storage**. Those are *source-level object sizes*, not a verified assembler image layout. If the 741+25 bytes are loaded separately as conventional data, even the hypothetical zero-page code tally would reach **16,649 bytes before runtime**. This is not a precise whole-image measurement or a proof that future DCE/constant propagation cannot improve it.

The current baseline **loaded** image was 27,468 bytes. Assuming unchanged 1,699-byte non-function overhead purely as an illustration would give 18,973 bytes with the cross-block code; **this is not a validated linked size**.

## Strongest and weakest changes

`whole_corpus/baselines.csv` has all 44 functions. The largest remaining functions after cross-block lowering:

| Function | Old | New | Reduction |
| --- | ---: | ---: | ---: |
| `assemble_instruction` | 2,403 | 1,707 | 29.0% |
| `parse_atom` | 2,207 | 1,160 | 47.4% |
| `resolve_fixups_for_symbol` | 1,235 | 1,074 | 13.0% |
| `assemble_direct_value` | 1,013 | 860 | 15.1% |
| `open_include` | 1,260 | 760 | 39.7% |
| `parse_value` | 1,521 | 731 | 51.9% |
| `allocate_symbol` | 823 | 719 | 12.6% |
| `process_source_line` | 1,624 | 641 | 60.5% |

Other weak cases include `patch_word_chain` (450→436), `append_fixup` (416→401), `stage_plain_word_reference` (377→361), and `same_text` (100→95, because the old compiler already has a hand-selected loop). The remaining big/weak cases are dominated by wide-array indexing, function argument staging, memory effects, comparisons and multiple stored values. **Do not infer a whole-program code-quality guarantee from the strong byte routines.**

## Independent checks performed

1. The **same exact `bootstrap/ass.c`** was compiled to a host executable with a small I/O adapter, and used as the assembler. It successfully assembled **44 of 44** generated and appropriately namespaced function fixtures with unresolved globals/callees supplied only as synthetic symbol addresses. **All 44 assembled lengths exactly match** the backend's predicted lengths. This checks actual 6502 mnemonic/addressing forms, real relative branch ranges and symbol syntax.
2. The whole-program symbolic link audit found no duplicate labels and detected only external I/O dependencies. Actual function ABI implementation, physical memory allocation, and executable entry point were **not** linked.
3. The research live-range allocator succeeded for **all 44 functions** under its caller-scratch liveness restrictions: **maximum packed scratch 8 bytes**, versus a combined **658 bytes of distinct named temporary storage** in the unpacked cross-block functions. Those eight bytes are **not** mapped to proven safe C64 zero-page addresses; a call-safe C64 runtime ABI remains open.
4. In two targeted new-operation differential checks, **1,426 independent executions** of the generated `stage_byte` (wide array index/store and guard) and `apply_byte_prefix` (right shifts) matched the exact C functions compiled with a host C compiler. The interpreter is experimental, not VICE. Native host `int` is 32-bit while Nano C `int` is signed 16-bit, so C oracle inputs were restricted to domains where this difference cannot invalidate the comparison. The earlier research bundles separately verified selected large functions with other differential cases.

## What remains unproved

- **No linked C64 executable**, VICE native run or exact assembler-output oracle from the whole generated assembler.
- Production static ABI aliasing, argument widths, return convention, shared backend ZP/scratch map, physical RAM/ROM regions, and runtime routines remain to be implemented and verified as one coherent whole.
- All **44 generated functions are syntactically valid 6502** according to the actual source assembler; that does **not** imply all are semantically correct, since whole-program differential execution and call interactions have not been demonstrated.
- There is no verified fit within 16 KiB. The plain code already exceeds the budget, and the hypothetical zero-page version does not include initialized data/runtime.
- The host research adapter and backend are not suitable as production Phase-1 C compiler code. Production changes are **not** justified merely by these output numbers.

## Verdict

This is a useful whole-program **negative-and-positive** result: the typed tape is broadly expressive and radically eliminates stack traffic; the simpler block-local backend gets most of the savings; yet the current design still does **not** produce a compact, runnable assembler. The remaining code size is not a parsing problem. The next serious test is an ABI-correct, function-at-a-time C64 packaging/linking plan and a smaller whole-program runtime+data strategy, coupled with machine planning for the worst remaining routines. That test might still falsify the architecture. There is no justification to declare the redesign complete.

## Reproduce

In an environment with `python3`, `pycparser`, and C compiler:

```sh
sh run_full.sh
```

`full_corpus_benchmark.py` writes all 44 variants and `coverage.csv`; `link_audit.py` builds a symbolically namespaced combined listing; `strict_asm_probe.py` assembles each using the actual `ass.c` host build; `scratch_audit.py` checks per-function liveness and scratch capacity; `new_ops_tests.py` executes the two new operation tests. The base assembly `n1-ass.asm` was recovered directly from PR #112's successful native CI artifact, not recomputed by a test-only compiler.
