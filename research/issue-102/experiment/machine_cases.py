"""Reproducible whole-program binary-vs-exact-C end-to-end tests."""
from pathlib import Path
from machine_verify import Machine,SYM,run_oracle
import random,json,time
R=Path(__file__).parent
random.seed(102)
programs={
 # Empty file has a known prefetch behaviour mismatch in target io-open.
 # It remains a separate TODO, not part of normal positive corpus.
 'simple_code':b'* = $0800\nlda #$12\nldx #$00\nsta $c000\nrts\n',
 'all_data':b'* = $0800\nbyte 1,2,3,4\nword $1234,$ffff\nstring "hello"\n',
 'labels':b'* = $0800\nstart: lda #1\nbeq done\nlda #2\ndone: rts\n',
 'comment':b';comment\n* = $0800 ; origin\nbyte 3, 4 ; bytes\n',
 'symbol_const':b'* = $0800\nnumber = $1234\nword number\nbyte <number,>number\n',
 'symbol_arith':b'* = $0800\nnumber = $1234\nword number+3,number-2\n',
 'forward_word':b'* = $0800\nword later\nbyte 9,8\nlater: rts\n',
 'forward_abs':b'* = $0800\njmp later\nlda #2\nlater: rts\n',
 'forward_branch':b'* = $0800\nbeq later\nlda #2\nlater: rts\n',
 'char_literal':b'* = $0800\nbyte \'A\',\'Z\'\n',
 'wrong_opcode':b'* = $0800\nzzz #0\n',
 'undefined_label':b'* = $0800\nword missing\n',
 'bad_data':b'* = $0800\nbyte bad\n',
 'zero_page':b'* = $0800\nlda $02\nsta $fa\n',
 'indirect':b'* = $0800\nlda ($fc),y\nsta ($fe),y\n',
 'long_indexed':b'* = $0800\nlda $1234,x\nldx #$ff\nrts\n',
 'multiple_labels':b'* = $0800\nfirst: second: lda #$0a\n',
}
for k in range(12):
 lines=['* = $0800','base = $%04x'%random.randrange(0x10000)]
 for j in range(5+random.randrange(10)):
  kind=random.randrange(9)
  if kind==0:lines.append('byte '+','.join(str(random.randrange(256)) for _ in range(1+random.randrange(4))))
  elif kind==1:lines.append('word base')
  elif kind==2:lines.append('word base+%d'%random.randrange(50))
  elif kind==3:lines.append('lda #$%02x'%random.randrange(256))
  elif kind==4:lines.append('sta $%04x'%random.randrange(65536))
  elif kind==5:lines.append('rts')
  elif kind==6:lines.append('; comment')
  elif kind==7:lines.append('lda $%04x,y'%random.randrange(65536))
  else:lines.append('byte $%02x'%random.randrange(256))
 programs['random%02d'%k]=('\n'.join(lines)+'\n').encode('ascii')
counts=[];started=time.time()
for i,(name,data) in enumerate(programs.items()):
 cpu=Machine({'test.asm':data})
 try:
  steps,elapsed=cpu.run(max_steps=5000000)
  ret=cpu.m[SYM['__experiment_status']]
  n=cpu.word(SYM['ass_image_length']);got=bytes(cpu.m[SYM['ass_image']:SYM['ass_image']+n])
  expected_ret,expected=run_oracle(data)
  ok=ret==expected_ret and got==expected
  counts.append(dict(name=name,ok=ok,steps=steps,status=ret,expected_status=expected_ret,bytes=n,expected_bytes=len(expected),match=got==expected))
  print('%02d/%02d %-22s %s ret %d/%d bytes %d/%d instructions %d'%(i+1,len(programs),name,'PASS' if ok else 'FAIL',ret,expected_ret,n,len(expected),steps),flush=True)
  if not ok:
   print('ACTUAL',got[:100].hex(),'EXPECTED',expected[:100].hex())
   break
 except Exception as e:
  print('ERROR',name,e);counts.append(dict(name=name,ok=False,error=str(e)));break
(R/'end_to_end.json').write_text(json.dumps({'cases':len(counts),'passed':sum(x['ok'] for x in counts),'seconds':round(time.time()-started,2),'results':counts},indent=2))
assert len(counts)==len(programs) and all(x['ok'] for x in counts)
