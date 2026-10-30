# Issue #102: second-pass machine-flow experiment (2026-10-30)

## Objective

Test the **architectural** hypothesis, not another late indexed-address tweak:
read the *whole semantic tape/control-flow graph first*, choose the roles of
6502 A/X/Y, source pointer and loop-carried values, and only then emit the
chosen whole-region machine algorithm. Preserve the mature #102 backend as
an independent, exactly matched control.

This experiment changes **only the research generator**. It does not modify
production `nanoc1.c`, change the C assembler source, or assert native C64
KERNAL/IRQ zero-page compatibility. The handwritten 6,905 B assembler is the
reference, not an arbitrary stopping size.

## Two-pass implementation

`full_corpus/flow_plan.py` first reconstructs a proven CFG for a fixed-width,
short-circuit table scan from the existing *unmodified* typed tape. It checks:

* one byte induction variable, initialized to zero, incremented exactly once,
  an upper bound that does not wrap the X table cursor, and a matching return;
* fixed-width table offsets, with each of the three byte comparisons and their
  early exits linked to the correct induction variable;
* calls to a side-effect-free byte function, summarised by running **all 256**
  possible input bytes through the independent tape VM, not by assuming a
  particular helper name;
* the indexed table is initialized with A–Z bytes over the **entire scanned
  range**, with a whole-corpus array-escape/use check showing only indexed reads;
* equality against that table permits substituting `AND #$DF` for the pure
  ASCII-uppercasing helper for every byte value and A–Z table byte; this exact
  256 × 26 relation is checked before the recipe becomes eligible;
* no stray writes, indirect stores, calls, loop effects or control-flow paths
  outside the accepted scan shape. Changed bounds, changed helper semantics
  and changed table alphabet reject the plan.

The selected machine contract is X = `3*candidate + Y` in the table, Y =
character position (0..2), `__ap` = current input string pointer, with the
candidate held in a memory byte across loop backedges. The emitter uses a
single compare loop, skips to the next three-byte table entry on mismatch, and
returns the correct full 16-bit C `int` in A/X.

**Important limitation:** the current proof is intentionally conservative and
matches only this one 16-block/three-column scan shape in the 44-function
corpus. It is a real whole-region *planning-before-emission* test, not yet a
general machine-flow analysis or register allocator. It does **not** prove that
the remaining 2 KB can be recovered the same way. Whole-program checked
read-only reasoning is valid only within the present restricted C tape model.

## Controlled A/B physical executable size

Both versions use the **same 44-function C**, same original C initializers,
same mature fallback backend, same scratch allocator, layout and exact
sequence outliner. The planner is optional (`FLOW_PLAN=1`) and is chosen only
where a full-tape proof succeeds and its complete function is smaller.

| Measurement | Old | Second-pass planner | Change |
| --- | ---: | ---: | ---: |
| `find_mnemonic` *fully encoded function instructions* | 230 B | **68 B** | **−162 B** |
| Full loaded executable before outlining | 9,936 B | **9,806 B** | **−130 B** |
| Full loaded executable after outlining | **8,945 B** | **8,848 B** | **−97 B** |
| Gap to existing handwritten assembler (6,905 B) | 2,040 B | **1,943 B** | −97 B |

The 162-byte function saving does **not** translate one-for-one to the final
image; machine-flow cleanup/layout and exact-sequence outlining have different
opportunities after the replacement. The outliner saves 991 B on the
unmodified 9,936-B image versus 958 B after planning. Do not attribute a
claimed extra 162 B to the linked image.

## Correctness and negative controls

Freshly rebuilt `reproduce_flow_plan.sh` using local C compiler and Python:

* **44/44** strict native assembler function checks.
* **45/45** independently encoded byte-matching segments.
* **29/29** complete research 6502 interpreter vs native-C assembly cases.
* **9,120/9,120** native 16-bit comparison differential executions.
* **1,202** independently interpreted 6502 `find_mnemonic` cases versus the
  *original compiled host-C function*, covering the 56 mnemonics in upper/lower
  and mixed case, every possible byte in each of the three input positions,
  random non-mnemonics, source-pointer and table page crossings, length values
  outside three, and the last table entry.
* **Three negative eligibility controls:** changed table to non-uppercase,
  changed helper semantics to identity, changed loop upper bound. All reject.

The independent test interpreter was minimally extended to model actual 6502
`INX` and absolute-X table reads used by the proposed machine plan. The
native linked-image test already understands these addressing modes. The
original recovered archive and prior independent research branches are intact.

## What this does and does not establish

**Positive:** an upstream machine-flow pass can jointly plan a loop's cursor,
input pointer, comparisons, return ABI and pure callee consumption, producing
a natural 68-byte 6502 algorithm from the *same* C source for which local
patches repeatedly left 230 bytes of code.

**Negative:** a second pass is not automatically a large win. This first
recogniser applies to exactly **one of 44 functions**, and final net benefit
is only 97 bytes. We have not replaced the 21-layer backend or solved its
call-rich, wide-pointer, multi-array loops. This is a bounded architectural
proof of concept, **not** a newly assembled general compiler.

**Next discriminating test** is to formulate *transferable* region contracts
for **multiple unrelated loops with calls/multiple arrays and 16-bit
cursors**, including `find_symbol` and fixups, while keeping the current
working mature generator as the correctness and size baseline. Do **not**
accumulate source-shape recognisers or claim kilobyte savings before a general
planner demonstrably selects the right state trajectories across functions.
No arbitrary image-size targets and no production integration at this stage.

## Reproduction

From this branch's `research/issue-102/experiment/` directory:

```sh
PYTHONHASHSEED=0 sh reproduce_flow_plan.sh
```

`FLOW_PLAN` unset keeps the prior generator's 8,945-byte baseline intact.
`flow_plan_choices.json` records the plan proof and 230→68-byte comparison.
