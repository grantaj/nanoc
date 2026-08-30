# Nano C Phase 1 compiler architecture

This document defines the implementation shape of `nanoc0`, the hand-written
6502 compiler for Nano C Phase 1.

The source language is defined in `docs/phase1.md` and the target machine model
in `docs/phase1-machine.md`. This document sits between them: it records the
smallest compiler architecture that connects the two without introducing
compiler machinery that the language does not need.

The governing principle remains:

> Nano C is a more convenient way to write 6502 assembly.

The compiler should therefore be understandable as a small amount of source
recognition and bookkeeping wrapped around assembly emission. It is not a
small implementation of a modern compiler architecture.

# 1. Overall shape

`nanoc0` is a streaming, single-pass compiler in the practical sense that
source is consumed from beginning to end once and assembly is emitted as soon
as a construct is understood.

```text
source bytes
    |
    v
small scanner
    |
    | one current token
    v
parser + direct emitter
    |
    v
ass assembly text
```

There is:

- no persistent token stream;
- no AST;
- no generic IR;
- no second semantic pass;
- no register allocator;
- no optimiser framework;
- no object file or linker stage.

A few small explicit stacks and tables are retained only because later source
needs them: symbols, expression operators, structured-control state, pending
calls, and string literals.

# 2. Declare before use everywhere

Phase 1 uses declaration-before-use as a universal source rule.

This is intentionally stricter than historical C's old implicit-function
behaviour. Nano C has **no implicit declarations**. If a source name has not
already been declared or defined, any occurrence of that name is an error.
Assignment does not create a variable: the target of `x = ...` must already be
declared just like a value read from `x`.

When the parser encounters a source identifier, its meaning is already known.
The only predeclared names are the small runtime functions defined by the
Phase 1 environment.

Concretely:

- all globals are declared before the first function;
- a global is known only after its declaration has been consumed;
- functions are defined before any later function calls them;
- there are no prototypes;
- there are no implicit function declarations;
- parameters are declared in the function header before the body;
- all locals are declared at the start of the function before executable
  statements;
- there are no block-local declarations;
- assignment targets must already be declared;
- a local or parameter therefore exists before every possible read or write;
- runtime functions are the sole predefined exception.

Global initialisers are deliberately restricted constant forms and therefore
do not create a hidden forward-reference problem.

This rule is central to the architecture, not merely a language style choice.
`nanoc0` does not need a declaration pass, unresolved C-symbol records, or
source-level fixups. Lookup either succeeds immediately or the compiler reports
an undeclared identifier.

Phase 1 also has no source-level labels and no `goto`. The compiler therefore
has no C label namespace or source-label fixups. Generated assembly still uses
synthetic labels for structured control flow; those are compiler output and are
resolved by `ass`.

# 3. Source input: bytes, not lines

C source is a character stream. Physical line endings are whitespace plus a
source-position update.

The input layer needs only:

```text
current input handle
current byte
one-byte lookahead/pushback state
current line number
end/error state
```

A small refill buffer is acceptable if it makes KERNAL I/O cheaper, but parser
state must not depend on buffer or line boundaries. A block comment, expression
or declaration may cross a physical line.

The scanner never retains the whole source file.

# 4. Scanner: one reusable token

Nano C needs more lexical recognition than `ass`, but it still does not need a
lexer phase.

`next_token` consumes source bytes and replaces one reusable current-token
record. Conceptually that record contains:

```text
token kind
integer value          when the token is numeric/character
integer type           int or unsigned where relevant
text length            for identifier/string text
text buffer             reusable bounded bytes
source line
```

Whitespace and `/* ... */` comments disappear in the scanner.

Useful token kinds are deliberately small:

- identifier;
- integer literal;
- character literal;
- string literal;
- Phase 1 keywords such as `int`, `unsigned`, `char`, `if`, `else`, `while`,
  `break`, `return`;
- single-character punctuation/operators represented directly where convenient;
- the two-character operators `==`, `!=`, `<=`, `>=`, `<<`, `>>`.

There is no separate token object for every occurrence in the source.

An identifier remains in the reusable token text buffer only until the parser
has decided what it means. A name is copied only if it must outlive that token,
for example when entering a global/function symbol or a current-function local.
This preserves the same copy-only-when-owned principle used by the assembler.

Keywords can be recognised immediately after scanning an identifier. The parser
therefore does not repeatedly compare arbitrary identifier text with language
keywords.

# 5. Direct parser and emitter

The parser does not construct a representation and later walk it. Recognising a
construct and generating its assembly are one operation.

Examples:

```text
recognise global declaration
    -> allocate its storage / emit initialised bytes

recognise local declaration
    -> allocate its fixed NC_BSS slot

recognise expression
    -> emit code leaving its value in A/X

recognise assignment
    -> emit the store

recognise if/while
    -> allocate synthetic labels and emit control flow
```

This is possible because declaration-before-use means all semantic information
needed at a use site is already present.

The parser owns one `current_token`. `next_token` advances it. There is no need
for arbitrary token backtracking. Where grammar decisions require lookahead,
the parser consumes the small prefix and chooses the corresponding construct.

An executable statement beginning with an identifier first performs symbol
lookup. The following token then distinguishes only the forms Phase 1 permits:

```text
identifier '=' ...        scalar assignment
identifier '[' ...        indexed assignment
identifier '(' ...        function call statement
```

There is no `identifier ':'` case because C labels do not exist in Phase 1.
Phase 1 also excludes assignment expressions and arbitrary expression
statements, making this decision much simpler than general C.

# 6. Symbol state

The compiler keeps two deliberately boring linear symbol areas.

## 6.1 Persistent translation-unit symbols

These contain globals and already-defined functions.

A global record needs only information such as:

```text
name
kind                   scalar / array / function
type
assembler-visible name
array length           when applicable
```

A function additionally needs enough metadata for later callers:

```text
parameter count
parameter types
parameter slot names or identifiers
```

The exact representation should use compact parallel arrays unless implementation
evidence shows that another fixed representation is simpler.

Because functions are definition-before-use, no function symbol exists in a
half-declared state.

## 6.2 Current-function symbols

Parameters and locals are held separately from translation-unit globals.
Lookup order is:

```text
current function parameters/locals
then globals/functions
then error
```

The current-function table can be discarded/reused when the function ends.
Persistent function metadata retains only what later callers need.

# 7. Static storage allocation while parsing

The Phase 1 machine model gives every function fixed storage for parameters,
locals, expression spills, saved effective addresses and call staging.

`nanoc0` maintains a monotonically increasing `NC_BSS` offset.

Storage that is known at function entry is allocated immediately:

- parameters;
- locals.

Compiler-created storage is allocated on demand the first time a depth is
needed:

- expression spill depth 0, 1, ...;
- saved indexed-lvalue addresses;
- call-staging depth and argument slot.

The compiler may emit zero-byte assembler symbol assignments at the point where
such storage is allocated. It does not need to know the function's maximum
expression or call depth before compiling the function body.

This avoids a preliminary function-analysis pass.

# 8. Expressions: explicit operator stack, no recursion

Expression parsing is the main place where a conventional recursive-descent
compiler would fight the Phase 1 bootstrap language. The self-hosted compiler
must itself be expressible without recursion, so `nanoc0` uses an explicit
bounded operator stack from the beginning.

The expression engine is shunting-yard-like, but it does **not** produce an RPN
stream or expression tree. Reducing an operator emits assembly immediately.

For:

```c
a + b * c
```

the conceptual flow is:

```text
load a -> A/X
spill A/X to function temp 0
push +

load b -> A/X
spill A/X to function temp 1
push *

load c -> A/X

reduce * using temp 1 and A/X -> A/X
reduce + using temp 0 and A/X -> A/X
```

An operator-stack entry needs only enough state to perform that later reduction,
for example:

```text
operator
left spill slot/depth
left type
```

Parentheses are markers on the same stack. When `)` is seen, operators reduce
until the matching marker.

Precedence is a tiny fixed mapping matching `docs/phase1.md`.

The current value is always in `A/X`, exactly as the machine model specifies.
Values that must survive parsing/evaluating a later operand are already in
function-owned static spill storage.

There is no runtime expression stack and no compiler recursion.

# 9. Primary expressions

Primary expressions are handled directly by the expression engine.

## 9.1 Literals and variables

Numbers, characters and named scalar values emit an immediate or memory load
into `A/X`.

A named array in the limited Phase 1 contexts where it decays to `char *`
emits its assembler address.

## 9.2 Function calls

A call is a primary expression whose final value is the callee's `A/X` result.

A small explicit pending-call stack records, for each nested call:

```text
callee function symbol
argument index
call nesting depth
expression-stack boundary for the current argument
```

Arguments are evaluated left to right.

At a comma or closing `)`:

1. reduce the current argument expression to A/X;
2. save it to caller-owned static staging for this pending-call depth;
3. advance the argument index.

At the closing `)` of the call:

1. validate argument count/types;
2. copy the staged values to the callee's fixed parameter slots;
3. emit `JSR callee`;
4. leave the returned value in A/X.

Nested calls use a deeper pending-call/staging depth, so:

```c
f(x, f(y, z))
```

cannot overwrite the already-staged outer `x`.

The pending-call stack is compiler state only. No C argument uses the 6502
hardware stack.

## 9.3 Indexing

For `base[index]`, the index is an ordinary expression.

The parser records the base/type, evaluates and reduces the index to A/X, then
emits the effective-address calculation described in `docs/phase1-machine.md`.
A value load through `NC_PTR` leaves the result in A/X.

For an indexed assignment lvalue, the effective address is saved in
function-owned static storage before the right-hand expression is evaluated,
because that expression may contain calls or further indexing that clobber
`NC_PTR`.

# 10. Statements and structured control: explicit control stack

Statement/block nesting also avoids compiler recursion.

The compiler keeps a small explicit control stack. Frames represent the source
constructs whose end has not yet been seen, for example:

```text
BLOCK
IF
WHILE
```

An `IF` frame owns generated false/end labels and enough state to handle an
optional following `else`.

A `WHILE` frame owns:

```text
loop top label
loop end label
```

`break;` searches downward for the nearest `WHILE` frame and emits a jump to
its end label.

Braces drive frame completion. The parser does not call itself recursively to
compile a nested block.

This explicit state should remain small because Phase 1 programs are expected
to have modest syntactic nesting; the implementation can impose a clear fixed
limit.

# 11. Conditional transfers are always long-form

`nanoc0` never tracks whether a control-flow target happens to lie within the
6502 relative-branch range.

Every generated conditional transfer whose semantic target may be non-local is
written as a short branch over an absolute jump:

```asm
    b<opposite-condition> .near
    jmp far_target
.near:
```

The relative target is generated immediately adjacent and is therefore always
in range. `JMP` carries the real control transfer.

This is unconditional policy, not a fallback. There is no branch-distance
analysis, relaxation or later layout pass.

A few bytes of occasionally unnecessary `JMP` code are cheaper than compiler
state devoted to an optimisation whose only purpose is to save those bytes.

# 12. Strings and other deferred assembly text

Explicitly initialised globals appear before functions and can be emitted when
parsed.

String literals inside function bodies are different: emitting their bytes at
the point of use would place data in the middle of executable code.

`nanoc0` therefore retains a bounded literal pool containing only the bytes and
generated label of string literals encountered while compiling functions.
The expression itself simply loads the generated label address.

After all function code has been emitted, the compiler emits the accumulated
literal data.

This is a narrow deferred-data mechanism, not a general IR or data-section
framework.

# 13. Output I/O required for self-hosting

The `ass.c` experiment needed only input, so the first runtime boundary contained:

```c
int io_open(char *name, int length);
int io_read(int handle);
int io_close(int handle);
```

The compiler itself provides concrete new evidence: a self-hosted Nano C
compiler must create and write its generated assembly.

The Phase 1 bootstrap runtime therefore also needs the minimal output surface:

```c
int io_create(char *name, int length);
int io_write(int handle, int value);
```

`io_create` returns a non-negative handle or `-1` on failure.
`io_write` writes the low byte of `value` and returns `0` on success or `-1` on
failure.

These remain runtime services, not language features or a standard library.
`nanoc0` and the later Phase 1 C compiler should use the same conceptual I/O
boundary so the assembly bootstrap does not rely on capabilities the
self-hosted compiler cannot express.

Assembly emission can then be extremely direct: small routines write fixed
mnemonic fragments, generated symbol text, decimal/hex numbers and line endings
through `io_write`.

# 14. Minimal persistent compiler state

The complete persistent state should be recognisable from this list:

```text
input state
current token + reusable token text
source line number
translation-unit symbol table
current-function symbol table
NC_BSS offset
current function
expression operator stack
expression spill depth
pending-call stack / call depth
structured-control stack
generated-label counter
string-literal pool
output handle / status
```

If implementation begins accumulating substantially more persistent state than
this, that is a reason to inspect the design rather than assume another compiler
layer is needed.

# 15. Worked control-flow shape

For:

```c
while (i < n) {
    if (p[i] == 0) {
        break;
    }
    i = i + 1;
}
```

`nanoc0` conceptually does:

```text
allocate while_top, while_end
push WHILE(while_top, while_end)
emit while_top

compile i < n -> A/X
emit false transfer using branch-over-JMP -> while_end

push block/if state as braces and if are encountered
compile p[i] == 0 -> A/X
emit false transfer using branch-over-JMP -> if_end

break -> find nearest WHILE -> JMP while_end

emit if_end
compile i = i + 1

on closing while brace:
    JMP while_top
    emit while_end
    pop WHILE
```

Nothing in this process requires retaining the body, building a tree, or knowing
instruction addresses.

# 16. Why this should self-host cleanly

The architecture intentionally uses only mechanisms that have straightforward
Phase 1 C representations:

- fixed global arrays for symbol/control/operator/call tables;
- integer indices instead of recursive calls;
- `while` loops instead of recursive grammar descent;
- pointer-plus-length/token-buffer text handling;
- direct output through a tiny runtime;
- explicit fixed storage rather than allocation.

That matters because `nanoc0.asm` is not the architecture's final home. The next
milestone is to rewrite the compiler clearly in Phase 1 C.

A bootstrap architecture that is elegant only in assembly but awkward or
impossible in Phase 1 C would defeat the purpose of the language we just
designed.

# 17. Implementation boundary

This document fixes the architecture before #36 begins substantive compiler
implementation.

Implementation may choose exact table capacities, record encodings and routine
boundaries from measured needs. Those choices should remain explicit and
bounded.

A concrete result may reveal that one small part of this design is unnecessarily
complicated. In that case simplify the smallest thing supported by evidence.
Do not use implementation friction as a reason to introduce a conventional
token stream, AST, IR, software stack, branch relaxation or general compiler
framework.
