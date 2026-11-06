#!/usr/bin/env python3
"""Native 6510 oracle for array decay plus typed byte/word call offsets."""
from test_native import ROOT, run_native, word_assert

def offset_call_test():
    lines=["\t* = $1000","main:"]
    sequence=0

    def byte_at(address, value):
        lines.extend(("\tlda #$%02x"%(value&255),
                      "\tsta "+address))

    def word_at(address, value):
        byte_at(address,value)
        byte_at(address+"+1",value>>8)

    def call(name, expected):
        nonlocal sequence
        lines.append("\tjsr n2_"+name)
        lines.extend(word_assert(expected,0,61000+sequence))
        sequence+=1

    for start in (0,1,127,254,255):
        result=(0x30+sequence)&255
        byte_at("n2_offset_bytes+%d"%(start+1),result)
        byte_at("n2_offset_from_byte_start",start)
        call("offset_from_byte",result)

    for start in (0,1,254,255,256,510,511,638):
        result=(0x60+sequence)&255
        byte_at("n2_offset_bytes+%d"%(start+1),result)
        word_at("n2_offset_from_word_start",start)
        call("offset_from_word",result)

    byte_at("n2_offset_bytes+256",0xc4)
    call("offset_from_literal",0xc4)

    # Crossing a page via the *pointer parameter* and a byte offset
    # must retain the carry even when the callee then uses (zp),Y.
    for base,start in ((0x30fe,0),(0x30fe,1),(0x30fe,255),
                       (0x31ff,1),(0x31fe,255)):
        result=(0xa0+sequence)&255
        byte_at("$%04x"%(base+start+1),result)
        word_at("n2_offset_from_pointer_data",base)
        byte_at("n2_offset_from_pointer_start",start)
        call("offset_from_pointer",result)

    return lines

def run_array_offset_call_tests(driver):
    source=(ROOT/"tests"/"nanoc2"/"array-offset-call.c").read_text()
    run_native("array_offset_call",source,offset_call_test(),driver)
