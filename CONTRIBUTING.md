# Contributing to nanoc

nanoc is deliberately a small, C64-native learning project. Changes should favour clear 6502 code, explicit machine-level contracts, and simple build/test machinery over abstraction for its own sake.

## Assembly style

Use lowercase instruction mnemonics:

```asm
	lda #$00
	sta value
	jsr printString
```

Use `UPPER_SNAKE_CASE` for constants and enumerated values, for example `CHROUT`, `TOKEN_OPERAND`, or fixed memory addresses.

Use descriptive lower-camel-case names for routines and persistent data, for example `printString`, `skipWhitespace`, `sourceEnd`, and `jumpVector`.

Use dot-prefixed local labels for control flow inside a routine:

```asm
.loop:
	lda (ZP_PTR1),y
	beq .done
	...
	jmp .loop
.done:
	rts
```

Short names such as `p`, `q`, or `tmp` are acceptable only where their meaning is genuinely local and obvious. At module boundaries, prefer names that describe the pointer or value's role.

## Routine contracts

Public or reusable routines should document their calling contract. State, where relevant:

- input registers and memory locations;
- output registers and memory locations;
- registers that are clobbered;
- registers or pointers that are preserved;
- deliberate memory side effects.

Do not preserve every register automatically. Preserve a register only when the routine's contract requires it. On the 6502, unnecessary save/restore code costs bytes, cycles, and stack space.

A typical header is:

```asm
;;; printString
;;;
;;; ZP_PTR1 points to a NUL-terminated string.
;;; ZP_PTR1 is preserved.
;;; A is clobbered. X and Y are preserved.
```

## Comments

Use the existing comment hierarchy consistently:

- `;;;` for file-level documentation and routine contracts;
- `;;` for block-level intent or an important implementation note;
- `;` for a short inline comment.

Comments should explain contracts, intent, machine constraints, and non-obvious decisions. Avoid merely translating an instruction into English.

Prefer:

```asm
	inc ZP_PTR1
	bne .loop
	inc ZP_PTR1+1		; handle page crossing
```

rather than commenting every instruction individually.

## Control flow

Keep routines small enough that their control flow can be followed directly from the source.

Remember that 6502 conditional branches have a limited range. When a destination is too far away, use the normal short-branch-over-`JMP` form rather than contorting the layout:

```asm
	bne .continue
	jmp farTarget
.continue:
```

Machine-driven idioms are welcome when they are documented. For example, manually constructing an indirect subroutine call is reasonable when working around the absence of `JSR (addr)`.

## Pointers and memory

Treat zero-page locations as scarce shared resources. Give persistent zero-page pointers symbolic names and make ownership/borrowing clear at routine boundaries.

When a routine temporarily borrows a zero-page pointer for indirect addressing, preserve and restore the previous value if the surrounding contract requires it.

Use explicit page-crossing logic where pointer arithmetic requires it. Do not hide important 16-bit behaviour behind clever assembler expressions if the resulting machine operation becomes harder to see.

## Source and token buffers

The tokenizer source buffer is an explicit half-open byte range `[start,end)`:

- `ZP_PTR1` points at the current source byte;
- `sourceEnd` is the one-past-end address;
- NUL means end of line;
- EOF means `ZP_PTR1 == sourceEnd`.

Do not reintroduce an in-band EOF sentinel. Blank lines, including consecutive blank lines, must remain representable without ambiguity.

## Testing

Tests should remain C64-native.

The code under test and its assertions run as 6502 programs under VICE. The host side may assemble programs, start VICE, and inspect the agreed test-result byte, but it should not duplicate the test logic in Python or another host language.

Use distinct failure codes where practical so a failing CI run identifies the assertion that failed.

Keep the test stack simple:

```text
assembly test source
        |
        v
      vasm
        |
        v
       PRG
        |
        v
      VICE
        |
        v
result byte -> make/CI
```

`make` and `make test` are the canonical local and CI entry points. New tests should integrate with those commands rather than introduce a parallel test framework.

## Scope of changes

Prefer small changes with one clear purpose. Avoid mixing behavioural fixes with broad cosmetic rewrites.

Do not reformat working historical code merely to make it match newer conventions. Apply these conventions to new code and improve older code when it is already being changed for a substantive reason.

The project should remain "spiritually 6502": direct, explicit, economical, and understandable from the machine upward.