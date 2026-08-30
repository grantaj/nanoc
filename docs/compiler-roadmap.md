# Nano C bootstrap roadmap

Nano C is intended to be a small C for the 6502/6510 that could plausibly have existed on machines of the period. The project is not aiming first at ISO C completeness. The immediate goal is to escape hand-written assembly as quickly as possible while preserving a language and implementation that remain direct, economical, understandable from the machine upward, and useful as a teaching compiler.

The roadmap is therefore driven by **bootstrapping pressure** rather than by a predetermined checklist of C features.

The central idea is:

> First write a real program in deliberately restricted C. Let that program tell us what the first language needs. Then implement exactly that language in assembly, use it to move the toolchain into C, and evolve the language from within itself.

## The two language phases

**Phase 1** is the bootstrap language. It must be small enough that the first compiler can realistically be written in 6502 assembly, but not so small that programs written in it become pseudo-assembly. Its purpose is to get development out of assembly quickly.

**Phase 2** is the first self-hosted language evolution. It is designed only after we have written both the assembler and compiler in Phase 1 and can see which restrictions actually hurt. The Phase 2 compiler is initially implemented in Phase 1 C; once that compiler understands the new features, its own source may be rewritten to use them.

This distinction is important. Phase 1 is not intended to predict the final language, and Phase 2 is not intended to be “all the rest of C”. Both phases are justified by real programs.

## Why the assembler comes first

The first substantial Nano C program will be a C reimplementation of the existing assembler, `ass`.

This is intentionally earlier than implementing the C compiler itself.

The assembler is already a useful, non-trivial program whose architecture fits the character we want Nano C to support:

- source is consumed incrementally rather than retained as a giant text image;
- parsing works directly on source views rather than copied token strings;
- persistent state is small, bounded and explicit;
- symbol lookup is linear;
- data structures are compact and machine-oriented;
- parsed statements are reduced to machine bytes and only genuinely unresolved state survives;
- file/include behaviour is deliberately bounded;
- there is no heap, object format, linker, generic IR or framework machinery.

That makes `ass` a much better language-design oracle than an abstract list of C features.

The question for Phase 1 is not:

> What is the smallest subset of C we can imagine?

It is:

> What is the smallest subset of C in which this real 6502 program can be expressed clearly and naturally?

That distinction is the guard against both feature creep and “stupidly minimal” C.

## Milestone 1: write candidate `ass.c`

The first compiler-related implementation task is to rewrite the production assembler in deliberately restricted C.

```text
current ass.asm
      |
      | same design and behaviour
      v
candidate ass.c
```

This is a **language-discovery exercise**.

It is not yet the Phase 1 specification, and it is not yet part of the native bootstrap chain.

The C should preserve the useful machine-level character of the current implementation, but it should be a natural C rendering rather than a line-by-line transliteration of `lda` and `sta` sequences. Fixed buffers, explicit workspaces, linear scans, compact records and zero-copy source handling remain good choices when they remain clear in C.

At the same time, the implementation should make language pressure visible. If omitting a modest C feature creates pervasive noise, that is evidence that the feature may earn a place in Phase 1. If a conventional feature provides only cosmetic improvement while requiring substantial compiler machinery, it can wait.

Questions such as these should be answered by the program rather than in advance:

- Do `char`, 16-bit `int`, pointers and arrays cover the useful data model?
- Are explicit compact records still clear, or does `struct` materially improve the assembler?
- Do `++` and `--` remove enough noise to justify their parser/code-generation cost?
- Does `for` buy anything significant over `while`?
- Does `switch` materially simplify the program?
- Which static initialiser forms are disproportionately useful for opcode and mode tables?
- Which expression operators are actually used?
- What form of local variables is really needed?

Issue: #33.

## The modern C compiler is only a check

During the `ass.c` experiment we can compile the candidate source with a modern C compiler and run it on the host.

That is useful because it lets us check the C implementation immediately:

```text
candidate ass.c
      |
      | modern host C compiler
      v
host validation executable
      |
      | assemble the real production ass/ass.asm source closure
      v
6502 assembler image
```

The host-compiled program should be able to assemble the existing production `ass` source tree and produce a working assembler image. Where useful, its output can be compared with the existing native assembler and exercised through the same behavioural smoke expectations.

However, **the modern compiler is not part of the Nano C bootstrap and does not define Nano C semantics**.

Host-specific facilities should therefore remain behind a small adapter boundary. The core candidate C should not become a conventional desktop program built around `FILE *`, `malloc`, host path abstractions or dynamic containers merely because those facilities are available.

Likewise, host `int` width, signedness defaults and other implementation-defined C behaviour must not silently become Nano C rules. Those rules are decided explicitly in the next milestone.

The host build answers only one question:

> Is this candidate C assembler logically correct enough to implement the existing assembler?

## Milestone 2: freeze Phase 1

Once `ass.c` is clear, working and stable enough to be useful evidence, extract the Phase 1 language from it.

```text
working restricted ass.c
      |
      | inventory constructs actually used
      v
Nano C Phase 1 specification
```

Issue #34 records this work.

The Phase 1 document defines exactly what the assembly-written bootstrap compiler must accept:

- scalar types and their widths;
- pointer forms and pointer arithmetic actually supported;
- arrays;
- declarations and static initialisation;
- globals, parameters and locals;
- function definitions, calls and returns;
- statements and control flow;
- expression grammar and precedence;
- literals and comments;
- the tiny external/runtime boundary;
- important unsupported C features.

Machine-visible semantics are explicit. Nano C does not inherit them accidentally from the host compiler.

The bootstrap language deliberately uses fixed per-function storage and has no recursion or reentrancy. This is not an arbitrary restriction: it lets the 6502 implementation avoid general stack frames while keeping the real assembler clear.

## Milestone 3: define the Phase 1 machine model

Before writing the compiler, define the concrete 6502 contract it targets.

Issue #35 covers this boundary.

This is deliberately smaller than a conventional ABI design. It answers only the questions required to generate Phase 1 programs:

- `A/X` as the visible 16-bit scalar/result pair;
- fixed per-function parameters, locals and compiler temporaries;
- caller-owned nested call staging;
- two fixed zero-page scratch pairs;
- `JSR`/`RTS` calls without a software C stack;
- an explicit `NC_BSS` static workspace;
- binary arithmetic mode (`D = 0`);
- a tiny runtime/KERNAL-facing interface.

Generated conditional control flow also stays deliberately simple. `nanoc0` does not calculate whether an arbitrary branch target is within the 6502 relative-branch range. It always uses a nearby conditional branch over an absolute `JMP` for generated conditional transfers. Spending the extra `JMP` is a good trade for eliminating branch-distance bookkeeping and relaxation from the assembly bootstrap compiler.

The result is concrete enough that small C fragments can be shown beside predictable 6502 assembly.

There is no virtual-register architecture, object ABI, linker contract or backend framework.

## Milestone 4: build `nanoc0` in assembly

With the language and target model fixed, write the one compiler that still has to be hand-written in assembly.

```text
Phase 1 C source
      |
      | nanoc0, written in 6502 assembly
      v
ass-compatible 6502 assembly
      |
      | ass
      v
C64 program
```

Issue #36 covers the bootstrap compiler.

`nanoc0` implements **only** frozen Phase 1. It is not a general C compiler skeleton waiting to be filled in later.

The preferred architecture is as direct as the language permits: scan source, recognise the current declaration/statement/expression, and emit assembler as soon as possible. A persistent token stream, AST, generic IR, optimiser, register allocator, object format and linker are all absent unless a concrete Phase 1 requirement demonstrates that some smaller representation is actually simpler.

The input is a character stream, not a sequence of semantically independent lines. The implementation may refill a small bounded buffer, but whitespace, expressions and block comments may cross physical input lines.

The output is ordinary `ass` source. `nanoc0` tracks generated size from the beginning because the native assembler has a finite 16 KiB staging region; compact obvious code matters, but not at the cost of introducing layout machinery such as branch relaxation.

`nanoc0` is also allowed to be bootstrap-specific. Once Nano C is self-hosted, we do not need to keep extending the assembly compiler. It should be correct, compact and exceptionally readable, but it does not need speculative architecture for Phase 2.

### The first decisive `nanoc0` test

The first serious program for the compiler is the same program that defined its language. `bootstrap/ass.c` is now literal Phase 1 source, with full-range machine values explicitly typed `unsigned` rather than relying on the host's wider `int`:

```text
nanoc0.asm
    |
    | compile
    v
ass.c
    |
    v
ass-from-c.asm
    |
    | existing ass
    v
ass-from-c
    |
    | assemble the production ass/ass.asm tree
    v
working assembler
```

This is a major project milestone.

At that point Nano C has already replaced an important assembly-language component of its own toolchain.

The modern host compiler remains only a convenient independent validation oracle: compiling the same `ass.c` must continue to reproduce the production assembler byte-for-byte.

## Milestone 5: rewrite Nano C in Phase 1 C

Once `nanoc0` can compile useful Phase 1 programs, rewrite the compiler itself in Phase 1 C.

Issue #37 tracks this transition.

The bootstrap becomes:

```text
existing ass
    |
    | assemble
    v
nanoc0.asm
    |
    | compile
    v
nanoc1.c
    |
    v
nanoc1.asm
    |
    | ass
    v
nanoc1
    |
    | compile nanoc1.c again
    v
nanoc2.asm
    |
    | ass
    v
nanoc2
```

The important proof is behavioural self-hosting: the compiler produced by Nano C can compile the compiler source again and the next generation behaves equivalently on the Phase 1 corpus.

A deterministic fixed point in generated assembly is attractive if it arises naturally, but byte identity is not the definition of success.

This is the milestone at which ordinary compiler development leaves assembly behind.

The Phase 1 C compiler implementation should again be a natural rewrite, not a transliteration of `nanoc0.asm`. Writing it is also our second language-design experiment. Any places where Phase 1 is awkward are recorded as evidence for Phase 2 rather than repaired immediately by silently growing the bootstrap language.

## Milestone 6: evolve to Phase 2 from within Nano C

Only after Phase 1 self-hosting is established do we decide what Phase 2 contains.

Issue #38 is intentionally a placeholder until that evidence exists.

Candidate features might eventually include things such as structures, enums, typedefs, more convenient loops/control flow, better automatic storage, recursion, richer initialisers, separate compilation or some preprocessing facility. None of those features is promised merely because conventional C contains it.

A Phase 2 feature earns its place when the Phase 1 implementation demonstrates that it materially improves the compiler, assembler or useful programs for a reasonable implementation cost.

The bootstrapping order matters:

```text
Phase 1 self-hosted compiler
        |
        | compiler source is still Phase 1 C
        | add support for selected Phase 2 constructs
        v
Phase 2-capable compiler
        |
        | now source may use Phase 2
        v
Phase 2 self-hosted compiler
```

We must first teach the compiler a new construct using the language it already understands. Only then can we rewrite the compiler itself to use that construct.

That keeps every bootstrap generation buildable.

## Long-term shape of the toolchain

If these milestones succeed, the repository will contain a useful historical ladder:

```text
hand-written assembly bootstrap

    ass.asm
    nanoc0.asm
        |
        v
Phase 1 C

    ass.c
    nanoc.c
        |
        v
Phase 2 C

    clearer self-hosted nanoc
    optional ass.c cleanup where Phase 2 genuinely helps
```

The assembly implementations remain valuable: they explain where the system came from and provide the root from which the C toolchain can be bootstrapped. But ordinary development moves upward as soon as each layer can reproduce the next.

## Roadmap principles

Across all of these milestones, a few rules should remain stable.

### Self-hosting is a design constraint

A feature is valuable when it helps us express the programs required to reproduce the toolchain. We do not implement C features in standards order.

### Real programs define the language

`ass.c` defines the pressure for Phase 1. The Phase 1 compiler source defines much of the pressure for Phase 2. This is preferable to guessing which features will matter.

### Minimal does not mean hostile

The project should not force clear algorithms into awkward pseudo-assembly C merely to save a few compiler routines. Small features may be excellent bargains when they remove substantial noise.

### The machine stays visible

Nano C should remain understandable from C source through generated assembler to 6502 execution. Fixed memory, linear scans and direct state are often virtues on this machine rather than deficiencies to abstract away.

### Do not build future architecture early

There is no need for a generic IR, object format, linker, optimiser, allocator framework or full standard library until a concrete program demonstrates that such machinery earns its cost.

### Host tools do not define the system

Modern host compilers and host-side orchestration are useful validation aids. Compiler and assembler semantics belong to Nano C and the C64/6502 implementation, not to the host test environment.

## Initial issue sequence

The first compiler tranche is intentionally ordered:

1. **#33 — Rewrite `ass` in candidate Phase 1 C to discover the bootstrap language.**
2. **#34 — Extract and freeze Nano C Phase 1 from `ass.c`.**
3. **#35 — Define the Phase 1 6502 execution and calling model.**
4. **#36 — Implement the assembly-written Nano C Phase 1 bootstrap compiler.**
5. **#37 — Rewrite Nano C compiler in Phase 1 C and prove self-hosting.**
6. **#38 — Define Phase 2 from self-hosting pressure and evolve Nano C in Nano C.**

The first three milestones are now complete. The immediate implementation target is #36.