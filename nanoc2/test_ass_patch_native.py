#!/usr/bin/env python3
"""Run actual ass.c patch_word_chain on a 6510, checking linked word patches."""
from test_native import ASS_SOURCE,ass_function,run_native,word_assert

def patch_test():
    lines=["\t* = $1000","main:"]
    check=0

    def put_byte(place,value):
        lines.extend(("\tlda #$%02x"%(value&255),"\tsta "+place))

    def put_word(place,value):
        put_byte(place,value)
        put_byte(place+"+1",value>>8)

    def assert_byte(place,value):
        nonlocal check
        put_byte("$03",check)
        lines.extend((
            "\tlda "+place,
            "\tcmp #$%02x"%(value&255),
            "\tbeq .patch_ok_%d"%check,
            "\tjmp native_fail",
            ".patch_ok_%d:"%check,
        ))
        check+=1

    def run_case(head,value,links):
        nonlocal check
        # links are (stage,next_head) and must form the exact chain.
        for stage,nxt in links:
            put_word("n2_ass_image+%d"%stage,nxt)
        put_word("n2_patch_word_chain_head",head)
        put_word("n2_patch_word_chain_value",value)
        put_byte("$03",check)
        lines.append("\tjsr n2_patch_word_chain")
        lines.extend(word_assert(0,0,45000+check))
        check+=1
        for stage,_ in links:
            assert_byte("n2_ass_image+%d"%stage,value&255)
            assert_byte("n2_ass_image+%d"%(stage+1),value>>8)

    put_byte("n2_ass_image+1024",0x5a)
    run_case(0,0xbeef,())
    assert_byte("n2_ass_image+1024",0x5a)
    run_case(1,0x1234,((0,0),))
    run_case(256,0xa57c,((255,0),))
    run_case(513,0xbeef,((512,257),(256,2),(1,0)))
    run_case(11263,0x8001,((11262,0),))
    return lines

def run_patch_tests(driver):
    source=ASS_SOURCE[:ASS_SOURCE.index("char upper_char(")]
    source+="\n"+ass_function("patch_word_chain")
    run_native("ass_patch_word",source,patch_test(),driver)
