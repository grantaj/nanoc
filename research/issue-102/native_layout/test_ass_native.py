"""Differential tests for a Phase-1 C assembler with native-like records.

Run: python3 research/issue-102/native_layout/test_ass_native.py
Uses a host C compiler, not the nanoc 6502 backend. Checks behavior against
bootstrap/ass.c without assuming symbol IDs or fixup addresses are identical.
"""
from pathlib import Path
import ctypes
import random
import subprocess
import tempfile
import re

ROOT=Path(__file__).resolve().parents[3] if __file__.endswith('test_ass_native.py') and 'research' in Path(__file__).parts else Path(__file__).resolve().parent
SOURCES=[ROOT/'bootstrap/ass.c', ROOT/'bootstrap/ass_native.c']
HOST=(ROOT/'bootstrap/ass_host.c').read_text()


def load(path):
    c=ctypes.CDLL(str(path))
    c.ass_assemble.argtypes=(ctypes.c_char_p, ctypes.c_ubyte, ctypes.c_char_p, ctypes.c_ubyte, ctypes.c_uint)
    c.ass_assemble.restype=ctypes.c_ubyte
    c.reset_assembler.argtypes=(ctypes.c_uint, ctypes.c_char_p, ctypes.c_ubyte)
    c.reset_assembler.restype=ctypes.c_ubyte
    c.allocate_symbol.argtypes=(ctypes.c_char_p, ctypes.c_ubyte, ctypes.c_ubyte, ctypes.c_uint)
    c.allocate_symbol.restype=ctypes.c_int
    c.find_symbol.argtypes=(ctypes.c_char_p, ctypes.c_ubyte)
    c.find_symbol.restype=ctypes.c_int
    c.append_fixup.argtypes=(ctypes.c_ubyte, ctypes.c_int, ctypes.c_int, ctypes.c_uint, ctypes.c_ubyte)
    c.append_fixup.restype=ctypes.c_ubyte
    c.stage_byte.argtypes=(ctypes.c_ubyte,)
    c.stage_byte.restype=ctypes.c_ubyte
    c.define_label.argtypes=(ctypes.c_char_p, ctypes.c_ubyte, ctypes.c_uint)
    c.define_label.restype=ctypes.c_ubyte
    c.intern_label.argtypes=(ctypes.c_char_p, ctypes.c_ubyte)
    c.intern_label.restype=ctypes.c_int
    c.stage_plain_word_reference.argtypes=(ctypes.c_int,)
    c.stage_plain_word_reference.restype=ctypes.c_ubyte
    return c


def program_corpus():
    programs={
      'simple_code':b'* = $0800\nlda #$12\nldx #$00\nsta $c000\nrts\n',
      'all_data':b'* = $0800\nbyte 1,2,3,4\nword $1234,$ffff\nstring "hello"\n',
      'labels':b'* = $0800\nstart: lda #1\nbeq done\nlda #2\ndone: rts\n',
      'comment':b';comment\n* = $0800 ; origin\nbyte 3, 4 ; bytes\n',
      'symbol_const':b'* = $0800\nnumber = $1234\nword number\nbyte <number,>number\n',
      'symbol_arith':b'* = $0800\nnumber = $1234\nword number+3,number-2\n',
      'forward_word':b'* = $0800\nword later\nbyte 9,8\nlater: rts\n',
      'forward_abs':b'* = $0800\njmp later\nlda #2\nlater: rts\n',
      'forward_branch':b'* = $0800\nbeq later\nlda #2\nlater: rts\n',
      'char_literal':b'* = $0800\nbyte \'A\',\'Z\'\n',
      'wrong_opcode':b'* = $0800\nzzz #0\n',
      'undefined_label':b'* = $0800\nword missing\n',
      'bad_data':b'* = $0800\nbyte bad\n',
      'zero_page':b'* = $0800\nlda $02\nsta $fa\n',
      'indirect':b'* = $0800\nlda ($fc),y\nsta ($fe),y\n',
      'long_indexed':b'* = $0800\nlda $1234,x\nldx #$ff\nrts\n',
      'multiple_labels':b'* = $0800\nfirst: second: lda #$0a\n',
      'scope_local':b'* = $0800\nMain: lda #0\n.local: word Main\nword .local\nNext: byte 3\n.local: word .local\n',
      'many_forward_words':b'* = $0800\n'+b''.join(f'word S{i}\n'.encode() for i in range(80))+b''.join(f'S{i}: byte {i}\n'.encode() for i in range(80)),
      'many_fixups':b'* = $0800\n'+b''.join(f'byte <S{i}, >S{i}\n'.encode() for i in range(90))+b''.join(f'S{i}: byte {i}\n'.encode() for i in range(90)),
      'repeat_labels':b'* = $0800\n'+b''.join(f'name{i} = ${i:04x}\n'.encode() for i in range(80))+b'word name79\n',
      'offset_and_labels':b'* = $0800\nword a+2,a-1\nbyte <a,>a\na: byte 0\n',
      'first_local_bad':b'* = $0800\n.local: byte 1\n',
      'duplicate':b'* = $0800\nfoo: byte 1\nfoo: byte 2\n',
      'long_unresolved':b'* = $0800\n'+b''.join(f'word sym{i}\n'.encode() for i in range(200)),
      'many_unique_labels':b'* = $0800\n'+b''.join(f's{i}: byte {i&255}\n'.encode() for i in range(450)),
      'long_output':b'* = $0800\n'+b'byte 1,2,3,4\n'*1200,
      'bad_relative':b'* = $0800\nbeq far\n'+b'byte 0,1,2,3\n'*40+b'far: rts\n',
      'mixed_forward':b'* = $0800\n'+b''.join((f'word symbol{i}\nbyte <symbol{i}, >symbol{i}\n').encode() for i in range(90))+b''.join((f'symbol{i}: byte {i}\n').encode() for i in range(90)),
    }
    rng=random.Random(102)
    for k in range(60):
        lines=['* = $0800',f'base = ${rng.randrange(65536):04x}']
        for _ in range(4+rng.randrange(12)):
            op=rng.randrange(9)
            if op==0:lines.append('byte '+','.join(str(rng.randrange(256)) for _ in range(1+rng.randrange(4))))
            elif op==1:lines.append('word base')
            elif op==2:lines.append('word base+%d'%rng.randrange(50))
            elif op==3:lines.append('lda #$%02x'%rng.randrange(256))
            elif op==4:lines.append('sta $%04x'%rng.randrange(65536))
            elif op==5:lines.append('rts')
            elif op==6:lines.append('; comment')
            elif op==7:lines.append('lda $%04x,y'%rng.randrange(65536))
            else:lines.append('byte $%02x'%rng.randrange(256))
        programs[f'random{k:02d}']='\n'.join(lines).encode()+b'\n'
    return programs


def image(lib):
    n=ctypes.c_int.in_dll(lib,'ass_image_length').value
    data=(ctypes.c_ubyte*16384).in_dll(lib,'ass_image')
    return bytes(data[:n])


def main():
    with tempfile.TemporaryDirectory(prefix='nanoc_ass_native_') as temp:
        temp=Path(temp)
        libs=[]
        for i,src in enumerate(SOURCES):
            stage=temp/str(i);stage.mkdir()
            (stage/'ass.c').write_bytes(src.read_bytes())
            (stage/'host.c').write_text(HOST)
            dll=stage/'libass.so'
            subprocess.run(['cc','-std=c99','-funsigned-char','-O0','-w','-shared','-fPIC','-o',str(dll),str(stage/'host.c')],check=True)
            libs.append(load(dll))
        tested=0
        for name,payload in program_corpus().items():
            path=temp/'test.asm';path.write_bytes(payload)
            namebytes=str(path).encode()
            result=[(lib.ass_assemble(namebytes,len(namebytes),b'',0,0x800),image(lib)) for lib in libs]
            assert result[0]==result[1], (name, (result[0][0],len(result[0][1])),(result[1][0],len(result[1][1])),result[0][1][:30],result[1][1][:30])
            tested+=1
        print('PASS',tested,'whole assembler source/status/byte comparisons')
        # API and capacity controls avoid assuming numeric symbol IDs are equal.
        for lib in libs:
            lib.reset_assembler(0x800,b'',0)
            for i in range(896):
                n=f's{i:03d}'.encode()
                symbol=lib.allocate_symbol(n,len(n),2,i)
                assert symbol>=0,(i,symbol)
            assert lib.allocate_symbol(b'overflow',8,2,0)==-3
            assert ctypes.c_int.in_dll(lib,'symbol_count').value==896
            for i in (0,1,255,256,511,512,895):
                n=f's{i:03d}'.encode()
                assert lib.find_symbol(n,len(n))>=0,(i,'missing')
            assert lib.find_symbol(b'absent',6)==-1
            lib.reset_assembler(0x800,b'',0)
            symbol=lib.intern_label(b'target',6)
            assert symbol>=0
            for i in range(20):
                assert lib.stage_plain_word_reference(symbol)==0
            assert lib.define_label(b'target',6,0x1234)==0
            assert image(lib)==bytes([0x34,0x12])*20
            lib.reset_assembler(0x800,b'',0)
            for i in range(640):
                assert lib.append_fixup(2,0,4,0,0)==0,i
            assert lib.append_fixup(2,0,4,0,0)==11
            assert ctypes.c_int.in_dll(lib,'fixup_count').value==640
            lib.reset_assembler(0x800,b'',0)
            for i in range(11264):
                assert lib.stage_byte(i&255)==0,i
            assert lib.stage_byte(3)==11
            assert len(image(lib))==11264
        print('PASS symbol records 896, forward chains, fixups 640, stage 11264, bounds and page edges')

if __name__=='__main__':main()
