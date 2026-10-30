#!/bin/sh
set -eu
cd "$(dirname "$0")"
export PYTHONPATH="$PWD/full_corpus:$PWD" REG_FIRST=1
unset POINTER_HOME
python link_model.py > xy_build.log
python arg_a_abi.py > xy_a_abi.log
python xy_function_home.py > xy_plan.log
python build_image.py > xy_image.log
python layout_pass.py > xy_layout.log
python strict_link_check.py > xy_strict.log
python byte_match.py > xy_byte_match.log
python parallel_cases.py > xy_end_to_end.log
python - <<'PY'
import json
from pathlib import Path
p=Path('.')
sz=json.loads((p/'layout_metrics.json').read_text())['compact_bytes']
r=json.loads((p/'region_parallel_results.json').read_text())
print('RESULT',sz,r['passed'],'/',r['cases'])
assert r['passed']==r['cases']==29
assert json.loads((p/'strict_check.json').read_text())['passed']==44
assert json.loads((p/'byte_match_result.json').read_text())['matched']==45
PY
