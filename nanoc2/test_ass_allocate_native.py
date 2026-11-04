#!/usr/bin/env python3
"""Native verification of the verbatim Phase-1 ass.c allocate_symbol.

Checks the 16-bit word+byte index used to copy a name from a char*
argument into the global byte table, as well as all five symbol fields,
boundary crossings and the original capacity/scope rejection paths.
"""
from test_native import ASS_SOURCE, ass_function, run_native, word_assert

def allocation_test():
    lines=["\t* = $1000","main:"]
    number=0

    def put_byte(address,value):
        lines.extend(("\tlda #$%02x"%(value&255),"\tsta "+address))

    def put_word(address,value):
        put_byte(address,value)
        put_byte(address+"+1",value>>8)

    def assert_byte(address,value):
        nonlocal number
        lines.extend((
            "\tlda #$%02x"%(number&255),
            "\tsta $03",
            "\tlda "+address,
            "\tcmp #$%02x"%(value&255),
            "\tbeq .alloc_ok_%d"%number,
            "\tjmp native_fail",
            ".alloc_ok_%d:"%number,
        ))
        number+=1

    # n, used, name bytes, scope, kind, payload, return status.
    # This covers 255/256, 511/512, maximum name-table address,
    # maximum symbol index, bad scope and full-table rejection.
    cases=(
        (0,0,(65,66,67),0,4,0x1234,0),
        (1,253,(87,88,89,90),0,7,0xabcd,1),
        (255,509,(70,79,79,33),0,255,0xffff,255),
        (256,255,(65,66,67),0,3,0x8000,256),
        (895,9342,(90,88),0,2,0x0102,895),
        (7,104,(46,76),7,5,0x4321,7),
        (896,100,(65,),0,2,0x1234,65533),
        (2,9343,(65,66),0,2,0x1234,65533),
        (2,100,(46,76),0,2,0x1234,65534),
        (2,100,(),0,2,0x1234,65534),
    )
    for count,used,name,scope,kind,payload,expected in cases:
        put_word("n2_symbol_count",count)
        put_word("n2_symbol_name_used",used)
        put_byte("n2_current_scope",scope)
        put_word("n2_allocate_symbol_name",0x3500)
        put_byte("n2_allocate_symbol_length",len(name))
        put_byte("n2_allocate_symbol_kind",kind)
        put_word("n2_allocate_symbol_payload",payload)
        for i,v in enumerate(name):
            put_byte("$3500+%d"%i,v)
        # Sentinel data ensure error exits do not accidentally write.
        put_byte("n2_symbol_name_bytes+%d"%min(used,9343),0x9b)
        lines.extend(("\tlda #$%02x"%(number&255),"\tsta $03"))
        lines.append("\tjsr n2_allocate_symbol")
        lines.extend(word_assert(expected&255,(expected>>8)&255,
                                 38000+number))
        success=expected<896
        assert_byte("n2_symbol_count", (count+1 if success else count)&255)
        assert_byte("n2_symbol_count+1",
                    ((count+1 if success else count)>>8)&255)
        assert_byte("n2_symbol_name_used",
                    (used+len(name) if success else used)&255)
        assert_byte("n2_symbol_name_used+1",
                    ((used+len(name) if success else used)>>8)&255)
        if success:
            assert_byte("n2_symbol_name_offset+%d"%(count*2),used&255)
            assert_byte("n2_symbol_name_offset+%d"%(count*2+1),used>>8)
            assert_byte("n2_symbol_name_length+%d"%count,len(name))
            assert_byte("n2_symbol_payload+%d"%(count*2),payload&255)
            assert_byte("n2_symbol_payload+%d"%(count*2+1),payload>>8)
            assert_byte("n2_symbol_scope+%d"%count,scope if name[0]==46 else 0)
            assert_byte("n2_symbol_kind+%d"%count,kind)
            for i,value in enumerate(name):
                assert_byte("n2_symbol_name_bytes+%d"%(used+i),value)
        else:
            assert_byte("n2_symbol_name_bytes+%d"%min(used,9343),0x9b)
    return lines

def run_allocation_tests(driver):
    source=ASS_SOURCE[:ASS_SOURCE.index("char upper_char(")]
    source+="\n"+ass_function("scope_for_name")
    source+="\n"+ass_function("allocate_symbol")
    run_native("ass_allocate",source,allocation_test(),driver)
