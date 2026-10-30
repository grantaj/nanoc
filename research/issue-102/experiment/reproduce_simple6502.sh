#!/bin/sh
set -eu
cd "$(dirname "$0")"
export PYTHONHASHSEED=0
export PYTHONPATH="$PWD/full_corpus:$PWD"
python3 test_simple6502.py
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
unset SIMPLE_6502
EXPECTED_BYTES=8945 sh reproduce_native_compare.sh
cp CANDIDATE.PRG "$work/control.prg"
cp PRE_OUTLINE.PRG "$work/control-pre.prg"
SIMPLE_6502=1 EXPECTED_BYTES=8697 sh reproduce_native_compare.sh
SIMPLE6502_WORK="$work" python3 - <<'PY'
from pathlib import Path
from hashlib import sha256
import os
work=Path(os.environ["SIMPLE6502_WORK"])
before=(work/'control.prg').read_bytes()
after=Path('CANDIDATE.PRG').read_bytes()
assert len(before)-2==8945
assert len(after)-2==8697
assert sha256(before).hexdigest()=='e155a78e9b7c4a5e68fc4b30ee9e4cb655048bdc2a9377477316ee1dcc813ef2'
assert len((work/'control-pre.prg').read_bytes())-2==9936
assert len(Path('PRE_OUTLINE.PRG').read_bytes())-2==9679
print('PASS machine-first immediate operand A/B: 8945 -> 8697 (-248) loaded bytes; pre-outline 9936 -> 9679 (-257)')
PY
