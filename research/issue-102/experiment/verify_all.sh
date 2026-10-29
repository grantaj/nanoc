#!/bin/sh
set -eu
cd "$(dirname "$0")"
export PYTHONPATH="$PWD/full_corpus:$PWD"
sh reproduce.sh
python test_typed_call_abi.py
python test_address_proofs.py
python test_indexed_abi.py
python test_byte_abi.py
python test_general_machine_rules.py
python test_word_comparisons_new.py
python - <<'PY'
from pathlib import Path
import json
p=Path('.')
loaded=len((p/'compact_image.prg').read_bytes())-2
assert loaded==12464,(loaded,'unexpected code-generation drift')
assert json.loads((p/'end_to_end.json').read_text())['passed']==29
print('PASS: exact 12,464-byte linked image and all test gates')
PY
