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
    return lines

def run_ass_wide_tests(driver):
    source=ASS_SOURCE[:ASS_SOURCE.index("char upper_char(")]
    source+="\n".join(ass_function(name) for name in (
        "upper_char","same_text","apply_byte_prefix","hex_nibble",
        "append_fixup"))
    import subprocess
    output=subprocess.run([str(driver),"native"],input=source.encode(),
                          capture_output=True,check=True)
    asm=output.stdout.decode()
    entry=asm.rfind("__c")
    import re
    labels=re.findall(r"^__c[0-9A-Fa-f]{2}:$",asm,re.M)
    assert labels
    start=asm.index(labels[-1]+"\n")
    print("ASS_APPEND_NATIVE_LISTING\n"+asm[start:start+12000],flush=True)
    print("ASS_ARRAY_HOMES\n"+"\n".join(
        x for x in asm.splitlines() if x.startswith(("n2_fixup_kind ",
           "n2_fixup_stage ","n2_fixup_count ","n2_append_fixup_kind ",
           "__tptr00 ","n2_fixup_prefix "))),flush=True)
    run_native("ass_wide_index",source,ass_wide_test(),driver)
