"""Adversarial proof tests for the general indexed-address state model."""
from pathlib import Path
from tape_frontend import TapeBuilder
from address_plan import AddressPlanBackend

prefix='''
char a[640];
char b[640];
char *p;
char side();
'''

def check(body,min_hit=0,max_hit=None):
    t=TapeBuilder(prefix+'char f(int i) { char x; char y; '+body+' }').build()
    b=AddressPlanBackend(t,{'a':('u8',640),'b':('u8',640)})
    code=b.run()
    hits=b.index_hits+b.address_hits
    assert hits>=min_hit and (max_hit is None or hits<=max_hit),(hits,body)
    return hits,code

# Two separate arrays indexed by the same 16-bit scalar can share __ix.
assert check('x=a[i]; y=b[i]; return x+y;',min_hit=1)[0]>=1
# The first indexed store into a known distinct array does not change i.
assert check('a[i]=3; b[i]=4; return a[i];',min_hit=1)[0]>=1
# Changing i makes the previous scaled index invalid.
assert check('x=a[i]; i=i+1; y=b[i]; return x+y;',max_hit=0)[0]==0
# An arbitrary pointer write can alter i or p itself.
assert check('x=a[i]; p[0]=4; y=b[i]; return x+y;',max_hit=0)[0]==0
# Calls may mutate i and clobber __ix / __ap.
assert check('x=a[i]; side(); y=b[i]; return x+y;',max_hit=0)[0]==0
# Opposite incoming edges cannot be merged without a must-state meet.
assert check('if(i<3){x=a[i];}else{x=b[i];} y=b[i]; return x+y;',max_hit=0)[0]==0
print('PASS six array-address machine-residency proof/refusal cases')
