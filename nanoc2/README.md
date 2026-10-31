# nanoc2: traversal-first 6502 compiler (experimental replacement)

This branch starts a **new C-written code-generation path**. It is **not**
an optimiser over the old `nanoc1` emitter. Production `nanoc1.c` is
unchanged.

## Working end-to-end experiment

`source_tape.c` accepts the **actual C function source**, scans a bounded
subset of Nano C, validates its supported operations, and records a function's
typed semantic events. `traversal_backend.c` then examines those events
before writing 6502, chooses X/Y roles from indexed-memory uses, and emits the
complete machine routine.

The current grammar handles byte scalar assignments, byte pointer/array
reads, simple affine array offsets, a power-of-two record stride, `if`,
`while`, `break`, and `return`. Nested traversals are supported.

There is **no function-name-specific code-generation recipe**, no general
instruction search, no register allocator, no Python compiler backend, and no
post-generation peephole pass. The code generator rejects operations it
cannot represent; no silent generic fallback is claimed.

Run the tests from the repository root:

```sh
python3 nanoc2/test_machine.py
```

The test extracts **exact** `same_bytes()` and `find_global()` definitions
from `nanoc1/nanoc1.c`. It feeds them as source text into the new **C**
parser/semantic tape/emitter, then runs the resulting 6502 in an independent
instruction interpreter. Independently host-compiled versions of those same
source definitions are the semantic oracle. The test checks 4,000 cases for
`same_bytes` and 2,500 for `find_global`, including pointer page crossings,
long symbol tables, early exits, and mismatched record contents. Negative
checks exercise both unsafe source constructs and unsupported machine
representations. CI runs this test separately from native C64 build jobs.

The adapter binds the test functions' existing symbol names to **experimental
zero-page and array ABI homes**. The body sizes do not include caller setup,
and this is not yet an executable self-hosted compiler or a whole-image size
result.

## What should be kept and what should be removed

The **lasting** design consists of a small function-local operation tape and
its traversal-first emitter. The existing `nanoc1` scanner, symbol and type
parser are the semantic authority and should be retained.

`source_tape.c` is **temporary integration scaffolding**, not a request to
retain a second scanner or parser in production. It exists solely to prove
source -> typed operations -> target 6502 without a manually supplied tape.
The next step is to modify the **original** bounded `nanoc1` parser so that
it creates these operations directly, preserving full Phase-1 rules. Once the
real parser supplies the tape, delete the temporary source scanner and
replace the old emitter's stack-expression, `ax_pending`, and eager indexed
address operations. In particular, do **not** keep two complete parsers or
two complete emitters.

Until that replacement is done, **do not merge as a finished compiler**.

## Boundaries and correctness caveats

- No 16-bit arithmetic, arbitrary expressions, call side effects, arbitrary
  aliases, `else`, or general nested expressions yet.
- The test adapter's `base = symbol * 32` represents a computed byte offset;
  the source-derived pointer is constructed when its indexed array owner is
  known. Invalid ownership is rejected.
- The low-level test interpreter is not VICE. Encoded body sizes are not
  complete linked C64 image measurements.
- Never treat a passing manually built operation tape as proof of C source
  compilation. The current primary machine tests use only automatically
  generated tapes from the exact original C functions.

