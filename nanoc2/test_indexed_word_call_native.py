#!/usr/bin/env python3
"""Real 6510 test: byte-array element promoted into word call argument."""
from test_native import ROOT, run_native, word_assert

def promoted_index_test():
    lines=["\t* = $1000", "main:"]
    case=0

    def put(addr,val):
        lines.extend(("\tlda #$%02x"%(val&255),"\tsta "+addr))

    def call(name,index,value,width):
        nonlocal case
        put("n2_promoted_bytes+%d"%index,value)
        put("n2_%s_offset"%name,index)
        if width==2:
            put("n2_%s_offset+1"%name,index>>8)
        lines.append("\tjsr n2_"+name)
        lines.extend(word_assert(value,0,62000+case))
        case+=1

    for i,value in ((0,0),(1,127),(127,128),(254,254),(255,255)):
        call("promoted_byte_index",i,value,1)

    for i,value in ((0,255),(1,1),(255,128),(256,253),
                    (257,0),(511,255),(512,128),(639,254)):
        call("promoted_word_index",i,value,2)

    return lines

def run_indexed_word_call_tests(driver):
    source=(ROOT/"tests"/"nanoc2"/"indexed-word-call.c").read_text()
    run_native("indexed_word_call",source,promoted_index_test(),driver)
