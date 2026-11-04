#!/usr/bin/env python3
"""Native VICE execution of the first four *verbatim* bootstrap/ass.c functions.

The caller is independent 6502 assembly and checks returns and actual
initialized global data. No surrogate C implementation is used.
"""
from test_native import ass_function, ass_global, run_native, word_assert

def ass_prefix_test():
    lines=["\t* = $1000","main:"]
    case=0

    def call(name,params,expected):
        nonlocal case
        for param,value,width in params:
            lines.extend((
                "\tlda #$%02x"%(value&255),
                "\tsta n2_%s_%s"%(name,param),
            ))
            if width==2:
                lines.extend((
                    "\tlda #$%02x"%((value>>8)&255),
                    "\tsta n2_%s_%s+1"%(name,param),
                ))
        lines.append("\tjsr n2_%s"%name)
        lines.extend(word_assert(expected&255,(expected>>8)&255,9000+case))
        case+=1

    for c in (0,65,90,96,97,122,123,127,255):
        call("upper_char",(("c",c,1),),c-32 if 97<=c<=122 else c)

    # Read the actual assembler's emitted initialized table.
    for i,value in enumerate((0,0,1,1,1,1,2,2,2,2,1,1,1,0)):
        lines.extend((
            "\tlda n2_mode_width+%d"%i,
            "\tcmp #$%02x"%value,
            "\tbeq .ass_data_%d"%i,
            "\tjmp native_fail",
            ".ass_data_%d:"%i,
        ))

    for value,prefix in ((0x1234,1),(0xabcd,1),(0xffff,1),
                         (0x1234,2),(0xabcd,2),(0xffff,2)):
        expected=value&255 if prefix==1 else (value>>8)&255
        call("apply_byte_prefix",
             (("value",value,2),("prefix",prefix,1)),expected)

    for c in (48,51,57,65,67,70,97,99,102,71,103,0):
        if 48<=c<=57: expected=c-48
        elif 65<=c<=70: expected=c-65+10
        elif 97<=c<=102: expected=c-97+10
        else: expected=65535
        call("hex_nibble",(("c",c,1),),expected)

    for i,c in enumerate((65,66,67,68)):
        lines.extend((
            "\tlda #$%02x"%c,
            "\tsta $%04x"%(0x3000+i),
            "\tsta $%04x"%(0x3200+i),
        ))
    pair=(("a",0x3000,2),("a_length",4,1),
          ("b",0x3200,2),("b_length",4,1))
    call("same_text",pair,1)
    lines.extend(("\tlda #$5a","\tsta $3201"))
    call("same_text",pair,0)
    call("same_text",(("a",0x3000,2),("a_length",3,1),
                      ("b",0x3200,2),("b_length",4,1)),0)
    call("same_text",(("a",0x3000,2),("a_length",0,1),
                      ("b",0x3200,2),("b_length",0,1)),1)
    return lines

def run_ass_tests(driver):
    source="\n".join(ass_global(name) for name in (
        "VALUE_PREFIX_LOW","VALUE_PREFIX_HIGH","mode_width"))+"\n"
    source+="\n".join(ass_function(name) for name in (
        "upper_char","same_text","apply_byte_prefix","hex_nibble"))
    run_native("ass_prefix",source,ass_prefix_test(),driver)
