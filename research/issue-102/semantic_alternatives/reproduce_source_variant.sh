#!/bin/sh
# Build one exact full-assembler variant at a time to avoid long combined runs.
set -eu
ZIP=${1:?Usage: reproduce_source_variant.sh ORIGINAL_ZIP baseline|cursor|early_exit}
MODE=${2:?Specify baseline, cursor or early_exit}
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
unzip -q "$ZIP" -d "$TMP"
cd "$TMP/nanoc_machine_value_home_planner"
case "$MODE" in
 baseline) : ;;
 cursor) patch -p0 < "$ROOT/cursor_source.patch" ;;
 early_exit) patch -p0 < "$ROOT/early_exit_source.patch" ;;
 *) echo "Invalid variant: $MODE" >&2; exit 2 ;;
esac
export PYTHONHASHSEED=0 PYTHONPATH="$PWD/full_corpus:$PWD" REG_FIRST=1 NATIVE_COMPARE=1 ZP_BASE=0x30 ZP_BUDGET=16
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
python - "$MODE" <<'PY'
import json,sys
from pathlib import Path
R=lambda f:json.loads(Path(f).read_text())
mode=sys.argv[1]
size=R('layout_metrics.json')['compact_bytes']
pre=len(Path('PRE_OUTLINE.PRG').read_bytes())-2
checks=(R('strict_check.json')['passed'],R('byte_match_result.json')['matched'],R('region_parallel_results.json')['passed'])
print('RESULT',mode,'pre_outline',pre,'final',size,'checks',checks)
assert checks==(44,45,29)
assert size=={'baseline':8945,'cursor':8975,'early_exit':8948}[mode]
PY
