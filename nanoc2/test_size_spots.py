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

from test_native import (ROOT, original_function, fixture_function,
                         globals_for_find, ass_function, ass_global,
                         ASS_SOURCE)

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

def exact_c_function(path, name):
    # Extract an actual checked-in C function, not a substitute algorithm.
    text = path.read_text()
    m = re.search(r'^(?:char|int|unsigned)\s+' + re.escape(name) + r'\s*\([^)]*\)\s*\{',
                  text, re.M)
    assert m, name
    depth, end = 1, m.end()
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[m.start():end]


def measure_assembled(asm, old, name):
    m = re.search((r'^(__f[0-9a-fA-F]{2}):\s*$' if old else
                   r'^(__c[0-9a-fA-F]{2}):\s*$'), asm, re.M)
    assert m, (name, "missing function entry label")
    entry = m.group(1)
    nlabels = len(re.findall(r'^__(?:f|c)[0-9a-fA-F]{2}:\s*$', asm, re.M))
    # Grouped calling-convention benchmark: count all function bodies
    # together, so caller + callee overhead is measured consistently.
    if name in ("word_call_unit", "ass_scope_find_unit",
                "ass_allocate_unit", "ass_symbol_api_unit",
                "ass_prefix15", "ass_prefix32"):
        assert nlabels > 1, (name,nlabels)
    else:
        assert nlabels == 1, (name,nlabels)
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
    assert 0 < count < 30000, (name,first,last)
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
        # Non-traversal controls: constant return and small byte branches.
        ("constant", exact_c_function(
            ROOT/"tests"/"nanoc2"/"call-arity.c", "constant")),
        ("guarded", exact_c_function(
            ROOT/"tests"/"nanoc2"/"call-arity.c", "guarded")),
        ("map_byte", exact_c_function(
            ROOT/"tests"/"nanoc2"/"call-index.c", "map_byte")),
    ]
    baseline_count = len(targets)
    # Compare identical Phase-1 C algorithms and physical assembled bytes,
    # not a handwritten assembler versus an unrelated C implementation.
    scalar = ROOT/"tests"/"nanoc2"/"word-scalar.c"
    ops = ROOT/"tests"/"nanoc2"/"word-ops.c"
    for name in ("constant_word", "echo_word", "add_word", "subtract_word"):
        targets.append((name,exact_c_function(scalar,name)))
    word_scalar_count = len(targets)-baseline_count
    for name in ("sum_word", "diff_word", "inplace_sum_left",
                 "inplace_sum_right", "return_sum", "return_diff",
                 "signed_lt", "signed_ge", "signed_eq",
                 "signed_const_lt", "word_truth", "word_count"):
        targets.append((name,exact_c_function(ops,name)))
    word_ops_count = len(targets)-baseline_count-word_scalar_count
    targets.append(("word_call_unit",
                    (ROOT/"tests"/"nanoc2"/"word-call.c").read_text()))
    mixed = ROOT/"tests"/"nanoc2"/"mixed-arithmetic.c"
    mixed_names = (
        "widen_copy", "narrow_copy", "widen_return", "narrow_return",
        "mix_add", "mix_sub", "mix_return", "mix_return_sub",
        "compound", "compound_return", "reverse_mixed",
        "literal_base", "reverse_sub", "alias_late",
        "byte_chain", "byte_return", "byte_sum_word",
        "reverse_add_store", "reverse_sub_store", "byte_sum_store",
        "byte_pair_return", "byte_pair_store", "fill_even",
    )
    for name in mixed_names:
        source=exact_c_function(mixed,name)
        if name=="fill_even":
            source="char out_even[256];\n" + source
        targets.append((name,source))
    mixed_count = len(mixed_names)
    compare_source = ROOT/"tests"/"nanoc2"/"mixed-compare.c"
    relation_names = ("lt","le","gt","ge","eq","ne")
    compare_names = tuple(prefix+"_"+relation for relation in relation_names
                          for prefix in ("mix","rev","umix","urev"))
    compare_names += (
        "byte_lt_256","byte_eq_256","literal_gt_byte",
        "literal_eq_byte","literal_lt_word","literal_eq_word",
        "literal_gt_unsigned","byte_ge_257","word_lt_byte_literal",
        "mark_below_word","advance_word_until_byte",
    )
    for name in compare_names:
        source=exact_c_function(compare_source,name)
        if name=="mark_below_word":
            source="char compare_marks[256];\n"+source
        targets.append((name,source))
    compare_count=len(compare_names)
    expression_source=ROOT/"tests"/"nanoc2"/"expression-condition.c"
    expression_names=(
        "expr_less","expr_ge_byte","expr_chain_equal",
        "expr_chain_truth","expr_difference_truth",
        "expr_reversed_byte","expr_compare_byte",
        "expr_count_down","expr_index_until",
    )
    for name in expression_names:
        source=exact_c_function(expression_source,name)
        if name=="expr_index_until":
            source="char expr_marks[256];\n"+source
        targets.append((name,source))
    expression_count=len(expression_names)
    rhs_source=ROOT/"tests"/"nanoc2"/"comparison-rhs.c"
    rhs_names=("rhs_lt","rhs_le","rhs_gt","rhs_ge","rhs_eq",
               "rhs_ne","rhs_signed","rhs_unsigned","rhs_literal","rhs_chain")
    for name in rhs_names:
        targets.append((name,exact_c_function(rhs_source,name)))
    rhs_count=len(rhs_names)
    # The actual assembler drives the next slice. These are exact
    # unmodified Phase-1 functions, not synthetic arithmetic lookalikes.
    for name in ("upper_char","same_text","apply_byte_prefix"):
        source=ass_function(name)
        if name=="apply_byte_prefix":
            source=ass_global("VALUE_PREFIX_LOW")+"\n"+source
        targets.append(("ass_"+name,source))
    # Complete original global declarations are required for this routine's
    # five parallel fixup arrays (char and two-byte int/unsigned). The
    # function body is copied byte-for-byte from bootstrap/ass.c.
    ass_prefix=ASS_SOURCE[:ASS_SOURCE.index("char upper_char(")]
    targets.append(("ass_append_fixup",ass_prefix+"\n"+ass_function("append_fixup")))
    targets.append(("ass_relative_byte",ass_function("relative_byte")))
    targets.append(("ass_trim_fixups",ass_prefix+"\n"+ass_function("trim_fixups")))
    targets.append(("ass_scope_find_unit",ass_prefix+"\n"+
                    ass_function("scope_for_name")+"\n"+
                    ass_function("find_symbol")))
    # The real allocate_symbol needs scope_for_name and the complete
    # original global table declaration block; count both bodies in
    # each compiler so that ABI calls are measured consistently.
    targets.append(("ass_allocate_unit",ass_prefix+"\n"+
                    ass_function("scope_for_name")+"\n"+
                    ass_function("allocate_symbol")))
    # Include every original callee in the same physical function span;
    # this is a five-function assembly comparison, not a surrogate body.
    targets.append(("ass_symbol_api_unit",ass_prefix+"\n"+
                    "\n".join(ass_function(name) for name in (
                        "scope_for_name","find_symbol","allocate_symbol",
                        "intern_label","define_constant"))))
    targets.append(("ass_patch_word_chain",ass_prefix+"\n"+
                    ass_function("patch_word_chain")))
    # Exact first 15 functions and all globals of original ass.c.
    targets.append(("ass_prefix15",
                    ASS_SOURCE[:ASS_SOURCE.index(
                        "/* ---------------- Tiny assembler value grammar")]))
    # Also measure the first 32 consecutive verbatim original functions.
    # This overlaps the 15-function checkpoint; neither is a whole image.
    targets.append(("ass_prefix32",
                    ASS_SOURCE[:ASS_SOURCE.index("char open_include(")]))
    ass_count=12
    # The original nanoc1 host compiler rejects this composed-call fixture.
    # It stays in independent native VICE correctness testing; the physical
    # comparison stays strictly apples-to-apples with accepted source.
    word_array=ROOT/"tests"/"nanoc2"/"word-array-read.c"
    word_array_names=("read_sample","copy_sample",
                      "sample_equals","read_previous_sample")
    for name in word_array_names:
        targets.append((name,"unsigned word_samples[640];\n"+
                        exact_c_function(word_array,name)))
    new_count=len(word_array_names)
    results = []
    for name, source in targets:
        old_asm = compile_host(old_driver,source)
        new_asm = compile_host(new_driver,source,"native")
        old_bytes,old_ins,old_body = measure_assembled(old_asm,True,name)
        new_bytes,new_ins,new_body = measure_assembled(new_asm,False,name)
        (OUT / (name + "-old-body.asm")).write_text(old_body)
        (OUT / (name + "-new-body.asm")).write_text(new_body)
        results.append((name,old_bytes,new_bytes,old_ins,new_ins))
        # The initial generic chain regressed on three direct two-leaf
        # cases. Keep the exact assembled-byte comparison as a regression
        # gate, not an instruction-count or arbitrary target estimate.
        if name in ("reverse_mixed","reverse_sub","byte_sum_word",
                    "ass_upper_char","ass_same_text","ass_apply_byte_prefix",
                    "ass_append_fixup","ass_relative_byte","ass_trim_fixups",
                    "ass_scope_find_unit"):
            assert new_bytes <= old_bytes, (name,old_bytes,new_bytes)
        # A previous full-word identity simplification accidentally
        # introduced a 12-byte in-place self-copy into the real assembler.
        if name=="ass_apply_byte_prefix":
            assert new_bytes <= 23, (name,new_bytes,"word self-copy regression")
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
    assert len(results)==baseline_count+word_scalar_count+word_ops_count+1+mixed_count+compare_count+expression_count+rhs_count+ass_count+new_count
    calls_index=baseline_count+word_scalar_count+word_ops_count
    compare_index=calls_index+1+mixed_count
    expression_index=compare_index+compare_count
    rhs_index=expression_index+expression_count
    ass_index=rhs_index+rhs_count
    added_index=ass_index+ass_count
    for title,subset in [
        ("legacy-seven",results[:baseline_count]),
        ("word-scalar",results[baseline_count:baseline_count+word_scalar_count]),
        ("word-ops",results[baseline_count+word_scalar_count:calls_index]),
        ("word-call-unit",results[calls_index:calls_index+1]),
        ("mixed-composed",results[calls_index+1:compare_index]),
        ("mixed-comparisons",results[compare_index:expression_index]),
        ("arithmetic-conditions",results[expression_index:rhs_index]),
        ("computed-RHS",results[rhs_index:ass_index]),
        ("real-ass.c",results[ass_index:added_index]),
        ("computed-calls-and-word-array",results[added_index:]),
    ]:
        old_size=sum(x[1] for x in subset)
        new_size=sum(x[2] for x in subset)
        print("GROUP %s: %d functions; old %d B; new %d B; saved %d B (%.1f%%)" %
              (title,len(subset),old_size,new_size,old_size-new_size,
               100.0*(old_size-new_size)/old_size),flush=True)

if __name__=="__main__":
    main()
