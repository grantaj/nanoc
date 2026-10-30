import random,ctypes
from pathlib import Path
from tape_frontend import TapeBuilder
from tape_vm import VM
from backend4 import IndexedBackend
from execute6502 import relax,CPU
SRC=Path(__file__).with_name('parse_atom.c').read_text();t=TapeBuilder(SRC).build()
b=IndexedBackend(t,{'symbol_kind':('u8',896),'symbol_payload':('s16',896)})
asm=b.run();code,bytecount,nrelax=relax(asm)
Path(__file__).with_name('parse_atom_demand_relaxed.asm').write_text(code)
lib=ctypes.CDLL(str(Path(__file__).with_name('oracle.so')))
lib.parse_atom.argtypes=[ctypes.c_void_p,ctypes.c_uint8];lib.parse_atom.restype=ctypes.c_uint8
def ci(n):return ctypes.c_int.in_dll(lib,n)
def cb(n):return ctypes.c_uint8.in_dll(lib,n)
stat={'VALUE_BAD':1,'VALUE_OK':0,'VALUE_SCOPE_ERROR':4,'VALUE_SYMBOL_FULL':3,
 'VALUE_UNRESOLVED':2,'SYMBOL_LABEL_UNDEFINED':9}
rng=random.Random(8151)
checks=0;kindcounts={};max_steps=0
for trial in range(1200):
 n=rng.randrange(0,70)
 if trial%13==0:n=rng.randrange(180,256)
 s=bytes(rng.choice([ord(x) for x in '0123456789abcdefABCDEFxy$+-\x27']) for _ in range(n))
 if trial%11==0:s=b'$'+b'ff'
 if trial%11==1:s=b'1234567'
 if trial%11==2:s=b'hello'
 if trial%11==3:s=b"'A'"
 if trial%11==4:s=b'$ffff'
 if trial%11==5:s=b'1+2'
 s=s[:255]
 fm=trial%3;im=trial%4;fidx=rng.randrange(896);iidx=rng.randrange(896)
 fk=rng.choice([2,9]); payload=rng.randrange(65536)
 kind=[0]*896;words=[0]*896
 kind[fidx]=fk;kind[iidx]=fk;words[fidx]=payload;words[iidx]=payload
 ci('find_mode').value=fm;ci('intern_mode').value=im
 ci('found_idx').value=fidx;ci('intern_idx').value=iidx
 ci('find_calls').value=ci('intern_calls').value=ci('hex_calls').value=0
 ctypes.memmove(ctypes.addressof((ctypes.c_uint8*896).in_dll(lib,'symbol_kind')),bytes(kind),896)
 ctypes.memmove(ctypes.addressof((ctypes.c_int*896).in_dll(lib,'symbol_payload')),(ctypes.c_int*896)(*words),896*ctypes.sizeof(ctypes.c_int))
 text_addr=0x30fd if trial%3==0 else (0x30ff if trial%3==1 else 0x3000)
 ini={**stat,'text':text_addr,'length':len(s),'atom_used':23,'atom_value':12345,'atom_kind':12,'atom_symbol':-1,
      'i':42,'digit':123,'symbol':-1,'value':0}
 def hx(c):
   ch=chr(c);return int(ch,16) if ch in '0123456789abcdefABCDEF' else 65535
 def find(p,ln):return (65535,fidx,65534)[fm]
 def intern(p,ln):return (65535,iidx,65534,65533)[im]
 calls={'hex_nibble':hx,'find_symbol':find,'intern_label':intern,'arrays':{'symbol_kind':kind,'symbol_payload':words}}
 cpu=CPU(code,s+b'\0\0\0',ini,calls,text_base=text_addr)
 got,out,called=cpu.run()
 buf=ctypes.create_string_buffer(s+b'\0\0\0')
 cb('atom_used').value=23;ctypes.c_uint.in_dll(lib,'atom_value').value=12345;cb('atom_kind').value=12;ci('atom_symbol').value=-1
 want=lib.parse_atom(buf,len(s))
 observ={'atom_used':cb('atom_used').value,'atom_value':ctypes.c_uint.in_dll(lib,'atom_value').value,
         'atom_kind':cb('atom_kind').value,'atom_symbol':ci('atom_symbol').value&65535}
 achieved={n:out.get(n,0)+(out.get(n+'+1',0)<<8 if n in ('atom_value','atom_symbol') else 0) for n in observ}
 expected_calls={'hex_nibble':ci('hex_calls').value,'find_symbol':ci('find_calls').value,
                 'intern_label':ci('intern_calls').value}
 if got!=want or achieved!=observ or any(called.get(n,0)!=k for n,k in expected_calls.items()):
  raise AssertionError((trial,s,got,want,achieved,observ,called,expected_calls,cpu.steps, {z:out.get(z) for z in ['symbol','symbol+1','__v164','__v164+1','__v167','__v167+1']},cpu.trace[-85:]))
 checks+=1;max_steps=max(max_steps,cpu.steps)
 kindcounts[trial%11]=kindcounts.get(trial%11,0)+1
print('PASS MACHINE',checks,'native-C differential cases; machine bytes',bytecount,'long branch expansion',nrelax,'max steps',max_steps)
