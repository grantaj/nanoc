#!/bin/sh
set -eu
cd "$(dirname "$0")"
export PYTHONPATH="$PWD/full_corpus:$PWD"
cd full_corpus
cc -std=c99 -funsigned-char -O0 -w -o host_assembler host_assembler.c
cc -std=c99 -funsigned-char -O0 -w -shared -fPIC -o host_ass.so host_assembler.c
python full_corpus_benchmark.py > /dev/null
cd ..
python link_model.py > link_output.log
python build_image.py > build_output.log
python layout_pass.py | tee layout_output.log
python strict_link_check.py > strict_length_output.log
python byte_match.py | tee byte_match_output.log
python machine_cases.py | tee machine_test_output.log
cp compact_image.prg CANDIDATE.PRG
printf 'PASS: complete physically linked candidate and tests\n'
