#!/bin/sh
set -eu
cd "$(dirname "$0")/../experiment"
export PYTHONPATH="$PWD/full_corpus:$PWD"
export PYTHONHASHSEED=0 REG_FIRST=1 NATIVE_COMPARE=1 ZP_BASE=0x30 ZP_BUDGET=16
unset NATURAL6502 NATURAL6502_WIDE POINTER_HOME WIDE_ALLOW
# The original control can be regenerated independently with:
# sh reproduce_native_compare.sh  # 8,945 B linked, tests 44/45/29/9120.
cc -std=c99 -funsigned-char -O0 -w -o full_corpus/host_assembler full_corpus/host_assembler.c
cc -std=c99 -funsigned-char -O0 -w -shared -fPIC -o full_corpus/host_ass.so full_corpus/host_assembler.c
python link_model.py > same_link.log
python arg_a_abi.py > same_abi.log
python machine_flow.py > same_flow.log
python register_home.py > same_reg.log
python live_home_allocator.py > same_allocator.log
python ../same_algorithm/splice_manual.py
python build_image.py > same_img.log
python layout_pass.py > same_layout.log
cp compact_image.prg SAME_ALGORITHM_PRE_OUTLINE.PRG
python outline_8.py > same_outline.log
python build_image.py > same_out_img.log
python layout_pass.py > same_out_layout.log
python strict_link_check.py > same_strict.log
python byte_match.py > same_bytes.log
python parallel_cases.py > same_cases.log
python test_native_compare.py > same_words.log
python ../same_algorithm/test_manual_find_symbol.py
python ../same_algorithm/test_manual_stage_byte.py
python - <<'PY'
import json
from pathlib import Path
read=lambda f:json.loads(Path(f).read_text())
metrics=read('layout_metrics.json')
symbols=read('compact_resolved.json')
size=metrics['compact_bytes']; strict=read('strict_check.json')['passed'];binary=read('byte_match_result.json')['matched'];cases=read('region_parallel_results.json')['passed']
assert (size,strict,binary,cases)==(8895,44,45,29),(size,strict,binary,cases)
assert len(Path('SAME_ALGORITHM_PRE_OUTLINE.PRG').read_bytes())-2==9878
assert 'PASS 9120' in Path('same_words.log').read_text()
print('SAME ALGORITHM FINAL',size,'bytes; 44/45/29/9120; function bytes:',
      symbols['allocate_symbol']-symbols['find_symbol'],
      symbols['stage_plain_word_reference']-symbols['stage_byte'])
PY
