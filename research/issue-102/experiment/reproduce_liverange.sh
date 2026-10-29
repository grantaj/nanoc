#!/bin/sh
set -eu
cd "$(dirname "$0")"
export PYTHONPATH="$PWD/full_corpus:$PWD" REG_FIRST=1
unset POINTER_HOME
python link_model.py > live_build.log
python arg_a_abi.py > live_a_abi.log
python machine_flow.py > live_flow.log
python live_home_allocator.py > live_zp.log
python build_image.py > live_image.log
python layout_pass.py > live_layout.log
python strict_link_check.py > live_strict.log
python byte_match.py > live_byte_match.log
python parallel_cases.py > live_end_to_end.log
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
