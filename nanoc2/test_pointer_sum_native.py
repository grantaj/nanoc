#!/usr/bin/env python3
"""VICE oracle for computed pointer sums, page carry and ZP-lane reuse."""
from test_native import ROOT, run_native, word_assert

def pointer_test():
    lines=["\t* = $1000","main:"]
    n=0
    def put_byte(place,value):
        lines.extend(("\tlda #$%02x"%(value&255),"\tsta "+place))
    def put_word(place,value):
        put_byte(place,value&255)
        put_byte(place+"+1",value>>8)
    def check(place,value):
        nonlocal n
        lines.extend(("\tlda "+place,"\tcmp #$%02x"%(value&255),
                      "\tbeq .psok_%d"%n,"\tjmp native_fail",
                      ".psok_%d:"%n))
        n+=1
    cases=((0,0),(1,0),(254,1),(255,1),(250,10),(255,255))
    for q,(left,right) in enumerate(cases):
        address=0x32fe+left+right
        expected=0x31+q
        put_byte("$%04x"%address,expected)
        put_word("n2_pointer_sum_read_data",0x32fe)
        put_byte("n2_pointer_sum_read_left",left)
        put_byte("n2_pointer_sum_read_right",right)
        lines.append("\tjsr n2_pointer_sum_read")
        lines.extend(word_assert(expected,0,60000+q))
        put_word("n2_pointer_sum_store_data",0x32fe)
        put_byte("n2_pointer_sum_store_left",left)
        put_byte("n2_pointer_sum_store_right",right)
        put_byte("n2_pointer_sum_store_value",0xa0+q)
        lines.append("\tjsr n2_pointer_sum_store")
        lines.extend(word_assert(0xa0+q,0,60100+q))
        check("$%04x"%address,0xa0+q)
    for q,(where,left,right) in enumerate((
        (0,1,2),(255,255,1),(256,254,2),(511,255,255),(639,0,1)
    )):
        # A and B have separate real static pointer homes. Wide array
        # access borrows B's cursor, then B[left] is read again.
        put_word("n2_pointer_mix_first",0x3200)
        put_word("n2_pointer_mix_second",0x39fe)
        put_word("n2_pointer_mix_where",where)
        put_byte("n2_pointer_mix_left",left)
        put_byte("n2_pointer_mix_right",right)
        put_byte("$3200",0x11)
        put_byte("$%04x"%(0x39fe+left+right),0x70+q)
        put_byte("$%04x"%(0x39fe+left),0x50+q)
        lines.append("\tjsr n2_pointer_mix")
        lines.extend(word_assert(0x50+q,0,60200+q))
        check("n2_mixed_marks+%d"%where,0x70+q)
    return lines

def run_pointer_sum_tests(driver):
    source=(ROOT/"tests"/"nanoc2"/"pointer-sum.c").read_text()
    run_native("pointer_sum",source,pointer_test(),driver)
