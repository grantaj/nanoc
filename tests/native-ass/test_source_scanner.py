#!/usr/bin/env python3
"""Compare source scanning in the two actual Phase-1 C assemblers.

The fixture generator does not parse or assemble source: it only supplies
different line layouts to the unchanged C assembler and the native-structured
translation, then compares status and successful output bytes.
"""
import random
import tempfile
from pathlib import Path

from test_instruction_value import assemble, compile_assembler, ROOT


def cases():
    fixed = {
        "empty": b"",
        "only_comment": b"   ; only a comment",
        "blank_lines": b"\n \t\n; comment\n* = $0800\nrts\n",
        "same_line_labels": b"* = $0800\nfirst: second: third: lda #7\n",
        "label_comment": b"* = $0800\nfirst: ; comment\nword first\n",
        "label_assignment": b"* = $0800\nfirst: base = 6\nword base\n",
        "tabs": b"\t* \t= \t$0800\t; origin\n\tlda\t #1 \t; note\n",
        "crlf": b"* = $0800\r\nlda #1\r\nrts\r\n",
        "cr_only": b"* = $0800\rlda #1\rrts\r",
        "no_final_newline": b"* = $0800\nlda #$12",
        "string_semicolon": b'* = $0800\nstring "a; b"\n',
        "char_semicolon": b"* = $0800\nbyte ';'\n",
        "comments_and_quotes": b'* = $0800\nstring "a; b" ; outer comment\nbyte \';\' ; inner\n',
        "trailing_whitespace": b"* = $0800\n  lda #1\t \t; comment\nrts\t\t\n",
        "empty_operand": b"* = $0800\nlda ; not an operand\n",
        "bad_statement": b"* = $0800\nxxx 123 ; comment\n",
        "missing_assignment": b"* = $0800\nvalue = ; comment\n",
        "long_comment_254": b";" + b"x" * 253 + b"\n",
        "long_comment_255": b";" + b"x" * 254 + b"\n",
        "long_comment_256": b";" + b"x" * 255 + b"\n",
    }
    for name, source in fixed.items():
        yield name, source

    rng = random.Random(129)
    indent = ("", " ", "\t", " \t")
    suffix = ("", "   ", "\t", " ; comment", " \t; trailing")
    instructions = ("lda #1", "ldx #$22", "sta $2000", "clc", "rts",
                    "byte 1,2,3", "word $1234", 'string "semi;colon"')
    for trial in range(200):
        lines = ["* = $0800"]
        for i in range(rng.randrange(2, 14)):
            statement = rng.choice(instructions)
            if rng.randrange(3) == 0:
                statement = "label%d: " % i + statement
            if rng.randrange(5) == 0:
                statement = "outer%d: inner%d: " % (trial, i) + statement
            lines.append(rng.choice(indent) + statement + rng.choice(suffix))
        eol = rng.choice(("\n", "\r\n", "\r"))
        source = eol.join(lines)
        if rng.randrange(2):
            source += eol
        yield "generated-%03d" % trial, source.encode("ascii")


def run():
    with tempfile.TemporaryDirectory(prefix="native_scanner_") as work:
        folder = Path(work)
        old = compile_assembler(ROOT, folder / "original.so", 0)
        new = compile_assembler(ROOT, folder / "native.so", 1)
        path = folder / "test.asm"
        count = 0
        for name, program in cases():
            path.write_bytes(program)
            old_result = assemble(old, path)
            new_result = assemble(new, path)
            if old_result[0] != new_result[0] or (
                old_result[0] == 0 and old_result[1] != new_result[1]
            ):
                raise AssertionError((name, old_result, new_result))
            count += 1
        assert count == 220, count
        print("PASS %d source scanner differential cases" % count)


if __name__ == "__main__":
    run()
