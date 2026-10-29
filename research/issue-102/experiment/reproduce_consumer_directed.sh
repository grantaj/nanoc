#!/bin/sh
# Research-only full physical-image experiment. Preserve the original
# reproduce_native_compare.sh and its asserted 8,945-byte baseline.
set -eu
cd "$(dirname "$0")"
export PYTHONHASHSEED=0
export PYTHONPATH="$PWD/full_corpus:$PWD"
export REG_FIRST=1 NATIVE_COMPARE=1 CONSUMER_DIRECTED=1
export CONSUMER_CALL="${CONSUMER_CALL:-1}"
export CONSUMER_RETURN="${CONSUMER_RETURN:-1}"
export ZP_BASE=0x30 ZP_BUDGET=16
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
from pathlib import Path
import json,collections,os
get=lambda f:json.loads(Path(f).read_text())
a=get('layout_metrics.json')['compact_bytes']
b=get('strict_check.json')['passed']
c=get('byte_match_result.json')['matched']
d=get('region_parallel_results.json')['passed']
stats=collections.Counter()
for fn in get('sizes.json'):
    stats.update(fn.get('consumer_stats',{}))
print('FINAL',a,'bytes',b,'functions',c,'segments',d,'cases')
print('CONSUMER_OPTIONS',os.environ['CONSUMER_CALL'],os.environ['CONSUMER_RETURN'],'STATS',dict(stats))
assert (b,c,d)==(44,45,29),(a,b,c,d)
assert len(Path('CANDIDATE.PRG').read_bytes())==a+2
assert 'PASS 9120' in Path('stage_word_edge_cases.log').read_text()
PY
