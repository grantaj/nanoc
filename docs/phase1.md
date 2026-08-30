# Nano C Phase 1

Nano C Phase 1 is the bootstrap language implemented by the hand-written 6502 compiler `nanoc0`.

It is deliberately small. Its purpose is to express two real programs clearly enough to escape assembly:

1. the C reimplementation of `ass`;
2. the first C reimplementation of Nano C itself.

Phase 1 is not a promise of ISO C compatibility and it is not the final Nano C language. It is the smallest useful C dialect justified by the bootstrap.

The evidence for this specification is `bootstrap/ass.c`. The rule used to extract the language is:

> Keep a feature when removing it would materially damage the clarity of a real bootstrap program. Do not add a feature merely because conventional C has it.

## Bootstrap position

```text
ass, written in 6502 assembly
        |
        | assembles
        v
nanoc0, written in 6502 assembly
        |
        | compiles Phase 1 C
        v
ass.c and then nanoc.c
```

The modern host compiler used while developing `ass.c` is only an independent behaviour check. It does not define any rule in this document.

## What the `ass.c` experiment established

The following features materially contribute to clear source and therefore belong in Phase 1:

- byte and 16-bit scalar values;
- `char *` source views;
- fixed one-dimensional arrays;
- global scalar and array storage;
- static/global initialisation;
- ordinary function parameters and local variables;
- `if` / `else`;
- `while`;
- `break`;
- `return`;
- simple assignment;
- multiplication as well as addition and subtraction;
- shifts and the bitwise operators actually used by the assembler;
- comparisons;
- array indexing and byte-pointer addition;
- integer, character and string literals;
- block comments.

Several familiar C features did not earn a place: `struct`, `for`, `switch`, `++`, logical operators, a preprocessor, dynamic allocation and separate compilation are all absent without making `ass.c` pseudo-assembly.

Two small additions are justified even though the #33 candidate does not yet use their final spelling everywhere:

- `unsigned` is required to represent the complete 16-bit address/value range without replacing natural negative status results with magic sentinel values;
- hexadecimal integer literals are justified by the machine-facing compiler/runtime work that immediately follows and are trivial compared with forcing 6502 addresses to be written in decimal.

Those are evidence-driven additions, not a move toward general C completeness.

# 1. Translation unit

A Phase 1 program is one translation unit.

There are no headers, includes, preprocessing, object files or language-level separate compilation.

The translation unit has this shape:

```text
global declarations
function definitions
```

All global declarations must precede the first function definition. Once function definitions begin, no further globals may be declared.

A C-defined function must be defined before another C-defined function calls it. Function prototypes are not supported.

The implementation may predeclare a small runtime interface. Those runtime functions may be called without a source-level declaration; see section 10.

This ordering rule is intentional. It allows `nanoc0` to compile directly from top to bottom without first building a general declaration/type graph.

# 2. Lexical rules

## 2.1 Identifiers

An identifier begins with an ASCII letter or `_` and continues with ASCII letters, decimal digits or `_`.

Identifiers are case-sensitive.

```text
identifier := (letter | '_') (letter | digit | '_')*
```

There is no implementation-significant identifier shortening in the language definition. A concrete compiler may impose a documented storage limit.

## 2.2 Whitespace

Space, horizontal tab, carriage return and line feed are whitespace.

## 2.3 Comments

Phase 1 supports C block comments:

```c
/* comment */
```

Comments do not nest.

`//` comments are not Phase 1.

# 3. Types and machine values

Phase 1 has four source-level type forms:

```text
char
int
unsigned
char *
```

`unsigned` means `unsigned int`. The spelling `unsigned int` is not required in Phase 1.

No other pointer type is required.

## 3.1 `char`

`char` is an unsigned 8-bit byte with range 0 through 255.

Assigning a 16-bit integer value to `char` stores the low eight bits.

Using a `char` in an integer expression zero-extends it to 16 bits.

There is no signed character type in Phase 1.

## 3.2 `int`

`int` is a 16-bit two's-complement signed integer with range -32768 through 32767.

Arithmetic overflow is **defined to wrap modulo 65536**. Nano C does not inherit ISO C's undefined signed-overflow rule.

The stored representation is the ordinary 16-bit two's-complement bit pattern.

## 3.3 `unsigned`

`unsigned` is a 16-bit unsigned integer with range 0 through 65535.

Arithmetic wraps modulo 65536.

`unsigned` exists because real Phase 1 software needs both:

- complete 6502 address/value bit patterns such as `$c000`;
- natural signed results such as `-1` from searches or I/O.

Forcing both roles through one signed 16-bit type makes ordinary range comparisons wrong above `$7fff`. Forcing both through one unsigned type turns natural error handling into magic-value code. `ass.c` demonstrated that the extra type is worth its small compiler cost.

## 3.4 Integer conversions

`char` promotes to `int` before arithmetic or comparison.

Converting between `int` and `unsigned` preserves the low 16-bit representation.

For a binary arithmetic, shift, bitwise or comparison operator:

- if both operands are `int`, signed interpretation is used where interpretation matters;
- if either operand is `unsigned`, both operands are interpreted as `unsigned` and the result uses unsigned interpretation;
- comparison results are always the `int` value 0 or 1.

This is the only arithmetic conversion rule Phase 1 needs.

## 3.5 Pointers

A `char *` is a 16-bit machine address.

The null-pointer abstraction is not part of Phase 1; a pointer is simply an address value supplied by an array/string, another pointer, a function parameter, or the runtime.

Supported pointer operations are deliberately narrow:

- assignment from another `char *`;
- passing and returning through parameter storage as required by calls;
- adding a 16-bit integer to a `char *`;
- indexing with `pointer[index]`;
- passing a character array or string literal where `char *` is required.

Pointer addition is byte-scaled and wraps modulo 65536.

Pointer subtraction, pointer ordering, general integer/pointer casts, `&` and unary `*` are not Phase 1.

## 3.6 Arrays

Phase 1 supports fixed, one-dimensional arrays of:

```text
char
int
unsigned
```

The array size is a positive integer literal known at compile time.

Array elements are contiguous. `char` elements occupy one byte; `int` and `unsigned` elements occupy two bytes.

Indexing is zero-based.

A character array used as a function argument or as the left operand of `+` yields a pointer to its first byte. This is the array-to-pointer behaviour required by `ass.c`.

`int` and `unsigned` arrays are indexable but Phase 1 does not require general `int *` or `unsigned *` decay.

## 3.7 Byte order

16-bit integers, unsigned values and pointers are stored little-endian: low byte first, high byte second.

# 4. Literals

## 4.1 Decimal integers

Decimal integer literals contain one or more decimal digits.

A non-negative literal from 0 through 32767 has type `int`.

A non-negative literal from 32768 through 65535 has type `unsigned`.

Literals outside 0 through 65535 are rejected.

Unary minus may be applied to an integer literal or expression. `-1`, `-2` and similar status values therefore remain ordinary signed `int` expressions.

## 4.2 Hexadecimal integers

Phase 1 accepts C-style hexadecimal literals:

```c
0x00
0xff
0xc000
0xffff
```

`0x` and `0X` are both accepted; hexadecimal digits are case-insensitive.

The same type rule as decimal literals applies to the resulting value: 0 through 32767 is `int`, 32768 through 65535 is `unsigned`.

## 4.3 Character literals

A character literal contains exactly one byte character:

```c
'A'
' '
';'
```

Its expression type is `int` and its value is the unsigned byte value of that character.

Escape sequences are not required in Phase 1.

## 4.4 String literals

A string literal is a sequence of byte characters between double quotes.

The compiler emits an anonymous static character array containing the bytes followed by one zero byte. In an expression the literal yields a `char *` to the first byte.

Escape sequences and adjacent-string concatenation are not Phase 1.

# 5. Declarations and storage

## 5.1 Global scalars

Supported global declarations include:

```c
char flag;
char flag = 1;
int count;
int count = -1;
unsigned address;
unsigned address = 0xc000;
char *source;
```

One declarator appears in each declaration. Comma-separated declarator lists are not Phase 1.

An uninitialised global scalar is initialised to zero.

A global scalar initializer must be an integer or character constant expression representable by the destination type. A `char *` global does not require a source-level initializer in Phase 1.

## 5.2 Global arrays

Supported forms are:

```c
char bytes[4];
int words[4];
unsigned addresses[4];

char widths[4] = {0, 1, 1, 2};
unsigned table[3] = {0x4000, 0xc000, 0xffff};
char text[4] = "abc";
```

Numeric array initializers are brace-enclosed comma-separated integer or character constant expressions.

An initializer may provide fewer elements than the declared size; the remainder is zero-filled. Providing more elements than the declared size is an error.

A string initializer for a `char` array includes its terminating zero and must fit in the declared array.

Uninitialised global arrays are zero-filled.

Local arrays are not Phase 1.

## 5.3 Function parameters and locals

Function parameters may have type:

```text
char
int
unsigned
char *
```

Local variables may have the same types except that no local array form is supported.

All local declarations appear immediately after the opening brace of the function body, before the first executable statement.

There are no block-local declarations.

A local has no source-level initializer in Phase 1. A well-formed program assigns a local before reading its value.

This restriction deliberately makes the physical storage strategy unobservable: #35 may allocate one fixed parameter/local area per function rather than building general automatic stack frames.

## 5.4 Recursion and reentrancy

Phase 1 is non-recursive.

A well-formed Phase 1 program has an acyclic call graph among its C-defined functions. A function must not be entered again before its previous invocation returns.

`nanoc0` is not required to perform a general call-graph analysis to diagnose mutual recursion. Programs that violate this rule are outside Phase 1.

This restriction is deliberate. `ass.c` does not need recursion, and removing it allows #35 to consider statically allocated per-function parameters and locals instead of immediately introducing a general software stack/frame ABI.

Nested calls to different functions are fully supported and must preserve the caller's local values.

# 6. Functions

A Phase 1 C-defined function returns `int` and has zero or more typed parameters.

Examples:

```c
int read_byte()
{
    int value;

    value = io_read(0);
    return value;
}

int same_text(char *a, int a_length, char *b, int b_length)
{
    /* ... */
}
```

`void` functions are not required. A function whose result is ignored still returns an `int` value.

Function prototypes are not supported.

A C-defined function must be defined before use. Runtime functions are the sole predeclared exception.

Arguments are evaluated from left to right.

The number of arguments in a call to a known C-defined or runtime function must match its parameter count.

Phase 1 does not define varargs, function pointers or old-style untyped parameter declarations.

# 7. Statements

Phase 1 statements are:

```text
block
assignment statement
function-call expression statement
if statement
while statement
break statement
return statement
```

A block is:

```text
{ statement* }
```

No declarations occur inside an executable block.

## 7.1 Assignment

Assignment is a statement, not a general expression operator.

```text
lvalue '=' expression ';'
```

A Phase 1 lvalue is either:

- a scalar variable;
- an array element;
- a `char *` indexed element.

Examples:

```c
count = count + 1;
bytes[i] = value;
pointer[i] = c;
```

Compound assignment operators are not Phase 1.

## 7.2 Function-call statement

A function call may appear as a statement when its result is ignored:

```c
io_close(handle);
```

General unused arithmetic expressions are not required as statements.

## 7.3 `if` / `else`

Phase 1 requires braces around controlled bodies:

```c
if (condition) {
    statements
} else {
    statements
}
```

The `else` clause is optional.

Mandatory braces avoid dangling-`else` machinery and match the style already used by the bootstrap source.

## 7.4 `while`

Phase 1 loop syntax is:

```c
while (condition) {
    statements
}
```

The controlled body uses braces.

`for` and `do` are not Phase 1.

## 7.5 `break`

`break;` exits the nearest enclosing `while` loop.

`break` earned its place in `ass.c`: removing it makes scanners depend on artificial flags or duplicated loop conditions.

`continue` is not Phase 1.

## 7.6 `return`

Every return has a value:

```c
return expression;
```

Falling off the end of a function is outside well-formed Phase 1; every control-flow path must return an `int` value.

# 8. Expressions

Phase 1 deliberately omits several C operators. The supported expression grammar is sufficient for `ass.c` and the first compiler.

From highest precedence to lowest:

| Level | Forms | Associativity |
| --- | --- | --- |
| primary | literals, variables, `(expr)`, call, `a[i]` | left |
| unary | `-expr` | right |
| multiplicative | `*` | left |
| additive | `+` `-` | left |
| shift | `<<` `>>` | left |
| relational | `<` `<=` `>` `>=` | left |
| equality | `==` `!=` | left |
| bitwise AND | `&` | left |
| bitwise OR | `|` | left |

Assignment is intentionally not in this table because Phase 1 assignment is a statement.

The supported operators are:

```text
unary:  -

binary:
    *
    + -
    << >>
    < <= > >=
    == !=
    & |
```

Division, remainder, bitwise XOR, logical `!`, `&&`, `||`, bitwise `~`, increment/decrement, ternary `?:`, comma expressions and assignment expressions are not Phase 1.

## 8.1 Truth

Zero is false. Any nonzero scalar integer value is true.

Comparisons produce exactly `int` 0 or `int` 1.

Pointers are not required as conditions in Phase 1.

## 8.2 Arithmetic

`+`, `-` and `*` operate on 16-bit promoted integer values and wrap according to section 3.

Multiplication is intentionally present. `ass.c` uses it for decimal parsing and fixed-width table indexing; replacing these operations with source-level shift/add code would make the C more machine-like without materially simplifying the language.

Division and remainder have not earned Phase 1 support.

## 8.3 Shifts

The right operand of `<<` or `>>` must evaluate to a value from 0 through 15. Other shift counts are outside well-formed Phase 1.

Left shift discards bits shifted beyond bit 15.

Right shift of `unsigned` is logical. Right shift of non-negative `int` is logical and produces the same bit result. Phase 1 programs must not right-shift a negative `int` value.

This avoids adding an arithmetic-right-shift semantic requirement that no bootstrap program needs.

# 9. Compact grammar

This grammar is descriptive rather than a demand for a particular parser architecture.

```text
translation-unit
    := global-declaration* function-definition+

global-declaration
    := scalar-type identifier ('=' constant-expression)? ';'
     | 'char' '*' identifier ';'
     | array-type identifier '[' integer-literal ']'
        ('=' array-initializer)? ';'

scalar-type
    := 'char' | 'int' | 'unsigned'

array-type
    := 'char' | 'int' | 'unsigned'

function-definition
    := 'int' identifier '(' parameter-list? ')' function-body

parameter-list
    := parameter (',' parameter)*

parameter
    := scalar-type identifier
     | 'char' '*' identifier

function-body
    := '{' local-declaration* statement* '}'

local-declaration
    := scalar-type identifier ';'
     | 'char' '*' identifier ';'

statement
    := block
     | lvalue '=' expression ';'
     | call-expression ';'
     | 'if' '(' expression ')' block ('else' block)?
     | 'while' '(' expression ')' block
     | 'break' ';'
     | 'return' expression ';'

block
    := '{' statement* '}'

lvalue
    := identifier
     | identifier '[' expression ']'

expression
    := the precedence grammar of section 8
```

# 10. Runtime boundary

Phase 1 has no standard library.

The bootstrap environment predeclares the small I/O surface required by `ass.c`:

```c
int io_open(char *name, int length);
int io_read(int handle);
int io_close(int handle);
```

For the bootstrap runtime:

- `io_open` returns a non-negative handle on success and `-1` on failure;
- `io_read` returns a byte value 0 through 255, `-1` for end of file, and `-2` for I/O failure;
- `io_close` closes a valid handle and returns 0.

These are runtime services, not language keywords or a general file API. Their C64 implementation and concrete calling convention belong to #35.

Additional runtime services should not be added to Phase 1 merely for convenience. They must be justified by the compiler or another bootstrap program.

# 11. Important non-features

The following are explicitly outside Phase 1:

- `struct` and `union`;
- `enum`;
- `typedef`;
- `const`, `volatile`, `static`, `extern`, `register`;
- general pointer types, pointer-to-pointer values, `&` and unary `*`;
- local arrays;
- recursion/reentrancy;
- `void`;
- function prototypes;
- function pointers;
- varargs;
- `for`, `do`, `switch`, `case`, `goto`, `continue`;
- `++`, `--` and compound assignments;
- division and remainder;
- logical `!`, `&&`, `||`;
- bitwise `~` and XOR;
- ternary `?:`;
- casts and `sizeof`;
- comma expressions;
- local initializers;
- general constant-expression machinery;
- escape sequences;
- a preprocessor;
- headers;
- separate compilation;
- object files or a linker contract;
- dynamic allocation;
- floating point, `long` or wider integer types;
- a standard library.

This list is not a judgement that these features are undesirable. It records that they do not earn the cost of the assembly bootstrap compiler yet.

# 12. Evidence categories

## 12.1 Required by `ass.c`

Directly exercised by the candidate assembler:

- `char`, `int` and `char *`;
- fixed global `char` and `int` arrays;
- global scalar variables;
- numeric and string static initializers;
- function parameters and ordinary locals;
- nested calls between different functions;
- `if`, `else`, `while`, `break`, `return`;
- assignment;
- `+`, `-`, `*`, `&`, `|`, `<<`, `>>`;
- equality and relational comparisons;
- unary minus for status/sentinel values;
- indexing and byte-pointer addition;
- integer, character and string literals;
- block comments;
- the three-function runtime I/O boundary.

## 12.2 Deliberate additions for the bootstrap

Not merely copied from conventional C:

### `unsigned`

The #33 host compiler has a wider `int`, which temporarily allows the candidate to hold both `$0000..$ffff` values and negative sentinels in the same host type. A real 16-bit target cannot do that.

The clear C solution is not to replace `-1` / `-2` with opaque 65535 / 65534 conventions. It is to use signed `int` for statuses and indices and `unsigned` for full-range machine values. That keeps both the source and target model straightforward.

### Hexadecimal literals

The assembler tables happened not to require C hexadecimal syntax, but the compiler and C64 runtime immediately will. Hex literals are a tiny lexical feature with a large readability return on a 6502.

## 12.3 Deferred until Phase 2 evidence

Everything in section 11 remains deferred unless Phase 1 self-hosting provides concrete evidence that the restriction damages the compiler substantially.

In particular, `struct`, `for`, `switch`, `++`, richer automatic storage and recursion should be judged after the compiler itself has been written in Phase 1, not added now by anticipation.

# 13. Consequences for `ass.c`

The #33 candidate was intentionally compiled with a modern host compiler before this machine model was frozen. Host `int` is wider than Phase 1 `int`.

Before `ass.c` becomes a `nanoc0` acceptance input, values that genuinely use the complete 16-bit machine range must be spelled `unsigned` rather than relying on the host's wider signed `int`. Typical examples are assembler addresses, parsed 16-bit values, symbol payloads and fixup addends.

That is a mechanical type-normalisation, not a redesign of the assembler. Negative search/status results remain `int`.

The host validation should continue to compile the normalised source and reproduce the production `ass.prg`; that keeps host C as an oracle while ensuring the source no longer depends on host integer width.

# 14. What Phase 1 freezes, and what it does not

This document freezes the **source language contract** for `nanoc0`.

It does not yet decide:

- the registers used for expression results;
- the location of parameter/local slots;
- the temporary-expression strategy;
- how 16-bit multiply is implemented;
- the exact runtime/KERNAL adapter;
- the emitted assembler conventions.

Those are #35 execution-model decisions.

The separation is deliberate: `nanoc0` should implement this fixed, small language against the smallest concrete 6502 machine model that makes it work.
