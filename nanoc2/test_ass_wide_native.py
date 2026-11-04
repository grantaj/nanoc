#!/usr/bin/env python3
"""Exercise the unmodified ass.c append_fixup routine on the 6510.

This source tests 16-bit array indexes across page boundaries and scaled
word elements. The complete original global prelude is used, not a reduced
lookalike layout. The native caller checks real memory and static ABI homes.
"""
from test_native import ASS_SOURCE,ass_function,run_native,word_assert

def ass_wide_test():
    lines=["\t* = $1000","main:"]
    case=0
    records=(
        (0, 1, 0x1234, 0x4321, 0xffff, 2),
        (1, 3, 0x00ff, 0xffff, 0x0100, 0),
        (255, 5, 0xff00, 0x7fff, 0xabcd, 1),
        (256, 7, 0x8000, 0x8001, 0x1234, 2),
        (511, 9, 0x1234, 0x0000, 0xffaa, 3),
        (639, 4, 0xffff, 0x9a01, 0x55aa, 1),
    )

    def put_word(name,value):
        lines.extend((
            "\tlda #$%02x"%(value&255),
            "\tsta %s"%name,
            "\tlda #$%02x"%((value>>8)&255),
            "\tsta %s+1"%name,
        ))

    def check_byte(name,value):
        nonlocal case
        lines.extend((
            "\tlda #$%02x"%(case&255),
            "\tsta $03",
            "\tlda %s"%name,
            "\tcmp #$%02x"%(value&255),
            "\tbeq .ab_check_%d"%case,
            "\tjmp native_fail",
            ".ab_check_%d:"%case,
        ))
        case+=1

    for index,kind,stage,symbol,addend,prefix in records:
        put_word("n2_fixup_count",index)
        put_word("n2_append_fixup_stage",stage)
        put_word("n2_append_fixup_symbol",symbol)
        put_word("n2_append_fixup_addend",addend)
        for param,value in (("kind",kind),("prefix",prefix)):
            lines.extend((
                "\tlda #$%02x"%value,
                "\tsta n2_append_fixup_%s"%param,
            ))
        lines.append("\tjsr n2_append_fixup")
        lines.extend(word_assert(0,0,11000+case))
        check_byte("n2_fixup_count", (index+1)&255)
        check_byte("n2_fixup_count+1",((index+1)>>8)&255)
        check_byte("n2_fixup_kind+%d"%index,kind)
        check_byte("n2_fixup_prefix+%d"%index,prefix)
        for name,value in (("fixup_stage",stage),
                           ("fixup_symbol",symbol),
                           ("fixup_addend",addend)):
            check_byte("n2_%s+%d"%(name,index*2),value&255)
            check_byte("n2_%s+%d"%(name,index*2+1),(value>>8)&255)

    # At capacity no table write should occur; count remains exactly 640.
    put_word("n2_fixup_count",640)
    lines.append("\tjsr n2_append_fixup")
    lines.extend(word_assert(11,0,11000+case))
    check_byte("n2_fixup_count",128)
    check_byte("n2_fixup_count+1",2)

    # Actual relative_byte() from ass.c: return a signed -1 for distances
    # outside [-128,127], otherwise the 8-bit wrapped displacement.
    for target,base in (
        (0,0),(1,0),(127,0),(128,0),(129,0),
        (65535,0),(65408,0),(65407,0),(65534,0),
        (0,1),(0,128),(0,129),(0,65535),
        (0x1234,0x1200),(0x1200,0x1234),
        (0x0000,0xff80),(0x0000,0xff7f),
        (0x7fff,0x8000),(0x8000,0x7fff)
    ):
        put_word("n2_relative_byte_target",target)
        put_word("n2_relative_byte_base",base)
        d=(target-base)&65535
        if d<=127:
            expected=d
        elif d>=65408:
            expected=d&255
        else:
            expected=65535
        lines.extend((
            "\tlda #$%02x"%(case&255),
            "\tsta $03",
            "\tjsr n2_relative_byte",
        ))
        lines.extend(word_assert(expected&255,(expected>>8)&255,
                                 12000+case))
        case+=1
    return lines

def run_ass_wide_tests(driver):
    source=ASS_SOURCE[:ASS_SOURCE.index("char upper_char(")]
    source+="\n".join(ass_function(name) for name in (
        "upper_char","same_text","apply_byte_prefix","hex_nibble",
        "append_fixup","relative_byte"))
    run_native("ass_wide_index",source,ass_wide_test(),driver)
