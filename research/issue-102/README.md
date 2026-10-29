# Issue #102: recovered experimental 6502 backend

**Status:** Preserved, independently reproduced research prototype; **not** integrated into production `nanoc1.c`. This branch is an archival and review checkpoint, not a production implementation PR.

## Contents

- [Original, byte-exact experimental ZIP](nanoc_remaining_gap_codegen_experiment.zip): complete previously generated 2.45 MB workspace, including all code, generated assembly, fixtures and binary images, as uploaded after the previous agent crashed. ZIP SHA-256: `3466aa5cf0335340c04e0a87260a572ed7961602475c5aae86a338959597ea30`; Git blob SHA-1: `b981eee81d334cf7fdd0508948dd1d5ba037c4db`.
- [Inspectable experimental sources](experiment/): 188 unpacked Python/C/shell/Markdown/JSON/CSV/patch/text files. Intermediate machine-code listings, binary oracles and non-source outputs remain in the canonical ZIP.
- [Original experimental report](REMAINING_GAP_REPORT.md).
- [Independent recovery validation](VALIDATION.md), including exact reproduction, expected checks and caveats.

The original ZIP is intentionally **unmodified**. The extracted `experiment/reproduce_native_compare.sh` adds an explicit `PYTHONHASHSEED=0` pin, because Python iteration ordering changed 147 encoded bytes between otherwise passing builds. With that seed, the regenerated 8,947-byte PRG matches the archived `CANDIDATE.PRG` byte-for-byte.

## Independent reproduction

```sh
unzip nanoc_remaining_gap_codegen_experiment.zip -d /tmp/nanoc102-recovery
cd /tmp/nanoc102-recovery/nanoc_machine_value_home_planner
PYTHONHASHSEED=0 sh reproduce_native_compare.sh
```

Expected: `FINAL 8945 bytes 44 functions 45 segments 29 cases`. The test also reports `PASS 9120` differential comparison executions. See [VALIDATION.md](VALIDATION.md).

The benchmark is the actual handwritten `ass` image **6,905 B**. The generated research program **8,945 B** is 1.295× that size, with **2,040 B still to explain**. The 16 KiB code region is only a runtime feasibility constraint, not the optimisation target.

## Safety and development separation

The research backend is **host Python**, testing 6502 output, not the Phase-1 C native compiler. Its 16-byte zero-page `$30-$3f` pool is hypothetical and is **not** proven safe across C64 KERNAL, IRQ and device-8 operations. Executions are in a research 6502 interpreter, **not VICE**. Whole-program instruction outlining introduces JSR/RTS depth and has its own preconditions. Do not substitute this binary for the production assembler or merge the research emitter into `nanoc1.c` without a native correctness and memory-safety plan.

Keep draft [PR #112](https://github.com/grantaj/nanoc/pull/112) distinct; its limited loop selector is not this backend. The authoritative architecture/quality target is [issue #102](https://github.com/grantaj/nanoc/issues/102).
