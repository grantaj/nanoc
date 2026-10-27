# nanoc1 first-generation native compiler

`nanoc1/nanoc1.c` is the exact Phase 1 C program compiled by the assembly-written `nanoc0` in issue #100. The handoff uses native `ass` and produces a runnable C64 compiler; `nanoc1` then compiles the selected Phase 1 smoke source.

## Source selection for native tests

`nanoc1` does not yet have a command-line environment. Its one-file job contract is deliberately small:

- Read device-8 `BUILD/N1JOB`, whose entire contents are a 1–63-byte relative source pathname, with **no final newline**.
- Compile the named source into device-9 `N1OUT.ASM`.
- Return zero on success; failures return a nonzero status.

The integration script creates `BUILD/N1JOB` automatically and uses the exact committed `nanoc1.c` throughout. For the full native compile/assemble/execute smoke, run `sh scripts/test-nanoc0-integration.sh`; the default `tests/nanoc1/n1src.c` returns `'Z'`. To compile another committed Phase 1 fixture without requiring its `main` to return `'Z'`, run:

```sh
NANOC1_SOURCE=TESTS/NANOC0-STMT/RETURN8.C NANOC1_COMPILE_ONLY=1 \
  sh scripts/test-nanoc0-integration.sh
```

This alternate path still runs the real native `nanoc1` compiler, then uses host `vasm` solely as an assembly syntax/size check. It does not assert runtime semantics. The default smoke additionally executes the generated program natively, with project `ass`.

## Why the text pool looks unusual

Phase 1 lacks source-level named constants and string escapes. The single `fixed_text` array avoids dozens of separately named global strings and keeps bootstrap workspace small. Its symbol spellings appear as character literals grouped by starting byte offset; byte-oriented 6502 templates remain compact numeric data. A numeric `fixed_text + offset` reference refers to one of these explicitly labelled entries, **not** a compiler optimisation state or intermediate representation. Any edit to the pool must preserve or deliberately update all later offsets.

This constraint, and any additional pain it creates, belong in #38 rather than expanding the Phase 1 language in #100. Machine-state/optimizer design remains deferred to #102.

## Native scanner and allocation regressions

The integration test uses the same committed compiler and the original generated
6502 image for three newline formats (LF, CRLF, and consecutive CR in a CR-only
source) plus two expected failures. The latter exercise 16-bit BSS sum overflow
(two 34,000-byte arrays) and byte-count multiplication overflow (`int[32768]`).

After the initial native bootstrap and smoke, `test_nanoc1_compile.asm` invokes
that generated machine image directly and records the returned A/X status. Each
fixture is compiled through the real device-8 source file, and the shell checks
both the result code and assembly of successful outputs. Rejected sources must
return layout status 6. Host `vasm` is only an assembly syntax check, never an
alternate C compiler. `tests/run-test.sh` has an optional `VICE_PRELOAD_PRG`
input for loading the already-generated native image alongside the tiny harness.
