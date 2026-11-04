#!/usr/bin/env python3
"""Fast, source-driven Phase-1 coverage frontier for bootstrap/ass.c.

Run the ORIGINAL parser and the replacement emitter on the real program.
First test its exact full translation unit, then find the longest complete
source prefix that compiles (including actual global declarations). Also
compile a real function in isolation so global-data blockers cannot hide
working code generation. Never rewrite ass.c or synthesise fake routines.

Failures in incomplete features are reported, not hidden or assumed fixed.
Once the entire source compiles, this continues to exercise that milestone.
Physical bytes and runtime correctness remain separate tests.
"""
import pathlib
import re
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent.parent
ASS = ROOT / "bootstrap" / "ass.c"
DRIVER = ROOT / "build" / "nanoc2-ass-frontier"
DRIVER.parent.mkdir(parents=True, exist_ok=True)

def c_mask(text):
    # Mask comments, strings and character literals while preserving exact
    # offsets and line boundaries for balanced function-body extraction.
    token = re.compile(
        r'/\*[\s\S]*?\*/|//[^\n]*|"(?:\\.|[^"\\])*"|'
        r"'(?:\\.|[^'\\])*'"
    )
    return token.sub(lambda match: re.sub(r'[^\n]', ' ', match.group()), text)

def definitions(text):
    clean = c_mask(text)
    pattern = re.compile(
        r'^[ \t]*(?:char|int|unsigned)[ \t]+'
        r'([A-Za-z_]\w*)[ \t]*\([^;]*?\)[ \t\n]*\{', re.M
    )
    found = []
    for match in pattern.finditer(clean):
        depth = 1
        end = match.end()
        while depth and end < len(clean):
            if clean[end] == '{':
                depth += 1
            elif clean[end] == '}':
                depth -= 1
            end += 1
        assert depth == 0, ("unbalanced C function", match.group(1))
        found.append((match.group(1), match.start(), end,
                      text.count('\n', 0, match.start()) + 1))
    assert found and found[-1][0] == "ass_assemble"
    return found

def compile_source(text):
    return subprocess.run(
        [str(DRIVER), "native"], input=text.encode(),
        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
        timeout=15,
    )

def status(result):
    if result.returncode == 0:
        return "OK"
    return "rejected (exit %d): %s" % (
        result.returncode,
        result.stderr.decode(errors="replace").strip()[:270],
    )

def main():
    text = ASS.read_text()
    funcs = definitions(text)
    subprocess.run(
        ["cc", "-std=c99", "-funsigned-char", "-O0",
         str(ROOT / "nanoc2" / "parser_tape_driver.c"),
         "-o", str(DRIVER)],
        check=True,
    )

    # An actual function from ass.c, unchanged. This verifies the first
    # source-driven success even if global-data integration blocks TU parsing.
    name, begin, end, _ = funcs[0]
    assert name == "upper_char"
    isolated = compile_source(text[begin:end])
    print("ass.c isolated %s: %s" % (name,status(isolated)),flush=True)
    assert isolated.returncode == 0, "known-good ass.c frontier regressed"

    whole = compile_source(text)
    print("ass.c complete translation unit (%d lines, %d functions): %s" %
          (len(text.splitlines()),len(funcs),status(whole)),flush=True)

    successful = 0
    first_blocker = None
    for index,(name, _,end,line) in enumerate(funcs,1):
        result = compile_source(text[:end]+"\n")
        if result.returncode != 0:
            first_blocker = (index,name,line,status(result))
            break
        successful += 1
    if first_blocker:
        index,name,line,message = first_blocker
        print("ass.c consecutive prefix: %d/%d functions; first "
              "blocked function %d %s (source line %d): %s" %
              (successful,len(funcs),index,name,line,message),flush=True)
    else:
        print("ass.c consecutive prefix: %d/%d functions compile" %
              (successful,len(funcs)),flush=True)

    # Full source compilation is necessary but not sufficient for native
    # correctness or size. A regression in isolated real C is always fatal.
    # Other failures are deliberately visible as our development frontier.
    # First seven original ass.c functions, including wide indexed
    # byte/word fixup stores and computed-index reads, compile with the
    # complete unmodified global declarations. Keep this milestone gated.
    assert successful >= 7, "ass.c prefix coverage regressed below seven functions"
    if whole.returncode == 0:
        assert first_blocker is None, "full source accepted, prefix rejected"

if __name__ == "__main__":
    main()
