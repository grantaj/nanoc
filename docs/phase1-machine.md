# Nano C Phase 1 machine model

This document defines the concrete 6502 execution model targeted by `nanoc0`.

The source language is frozen in `docs/phase1.md`. This document answers the next question: **what obvious 6502 code should that language mean?**

The north star is simple:

> Nano C Phase 1 is a more convenient way to write 6502 assembly.

The compiler should remove clerical work that an assembly programmer would otherwise do by hand: naming storage, assigning addresses, evaluating expressions, laying out static data, passing parameters, and writing structured branches and loops. It should not simulate a conventional abstract C machine on top of the 6502.

A 6502 programmer reading generated output should usually be able to say: "yes, that is roughly how I would have written it."

# 1. What this model deliberately does not have

Phase 1 has:

- no recursion or reentrancy;
- no software C stack;
- no stack frames;
- no dynamic local storage;
- no register allocator;
- no virtual registers;
- no object files or linker;
- no position-independent code;
- no general ABI framework.

The 6502 hardware stack remains primarily the return-address stack used by `JSR` and `RTS`.

Generated C code does not push locals, parameters, expression values, or call arguments onto page `$0100`. A private runtime/support routine may use `PHA`/`PLA` internally when convenient, but it must balance the hardware stack before returning and no C value lives there across a call.

# 2. The two machine scratch values

Nano C reserves the same two user zero-page pointer pairs already used by the native assembler:

```asm
NC_TMP = $fc      ; $fc/$fd: transient 16-bit arithmetic scratch
NC_PTR = $fe      ; $fe/$ff: transient indirect-address scratch
```

They are compiler-owned scratch, not C objects.

Both are caller-clobbered. Neither may hold a value that must survive `JSR`.

`NC_TMP` is used for short-lived 16-bit operator work. `NC_PTR` is used when an array or `char *` access needs `(zp),Y` addressing.

This is intentionally a tiny fixed machine convention. Phase 1 C source cannot name zero-page objects directly, so reserving these four bytes costs no source-language generality.

# 3. Binary arithmetic mode is an invariant

Nano C integer arithmetic always uses ordinary binary 6502 `ADC`/`SBC` semantics.

The decimal flag is therefore part of the machine contract rather than ambient machine state:

- generated Nano C code assumes `D = 0`;
- `__nc_init` executes `CLD` before any C code runs;
- Nano C generated code never executes `SED`;
- compiler support and runtime/KERNAL-facing routines must return with `D = 0`.

A runtime helper may call code whose decimal-flag behaviour is not part of the Nano C contract, but it must execute `CLD` before returning to generated C.

This avoids every generated add/subtract having to defend itself against arbitrary processor state while still making the requirement explicit and visible.

# 4. Expression value convention

Every scalar expression finishes in the same visible machine value pair:

```text
A = low byte
X = high byte
```

For an 8-bit `char`, `X` is zero.

For `int`, `unsigned`, and `char *`, `A/X` contain the complete 16-bit representation.

Comparison results are canonical:

```text
false -> A = 0, X = 0
true  -> A = 1, X = 0
```

A Phase 1 C-defined function returns `int`, so its return value is also in `A/X`.

`A`, `X`, `Y`, processor flags, `NC_TMP`, and `NC_PTR` are all caller-clobbered by a function call. Source locals do not need register preservation because they live in static memory.

## 4.1 Loading ordinary objects

A `char` object naturally loads as:

```asm
lda c
ldx #0
```

A 16-bit scalar or pointer naturally loads as:

```asm
lda value
ldx value+1
```

An array or string address naturally becomes:

```asm
lda #<text
ldx #>text
```

Stores reverse the same convention. A `char` destination stores only `A`; a 16-bit destination stores both bytes.

# 5. Static storage instead of stack frames

Every function owns one fixed set of storage for:

- parameters;
- locals;
- compiler expression spills;
- caller-side argument staging.

Because Phase 1 forbids recursion and reentrancy, the same storage is safely reused on every call to that function.

Conceptually:

```c
int add(int a, int b)
{
    int result;

    result = a + b;
    return result;
}
```

has storage equivalent to:

```asm
__add_a      = NC_BSS+40
__add_b      = NC_BSS+42
__add_result = NC_BSS+44
```

and code equivalent in spirit to:

```asm
add:
    ; operate directly on __add_a, __add_b and __add_result
    ; return the final int in A/X
    rts
```

No stack frame is created or destroyed.

A caller's locals survive a nested call simply because the callee owns different addresses.

# 6. `NC_BSS`: explicit static RAM workspace

The existing native assembler can stage at most 16 KiB of output, while the candidate `ass.c` needs roughly 29 KiB of uninitialised arrays before function storage is counted. Emitting every zero-initialised C object as bytes in the PRG would therefore make the bootstrap impossible for the wrong reason.

Phase 1 instead uses an explicit static RAM workspace.

The assembly wrapper supplies one absolute symbol:

```asm
NC_BSS = $5000       ; example only; the wrapper chooses the real address
```

`nanoc0` allocates zero-initialised globals and function-owned storage as offsets from that base:

```asm
ass_image        = NC_BSS+0
ass_image_length = NC_BSS+11264
```

These symbol assignments emit no bytes. They are the C equivalent of the explicit RAM geometry already used by `ass.asm`.

There is no allocator and no linker. `nanoc0` simply maintains a monotonically increasing static offset while compiling the translation unit.

The compiler emits the final symbol:

```asm
__nc_bss_end = NC_BSS+<total bytes>
```

so the chosen memory geometry remains visible to the build and to a human reader.

## 6.1 What lives in loaded image bytes

Objects with explicit source initialisers remain ordinary loaded data because their bytes must exist before C code runs:

```c
char widths[4] = {0, 1, 1, 2};
```

maps naturally to:

```asm
widths:
    byte 0,1,1,2
```

Likewise, explicitly initialised 16-bit tables use `word`, and string literals/static string initialisers use ordinary labelled byte/string data.

C64 RAM is writable, so an explicitly initialised global remains mutable even though its initial bytes arrived in the loaded image.

## 6.2 Zero-initialised globals

Source-level uninitialised globals must begin as zero according to Phase 1 semantics.

They are allocated first in `NC_BSS`. Because all globals precede all functions in Phase 1, `nanoc0` knows the end of the zero-required region before function storage begins.

The generated unit provides a tiny routine whose first instruction also establishes the binary-arithmetic invariant:

```asm
__nc_init:
    cld
    ; clear [NC_BSS, __nc_zero_end)
    rts
```

The assembly program wrapper calls `__nc_init` once before calling any C-defined function.

Function parameter/local/temporary storage lies after `__nc_zero_end` and does not need startup clearing: parameters are written by callers, well-formed Phase 1 locals are assigned before reading, and compiler temporaries are overwritten before use.

If the generated program uses the bootstrap I/O runtime, `__nc_init` separately clears its small handle-mode/EOF state. That is runtime initialization, not an extension of C zero-initialisation to all compiler-owned BSS.

This keeps the loaded image small while retaining the source language's zero-initialisation rule.

# 7. Function calls

Calls use **callee-owned parameter slots** and the 6502's natural `JSR`/`RTS` pair.

No C argument is passed on the hardware stack.

Suppose:

```c
int add(int a, int b)
{
    return a + b;
}
```

The callee owns fixed slots such as:

```asm
__add_a = NC_BSS+100
__add_b = NC_BSS+102
```

Immediately before the call, the caller copies the final argument values into those slots and executes:

```asm
jsr add
```

The return value arrives in `A/X`.

## 7.1 Why arguments are staged by the caller first

Arguments are evaluated left to right, as required by Phase 1.

It is **not safe** to write each argument directly into the callee's parameter slot as soon as it is evaluated.

Consider:

```c
f(g(), h());
```

If `h()` itself calls `f()`, that nested call is legal: the outer `f` has not begun yet. But it would overwrite any outer argument already placed in `f`'s static parameter slots.

Therefore every caller owns static call-staging words. The sequence is:

```text
1. evaluate argument 0 -> caller staging
2. evaluate argument 1 -> caller staging
3. ...
4. copy all staged values to the callee's parameter slots
5. JSR callee
```

In assembly shape:

```asm
    ; g()
    jsr g
    sta __caller_call0
    stx __caller_call0+1

    ; h()
    jsr h
    sta __caller_call1
    stx __caller_call1+1

    ; only now expose the arguments to f
    lda __caller_call0
    sta __f_a
    lda __caller_call0+1
    sta __f_a+1

    lda __caller_call1
    sta __f_b
    lda __caller_call1+1
    sta __f_b+1

    jsr f
```

A `char` parameter copies only the low staged byte. `int`, `unsigned`, and `char *` parameters copy both bytes.

Call-staging storage is static per caller and may be reused by later non-overlapping calls. Nested pending calls receive distinct staging slots as required by their nesting depth. For example, while compiling `f(x, f(y, z))`, the saved outer `x` and the inner call's arguments occupy different compile-time slots.

The bootstrap compiler bounds pending call nesting at four and arguments per call at eight. `bootstrap/ass.c` currently needs at most five arguments, so this is measured capacity with modest headroom rather than an arbitrary ABI limit.

This is still much smaller than a software call stack: the compiler resolves every slot at compile time.

# 8. Function return and call clobbers

A Phase 1 C function returns an `int` in:

```text
A = low byte
X = high byte
```

`return expression;` therefore means:

```text
evaluate expression into A/X
RTS
```

Every C call may clobber:

- A;
- X;
- Y;
- processor flags;
- `NC_TMP`;
- `NC_PTR`.

Nothing else owned by the caller is implicitly changed.

The decimal flag is the one exception to the otherwise caller-clobbered flag rule: every generated/runtime return re-enters Nano C with `D = 0`.

This rule is deliberately severe and simple: generated code never saves registers merely because an ABI says it should. If a value must survive a call, the compiler spills it to the caller's static storage before `JSR`.

# 9. Expression evaluation

Expressions are evaluated directly from left to right.

The baseline strategy for a binary operator is:

```text
1. evaluate left operand -> A/X
2. spill A/X to the next static temporary owned by the function
3. evaluate right operand -> A/X
4. combine with the spilled left operand
5. release that temporary
```

The compiler therefore needs only as many two-byte spill slots as the maximum simultaneously live expression depth in that function.

Those slots are fixed at compile time and reused by later expressions.

There is no runtime expression stack.

This strategy is intentionally more obvious than clever. Later peephole work may omit unnecessary spills for literals or simple loads, but the semantic machine model does not depend on that optimisation.

## 9.1 Example: 16-bit addition

For:

```c
x = y + 1;
```

a straightforward baseline shape is:

```asm
    ; left operand y -> A/X
    lda y
    ldx y+1
    sta __fn_tmp0
    stx __fn_tmp0+1

    ; right operand 1 -> A/X
    lda #1
    ldx #0

    ; __fn_tmp0 + A/X -> A/X
    sta NC_TMP
    stx NC_TMP+1
    lda __fn_tmp0
    clc
    adc NC_TMP
    tay
    lda __fn_tmp0+1
    adc NC_TMP+1
    tax
    tya

    ; assignment
    sta x
    stx x+1
```

This is not claimed to be the final shortest sequence. It is the deliberately simple baseline that `nanoc0` can generate reliably.

## 9.2 Conditions and branch reach

An arbitrary 16-bit expression is false only when both bytes are zero.

A baseline false test can therefore reduce `A/X` to flags with:

```asm
    sta NC_TMP
    txa
    ora NC_TMP
```

`nanoc0` does **not** keep track of conditional-branch distance and does not perform branch relaxation. It always represents a generated conditional transfer as a short branch to a nearby label plus an absolute `JMP` for the potentially distant path.

For example, a false transfer is shaped as:

```asm
    bne .condition_true
    jmp .false_target
.condition_true:
```

The branch target is deliberately adjacent and therefore always in range; the `JMP` carries the arbitrary-distance control transfer.

This is the normal Phase 1 form even when the final target would happen to be within relative-branch range. `nanoc0` never asks that question, so it never needs to retain or calculate branch extent.

This deliberately spends one `JMP` to remove an entire class of layout bookkeeping from the bootstrap compiler.

Comparisons may feed this control-flow form directly instead of first materialising canonical `0`/`1` when their value is consumed only by a branch.

## 9.3 Multiplication

Phase 1 multiplication is 16-bit modulo 65536. Signedness does not change the low 16-bit product representation.

Rather than expanding a shift/add loop at every `*`, the baseline compiler calls one private support routine:

```text
left operand  -> NC_TMP low/high
right operand -> A/X
JSR __nc_mul16
result        -> A/X
```

`__nc_mul16` is compiler support, not a C library function. It may clobber `Y` and `NC_PTR` as well as ordinary call-clobbered state. It returns with `D = 0` like every other Nano C support routine. The compiler emits it only when the translation actually contains a multiplication.

An assembly programmer would normally factor repeated 16-bit multiplication into a small subroutine; Nano C does the same.

## 9.4 Shifts

A variable shift count is 0 through 15 by Phase 1 rule.

The baseline compiler may place the value in `NC_TMP`, use `Y` as the count, and emit a short `ASL`/`ROL` or `LSR`/`ROR` loop over the two scratch bytes.

No general shift runtime helper is required.

# 10. Arrays and pointers

There is no bounds checking.

Indexing follows the shape of the 6502 instruction set rather than forcing every access through one general address calculation. When the index expression is already typed as `char`, the compiler knows that its offset fits in `Y` and uses indexed addressing directly. When the index is an `int`/`unsigned`, or the element width requires scaling, it computes a full address in `NC_PTR`.

## 10.1 Fixed `char` arrays

A fixed `char[]` has an assembler-visible base address. If its index is a `char`, the natural read is simply:

```asm
    ; index is in A
    tay
    lda array,y
    ldx #0
```

There is no reason to construct `array + index` in zero page first. The array base is already part of the instruction and the byte index is exactly what `Y` represents.

A byte-index store uses the same absolute-`,Y` form. If the right-hand expression must be evaluated first, only the one-byte index needs to survive that evaluation.

Integer literals have Phase 1 type `int`, so even a small literal such as `array[4]` currently takes the conservative 16-bit fallback. Recognizing numerically byte-sized `int` expressions is a separate local improvement; it is not needed to make `char` indexing machine-shaped.

## 10.2 `char *` with a byte index

A `char *` is a runtime value, so indirect addressing is still required. With a byte index the pointer itself goes in `NC_PTR` and the index goes in `Y`:

```asm
    ; pointer value has been placed in NC_PTR
    ; index is in A
    tay
    lda (NC_PTR),y
    ldx #0
```

The compiler preserves the pointer value before evaluating a side-effecting index expression when necessary. It does **not** first add the byte index to a second 16-bit pointer merely to access offset zero.

A `char` load is zero-extended into `A/X`.

## 10.3 Full 16-bit and scaled indexing

The byte-index forms are deliberately not treated as a general C indexing mechanism. A wide index still means:

```text
effective address = base + index  (mod 65536)
```

and a named `int[]` or `unsigned[]` means:

```text
effective address = base + 2 * index  (mod 65536)
```

The compiler keeps the offset in `NC_TMP`; non-byte elements scale it before the addition. The small generated support routine `__nc_index16` adds that offset to the base in `A/X` and leaves the full effective address in `NC_PTR`.

A 16-bit load is then conceptually:

```asm
    ldy #0
    lda (NC_PTR),y
    sta NC_TMP
    iny
    lda (NC_PTR),y
    tax
    lda NC_TMP
```

The result is again in `A/X`.

## 10.4 Indexed assignment lifetime

The compiler evaluates the lvalue index before the right-hand expression, but it saves only as much state as must genuinely survive the RHS:

- a fixed `char[]` with a byte index saves only that one-byte index;
- a current function's `char *` parameter/local may save the byte index and reload its own fixed pointer slot after the RHS, because a callee cannot name that slot;
- a global pointer, wide index, scaled element, or other general case saves the complete effective address in function-owned static storage.

The last case matters because the RHS may contain calls or other indexed accesses that clobber `NC_PTR`, or may itself change a global pointer. After the RHS is available, the saved address is restored and the value is stored.

Again, no machine stack is involved.

# 11. Globals and data layout

Object widths are exactly the Phase 1 widths:

```text
char      1 byte
int       2 bytes, little-endian
unsigned  2 bytes, little-endian
char *    2 bytes, little-endian address
```

There is no alignment padding.

Global arrays are contiguous element sequences using the same widths.

`nanoc0` has two storage destinations:

```text
explicitly initialised globals / strings -> loaded assembly image
zero-initialised globals                 -> NC_BSS, cleared by __nc_init
```

Function parameters, locals, spills, and call-staging slots also live in `NC_BSS`, after the zero-required global region.

This is not a general data-section system. It is one loaded image plus one explicitly based static RAM workspace.

# 12. Runtime calls

The Phase 1 source runtime is exactly:

```c
int io_open(char *name, int length);
int io_read(int handle);
int io_create(char *name, int length);
int io_write(int handle, int value);
int io_close(int handle);
```

These are ordinary assembly helpers with fixed parameter slots and the same `A/X` integer return convention as C-defined functions. They are runtime services, not language features or a standard library.

Generated calls use the same caller-staging sequence as C-defined functions: calculate every argument, save it in caller-owned words, copy those words to the known runtime parameter slots, then `JSR` the runtime entry.

## 12.1 Concrete C64 file model

The bootstrap runtime manages six small handle slots. This is enough for the measured assembler need of five simultaneously nested source files plus one output file; it is not an arbitrary file-object API.

C-visible handles are indices 0 through 5. The generated runtime maps them to KERNAL logical file numbers 4 through 9. Input uses device 8 and output uses device 9 in the project test environment.

`io_open` uses the ordinary KERNAL `SETNAM`, `SETLFS`, `OPEN`, `CHKIN`, `CHRIN`, `READST`, `CLRCHN` and `CLOSE` path. IEC disk `OPEN` does not itself make a missing file observable, so `io_open` probes one byte. On success that byte is retained in the handle's existing EOF/state storage and returned by the first `io_read`; the probe never consumes a source byte from the C program's point of view.

`io_read` follows the same end-of-input convention as the native assembler: the final valid byte is returned even when `READST` reports EOI with it, and the following call returns `-1`.

`io_create` creates/replaces a sequential output file by spelling the C64 filename as `@0:<name>,S,W` and opening it on output device 9. `io_write` selects that channel and writes the low byte of its value through `CHROUT`.

The C-facing results are:

- `io_open`: non-negative handle or `-1`;
- `io_read`: byte 0..255, `-1` EOF, or `-2` I/O error;
- `io_create`: non-negative handle or `-1`;
- `io_write`: `0` on success or `-1`;
- `io_close`: `0` for a valid handle.

The runtime may clobber all ordinary call-clobbered machine state. Every entry starts in binary mode for its own arithmetic and every path that returns to generated C restores `D = 0`.

No seek, formatted I/O, stream object, allocator or other standard-library surface is implied.

# 13. Assembly wrapper boundary

A compiled Phase 1 translation unit is not an object file and does not choose a universal C64 memory map.

A tiny assembly wrapper supplies the machine placement appropriate to the program, for example:

```asm
NC_BSS = $5000

* = $1000
include "generated.asm"
```

The wrapper is responsible for:

1. selecting any C64 memory banking required by its chosen RAM geometry;
2. calling generated `__nc_init` once, which establishes `D = 0`, clears source-level zero-initialised globals and initializes emitted runtime state;
3. calling whichever C function is the program entry point;
4. interpreting the returned `A/X` value if needed.

Compiler-private support and used runtime entries are emitted directly in the generated `ass` source; there is no separate runtime package or linker step.

This is deliberately analogous to the current `ass_4000.asm` / `ass_0800.asm` wrappers: the reusable body does not need to own the whole machine.

There is no required C `main` convention in Phase 1.

# 14. Worked examples

These examples show the baseline mapping, not an optimisation target.

## 14.1 Byte comparison

```c
if (c == 'A') {
    found = 1;
}
```

A natural generated form uses a local branch over the arbitrary-distance jump:

```asm
    lda c
    cmp #'A'
    beq .equal
    jmp .not_equal
.equal:

    lda #1
    sta found
.not_equal:
```

`nanoc0` uses this safe form rather than asking whether `.not_equal` happens to be within relative-branch range.

## 14.2 Static local survives a call

```c
int outer(int x)
{
    int saved;

    saved = x;
    x = inner();
    return saved + x;
}
```

`__outer_saved` is an ordinary fixed RAM address. `inner()` may freely clobber registers and the zero-page scratch values; it cannot clobber `__outer_saved` because `inner` owns different static storage.

There is nothing to push before `JSR inner`.

## 14.3 Pointer byte store

```c
p[i] = value;
```

If `i` is a `char` and `p` is a current-function pointer slot, the compiler can use the smaller machine-shaped sequence:

```text
1. evaluates i and saves its low byte;
2. evaluates value;
3. saves the result byte briefly in NC_TMP;
4. reloads p into NC_PTR;
5. loads the saved index into Y;
6. stores the result through (NC_PTR),Y.
```

If `p` is global, the compiler instead computes and saves the complete effective address before evaluating `value`, because the RHS is allowed to change that global pointer.

This is exactly the lifetime distinction an assembly programmer would make by hand.

# 15. Compiler invariants

`nanoc0` can be implemented against a small set of hard invariants:

1. **A/X is the current scalar result.**
2. **A call destroys all registers and zero-page scratch.**
3. **Nano C arithmetic always runs with `D = 0`; runtime/support code restores that invariant before returning.**
4. **Anything that must survive a call is already in static memory.**
5. **Every C function has one fixed parameter/local/temp area.**
6. **No C value uses the hardware stack for storage.**
7. **`NC_PTR` is only a transient effective address.**
8. **`NC_TMP` is only transient operator scratch.**
9. **All persistent storage has an assembler-visible absolute address.**
10. **Zero-initialised globals occupy the initial part of `NC_BSS`; function scratch does not require clearing.**
11. **Conditional control flow always uses local branches over absolute `JMP`s; `nanoc0` never tracks branch reach.**
12. **Generated code may be verbose, but its machine behaviour should be unsurprising.**

These invariants are more valuable to the bootstrap compiler than a more general ABI would be.

# 16. What may improve later without changing the model

The first compiler should prefer obvious code over clever code.

Later versions may safely make local improvements such as:

- retaining a simple byte value in `A` without writing a spill;
- recognizing additional expressions that are provably byte-sized and can therefore use indexed addressing;
- folding literal arithmetic;
- shortening a branch-over-`JMP` sequence when a later compiler already knows the final layout;
- omitting redundant reloads;
- using shorter increment/decrement sequences.

Those are peephole/code-generation improvements, not changes to the Phase 1 execution model.

The underlying contract remains static storage, explicit addresses, `A/X` values, `JSR`/`RTS`, and a machine that stays visible.