#!/usr/bin/env python3
"""VICE truth table for the verbatim original ass.c hexadecimal/decimal atom parser.

C source is the actual complete prefix of bootstrap/ass.c, with original
global declarations and preceding functions (no surrogate tokenizer).
The caller independently checks status, consumed bytes, kind and full 16-bit
value, especially decimal overflow and pointer indexing across a page.
"""
from test_native import ASS_SOURCE,run_native,word_assert

def atom_test():
    lines=["\t* = $1000","main:"]
    cases=(
        ("$1A2B",0,0x1a2b,5),
        ("$fF+12",0,0x00ff,3),
        ("$0000",0,0,5),
        ("$FFFF",0,65535,5),
        ("$12345",2,None,4),
        ("$G",2,None,0),
        ("$",2,None,0),
        ("'A'",0,65,3),
        ("'-'",0,45,3),
        ("'A",2,None,0),
        ("12",0,12,2),
        ("65535",0,65535,5),
        ("65536",0,0,5),
        ("99999",0,99999&65535,5),
        ("12+9",0,12,2),
        ("45-7",0,45,2),
    )
    n=0
    def check(place,value):
        nonlocal n
        lines.extend((
            "\tlda "+place,
            "\tcmp #$%02x"%(value&255),
            "\tbeq .atom_ok_%d"%n,
            "\tjmp native_fail",
            ".atom_ok_%d:"%n,
        ))
        n+=1
    for index,(source,status,value,used) in enumerate(cases):
        address=0x3500 if index%2==0 else 0x35fe
        for k,c in enumerate(source.encode()):
            lines.extend((
                "\tlda #$%02x"%c,
                "\tsta $%04x"%(address+k),
            ))
        lines.extend((
            "\tlda #$%02x"%(address&255),
            "\tsta n2_parse_atom_text",
            "\tlda #$%02x"%((address>>8)&255),
            "\tsta n2_parse_atom_text+1",
            "\tlda #$%02x"%len(source),
            "\tsta n2_parse_atom_length",
            "\tlda #$%02x"%index,
            "\tsta $03",
            "\tjsr n2_parse_atom",
        ))
        lines.extend(word_assert(status,0,39000+index))
        check("n2_atom_used",used)
        if value is not None:
            check("n2_atom_kind",0)
            check("n2_atom_value",value&255)
            check("n2_atom_value+1",(value>>8)&255)
    return lines

def run_ass_atom_tests(driver):
    source=ASS_SOURCE[:ASS_SOURCE.index("char parse_value(")]
    run_native("ass_atom",source,atom_test(),driver)
