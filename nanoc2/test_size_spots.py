#!/usr/bin/env python3
"""Exact-source, exact-ABI size spot checks: production nanoc1 vs nanoc2.

Both parse the same unmodified Phase-1 C function source and use the same
static Nano C symbol/argument layout. vasm resolves all instructions.
Only bytes __cXX .. __bench_end are counted as function-body bytes.
The unchanged production compiler's shared runtime is intentionally excluded.
"""
import pathlib
import re
import subprocess
import tempfile

from test_native import ROOT, original_function, fixture_function, globals_for_find

OUT = ROOT / "build" / "nanoc2-size-spots"
OUT.mkdir(parents=True, exist_ok=True)
VASM = "vasm6502_oldstyle"

def compile_host(driver, source, *args):
    result = subprocess.run([str(driver), *args], input=source.encode(),
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        raise RuntimeError(
            "%s error %s\n%s" % (driver, result.returncode,
                                  result.stderr.decode(errors="replace")))
    return result.stdout.decode()

def measure_assembled(asm, old, name):
    m = re.search(r'^(__c[0-9a-fA-F]{2}):\s*$', asm, re.M)
    assert m, (name, "missing function entry label")
    entry = m.group(1)
    assert len(re.findall(r'^__c[0-9a-fA-F]{2}:\s*$', asm, re.M)) == 1, name
    if old:
        # This equate is emitted immediately after the final user function,
        # before the production runtime is appended. Its address is the
        # function's end, independent of common-runtime size.
        end = re.search(r'^__nc_bss_bytes\s*=', asm, re.M)
        assert end, (name, "production function terminator missing")
        assert end.start() > m.start()
        asm = asm[:end.start()] + "__bench_end:\n" + asm[end.start():]
        body_text = asm[m.end():asm.index("__bench_end:",m.end())]
    else:
        body_text = asm[m.end():]
        asm += "\n__bench_end:\n"
    # The two word expressions are resolved by vasm in the same binary as
    # the function, so no instruction-heuristic or unlinked source-counting.
    asm += "\n\tword " + entry + ", __bench_end\n"
    with tempfile.NamedTemporaryFile(
        mode="w", prefix=".nanoc2-spots-", suffix=".asm",
        dir=ROOT / "ass", delete=False
    ) as temp:
        temp.write(asm)
        temp_path = pathlib.Path(temp.name)
    image = OUT / ("%s-%s.prg" % (name, "nanoc1" if old else "nanoc2"))
    try:
        run = subprocess.run(
            [VASM, "-Fbin", "-cbm-prg", "-o", str(image), str(temp_path)],
            cwd=ROOT / "ass", stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        if run.returncode:
            raise RuntimeError("vasm failed for %s %s:\n%s" %
                               (name, "nanoc1" if old else "nanoc2",
                                (run.stdout + run.stderr).decode(errors="replace")))
    finally:
        temp_path.unlink(missing_ok=True)
    raw = image.read_bytes()
    assert raw[:2] == b"\x00\x08"
    first = int.from_bytes(raw[-4:-2], "little")
    last = int.from_bytes(raw[-2:], "little")
    count = last - first
    assert 0 < count < 12000, (name,first,last)
    if not old:
        assert first >= 0x0803
    ins = dict((op, len(re.findall(r'^\s*' + op + r'\s*(?:\n|$)',
                                    body_text, re.M | re.I)))
               for op in ('pha','pla','jsr','rts','iny','inx'))
    return count, ins, body_text

def main():
    old_driver = OUT / "old-compiler"
    new_driver = OUT / "new-compiler"
    for src, exe in [
        ("production_baseline_driver.c", old_driver),
        ("parser_tape_driver.c", new_driver),
    ]:
        subprocess.run(["cc", "-std=c99", "-funsigned-char", "-O0",
                        str(ROOT/"nanoc2"/src), "-o", str(exe)], check=True)

    targets = [
        ("same_bytes", original_function("same_bytes")),
        ("find_global", globals_for_find() + original_function("find_global")),
        ("copy_pointer", fixture_function("copy_pointer")),
        ("copy_array", "char source_bytes[256];\nchar dest_bytes[256];\n" +
         fixture_function("copy_array")),
    ]
    results = []
    for name, source in targets:
        old_asm = compile_host(old_driver,source)
        new_asm = compile_host(new_driver,source,"native")
        old_bytes,old_ins,old_body = measure_assembled(old_asm,True,name)
        new_bytes,new_ins,new_body = measure_assembled(new_asm,False,name)
        (OUT / (name + "-old-body.asm")).write_text(old_body)
        (OUT / (name + "-new-body.asm")).write_text(new_body)
        results.append((name,old_bytes,new_bytes,old_ins,new_ins))
        print("%s: old %d B, new %d B, saved %d B (%.1f%%); "
              "PHA/PLA %d/%d vs %d/%d" %
              (name,old_bytes,new_bytes,old_bytes-new_bytes,
               100.0*(old_bytes-new_bytes)/old_bytes,
               old_ins["pha"],old_ins["pla"],
               new_ins["pha"],new_ins["pla"]),flush=True)

    old_total=sum(x[1] for x in results)
    new_total=sum(x[2] for x in results)
    print("TOTAL same-source function bodies: old %d B; new %d B; "
          "saved %d B (%.1f%%)" %
          (old_total,new_total,old_total-new_total,
           100.0*(old_total-new_total)/old_total))
    assert len(results)==4

if __name__=="__main__":
    main()
