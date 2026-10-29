# Issue #102 research recovery checkpoint (2026-10-29)

This directory preserves the **verbatim final experimental report** from the crashed agent's ChatGPT Library. The report describes the 8,945-byte physically linked `bootstrap/ass.c` image, against the 6,905-byte handwritten native assembler.

**IMPORTANT: source code has not been recovered into this branch.** This is a report-only checkpoint. Neither this branch nor any open PR contains the complete experimental typed-tape/backend, 6502 machine selector, native compare and outlining source. The report's test claims were made by the previous research agent and have **not** been independently rerun from this branch.

## Original research artifacts

The original archives are still visible under the user's ChatGPT Library `/nanoc/`, especially:

- `nanoc_remaining_gap_codegen_experiment.zip` (634,855 bytes; created 2026-10-29 08:22 UTC), containing the final backend and `reproduce_native_compare.sh`.
- `CANDIDATE.PRG` (8,947 bytes including 2-byte load header).
- `REMAINING_GAP_REPORT.md` (copied here).
- `nanoc_outlined_machine_experiment.zip` and `nanoc_machine_value_home_planner.zip` (earlier reproduction checkpoints).

The ZIP was **not** in git as of this recovery attempt. An attempted Library raw-byte materialization returned `This Project file does not have an authorized raw-byte materialization path`; text retrieval of the report succeeded. Do not claim the source has been saved to GitHub.

## Recovery gate

1. Export or re-attach the exact final ZIP (do not recreate it from the report), inspect its manifest and checksums, and commit the complete research sources and fixtures on a separate experimental branch.
2. Execute `sh reproduce_native_compare.sh` in a clean extraction and independently verify 44/44 assembler functions, 45/45 encoded segments, 29/29 linked test programs, 9,120/9,120 comparison cases and the 8,945-byte physically loaded image.
3. Keep research-only Python tools distinct from production native `nanoc1.c`. The original archive's ZP `$30`–`$3f` mapping is hypothetical; no native VICE/KERNAL/IRQ safety is established.
4. Continue #102 from its genuine code-generation objective: comparing the remaining 2,040 bytes with the handwritten 6,905-byte assembler. Do not conflate 16-KiB fit with compiler quality, and do not merge draft PR #112 as the replacement generator.

Authoritative issue: https://github.com/grantaj/nanoc/issues/102
