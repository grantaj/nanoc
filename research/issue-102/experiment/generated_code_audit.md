# Generated-code audit — 29 October 2026

Input: the **actual** `compact_image.asm`, `compact_resolved.json`, and `CANDIDATE.PRG` from the physically linked Nano C research prototype. The production `nanoc1.c` compiler is **not** generating this image; it was produced by the research-only Python tape/backend plus a layout pass. No production changes were made for this audit.

## Assessment

**Structurally encouraging, but not yet consistently competent 6502.** The replacement eliminates the hardware-stack evaluation templates and produces ordinary 6502 instructions; several large functions are dramatically smaller. However, easy and entirely general machine algorithms remain unrecognised, including simple byte extraction and bounded table scans. VICE is needed for ROM/device/IRQ correctness, but it should not be used to declare the generated code's quality satisfactory.

## Measured image and instruction mix

- Linked payload: **16,311 bytes**, `$0800..$47B6`, only **73** bytes beneath BSS at `$4800`. PRG including two-byte load address: 16,313 B.
- All 44 C functions: **15,091 actual linked instruction bytes** and **6,625 instructions**. The larger 15,883 B number was measured *before* the separate 823-byte code-layout transformation; totals should not be mixed.
- Function instruction mix: `LDA` **2,178**, `STA` **1,832**, `JMP` **248**, `CMP` **355**, `JSR` **111**, `RTS` **217**. Approximately **61%** of all function instructions are `LDA`/`STA` alone; this is not itself proof they are redundant.
- `__ap` low/high zero-page slots are explicitly written **157 times each**, and `__ix` low/high **64 times each**. The backend often reconstructs effective addresses for separate accesses even when a register-held index or retained pointer would suffice.
- **356 `STA __call_*`** instructions set static parameter slots. Some are required by the nonrecursive ABI; others are reached via intermediary stores/loads.
- The emitted stream still contains **37 signed-word high-byte sign-bias compare setups** and **146 `__sel` branch-dispatch labels**, even after the final layout pass. Some compare machinery is necessary, but the examples below show severe overgeneralisation.

## Concrete real function comparisons

All generated sizes below are **actual linked byte distances between function labels**, not estimates. Reference sizes were assembled using the repository opcode table, but the reference code is not emitted by the compiler.

| Function | Actual linked prototype | Simple 6502 reference | Mechanism being missed |
|---|---:|---:|---|
| `upper_char` | 41 B | 16 B | Range-check, then clear ASCII bit 5 rather than 16-bit subtract and temporary copy |
| `apply_byte_prefix` | 106 B | 20 B | Return low/high byte directly instead of writing back `(value & 65535)`, masking and shifting 8 times |
| `find_opcode` | 185 B | 29 B | One-byte Y-indexed table scan, with 256th-step wrap for the not-found case, instead of 16-bit counter, wide address construction and generic signed comparison |
| `same_text` | 82 B | not scored | Rebuilds pointer `a` and `b` in `__ap` separately every iteration; could retain two pointer bases for the loop; care needed for aliasing with `i` |
| `stage_byte` | 127 B | not scored | Signed-word range test, full address reconstruction and 16-bit increment dominate a small byte-store routine |

The `upper_char`, `apply_byte_prefix`, and `find_opcode` references alone represent **332 B versus 65 B** (a possible 267 B difference). These are demonstrations of missing *general* machine choices, not a proposed hand-written whitelist.

### Reference: `find_opcode` (29 bytes)

```asm
find_opcode:
    ldy #$00
.loop:
    lda opcode_mnemonic,y
    cmp __L_find_opcode_mnemonic
    bne .next
    lda opcode_mode,y
    cmp __L_find_opcode_mode
    beq .found
.next:
    iny
    bne .loop
    lda #$ff
    tax
    rts
.found:
    tya
    ldx #$00
    rts
```

This is valid for `find_opcode`'s actual `int opcode = 0; while (opcode < 256)` semantics, assuming these two 256-byte tables and the static arguments are not modified inside the loop (they are not). Successful return carries `A=index`, `X=0`; failure carries `A=X=$ff` (-1). It is a **machine-algorithm selection** that an expression-local backend is not discovering.

### Reference: `upper_char` (16 bytes)

```asm
upper_char:
    lda __L_upper_char_c
    cmp #$61
    bcc .done
    cmp #$7b
    bcs .done
    and #$df
.done:
    ldx #$00
    rts
```

The only byte modification on the valid `[a,z]` range is clearing bit 5. This correctly returns an unsigned `char` in `A` with zero extension in `X`.

### Reference: `apply_byte_prefix` (20 bytes)

```asm
apply_byte_prefix:
    lda __L_apply_byte_prefix_prefix
    cmp VALUE_PREFIX_LOW   ; mutable C global, so a memory comparison
    beq .low
    lda __L_apply_byte_prefix_value+1
    ldx #$00
    rts
.low:
    lda __L_apply_byte_prefix_value
    ldx #$00
    rts
```

This respects the source's `unsigned` 16-bit width and the C global `VALUE_PREFIX_LOW` being mutable.

## Largest remaining bodies

| Function | Linked instruction bytes |
|---|---:|
| `assemble_instruction` | 1,531 |
| `parse_atom` | 1,022 |
| `resolve_fixups_for_symbol` | 961 |
| `assemble_direct_value` | 750 |
| `open_include` | 684 |
| `allocate_symbol` | 643 |
| `parse_value` | 637 |
| `define_label` | 559 |
| `process_source_line` | 548 |

`assemble_instruction` alone has 224 `LDA`, 209 `STA`, 22 `JMP`, and 673 instructions. The `allocate_symbol` body repeatedly generates full 16-bit effective addresses for parallel arrays indexed by the same `n`. These look like areas for *general address/value residency* choices, not special source-pattern matchers.

## Physical / semantic caution

- Byte-level assembly and interpreter execution do not validate ROM, IRQ or IEC behaviour. The shared `$02..$10` machine scratch and `$FC..$FF` target runtime workspace should be checked under real VICE KERNAL calls and interrupts.
- The current 73-byte code/BSS gap is fragile; *fitting* is not the same thing as excellent 6502 code.
- The code was generated by a research backend and a separate 823-byte post-layout transformation, **not by native Nano C**. The production architecture still needs implementation.
- The existing full-linked interpreter test excludes the empty-file prefetch disagreement; VICE is required to resolve it.

## Recommendation

Keep the linked candidate as an excellent correctness/fit milestone, but **do not freeze its backend architecture or judge it good on fit**. First generalise the machine planning for byte demands, loop-carried Y / pointer bases, and repeated parallel-array addresses; evaluate its effect against the real largest functions, not only the selected examples. Then perform VICE as an independent native runtime gate. Do not reintroduce a catalogue of recognisers for `upper_char`, `find_opcode`, etc.
