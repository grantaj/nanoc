#!/usr/bin/env python3
"""#102 research controls: source-level semantic alternatives, unchanged 6502 backend.

Input is the immutable recovered ZIP. The replacements below are deliberately
source-specific controls, NOT general compiler optimisations or codegen rules.
"""
from __future__ import annotations
import argparse
import ctypes
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import zipfile

VARIANTS = ("control", "early_break_keep_flag", "early_break_use_index", "persistent_cursor_plus_count")
REPLACE_FN = ["full_corpus/ass.c", "full_corpus/exact_source/ass.c", "full_corpus/whole_corpus/find_symbol.c"]


def patch_find(s: str, name: str) -> str:
    assert s.count("same = 0;") == 1
    if name == "early_break_keep_flag":
        return s.replace("same = 0;", "same = 0;\n            break;", 1)
    if name == "early_break_use_index":
        assert len(re.findall(r"\bsame\s*=\s*1\s*;", s)) == 1
        assert len(re.findall(r"if\s*\(same\s*!=\s*0\)", s)) == 1
        s, n = re.subn(r"^\s*char same;\n", "", s, count=1, flags=re.M)
        assert n == 1
        s, n = re.subn(r"^\s*same\s*=\s*1\s*;\n", "", s, count=1, flags=re.M)
        assert n == 1
        return re.sub(r"if\s*\(same\s*!=\s*0\)", "if (j == length)", s.replace("same = 0;", "break;", 1), count=1)
    raise ValueError(name)


def patch_cursor(s: str, path: str) -> str:
    assert s.count("char ass_image[11264];") == 1
    s = s.replace("char ass_image[11264];", "char ass_image[11264];\nchar *ass_image_cursor;", 1)
    if path in ("full_corpus/ass.c", "full_corpus/exact_source/ass.c", "full_corpus/whole_corpus/stage_byte.c"):
        assert s.count("ass_image[ass_image_length] = value & 255;") == 1
        s = s.replace("ass_image[ass_image_length] = value & 255;", "ass_image_cursor[0] = value & 255;\n    ass_image_cursor = ass_image_cursor + 1;", 1)
    if path in ("full_corpus/ass.c", "full_corpus/exact_source/ass.c", "full_corpus/whole_corpus/reset_assembler.c"):
        assert s.count("ass_image_length = 0;") == 1
        s = s.replace("ass_image_length = 0;", "ass_image_length = 0;\n    ass_image_cursor = ass_image;", 1)
    return s


def prepare(archive: Path, dest: Path, variant: str) -> Path:
    dest.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive) as z:
        for name in z.namelist():
            p = Path(name)
            if p.is_absolute() or ".." in p.parts:
                raise ValueError(f"unsafe ZIP member {name}")
        z.extractall(dest)
    root = dest / "nanoc_machine_value_home_planner"
    assert (root / "reproduce_native_compare.sh").exists()
    if variant.startswith("early_break"):
        for path in REPLACE_FN:
            f = root / path
            f.write_text(patch_find(f.read_text(), variant))
    if variant == "persistent_cursor_plus_count":
        for path in ["full_corpus/ass.c", "full_corpus/exact_source/ass.c", "full_corpus/whole_corpus/stage_byte.c", "full_corpus/whole_corpus/reset_assembler.c"]:
            f = root / path
            f.write_text(patch_cursor(f.read_text(), path))
    if variant != "control":
        # Keep the actual correctness assertions, but do not hard-code a target size.
        p = root / "reproduce_native_compare.sh"
        assert "assert (a,b,c,d)==(8945,44,45,29),(a,b,c,d)" in p.read_text()
        p.write_text(p.read_text().replace("assert (a,b,c,d)==(8945,44,45,29),(a,b,c,d)", "assert (b,c,d)==(44,45,29),(a,b,c,d)"))
    return root


def build(root: Path) -> dict:
    env = dict(os.environ, PYTHONHASHSEED="0")
    p = subprocess.run(["sh", "reproduce_native_compare.sh"], cwd=root, env=env, text=True, capture_output=True)
    if p.returncode:
        print(p.stdout, p.stderr, file=sys.stderr)
        raise RuntimeError(f"full linked 6502 tests failed: {root}")
    print(root.parent.name + ": " + p.stdout.strip(), flush=True)
    sizes = {q["name"]:q["bytes"] for q in json.loads((root/"sizes.json").read_text())}
    layout = json.loads((root/"layout_metrics.json").read_text())
    checks = {
        "strict_functions": json.loads((root/"strict_check.json").read_text())["passed"],
        "segments": json.loads((root/"byte_match_result.json").read_text())["matched"],
        "programs": json.loads((root/"region_parallel_results.json").read_text())["passed"],
    }
    assert checks == {"strict_functions":44,"segments":45,"programs":29},checks
    return {"before_outlining":len((root/"PRE_OUTLINE.PRG").read_bytes())-2,
            "linked_bytes":layout["compact_bytes"], "functions":{k:sizes[k] for k in ("stage_byte", "reset_assembler", "find_symbol")}, "checks":checks}


def verify_host_equivalence(roots: dict[str, Path]) -> int:
    # Unlike the full 6502-oracle test, this checks modified C directly against
    # the *original C* on the identical source programs, status and every output byte.
    control = roots["control"]
    sys.path.insert(0,str(control))
    src=(control/"machine_cases.py").read_text().split("counts=[];started=time.time()")[0]
    env={"__file__":str(control/"machine_cases.py")}
    exec(src,env)
    lib = {}
    for name,root in roots.items():
        c=ctypes.CDLL(str((root/"full_corpus/host_ass.so").resolve()))
        c.ass_assemble.argtypes=[ctypes.c_char_p,ctypes.c_ubyte,ctypes.c_char_p,ctypes.c_ubyte,ctypes.c_uint]
        c.ass_assemble.restype=ctypes.c_ubyte
        lib[name]=c
    with tempfile.TemporaryDirectory() as tmp:
        p=Path(tmp)/"test.asm"
        for label,data in env["programs"].items():
            p.write_bytes(data)
            result={}
            for name,c in lib.items():
                status=c.ass_assemble(str(p).encode(),len(str(p).encode()),b"",0,0)
                n=ctypes.c_int.in_dll(c,"ass_image_length").value
                output=bytes((ctypes.c_ubyte*11264).in_dll(c,"ass_image"))[:n]
                result[name]=(status,output)
            assert all(v==result["control"] for v in result.values()),label
    print("SOURCE LEVEL: original and modified C agree on 29/29 statuses and output byte arrays")
    return 29

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--archive", type=Path, default=Path(__file__).resolve().parents[1]/"nanoc_remaining_gap_codegen_experiment.zip")
    ap.add_argument("--output",type=Path,default=Path("/tmp/nanoc102-alternatives"))
    ap.add_argument("--variant",choices=(*VARIANTS,"all"),default="all")
    a=ap.parse_args()
    targets=VARIANTS if a.variant=="all" else (a.variant,)
    roots={}
    sizes={}
    for name in targets:
        root=prepare(a.archive,a.output/name,name)
        roots[name]=root
        sizes[name]=build(root)
    if "control" in roots and len(roots)>1:
        verify_host_equivalence(roots)
    a.output.mkdir(parents=True,exist_ok=True)
    (a.output/"measured.json").write_text(json.dumps(sizes,indent=2))
    print(json.dumps(sizes,indent=2))
