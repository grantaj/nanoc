"""Independent research: exact cost search across alternative 6502 address plans.

The problem is deliberately narrow: read N independent 16-bit fields at
(base_k + 2*i), where 'i' is unchanged.  Strategies include recomputing an
address or retargeting the current 16-bit cursor by an integral-page delta.
The latter is legal only when base low bytes are equal.  A call/effect barrier
may force dropping the cursor, which is modelled explicitly.

This tests the missing *relational representation*, NOT production lowering.
"""
from __future__ import annotations
import sys
from pathlib import Path
from functools import lru_cache
from itertools import permutations
import random,json
sys.path.insert(0,str(Path(__file__).parent))
from address_relation_probe import BASES, FIELDS, Machine, build_independent, ins_size

# Keep these recipes transparent for inspection by a 6502 programmer.
def prepare(base):
    return ['lda i','asl','sta __ix','lda i+1','rol','sta __ix+1',
       'clc','lda __ix',f'adc #${base&255:02x}','sta __ap',
       'lda __ix+1',f'adc #${base>>8:02x}','sta __ap+1']

def retarget(src,dst):
    if (src&255)!=(dst&255): return None
    delta=((dst-src)>>8)&255
    return ['clc','lda __ap+1',f'adc #${delta:02x}','sta __ap+1']

def fetch(k):
    return ['ldy #$00','lda (__ap),y',f'sta out{k}',
            'iny','lda (__ap),y',f'sta out{k}+1']

def cost(code):return sum(ins_size(x) for x in code)

def solve(bases,barriers=()):
    """Bitmask DP: (remaining field bits, last cursor field or None).
    A barrier immediately *before* a field invalidates any cached pointer.
    The field read order is fixed by source effects, except this pure test's
    mutually independent reads where exhaustive ordering is allowed.
    """
    n=len(bases)
    @lru_cache(None)
    def go(mask,last):
        if mask==(1<<n)-1: return (0,())
        best=(10**9,())
        for k in range(n):
            if (mask>>k)&1:continue
            prior=last if k not in barriers else -1
            variants=[('fresh',prepare(bases[k]))]
            if prior>=0 and retarget(bases[prior],bases[k]) is not None:
                variants.append(('retarget',retarget(bases[prior],bases[k])))
            for name,setup in variants:
                sub_cost,sub_plan=go(mask|(1<<k),k)
                expense=cost(setup)+cost(fetch(k))+sub_cost
                if expense<best[0]:best=(expense,((k,name,tuple(setup)),)+sub_plan)
        return best
    return go(0,-1)

def run_experiment():
    optimal,plan=solve(BASES)
    original=build_independent()
    lines=[]
    for k,decision,setup in plan:lines+=list(setup)+fetch(k)
    assert cost(lines)==optimal
    assert set(k for k,_,_ in plan)==set(range(len(BASES)))
    assert optimal<cost(original)
    rnd=random.Random(20261030)
    tests=0
    for i in range(640):
        for trial in range(3):
            data=tuple(rnd.randrange(256) for _ in range(6))
            target=[data[j*2]+(data[j*2+1]<<8) for j in range(3)]
            assert Machine(i,data).run(lines)==target,(i,data)
            assert Machine(i,data).run(original)==target,(i,data)
            tests+=1
    # Semantics guard: different base low-byte must not be patched by high-only ADC.
    assert retarget(BASES[0],BASES[0]+1) is None
    # Breaking the cursor by an intervening opaque call forces fresh formation.
    # In this example a fixed order permits directly comparing possible barriers.
    fresh_cost=cost(prepare(BASES[0])+fetch(0))
    call_barrier_cost=fresh_cost+cost(prepare(BASES[1])+fetch(1))
    optimized_two_cost=cost(prepare(BASES[0])+fetch(0)+retarget(BASES[0],BASES[1])+fetch(1))
    assert call_barrier_cost>optimized_two_cost
    result={'fields':list(FIELDS),'addresses':[hex(x) for x in BASES],
        'baseline_fragment_bytes':cost(original),
        'optimal_affine_fragment_bytes':optimal,
        'local_difference_before_outlining':cost(original)-optimal,
        'optimum_decisions':[(FIELDS[k],d) for k,d,_ in plan],
        'machine_tests_per_strategy':tests,
        'two_fields_with_preserved_pointer_bytes':optimized_two_cost,
        'two_fields_with_forced_clobber_bytes':call_barrier_cost,
        'notes':['This is a pure independent 3-field load fragment, not the full resolve_fixups_for_symbol function',
                 'A call or interfering store invalidates the cursor unless a stronger alias/calling-convention proof exists',
                 'The current outliner already compresses repeated address constructors, so pre-outline savings cannot be added to linked savings']}
    dest=Path(__file__).with_name('affine_search_results.json')
    dest.write_text(json.dumps(result,indent=2)+'\n')
    Path(__file__).with_name('affine_search_6502.asm').write_text('; Cost-optimal under the stated address recipes, independent loads only\n'+'\n'.join(lines)+'\n')
    return result

if __name__=='__main__':print(json.dumps(run_experiment(),indent=2))
