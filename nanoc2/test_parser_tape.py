"""Verify that the *original nanoc1 semantic parser* records source events.
This checks semantic tape capture only. Machine execution remains in the
source-to-machine test until the event lowerer takes over.
"""
import pathlib
import re
import subprocess

ROOT = pathlib.Path(__file__).parent
SOURCE = (ROOT.parent/"nanoc1"/"nanoc1.c").read_text()
DRIVER = ROOT/"parser_tape_driver"

def function(name):
    m = re.search(r'^char\s+'+re.escape(name)+r'\s*\([^)]*\)\s*\{', SOURCE, re.M)
    assert m, name
    depth=1
    pos=m.end()
    while depth:
        if SOURCE[pos]=='{': depth+=1
        if SOURCE[pos]=='}': depth-=1
        pos+=1
    return SOURCE[m.start():pos]

subprocess.run(["cc","-std=c99","-funsigned-char","-O0",
                str(ROOT/"parser_tape_driver.c"),"-o",str(DRIVER)],check=True)

decls = []
for name in ("global_name","global_name_len","token_text","token_length","global_count"):
    m = re.search(r'^char\s+'+re.escape(name)+r'(?:\[\d+\])?\s*;', SOURCE,re.M)
    assert m, name
    decls.append(m.group())

for name,prelude in [
    ("same_bytes",""),
    ("find_global","\n".join(decls)+"\n"),
]:
    c = prelude + function(name) + "\n"
    result=subprocess.run([str(DRIVER),'dump'],input=c.encode(),capture_output=True)
    assert result.returncode == 0, (name,result.stderr.decode())
    records=result.stdout.decode().splitlines()
    hdr=records[0].split()
    nodes=int(hdr[1]); events=int(hdr[3])
    assert nodes > 10 and events > 8, (name,nodes,events)
    assert sum(r.startswith("E ") for r in records)==events
    assert any(r.startswith("E ") and r.split()[2]=="3" for r in records)
    assert any(r.startswith("N ") and r.split()[2]=="4" for r in records),name
    assert any(r.startswith("E ") and r.split()[2]=="5" for r in records),name
    print(f"{name}: original parser recorded {nodes-1} semantic nodes, {events} control/assignment events")

# A semantically illegal source must be rejected by the same Phase-1 parser.
bad=function("same_bytes").replace("i = i + 1;", "i = a;")
result=subprocess.run([str(DRIVER)],input=bad.encode(),capture_output=True)
assert result.returncode != 0, "invalid byte <- pointer assignment accepted"
print("original Phase-1 type rejection passed")

# The native emitter uses the same parser, but this first ABI stage deliberately
# handles one function and uninitialized BSS only. Reject unsupported units
# before treating their emitted assembly as a complete program.
for candidate in (
    "char initialized = 7; char first() { return 1; }",
):
    result=subprocess.run([str(DRIVER),'native'],input=candidate.encode(),
                          capture_output=True)
    assert result.returncode != 0, "unsupported native translation unit accepted"
print("native ABI initialized-data rejection passed")

# Multiple functions no longer require keeping their previous semantic tapes
# in memory. All definitions must be present in one generated assembly unit.
r = subprocess.run(
    [str(DRIVER), 'native'],
    input=b'char first() { return 1; } char second() { return 2; }',
    capture_output=True)
assert r.returncode == 0, r.stderr.decode()
generated = r.stdout.decode()
assert generated.count('\n\trts\n') == 2, generated
assert generated.count('\n__c') >= 2
print("original parser streamed two independent functions correctly")

# Calls with zero and two byte parameters use the same original parser and
# the same static argument ABI. Reject wrong counts before machine emission.
arity = (ROOT.parent/"tests"/"nanoc2"/"call-arity.c").read_text()
ok = subprocess.run([str(DRIVER),"native"],input=arity.encode(),
                    capture_output=True)
assert ok.returncode == 0, ok.stderr.decode()
assert sum(line.strip()=="rts" for line in ok.stdout.decode().splitlines()) >= 3
for bad in (
    arity.replace("guarded(call_source[i], 90)",
                  "guarded(call_source[i])"),
    arity.replace("guarded(call_source[i], 90)",
                  "guarded(call_source[i], 90, 91)"),
    arity.replace("return constant();",
                  "return constant(90);"),
):
    result = subprocess.run([str(DRIVER),"native"],input=bad.encode(),
                            capture_output=True)
    assert result.returncode != 0, "invalid function call count accepted"
print("original parser: zero/two-byte calls, argument count rejection passed")
