# nanoc2: traversal-first replacement backend, first C implementation

This is the **first implementation slice**, not a new working Phase-1 compiler yet.
It is a proposed replacement for the direct, stack-oriented emitter in
`nanoc1/nanoc1.c`, not an optimiser applied after that emitter.

## What actually runs

`traversal_backend.c` is C shaped to fit Nano C Phase 1: fixed arrays,
no AST, no allocation, no recursive parser, no host libraries, and no Python
in the compiler. It accepts a bounded *typed operation tape* from the parser,
examines its indexed accesses, chooses simple register roles, and emits text
6502. It does not inspect or recognise function names.

The separate host test adapter **manually supplies the semantic tape** for
unmodified algorithms from `nanoc1.c`: `same_bytes` and the nested
`find_global` (including its match flag, break and two loops). This is a
critical limitation: the production parser has **not yet been wired to
produce the tape**. Passing these tests does *not* establish C-to-6502
compilation or self-hosting.

The machine choices are simple: an index used for indirect pointer accesses
lives in Y; another index used for absolute array accesses lives in X.
Scalar values not selected as index homes are stored in named byte locations.
A scaled pointer is constructed once for the outer record, here using the
algebraic identity `symbol*32 == symbol<<5`, rather than rematerialising it
for every byte in the inner loop. The emitter uses general labels and branches;
there is no `find_global`-specific output template.

## Running the tests

```sh
python3 nanoc2/test_machine.py
```

The test builds the **C emitter** with `cc`, asks it to generate both assembly
listings, and runs a small independent opcode-level interpreter against the
algorithms compiled from C with GCC. It includes arrays crossing pages, full
176-symbol tables and mismatches in the middle of a record. This test
interpreter is *not* VICE or the project's production assembler. Byte sizes
are estimated from 6502 instruction/addressing-mode widths, not native links.

Measured on this slice:

| Exact algorithm | Emitted body | Independent comparisons |
|---|---:|---:|
| `same_bytes` | 37 bytes | 4,000 |
| `find_global` | 108 bytes | 2,500 |

The zero-page homes, function parameter convention and returned byte are part
of this experimental machine contract; those setup costs are not charged to
these body counts. Do not compare them directly with complete `nanoc1` images.

## The architectural boundary

The following remains to be implemented before replacing any production path:

1. The *existing* bounded Phase-1 scanner/type parser must record these
   operations instead of calling direct machine emitters. This is not a
   second parser or a separate Python implementation.
2. The same emitter must handle **ordinary operations, calls, 16-bit values,
   source aliasing, loop exits and arbitrary joins**, with a correct canonical
   fallback. This first slice rejects index conflicts and non-power-of-two
   scales instead of guessing.
3. Replace (rather than duplicate) `ax_pending`, stack-expression templates,
   eager pointer reconstruction and statement-local branch emission.
4. Compare complete generated programs, including ABI/runtime costs, using
   real nanoc tests and the handwritten assembler as a machine-style control.

**Simplicity gate:** if this starts accumulating multiple special recognisers,
large parallel code generators, or an elaborate optimiser, stop and reconsider.
The goal is to make the compiler more readable while getting better 6502.
