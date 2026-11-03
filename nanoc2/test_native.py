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


def original_function(name):
    match = re.search(r"^char\s+" + re.escape(name) + r"\s*\([^)]*\)\s*\{",
                      SOURCE, re.M)
    assert match, name
    n, p = 1, match.end()
    while n:
        n += (SOURCE[p] == "{") - (SOURCE[p] == "}")
        p += 1
    return SOURCE[match.start():p]


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
        "\t* = $0200", "main:",
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
        "\t* = $0200", "main:",
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


def run_native(name, source, test_lines, driver):
    output = subprocess.run([str(driver), "native"], input=source.encode(),
                            capture_output=True, check=True)
    asm = output.stdout.decode()
    assert "__nc_start:" in asm and "NC_BSS = $4800" in asm
    assert "sta __tptr" in asm if name == "same_bytes" else "__tptr" in asm
    # Checking source rather than a handcrafted generated instruction listing.
    # Local declarations and global array homes are in the same source stream.
    harness = list(test_lines)
    harness += [
        "\tjmp success",
        "native_fail:", "\tlda #$40", "\tsta $02",
        ".halt:", "\tjmp .halt",
        "success:", "\tlda #$ff", "\tsta $02",
        ".halt:", "\tjmp .halt",
        "",
    ]
    # vasm treats separate "* = $0200" and "* = $0800" origins as
    # independent segments. The normal project test pattern is therefore
    # two PRGs, with the code PRG preloaded at $0800.
    generated_source = OUT / (name + "-generated.asm")
    generated_source.write_text(asm)
    code_prg = OUT / (name + "-generated.prg")
    subprocess.run([VASM, "-Fbin", "-cbm-prg", "-o", str(code_prg),
                    str(generated_source)], cwd=ROOT, check=True)
    code = code_prg.read_bytes()
    assert code[:2] == b"\x00\x08", (name, code[:2])

    # Symbol-only equates from the exact generated compiler output can be
    # shared by the independently assembled native caller. No duplicated
    # parameter/array offsets are hardcoded in the test.
    symbols = []
    for line in asm.splitlines():
        if re.match(r'^(?:NC_BSS|__tptr\w*|__tw\w*|__g\w*|__v\w*|n2_\w+)\s*=', line):
            symbols.append(line)
    assert any(line.startswith("n2_") for line in symbols)
    asm_path = OUT / (name + "-caller.asm")
    asm_path.write_text("\n".join(harness) + "\n" +
                        "\n".join(symbols) + "\n")
    prg = OUT / (name + "-caller.prg")
    subprocess.run([VASM, "-Fbin", "-cbm-prg", "-o", str(prg),
                    str(asm_path)], cwd=ROOT, check=True)
    raw = prg.read_bytes()
    assert raw[:2] == b"\x00\x02", (name, raw[:2])
    env = os.environ.copy()
    env["BUILD_DIR"] = str(OUT)
    env["VICE_TIMEOUT"] = "35"
    env["VICE_PRELOAD_PRG"] = str(code_prg)
    subprocess.run(["sh", "tests/run-test.sh", str(prg),
                    "nanoc2-" + name], cwd=ROOT, env=env, check=True)
    print("%s: assembled %d loaded bytes; native ABI and result checks passed" %
          (name, len(raw)-2))


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


if __name__ == "__main__":
    main()
