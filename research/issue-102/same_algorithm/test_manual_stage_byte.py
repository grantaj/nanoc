"""Execute the same static-ABI hand-coded C stage_byte on real linked 6502 image."""
import machine_verify as mv
S=mv.SYM
count=0
for n in (0,1,254,255,256,257,511,512,4095,4096,11262,11263,11264,11265,32767):
 for value in (0,0x12,0x7f,0xff):
  cpu=mv.Machine({})
  cpu.m[1]=0x34
  cpu.poke_word(S['ass_image_length'],n)
  addr=S['ass_image']+n
  before=0x5a
  if n<11264:cpu.write(addr,before)
  cpu.A=value;cpu.PC=S['stage_byte']
  sentinel=0x0740;cpu.push((sentinel-1)>>8);cpu.push((sentinel-1)&255)
  for k in range(300):
   if cpu.PC==sentinel:break
   cpu.step()
  else:raise AssertionError(('timeout',n))
  want=11 if n>=11264 else 0
  assert cpu.A==want,(n,value,'return',cpu.A,want)
  assert cpu.word(S['ass_image_length'])==n+(n<11264),(n,value,'len')
  if n<11264:assert cpu.read(addr)==value,(n,value,'stored',cpu.read(addr))
  count+=1
print('PASS',count,'stage_byte machine executions incl >255 index, page crossing, final capacity, full cases')
