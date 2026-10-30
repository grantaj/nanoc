# #102 — conventional 6502 code generation by construction

**Date:** 2026-10-30. **Status:** Independent, limited-subset research compiler; _not_ a solution to the remaining executable size gap and _not_ a production `nanoc1.c` change.

## Hypothesis

Instead of materialising each C tape operation in a temporary memory home and hoping for later clean-up, a tiny 6502 compiler should naturally compile expressions into A, comparisons into processor flags, indexed reads through Y, and call-free indexed loops through Y with stable zero-page pointers. No tree search, global optimizer, function-name recognition, or 21-layer inheritance chain.

## Implemented

`full_corpus/natural6502.py` is a **255-line independent direct C-AST emitter** (pycparser parses already extracted one-function C sources). This architecture deliberately does **not** inherit any of the previous research backends or use their instruction selector. Its ordinary compilation conventions are:

- A is the result of byte expressions. Arithmetic uses `CLC/ADC`, `SEC/SBC`, `AND/ORA/EOR`, as appropriate.
- For expressions proven to have operands in `[0,255]`, C's promoted comparison uses direct byte `CMP` and branches, with the successful path falling through. Unknown widths and promoted arithmetic in conditions are **rejected**, not incorrectly narrowed.
- A byte increment is `INC name` (decrement `DEC`). This is chosen in semantic lowering, **not** recovered by a peephole pass.
- Indexed byte loads use absolute,Y for static arrays or `(zp),Y` for pointers.
- For a **call-free, one-byte monotonic index loop**, a small general proof recognises initialization to zero, `<` a byte bound, a last-statement `+1`, and non-use of the index afterwards. It maps the loop counter to **Y** and up to two invariant pointer inputs to `__ap`/`__ix`, preinitialised once. All indexed accesses inside the loop must refer to the same index and calls/other assignments are rejected. No function names are inspected. A field comparison can use `CMP (zp),Y` directly.
- Existing static call-parameter ABI remains unchanged. The direct emitter only replaces independently compiled functions when it actually produces fewer encoded **function instruction bytes**. Unsupported operations fall back to the unchanged, independently validated research backend.

No optimisation pass is needed to produce the four selected candidate bodies. Later existing machine-flow/layout/outlining passes are retained **only** for fair whole-image comparison with the previously recovered image.

## Actual output

The clean-byte C function `same_text` now compiles to the following conventional 6502 algorithm; this was generated from the ordinary C function and the generic byte-index loop convention, **not** from a function-name template:

```asm
    lda __L_same_text_a_length
    cmp __L_same_text_b_length
    beq .length_ok
    lda #0
    rts
.length_ok:
    lda __L_same_text_a
    sta __ap
    lda __L_same_text_a+1
    sta __ap+1
    lda __L_same_text_b
    sta __ix
    lda __L_same_text_b+1
    sta __ix+1
    ldy #0
.loop:
    cpy __L_same_text_a_length
    bcs .matched
    lda (__ap),y
    cmp (__ix),y
    bne .mismatch
    iny
    jmp .loop
.mismatch:
    lda #0
    rts
.matched:
    lda #1
    rts
```

This illustration simplifies label names/arrangement; inspect `full_corpus/natural6502.py` / generated `functions.asm` for the exact emitted listing.

### Function-level direct output

| C function | Mature emitter bytes before its global cleanup | New independent direct emitter bytes |
| --- | ---: | ---: |
| `upper_char` | 35 | **27** |
| `short_mode_for_index` | 32 | **26** |
| `long_mode_for_index` | 32 | **26** |
| `same_text` | 76 | **54** |

`same_text`'s two-pointer version eliminates address recomputation and materialized index; these are ordinary 6502 choices. Only **4 of 44** original functions are eligible for this deliberately narrow independent emitter. The other 40 remain unchanged.

### Physically linked whole-assembler results

| Whole assembler | Before outlining | Final loaded executable |
| --- | ---: | ---: |
| Frozen recovered control | **9,936 B** | **8,945 B** |
| Four native-convention functions + unchanged mature fallback | **9,926 B** | **8,935 B** |
| Handwritten native reference | — | **6,905 B** |

The initially selected function bodies account for **42 B less raw code**, but the existing global machine-flow and ABI transformations already recover much of this in the mature control. The final linked saving is just **10 B**. This does **not** validate a general size solution; it makes the repeated observations reproducible in a separate simple emitter.

## Independent verification

1. `sh reproduce_native_compare.sh` (without `NATURAL6502`) reproduces **8,945 B**, including original archived PRG SHA-256 `e155a78e9b7c4a5e68fc4b30ee9e4cb655048bdc2a9377477316ee1dcc813ef2`.
2. `sh reproduce_natural6502.sh` builds the new version and checks **8,935 B**, **44/44** strict assemblies, **45/45** physical segment byte matches, **29/29** full interpreted 6502 vs host-C assembler programs and **9,120/9,120** 16-bit comparisons. Final PRG SHA-256: `7ab64ec5a997de9be68b8eecf3d1e8e0c485bf109ed644ac484541409f8ca796`.
3. `PYTHONPATH=full_corpus python full_corpus/test_natural6502.py` passes **5,094** independent interpreted-6502 differential executions of the **directly emitted functions**, including all 256 possible input bytes, all 256 mode-selector indices and strings of length 0, 1, 127, 128, 254 and 255 with page-crossing pointers. No hidden source-specific expected return assumptions.

The scripts were also run separately because a single back-to-back reproduction including the full control plus machine tests exceeded the runner time limit. That timed-out combined run is *not* counted as a pass. Both independent commands passed.

## Interpretation and next architectural constraint

This is strong evidence that **standard 6502 conventions can be encoded in a small direct compiler**, including a coherent loop with no search and no post-generation local optimiser. It is **not** evidence that simply replacing the 21-layer hierarchy with a naïve subset compiler will close the ~2 KB difference. The baseline backend already recovers many straightforward byte-flow idioms, and the remaining C assembler is dominated by *word-valued operations, pointer lifetime across calls, and parallel-table algorithms*, which the narrow independent emitter deliberately does not handle.

Before growing the new compiler, the next sensible design step is to define the same by-construction discipline for **16-bit pointers/word values and call ABI**. It must work correctly for multiple unrelated substantial functions and outperform the frozen baseline **after** linked-image outlining. Avoid new function-name patterns, another state-search framework, and arbitrary size thresholds. Preserve the exact 8,945-B reference and compare real 6502 output, not instruction-count estimates.
