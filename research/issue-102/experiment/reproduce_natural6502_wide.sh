#!/bin/sh
# Run independently of reproduce_native_compare.sh, which verifies the control.
set -eu
cd "$(dirname "$0")"
export PYTHONPATH="$PWD/full_corpus:$PWD"
export PYTHONHASHSEED=0 REG_FIRST=1 NATIVE_COMPARE=1 ZP_BASE=0x30 ZP_BUDGET=16 NATURAL6502_WIDE=1
export WIDE_ALLOW=parse_value,stage_byte
unset POINTER_HOME
cc -std=c99 -funsigned-char -O0 -w -o full_corpus/host_assembler full_corpus/host_assembler.c
cc -std=c99 -funsigned-char -O0 -w -shared -fPIC -o full_corpus/host_ass.so full_corpus/host_assembler.c
python link_model.py > natural_link.log
python arg_a_abi.py > natural_abi.log
python machine_flow.py > natural_flow.log
python register_home.py > natural_reg.log
python live_home_allocator.py > natural_allocator.log
python build_image.py > natural_img.log
python layout_pass.py > natural_layout.log
cp compact_image.prg WIDE_PRE_OUTLINE.PRG
python outline_8.py > natural_outline.log
python build_image.py > natural_out_img.log
python layout_pass.py > natural_out_layout.log
python strict_link_check.py > natural_strict.log
python byte_match.py > natural_bytes.log
python parallel_cases.py > natural_cases.log
python test_native_compare.py > natural_word.log
cp compact_image.prg WIDE_CANDIDATE.PRG
python - <<'PY'
import json
from pathlib import Path
read=lambda x:json.loads(Path(x).read_text())
size=read('layout_metrics.json')['compact_bytes']
valid=(read('strict_check.json')['passed'],read('byte_match_result.json')['matched'],read('region_parallel_results.json')['passed'])
assert valid==(44,45,29),valid
assert 'PASS 9120' in Path('natural_word.log').read_text()
assert size==8921,size
print('WIDE',size,'loaded bytes; pre-outline',len(Path('WIDE_PRE_OUTLINE.PRG').read_bytes())-2)
print('PASS 44 functions, 45 segments, 29 assembly programs, 9120 word comparisons')
PY
