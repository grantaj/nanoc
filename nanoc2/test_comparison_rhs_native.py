#!/usr/bin/env python3
"""Native correctness of Phase-1 pure arithmetic on comparison RHS."""
from test_native import ROOT, run_native, word_assert

SOURCE = (ROOT / "tests" / "nanoc2" / "comparison-rhs.c").read_text()

def rhs_test():
    lines = ["\t* = $1000", "main:"]
    count = 0

    def exercise(name, parameters, expected):
        nonlocal count
        for parameter, value, width in parameters:
            lines.extend(("\tlda #$%02x" % (value & 255),
                          "\tsta n2_%s_%s" % (name, parameter)))
            if width == 2:
                lines.extend(("\tlda #$%02x" % ((value >> 8) & 255),
                              "\tsta n2_%s_%s+1" % (name, parameter)))
        lines.append("\tjsr n2_%s" % name)
        lines.extend(word_assert(int(expected), 0, 53000+count))
        count += 1

    operations = (("lt", lambda a,b:a<b), ("le", lambda a,b:a<=b),
                  ("gt", lambda a,b:a>b), ("ge", lambda a,b:a>=b),
                  ("eq", lambda a,b:a==b), ("ne", lambda a,b:a!=b))
    for suffix,compare in operations:
        for value,limit in ((0,0),(0,1),(1,2),(254,255),
                            (255,255),(127,128),(0,255)):
            exercise("rhs_"+suffix,(("value",value,1),("limit",limit,1)),
                     compare(value,limit-1))

    def signed16(value):
        value &= 65535
        return value if value<32768 else value-65536
    for value,limit in ((0,0),(65535,0),(0,1),(32767,32767),
                        (32768,0),(32768,32769),(255,256)):
        exercise("rhs_signed",(("value",value,2),("limit",limit,2)),
                 signed16(value)<signed16(limit-1))
        exercise("rhs_unsigned",(("value",value,2),("limit",limit,2)),
                 value<((limit-1)&65535))

    for limit in (0,1,255,256,257,32767):
        exercise("rhs_literal",(("limit",limit,2),),
                 255<signed16(limit-1))
    for value,limit,offset in ((0,0,1),(0,1,1),(1,3,1),
                               (255,255,0),(0,255,255),(254,254,1)):
        exercise("rhs_chain",(("value",value,1),("limit",limit,1),
                              ("offset",offset,1)),
                 value<limit-offset+1)
    return lines

def run_rhs_tests(driver):
    run_native("comparison_rhs",SOURCE,rhs_test(),driver)
