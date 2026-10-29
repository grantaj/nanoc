#!/bin/sh
# Rebuild the 4 source variants with the exact frozen research backend.
set -eu
here=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
# This script lives alongside the original exact ZIP in research/issue-102/.
archive="$here/../nanoc_remaining_gap_codegen_experiment.zip"
output=${1:-"$here/record_ab_repro"}
mkdir -p "$output"
for variant in baseline symbol_only fixup_only both; do
    dest="$output/$variant"
    mkdir -p "$dest"
    unzip -q -o "$archive" -d "$dest"
    work="$dest/nanoc_machine_value_home_planner"
    if [ "$variant" != baseline ]; then
        cp "$here/${variant}_ass.c" "$work/full_corpus/ass.c"
        cp "$here/${variant}_ass.c" "$work/full_corpus/exact_source/ass.c"
    fi
    (
      cd "$work"
      export PYTHONPATH="$PWD/full_corpus:$PWD" PYTHONHASHSEED=0
      export REG_FIRST=1 NATIVE_COMPARE=1 ZP_BASE=0x30 ZP_BUDGET=16
      unset POINTER_HOME
      python full_corpus/full_corpus_benchmark.py > regenerate_corpus.log
      # Original reproduction script intentionally asserts the 8,945-B
      # baseline. Keep its checks for 44/45/29, not the baseline size.
      sed 's/assert (a,b,c,d)==(8945,44,45,29),(a,b,c,d)/assert (b,c,d)==(44,45,29),(a,b,c,d)/' reproduce_native_compare.sh > reproduce_ab_variant.sh
      sh reproduce_ab_variant.sh > reproduction.log
      tail -1 reproduction.log
      echo 'before outlining:'
      grep '^FINAL ' stage_preoutline_layout.log
      echo 'after outlining:'
      grep '^FINAL ' stage_outlined_layout.log
    )
done
