#!/bin/sh
set -eu
cd "$(dirname "$0")"
export PYTHONPATH="$PWD/full_corpus:$PWD"
sh reproduce.sh
python test_typed_call_abi.py
python test_address_proofs.py
python test_indexed_abi.py
python test_byte_abi.py
python - <<'PY'
from pathlib import Path
import json
n=len(Path('compact_image.prg').read_bytes())-2
assert n==12464, n
r=json.loads(Path('end_to_end.json').read_text())
assert r['passed']==29,r
assert len(json.loads(Path('sizes.json').read_text()))==44
print('PASS 44 linked functions; 29 assembly programs; 12,464-byte image')
PY
