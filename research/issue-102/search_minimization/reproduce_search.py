"""Reproduce the #102 search experiments against a freshly built 6502 image.

Use the original recovered 44-function source, no production nanoc1 edits.
The same strict/native 6502 checks run for each linked candidate.  The
baseline and separate DP/layout search variants are compared after outlining.
"""
import os,sys,subprocess,json,hashlib
from pathlib import Path

R=Path(__file__).resolve().parent
os.chdir(R)
ENV=dict(os.environ,PYTHONHASHSEED='0',PYTHONPATH=str(R/'full_corpus')+':'+str(R),
         REG_FIRST='1',NATIVE_COMPARE='1',ZP_BASE='0x30',ZP_BUDGET='16')
ENV.pop('POINTER_HOME',None);ENV.pop('BLOCK_ONLY',None)

def run(command):
    p=subprocess.run(command,env=ENV,capture_output=True,text=True)
    if p.returncode:
        print('FAILED',command,'\n',p.stdout[-3000:],'\n',p.stderr[-3000:]);raise SystemExit(1)
    return p.stdout

def measure():
    j=lambda x:json.loads((R/x).read_text())
    return dict(loaded=j('layout_metrics.json')['compact_bytes'],strict=j('strict_check.json')['passed'],
        segments=j('byte_match_result.json')['matched'],cases=j('region_parallel_results.json')['passed'],
        prg_sha256=hashlib.sha256((R/'compact_image.prg').read_bytes()).hexdigest(),
        outliner=j('outline_stats.json')['nominal_bytes_saved'])

def build(variant):
    for script in ('link_model.py','arg_a_abi.py','machine_flow.py'):run([sys.executable,script])
    if variant=='copy':
        run([sys.executable,'copy_state_search.py'])
        run([sys.executable,'test_copy_state_search.py'])
    elif variant=='layout':run([sys.executable,'block_order_search.py'])
    elif variant!='control':raise ValueError(variant)
    for script in ('register_home.py','live_home_allocator.py','build_image.py','layout_pass.py'):
        run([sys.executable,script])
    pre=len((R/'compact_image.prg').read_bytes())-2
    for script in ('outline_8.py','build_image.py','layout_pass.py','strict_link_check.py','byte_match.py',
                   'parallel_cases.py','test_native_compare.py'):
        run([sys.executable,script])
    m=measure();m['before_outlining']=pre
    assert (m['strict'],m['segments'],m['cases'])==(44,45,29),m
    (R/f'SEARCH_{variant.upper()}.PRG').write_bytes((R/'compact_image.prg').read_bytes())
    return m

def main():
    records={}
    selected=tuple(sys.argv[1:]) or ('control','layout','copy')
    if any(v not in ('control','layout','copy') for v in selected):raise SystemExit('variants: control layout copy')
    for variant in selected:
        records[variant]=build(variant)
        print(variant.upper(),records[variant],flush=True)
    expected={'control':8945,'layout':8945,'copy':8941}
    for variant,m in records.items():assert m['loaded']==expected[variant],records
    if 'copy' in records:assert records['copy']['before_outlining']==9932,records
    (R/'search_experiment_results.json').write_text(json.dumps(records,indent=2))
    print('REPRODUCTION PASS: all requested actual 6502 images machine-tested',flush=True)
if __name__=='__main__':main()
