#!/usr/bin/env python3
"""Small native-6510 ABI smoke for the single original-parser nanoc2 path.

Compiles exact Phase-1 C functions with the existing semantic parser, emits
native static Nano C homes and a pointer prologue, assembles the *actual*
emitted 6502 with vasm and executes it in VICE. No manual ZP pointer setup.
This is deliberately separate from the fast host/interpreter test suite.
"""
import os
import pathlib
import re
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "build" / "nanoc2-native"
OUT.mkdir(parents=True, exist_ok=True)
CC = os.environ.get("CC", "cc")
VASM = os.environ.get("VASM", "vasm6502_oldstyle")
SOURCE = (ROOT / "nanoc1" / "nanoc1.c").read_text()
ASS_SOURCE = (ROOT / "bootstrap" / "ass.c").read_text()
WRITE_FIXTURE = (ROOT / "tests" / "nanoc2" / "indexed-write.c").read_text()


def original_function(name):
    match = re.search(r"^char\s+" + re.escape(name) + r"\s*\([^)]*\)\s*\{",
                      SOURCE, re.M)
    assert match, name
    n, p = 1, match.end()
    while n:
        n += (SOURCE[p] == "{") - (SOURCE[p] == "}")
        p += 1
    return SOURCE[match.start():p]



def ass_function(name):
    """Extract a verbatim function from the actual Phase-1 assembler."""
    m = re.search(r"^(?:char|int|unsigned)\s+"+re.escape(name)+
                  r"\s*\([^)]*\)\s*\{",ASS_SOURCE,re.M)
    assert m,name
    depth=1
    end=m.end()
    while depth:
        depth += (ASS_SOURCE[end]=="{")-(ASS_SOURCE[end]=="}")
        end += 1
    return ASS_SOURCE[m.start():end]


def ass_global(name):
    """Extract a verbatim initialized global declaration from ass.c."""
    m = re.search(r"^(?:char|int|unsigned)\s+"+re.escape(name)+
                  r"(?:\[\d+\])?\s*=\s*[^;]+;",
                  ASS_SOURCE,re.M)
    assert m,name
    return m.group()


def fixture_function(name):
    match = re.search(r"^char\s+" + re.escape(name) + r"\s*\([^)]*\)\s*\{",
                      WRITE_FIXTURE, re.M)
    assert match, name
    n, p = 1, match.end()
    while n:
        n += (WRITE_FIXTURE[p] == "{") - (WRITE_FIXTURE[p] == "}")
        p += 1
    return WRITE_FIXTURE[match.start():p]


def globals_for_find():
    names = ("global_name", "global_name_len", "token_text",
             "token_length", "global_count")
    defs = []
    for name in names:
        match = re.search(r"^char\s+" + name +
                          r"(?:\[\d+\])?\s*;", SOURCE, re.M)
        assert match, name
        defs.append(match.group())
    return "\n".join(defs) + "\n"


def check_call(expected, check):
    # Both registers in Nano C's existing byte-return ABI are verified.
    return [
        "\tjsr $0800",
        "\tcmp #$%02x" % expected,
        "\tbeq .a%02x" % check,
        "\tjmp native_fail",
        ".a%02x:" % check,
        "\tcpx #$00",
        "\tbeq .x%02x" % check,
        "\tjmp native_fail",
        ".x%02x:" % check,
    ]


def same_bytes_test():
    lines = [
        "\t* = $1000", "main:",
        # This is how an ordinary Nano C caller stages pointer parameters.
        # The compiler itself copies these two-byte homes to ZP at entry.
        "\tlda #<$300f", "\tsta n2_a",
        "\tlda #>$300f", "\tsta n2_a+1",
        "\tlda #<$31f9", "\tsta n2_b",
        "\tlda #>$31f9", "\tsta n2_b+1",
        "\tlda #$c8", "\tsta n2_a_length", "\tsta n2_b_length",
        "\tlda #$a5", "\tldx #$00",
        ".fill:", "\tsta $300f,x", "\tsta $31f9,x",
        "\tinx", "\tcpx #$c8", "\tbne .fill",
    ]
    lines += check_call(1, 0)
    lines += [
        "\tlda #$a4", "\tsta $31f9+199",
    ]
    lines += check_call(0, 1)
    lines += [
        "\tlda #$a5", "\tsta $31f9+199",
        "\tlda #$c7", "\tsta n2_b_length",
    ]
    lines += check_call(0, 2)
    lines += [
        "\tlda #$00", "\tsta n2_a_length", "\tsta n2_b_length",
    ]
    lines += check_call(1, 3)
    return lines


def find_global_test():
    # Exercise the 32-byte record scaling, 16-bit pointer carry, nested
    # comparison, 175th record and early mismatch. Every length relevant
    # to the search is explicitly initialized, not assumed zero-filled.
    lines = [
        "\t* = $1000", "main:",
        "\tlda #$00", "\tldy #$00",
        ".zero:", "\tsta n2_global_name_len,y",
        "\tiny", "\tcpy #$b0", "\tbne .zero",
        "\tlda #$b0", "\tsta n2_global_count",
        "\tlda #$03", "\tsta n2_token_length",
        "\tlda #$41", "\tsta n2_token_text",
        "\tlda #$42", "\tsta n2_token_text+1",
        "\tlda #$43", "\tsta n2_token_text+2",
        "\tlda #$03", "\tsta n2_global_name_len+175",
        "\tlda #$41", "\tsta n2_global_name+5600",
        "\tlda #$42", "\tsta n2_global_name+5601",
        "\tlda #$43", "\tsta n2_global_name+5602",
    ]
    lines += check_call(175, 0)
    lines += [
        "\tlda #$44", "\tsta n2_token_text+2",
    ]
    lines += check_call(255, 1)
    lines += [
        "\tlda #$43", "\tsta n2_token_text+2",
        "\tlda #$00", "\tsta n2_global_name_len+175",
        "\tlda #$03", "\tsta n2_global_name_len",
        "\tlda #$41", "\tsta n2_global_name",
        "\tlda #$42", "\tsta n2_global_name+1",
        "\tlda #$43", "\tsta n2_global_name+2",
    ]
    lines += check_call(0, 2)
    return lines


def copy_pointer_test():
    lines = [
        "\t* = $1000", "main:",
        "\tlda #<$31f9", "\tsta n2_dst",
        "\tlda #>$31f9", "\tsta n2_dst+1",
        "\tlda #<$300f", "\tsta n2_src",
        "\tlda #>$300f", "\tsta n2_src+1",
        "\tlda #$c8", "\tsta n2_n",
        "\tldx #$00",
        ".prepare:",
        "\ttxa", "\tsta $300f,x",
        "\tlda #$00", "\tsta $31f9,x",
        "\tinx", "\tcpx #$c8", "\tbne .prepare",
    ]
    lines += check_call(200, 0)
    lines += [
        "\tldx #$00",
        ".verify:", "\tlda $300f,x",
        "\tcmp $31f9,x",
        "\tbeq .matching",
        "\tjmp native_fail",
        ".matching:", "\tinx",
        "\tcpx #$c8", "\tbne .verify",
    ]
    return lines


def copy_array_test():
    lines = [
        "\t* = $1000", "main:",
        "\tlda #$c8", "\tsta n2_n",
        "\tldx #$00",
        ".prepare:", "\ttxa", "\tsta n2_source_bytes,x",
        "\tlda #$00", "\tsta n2_dest_bytes,x",
        "\tinx", "\tcpx #$c8", "\tbne .prepare",
    ]
    lines += check_call(200, 0)
    lines += [
        "\tldx #$00",
        ".verify:", "\tlda n2_source_bytes,x",
        "\tcmp n2_dest_bytes,x",
        "\tbeq .matching",
        "\tjmp native_fail",
        ".matching:", "\tinx",
        "\tcpx #$c8", "\tbne .verify",
    ]
    return lines


def multi_function_test():
    # Two functions share the same Phase-1 static ABI but have distinct
    # parameter slots and independent X/Y/zero-page traversal decisions.
    lines = [
        "\t* = $1000", "main:",
        "\tcli",  # explicitly exercise C64 IRQs during repeated pointer loops
        "\tlda #<$31f9", "\tsta n2_fill_bytes_dst",
        "\tlda #>$31f9", "\tsta n2_fill_bytes_dst+1",
        "\tlda #$c8", "\tsta n2_fill_bytes_n",
        "\tlda #$5a", "\tsta n2_fill_bytes_value",
    ]
    lines += ["\tlda #$41", "\tsta $03"]
    lines += check_call(200,0)  # first function uses $0800 jump wrapper
    lines += [
        "\tlda #$42", "\tsta $03",
        "\tldx #$00", ".fill_verify:",
        "\tlda $31f9,x", "\tcmp #$5a",
        "\tbeq .fill_good", "\tjmp native_fail",
        ".fill_good:", "\tinx", "\tcpx #$c8", "\tbne .fill_verify",
        "\tlda #<$31f9", "\tsta n2_copy_bytes_dst",
        "\tlda #>$31f9", "\tsta n2_copy_bytes_dst+1",
        "\tlda #<$300f", "\tsta n2_copy_bytes_src",
        "\tlda #>$300f", "\tsta n2_copy_bytes_src+1",
        "\tlda #$c8", "\tsta n2_copy_bytes_n",
        "\tldx #$00", ".source_prepare:",
        "\ttxa", "\tsta $300f,x",
        "\tinx", "\tcpx #$c8", "\tbne .source_prepare",
        "\tlda #$43", "\tsta $03",
        "\tjsr n2_copy_bytes",
        "\tcmp #$c8", "\tbeq .return_a",
        "\tjmp native_fail",
        ".return_a:", "\tcpx #$00", "\tbeq .return_x",
        "\tjmp native_fail",
        ".return_x:", "\tlda #$44", "\tsta $03",
        "\tldx #$00", ".copy_verify:",
        "\tlda $300f,x", "\tcmp $31f9,x",
        "\tbeq .copy_good", "\tjmp native_fail",
        ".copy_good:", "\tinx", "\tcpx #$c8", "\tbne .copy_verify",
    ]
    return lines

def call_index_test():
    # The original C caller drives a helper from inside an X-indexed loop.
    # Callee must not destroy the caller's logical induction variable,
    # even though its return convention clobbers physical X.
    lines = [
        "\t* = $1000", "main:",
        "\tldx #$00",
        ".prepare:",
        "\ttxa", "\teor #$5a",
        "\tsta n2_call_source,x",
        "\tlda #$00", "\tsta n2_call_dest,x",
        "\tinx", "\tcpx #$c8", "\tbne .prepare",
    ]
    lines += check_call(200, 0)
    lines += [
        "\tldx #$00",
        ".verify:",
        "\tlda #$22",
        "\tcpx #$5a", "\tbne .expected",
        "\tlda #$11",
        ".expected:",
        "\tcmp n2_call_dest,x",
        "\tbeq .matching",
        "\tjmp native_fail",
        ".matching:",
        "\tinx", "\tcpx #$c8", "\tbne .verify",
    ]
    return lines


def call_arity_test():
    # Exercise zero- and two-argument byte calls, including two static
    # callee argument slots and a call with X live inside the outer loop.
    lines = [
        "\t* = $1000", "main:",
        "\tldx #$00",
        ".prepare:",
        "\ttxa", "\teor #$5a",
        "\tsta n2_call_source,x",
        "\tlda #$00", "\tsta n2_call_dest,x",
        "\tinx", "\tcpx #$c8", "\tbne .prepare",
    ]
    lines += check_call(90, 0)
    lines += [
        "\tldx #$00",
        ".verify:",
        "\tlda n2_call_source,x",
        "\tcmp n2_call_dest,x",
        "\tbeq .matching",
        "\tjmp native_fail",
        ".matching:",
        "\tinx", "\tcpx #$c8", "\tbne .verify",
        # The wrong second parameter must force the non-identity path.
        "\tlda #$ac", "\tsta n2_guarded_value",
        "\tlda #$01", "\tsta n2_guarded_sentinel",
        "\tjsr n2_guarded",
        "\tcmp #$00", "\tbeq .guard_a",
        "\tjmp native_fail",
        ".guard_a:", "\tcpx #$00", "\tbeq .guard_x",
        "\tjmp native_fail",
        ".guard_x:",
    ]
    return lines


def word_assert(low, high, number):
    return [
        "\tcmp #$%02x" % low,
        "\tbeq .word_a%02x" % number,
        "\tjmp native_fail",
        ".word_a%02x:" % number,
        "\tcpx #$%02x" % high,
        "\tbeq .word_x%02x" % number,
        "\tjmp native_fail",
        ".word_x%02x:" % number,
    ]


def word_scalar_test():
    lines = ["\t* = $1000", "main:", "\tjsr $0800"]
    lines += word_assert(0x34,0x12,0)
    lines += [
        "\tlda n2_target",
        "\tcmp #$34", "\tbeq .target_lo",
        "\tjmp native_fail",
        ".target_lo:",
        "\tlda n2_target+1",
        "\tcmp #$12", "\tbeq .target_hi",
        "\tjmp native_fail",
        ".target_hi:",
        "\tjsr n2_constant_word",
    ]
    lines += word_assert(0x34,0x12,1)
    lines += [
        "\tlda #$cd", "\tsta n2_echo_word_value",
        "\tlda #$ab", "\tsta n2_echo_word_value+1",
        "\tjsr n2_echo_word",
    ]
    lines += word_assert(0xcd,0xab,2)
    lines += [
        "\tlda #$fe", "\tsta n2_add_word_value",
        "\tlda #$00", "\tsta n2_add_word_value+1",
        "\tjsr n2_add_word",
    ]
    lines += word_assert(0xfe,0x01,3)  # $00fe + $00ff + 1
    lines += [
        "\tlda #$ff", "\tsta n2_add_word_value",
        "\tsta n2_add_word_value+1",
        "\tjsr n2_add_word",
    ]
    lines += word_assert(0xff,0x00,4)  # $ffff wraps to $00ff
    lines += [
        "\tlda #$00", "\tsta n2_subtract_word_value",
        "\tlda #$01", "\tsta n2_subtract_word_value+1",
        "\tjsr n2_subtract_word",
    ]
    lines += word_assert(0xfe,0xff,5)  # $0100 - $0101 - 1
    return lines



def word_ops_test():
    # This fixture deliberately includes signed and unsigned 16-bit values
    # around $7fff/$8000 and byte carry/borrow boundaries. Directly drive
    # the original static ABI with an independently assembled 6510 caller.
    lines = ["\t* = $1000", "main:"]
    case = 0

    def call(name, left, right, answer):
        nonlocal case
        lines.extend([
            "\tlda #$%02x" % (left & 255),
            "\tsta n2_%s_left" % name,
            "\tlda #$%02x" % ((left >> 8) & 255),
            "\tsta n2_%s_left+1" % name,
        ])
        if right is not None:
            lines.extend([
                "\tlda #$%02x" % (right & 255),
                "\tsta n2_%s_right" % name,
                "\tlda #$%02x" % ((right >> 8) & 255),
                "\tsta n2_%s_right+1" % name,
            ])
        lines.append("\tjsr n2_%s" % name)
        lines.extend(word_assert(answer & 255, (answer >> 8) & 255, 1000+case))
        case += 1

    arith = [
        (0, 0), (0xff, 1), (0x100, 1), (0, 1),
        (0xffff, 1), (0x8000, 0x7fff), (0x1234, 0x0234),
    ]
    for left, right in arith:
        for name in ("sum_word", "inplace_sum_left", "inplace_sum_right", "return_sum"):
            call(name, left, right, (left+right) & 65535)
        for name in ("diff_word", "inplace_diff_left", "inplace_diff_right", "return_diff"):
            call(name, left, right, (left-right) & 65535)

    ordered = [
        (0, 0), (0, 1), (1, 0), (0xff, 0x100),
        (0x100, 0xff), (0x7fff, 0x8000), (0x8000, 0x7fff),
        (0xffff, 0), (0, 0xffff), (0x8000, 0xffff),
    ]
    relations = (
        ("lt", lambda a,b: a < b), ("le", lambda a,b: a <= b),
        ("gt", lambda a,b: a > b), ("ge", lambda a,b: a >= b),
        ("eq", lambda a,b: a == b), ("ne", lambda a,b: a != b),
    )
    for a, b in ordered:
        signed_a = a if a < 0x8000 else a-0x10000
        signed_b = b if b < 0x8000 else b-0x10000
        for suffix, compare in relations:
            call("signed_"+suffix, a, b, int(compare(signed_a, signed_b)))
            call("unsigned_"+suffix, a, b, int(compare(a, b)))
        call("mixed_gt", a, b, int(a > b))
    for left in (0, 1, 255, 256, 32767, 32768, 65535):
        signed_left = left if left < 32768 else left-65536
        call("signed_const_lt", left, None, int(signed_left < 256))
        call("unsigned_const_gt", left, None, int(left > 32768))
        call("word_truth", left, None, int(left != 0))
    for left in (0, 1, 255, 256):
        call("word_count", left, None, left)
    return lines



def word_call_test():
    lines = ["\t* = $1000", "main:", "\tjsr $0800"]
    lines += word_assert(0x34, 0x12, 3000)
    calls = [
        ("pass_one", (("value", 0xabcd, 2),), 0xabcd),
        ("add_pair", (("left", 0xffff, 2), ("right", 1, 2)), 0),
        ("add_pair", (("left", 0x7fff, 2), ("right", 1, 2)), 0x8000),
        ("word_relay", (("value", 0xabcd, 2),), 0xabcd),
        ("pair_relay", (("left", 0x00ff, 2), ("right", 1, 2)), 0x100),
        ("pair_relay", (("left", 0xffff, 2), ("right", 1, 2)), 0),
        ("const_pair", (), 4661),
        ("echo_byte", (("value", 0x84, 1),), 0x84),
        ("byte_to_word", (("value", 0x84, 1),), 0x84),
        ("word_to_byte", (("value", 0x12ab, 2),), 0xab),
        ("byte_to_word_store", (("value", 0x12ab, 2),), 0xab),
        ("mixed_pair", (("left", 0xabcd, 2), ("tag", 0x91, 1)), 0xabcd),
        ("mixed_relay", (("left", 0xabcd, 2), ("tag", 0x91, 1)), 0xabcd),
        ("indexed_word_call", (("i", 0x02, 1),), 4660),
    ]
    for num, (name, arguments, expected) in enumerate(calls):
        for arg, value, size in arguments:
            lines.extend([
                "\tlda #$%02x" % (value & 255),
                "\tsta n2_%s_%s" % (name, arg),
            ])
            if size == 2:
                lines.extend([
                    "\tlda #$%02x" % ((value >> 8) & 255),
                    "\tsta n2_%s_%s+1" % (name, arg),
                ])
        lines.append("\tjsr n2_%s" % name)
        lines.extend(word_assert(expected & 255, expected >> 8, 3001+num))
    for i in range(3):
        lines.extend([
            "\tlda n2_out_bytes+%d" % i,
            "\tcmp #$%02x" % i,
            "\tbeq .array_ok_%d" % i,
            "\tjmp native_fail",
            ".array_ok_%d:" % i,
        ])
    return lines


def mixed_arithmetic_test():
    lines = ["\t* = $1000", "main:"]
    case = 0

    def exercise(name, args, expected):
        nonlocal case
        for slot, value, size in args:
            lines.extend([
                "\tlda #$%02x" % (value & 255),
                "\tsta n2_%s_%s" % (name, slot),
            ])
            if size == 2:
                lines.extend([
                    "\tlda #$%02x" % ((value >> 8) & 255),
                    "\tsta n2_%s_%s+1" % (name, slot),
                ])
        lines.append("\tjsr n2_%s" % name)
        lines.extend(word_assert(expected & 255, (expected >> 8) & 255,
                                 4000 + case))
        case += 1

    pairs = [
        (0, 0), (255, 1), (256, 255), (65535, 1),
        (32767, 255), (32768, 1), (0x1234, 0x80),
        (0x0100, 0xff), (0xffff, 0xff),
    ]
    for wide, delta in pairs:
        one_byte = (("small", delta, 1),)
        one_word = (("wide", wide, 2),)
        mixed = (("wide", wide, 2), ("delta", delta, 1))
        exercise("widen_copy", one_byte, delta)
        exercise("narrow_copy", one_word, wide & 255)
        exercise("widen_return", one_byte, delta)
        exercise("narrow_return", one_word, wide & 255)
        exercise("mix_add", mixed, (wide + delta) & 65535)
        exercise("mix_sub", mixed, (wide - delta) & 65535)
        exercise("mix_return", mixed, (wide + delta) & 65535)
        exercise("mix_return_sub", mixed, (wide - delta) & 65535)
        exercise("reverse_mixed",
                 (("delta", delta, 1), ("wide", wide, 2)),
                 (wide + delta) & 65535)
        exercise("reverse_sub",
                 (("delta", delta, 1), ("wide", wide, 2)),
                 (delta - wide) & 65535)
        reverse = (("delta", delta, 1), ("wide", wide, 2))
        exercise("reverse_add_store", reverse, (delta + wide) & 65535)
        exercise("reverse_sub_store", reverse, (delta - wide) & 65535)
        exercise("literal_base", mixed, (1 + wide - delta) & 65535)
        exercise("alias_late", mixed, (2 * wide + delta) & 65535)

    triples = [
        (0, 0, 0), (255, 1, 255), (0xffff, 1, 1),
        (32767, 32768, 255), (0x1234, 0x4321, 0x80),
    ]
    for left, right, offset in triples:
        args = (("left", left, 2), ("right", right, 2),
                ("offset", offset, 1))
        answer = (left + right - offset + 257) & 65535
        exercise("compound", args, answer)
        exercise("compound_return", args, answer)

    for left, right in ((0, 0), (255, 255), (255, 1),
                        (128, 128), (0x70, 0x7f)):
        args = (("left", left, 1), ("right", right, 1))
        expected = left + right + 1
        exercise("byte_chain", args, expected & 255)
        exercise("byte_return", args, expected & 255)
        exercise("byte_sum_word", args, left + right)
        exercise("byte_sum_store", args, left + right)
        exercise("byte_pair_return", args, (left + right) & 255)
        exercise("byte_pair_store", args, (left + right) & 255)
    # The same arithmetic chain must round-trip a live X loop index.
    for bound in (0, 1, 2, 3, 4, 7, 10, 11):
        exercise("fill_even", (("count", bound, 1),),
                 2 * ((bound + 1) // 2))
    for i in (2, 4, 6, 8, 10):
        lines.extend([
            "\tlda n2_out_even+%d" % i,
            "\tcmp #$%02x" % i,
            "\tbeq .even_ok_%d" % i,
            "\tjmp native_fail",
            ".even_ok_%d:" % i,
        ])
    return lines


def mixed_compare_test():
    lines = ["\t* = $1000", "main:"]
    case = 0

    def test(name, args, expected):
        nonlocal case
        for parameter, value, width in args:
            lines.extend([
                "\tlda #$%02x" % (value & 255),
                "\tsta n2_%s_%s" % (name, parameter),
            ])
            if width == 2:
                lines.extend([
                    "\tlda #$%02x" % ((value >> 8) & 255),
                    "\tsta n2_%s_%s+1" % (name, parameter),
                ])
        lines.append("\tjsr n2_%s" % name)
        lines.extend(word_assert(expected & 255, (expected >> 8) & 255,
                                 6000+case))
        case += 1

    comparisons = (
        ("lt", lambda x,y: x<y), ("le", lambda x,y: x<=y),
        ("gt", lambda x,y: x>y), ("ge", lambda x,y: x>=y),
        ("eq", lambda x,y: x==y), ("ne", lambda x,y: x!=y),
    )
    pairs = [
        (0, 0), (0, 255), (255, 255), (256, 255), (256, 0),
        (32767, 255), (32768, 0), (32768, 255),
        (65535, 0), (65535, 255), (0x12ff, 0x34),
    ]
    for word, byte in pairs:
        signed = word if word < 32768 else word-65536
        for suffix, compare in comparisons:
            for prefix, lhs, rhs, unsigned in (
                ("mix", "word", "byte", False),
                ("rev", "byte", "word", False),
                ("umix", "word", "byte", True),
                ("urev", "byte", "word", True),
            ):
                converted_word = word if unsigned else signed
                left = converted_word if lhs=="word" else byte
                right = converted_word if rhs=="word" else byte
                args = ((lhs, word if lhs=="word" else byte,
                         2 if lhs=="word" else 1),
                        (rhs, word if rhs=="word" else byte,
                         2 if rhs=="word" else 1))
                test(prefix+"_"+suffix, args, int(compare(left,right)))
    for byte in (0, 1, 254, 255):
        args = (("byte",byte,1),)
        test("byte_lt_256",args,int(byte < 256))
        test("byte_eq_256",args,int(byte == 256))
        test("literal_gt_byte",args,int(256 > byte))
        test("literal_eq_byte",args,int(255 == byte))
        test("byte_ge_257",args,int(byte >= 257))
    for word in (0, 255, 256, 257, 32767, 32768, 65535):
        signed = word if word < 32768 else word-65536
        test("literal_lt_word",(("word",word,2),),int(256 < signed))
        test("literal_eq_word",(("word",word,2),),int(256 == signed))
        test("literal_gt_unsigned",(("word",word,2),),int(256 > word))
        test("word_lt_byte_literal",(("word",word,2),),int(signed < 255))
    for limit in (0,1,2,16):
        test("mark_below_word",(("limit",limit,2),),limit)
    for i in range(16):
        lines.extend([
            "\tlda n2_compare_marks+%d" % i,
            "\tcmp #$%02x" % i,
            "\tbeq .mixed_mark_%d" % i,
            "\tjmp native_fail",
            ".mixed_mark_%d:" % i,
        ])
    for start,limit in ((0,5),(3,3),(8,3),(65535,2)):
        signed = start if start < 32768 else start-65536
        expect = start if signed>=limit else limit
        test("advance_word_until_byte",
             (("start",start,2),("limit",limit,1)),expect)
    return lines


def expression_condition_test():
    lines = ["\t* = $1000", "main:"]
    case = 0

    def run(name, arguments, expected):
        nonlocal case
        for param, value, width in arguments:
            lines.extend([
                "\tlda #$%02x" % (value & 255),
                "\tsta n2_%s_%s" % (name,param),
            ])
            if width == 2:
                lines.extend([
                    "\tlda #$%02x" % ((value >> 8) & 255),
                    "\tsta n2_%s_%s+1" % (name,param),
                ])
        lines.append("\tjsr n2_%s" % name)
        lines.extend(word_assert(expected & 255,(expected >> 8) & 255,6000+case))
        case += 1

    def signed16(n):
        n = n & 65535
        return n if n < 32768 else n-65536

    triples = [
        (0,0,0), (1,2,3), (0xff,1,0x100), (0xfffe,1,0),
        (0x7fff,0,0x8000), (0x8000,1,0), (0xff00,0x80,0xff80),
    ]
    for left,right,limit in triples:
        value=signed16(left+right)
        args=(("left",left,2),("right",right,2),("limit",limit,2))
        run("expr_less",args,int(value < signed16(limit)))

    for left,offset,limit in [
        (0,0,0), (255,1,255), (0xff00,0x7f,0xff7f),
        (0x7fff,0,0x7fff), (0x8000,1,0x8000),
        (0xffff,1,1), (0x100,0xff,0x200),
    ]:
        args=(("left",left,2),("offset",offset,1),("limit",limit,2))
        run("expr_ge_byte",args,int(signed16(left+offset)>=signed16(limit)))

    for left in (0,1,254,255,256,65534,65535):
        for offset in (0,1,255):
            val=(left+offset+1)&65535
            run("expr_chain_equal",(("left",left,2),("offset",offset,1)),
                int(val==256))

    for value in (0,1,2,127,128,254,255):
        run("expr_chain_truth",(("value",value,1),),1)

    for left,right in ((0,0),(0,1),(1,0),(255,255),
                       (0xff00,0xff00),(0x8000,0xffff)):
        run("expr_difference_truth",
            (("left",left,2),("right",right,2)),int(left!=right))

    for offset,left,limit in [
        (0,0,0),(1,0,1),(255,1,256),(0,65535,0),
        (1,65535,1),(127,100,227),(255,256,511),
    ]:
        val=(offset+left)&65535
        run("expr_reversed_byte",
            (("offset",offset,1),("left",left,2),("limit",limit,2)),
            int(val<limit))

    for left,offset,limit in [
        (0,0,0),(0,1,1),(255,1,0),(255,1,255),
        (0xff00,0,0),(65535,1,0),(3,255,255),
    ]:
        val=(left+offset)&65535
        run("expr_compare_byte",
            (("left",left,2),("offset",offset,1),("limit",limit,1)),
            int(val<=limit))

    for value in (1,2,3,5,10):
        run("expr_count_down",(("value",value,2),),value-1)

    for limit in (0,1,2,3,6,12):
        run("expr_index_until",(("limit",limit,1),),max(0,limit-1))
    for index in (0,1,2,3,4,5,6,7,8,9,10):
        lines.extend([
            "\tlda n2_expr_marks+%d" % index,
            "\tcmp #$%02x" % index,
            "\tbeq .expr_index_%d" % index,
            "\tjmp native_fail",
            ".expr_index_%d:" % index,
        ])
    return lines

def run_native(name, source, test_lines, driver):
    output = subprocess.run([str(driver), "native"], input=source.encode(),
                            capture_output=True)
    if output.returncode:
        raise AssertionError("%s native compiler rejected source (exit %d): %s" %
                             (name,output.returncode,
                              output.stderr.decode(errors="replace")))
    asm = output.stdout.decode()
    assert "__nc_start:" in asm and "NC_BSS = $4800" in asm
    assert "sta __tptr" in asm if name == "same_bytes" else "__tptr" in asm
    # Checking source rather than a handcrafted generated instruction listing.
    # Local declarations and global array homes are in the same source stream.
    harness = list(test_lines)
    harness += [
        "\tjmp success",
        "native_fail:", "\tlda $03" if name in ("two_functions","ass_wide_index","ass_resolve","pointer_call") else "\tlda #$40",
        "\tsta $02",
        ".halt:", "\tjmp .halt",
        "success:", "\tlda #$ff", "\tsta $02",
        ".halt:", "\tjmp .halt",
        "",
    ]
    # vasm treats separate "* = $0200" and "* = $0800" origins as
    # independent segments. The normal project test pattern is therefore
    # two PRGs, with the code PRG preloaded at $0800. Callers use $1000, not the
    # IRQ-owned keyboard-buffer/system-variable RAM at $0200-$02ff.
    generated_source = OUT / (name + "-generated.asm")
    generated_source.write_text(asm)
    code_prg = OUT / (name + "-generated.prg")
    subprocess.run([VASM, "-Fbin", "-cbm-prg", "-o", str(code_prg),
                    str(generated_source)], cwd=ROOT, check=True)
    code = code_prg.read_bytes()
    assert code[:2] == b"\x00\x08", (name, code[:2])
    # The independent 6502 caller must not overlap an increasingly large
    # generated ass.c prefix. The VICE test runner starts from the caller
    # PRG's load address, so use the first safe 4 KiB boundary and keep
    # all test code below the original Nano C global BSS at $4800.
    code_end = 0x0800 + len(code) - 2
    caller_origin = 0x1000
    while caller_origin <= code_end:
        caller_origin += 0x1000
    assert caller_origin < 0x4000, (name, code_end)
    assert harness[0] == "\t* = $1000", name
    harness[0] = "\t* = $%04x" % caller_origin

    # Symbol-only equates from the exact generated compiler output can be
    # shared by the independently assembled native caller. No duplicated
    # parameter/array offsets are hardcoded in the test.
    symbols = []
    function_aliases = []
    for line in asm.splitlines():
        # Function aliases depend on labels defined in the *other* PRG.
        # Resolve their physical addresses with vasm rather than forwarding
        # an undefined __cXX symbol into the separately assembled caller.
        if re.match(r'^n2_\w+\s*=\s*__(?:c|g)[0-9A-Fa-f]{2}\s*$', line):
            function_aliases.append(line.split('=')[0].strip())
        elif re.match(r'^(?:NC_BSS|__tptr\w*|__tw\w*|__g\w*|__v\w*|n2_\w+)\s*=', line):
            symbols.append(line)
    if function_aliases:
        aliases_asm = asm + "\n\tword " + ", ".join(function_aliases) + "\n"
        aliases_src = OUT / (name + "-addresses.asm")
        aliases_src.write_text(aliases_asm)
        aliases_prg = OUT / (name + "-addresses.prg")
        subprocess.run([VASM, "-Fbin", "-cbm-prg", "-o", str(aliases_prg),
                        str(aliases_src)], cwd=ROOT, check=True)
        resolved = aliases_prg.read_bytes()[-2*len(function_aliases):]
        for index, alias in enumerate(function_aliases):
            address = resolved[2*index] | resolved[2*index+1]<<8
            symbols.append("%s = $%04X" % (alias,address))
    assert any(line.startswith("n2_") for line in symbols)
    asm_path = OUT / (name + "-caller.asm")
    asm_path.write_text("\n".join(harness) + "\n" +
                        "\n".join(symbols) + "\n")
    prg = OUT / (name + "-caller.prg")
    subprocess.run([VASM, "-Fbin", "-cbm-prg", "-o", str(prg),
                    str(asm_path)], cwd=ROOT, check=True)
    raw = prg.read_bytes()
    assert raw[:2] == caller_origin.to_bytes(2,"little"), (name,raw[:2])
    assert caller_origin + len(raw)-2 < 0x4800, (name,"caller meets BSS")
    env = os.environ.copy()
    env["BUILD_DIR"] = str(OUT)
    env["VICE_TIMEOUT"] = "35"
    env["VICE_PRELOAD_PRG"] = str(code_prg)
    subprocess.run(["sh", "tests/run-test.sh", str(prg),
                    "nanoc2-" + name], cwd=ROOT, env=env, check=True)
    print("%s: generated %d-byte native program, %d-byte caller; "
          "ABI, results and memory checks passed" %
          (name, len(code)-2, len(raw)-2))


def main():
    driver = OUT / "native-compiler"
    subprocess.run([CC, "-std=c99", "-funsigned-char", "-O0",
                    str(ROOT / "nanoc2" / "parser_tape_driver.c"),
                    "-o", str(driver)], cwd=ROOT, check=True)
    run_native("same_bytes", original_function("same_bytes"),
               same_bytes_test(), driver)
    run_native("find_global", globals_for_find() +
               original_function("find_global"),
               find_global_test(), driver)
    run_native("copy_pointer", fixture_function("copy_pointer"),
               copy_pointer_test(), driver)
    run_native("copy_array", "char source_bytes[256];\n" +
               "char dest_bytes[256];\n" + fixture_function("copy_array"),
               copy_array_test(), driver)
    call_source = (ROOT / "tests" / "nanoc2" / "call-index.c").read_text()
    run_native("call_index", call_source, call_index_test(), driver)
    arity_source = (ROOT / "tests" / "nanoc2" / "call-arity.c").read_text()
    run_native("call_arity", arity_source, call_arity_test(), driver)
    word_source = (ROOT / "tests" / "nanoc2" / "word-scalar.c").read_text()
    run_native("word_scalar", word_source, word_scalar_test(), driver)
    word_ops_source = (ROOT / "tests" / "nanoc2" / "word-ops.c").read_text()
    run_native("word_ops", word_ops_source, word_ops_test(), driver)
    word_call_source = (ROOT / "tests" / "nanoc2" / "word-call.c").read_text()
    run_native("word_call", word_call_source, word_call_test(), driver)
    mixed_source = (ROOT / "tests" / "nanoc2" / "mixed-arithmetic.c").read_text()
    run_native("mixed_arithmetic", mixed_source, mixed_arithmetic_test(), driver)
    compare_source = (ROOT / "tests" / "nanoc2" / "mixed-compare.c").read_text()
    run_native("mixed_compare", compare_source, mixed_compare_test(), driver)
    expr_source = (ROOT / "tests" / "nanoc2" / "expression-condition.c").read_text()
    run_native("expression_condition", expr_source, expression_condition_test(), driver)
    # Actual Phase-1 assembler, with unmodified functions and data.
    from test_ass_native import run_ass_tests
    run_ass_tests(driver)
    from test_ass_wide_native import run_ass_wide_tests
    run_ass_wide_tests(driver)
    from test_ass_resolve_native import run_resolve_tests
    run_resolve_tests(driver)
    from test_ass_allocate_native import run_allocation_tests
    run_allocation_tests(driver)
    from test_ass_symbol_api_native import run_symbol_api_tests
    run_symbol_api_tests(driver)
    from test_ass_patch_native import run_patch_tests
    run_patch_tests(driver)
    from test_ass_define_native import run_define_label_tests
    run_define_label_tests(driver)
    from test_ass_atom_native import run_ass_atom_tests
    run_ass_atom_tests(driver)
    from test_ass_value_native import run_ass_value_tests
    run_ass_value_tests(driver)
    from test_computed_call_native import run_computed_call_tests
    run_computed_call_tests(driver)
    from test_word_array_native import run_word_array_tests
    run_word_array_tests(driver)
    from test_pointer_call_native import run_pointer_call_tests
    run_pointer_call_tests(driver)
    # One source unit, two real Phase-1 definitions. The parser must emit
    # each bounded function tape before it is reset for the next function.
    multi_source = (
        fixture_function("fill_pointer").replace("fill_pointer", "fill_bytes")
        + "\n"
        + fixture_function("copy_pointer").replace("copy_pointer", "copy_bytes")
        + "\n"
    )
    run_native("two_functions", multi_source, multi_function_test(), driver)


if __name__ == "__main__":
    main()
