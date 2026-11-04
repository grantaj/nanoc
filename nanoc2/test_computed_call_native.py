#!/usr/bin/env python3
"""Native correctness of computed Phase-1 C arguments staged before JSR."""
from test_native import ROOT,run_native,word_assert

def computed_call_test():
    lines=["\t* = $1000","main:"]
    check=0
    tests=((0,0),(1,2),(255,1),(256,255),
           (0x7fff,1),(0x8000,1),(0xffff,1),
           (0xffff,0x8000),(0x1234,0x4321),
           (0x8001,0xff01),(0x0100,0xff00))
    for a,b in tests:
        for name in ("computed_call","two_computed",
                     "wrapped_args","mixed_args"):
            av=a&65535
            bv=b&255 if name=="mixed_args" else b&65535
            lines.extend((
                "\tlda #$%02x"%(av&255),
                "\tsta n2_%s_a"%name,
                "\tlda #$%02x"%((av>>8)&255),
                "\tsta n2_%s_a+1"%name,
                "\tlda #$%02x"%(bv&255),
                "\tsta n2_%s_b"%name,
            ))
            if name!="mixed_args":
                lines.extend((
                    "\tlda #$%02x"%((bv>>8)&255),
                    "\tsta n2_%s_b+1"%name,
                ))
            if name=="computed_call":
                expected=(av + av + bv + 1)&65535
            elif name=="two_computed":
                expected=(2*bv)&65535
            elif name=="wrapped_args":
                expected=(av - 1 + bv + 1)&65535
            else:
                expected=(av+bv+av-bv+257)&65535
            lines.append("\tjsr n2_%s"%name)
            lines.extend(word_assert(expected&255,(expected>>8)&255,
                                     17000+check))
            check+=1
    return lines

def run_computed_call_tests(driver):
    source=(ROOT/"tests"/"nanoc2"/"computed-call.c").read_text()
    run_native("computed_call",source,computed_call_test(),driver)
