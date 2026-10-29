# #102 — whole-function machine-value homes, not local register caches

**Date:** 2026-10-29. Research compiler only; production `nanoc1.c` is unchanged.

## Decision being tested

Instead of giving each Phase-1 C local and formal parameter a distinct static home and only then attempting to eliminate its loads, assign *physical machine homes* after a whole-function liveness / interprocedural call-graph proof:

- A: forward must-available value and NZ flags across all CFG predecessors, with hard clobber barriers.
- X or Y: an *actual register home*, eliminating the original scalar's STA and LDA, only when a byte local is defined on every path, never crosses a clobber, and does not steal an existing hardware live value. (The present conservative implementation finds eight profitable cases.)
- Zero-page: a small **shared 16-byte register file** for private scalar locals/formals chosen by instruction-frequency-per-byte and interference. Values with disjoint lifetimes or disjoint active call stacks may share a physical byte or word. Interfering values may not. Parameter staging aliases follow each callee's chosen physical home. All globals, arrays, data and non-promoted locals remain at their prior addresses.

This is a genuine alternative **value-location assignment** over the whole call graph, not an attempt to recognise the spelling of an individual C function. It is still a research-stage *post-emission* allocator, not yet a native C tape-to-machine backend or a general optimal register allocator. The 16-byte ZP window used here is a counterfactual storage hypothesis, not a claim that $30–$3f belongs to the program under actual KERNAL/IRQ operation.

## Measured linked-image results

| Machine model / transformation | Loaded bytes | Saving vs preceding | Ratio to handwritten 6,905 B |
|---|---:|---:|---:|
| Research assembler with existing final-byte-in-A call ABI | 11,562 | — | 1.674× |
| Whole-CFG dead homes + A/NZ value flow | 11,430 | 132 | 1.655× |
| Above + 16-byte call-graph-aware live-range ZP homes | 10,358 | 1,072 | 1.500× |
| Above + X/Y as actual byte-local homes where proven safe | **10,321** | **37** | **1.495×** |
| Handwritten native `ass` | **6,905** | reference | 1.000× |

**The new value-location strategy eliminates 1,241 loaded bytes (10.7%) from the immediate previous candidate.** The remaining gap is **3,416 B**. The old initial `nanoc1` output was 27,468 B (3.98×), so the research work has closed a large part of that gap, but not all of it.

The 16-byte pool places **142 distinct C scalar values** into 16 physical bytes without overlapping provably interfering lifetimes (135 when register homes first eliminate some scalar memory traffic). The location allocator sees 991 hot references in the ZP-only variant and 963 in the combined variant. The selected values include 16-bit word locals: the allocation checks *byte interval overlap*, not merely equal starting addresses.

**Saturation test:** with only 8 hypothetical ZP bytes, the A-flow result is 10,560 B (also 29/29 end-to-end); with 16 bytes it is 10,358 B (29/29). A 24-byte layout probe yielded 10,258 B but did not complete the full program oracle test in this session. The modest marginal returns show why growing this pool indefinitely will not explain the final ~3.4 KiB.

## Executed validation

- Exact entire `bootstrap/ass.c`: **44 of 44** compiled functions assembled by the original host-built assembler.
- **45/45** assembled segments (44 functions and the original I/O runtime) byte-for-byte match that assembler.
- **29/29 linked binary execution cases** agree with exact native-host-compiled C on return status and output image.
- Repeated full 29-program runs with the same 16-byte live allocator at two *different* hypothetical ZP bases (`$11` and `$30`), identical loaded size **10,358 B**.
- Combined register-home + 16-byte shared pool at `$30`: **10,321 B**, 29/29, 44/44, 45/45.
- An **independent interference checker**, using machine instruction CFG + source parameter signatures, validates **3,658 interfering pairs** over **5,229 machine positions** and 69 C call edges, checks the physical ABI aliases, and rejects an intentionally corrupted allocation.
- Six adversarial register-as-home tests include: call clobber, other X use, uninitialized CFG join, flag-sensitive store, later X clobber, and a valid straight line.
- The adversarial branch test found a *research parser weakness* for dot-prefixed internal labels; the machine-CFG label recognizer was updated. The actual generated C code uses `__F_*` labels, so this correction does not change the measured image, but prevents silently accepting an unsafe alternate-entry path in the general planner.

All these checks execute the experimental linked program in a research 6502 instruction model. They do not prove that the chosen ZP locations are safe under actual C64 ROM/IRQ calls, nor that an untested Phase-1 program is correct. No VICE testing was requested or performed.

## Why this matters, and what it does *not* demonstrate

This shows that **reassigning physical homes is materially stronger than retaining A or X/Y after an ordinary load**. The strongest effect is overlapping lifetimes in a bounded shared ZP window. Unlike prior independent static locals, the same 16 hardware bytes can serve more than one hundred C values, with a proof that callers and active callees do not clash.

However, it also places a useful boundary on this design: after the new plan, the emitted image still contains about **4,508 instructions**, including **1,419 LDA, 1,011 STA** and **978 references to private static locals/params**, **247 to call slots**, **320 to scratch temporaries**, and **352 to the address/index scratch**. These counts are not claims that each instruction is redundant, but they identify the repeating families that remain.

The most costly current functions are `assemble_instruction` (991 B), `parse_atom` (717 B), `resolve_fixups_for_symbol` (542 B), and `open_include` (510 B). The current machine planner leaves the majority of those bytes intact. The remaining difference is not a proof that C or the tape inherently needs 1.5× handwritten size.

**Key architectural verdict:** the live-range / interprocedural placement is worth keeping as a *candidate machine-home mechanism*. The register-as-home subproblem is currently too conservative to add substantial code-size benefit (37 B). We should not invest in squeezing another 30 B from it. The next discriminating work should compare a truly different *function/region machine algorithm*—including how signed word results, call status, and repeated word-array accesses are represented—rather than append more A/X/Y caches. Source-level representation differences versus the native assembler also remain to be quantified.

## Reproduction

`sh reproduce_machine_homes.sh` in this directory regenerates the **10,321 B** PRG from the exact Phase-1 source, cross-checks 44/44 function assembly and 45/45 segment bytes with the repository's original host-built assembler, runs the 29 linked-machine program cases, tests register-home refusals, checks the CFG/call-graph interference proof and negative injection, and asserts the final byte count. Requires Python 3, `pycparser`, and the included host-assembler fixture. Output is `CANDIDATE.PRG` (**10,323 B with two-byte load-address header**) and `compact_image.asm`.

`live_home_allocator.py` is intentionally small, explicit research machinery; `register_home.py` demonstrates the alternative physical X/Y homes with must-availability proof; `verify_location_interference.py` is an independent checker, not part of the allocator. A separate baseline in the prior experiment is 11,562 B with A-only final-char ABI.
