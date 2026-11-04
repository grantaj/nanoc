#!/usr/bin/env python3
"""Execute verbatim ass.c resolve_fixups_for_symbol() on a real 6510.

Check word/byte/relative fixup application and error preservation. Each
sample programs original compiler globals using the independent native
caller; no equivalent C routine or hand-picked emitter source is used.
"""
from test_native import ASS_SOURCE,ass_function,run_native,word_assert

def resolve_test():
    lines=["\t* = $1000","main:"]
    number=0

    def put_byte(place,value):
        lines.extend(("\tlda #$%02x"%(value&255),"\tsta "+place))
    def put_word(place,value):
        put_byte(place,value)
        put_byte(place+"+1",(value>>8)&255)
    def check(place,expected):
        nonlocal number
        lines.extend((
            "\tlda #$%02x"%(number&255),
            "\tsta $03",
            "\tlda "+place,
            "\tcmp #$%02x"%(expected&255),
            "\tbeq .rv_ok_%d"%number,
            "\tjmp native_fail",
            ".rv_ok_%d:"%number,
        ))
        number+=1

    # kind, payload, addend, prefix, stage, origin, expected return,
    # expected image low, expected image high (None = unchanged).
    cases=(
        (2,0x1234,0x00cd,0,255,0x2000,0,0x01,0x13),
        (2,0xabcd,0,1,256,0x2000,0,0xcd,0),
        (2,0xabcd,0,2,511,0x2000,0,0xab,0),
        (3,0x1004,0,0,1,0x1000,0,2,None),
        (3,0x1000,0,0,0,0x1000,0,255,None),
        (3,0x1200,0,0,0,0x1000,7,None,None),
        (4,0x0123,0,0,500,0x2000,9,None,None),
        (1,0x00fe,0,0,127,0x2000,0,0xfe,None),
        (1,0x0300,0,0,128,0x2000,7,None,None),
    )
    symbol=7
    for kind,payload,addend,prefix,stage,origin,status,lo,hi in cases:
        put_word("n2_fixup_count",1)
        put_byte("n2_fixup_kind",kind)
        put_word("n2_fixup_stage",stage)
        put_word("n2_fixup_symbol",symbol)
        put_word("n2_fixup_addend",addend)
        put_byte("n2_fixup_prefix",prefix)
        put_word("n2_symbol_payload+%d"%(symbol*2),payload)
        put_word("n2_ass_origin",origin)
        put_byte("n2_ass_image+%d"%stage,0x5a)
        put_byte("n2_ass_image+%d"%(stage+1),0xa5)
        put_word("n2_resolve_fixups_for_symbol_symbol",symbol)
        lines.append("\tjsr n2_resolve_fixups_for_symbol")
        lines.extend(word_assert(status,0,28000+number))
        success=(status==0)
        check("n2_fixup_kind",0 if success else kind)
        check("n2_fixup_count",0 if success else 1)
        check("n2_fixup_count+1",0)
        check("n2_ass_image+%d"%stage,0x5a if lo is None else lo)
        check("n2_ass_image+%d"%(stage+1),0xa5 if hi is None else hi)

    # A different symbol must not touch either image or fixup, and trim
    # cannot remove a still-pending final table entry.
    put_word("n2_fixup_count",1)
    put_byte("n2_fixup_kind",2)
    put_word("n2_fixup_stage",300)
    put_word("n2_fixup_symbol",7)
    put_word("n2_symbol_payload+%d"%(7*2),0x7777)
    put_byte("n2_ass_image+300",0x5a)
    put_word("n2_resolve_fixups_for_symbol_symbol",8)
    lines.append("\tjsr n2_resolve_fixups_for_symbol")
    lines.extend(word_assert(0,0,28000+number))
    check("n2_fixup_kind",2)
    check("n2_fixup_count",1)
    check("n2_ass_image+300",0x5a)

    # The next original function uses name[0] with a literal pointer
    # offset, including dot-scoped labels and the special empty name.
    for first,length,scope,expected in (
        (46,0,0,65535),(46,1,0,65535),
        (46,1,1,1),(46,1,0xa5,0xa5),
        (65,1,0,0),(65,1,0xa5,0),
    ):
        put_word("n2_scope_for_name_name",0x3300)
        put_byte("n2_scope_for_name_length",length)
        put_byte("$3300",first)
        put_byte("n2_current_scope",scope)
        put_byte("$03",number&255)
        lines.append("\tjsr n2_scope_for_name")
        lines.extend(word_assert(expected&255,(expected>>8)&255,
                                 28000+number))
        number+=1

    # Real owned-name lookup: the caller passes the char* to
    # scope_for_name(), then reads both global word/byte tables and
    # compares symbol_name_bytes[offset+j] with name[j] through two
    # independently owned zero-page cursors.
    put_word("n2_symbol_count",3)
    for index,scope,name,offset in (
        (0,0,(70,79,79),0), (1,7,(46,76),3),
        (2,0,(66,65,82),5),
    ):
        put_byte("n2_symbol_scope+%d"%index,scope)
        put_byte("n2_symbol_name_length+%d"%index,len(name))
        put_word("n2_symbol_name_offset+%d"%(2*index),offset)
        for j,c in enumerate(name):
            put_byte("n2_symbol_name_bytes+%d"%(offset+j),c)

    for name,scope,expected in (
        ((70,79,79),0,0), ((70,79,66),0,65535),
        ((46,76),7,1), ((46,76),0,65534),
        ((66,65,82),7,2), ((70,79),0,65535),
        ((66,65,82),0,2),
    ):
        for j,c in enumerate(name):
            put_byte("$3500+%d"%j,c)
        put_word("n2_find_symbol_name",0x3500)
        put_byte("n2_find_symbol_length",len(name))
        put_byte("n2_current_scope",scope)
        put_byte("$03",number&255)
        lines.append("\tjsr n2_find_symbol")
        lines.extend(word_assert(expected&255,(expected>>8)&255,
                                 29000+number))
        number+=1

    # Cross the 8-bit symbol index at 256 and the byte-array page
    # boundary at offset 510. Earlier symbol scopes deliberately differ.
    put_word("n2_symbol_count",257)
    for index in range(256):
        put_byte("n2_symbol_scope+%d"%index,7)
    put_byte("n2_symbol_scope+256",0)
    put_byte("n2_symbol_name_length+256",3)
    put_word("n2_symbol_name_offset+512",510)
    for j,c in enumerate((65,66,67)):
        put_byte("n2_symbol_name_bytes+%d"%(510+j),c)
        put_byte("$3500+%d"%j,c)
    put_word("n2_find_symbol_name",0x3500)
    put_byte("n2_find_symbol_length",3)
    put_byte("n2_current_scope",0)
    put_byte("$03",number&255)
    lines.append("\tjsr n2_find_symbol")
    lines.extend(word_assert(0,1,29000+number))
    return lines

def run_resolve_tests(driver):
    source=ASS_SOURCE[:ASS_SOURCE.index("char upper_char(")]
    source+="\n".join(ass_function(name) for name in (
        "upper_char","same_text","apply_byte_prefix","hex_nibble",
        "append_fixup","relative_byte","trim_fixups",
        "resolve_fixups_for_symbol","scope_for_name","find_symbol"))
    run_native("ass_resolve",source,resolve_test(),driver)
