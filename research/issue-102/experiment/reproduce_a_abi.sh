#!/bin/sh
set -eu
cd "$(dirname "$0")"
export PYTHONPATH="$PWD/full_corpus:$PWD"
export REG_FIRST=1
unset POINTER_HOME
python link_model.py > a_abi_link.log
python arg_a_abi.py > a_abi_rewrite.log
python build_image.py > a_abi_image.log
python layout_pass.py > a_abi_layout.log
python strict_link_check.py > a_abi_strict.log
python byte_match.py > a_abi_byte_match.log
python parallel_cases.py > a_abi_end_to_end.log
python - <<'PY'
import json
from pathlib import Path
p=Path('.')
size=json.loads((p/'layout_metrics.json').read_text())['compact_bytes']
assert size==11562,size
assert json.loads((p/'strict_check.json').read_text())['passed']==44
assert json.loads((p/'byte_match_result.json').read_text())['matched']==45
r=json.loads((p/'region_parallel_results.json').read_text())
assert r['passed']==r['cases']==29
print('PASS: 11562 B, 44/44 strict, 45/45 byte identical, 29/29 full-image oracle')
PY
