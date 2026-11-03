# CI tiers: fast iteration versus native correctness

The fastest useful feedback for a C64-native compiler change is not a full
self-hosting run. GitHub Actions uses three deliberately separate tiers.

| Tier | GitHub workflow / job | Trigger | What it establishes |
| --- | --- | --- | --- |
| **Fast development** | `CI / build` | Every PR update and push to `main` | Shell syntax, host C syntax, and nanoc2's original-parser and 6502-interpreter tests when present |
| **Full native correctness** | `Full native correctness / native` | Push to `main`, nightly, manual dispatch, or a PR with `full-ci` label | Entire existing `make setup`, `make`, assembler comparison, C64 test suite, physical-contract test, nanoc0 bootstrap and nanoc1 Phase-1 corpus |
| **Oversized development bootstrap** | `Oversized seed compiler (development layout) / development-bootstrap` | Manual dispatch or a PR explicitly labeled `dev-bootstrap` | The experimental oversized-seed/self-compilation path on VICE; not a replacement for normal native correctness |

## Daily development

The default PR gate requires no vasm or VICE installation. The two nanoc2
tests operate on the *actual original Nano C parser*, lower to machine code,
and compare interpreted 6502 execution against separately compiled C. They
are run automatically when `nanoc2/test_parser_tape.py` and
`nanoc2/test_lower_tape.py` are part of a branch. No private oracle source
is used.

This gate is intentionally **not proof of 6510/C64 correctness**. In
particular, syntax-only host compilation does not verify native addressing,
timing, C64 memory mapping, assembler compatibility, image size, or
self-hosting.

All PR workflows use concurrency groups. A new commit **cancels older runs
for that PR** rather than allowing a queue of obsolete VICE jobs to accumulate.
Runs on `main` are never cancelled by subsequent pushes.

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
sh -n scripts/*.sh
cc -std=c90 -funsigned-char -fsyntax-only nanoc1/nanoc1.c
cc -std=c90 -funsigned-char -fsyntax-only bootstrap/ass.c
python3 nanoc2/test_parser_tape.py
python3 nanoc2/test_lower_tape.py

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
The two native tiers have a 120-minute job limit to prevent a genuinely
stuck native experiment from holding a runner indefinitely.

For PRs affecting CI itself, validate workflow trigger conditions and run
the fast gate. Always request a full run before declaring the changed native
workflow proven.
