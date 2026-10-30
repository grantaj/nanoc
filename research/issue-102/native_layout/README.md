# A new C assembler based on the handwritten 6502 design

**Status:** first independent Phase-1 C source variant, `bootstrap/ass_native.c`. **Do not replace** `bootstrap/ass.c` yet. This experiments with the assembler *algorithm and data representation*, not a new compiler optimisation pass.

## What is different

The original C assembler was implemented with a structure-of-arrays symbol table (name offsets, lengths, kinds, scopes and payloads), and five parallel fixup arrays. The original handwritten `ass/symbols.asm` and `ass/representation.asm` instead use stable variable-length inline-name records and eight-byte exceptional fixup records descending within the output workspace.

This C implementation follows that design:

- **Symbol records:** contiguous bytes `[length, payload_lo, payload_hi, kind, scope, name...]` in `symbol_records`. The return value from symbol lookup/allocation is a *stable record offset*, not a numeric table row. `find_symbol` maintains a record pointer, compares names in place, and advances over the previous record length. All consumers (`parse_atom`, `intern_label`, `define_label`, `stage_plain_word_reference`, fixup resolution, all-symbols-defined) use the record identity consistently. The payload is mutually exclusive value or forward-chain head as in the native assembler. An additional **scope byte** retains the original C program's numbered local scopes; the native assembler distinguishes scope using separate arena lifetimes instead.
- **Fixup records:** `[kind, stage_lo, stage_hi, symbol_lo, symbol_hi, addend_lo, addend_hi, prefix]`. They are placed at descending addresses within the same 16-KiB `ass_image` staging buffer. All scans and consumers use these packed records, and resolved newest records can be reclaimed from the high end.
- **Output staging:** `staging_cursor` increments directly on output, with `ass_image_length` retained because it is used by other functions for origin arithmetic, relative branches and output length. The two representations are not yet reduced to one; the native assembly likewise maintains distinct staging and assembly-address pointers.
- **Compatibility:** retains the original program's 11264-byte output, 640-fixup, 896-symbol and 9344-name-byte limits, plus status codes and the existing assembler grammar. No `struct`, casts, preprocessing, recursion or other additions to Phase-1 C.

This is a *real change to the C algorithms* rather than an AST or machine-optimiser experiment. It does **not** yet implement the native assembler's separate local/global symbol lifetimes, banked RAM arena, or carry-flag result ABI. Those should be approached separately after this source is stable.

## Verification

From the repository root:

```sh
python3 research/issue-102/native_layout/test_ass_native.py
```

The test compiles **two independent host C libraries** from `bootstrap/ass.c` and `bootstrap/ass_native.c` with the same existing `bootstrap/ass_host.c` host I/O adapter. It compares return statuses and every emitted byte on **89 source programs**, including valid input, errors, forwards, local names, loops of 200 unresolved names, many mixed fixups, page boundaries and randomized assembly. It additionally checks 896 symbol allocations, original symbol-ID-independent lookup behaviour, forward word chains, 640 exceptional fixups and the 11264-byte output capacity. Run with `cc`, Python 3 and no target emulator.

Separate experimental research-tool reproduction from the archived issue-102 research backend:

| Result | Original `ass.c` | New `ass_native.c` |
| --- | ---: | ---: |
| Functions lowered to typed tape | 44/44 | **48/48** |
| Linked full executable size | **8,945 bytes** | **9,501 bytes** |
| Independently assembled functions | 44/44 | **48/48** |
| Matching encoded segments | 45/45 | **49/49** |
| Complete C-oracle vs 6502 emulator cases | 29/29 | **29/29** |
| Research BSS bytes | 32,831 | **32,866** |

This is an **honest size regression of 556 bytes**, despite better source data organisation. The same experimental backend expands repeated record-pointer operations and static helper calls; the above comparison does not establish whether the native algorithms are inherently larger or the emitter is poor at compiling them. Likewise, the new C code has not been run under VICE or C64 KERNAL/IRQ conditions. The experimental 6502 ABI and zero-page map remain separate research issues.

**Next source-program work:** follow the native assembler's distinct global/local arena lifetimes, then revisit the symbol and fixup consumers together. Examine `ass/assembler.asm`, `ass/value.asm` and `ass/representation.asm` to simplify staging/dispatch and status protocols in C, while keeping the current source and differential tests as a working checkpoint. Do not optimise each function against arbitrary byte thresholds or automatically promote these algorithms into the canonical assembler until behaviour and tradeoffs are clear.
