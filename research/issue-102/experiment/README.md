# Nano C #102 — physically linked 16 KiB assembler experiment

29 October 2026. This is a **research prototype**, not a production `nanoc1` compiler or a verified C64-native release.

## Result

The exact 44-function `bootstrap/ass.c` from `grantaj/nanoc` was mechanically transformed into typed operation tapes and then into 6502 assembly using the experimental general backend. The resulting function code was packed into a C64 memory layout, linked with **only** the original `io-common`, `io-open`, `io-read`, `io-close`, and `__nc_init` routines, and encoded as one `.prg`.

| Property | Result |
|---|---:|
| Linked image start | `$0800` |
| Linked image end (inclusive) | `$47B6` |
| **Actual linked payload bytes** | **16,311** |
| 16 KiB limit | 16,384 |
| **Headroom before BSS** | **73 bytes** |
| C globals, locals, parameter BSS | 32,831 bytes |
| Additional test status BSS | 1 byte |
| BSS range | `$4800`–`$C83F` |
| Runtime private data | `$CE00`–`$CF1F` |
| Experimental zero-page scratch | `$02`–`$10`, `$FC`–`$FF` |
| All function bodies lowered | 44/44 |
| Strict **byte-for-byte** comparisons with the actual `ass.c` assembler | 45/45 segments (44 functions + 418-byte retained runtime) |
| Linked-machine execution vs native-compiled exact `ass.c` | 29/29 nonempty fixture programs, matching return codes and assembled bytes |

The assembled binary includes its own small experiment entry point and a fixed `TEST.ASM` input filename. The original compiler had 27,468 loaded bytes in the prior benchmark; the current experiment is 11,157 bytes smaller. The exact entry wrapper and data layout differ, so this is a cross-implementation comparison, not a byte-for-byte equivalent packaging.

### Savings relative to initial physical image

- Initial image with proven 8-byte packed scratch: **17,134** bytes.
- 45 jumps to adjacent labels eliminated, 189 safe conditional-branch/JMP pairs collapsed, and 42 proven redundant A reloads removed: **823** bytes.
- Final image: **16,311** bytes. Relative branches and all addresses were re-encoded and validated after the layout transformations.

### C64 memory model

- Code/data loaded at `$0800` through `$47B6`.
- At startup, `LDA $01; AND #$FE; STA $01` banks out BASIC ROM so reads from BSS RAM under `$A000`–`$BFFF` are correct. KERNAL and I/O remain mapped.
- `$02`–`$10` are reserved from BASIC-only zero-page workspace; this code never calls BASIC. `$FC`–`$FF` hold the existing `NC_TMP` / `NC_PTR` runtime scratch. Function-scoped temporary slot liveness proves no packed scratch value remains live *through* a C call.
- Calls pass arguments through the callee's nonrecursive static parameter slots. The three external IO functions use the unchanged runtime slots at `$CF10`, `$CF14`, and `$CF1E`.
- `__nc_init` clears all ordinary BSS before entering `ass_assemble`.

## Execution experiment

`machine_verify.py` executes **the linked 6502 binary** instruction by instruction, including the real startup, all calls and data accesses. The host simulates the necessary KERNAL jump-table calls to a device-8 file (SETNAM, SETLFS, OPEN, CHKIN, CHRIN, READST, CLRCHN, CLOSE). It checks RAM banking, branches, stacks, static parameters, and the resulting assembled image. `machine_cases.py` compares output to the **exact `ass.c` compiled with a host C compiler**.

This is **not VICE** and not cycle-accurate 6510/IEC execution. There has been no actual KERNAL ROM or physical C64 test. In particular, the empty-file prefetch behaviour remains unverified: an empty-file test does not match the host C oracle under the experimental trap implementation, and is intentionally excluded from the 29 successful cases.

## Reproduce on a host

Requirements: Python 3 with `pycparser`; a C99 compiler.

```sh
sh reproduce.sh
```

The script builds the host-executable **original** `ass.c` (using `-funsigned-char -O0` to match Phase 1 byte semantics), regenerates the 44-function tapes and output, links and encodes the program, independently assembles each function, verifies 45 linked byte segments against the original assembler, and reruns 29 linked-machine tests.

The generated artifact is `CANDIDATE.PRG`, and the resolved source is `compact_image.asm`. This research backend is in Python only; it is **not** checked into the production compiler.

## Manual VICE test

Place `CANDIDATE.PRG` and the included `TEST.ASM` in the directory VICE exposes as device 8, then load it as a machine-code image and jump to `$0800`:

```text
LOAD "CANDIDATE.PRG",8,1
SYS 2048
```

It deliberately stops in an infinite loop at `$47AC` so the VICE monitor can examine results:

- One-byte status at `$C83F` (zero means success).
- Output image begins at `$4800`.
- Output byte count is the little-endian word at `$7400`.

A real VICE test remains a **required next validation step**; the instructions above describe a manual probe, not a completed VICE test.

## Limitations / next steps

1. Run the candidate on real VICE with the actual KERNAL, native file system and IRQ behaviour. Do not equate emulated device-8 traps with ROM verification.
2. Reuse an exact, documented ABI and memory map in the actual Phase-1 C compiler backend; the present linker and operation-tape compiler are research-only.
3. Extend the oracle to include the assembler's full original test source. The 29 small programs test inter-function interaction but not the largest native assembly job.
4. Investigate the empty-file prefetch disagreement on native VICE before treating it as a runtime bug or a host model issue.
5. The 73-byte headroom is not a large margin; the ABI and entry wrapper should remain compact, but this is now a measured **fit**, not a prediction.
