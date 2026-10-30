#!/usr/bin/env python3
"""Reproduce a measured *source-representation* ablation, not a new 6502 optimiser.

Run from issue-102 research recovery checkout. Requires original bundled ZIP,
Python with pycparser, cc, and original research backend dependencies.

The experiment substitutes literals for globally initialized scalar constants
whose addresses are not taken and which have no writes in the complete C unit.
It leaves the rest of the C code, machine backend, calling convention, and
linker untouched. It regenerates the typed per-function source tapes.
"""
from pathlib import Path
import argparse, copy, json, os, re, subprocess, tempfile, zipfile, shutil, sys
from pycparser import c_parser, c_ast, c_generator

ARCHIVE = Path(__file__).resolve().parents[1] / 'nanoc_remaining_gap_codegen_experiment.zip'

def parse(src):
    return c_parser.CParser().parse(re.sub(r'/\*.*?\*/', '', src, flags=re.S))

def immutable_scalars(src):
    unit=parse(src)
    written=set();address_taken=set()
    class Inspect(c_ast.NodeVisitor):
        def visit_Assignment(self,n):
            if isinstance(n.lvalue,c_ast.ID):written.add(n.lvalue.name)
            self.generic_visit(n)
        def visit_UnaryOp(self,n):
            if n.op=='&' and isinstance(n.expr,c_ast.ID):address_taken.add(n.expr.name)
            if n.op in ('p++','p--','++','--') and isinstance(n.expr,c_ast.ID):written.add(n.expr.name)
            self.generic_visit(n)
    Inspect().visit(unit)
    result={}
    for x in unit.ext:
        if not (isinstance(x,c_ast.Decl) and isinstance(x.type,c_ast.TypeDecl)
                and isinstance(x.init,c_ast.Constant)):
            continue
        if x.name not in written|address_taken:
            result[x.name]=int(x.init.value,0)
    return result

def transform(src):
    immut=immutable_scalars(src)
    for name,value in immut.items():
        pattern=r'(?m)^char\s+'+re.escape(name)+r'\s*=\s*'+str(value)+r'\s*;[ \t]*\n'
        src,count=re.subn(pattern, '', src)
        assert count==1,(name,count)
    for name,value in sorted(immut.items(),key=lambda x:-len(x[0])):
        src=re.sub(r'\b'+re.escape(name)+r'\b',str(value),src)
    parse(src)
    return src,immut

def regenerate_func_files(root,src):
    unit=parse(src); generator=c_generator.CGenerator()
    funcs=[f for f in unit.ext if isinstance(f,c_ast.FuncDef)]
    globals_=[x for x in unit.ext if isinstance(x,c_ast.Decl) and not isinstance(x.type,c_ast.FuncDecl)]
    decl=[]
    for x in globals_:
        y=copy.deepcopy(x);y.init=None;decl.append(generator.visit(y)+';')
    proto=[generator.visit(f.decl)+';' for f in funcs]
    proto+=['int io_open(char *name, int length);','int io_read(int handle);','char io_close(int handle);']
    prefix='\n'.join(decl+proto)+'\n'
    for f in funcs:
        (root/'full_corpus'/'whole_corpus'/(f.decl.name+'.c')).write_text(prefix+generator.visit(f)+'\n')
    assert len(funcs)==44

def run(args,cwd,env,logfile):
    with (cwd/logfile).open('w') as f:
        subprocess.run(args,cwd=cwd,env=env,stdout=f,stderr=subprocess.STDOUT,check=True)

def build(root):
    env=os.environ.copy();env.update(PYTHONPATH=str(root/'full_corpus')+':'+str(root),PYTHONHASHSEED='0',REG_FIRST='1',NATIVE_COMPARE='1',ZP_BASE='0x30',ZP_BUDGET='16')
    for n in ('POINTER_HOME','NATURAL6502','NATURAL6502_WIDE','WIDE_ALLOW'):
        env.pop(n,None)
    run(['cc','-std=c99','-funsigned-char','-O0','-w','-o','full_corpus/host_assembler','full_corpus/host_assembler.c'],root,env,'immut_host_build.log')
    run(['cc','-std=c99','-funsigned-char','-O0','-w','-shared','-fPIC','-o','full_corpus/host_ass.so','full_corpus/host_assembler.c'],root,env,'immut_shared_build.log')
    for script, log in [('link_model.py','link'),('arg_a_abi.py','abi'),('machine_flow.py','flow'),('register_home.py','register'),('live_home_allocator.py','allocator'),('build_image.py','image'),('layout_pass.py','pre_layout')]:
        run([sys.executable,script],root,env,'immut_'+log+'.log')
    pre=(root/'compact_image.prg').stat().st_size-2
    for script, log in [('outline_8.py','outline'),('build_image.py','out_image'),('layout_pass.py','out_layout'),('strict_link_check.py','strict'),('byte_match.py','byte_match'),('parallel_cases.py','programs'),('test_native_compare.py','words')]:
        run([sys.executable,script],root,env,'immut_'+log+'.log')
    read=lambda f:json.loads((root/f).read_text())
    size=read('layout_metrics.json')['compact_bytes']
    correctness=(read('strict_check.json')['passed'],read('byte_match_result.json')['matched'],read('region_parallel_results.json')['passed'])
    assert correctness==(44,45,29),correctness
    assert 'PASS 9120' in (root/'immut_words.log').read_text()
    return dict(preoutline=pre,linked=size,functions=44,segments=45,programs=29,word_cases=9120)

def verify_host_oracles(root,original_src):
    host=root/'full_corpus'/'host_assembler.c'
    src=root/'full_corpus'/'ass.c'
    orig_src=src.read_text();orig_host=host.read_text()
    origlib=root/'host_original.so'
    try:
        src.write_text(original_src)
        host.write_text(orig_host.replace('st!=0','st!=ASSEMBLE_OK'))
        subprocess.run(['cc','-std=c99','-funsigned-char','-O0','-w','-shared','-fPIC','-o',str(origlib),str(host)],check=True,cwd=root)
    finally:
        src.write_text(orig_src);host.write_text(orig_host)
    # Read corpus exactly as defined by original research tests, no handwritten test choices.
    sys.path[:0]=[str(root)]
    source=(root/'machine_cases.py').read_text().split('counts=[];started=time.time()')[0]
    namespace={'__file__':str(root/'machine_cases.py')}
    # For a trusted repository-local Python test fixture only.
    exec(compile(source,str(root/'machine_cases.py'),'exec'),namespace)
    programs=namespace['programs']
    import ctypes
    def run_oracle(library,inputs):
        dll=ctypes.CDLL(str(library))
        dll.ass_assemble.argtypes=[ctypes.c_char_p,ctypes.c_ubyte,ctypes.c_char_p,ctypes.c_ubyte,ctypes.c_uint]
        dll.ass_assemble.restype=ctypes.c_ubyte
        out={}
        # A short temporary filename avoids the research ABI's byte-length truncation.
        with tempfile.TemporaryDirectory() as td:
            p=Path(td)/'t.asm'
            for k,data in inputs.items():
                p.write_bytes(data)
                result=dll.ass_assemble(str(p).encode(),len(str(p)),b'',0,0)
                n=ctypes.c_int.in_dll(dll,'ass_image_length').value
                raw=bytes((ctypes.c_ubyte*11264).in_dll(dll,'ass_image'))[:n]
                out[k]=(result,raw)
        return out
    a=run_oracle(origlib,programs)
    b=run_oracle(root/'full_corpus'/'host_ass.so',programs)
    assert a==b,[(k,len(a[k][1]),len(b[k][1])) for k in a if a[k]!=b[k]]
    return len(a)

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--archive',type=Path,default=ARCHIVE);ap.add_argument('--workdir',type=Path,default=None)
    ns=ap.parse_args()
    with tempfile.TemporaryDirectory(prefix='nanoc_immutable_') if ns.workdir is None else tempfile.TemporaryDirectory(prefix='unused_') as td:
        dest=Path(td) if ns.workdir is None else ns.workdir.resolve()
        dest.mkdir(parents=True,exist_ok=True)
        with zipfile.ZipFile(ns.archive) as archive: archive.extractall(dest)
        root=dest/'nanoc_machine_value_home_planner';p=root/'full_corpus'/'ass.c'
        original=p.read_text();changed,immut=transform(original)
        assert len(immut)==43,len(immut)
        p.write_text(changed)
        host=root/'full_corpus'/'host_assembler.c'
        source=host.read_text();assert 'st!=ASSEMBLE_OK' in source
        host.write_text(source.replace('st!=ASSEMBLE_OK','st!=0'))
        regenerate_func_files(root,changed)
        result=build(root)
        assert (result['preoutline'],result['linked'])==(9679,8697),result
        result['original_c_oracle_matches']=verify_host_oracles(root,original)
        assert result['original_c_oracle_matches']==29
        result['immutable_symbols']=immut
        (dest/'immutable_result.json').write_text(json.dumps(result,indent=2))
        print(json.dumps({k:v for k,v in result.items() if k!='immutable_symbols'},indent=2))
        print('Proof set',len(immut),'immutable scalars; source and generated artifact in',dest)

if __name__=='__main__':main()
