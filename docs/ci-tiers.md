# CI tiers: fast iteration versus native correctness

The fastest useful feedback for a C64-native compiler change is not a full
self-hosting run. GitHub Actions uses separate feedback and correctness tiers.

| Tier | GitHub workflow / job | Trigger | What it establishes |
| --- | --- | --- | --- |
| **Fast development** | `CI / build` | Every PR update and push to `main` | Shell syntax, host C syntax, and nanoc2's original-parser and 6502-interpreter tests when present |
| **Targeted nanoc2 native smoke** | `nanoc2 targeted native ABI / native-abi` | Explicit `native-smoke` PR label or manual dispatch | vasm assembly and VICE execution of four real C-to-6502 functions with normal Nano C static homes and return convention; **not** full Phase-1 self-hosting |
| **Full native correctness** | `Full native correctness / native` | Push to `main`, nightly, manual dispatch, or a PR with `full-ci` label | Entire existing `make setup`, `make`, assembler comparison, C64 test suite, physical-contract test, nanoc0 bootstrap and nanoc1 Phase-1 corpus |
| **Oversized development bootstrap** | `Oversized seed compiler (development layout) / development-bootstrap` | Manual dispatch or a PR explicitly labeled `dev-bootstrap` | The experimental oversized-seed/self-compilation path on VICE; not a replacement for normal native correctness |

## Daily development

The default PR gate requires no vasm or VICE installation. The three nanoc2
tests operate on the *actual original Nano C parser*, lower to machine code,
and compare interpreted 6502 execution against separately compiled C. They
are run automatically when `nanoc2/test_parser_tape.py` and
`nanoc2/test_lower_tape.py` and `nanoc2/test_indexed_write.py` are part of a branch. No private oracle source
is used.

This gate is intentionally **not proof of 6510/C64 correctness**. In
particular, syntax-only host compilation does not verify native addressing,
timing, C64 memory mapping, assembler compatibility, image size, or
self-hosting.

All PR workflows use concurrency groups. A new commit **cancels older runs
for that PR** rather than allowing a queue of obsolete VICE jobs to accumulate.
Runs on `main` are never cancelled by subsequent pushes.

## Focused native ABI gate

For nanoc2 byte traversal changes that affect calling convention, zero-page
pointer setup, or indexed instruction selection, request **nanoc2 targeted
native ABI** by applying the `native-smoke` PR label (create it once in the
repository if necessary). This is a one-off label event, **not** a job run
automatically on each later commit. Remove/reapply the label or dispatch the
workflow explicitly when its definition is on the default branch.

This smoke assembles the **compiler-emitted** `same_bytes`, `find_global`,
`copy_pointer` and `copy_array` with vasm and executes them with VICE. It
checks pointer page crossing, static argument homes, indexed writes and the
A/X byte-return convention without running the whole bootstrap. See
`nanoc2/test_native.py` and its recorded green CI run. It is intentionally
neither a new compiler backend nor a substitute for the full correctness
suite.

## Before merging substantive compiler/assembler changes

Request a full run by adding the `full-ci` PR label (create this label once
in repository Settings if it does not exist). While the label remains, each
subsequent PR update runs the full native suite; removing it returns to
fast-only development. Alternatively, after this workflow is on `main`,
open **Actions → Full native correctness → Run workflow** and select the
feature branch. A passing run applies to **that exact commit**, not to later
changes.

Treat full native testing as a release/merge gate for changes to actual
compiler/assembler semantics, even if branch protection only requires
`CI / build`. Also inspect the compiled image-size measurements separately;
passing semantic tests says nothing about optimised code size.

The full test job is the former `CI / build` pipeline, *not* a reduced
sample. The existing generated-bootstrap-assembly artifact is retained on
that workflow.

## Oversized-seed experiments

To exercise the more expensive development-layout path, use
**Actions → Oversized seed compiler (development layout) → Run workflow**
with the selected branch. Alternatively, apply a `dev-bootstrap` PR label
(create it once in Settings if necessary). The label action triggers a
**one-off** run; subsequent commits do not automatically repeat this
experiment. To run it again by label, remove and reapply the label.

The result is diagnostic; the oversized layout is deliberately different
from the production self-hosting contract.

## Local commands

A fresh machine needs tools only for the native/full path:

```sh
# Fast: host syntax and nanoc2 machine interpreter tests
for script in scripts/*.sh tests/run-test.sh; do sh -n "$script"; done
cc -std=c90 -funsigned-char -fsyntax-only nanoc1/nanoc1.c
cc -std=c90 -funsigned-char -fsyntax-only bootstrap/ass.c
python3 nanoc2/test_parser_tape.py
python3 nanoc2/test_lower_tape.py
python3 nanoc2/test_indexed_write.py

# Focused native byte ABI smoke (once the project's C64 tools are installed)
python3 nanoc2/test_native.py

# Full native (once the project's C64 tools are installed)
make setup
make
sh scripts/test-ass-c.sh
make test
sh scripts/test-nanoc0-physical-contract.sh
sh scripts/test-nanoc0-integration.sh
sh scripts/test-nanoc1-baseline.sh

# Extra, explicitly requested bootstrap experiment
sh scripts/test-nanoc1-development.sh
```

Omit the nanoc2 commands on branches that do not yet contain `nanoc2`.

The fast tier has an eight-minute job limit and shorter per-test timeouts.
The full-native and oversized-bootstrap tiers have a 120-minute job limit to prevent a genuinely
stuck native experiment from holding a runner indefinitely.

For PRs affecting CI itself, validate workflow trigger conditions and run
the fast gate. Always request a full run before declaring the changed native
workflow proven.
