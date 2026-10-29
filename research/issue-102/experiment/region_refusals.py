from full_corpus.tape_frontend import TapeBuilder
from full_corpus.direct_address import DirectAddressBackend
import json
s=open('full_corpus/whole_corpus/find_symbol.c').read()
arr=json.load(open('full_corpus/whole_corpus/arrays.json'))
probes={
 'original':(s,True),
 'mutable_offset':(s.replace('same = 0;', 'offset = offset + 1; same = 0;'),False),
 'call_in_loop':(s.replace('same = 0;', 'dummy(); same = 0;').replace('int find_symbol(', 'int dummy();\nint find_symbol('),False),
 'bound_changes':(s.replace('same = 0;', 'length = length - 1; same = 0;'),False),
 'pointer_rebound':(s.replace('same = 0;', 'name = name + 1; same = 0;'),False),
 'nonunit_step':(s.replace('j = j + 1;', 'j = j + 2;'),False),
}
for name,(c,expected) in probes.items():
 try:
  t=TapeBuilder(c).build();b=DirectAddressBackend(t,arr)
  actual=any(p.offset_bases for p in b.dual_plans)
  assert actual==expected,(name,actual)
  print('PASS',name,'plan:',actual)
 except Exception as e:
  print('FAIL',name,type(e).__name__,e)
  raise
