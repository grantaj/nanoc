#!/usr/bin/env python3
"""Native VICE truth table for verbatim Phase-1 ass.c parse_value().

The caller tests the actual global result/fixup capture fields and the
source's pointer-plus-position and length-minus-position call operands,
including 6502 page carry and 16-bit wraparound.
"""
from test_native import ASS_SOURCE,run_native,word_assert

def value_test():
    lines=["\t* = $1000","main:"]
    n=0
    # source, status, resolved value, captured prefix, captured addend
    cases=(
        ("$1234",0,0x1234,0,0x1234),
        ("<$1234",0,0x34,1,0x1234),
        (">$1234",0,0x12,2,0x1234),
        ("$FFFF+1",0,0,0,0),
        ("<$FFFF+1",0,0,1,0),
        ("100+20",0,120,0,120),
        ("0-1",0,65535,0,65535),
        ("'A'+1",0,66,0,66),
        ("65536",0,0,0,0),
        ("17+3",0,20,0,20),
        ("<17+3",0,20,1,20),
        (">258",0,1,2,258),
        ("0+",2,None,0,None),
        (">",2,None,2,None),
    )
    def check(place,value):
        nonlocal n
        lines.extend((
            "\tlda "+place,
            "\tcmp #$%02x"%(value&255),
            "\tbeq .pv_ok_%d"%n,
            "\tjmp native_fail",
            ".pv_ok_%d:"%n,
        ))
        n+=1
    for case,(source,status,result,prefix,addend) in enumerate(cases):
        address=0x3600 if case%2==0 else 0x36fc
        for k,c in enumerate(source.encode()):
            lines.extend((
                "\tlda #$%02x"%c,
                "\tsta $%04x"%(address+k),
            ))
        lines.extend((
            "\tlda #$%02x"%(address&255),
            "\tsta n2_parse_value_text",
            "\tlda #$%02x"%((address>>8)&255),
            "\tsta n2_parse_value_text+1",
            "\tlda #$%02x"%len(source),
            "\tsta n2_parse_value_length",
            "\tlda #$%02x"%case,
            "\tsta $03",
            "\tjsr n2_parse_value",
        ))
        lines.extend(word_assert(status,0,41000+case))
        if result is not None:
            check("n2_value_result",result&255)
            check("n2_value_result+1",(result>>8)&255)
            check("n2_captured_prefix",prefix)
            check("n2_captured_addend",addend&255)
            check("n2_captured_addend+1",(addend>>8)&255)
            check("n2_captured_symbol",255)
            check("n2_captured_symbol+1",255)
    return lines

def run_ass_value_tests(driver):
    source=ASS_SOURCE[:ASS_SOURCE.index("/* ---------------- Shared 6502 instruction metadata")]
    run_native("ass_value",source,value_test(),driver)
