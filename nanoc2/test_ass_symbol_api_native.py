#!/usr/bin/env python3
"""Native 6510 regression tests for original ass.c intern_label/define_constant.

This uses the unmodified Phase-1 function bodies and original globals;
the independent caller exercises four-argument calls, pointers, rejection,
symbol reuse, index/page boundaries and two-byte payload storage.
"""
from test_native import ASS_SOURCE,ass_function,run_native,word_assert

def symbol_api_test():
    lines=["\t* = $1000","main:"]
    n=0

    def put_byte(place,value):
        lines.extend(("\tlda #$%02x"%(value&255),"\tsta "+place))

    def put_word(place,value):
        put_byte(place,value)
        put_byte(place+"+1",value>>8)

    def check_byte(place,value):
        nonlocal n
        put_byte("$03",n)
        lines.extend((
            "\tlda "+place,
            "\tcmp #$%02x"%(value&255),
            "\tbeq .api_ok_%d"%n,
            "\tjmp native_fail",
            ".api_ok_%d:"%n,
        ))
        n+=1

    def call(func,name,scope,expected,payload=0):
        nonlocal n
        for i,c in enumerate(name):
            put_byte("$3500+%d"%i,c)
        put_word("n2_"+func+"_name",0x3500)
        put_byte("n2_"+func+"_length",len(name))
        put_byte("n2_current_scope",scope)
        if func=="define_constant":
            put_word("n2_define_constant_value",payload)
        put_byte("$03",n)
        lines.append("\tjsr n2_"+func)
        lines.extend(word_assert(expected&255,(expected>>8)&255,41000+n))
        n+=1

    put_word("n2_symbol_count",0)
    put_word("n2_symbol_name_used",0)
    call("intern_label",(65,66,67),0,0)
    check_byte("n2_symbol_count",1)
    check_byte("n2_symbol_name_used",3)
    check_byte("n2_symbol_kind",1)
    check_byte("n2_symbol_payload",0)
    check_byte("n2_symbol_payload+1",0)
    for i,c in enumerate((65,66,67)):
        check_byte("n2_symbol_name_bytes+%d"%i,c)

    call("intern_label",(65,66,67),0,0)
    check_byte("n2_symbol_count",1)
    check_byte("n2_symbol_name_used",3)
    call("define_constant",(65,66,67),0,2,0xabcd)
    check_byte("n2_symbol_count",1)

    call("define_constant",(88,89,90),0,0,0xbeef)
    check_byte("n2_symbol_count",2)
    check_byte("n2_symbol_name_used",6)
    check_byte("n2_symbol_kind+1",0)
    check_byte("n2_symbol_payload+2",0xef)
    check_byte("n2_symbol_payload+3",0xbe)
    call("intern_label",(88,89,90),0,65532)

    call("intern_label",(46,76),0,65534)
    call("define_constant",(46,76),0,4,0x1234)
    check_byte("n2_symbol_count",2)
    call("intern_label",(46,76),7,2)
    check_byte("n2_symbol_count",3)
    check_byte("n2_symbol_name_used",8)
    check_byte("n2_symbol_scope+2",7)
    check_byte("n2_symbol_kind+2",1)
    call("intern_label",(46,76),7,2)

    # 16-bit symbol index 255, and a name starting at byte 255;
    # mismatch scope for earlier slots so find_symbol scans safely.
    put_word("n2_symbol_count",255)
    put_word("n2_symbol_name_used",255)
    for i in range(3,255):
        put_byte("n2_symbol_scope+%d"%i,7)
    put_byte("n2_symbol_scope",7)
    put_byte("n2_symbol_scope+1",7)
    call("intern_label",(70,79,79),0,255)
    check_byte("n2_symbol_count",0)
    check_byte("n2_symbol_count+1",1)
    check_byte("n2_symbol_name_used",2)
    check_byte("n2_symbol_name_used+1",1)
    check_byte("n2_symbol_name_offset+510",255)
    check_byte("n2_symbol_name_offset+511",0)
    for i,c in enumerate((70,79,79)):
        check_byte("n2_symbol_name_bytes+%d"%(255+i),c)
    call("intern_label",(70,79,79),0,255)
    check_byte("n2_symbol_count",0)
    check_byte("n2_symbol_count+1",1)

    # Capacity failure propagates from the real allocate_symbol call
    # through the API without mutating either counter.
    put_word("n2_symbol_name_used",9343)
    call("define_constant",(90,90),0,3,0x2222)
    check_byte("n2_symbol_count",0)
    check_byte("n2_symbol_count+1",1)
    check_byte("n2_symbol_name_used",0x7f)
    check_byte("n2_symbol_name_used+1",0x24)
    return lines

def run_symbol_api_tests(driver):
    source=ASS_SOURCE[:ASS_SOURCE.index("char upper_char(")]
    source+="\n".join(ass_function(name) for name in (
        "scope_for_name","find_symbol","allocate_symbol",
        "intern_label","define_constant"))
    run_native("ass_symbol_api",source,symbol_api_test(),driver)
