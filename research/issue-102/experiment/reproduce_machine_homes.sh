#!/bin/sh
# Whole-44-function C64 value-home architecture experiment.
# Research-only: ZERO PAGE $30-$3f is a counterfactual memory allocation,
# not an ownership claim against a physical C64's KERNAL/IRQ.
set -eu
cd "$(dirname "$0")"
export PYTHONPATH="$PWD/full_corpus:$PWD"
export REG_FIRST=1
export ZP_BASE=0x30 ZP_BUDGET=16
unset POINTER_HOME
# Build the exact supplied Phase-1 C assembler as both syntax oracle and
# independently compiled semantic oracle (do not depend on prebuilt x86 ELF).
cc -std=c99 -funsigned-char -O0 -w -o full_corpus/host_assembler full_corpus/host_assembler.c
cc -std=c99 -funsigned-char -O0 -w -shared -fPIC -o full_corpus/host_ass.so full_corpus/host_assembler.c
python link_model.py > repro_link.log
python arg_a_abi.py > repro_abi.log
python machine_flow.py > repro_machine_flow.log
python register_home.py > repro_register_homes.log
python test_register_homes.py > repro_register_refusals.log
python live_home_allocator.py > repro_home_allocator.log
python build_image.py > repro_image.log
python layout_pass.py > repro_layout.log
python strict_link_check.py > repro_strict.log
python byte_match.py > repro_bytes.log
python verify_location_interference.py > repro_interference.log
python parallel_cases.py > repro_programs.log
cp compact_image.prg CANDIDATE.PRG
python - <<'PY'
import json
from pathlib import Path
r=Path('.')
size=json.loads((r/'layout_metrics.json').read_text())['compact_bytes']
functions=json.loads((r/'strict_check.json').read_text())['passed']
segments=json.loads((r/'byte_match_result.json').read_text())['matched']
programs=json.loads((r/'region_parallel_results.json').read_text())['passed']
proof=json.loads((r/'independent_location_check.json').read_text())
assert (size,functions,segments,programs)==(10321,44,45,29),(size,functions,segments,programs)
assert len((r/'CANDIDATE.PRG').read_bytes())==size+2
assert proof['allocated_values']>=130 and proof['byte_budget']==16
print(f'PASS exact ass.c, image={size} B, original A-argument baseline=11562 B, savings={11562-size} B')
print(f'Strict assembly={functions}/44, encoding={segments}/45, end-to-end={programs}/29, address safety={proof["interference_edges"]} edges')
PY
