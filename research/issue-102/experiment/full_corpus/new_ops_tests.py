"""Differential machine execution for newly added whole-corpus backend operations
against exact bootstrap/ass.c, compiled as native C. Research-only emulator.
"""
import ctypes,random
from pathlib import Path
from execute6502 import CPU
p=Path(__file__).parent
lib=ctypes.CDLL(str(p/'host_ass.so'))
lib.stage_byte.argtypes=[ctypes.c_ubyte];lib.stage_byte.restype=ctypes.c_ubyte
lib.apply_byte_prefix.argtypes=[ctypes.c_uint,ctypes.c_ubyte];lib.apply_byte_prefix.restype=ctypes.c_ubyte
lib.symbol_payload if False else None
length=ctypes.c_int.in_dll(lib,'ass_image_length')
image=(ctypes.c_ubyte*11264).in_dll(lib,'ass_image')
seed=random.Random(102)
case_count=0
for n in [0,1,255,256,257,1023,4095,11262,11263,11264,11265,32767]+[seed.randrange(0,32768) for _ in range(600)]:
 value=seed.randrange(256)
 length.value=n
 if n<11264:image[n]=0xc7
 expected=int(lib.stage_byte(value))
 exp_length=length.value
 exp_byte=image[n] if n<11264 else None
 cpu=CPU((p/'whole_corpus'/'stage_byte.cross.asm').read_text(),[],{}, {})
 cpu.bases['ass_image']=0x4000
 cpu.mem.update({'ass_image_length':n&255,'ass_image_length+1':(n>>8)&255,'value':value,'assemble_ok':0,'assemble_work_full':11})
 cpu.heap.update({0x4000+n:0xc7} if n<11264 else {})
 actual,mem,calls=cpu.run(max_steps=3000)
 got_n=mem['ass_image_length'] | mem['ass_image_length+1']<<8
 got_val=cpu.heap.get(0x4000+n) if n<11264 else None
 assert (actual,got_n,got_val)==(expected,exp_length,exp_byte),(n,value,(actual,got_n,got_val),(expected,exp_length,exp_byte))
 case_count+=1
print('stage_byte exact C versus emitted 6502',case_count,'passed')
for v in [0,1,255,256,32767,32768,65535]+[seed.randrange(65536) for _ in range(400)]:
 for prefix in (1,2):
  expected=int(lib.apply_byte_prefix(v,prefix))
  cpu=CPU((p/'whole_corpus'/'apply_byte_prefix.cross.asm').read_text(),[],{}, {})
  cpu.mem.update({'value':v&255,'value+1':(v>>8)&255,'prefix':prefix,'value_prefix_low':1})
  actual,mem,calls=cpu.run(max_steps=3000)
  assert actual==expected,(v,prefix,actual,expected)
  case_count+=1
print('apply_byte_prefix exact C versus emitted 6502',case_count,'total passed')
