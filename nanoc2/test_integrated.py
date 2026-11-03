"""Exercise source->semantic tape->6502 via nanoc1's original parser.

The old C-written compiler remains unchanged and independently tested; this
new file drives the byte-only replacement path under development.
"""
import pathlib
import re
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
source = (root / 'nanoc1' / 'nanoc1.c').read_text()


def function(name):
    match = re.search(r'^(?:char|int)\s+' + name + r'\s*\([^)]*\)\s*\{', source, re.M)
    if not match:
        raise AssertionError('Missing original C function ' + name)
    pos, depth = match.end(), 1
    while depth:
        if source[pos] == '{': depth += 1
        if source[pos] == '}': depth -= 1
        pos += 1
    return source[match.start():pos]


with tempfile.TemporaryDirectory() as tmp:
    binary = pathlib.Path(tmp) / 'nanoc2-host'
    subprocess.run(['cc', '-std=gnu99', '-funsigned-char', '-O0',
                    str(root / 'nanoc2' / 'integrated_driver.c'), '-o', str(binary)],
                   check=True)
    for name in ('same_bytes', 'find_global'):
        if name == 'same_bytes':
            ctext = function(name)
        else:
            # Exact declarations copied from the original compiler, not tests.
            names = ('global_name', 'global_name_len', 'token_text',
                     'token_length', 'global_count')
            decls = []
            for v in names:
                m = re.search(r'^char\s+' + v + r'(?:\[\d+\])?\s*;', source, re.M)
                assert m, v
                decls.append(m.group())
            ctext = '\n'.join(decls) + '\n' + function(name)
        p = subprocess.run([str(binary)], input=ctext.encode(),
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if p.returncode:
            raise AssertionError(f'{name}: compiler exited {p.returncode}: {p.stderr.decode()}')
        asm = p.stdout.decode()
        (pathlib.Path(tmp) / (name + '.asm')).write_text(asm)
        assert 'jsr __nc_mul16' not in asm.lower(), name
        assert '.L' in asm, name
        assert 'rts' in asm.lower(), name
        print(name + ': parsed by original compiler, machine body produced')

    # Fail closed on expressions not yet supported by the new emitter.
    bad = function('same_bytes').replace('i = i + 1;', 'i = i + 2;')
    p = subprocess.run([str(binary)], input=bad.encode(), stdout=subprocess.DEVNULL,
                       stderr=subprocess.PIPE)
    assert p.returncode != 0, 'unsupported expression accepted'
    print('Unsupported induction expression rejected')
