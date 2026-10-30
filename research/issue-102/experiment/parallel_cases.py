from pathlib import Path
import multiprocessing as mp
import tempfile, shutil, json, time, os
import machine_verify as mv
from machine_verify import Machine, SYM
source=(Path(__file__).parent/'machine_cases.py').read_text().split('counts=[];started=time.time()')[0]
env={'__file__':str(Path(__file__).parent/'machine_cases.py')}
exec(source,env)
programs=list(env['programs'].items())

def check(item):
 name,data=item
 # Every independent C oracle gets a private test.asm file.
 with tempfile.TemporaryDirectory(prefix='nanoc_case_') as td:
  r=Path(td);(r/'full_corpus').mkdir()
  shutil.copy2(Path(__file__).parent/'full_corpus/host_ass.so',r/'full_corpus/host_ass.so')
  mv.R=r
  cpu=Machine({'test.asm':data})
  steps,elapsed=cpu.run(max_steps=5000000)
  ret=cpu.m[SYM['__experiment_status']];n=cpu.word(SYM['ass_image_length']);got=bytes(cpu.m[SYM['ass_image']:SYM['ass_image']+n])
  er,eb=mv.run_oracle(data)
  return dict(name=name,ok=(ret==er and got==eb),status=ret,expected_status=er,size=n,expected_size=len(eb),steps=steps,elapsed=elapsed)
if __name__=='__main__':
 start=time.monotonic()
 with mp.Pool(4) as pool:
  res=[]
  for item in pool.imap_unordered(check,programs):
   res.append(item)
   print(f'{len(res):02d}/29 {item["name"]:24s} {"PASS" if item["ok"] else "FAIL"} {item["steps"]} instructions',flush=True)
   if not item['ok']:break
 Path(__file__).parent.joinpath('region_parallel_results.json').write_text(json.dumps({'passed':sum(x['ok'] for x in res),'cases':len(res),'seconds':time.monotonic()-start,'results':res},indent=2))
 assert len(res)==29 and all(x['ok'] for x in res)
 print('COMPLETE 29/29',flush=True)
