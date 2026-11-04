#!/usr/bin/env python3
"""Native VICE checks of verbatim ass.c staging and mnemonic lookup.

The test contains the entire original global section and first 23 functions.
It checks real global memory effects, not merely parsing or code size.
"""
from test_native import ASS_SOURCE,run_native,word_assert

def stage_test():
    lines=["\t* = $1000","main:"]
    n=0
    def put_byte(where,value):
        lines.extend(("\tlda #$%02x"%(value&255),"\tsta "+where))
    def put_word(where,value):
        put_byte(where,value&255)
        put_byte(where+"+1",value>>8)
    def check(where,value):
        nonlocal n
        lines.extend((
            "\tlda #$%02x"%(n&255),"\tsta $03",
            "\tlda "+where,"\tcmp #$%02x"%(value&255),
            "\tbeq .stage_ok_%d"%n,
            "\tjmp native_fail",
            ".stage_ok_%d:"%n,
        ))
        n+=1
    def result(status):
        lines.extend(word_assert(status&255,0,51000+n))

    # Direct staging, including last legal destination and full memory.
    for offset,value,status,expected in (
        (0,0x12,0,1),(255,0xa5,0,256),
        (256,0x7f,0,257),(11263,0xff,0,11264),
        (11264,0x34,11,11264)):
        put_word("n2_ass_image_length",offset)
        put_byte("n2_stage_byte_value",value)
        lines.append("\tjsr n2_stage_byte")
        result(status)
        check("n2_ass_image_length",expected&255)
        check("n2_ass_image_length+1",expected>>8)
        if status==0:
            check("n2_ass_image+%d"%offset,value)

    # The original word reference chain uses two stage_byte calls and
    # stores stage+1 in a true 16-bit symbol_payload array element.
    for symbol,offset,previous in (
        (0,0,0x1234),(255,255,0x00ff),
        (256,256,0xabcd),(895,511,0xffff)):
        put_word("n2_ass_image_length",offset)
        put_word("n2_symbol_payload+%d"%(2*symbol),previous)
        put_word("n2_stage_plain_word_reference_symbol",symbol)
        lines.append("\tjsr n2_stage_plain_word_reference")
        result(0)
        check("n2_ass_image+%d"%offset,previous&255)
        check("n2_ass_image+%d"%(offset+1),previous>>8)
        check("n2_ass_image_length",(offset+2)&255)
        check("n2_ass_image_length+1",(offset+2)>>8)
        check("n2_symbol_payload+%d"%(2*symbol),(offset+1)&255)
        check("n2_symbol_payload+%d"%(2*symbol+1),(offset+1)>>8)

    # Width zero, one, two, and rejected oversized immediate.
    for mode,value,opcode,status,output in (
        (0,0,0xea,0,(0xea,)),
        (2,0x34,0xa9,0,(0xa9,0x34)),
        (6,0x1234,0xad,0,(0xad,0x34,0x12)),
        (2,0x1234,0xa9,5,()),
    ):
        put_word("n2_ass_image_length",1000)
        put_byte("n2_stage_resolved_instruction_opcode",opcode)
        put_byte("n2_stage_resolved_instruction_mode",mode)
        put_word("n2_stage_resolved_instruction_value",value)
        lines.append("\tjsr n2_stage_resolved_instruction")
        result(status)
        check("n2_ass_image_length",(1000+len(output))&255)
        check("n2_ass_image_length+1",(1000+len(output))>>8)
        for index,c in enumerate(output):
            check("n2_ass_image+%d"%(1000+index),c)

    # Case-insensitive triplets: the callee upper_char() is exercised
    # while mnemonic_table[offset] is read through scaled char indexing.
    for name,length,expected in (
        ("ADC",3,0),("and",3,1),("AsL",3,2),
        ("ABC",3,65535),("ADC",2,65535)):
        for index,c in enumerate(name.encode()):
            put_byte("$4400+%d"%index,c)
        put_word("n2_find_mnemonic_name",0x4400)
        put_byte("n2_find_mnemonic_length",length)
        lines.append("\tjsr n2_find_mnemonic")
        lines.extend(word_assert(expected&255,(expected>>8)&255,
                                 51000+n))
        n+=1

    # 6502 ADC: immediate=$69, absolute=$6D, unknown implicit=-1.
    for mnemonic,mode,expected in (
        (0,2,0x69),(0,6,0x6d),(0,0,65535)):
        put_byte("n2_find_opcode_mnemonic",mnemonic)
        put_byte("n2_find_opcode_mode",mode)
        lines.append("\tjsr n2_find_opcode")
        lines.extend(word_assert(expected&255,(expected>>8)&255,
                                 51000+n))
        n+=1
    return lines

def run_stage_tests(driver):
    source=ASS_SOURCE[:ASS_SOURCE.index("char stage_unresolved_instruction(")]
    run_native("ass_stage",source,stage_test(),driver)
