"""Indexed byte write tests: original Nano C parser -> C tape -> 6502.

The same committed C fixture is compiled by GCC as the independent oracle.
Test-ABI zero-page pointer homes are supplied by this harness, not by nanoc2.
"""
import ctypes
import pathlib
import random
import re
import subprocess
import tempfile

from test_6502 import Machine

ROOT = pathlib.Path(__file__).parent
FIXTURE = (ROOT.parent / 'tests' / 'nanoc2' / 'indexed-write.c').read_text()
DECLS = "char source_bytes[256];\nchar dest_bytes[256];\n"

def function(name):
    m = re.search(r'^char\s+' + re.escape(name) + r'\s*\([^)]*\)\s*\{',
                  FIXTURE, re.M)
    assert m, name
    level = 1
    end = m.end()
    while level:
        if FIXTURE[end] == '{':
            level += 1
        if FIXTURE[end] == '}':
            level -= 1
        end += 1
    return FIXTURE[m.start():end]


def pointer(m, slot, address):
    where = m.addr[f'__tptr{slot:02x}']
    m.m[where] = address & 255
    m.m[where+1] = address >> 8


def compile_source(driver, name, text):
    p = subprocess.run([str(driver)], input=text.encode(), capture_output=True)
    if p.returncode:
        raise AssertionError((name, p.returncode, p.stderr.decode()))
    listing = p.stdout.decode()
    scalars, ptrs = {}, {}
    for line in p.stderr.decode().splitlines():
        fields = line.split()
        if len(fields) == 3 and fields[0] == 'NC2VAR':
            scalars[fields[1]] = int(fields[2])
        if len(fields) == 3 and fields[0] == 'NC2PTR':
            ptrs[fields[1]] = int(fields[2])
    assert re.search(r'^\s*sta\s+[^;\n]*[,][xy]', listing, re.M), (name, listing)
    return listing, scalars, ptrs


rng = random.Random(0x6510)
NAMES = ('copy_pointer', 'fill_pointer', 'clear_pointer',
         'copy_array', 'fill_array')
CASES_PER_ROUTINE = 650

with tempfile.TemporaryDirectory() as folder:
    folder = pathlib.Path(folder)
    exe = folder / 'nanoc2'
    subprocess.run(['cc', '-std=c99', '-funsigned-char', '-O0',
                    str(ROOT / 'parser_tape_driver.c'), '-o', str(exe)],
                   check=True)

    so = folder / 'oracle.so'
    oracle = folder / 'oracle.c'
    oracle.write_text(FIXTURE)
    subprocess.run(['cc', '-std=c99', '-funsigned-char', '-O0',
                    '-fPIC', '-shared', str(oracle), '-o', str(so)], check=True)
    lib = ctypes.CDLL(str(so))

    compiled = {}
    for name in NAMES:
        compiled[name] = compile_source(exe, name, DECLS + function(name))

    u8 = ctypes.c_ubyte
    ptr = ctypes.POINTER(u8)
    lib.copy_pointer.argtypes = [ptr, ptr, u8]
    lib.fill_pointer.argtypes = [ptr, u8, u8]
    lib.clear_pointer.argtypes = [ptr, u8]
    lib.copy_array.argtypes = [u8]
    lib.fill_array.argtypes = [u8, u8]
    for name in NAMES:
        getattr(lib, name).restype = u8

    c_source = (u8 * 256).in_dll(lib, 'source_bytes')
    c_dest = (u8 * 256).in_dll(lib, 'dest_bytes')
    values = (0, 1, 2, 15, 16, 127, 128, 254, 255)

    for name in NAMES:
        listing, scalars, ptrs = compiled[name]
        for q in range(CASES_PER_ROUTINE):
            n = values[q % len(values)] if q < 90 else rng.randrange(256)
            value = rng.randrange(256)
            source = bytes(rng.randrange(256) for _ in range(256))
            dest = bytes(rng.randrange(256) for _ in range(256))
            for j in range(256):
                c_source[j] = source[j]
                c_dest[j] = dest[j]

            if name == 'copy_pointer':
                cb_dst = (u8 * 256).from_buffer_copy(dest)
                cb_src = (u8 * 256).from_buffer_copy(source)
                expected = lib.copy_pointer(cb_dst, cb_src, n)
                expected_bytes = bytes(cb_dst)
            elif name == 'fill_pointer':
                cb_dst = (u8 * 256).from_buffer_copy(dest)
                expected = lib.fill_pointer(cb_dst, n, value)
                expected_bytes = bytes(cb_dst)
            elif name == 'clear_pointer':
                cb_dst = (u8 * 256).from_buffer_copy(dest)
                expected = lib.clear_pointer(cb_dst, n)
                expected_bytes = bytes(cb_dst)
            elif name == 'copy_array':
                expected = lib.copy_array(n)
                expected_bytes = bytes(c_dest)
            else:
                expected = lib.fill_array(n, value)
                expected_bytes = bytes(c_dest)

            m = Machine(listing)
            for i in range(1, 32):
                m.addr[f'__v{i}'] = 0x30 + i
            m.addr['source_bytes'] = 0x61F1
            m.addr['dest_bytes'] = 0x724F
            m.m[0x61F1:0x61F1+256] = source
            m.m[0x724F:0x724F+256] = dest
            m.m[0x40F7:0x40F7+256] = source
            m.m[0x51F3:0x51F3+256] = dest
            for symbol, slot in ptrs.items():
                if symbol == 'src':
                    pointer(m, slot, 0x40F7)
                elif symbol == 'dst':
                    pointer(m, slot, 0x51F3)
                else:
                    raise AssertionError((name, symbol))
            for symbol, slot in scalars.items():
                if symbol == 'n':
                    m.m[m.addr[f'__v{slot}']] = n
                elif symbol == 'value':
                    m.m[m.addr[f'__v{slot}']] = value
                elif symbol != 'i':
                    raise AssertionError((name, symbol))

            actual, steps = m.run(400000)
            if name.endswith('_pointer'):
                actual_bytes = bytes(m.m[0x51F3:0x51F3+256])
            else:
                actual_bytes = bytes(m.m[0x724F:0x724F+256])
            assert actual == expected and actual_bytes == expected_bytes, (
                name, q, n, value, actual, expected,
                next((i for i, (a, b) in
                      enumerate(zip(actual_bytes, expected_bytes)) if a != b),
                     None))
        print(f'{name}: {CASES_PER_ROUTINE} actual-C / 6502 comparisons passed')

    # The original parser can parse these expressions, but the byte-only
    # backend must reject them until it supports their real semantics.
    bad = (
        function('copy_pointer').replace('dst[i] = src[i];',
                                         'dst[i + 1] = src[i];'),
        function('copy_pointer').replace('dst[i] = src[i];',
                                         'dst[i] = src[i] + 1;')
    )
    for source in bad:
        p = subprocess.run([str(exe)], input=source.encode(),
                           capture_output=True)
        assert p.returncode != 0, 'unsupported indexed assignment accepted'
    print('3,250 indexed-write semantic/machine checks plus rejection checks passed')
