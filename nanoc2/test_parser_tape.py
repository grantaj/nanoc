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

# The word slice uses the same original Phase-1 typed nodes and static BSS
# slots. Complete 16-bit arithmetic remains an explicit unsupported case.
word = (ROOT.parent/"tests"/"nanoc2"/"word-scalar.c").read_text()
result = subprocess.run([str(DRIVER),"native"],input=word.encode(),
                        capture_output=True)
assert result.returncode == 0, result.stderr.decode()
out = result.stdout.decode()
assert "ldx #$12" in out and "sta __g" in out and "+1" in out
assert "\tadc #$FF" in out and "\tsbc #$01" in out
invalid = word.replace("local = 4660;", "local = local * 2;")
result = subprocess.run([str(DRIVER),"native"],input=invalid.encode(),
                        capture_output=True)
assert result.returncode != 0, "unsupported 16-bit multiplication silently accepted"
print("original parser: typed 16-bit scalars, add/sub literals and multiplication rejection passed")

# Word arithmetic and comparisons must be emitted by the *same* parser path.
# Unsupported word multiply remains rejected, not rerouted to legacy output.
word_ops = (ROOT.parent/"tests"/"nanoc2"/"word-ops.c").read_text()
result = subprocess.run([str(DRIVER),"native"],input=word_ops.encode(),
                        capture_output=True)
assert result.returncode == 0, result.stderr.decode()
assembly = result.stdout.decode()
assert "INVALID_HOME" not in assembly, "unmapped native operand emitted"
assert "adc " in assembly and "sbc " in assembly
assert "eor #$80" in assembly
for rel in ("bne", "bcc", "bcs"):
    assert rel in assembly
unsupported = word_ops.replace("return left + right;", "return left * right;")
result = subprocess.run([str(DRIVER),"native"],input=unsupported.encode(),
                        capture_output=True)
assert result.returncode != 0, "unsupported two-word multiplication silently accepted"
print("original parser: word arithmetic and signed/unsigned branch lowering passed")

# Word-call tests exercise source-streaming multiple real functions, two-byte
# parameter homes and caller X/Y reconciliation, with wrong arity rejected.
word_call = (ROOT.parent/"tests"/"nanoc2"/"word-call.c").read_text()
result = subprocess.run([str(DRIVER),"native"],input=word_call.encode(),
                        capture_output=True)
assert result.returncode == 0, result.stderr.decode()
assembly = result.stdout.decode()
assert "INVALID_HOME" not in assembly
assert "stx __trethi" in assembly and "ldx __trethi" in assembly
assert "sta __tret" in assembly
for incorrect in (
    word_call.replace("return pass_one(value);", "return pass_one(value, value);"),
    word_call.replace("return add_pair(4660, 1);", "return add_pair(4660);"),
):
    reject = subprocess.run([str(DRIVER),"native"],input=incorrect.encode(),
                            capture_output=True)
    assert reject.returncode != 0, "invalid wide-call arity accepted"
print("original parser: typed word arguments/returns and arity rejection passed")

# Mixed scalar widths and left-associated arithmetic share the same
# Phase-1 semantic capture. No alternate parser or text substitution.
mixed = (ROOT.parent/"tests"/"nanoc2"/"mixed-arithmetic.c").read_text()
compiled = subprocess.run([str(DRIVER),"native"],input=mixed.encode(),
                          capture_output=True)
assert compiled.returncode == 0, compiled.stderr.decode()
assembly = compiled.stdout.decode()
assert "INVALID_HOME" not in assembly
assert "sta __tacc" in assembly and "sta __tacc+1" in assembly
assert "adc #$00" in assembly and "sbc #$00" in assembly
# A right-nested expression is not a left-associated chain: it cannot be
# silently evaluated in the wrong order or with an overwritten operand.
for invalid in (
    mixed.replace("return wide + delta;", "return wide * delta;"),
    mixed.replace("return wide + delta;",
                  "return wide + (delta + 1);"),
):
    rejected = subprocess.run([str(DRIVER),"native"],input=invalid.encode(),
                              capture_output=True)
    assert rejected.returncode != 0, "unsupported expression silently accepted"
print("original parser: mixed widths, left-associated chains and strict rejections passed")

# Mixed-width numeric conditions must compare *full* integer widths:
# char is zero extended, signed word is biased only for ordering, and
# expressions with a literal on the left must not be reversed silently.
mixed_compare = (ROOT.parent/"tests"/"nanoc2"/"mixed-compare.c").read_text()
compiled = subprocess.run([str(DRIVER),"native"],input=mixed_compare.encode(),
                          capture_output=True)
assert compiled.returncode == 0, compiled.stderr.decode()
assembly = compiled.stdout.decode()
assert "INVALID_HOME" not in assembly
assert "\tcmp #$80" in assembly and "\teor #$80" in assembly
assert "\tcmp #$00" in assembly
assert "compare_marks" in assembly
# The pure-scalar numeric comparator deliberately does not invent semantics
# for a call or an expression tree inside its operands.
bad = mixed_compare.replace("if (word < byte)",
                            "if (word * 2 < byte)")
result = subprocess.run([str(DRIVER),"native"],input=bad.encode(),
                        capture_output=True)
assert result.returncode != 0, "composed comparison operand accepted incorrectly"
print("original parser: full-width mixed C comparisons and literal order passed")
