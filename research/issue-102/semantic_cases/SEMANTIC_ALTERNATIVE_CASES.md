# #102 — three genuinely different 6502 computations hidden by one typed tape

2026-10-30. **Diagnostic analysis and one executable 6502 fragment A/B, not a compiler optimisation or a full-image improvement.** Compare to the archived physical 8,945-B research assembler. No production compiler changes.

## What was inspected

- The *actual* `full_corpus/exact_source/ass.c`, corresponding `full_corpus/whole_corpus/{find_mnemonic,stage_byte,find_symbol,resolve_fixups_for_symbol,allocate_symbol}.c` typed-tape inputs, and the archived **physically linked** `compact_image.asm`.
- The research `full_corpus/tape_frontend.py` builds typed `load`, `read`, `arith`, `store`, `call` operations, but does not preserve a cursor invariant as a first-class alternative. Its `ArrayRef` lowers to `read(base, index)`; the eventual addressing selector can choose *(zp),Y* for simple indices but cannot replace arbitrary repeated indexes with an evolving pointer by selecting a single instruction.
- The actual BSS addresses from `symbols.json` for the **specific linked baseline**; these are not assumed to be true under another program layout.

## Case A: `find_mnemonic` — contextual equivalence, not just address scheduling

The C source says `offset = candidate * 3`, then separately evaluates three `upper_char(name[k]) == mnemonic_table[offset+k]` expressions. The emitted 6502 function is **230 B before outlining**, with repeated calls and indexed lookups. The existing two-pass experiment in draft PR #115 generated a **68-B complete function** with X carrying table position and Y carrying character position. The full original 44-function image fell **8,945 → 8,848 B**, with machine differential tests already committed in #115. **No new size reduction is claimed here.**

The critical equivalence is not `upper_char(c) == (c & $df)` in general—that is FALSE for non-letters. It is **contextual**: when comparison target `t` is an ASCII uppercase letter A–Z, `upper_char(c) == t` is equivalent to `(c & $df) == t` for all byte `c`. A search over the instruction sequences after the `upper_char` call cannot discover that replacement. The search needs alternative semantic expressions, restrictions on table contents, and loop-carried register contracts.

## Case B: `stage_byte` — whole-program value-representation invariant

C source:

```c
if (ass_image_length >= 11264) return ASSEMBLE_WORK_FULL;
ass_image[ass_image_length] = value & 255;
ass_image_length = ass_image_length + 1;
return ASSEMBLE_OK;
```

The actually emitted `stage_byte` is **76 instruction bytes**. It reconstructs the full address of `ass_image + ass_image_length` on every call, stores through `(zp),Y`, then increments the length separately. There are **18 static `JSR stage_byte` call sites** in the archived assembly. The BSS linker places `ass_image=$4800`, `ass_image_length=$7400`.

A different machine computation is to maintain a **persistent cursor** `P = $4800 + ass_image_length (mod 65536)`. On reset, set `P=$4800`; a successful `stage_byte` stores through `P` and increments both `P` and the logical length, or replace the length's representation with `P-$4800` and derive length at its other consumers. An AST audit finds the **only direct assignments** of `ass_image_length` in `reset_assembler` and `stage_byte`. Other functions read it and write staged image bytes, but do not modify the count. Thus this is a well-defined candidate whole-program invariant, not a heuristic reuse of `__ap` across calls.

**Caveat:** keeping both `P` and the length may itself be larger than reconstructing the pointer; eliminating the redundant counter imposes conversion costs on the other length consumers. Its profitability is a **whole-program representation decision**, not decided by comparing one instruction pair. The pointer also needs a persistent, call-safe location with a proven reset/alias contract. A subsequent [full-image C pointer-cursor A/B test](../semantic_alternatives/TROUBLESOME_CASES.md) has now been performed: adding an explicit persistent cursor while retaining the length increased the 44-function physically linked image **8,945 → 8,975 bytes** (+30), with 44/44, 45/45, 29/29 passing and original-vs-modified host C output matching byte-for-byte on all 29 fixtures. This demonstrates the cost of *duplicating* representations, not the cost of replacing the length everywhere with a cursor; that larger program-wide substitution remains untested.

## Case C: `resolve_fixups_for_symbol` — shared affine addresses and call boundaries

The original C loop uses `fixup_kind[i]`, `fixup_symbol[i]`, `fixup_addend[i]`, `fixup_prefix[i]`, `fixup_stage[i]` for the *same* 16-bit `i`, iterating up to **640** entries. The emitted 6502 function is **617 B** (pre-outline function-body instruction bytes) and rebuilds several indexed addresses. Calls to `apply_byte_prefix` and `relative_byte` intervene; the current temporary `__ap` address cannot simply be assumed preserved across them.

In the archived BSS layout:

```
fixup_kind   = $b314       one-byte elements
fixup_stage  = $b594       two-byte elements
fixup_symbol = $ba94       two-byte elements
fixup_addend = $bf94       two-byte elements
fixup_prefix = $c494       one-byte elements
```

The three **two-byte** columns all have the *same low address* (`$94`) and differ by whole-page steps (`$0500`). For any index 0..639, their effective addresses satisfy:

```
q = (2*i) mod 65536
p_stage  = $b594 + q
p_symbol = p_stage  + $0500
p_addend = p_symbol + $0500
```

The **low pointer byte does not change** when crossing between those columns, even as `i` crosses byte and page boundaries. A more economical plan can calculate `q` once, read one field through a pointer, and retarget only the pointer's high byte for the other fields. For the *call-free three-field read fragment* the test `address_relation_probe.py` constructs two concrete 6502 instruction sequences:

| Variant | Native host assembler | Instructions |
| --- | ---: | ---: |
| Independently reconstruct all three word addresses | **114 bytes** | 57 |
| Compute once, then retarget high pointer byte | **78 bytes** | 39 |

Both versions are executed in the test's small explicit 6502-instruction interpreter for **1,920 independent input cases each** (all 640 indexes × 3 independent random word triples), comparing all three loaded 16-bit values to the expected memory contents. The **36-byte saving is for the isolated *pre-outline* fragment only**, not for `resolve_fixups_for_symbol` as linked and absolutely not a new 36-B executable reduction. The proof relies on known linker array bases and no intervening clobber of the selected zero-page pointer; it cannot be dropped unchanged into the entire function across the existing calls.

The same family appears in `allocate_symbol`, which writes five distinct symbol-table arrays at common `n` in one CFG basic block (no intervening function call). The arrays have mixed 1- and 2-byte element sizes and different low base bytes. That requires choosing shared scaled indexes and retargeting multiple address states, not only this special `$0500` field step.

## The actual missing search variables

The proposed search **cannot** only track `(A,X,Y,flags,what __ap currently holds)`. To express these cases generally it also needs *relationships* between semantic values, independently of their current homes:

- `address = base + scale*index + displacement (mod 65536)`; relative differences between several bases; exactly which layout facts are known;
- `cursor_next = cursor + element_stride`, with proof tying its value to the original C index around the backedge;
- materialized integer versus maintained pointer as two alternative **representations of the same logical quantity**, not two schedules of existing `LDA`s;
- contextual equivalences and range assumptions for consumers (e.g. comparing ASCII uppercase only);
- effects at calls/joins, including which abstract facts remain valid and whether scratch pointers are clobbered;
- whole-program variable representation when a value is used in multiple functions, including reset sites.

This is an **alternative computation graph** question. Tree covering is appropriate for local expression alternatives, but long-lived cursors require dataflow/induction relationships and costed region contracts. A finite search over already emitted 6502 *cannot* invent them.

## What this audit establishes and does not

It establishes **three distinct required categories of semantic alternatives**, and tests one concrete related-address pair of machine computations with the real 6502 assembler and exhaustive-index simulation. It also corrects the simplistic claim that simply holding two pointers suffices for the real multi-table loops. It **does not** establish another whole-program code-size win or prove that all remaining 2,040 bytes are eliminable by compiler changes.

An appropriate next *implementation* experiment is a **general affine-address state** (base, scale, index identity, displacement, validity) over a call-free *multi-column region* such as `allocate_symbol` or part of fixup resolution, with true 6502 emitted code, explicit state contracts and the full 44-function / 29-case linked oracle. It should demonstrate useful effects on multiple independent regions and compare pre/post outlining, rather than hardcode these field names.
