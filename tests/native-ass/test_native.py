#!/usr/bin/env python3
"""Differential tests for the native-structured Phase-1 C assembler.

Compiles both genuine C sources with a host C compiler, supplies only I/O,
and compares return statuses and exact output bytes for successful programs.
Different failure points can legitimately leave different partial outputs.

No Python assembler, duplicate parser, or private test implementation.
"""
import ctypes
import random
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADAPTER = ROOT / 'tests' / 'native-ass' / 'host_adapter.c'


def programs():
    p = {
        'simple_code': b'* = $0800\nlda #$12\nldx #$00\nsta $c000\nrts\n',
        'all_data': b'* = $0800\nbyte 1,2,3,4\nword $1234,$ffff\nstring "hello"\n',
        'labels': b'* = $0800\nstart: lda #1\nbeq done\nlda #2\ndone: rts\n',
        'comment': b';comment\n* = $0800 ; origin\nbyte 3, 4 ; bytes\n',
        'symbol_const': b'* = $0800\nnumber = $1234\nword number\nbyte <number,>number\n',
        'symbol_arith': b'* = $0800\nnumber = $1234\nword number+3,number-2\n',
        'forward_word': b'* = $0800\nword later\nbyte 9,8\nlater: rts\n',
        'forward_abs': b'* = $0800\njmp later\nlda #2\nlater: rts\n',
        'forward_branch': b'* = $0800\nbeq later\nlda #2\nlater: rts\n',
        'char_literal': b'* = $0800\nbyte \'A\',\'Z\'\n',
        'wrong_opcode': b'* = $0800\nzzz #0\n',
        'undefined_label': b'* = $0800\nword missing\n',
        'bad_data': b'* = $0800\nbyte bad\n',
        'zero_page': b'* = $0800\nlda $02\nsta $fa\n',
        'indirect': b'* = $0800\nlda ($fc),y\nsta ($fe),y\n',
        'long_indexed': b'* = $0800\nlda $1234,x\nldx #$ff\nrts\n',
        'multiple_labels': b'* = $0800\nfirst: second: lda #$0a\n',
    }
    rng = random.Random(102)
    for k in range(12):
        lines = ['* = $0800', 'base = $%04x' % rng.randrange(65536)]
        for _ in range(5 + rng.randrange(10)):
            kind = rng.randrange(9)
            if kind == 0:
                lines.append('byte ' + ','.join(str(rng.randrange(256)) for _ in range(1 + rng.randrange(4))))
            elif kind == 1:
                lines.append('word base')
            elif kind == 2:
                lines.append('word base+%d' % rng.randrange(50))
            elif kind == 3:
                lines.append('lda #$%02x' % rng.randrange(256))
            elif kind == 4:
                lines.append('sta $%04x' % rng.randrange(65536))
            elif kind == 5:
                lines.append('rts')
            elif kind == 6:
                lines.append('; comment')
            elif kind == 7:
                lines.append('lda $%04x,y' % rng.randrange(65536))
            else:
                lines.append('byte $%02x' % rng.randrange(256))
        p['random%02d' % k] = ('\n'.join(lines) + '\n').encode('ascii')
    return p


def assemble(lib, path):
    name = str(path).encode('ascii')
    result = lib.ass_assemble(name, len(name), b'', 0, 0)
    length = ctypes.c_int.in_dll(lib, 'ass_image_length').value
    image = bytes((ctypes.c_ubyte * 11264).in_dll(lib, 'ass_image'))[:length]
    return result, image


def run():
    with tempfile.TemporaryDirectory(prefix='native_phase1_') as td:
        d = Path(td)
        libs = []
        for native in (False, True):
            so = d / ('native.so' if native else 'original.so')
            subprocess.run(['cc', '-shared', '-fPIC', '-O0', '-std=c99',
                            '-funsigned-char', '-w', '-DNATIVE_ALGORITHM=%d' % int(native),
                            '-o', str(so), str(ADAPTER)], check=True, cwd=ROOT)
            lib = ctypes.CDLL(str(so))
            lib.ass_assemble.argtypes = [ctypes.c_char_p, ctypes.c_ubyte,
                                        ctypes.c_char_p, ctypes.c_ubyte, ctypes.c_uint]
            lib.ass_assemble.restype = ctypes.c_ubyte
            libs.append(lib)

        # For a failed assembly, native lifetime checking may report the
        # error earlier, hence different partial emitted bytes are expected.
        def compare(label, source):
            path = d / 'test.asm'
            path.write_bytes(source)
            old, new = (assemble(lib, path) for lib in libs)
            if old[0] != new[0] or (old[0] == 0 and old[1] != new[1]):
                raise AssertionError((label, old, new))
            return old, new

        for label, source in programs().items():
            compare(label, source)
        print('PASS 29/29 original complete assembler program cases')

        samples = {
            'reused_local': b'* = $0800\nglobal: word .fwd\n.fwd: rts\nsecond: word .fwd\n.fwd: rts\n',
            'local_unresolved': b'* = $0800\na: word .missing\nb: rts\n',
            'local_constants': b'* = $0800\na:\n.local = 3\nbyte .local\nb:\n.local = 5\nbyte .local\n',
            'word_chain': b'* = $0800\nword last,last,last\nlast: rts\n',
            'relative_fixup': b'* = $0800\nbeq end\nbyte 1\nend: rts\n',
            'mixed_fixups': b'* = $0800\nword later\nbyte <later,>later\nlater: rts\n',
            'reused_local_many': b'* = $0800\n' + b''.join(
                b'g%d: word .local\n.local: rts\n' % j for j in range(60)),
        }
        for label, source in samples.items():
            compare(label, source)
        print('PASS 7 named local-lifetime / word-chain / exceptional fixup cases')

        rng = random.Random(102)
        for k in range(200):
            lines = ['* = $0800']
            for j in range(rng.randrange(2, 15)):
                lines.append('g%d: word .local' % j)
                for _ in range(rng.randrange(1, 5)):
                    lines.append('byte ' + str(rng.randrange(256)))
                lines.append('.local: word g%d' % j)
            compare('scope%d' % k, ('\n'.join(lines) + '\n').encode())
        print('PASS 200 generated global/local/forward-reference programs')

        for label, source in [
            ('symbol_capacity', b'* = $0800\n' + b''.join(
                b's%d = %d\n' % (i, i) for i in range(950))),
            ('many_locals', b'* = $0800\nmain: rts\n' + b''.join(
                b'.l%d = %d\n' % (i, i) for i in range(500))),
        ]:
            compare(label, source)
        print('PASS 2 symbol-capacity boundary cases')

        # Inspect native record representation rather than only emitted output.
        path = d / 'test.asm'
        path.write_bytes(b'* = $0800\nanswer = $1234\nword answer\n')
        result, image = assemble(libs[1], path)
        assert (result, image) == (0, b'\x34\x12')
        records = (ctypes.c_ubyte * 15616).in_dll(libs[1], 'symbol_records')
        assert bytes(records[:10]) == bytes([6, 0x34, 0x12, 0]) + b'answer'
        assert ctypes.c_int.in_dll(libs[1], 'symbol_global_end').value == 10
        assert ctypes.c_int.in_dll(libs[1], 'symbol_local_start').value == 15616
        assert ctypes.c_int.in_dll(libs[1], 'fixup_end').value == 0
        assert ctypes.c_int.in_dll(libs[1], 'ass_image_length').value == 2
        print('PASS packed-record bytes, global frontier and staging output contract')

        # Hard physical staging boundary: exactly 11,264 bytes fit, one more
        # must fail without advancing the cursor beyond the output buffer.
        for length, expected_status in ((11264, 0), (11265, 11)):
            lines = ['* = $0800']
            remaining = length
            while remaining:
                n = min(80, remaining)
                lines.append('byte ' + ','.join('0' for _ in range(n)))
                remaining -= n
            path.write_bytes(('\n'.join(lines) + '\n').encode())
            status, data = assemble(libs[1], path)
            assert status == expected_status, (length, status)
            assert len(data) == 11264, (length, len(data))
            assert data == bytes(11264)
        print('PASS 11,264-byte physical staging boundary and one-byte overflow')

        # 640 exceptional byte fixups fit; the next append fails cleanly.
        # Explicit <label form forces exceptional fixups rather than word chains.
        for count, expected_status in ((640, 0), (641, 11)):
            program = b'* = $0800\n' + b'byte <later\n' * count + b'later: rts\n'
            path.write_bytes(program)
            status, data = assemble(libs[1], path)
            assert status == expected_status, (count, status)
            if status == 0:
                assert data == bytes([0x80] * count + [0x60]), len(data)
        print('PASS 640 exceptional-fixup entries and one-record overflow')


if __name__ == '__main__':
    run()
