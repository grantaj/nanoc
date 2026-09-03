# Nano C Phase 1 machine model

This document defines the concrete 6502 execution model targeted by `nanoc0`.

The source language is frozen separately in `docs/phase1.md`. That document says
what a Nano C program means. This document answers a different question:
**what machine state should exist while that meaning is being carried out on a
6502?**

The north star is:

> Nano C Phase 1 is a more convenient way to write 6502 assembly.

The compiler should remove clerical work that an assembly programmer would
otherwise do by hand: naming storage, assigning addresses, evaluating
expressions, laying out static data, passing parameters, and writing structured
branches and loops. It should not manufacture an abstract C machine and then
simulate that machine on the 6502.

The governing physical rule is:

> **Do not manufacture machine state until some later C operation can observe it.**

A 6502 programmer reading generated output should usually be able to say: “yes,
that is roughly how I would have written it.”

# 1. What this model deliberately does not have

Phase 1 has:

- no recursion or reentrancy;
- no software C stack;
- no stack frames;
- no dynamic local storage;
- no AST or generic IR;
- no CFG or basic blocks;
- no SSA;
- no virtual registers;
- no register allocator;
- no generic optimizer or peephole pass;
- no object files or linker;
- no position-independent code;
- no general ABI framework.

`nanoc0` remains a streaming parser/emitter. It remembers only small facts that
are useful to the next source operation or target instruction.

The 6502 hardware stack remains primarily the return-address stack used by
`JSR` and `RTS`. A bounded, explicit use of `PHA`/`PLA` is a legitimate target
resource when a later issue demonstrates that it is the clearest lifetime
solution, but Phase 1 does not acquire a software expression stack or automatic
stack frames.

# 2. The target resources

Nano C has the resources a 6502 programmer actually sees:

```text
A, X, Y
N, V, Z, C flags
hardware stack
named/static RAM
```

It also reserves the same two user zero-page pairs already used by the native
assembler:

```asm
NC_TMP = $fc      ; $fc/$fd: transient operator scratch
NC_PTR = $fe      ; $fe/$ff: transient indirect-address scratch
```

They are compiler-owned scratch, not C objects. Both are caller-clobbered and
neither may silently become long-lived storage.

A useful default lifetime order is:

```text
A / X / Y
processor flags
NC_TMP / NC_PTR
bounded hardware stack where explicitly justified
static spill only when the lifetime actually requires it
```

That is a preference, not a register allocator. The emitter chooses from a tiny
known set of machine situations at the point it emits code.

# 3. Binary arithmetic mode is an invariant

Nano C integer arithmetic always uses ordinary binary 6502 `ADC`/`SBC`
semantics.

The decimal flag is therefore part of the machine contract rather than ambient
machine state:

- generated Nano C code assumes `D = 0`;
- `__nc_init` executes `CLD` before any C code runs;
- Nano C generated code never executes `SED`;
- compiler support and runtime/KERNAL-facing routines return with `D = 0`.

A runtime helper may call code whose decimal-flag behaviour is outside the Nano
C contract, but it must execute `CLD` before returning to generated C.

# 4. Physical values are small 6502 facts

There is no universal “expression value register pair”. A source expression has
a C type, but its current physical representation is only as wide or as
materialised as its next consumer requires.

The useful vocabulary is intentionally small.

## 4.1 Byte value

```text
A = value
X = unspecified
```

This is the natural physical form for a `char` and for any result whose next
observable consumer needs only the low byte.

“X unspecified” is a promise to the consumer, not a demand that X contain
random data. An implementation may happen to leave zero there. It must not emit
`LDX #0` merely to make an unobserved high byte look tidy.

For example, the physical shape of an ordinary byte load is simply:

```asm
lda c
```

A byte store consumes only A:

```asm
sta c
```

## 4.2 Word or pointer value

```text
A = low byte
X = high byte
```

Use this form when the consumer genuinely observes a complete 16-bit value:

- a 16-bit arithmetic operation;
- a 16-bit store;
- a complete `int`/`unsigned` return under the current call convention;
- a `char *` value;
- a helper whose explicit contract requires A/X.

A named word load therefore has the familiar shape:

```asm
lda value
ldx value+1
```

and an address constant can naturally use:

```asm
lda #<text
ldx #>text
```

## 4.3 Condition

A comparison or truth test may be represented directly by live processor flags.
The compiler needs only enough compile-time information to know which 6502
branch observes “true”. Examples include `BNE`, `BEQ`, `BCC`, or `BCS`.

That state is physical and short-lived. Any emitted instruction that changes the
relevant flags ends its lifetime.

A condition does **not** have to be turned into an integer before an `if` or
`while` can consume it. For example:

```c
if (c < 10) {
    ...
}
```

may naturally reach the control-flow emitter as:

```asm
lda c
cmp #10
```

with carry describing the result. The branch consumes that carry directly.

A comparison can temporarily have both a materialised C value and useful live
flags. Current `nanoc0` still does this in several places. The important contract
change is that the flags are now a first-class physical fact rather than an
accidental property of a canonical 0/1 value.

## 4.4 Location

An lvalue is not automatically a generic 16-bit address. Keep the addressing
situation the 6502 can actually use.

The bounded vocabulary needed by Phase 1 includes:

```text
named scalar                 lda name / sta name
fixed array, byte index      lda array,y / sta array,y
byte pointer, byte index     lda (NC_PTR),y / sta (NC_PTR),y
full computed address        NC_PTR, then (NC_PTR),y
```

The first three should not be converted to the fourth merely to create a uniform
“address value”.

`nanoc0` already records the important indexed-lvalue distinction directly:
fixed-array byte indexing and a reloadable current-function byte pointer have
separate statement states; the remaining cases use the saved full-address
fallback. This is machine state, not an lvalue IR.

## 4.5 These facts are not an IR

The compiler does not retain a general record such as “value kind + register +
address mode + lifetime”. It emits source as soon as the parser knows enough.

`expressionValueType` remains the **source-semantic type**. It answers questions
such as signed versus unsigned comparison and parameter compatibility. It must
not be reinterpreted as a demand that a particular set of target registers be
filled.

Where a physical fact must survive between producer and immediate consumer,
keep exactly that fact. The first such explicit seam is the condition-branch
state in `expression_codegen_state.asm`: it names the branch that can observe
live flags. No general value object or register description is introduced.

# 5. Source semantics are not physical representation

C rules still apply even when the machine does less work.

## 5.1 Integer promotion does not mean eager zero-extension

A `char` participates in Phase 1 integer promotion according to the source
language rules. Semantically, an expression such as:

```c
c + 1
```

is integer arithmetic.

That does not imply that every earlier load of `c` must immediately execute:

```asm
ldx #0
```

If the eventual observable result is stored to another `char`, or a byte-native
operation can implement the required modulo-low-byte behaviour directly, the
high byte may never need to exist.

Conversely, when a later operation really observes the promoted 16-bit value,
the compiler must establish the correct high byte before that operation. The
semantic rule is unchanged; only the time at which machine state is manufactured
changes.

## 5.2 Comparison as value versus comparison as condition

A C comparison has the integer value 0 or 1 when that value is observed. Thus:

```c
x = a < b;
return a == b;
f(a != b);
```

must materialise a canonical integer result before the store, return, or call
consumer needs it.

Control flow is different:

```c
if (a < b) { ... }
while (a != b) { ... }
```

Here the next consumer asks only whether the condition is true. Processor flags
are already a complete physical representation of that question, so creating 0
or 1 first is unnecessary.

This distinction is central to the machine model, not a peephole optimisation.

# 6. Static storage instead of automatic stack frames

Phase 1 remains non-recursive and non-reentrant. Ordinary source parameters and
locals therefore have fixed storage owned by their function.

A function may also own bounded static storage for values that genuinely must
survive later source operations or calls. Such storage is a lifetime tool, not
the default representation of every intermediate expression.

Conceptually:

```c
int add(int a, int b)
{
    int result;

    result = a + b;
    return result;
}
```

has assembler-visible storage equivalent to:

```asm
__add_a      = NC_BSS+40
__add_b      = NC_BSS+42
__add_result = NC_BSS+44
```

No stack frame is created or destroyed.

A caller's ordinary locals survive a nested call because the callee owns
different addresses.

# 7. `NC_BSS`: explicit static RAM workspace

The native assembler can stage at most 16 KiB of output, while the bootstrap
source requires much more uninitialised workspace than can sensibly live in the
loaded PRG. Phase 1 therefore uses an explicit static RAM region.

The assembly wrapper supplies one absolute symbol:

```asm
NC_BSS = $5000       ; example only; the wrapper chooses the real address
```

`nanoc0` allocates zero-initialised globals and function-owned static storage as
offsets from that base:

```asm
ass_image        = NC_BSS+0
ass_image_length = NC_BSS+11264
```

These assignments emit no bytes. There is no allocator or linker: the compiler
maintains one monotonically increasing static offset while compiling the
translation unit.

It emits:

```asm
__nc_bss_end = NC_BSS+<total bytes>
```

so the chosen memory geometry remains visible.

## 7.1 Loaded data

Objects with explicit source initialisers remain ordinary loaded data because
their bytes must exist before C code runs:

```c
char widths[4] = {0, 1, 1, 2};
```

maps naturally to:

```asm
widths:
    byte 0,1,1,2
```

Explicitly initialised 16-bit tables use `word`, and strings remain labelled
bytes/string data. C64 RAM is writable, so these globals remain mutable.

## 7.2 Zero-initialised globals

Source-level uninitialised globals must begin as zero. They occupy the initial
part of `NC_BSS`, and the generated unit supplies:

```asm
__nc_init:
    cld
    ; clear [NC_BSS, __nc_zero_end)
    rts
```

The wrapper calls `__nc_init` once before generated C code. Function parameters,
locals and compiler lifetime storage lie after `__nc_zero_end` and do not need
startup clearing.

# 8. Calls: current implementation and physical contract

The call implementation present when this contract was adopted uses
callee-owned parameter slots plus `JSR`/`RTS`. Earlier arguments that must
survive later argument evaluation use caller-owned staging slots.

That is an implementation baseline, not a reason to force every expression into
one universal A/X form. Issue #89 owns the call/return redesign and may use live
6502 state more directly while preserving the same source semantics.

Until that redesign, a complete `int` result returned from a C-defined function
is consumed as:

```text
A = low byte
X = high byte
```

and every call may clobber:

- A;
- X;
- Y;
- ordinary processor flags;
- `NC_TMP`;
- `NC_PTR`.

The decimal-mode invariant is the exception: returns re-enter generated Nano C
with `D = 0`.

A useful condition flag therefore never survives a call unless a future explicit
call contract says otherwise. The compiler's condition state is cleared at a
call boundary.

# 9. Expression evaluation is streaming and lifetime-driven

Expressions are parsed with the existing explicit bounded operator stack. There
is no expression tree and no runtime expression stack.

The parser evaluates source left to right as Phase 1 requires. When a left value
must survive evaluation of later source, the compiler chooses the smallest
clear lifetime mechanism available. A static spill remains valid where the
lifetime really crosses code that can clobber the live machine state; it is no
longer the conceptual baseline for every binary operator.

The current implementation still contains conservative A/X spills and eager
high-byte construction inherited from the old contract. Those are transitional
lowering choices, not semantic requirements. Issue #88 owns the first systematic
byte/condition rewrite.

## 9.1 Genuine 16-bit arithmetic

When both bytes are observable, ordinary 16-bit 6502 arithmetic is exactly the
right shape. For example, a word addition may use a saved operand and carry from
low byte to high byte. Nothing in the new contract tries to disguise that as a
byte operation.

The distinction is simply this: do not execute the high-byte half until the
consumer actually requires a 16-bit result.

## 9.2 Conditions and branch reach

When no useful comparison flags are live, truth testing a byte needs only the
byte. A genuine 16-bit truth test must account for both bytes.

When useful flags *are* live, the statement emitter should branch from them
directly rather than reconstructing truth from a materialised Boolean.

`nanoc0` still deliberately avoids branch-distance analysis. A generated
conditional transfer uses a nearby relative branch over an absolute `JMP`, for
example:

```asm
    bne .condition_true
    jmp .false_target
.condition_true:
```

The relative target is local by construction. No branch relaxation or retained
layout analysis is implied by the physical condition model.

## 9.3 Multiplication and shifts

A repeated 16-bit multiplication may still use the small private
`__nc_mul16` helper. Variable 16-bit shifts may still use `NC_TMP` and Y for a
short loop. These are explicit target routines for genuine 16-bit operations,
not evidence for a universal expression representation.

# 10. Arrays and pointers are addressing modes first

There is no bounds checking.

Indexing should follow the 6502 instruction set rather than first constructing a
generic address object.

## 10.1 Fixed `char` arrays

If the index is physically a byte, a fixed `char[]` read is naturally:

```asm
    tay
    lda array,y
```

X is unspecified because the loaded value is a byte. There is no reason to form
`array + index` in zero page merely to access offset zero from the computed
address.

A store uses the same absolute-`,Y` form. If the RHS must be evaluated first,
only the byte index needs to survive that evaluation.

## 10.2 `char *` with a byte index

A runtime pointer needs an indirect base, so place the pointer in `NC_PTR` and
the byte index in Y:

```asm
    tay
    lda (NC_PTR),y
```

Again, the result is physically a byte in A. Do not create a second 16-bit
pointer equal to `pointer + index` merely to use `(zp),Y` with Y=0.

## 10.3 Full 16-bit and scaled indexing

A wide index or a two-byte element genuinely requires more work:

```text
effective address = base + scaled index  (mod 65536)
```

The current fallback computes that address in `NC_PTR`. A 16-bit load through it
then returns a word in A/X. That is the correct physical form because both bytes
are observable.

## 10.4 Indexed assignment lifetime

The compiler saves only what must survive the RHS:

- fixed `char[]`, byte index: the one-byte index;
- reloadable current-function `char *`, byte index: the index, then reload the
  pointer slot;
- global pointer, wide index, scaled element, or general case: the complete
  effective address.

This is precisely the lifetime distinction an assembly programmer would make by
hand.

# 11. Data layout

Object widths remain exactly the Phase 1 source widths:

```text
char      1 byte
int       2 bytes, little-endian
unsigned  2 bytes, little-endian
char *    2 bytes, little-endian address
```

There is no alignment padding. Arrays are contiguous element sequences.

`nanoc0` has two storage destinations:

```text
explicitly initialised globals / strings -> loaded assembly image
zero-initialised globals                 -> NC_BSS, cleared by __nc_init
```

Function-owned static storage also lives in `NC_BSS` after the zero-required
global region.

# 12. Runtime calls

The Phase 1 source runtime remains exactly:

```c
int io_open(char *name, int length);
int io_read(int handle);
int io_create(char *name, int length);
int io_write(int handle, int value);
int io_close(int handle);
```

These are assembly helpers, not a standard library. Their current parameter-slot
implementation follows the call baseline above and is subject to the same #89
machine-native redesign.

The C64 runtime still provides the existing file semantics: bounded handles,
KERNAL file calls, `-1` EOF from `io_read`, explicit output creation, and `D = 0`
on return. None of that depends on canonicalising every intermediate expression.

# 13. Assembly wrapper boundary

A compiled Phase 1 translation unit is not an object file and does not choose a
universal C64 memory map.

A tiny assembly wrapper supplies placement, for example:

```asm
NC_BSS = $5000

* = $1000
include "generated.asm"
```

The wrapper is responsible for choosing the memory map, calling `__nc_init`, and
calling the desired C entry point. Compiler-private support is emitted directly
in the generated `ass` source; there is no separate linker step.

# 14. Worked physical examples

These examples describe the contract the lowering should approach. They are not
claims that the #87 implementation has already completed the #88 rewrite.

## 14.1 Byte comparison consumed by control flow

```c
if (c == 'A') {
    found = 1;
}
```

The important machine state is:

```asm
    lda c
    cmp #'A'          ; flags now are the condition
```

The statement emitter can consume those flags directly using the appropriate
local-branch-over-`JMP` form. No integer Boolean is needed between `CMP` and the
branch.

## 14.2 The same comparison consumed as a value

```c
x = c == 'A';
```

Here the store observes a 16-bit `int`. The comparison may begin identically,
but before the store the compiler must materialise exactly 0 or 1 in the
physical form the 16-bit destination consumes.

The difference comes from the consumer, not from a different source meaning for
`==`.

## 14.3 Byte promoted only when observed as a word

```c
char c;
int x;
x = c;
```

Loading `c` needs only A. The assignment to `x` is the point at which the high
byte becomes observable, so zero-extension belongs there—not automatically at
the load.

## 14.4 Pointer byte store

```c
p[i] = value;
```

For a byte index and reloadable current-function pointer, a natural lifetime is:

```text
1. save the byte index;
2. evaluate value;
3. preserve the result byte briefly;
4. reload p into NC_PTR;
5. load the saved index into Y;
6. STA (NC_PTR),Y.
```

A global pointer may require the complete effective address to be saved before
the RHS because the RHS is allowed to change that global pointer.

# 15. Compiler invariants

A 6502 reader should be able to reason about `nanoc0` from these invariants:

1. **Source type and physical machine state are different facts.**
2. **A byte value needs only A; X is unspecified until a consumer requires a high byte.**
3. **A genuine word or pointer uses A=low, X=high.**
4. **A condition may live entirely in processor flags, together with the branch that observes true.**
5. **A comparison becomes integer 0/1 only when a value consumer requires it.**
6. **Use named memory, `array,Y`, and `(NC_PTR),Y` directly when those are the actual locations.**
7. **A call destroys ordinary registers, flags and zero-page scratch under the current contract.**
8. **Anything that truly must outlive such clobbering receives explicit longer-lived storage.**
9. **`NC_PTR` and `NC_TMP` are transient target scratch, not hidden C objects.**
10. **Nano C arithmetic runs with `D = 0`.**
11. **Ordinary source locals remain fixed static storage while Phase 1 is non-recursive/non-reentrant.**
12. **Conditional control flow retains local relative branches over absolute `JMP`s; no branch-distance machinery is added.**
13. **The streaming parser/emitter does not acquire a generic intermediate representation to express these facts.**
14. **Every manufactured high byte, Boolean value, address, spill, save or reload should have an observable semantic or lifetime reason.**

# 16. Convergence frame

The contract changed because generated-code evidence showed a systemic machine
mismatch, not because of stylistic preference.

At the #87 baseline after #74:

```text
handwritten production assembler image     about  8,124 bytes
generated bootstrap/ass.c image            about 19,868 bytes
generated C-function instructions          about 18.4 KiB
LDX #$00 in generated bootstrap             about    758
```

Those zero-high loads alone consume roughly 1.5 KiB before secondary effects.

The 16 KiB assembler staging region is a **hard bootstrap ceiling**, not the
quality target. The engineering target is the handwritten assembler's roughly
8.1 KiB footprint: approach it closely enough that each remaining abstraction
cost can be explained in ordinary 6502 terms.

Issue #87 establishes the physical contract and the compiler seam. It does not
claim the size reduction itself:

- #88 owns byte-native values, deferred zero-extension and direct flag
  consumption;
- #89 owns the call/return convention;
- #90 owns the remaining location/index representation;
- later profiling decides whether another systemic contract correction is
  needed.

This ordering is deliberate. First make the machine model say the right thing;
then make each emitter obey it without hiding the work inside an optimizer.
