# #102: inspect the semantic alternatives that our searches could not choose

**2026-10-30. Independent research analysis, not a production backend change.**

## Question

Can we identify materially different *machine computations* for several real assembler functions, rather than trying to re-schedule already-emitted instructions? Do they reliably save size once all live values, calls, control flow and the code outliner are included?

The answer is **mixed**. A whole semantic transformation produces a major reduction for one function; a superficially sensible cursor transformation **makes the complete image larger**; and an exact small search finds a compact addressing plan for a pure fixup field-load fragment, but its assumptions do not hold throughout the actual fixup function. **No broad code-generation mechanism or kilobyte-scale result is established by this study.**

## Controlled experiment 1: output staging, `stage_byte`

**Original C source:** `ass_image[ass_image_length] = value & 255; ++ass_image_length;`, guarded by the full 11,264-byte image bound. **Alternative C source:** introduce `char *ass_image_cursor`, initialise it to `ass_image` in `reset_assembler`, write `ass_image_cursor[0]`, then increment the cursor *and* the original length. This is the most literal expression of the native `stagingPtr` idea without changing the rest of the C program or the compiler.

The experiment modifies the actual `full_corpus/ass.c` **and** the two corresponding per-function compiler inputs, leaves every backend pass unchanged, and builds fully independent physical 6502 executables from the exact recovered ZIP.

| Complete machine image | Original C | Persistent C cursor | Delta |
| --- | ---: | ---: | ---: |
| Before machine-sequence outlining | **9,936 B** | 9,966 B | **+30 B** |
| Final physically linked image | **8,945 B** | 8,975 B | **+30 B** |
| `stage_byte` per-function code before outlining | 76 B | 96 B | +20 B |
| `reset_assembler` per-function code before outlining | 78 B | 88 B | +10 B |

**Tests rerun from a fresh ZIP:** both variants 44/44 strict native-assembler functions; 45/45 byte-matched encoded segments; 29/29 full 6502 interpreter program cases; 9,120/9,120 comparison tests. The original host C and cursor-source host C return identical statuses and bytes on the 29 source cases. An additional independent host-level boundary test stages **11,264 bytes into each implementation**, verifies the entire byte image and returned length, then verifies that the next write returns work-full status **11** in both.

**Why this matters:** the pointer does not replace the length! The C program needs the length as an externally visible offset for staging, labels and fixups, so the modified C now maintains **two related 16-bit quantities**, `cursor == ass_image + ass_image_length`. Making the cursor an independent C variable adds instructions. A planner must decide *which representation is primary* **and how other consumers recover the other value**. Locally replacing index calculations with a cursor cannot succeed if the other state remains independently live. The result does not prove a better compiler couldn't transparently retain the same relation and avoid one of the updates.

## Controlled experiment 2: related fixup fields and affine address search

The actual recovered physical layout contains:

- `fixup_stage` at `$B594`, **stride 2**
- `fixup_symbol` at `$BA94`, **stride 2**
- `fixup_addend` at `$BF94`, **stride 2**
- `fixup_prefix` at `$C494`, **stride 1** (must NOT be folded into the same scaled-index equivalence class)

The three word-array bases are **five pages apart and share their low byte**. Thus for a single unchanged `i`, a machine state may retain the relationship `ptr = base + 2*i` and retarget to another word field just by adding five to the pointer's *high byte*. This is not the same as choosing `(zp),Y` for three unrelated addresses.

A small exact bitmask-DP search (`affine_strategy_search.py`) offers two genuine alternative recipes for each field: recompute `base + 2*i`, or retarget the current pointer by a proved whole-page constant, subject to clobber checks. It considers all field orders and costs **real 6502 instructions** using their encoded widths. It chooses **fresh / retarget / retarget**:

| Independent three-word-load fragment | Machine bytes | Instructions |
| --- | ---: | ---: |
| Form three complete addresses | **114** | 57 |
| Form one address, retarget two page deltas | **78** | 39 |
| **Difference before outlining** | **36** | 18 |

The same two generated sequences each passed **1,920 independent memory-execution cases**: indexes 0..639 including page boundaries, three random 16-bit field tuples per index. The `retarget` recipe explicitly refuses base addresses with unequal low bytes. A forced clobber barrier between two accesses makes that two-field fragment **76 bytes instead of 58** because the pointer must be recomputed. Exact DP proves optimality **only among this small specified recipe set**, not among all 6502 programs.

**Major limitation:** this is an **isolated pure-read fragment**, not an implementation of `resolve_fixups_for_symbol`. The actual function branches between accesses, reads more fields of different strides, calls `apply_byte_prefix` and `relative_byte` on certain paths, and writes `ass_image` and `fixup_kind`. These effects can invalidate A/Y/`__ap` or the relevant alias assumptions, so the whole ideal 36-byte saving cannot be claimed. It will also interact with the outliner. The physical array base relationship itself may change under alternative layouts and requires a linker-preserved placement proof.

## Controlled experiment 3: fixed-width table scan, `find_mnemonic`

This is a **previously verified positive control**, not a newly claimed saving in this study. The earlier independent `issue-102-two-pass-flow-experiment` proved the entire 16-block scan and lowered it to an X/Y table-cursor loop, including all early-exit paths and exact result ABI:

| | Mature backend | Before-emission whole-loop plan |
| --- | ---: | ---: |
| `find_mnemonic` function code | **230 B** | **68 B** |
| Complete image after outlining | **8,945 B** | **8,848 B** |

It passed 1,202 machine-level differential cases and the complete assembler tests. Its important transformation is **not just addressing**: the plan proves that `upper_char(ch) == uppercase_table_byte` may be replaced by `((ch & $DF) == uppercase_table_byte)` for the allowed uppercase table alphabet, so *three helper calls* can be removed. Without the exact semantic relationship, cursor planning alone cannot yield the same result. The current proof only recognises one narrow three-column short-circuit scan; it is not a generic optimisation.

## Two more troublesome functions examined (not rewritten in this study)

- **`find_symbol`:** 22 tape blocks / 82 ops, one `scope_for_name` call before traversal, five indexed reads, nested `i` (16-bit, up to 896) and `j` (byte) induction, and independently laid-out parallel arrays with **different strides**. The candidate strategy must coordinate an outer word index, an inner byte index, record fields and the name-text pointer across a nested loop; the existing one-cursor loop recogniser cannot express this contract. Baseline unoutlined function code is **307 B**. Earlier packed-record C A/B trials made the full image **409 B larger** for the symbol-only variant, so it is not justified to assume rewriting source alone fixes this.
- **`parse_atom`:** 85 tape blocks / 317 ops, 18 indexed reads, three calls, 18 exits, loops for hexadecimal/decimal digits, and width-sensitive arithmetic. The recovered output **already uses `(zp),Y`** on its byte text reads and native `ASL/ROL` on its 16-bit hex shift. This disproves the simplistic story that all remaining cost is failure to pick indexed opcodes. The larger issue includes flag/result protocols across calls and arithmetic, multiple early-exit paths and intermediate state. Baseline unoutlined function code is **832 B** (557 B after outliner in previous audit).

## Common representation that covers these cases

A machine planner needs to preserve **relationships and effects**, not just the current register contents. A minimal abstract candidate is:

```
Affine value:  base + scale * i + constant   [width, bounds, provenance]
Value location: A / X / Y / flag / ZP pointer / memory
State relation: cursor == ass_image + ass_image_length
Control effect: call / possible indirect write / branch / loop backedge
Required observations: bytes, status, live scalar, carry/zero on the consuming edge
```

An alternative recipe may rewrite the *semantic computation* (e.g., case-folded table comparison), create or advance an affine cursor, materialise an index only when actually observed, or keep the original scalar algorithm. To choose correctly, the cost must include **setup, preservation across effects, spills, restoration at joins/backedges, and all other consumers**. Bare register-state DP or post-emission peepholes cannot solve this problem; blindly keeping a cursor also fails.

**What this experiment establishes:** The right search space contains genuinely different machine computations; those differences can matter a lot in one function (positive scan control), have **negative global cost** when the added state must coexist with other live values (stage cursor A/B), and offer strictly conditional savings when a shared affine relation survives (fixup fragment). It does **not** yet demonstrate a general costed selector or a further valid whole-image reduction. A credible next experiment would choose one complete multi-block function, carry these relations through *all* CFG edges and calls, and compare an independently executable complete function before applying the code outliner. We must not return to chains of isolated 30-byte patches or invent an arbitrary size target.

## Reproduction

This directory includes a byte-for-byte source patch and a clean two-image build harness. From a checkout of this branch:

```sh
sh research/issue-102/semantic_case_study/reproduce_cursor_ab.sh /path/to/nanoc_remaining_gap_codegen_experiment.zip
```

The script extracts the original ZIP into a temporary workspace, builds the two programs independently, runs 44/45/29/9120 checks, compares host-C results, stages all 11,264 bytes plus the overflow boundary, and runs the independent 1,920-case affine-address DP/machine test. No native VICE or physical C64 KERNAL/IRQ safety claim is made.
