#!/usr/bin/env python3
"""Native end-to-end checks for verbatim ass.c define_label and its callees.

Uses original unmodified assembler prefix (15 functions) and independent
6502 assertions for symbol allocation, duplicate errors, patch chains,
scoping and fixup resolution.
"""
from test_native import ASS_SOURCE,run_native,word_assert

def define_label_test():
    lines=["\t* = $1000","main:"]
    n=0

    def put_byte(place,value):
        lines.extend(("\tlda #$%02x"%(value&255),"\tsta "+place))

    def put_word(place,value):
        put_byte(place,value)
        put_byte(place+"+1",value>>8)

    def check(place,value):
        nonlocal n
        put_byte("$03",n)
        lines.extend((
            "\tlda "+place,
            "\tcmp #$%02x"%(value&255),
            "\tbeq .dl_ok_%d"%n,
            "\tjmp native_fail",
            ".dl_ok_%d:"%n,
        ))
        n+=1

    def call(name,scope,value,status):
        nonlocal n
        for i,c in enumerate(name):
            put_byte("$3500+%d"%i,c)
        put_word("n2_define_label_name",0x3500)
        put_byte("n2_define_label_length",len(name))
        put_word("n2_define_label_value",value)
        put_byte("n2_current_scope",scope)
        put_byte("$03",n)
        lines.append("\tjsr n2_define_label")
        lines.extend(word_assert(status,0,50000+n))
        n+=1

    put_word("n2_symbol_count",0)
    put_word("n2_symbol_name_used",0)
    put_word("n2_fixup_count",0)

    call((65,66,67),0,0x1234,0)
    check("n2_symbol_count",1)
    check("n2_symbol_name_used",3)
    check("n2_symbol_kind",2)  # SYMBOL_LABEL_DEFINED
    check("n2_symbol_payload",0x34)
    check("n2_symbol_payload+1",0x12)
    for i,c in enumerate((65,66,67)):
        check("n2_symbol_name_bytes+%d"%i,c)

    call((65,66,67),0,0x7777,2)  # duplicate defined label
    check("n2_symbol_payload",0x34)
    check("n2_symbol_payload+1",0x12)
    call((46,81),0,0x2345,4)  # dot-scoped with no active scope
    check("n2_symbol_count",1)

    # Resolve an undefined label whose head encodes a linked word patch.
    put_byte("n2_symbol_kind",1)  # SYMBOL_LABEL_UNDEFINED
    put_word("n2_symbol_payload",257)
    put_word("n2_ass_image+256",0)
    call((65,66,67),0,0xbeef,0)
    check("n2_symbol_kind",2)
    check("n2_symbol_payload",0xef)
    check("n2_symbol_payload+1",0xbe)
    check("n2_ass_image+256",0xef)
    check("n2_ass_image+257",0xbe)
    check("n2_symbol_count",1)

    call((46,81),7,0xa1bc,0)
    check("n2_symbol_count",2)
    check("n2_symbol_name_used",5)
    check("n2_symbol_scope+1",7)
    check("n2_symbol_kind+1",2)
    check("n2_symbol_payload+2",0xbc)
    check("n2_symbol_payload+3",0xa1)

    # Re-definition of an unresolved scoped label applies a waiting
    # 16-bit FIXUP_WORD through the actual resolve_fixups_for_symbol().
    put_byte("n2_symbol_kind+1",1)
    put_word("n2_symbol_payload+2",0)
    put_word("n2_fixup_count",1)
    put_byte("n2_fixup_kind",2)
    put_word("n2_fixup_symbol",1)
    put_word("n2_fixup_stage",300)
    put_word("n2_fixup_addend",17)
    put_byte("n2_fixup_prefix",0)
    put_byte("n2_ass_image+300",0x5a)
    put_byte("n2_ass_image+301",0xa5)
    call((46,81),7,0xa1bc,0)
    check("n2_symbol_kind+1",2)
    check("n2_fixup_kind",0)
    check("n2_fixup_count",0)
    check("n2_fixup_count+1",0)
    check("n2_ass_image+300",0xcd)
    check("n2_ass_image+301",0xa1)
    return lines

def run_define_label_tests(driver):
    end=ASS_SOURCE.index("/* ---------------- Tiny assembler value grammar")
    run_native("ass_define_label",ASS_SOURCE[:end],
               define_label_test(),driver)
