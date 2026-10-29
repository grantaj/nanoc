#!/bin/sh
set -eu
export PYTHONHASHSEED=0
export NATIVE_INPLACE=1
cd "$(dirname "$0")"
export PYTHONPATH="$PWD/full_corpus:$PWD"
export REG_FIRST=1 NATIVE_COMPARE=1 ZP_BASE=0x30 ZP_BUDGET=16
unset POINTER_HOME
cc -std=c99 -funsigned-char -O0 -w -o full_corpus/host_assembler full_corpus/host_assembler.c
cc -std=c99 -funsigned-char -O0 -w -shared -fPIC -o full_corpus/host_ass.so full_corpus/host_assembler.c
python link_model.py > stage_link.log
python arg_a_abi.py > stage_abi.log
python machine_flow.py > stage_flow.log
python register_home.py > stage_reg.log
python live_home_allocator.py > stage_allocator.log
python build_image.py > stage_img.log
python layout_pass.py > stage_preoutline_layout.log
cp compact_image.prg PRE_OUTLINE.PRG
python outline_8.py > stage_outline_selection.log
python build_image.py > stage_outlined_img.log
python layout_pass.py > stage_outlined_layout.log
python strict_link_check.py > stage_strict.log
python byte_match.py > stage_bytes.log
python parallel_cases.py > stage_cases.log
python test_native_compare.py > stage_word_edge_cases.log
cp compact_image.prg CANDIDATE.PRG
python - <<'PY'
import json
from pathlib import Path
get=lambda f:json.loads(Path(f).read_text())
a=get('layout_metrics.json')['compact_bytes'];b=get('strict_check.json')['passed'];c=get('byte_match_result.json')['matched'];d=get('region_parallel_results.json')['passed']
print('FINAL',a,'bytes',b,'functions',c,'segments',d,'cases')
assert (a,b,c,d)==(8823,44,45,29),(a,b,c,d)
assert len(Path('CANDIDATE.PRG').read_bytes())==a+2
PY
