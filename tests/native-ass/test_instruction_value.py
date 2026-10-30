#!/usr/bin/env python3
"""Compare native-structured instruction/value decoding against original ass.c.

Both tested assemblers are genuine Phase-1 C compiled by the host. This script
contains test input generation and output comparisons, not a shadow assembler.
"""
import ctypes
import random
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADAPTER = ROOT / 'tests/native-ass/host_adapter.c'


def compile_assembler(root, destination, native):
    subprocess.run(['cc', '-shared', '-fPIC', '-O0', '-std=c99',
                    '-funsigned-char', '-w',
                    '-DNATIVE_ALGORITHM=%d' % native,
                    '-o', str(destination), str(ADAPTER)],
                   cwd=root, check=True)
    lib = ctypes.CDLL(str(destination))
    lib.ass_assemble.argtypes = [ctypes.c_char_p, ctypes.c_ubyte,
                                 ctypes.c_char_p, ctypes.c_ubyte, ctypes.c_uint]
    lib.ass_assemble.restype = ctypes.c_ubyte
    return lib


def assemble(lib, source_path):
    path = str(source_path).encode('ascii')
    code = lib.ass_assemble(path, len(path), b'', 0, 0)
    length = ctypes.c_int.in_dll(lib, 'ass_image_length').value
    data = bytes((ctypes.c_ubyte * 11264).in_dll(lib, 'ass_image'))[:length]
    return code, data


def cases():
    # Instruction formats and value expressions follow ass/instruction.asm and
    # ass/value.asm. Forward labels exercise the native captured-fixup path.
    fixed = {
        'accumulator': b'* = $0800\nasl a\nror A\n',
        'implied': b'* = $0800\nclc\nrts\n',
        'immediate': b'* = $0800\nlda #255\nldx #$ff\n',
        'zero_page': b'* = $0800\nlda $00\nsta $ff\n',
        'absolute': b'* = $0800\nlda $0100\nsta $ffff\n',
        'x_y_indexed': b'* = $0800\nlda $10,x\nldx $20,y\nsta $1234,y\n',
        'indirect_x': b'* = $0800\nlda ($fd,X)\n',
        'indirect_y': b'* = $0800\nlda ($fd),Y\n',
        'indirect_absolute': b'* = $0800\njmp ($1234)\n',
        'relative_known': b'* = $0800\nbeq $0805\nbyte 1,2,3\nrts\n',
        'relative_forward': b'* = $0800\nbeq end\nbyte 1,2\nend: rts\n',
        'relative_backward': b'* = $0800\nloop: byte 0\nbne loop\n',
        'plain_word_chain': b'* = $0800\njmp last\nword last,last\nlast: rts\n',
        'low_high_selector': b'* = $0800\nlda #<last\nldx #>last\nbyte <last,>last\nlast: rts\n',
        'explicit_zp_reference': b'* = $0800\nlda <last\nlast: rts\n',
        'symbol_addend': b'* = $0800\nlda #<last+3\nword last-2\nlast: rts\n',
        'numeric_expressions': b'* = $0800\nword 65535,65536,17+3,$0f-2\n',
        'character_atoms': b'* = $0800\nlda #\'A\'\nbyte \'Z\'\n',
        'bad_mode': b'* = $0800\nsta #$12\n',
        'bad_index': b'* = $0800\nlda ($fd,y)\n',
        'bad_byte_operand': b'* = $0800\nlda ($1234),y\n',
        'bad_immediate': b'* = $0800\nlda #$1234\n',
        'bad_relative_range': b'* = $0800\nbeq too_far\n' + b'byte 0\n' * 140 + b'too_far: rts\n',
        'bad_extra_operator': b'* = $0800\nword 1+2+3\n',
        'unknown_mnemonic': b'* = $0800\nxyz #1\n',
    }
    for name, source in fixed.items():
        yield name, source

    rng = random.Random(127)
    operands = ['#$%02x', '$%04x', '$%02x,x', '$%04x,y',
                'number', 'number+3', '<number', '>number']
    mnem = ['lda', 'ldx', 'ldy', 'adc', 'and', 'ora', 'sta', 'jmp', 'beq', 'bne']
    for trial in range(400):
        source = ['* = $0800', 'number = $%04x' % rng.randrange(65536)]
        for _ in range(rng.randrange(1, 17)):
            op = rng.choice(mnem)
            fmt = rng.choice(operands)
            if '%' in fmt:
                width = 256 if '%02x' in fmt else 65536
                operand = fmt % rng.randrange(width)
            else:
                operand = fmt
            source.append(op + ' ' + operand)
        source.append('rts')
        yield 'generated-%03d' % trial, ('\n'.join(source) + '\n').encode()


def run():
    with tempfile.TemporaryDirectory(prefix='native_instruction_') as folder:
        directory = Path(folder)
        old = compile_assembler(ROOT, directory / 'old.so', 0)
        new = compile_assembler(ROOT, directory / 'new.so', 1)
        path = directory / 'test.asm'
        tested = 0
        for name, source in cases():
            path.write_bytes(source)
            old_code, old_data = assemble(old, path)
            new_code, new_data = assemble(new, path)
            if old_code != new_code or (old_code == 0 and old_data != new_data):
                raise AssertionError((name, old_code, new_code,
                                      old_data.hex(), new_data.hex()))
            tested += 1
        assert tested == 425, tested
        print('PASS %d instruction/value fixtures and generated programs' % tested)


if __name__ == '__main__':
    run()
