#!/usr/bin/env python3
"""Run original close_source_tree unchanged: indexed char -> int io_close."""
from test_native import ROOT, ASS_SOURCE, ass_function, run_native, word_assert

def original_close_test():
    lines=["\t* = $1000","main:","\tjsr n2_io_init"]
    case=0

    def put(addr,value):
        lines.extend(("\tlda #$%02x"%(value&255),"\tsta "+addr))

    def check(addr,value):
        nonlocal case
        lines.extend(("\tlda "+addr,"\tcmp #$%02x"%(value&255),
                      "\tbeq .close_ok_%d"%case,"\tjmp native_fail",
                      ".close_ok_%d:"%case))
        case+=1

    for depth in (-1,0,2,4):
        put("n2_source_depth",depth)
        put("n2_source_depth+1",255 if depth<0 else 0)
        for i in range(5):
            put("n2_source_handle+%d"%i,255)
        lines.append("\tjsr n2_close_source_tree")
        lines.extend(word_assert(0,0,63000+case))
        check("n2_source_depth",255)
        check("n2_source_depth+1",255)

    return lines

def run_ass_close_tests(driver):
    # Keep the actual unmodified function and complete original global
    # declarations, without requiring all preceding function bodies.
    prefix=ASS_SOURCE[:ASS_SOURCE.index("char upper_char(")]
    source=prefix+"\n"+ass_function("close_source_tree")+"\n"
    run_native("ass_close_source_tree",source,original_close_test(),driver)
