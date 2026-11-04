#!/usr/bin/env python3
"""Original Phase-1 builtin I/O ABI and real open_include under native VICE.

The small standalone program exercises all five runtime entry points using
invalid handles/lengths independent of a host drive. The second run compiles
the actual 33-function original assembler prefix and verifies the original
open_include's name construction, return/error and pointer path.
"""
from test_native import ROOT, ASS_SOURCE, run_native, word_assert

def io_contract_test():
    lines=["\t* = $1000", "main:", "\tjsr n2_io_init"]
    for i,(name,low,high) in enumerate((
        ("reject_open",255,255),
        ("reject_create",255,255),
        ("reject_read",254,255),
        ("reject_write",255,255),
        ("reject_close",255,255),
    )):
        lines.append("\tjsr n2_"+name)
        lines.extend(word_assert(low,high,57000+i))
    return lines

def original_open_test():
    lines=["\t* = $1000", "main:", "\tjsr n2_io_init"]
    n=0
    def put(where,value):
        lines.extend(("\tlda #$%02x"%(value&255),"\tsta "+where))
    def check(where,value):
        nonlocal n
        lines.extend(("\tlda "+where,"\tcmp #$%02x"%(value&255),
                      "\tbeq .iook_%d"%n,"\tjmp native_fail",
                      ".iook_%d:"%n))
        n+=1

    # The argument bytes live below $4800 BSS and beyond this caller's
    # small $4000-origin test code; the original source_path is in BSS.
    for test,source in enumerate((b'"NOFILEZZ"',b'"../NOFILEZZ"')):
        for i,b in enumerate(source):
            put("$4700+%d"%i,b)
        put("n2_open_include_argument",0x00)
        put("n2_open_include_argument+1",0x47)
        put("n2_open_include_length",len(source))
        put("n2_source_directory_length",0)
        put("n2_source_depth",0)
        put("n2_source_depth+1",0)
        lines.append("\tjsr n2_open_include")
        lines.extend(word_assert(12,0,58000+test))
        check("n2_source_depth",0)
        for k,b in enumerate(b"NOFILEZZ"):
            check("n2_source_path+%d"%k,b)
    # Invalid source stops before touching KERNAL or output path.
    put("n2_open_include_length",1)
    lines.append("\tjsr n2_open_include")
    lines.extend(word_assert(1,0,58005))
    return lines

def run_io_builtin_tests(driver):
    source=(ROOT/"tests"/"nanoc2"/"io-builtins.c").read_text()
    run_native("io_builtin_contract",source,io_contract_test(),driver)
    prefix=ASS_SOURCE[:ASS_SOURCE.index("int read_source_line(")]
    run_native("ass_open_include",prefix,original_open_test(),driver)
