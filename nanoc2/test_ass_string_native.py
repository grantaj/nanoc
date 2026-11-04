#!/usr/bin/env python3
"""Native VICE oracle for the verbatim original ass.c assemble_string()."""
from test_native import ASS_SOURCE, run_native, word_assert

def string_test():
    lines=["\t* = $1000","main:"]
    n=0
    def put_byte(where,value):
        lines.extend(("\tlda #$%02x"%(value&255),"\tsta "+where))
    def put_word(where,value):
        put_byte(where,value&255)
        put_byte(where+"+1",value>>8)
    def check(where,value):
        nonlocal n
        lines.extend(("\tlda "+where,"\tcmp #$%02x"%(value&255),
                      "\tbeq .str_ok_%d"%n,"\tjmp native_fail",
                      ".str_ok_%d:"%n))
        n+=1

    cases=(
        (b'""',0,0,b'\x00'),
        (b'"A"',0,255,b'A\x00'),
        (b'"BC"',0,256,b'BC\x00'),
        (b'bad',9,512,b''),
        (b'"A',9,512,b''),
        (b'X"',9,512,b''),
        (b'',9,512,b''),
        (b'"'+b'A'*253+b'"',0,1024,b'A'*253+b'\x00'),
        (b'""',0,11263,b'\x00'),
        (b'""',11,11264,b''),
    )
    for case,(source,status,offset,output) in enumerate(cases):
        address=0x88fe if case%2 else 0x8800
        if len(source)>40:
            lines.extend(("\tldx #$00","\tlda #$41",
                          ".str_fill_%d:"%case,
                          "\tsta $%04x,x"%address,
                          "\tinx",
                          "\tbne .str_fill_%d"%case))
            for index in (0,len(source)-1):
                put_byte("$%04x"%(address+index),source[index])
        else:
            for index,c in enumerate(source):
                put_byte("$%04x"%(address+index),c)
        put_word("n2_assemble_string_argument",address)
        put_byte("n2_assemble_string_length",len(source))
        put_word("n2_ass_image_length",offset)
        lines.append("\tjsr n2_assemble_string")
        lines.extend(word_assert(status,0,55000+case))
        expected_length=offset+len(output)
        check("n2_ass_image_length",expected_length&255)
        check("n2_ass_image_length+1",expected_length>>8)
        if output:
            for index in sorted(set((0,len(output)//2,len(output)-1))):
                check("n2_ass_image+%d"%(offset+index),output[index])
    return lines

def run_string_tests(driver):
    source=ASS_SOURCE[:ASS_SOURCE.index("char open_include(")]
    run_native("ass_string",source,string_test(),driver)
