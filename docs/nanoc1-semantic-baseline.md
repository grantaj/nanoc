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
| Exact `bootstrap/ass.c` | Production `nanoc1` compiles the committed source; host `vasm` assembles generated code and measures size. Executable assembler oracle is deferred to #37. |

The shell reads A/X after the actual compiler at `$4000`, uses vasm as an
assembly syntax and packaging tool where needed, and runs program-result
assertions on the 6510 under VICE. The small smoke from issue #100 continues
to use the **production native assembler**. The exact `ass.c` stress case **does not** execute its resulting assembler: its
image does not fit the current Phase 1 code region. The independent native
assembler bootstrap oracle remains a later #37 milestone after the #102
code-generation improvements.

## Frozen measurements

The issue #100 main-branch run (commit
`17fde706542237753742bd4807aed96d6de10b34`) reported:

- `nanoc0` loaded image: **16,702 bytes**.
- `nanoc1` generated assembler text: **186,937 bytes**.
- `nanoc1` loaded image: **24,184 bytes** in its 24,576-byte
  `$4000-$9fff` bootstrap window.

Each #101 run writes `build/nanoc0-integration/nanoc1-baseline.txt`
containing the **repository commit and exact Git blob of `nanoc1.c`**, exact
current compiler image sizes, exact `bootstrap/ass.c` generated assembly
and image sizes, and two representative counts of `PHA`/`PLA`
materialisation operations.

## #101 result — exact pre-optimisation baseline

Native CI run [40593997225](https://github.com/grantaj/nanoc/actions/runs/40593997225)
establishes the following for compiler content blob
`489b31fab7ffc943fc95f7e0f032c66b2004d818`:

| Measurement | Actual result |
| --- | ---: |
| C-written `nanoc1` generated assembler source | 189,920 bytes |
| Native `nanoc1` loaded compiler image | **24,545 bytes** |
| Spare `$4000-$9fff` bootstrap image space | **31 bytes** |
| `ass.c` emitted assembler source, via native `nanoc1` | **182,686 bytes** |
| `ass.c` emitted loaded image, assembled by vasm | **33,225 bytes** |
| `ass.c` `PHA` instructions | 4,186 |
| `ass.c` `PLA` instructions | 4,186 |
| `ass.c` Phase 1 `$0800-$47ff` executable limit | 16,384 bytes |
| Excess over executable limit | **16,841 bytes** |

For comparison, the #100 production `nanoc0` compilation of the very
same committed `bootstrap/ass.c` generated 123,495 bytes of assembly and
a 14,470-byte loaded image. The `nanoc1` image is approximately 2.30 times
the `nanoc0` image. The counts of 4,186 `PHA` / 4,186 `PLA` are an
objective symptom of the stack-heavy lowering, not a proof that each pair
can individually be eliminated.

**Result and agreed gate change (2026-10-28):** representative Phase 1
semantic fixtures compile, assemble and execute correctly on the real 6510,
including explicit rejection cases. Exact `bootstrap/ass.c` compiles through
production `nanoc1`; the emitted assembler assembles. The 33,225-byte
compiled assembler **cannot execute** in the current 16 KiB code window, so
its functional equivalence to the native assembler is **not yet proved**.

This size shortfall is **not a #101 failure**. Its image size and stack
traffic are deliberately frozen as evidence for #102's context-aware code
generator. The byte-exact native assembler bootstrap oracle is required for
eventual self-hosting, but is now a later **#37 convergence gate**, after
#102 has made the output executable. The issue and parent roadmap record
the same change. CI will report an informative size warning and remain green
if all native semantic checks and the exact `ass.c` compile/assembly pass.

### Architectural implication

The first C-written compiler is live, but its emitter decides too early:
scattered materialisation to the hardware stack, reconstructed pointers and
indexes, and no persistent A/X/Y/flags or loop-cursor strategy. The first #102
step is **bounded lookahead over *semantic operations***, allowing the
machine-code strategy to be selected before emission. Merely buffering
already chosen instructions is not sufficient.

The 31-byte compiler-image margin also argues for **replacing** existing
direct-emitter machinery in stages rather than simply adding a second
general-purpose optimiser alongside it.

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

**The #101 gate is observed Phase 1 semantic behaviour, not size.** The native
fixtures must execute correctly (or reject invalid input), and exact `ass.c`
must compile and assemble. Compile-and-assemble alone does **not** prove the
compiled C assembler works; its native functional oracle is explicitly retained
as a later #37 gate once #102 addresses the physical code size.
