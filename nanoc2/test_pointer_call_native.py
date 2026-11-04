#!/usr/bin/env python3
"""Verify original Nano C static pointer-argument ABI on a live 6510."""
from test_native import ROOT,run_native,word_assert

def pointer_call_test():
    lines=["\t* = $1000","main:"]
    cases=((0x3000,0,0x11),(0x30fe,0,0x4a),
           (0x30fe,1,0xbc),(0x30fe,2,0xff),
           (0x3ffe,1,0x00),(0x3ffe,2,0x7f))
    n=0
    for addr,offset,value in cases:
        lines.extend((
            "\tlda #$%02x"%value,
            "\tsta $%04x"%((addr+offset)&65535),
        ))
        for name,indexed in (("forwarding_pointer",False),
                             ("forwarding_pointer_index",True)):
            if not indexed and offset!=0:
                continue
            lines.extend((
                "\tlda #$%02x"%(addr&255),
                "\tsta n2_%s_data"%name,
                "\tlda #$%02x"%((addr>>8)&255),
                "\tsta n2_%s_data+1"%name,
            ))
            if indexed:
                lines.extend((
                    "\tlda #$%02x"%offset,
                    "\tsta n2_%s_offset"%name,
                ))
            lines.append("\tjsr n2_"+name)
            lines.extend(word_assert(value,0,33000+n))
            n+=1
    return lines

def run_pointer_call_tests(driver):
    source=(ROOT/"tests"/"nanoc2"/"pointer-call.c").read_text()
    run_native("pointer_call",source,pointer_call_test(),driver)
