# Native testing and CI

**The host does not test the 6502 program. The 6502 program tests itself.**

That boundary is the central rule of nanoc's test system.

The repository uses VICE to execute ordinary C64 programs whose assertions are written in 6502 assembly. A tiny host shell launches the emulator, waits for one agreed result byte, and turns that byte into a Make/CI success or failure.

```text
assembly test source
        |
        | vasm
        v
      C64 PRG
        |
        | VICE
        v
6502 executes code + assertions
        |
        v
store one byte at $02
        |
        v
host reports PASS / FAIL
```

There is no Python test implementation shadowing the assembler.

## The one-byte test protocol

`test.inc` defines:

```asm
TEST_RESULT          = $02
TEST_PASS            = $ff
TEST_ENTRY           = $c000
ASSEMBLER_TEST_ENTRY = $4000
```

A test writes `TEST_RESULT` **exactly once**, after it has completed:

```text
$ff        success
anything
else       test-specific failure code
```

A small test can therefore be completely direct:

```asm
    lda actual
    cmp #expected
    bne .bad

    lda #TEST_PASS
    sta TEST_RESULT
.halt:
    jmp .halt

.bad:
    lda #FAIL_EXPECTED_VALUE
    sta TEST_RESULT
    jmp .halt
```

The final infinite loop is intentional. The VICE monitor has already stopped on the store to `$02`; the program does not need a host-style process exit mechanism.

Distinct `FAIL_*` values are useful because a CI failure points back to one specific assertion in the native source.

## Larger tests: a small calling convention, not a framework

When a test is large enough to benefit from named subtests, nanoc commonly uses:

```text
carry set   subtest passed
carry clear subtest failed, A contains FAIL_* code
```

The top-level routine stops on the first failure and writes A to `TEST_RESULT`.

For example:

```asm
main:
    jsr testForwardReference
    bcc finish
    jsr testBackwardReference
    bcc finish
    lda #TEST_PASS
finish:
    sta TEST_RESULT
.halt:
    jmp .halt
```

This is just a convenient 6502 routine contract. It is not an assertion library. The checks inside each subtest remain explicit loads, compares, branches, pointer checks, and byte checks.

## What the host runner actually does

Every Make test target eventually calls `tests/run-test.sh`.

The runner deliberately has very little authority. It:

1. reads the little-endian load address from the first two bytes of the CBM PRG;
2. asks the VICE monitor to load the PRG;
3. sets a watchpoint on stores to `$0002`;
4. starts execution at the PRG's own load address;
5. saves the byte at `$02` after the watchpoint fires;
6. reports `PASS` for 255 or `FAIL ... code N` otherwise;
7. uses a timeout so a crashed or looping test cannot hang CI forever.

For file-streaming tests it additionally mounts a host directory as VICE device 8.

The host runner does **not**:

- parse assembler source;
- calculate addresses or branch offsets;
- decode generated machine code to decide whether it is correct;
- reproduce symbol lookup or fixup logic;
- assert register or memory semantics on behalf of the C64 program;
- contain an alternate implementation in Python or another host language.

If a behavior matters, the C64 test program should assert it.

## Why tests start at two different addresses

Small tests use:

```text
TEST_ENTRY = $c000
```

Tests that include the complete production assembler use:

```text
ASSEMBLER_TEST_ENTRY = $4000
```

The assembled production code no longer fits comfortably below the `$d000` C64 I/O window when linked into a test at `$c000`. Starting those larger native tests at `$4000` keeps the executable in ordinary RAM and leaves lower memory available for output and explicit workspaces.

`run-test.sh` does not hard-code either address. It reads the PRG's own load address and starts there.

## The test layers

The suite deliberately starts close to individual machine operations and grows toward full-system behavior.

`make test` currently runs native tests covering:

- whitespace and pointer advancement;
- zero-copy scanning;
- statement parsing and EOL/EOF behavior;
- instruction and addressing-mode recognition;
- the tiny value grammar;
- global and local labels;
- full assembler behavior and exact branch limits;
- origin and data declarations;
- strings;
- streamed file input and nested includes;
- behavioral self-hosting.

The host sees all of these through the same one-byte protocol.

## Streaming-source test

`ass/test_streaming.asm` exercises the production `assembleFile` path rather than the in-memory test entry point.

The Make target mounts `tests/stream-src` as device 8:

```make
VICE_FS_DIR=$(CURDIR)/tests/stream-src ... tests/run-test.sh ...
```

The C64 program then asks the KERNAL reader to open `MAIN.ASM`, follows includes, resumes parents, resolves symbols after line-buffer reuse, and checks the final output bytes and `assemblyPtr` itself.

The shell knows only which directory to expose. It does not understand include order or expected assembler output.

## The self-host test

`test-selfhost` is the strongest integration test in the suite.

The Make target mounts the repository root as device 8 and gives the test a longer timeout:

```text
VICE_FS_DIR=<repository root>
VICE_TIMEOUT=60
```

Inside the C64, `ass/test_selfhost.asm` performs:

```text
vasm-built assembler A at $4000
        |
        | assemble the real ass/ass_0800.asm source closure
        v
nanoc-built assembler B at $0800
        |
        | execute B with JSR $0800
        v
B assembles ass/selfhost_smoke.asm
        |
        v
verify A9 2A 8D 20 D0 60
```

The final six bytes are the known machine code for:

```asm
lda #$2a
sta $d020
rts
```

This is deliberately a behavioral proof. The test does not compare B byte-for-byte with the vasm-built A. It proves that the generated image is executable assembler code and that it can correctly assemble another source file.

## Exact branch-boundary coverage

Branch limits are tested through the real parser and staged assembler path, not through a separate emitter implementation.

The assembler test covers all four exact signed boundaries:

```text
+127   accepted
-128   accepted
+128   rejected
-129   rejected
```

The failing cases also check that the final target memory and `assemblyPtr` have not been partially committed. This exercises the same `encodeRelativeByte` and staging/validation behavior used by production assembly.

## How to add a native test

A new behavior test should normally follow this path.

### 1. Write the C64 test

Create something such as:

```text
ass/test_feature.asm
```

Include `../test.inc`, choose `TEST_ENTRY` or `ASSEMBLER_TEST_ENTRY`, define useful `FAIL_*` constants, and put every behavioral assertion in 6502 code.

Prefer a straight-line test when that is easiest to read. Use the carry/A subtest convention only when named subtests genuinely clarify a larger case.

### 2. Add a build target

Add the PRG to the appropriate target list in the root `Makefile` and add a rule that assembles it with `vasm6502_oldstyle`.

If it uses the complete assembler, depend on `$(ASSEMBLER_DEPS)` rather than rebuilding a second dependency list by hand.

### 3. Add a Make test target

For an ordinary test:

```make
test-feature: $(BUILD_DIR)/test_feature.prg
	VICE=$(VICE) BUILD_DIR=$(BUILD_DIR) sh tests/run-test.sh $< feature
```

If the test reads C64 files, also provide the relevant `VICE_FS_DIR`.

### 4. Add it to `make test`

The root aggregate is the contract used locally and in CI. Do not create a parallel test command that CI does not exercise.

### 5. Keep the host dumb

If you find yourself wanting the shell runner to decode output or reimplement a rule, move that assertion into the assembly test instead.

## Debugging a failing test

A normal failure looks like:

```text
FAIL assembler: code 5
```

Start by finding the corresponding failure constant in the test source:

```sh
grep -n 'FAIL_.*= *\$05' ass/test_assembler.asm
```

or search for the decimal code if the test uses a different spelling.

That takes you directly to the native assertion that failed.

The VICE console log is kept in:

```text
build/<test-name>.vice.log
```

The generated monitor command file and result byte also remain in `build/` for inspection:

```text
build/<test-name>.mon
build/<test-name>.result
```

For deeper debugging, reproduce the test in VICE and use the monitor around the native assertion. The important principle remains the same: diagnose the actual C64 state rather than adding a second semantic oracle on the host.

## CI uses the same setup and test entry points

The workflow in `.github/workflows/ci.yml` is intentionally short:

```text
checkout
   |
   v
make setup
   |
   v
make
   |
   v
make test
```

`make setup` calls `scripts/setup-dev.sh`, the same Ubuntu 24.04 setup path documented for a new developer. This prevents the documentation and CI dependency recipes from drifting apart.

The setup script installs the VICE 3.7.1 data explicitly because the Ubuntu package does not by itself provide the complete ROM data expected by the tests. It also builds vasm from a pinned commit rather than whatever the mirror happens to contain that day.

Those pins make the machine on which the native tests run part of a reproducible development contract rather than an accidental property of a particular CI image.

## The intended boundary

The whole test philosophy can be reduced to this:

```text
host responsibility: build, boot, observe, report
C64 responsibility:  execute, assert, decide correctness
```

That boundary is worth keeping even when a host-language assertion would appear more convenient. nanoc is specifically trying to make the 6502 implementation understandable and trustworthy on its own terms.
