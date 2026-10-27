# First-generation Nano C semantic baseline (#101)

This document separates **language correctness** from **code-generation quality**.
Issue #100 bootstrapped the exact `nanoc1/nanoc1.c` through the native
`nanoc0 -> ass -> nanoc1` ladder. Issue #101 checks whether the resulting
native compiler implements Phase 1 well enough to become the fixed reference
for the first context-aware 6502 code generator (#102).

## Reproduce

Run `make` first, then:

```sh
sh scripts/test-nanoc0-integration.sh
sh scripts/test-nanoc1-baseline.sh
```

The second script requires and **reuses** the `nanoc1.prg` from the first.
CI runs exactly this sequence. Native compiler input is always selected by
`BUILD/N1JOB`; the compiler's own source, parser and emitter are not copied,
translated, or reimplemented by the host.

## Coverage

| Contract | Production-path evidence |
| --- | --- |
| Streaming scanner, LF/CRLF/CR | The #100 integrated newline fixtures |
| Declarations before use, locals, parameters, types, pointers and arrays | Exact `tests/nanoc0-src/decls.c`, compiled and run |
| Expression precedence, bounded operators and indexes | Exact `tests/nanoc0-expr/expressions.c`, compiled and assembled |
| Narrow/wide arithmetic, return values, function arguments | Exact `tests/nanoc0-stmt/return8.c`, compiled, assembled and run |
| Assignment, indexed stores, nesting, call argument order and staging, if/else/while/break/return | Exact `tests/nanoc0-stmt/statements.c`, compiled, assembled and run |
| Native runtime I/O, source input and output on separate devices | Exact `tests/nanoc0-runtime/runtime.c`, native execution and output-file checks |
| Lexical, declaration, unsupported-syntax, call and bounded-control errors | Existing rejected-source fixtures through the native compiler |
| Exact `bootstrap/ass.c` | Production `nanoc1` compile, native assembler and byte-exact bootstrap oracle |

The shell reads A/X after the actual compiler at `$4000`, uses vasm as an
assembly syntax and packaging tool where needed, and runs program-result
assertions on the 6510 under VICE. The small smoke from issue #100 continues
to use the **production native assembler**. The final `ass.c` check reuses
the stronger existing native assembler self-host/oracle test.

## Frozen measurements

The issue #100 main-branch run (commit
`17fde706542237753742bd4807aed96d6de10b34`) reported:

- `nanoc0` loaded image: **16,702 bytes**.
- `nanoc1` generated assembler text: **186,937 bytes**.
- `nanoc1` loaded image: **24,184 bytes** in its 24,576-byte
  `$4000-$9fff` bootstrap window.

Each #101 run writes `build/nanoc0-integration/nanoc1-baseline.txt`
containing the **last source-touching commit for `nanoc1.c`**, exact
current compiler image sizes, exact `bootstrap/ass.c` generated assembly
and image sizes, and two representative counts of `PHA`/`PLA`
materialisation operations.

These are measurements, **not** optimisation targets in #101. No modified
`ass.c`, alternate semantic implementation, relaxed language contract or
emitter optimisation is permitted to make the result pass.

## Deliberately carried code quality

The initial compiler uses canonical A/X 16-bit values, a stack-based
expression evaluation scheme, direct source-to-assembly emission, and
conservative call argument staging. These make a clear semantic reference
but lead to redundant value movement, stack traffic and address
reconstruction. The `PHA`/`PLA` counts in the saved baseline illustrate
the symptom; they do not explain the systemic cause in isolation.

**The gate for #102 is semantic and functional, not aesthetic.** A compiler
that merely emits valid assembler is not enough: existing native fixture
behaviour and the exact compiled-assembler bootstrap oracle must pass.
If the generated assembler exceeds the fixed `$0800-$47ff` code region,
or if the oracle does not complete, the check fails and #101 remains open.
