#!/usr/bin/env python3
"""VICE checks complete 16-bit loads and comparisons of word-array elements."""
from test_native import ROOT,run_native,word_assert

def word_array_test():
    lines=["\t* = $1000","main:"]
    case=0
    samples=((0,0x0000),(1,0x00ff),(127,0x0100),
             (128,0x7fff),(255,0x8000),(256,0xffff),
             (511,0x1234),(639,0xabcd))
    def put(name,value,width=2):
        lines.extend((
            "\tlda #$%02x"%(value&255),
            "\tsta %s"%name,
        ))
        if width==2:
            lines.extend((
                "\tlda #$%02x"%((value>>8)&255),
                "\tsta %s+1"%name,
            ))
    def call(name,index,expect,other=None):
        nonlocal case
        put("n2_"+name+"_index",index)
        if other is not None:
            put("n2_"+name+"_expected",other)
        lines.append("\tjsr n2_"+name)
        lines.extend(word_assert(expect&255,(expect>>8)&255,21000+case))
        case+=1

    for index,value in samples:
        put("n2_word_samples+%d"%(index*2),value)
        call("read_sample",index,value)
        call("copy_sample",index,value)
        call("sample_equals",index,1,value)
        call("sample_equals",index,0,value^1)
        call("read_previous_sample",index+1,value)
    return lines

def run_word_array_tests(driver):
    source=(ROOT/"tests"/"nanoc2"/"word-array-read.c").read_text()
    run_native("word_array_read",source,word_array_test(),driver)
