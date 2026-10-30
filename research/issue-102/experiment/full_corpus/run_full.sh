#!/bin/sh
set -eu
cd "$(dirname "$0")"
python3 -c 'import pycparser'
cc -std=c99 -funsigned-char -O0 -w host_assembler.c -o host_assembler
cc -std=c99 -funsigned-char -O0 -fPIC -shared -w host_assembler.c -o host_ass.so
python3 full_corpus_benchmark.py
python3 link_audit.py
python3 strict_asm_probe.py
python3 scratch_audit.py
python3 new_ops_tests.py
