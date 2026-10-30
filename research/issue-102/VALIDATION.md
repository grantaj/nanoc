# Independent recovery validation — 2026-10-29

## Recovered files

Source: user re-attached `nanoc_remaining_gap_codegen_experiment.zip` from the crashed agent's session; archive size 634,855 bytes. Archive SHA-256:
`3466aa5cf0335340c04e0a87260a572ed7961602475c5aae86a338959597ea30`.

The complete ZIP was sent to GitHub as a raw Git blob through the connected GitHub tools, and the returned Git blob SHA-1 `b981eee81d334cf7fdd0508948dd1d5ba037c4db` matched `git hash-object` of the user's uploaded ZIP. The original report and 188 extracted source/support files are also preserved on this branch.

## Locally rerun

The archived ZIP was freshly extracted and its unmodified `reproduce_native_compare.sh` executed using local `cc` and Python 3. The script completed successfully in approximately 21 seconds.

Observed:

| Independent result | Observed |
| --- | --- |
| Encoded, physically linked loaded bytes | **8,945** |
| Binary file length (with 2-byte PRG load header) | **8,947** |
| Original assembler strict 6502 function checks | **44/44** |
| Original assembler byte-for-byte encoded segment checks | **45/45** |
| Full C-oracle-vs-interpreter assembly programs | **29/29** |
| Typed 16-bit constant compare interpreter differential cases | **9,120/9,120** |
| Handwritten native assembler reference | **6,905 bytes** |
| Remaining size difference | **2,040 bytes (1.295×)** |

This is genuinely rerun validation, not solely a transcription of the previous agent's report.

## Bitwise reproducibility caveat and correction

The first rerun, without `PYTHONHASHSEED`, passed every test and produced the same 8,945-byte loaded size, but its PRG differed from the archived one at **147 file-byte positions (offsets 3437–3583)**. SHA-256:

- Original archived `CANDIDATE.PRG`: `e155a78e9b7c4a5e68fc4b30ee9e4cb655048bdc2a9377477316ee1dcc813ef2`.
- First unseeded re-generation: `66be0c618943b71cb1f10380eb90521be423509a92004aac11dc58f415438f34`.

A second complete fresh generation with `PYTHONHASHSEED=0` passed all tests again and produced a **byte-identical match to the archived CANDIDATE.PRG**, including SHA-256 `e155a78e9b7c4a5e68fc4b30ee9e4cb655048bdc2a9377477316ee1dcc813ef2`. The extracted source-tree reproduction script adds the seed pin. The original archive remains untouched.

## Remaining limitations

- This is a **research 6502 instruction interpreter**, not a VICE/native 6510 execution or a C64 ROM/KERNAL/IRQ validation.
- Its shared zero-page allocation `$30-$3f` is **hypothetical** and not physically validated against C64 ownership.
- Machine-sequence outlining adds hardware JSR/RTS stack frames; stack depth for every legal native program was not proven.
- The backend is written in host Python; no production `nanoc1.c` implementation or native self-hosting convergence was produced by this recovery.
- Generated C may use a different symbol/fixup representation from handwritten `ass`, so the remaining 2,040 B is not automatically all compiler inefficiency.

Next engineering work should be planned and tested separately from preserving this exact checkpoint.
