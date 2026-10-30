"""Small independently executed 6502 subset emulator from the earlier probe.
This is NOT the nanoc compiler, the new selector, or a full 6502 emulator.
Used only to check instructions that this experiment actually emits.
"""
import re
from pathlib import Path
BASELINE=(Path(__file__).parent/'n1-ass.asm').read_text().splitlines()
IMPLIED={'clc','sec','cld','sei','cli','rts','rti','tax','tay','tya','txa','dex','dey','inx','iny','pha','pla','php','plp','asl','lsr','rol','ror','nop','brk'}
BRANCHES={'bcc','bcs','beq','bne','bmi','bpl','bvc','bvs'}
def parse_lines(lines):
    ins = []
    labels = {}
    for line in lines:
        t = line.split(';', 1)[0].strip().lower()
        if not t or t.startswith('include ') or t.startswith('* ') or t.startswith('byte ') or t.startswith('word ') or t.startswith('__nc_') or (' = ' in t):
            continue
        if t.endswith(':'):
            labels[t[:-1]] = len(ins)
            continue
        op, *args = t.split(None, 1)
        ins.append((op, args[0].replace(' ', '') if args else ''))
    return (ins, labels)

def ins_size(op, arg):
    if op in IMPLIED and (not arg):
        return 1
    if op in BRANCHES:
        return 2
    if arg.startswith('#'):
        return 2
    if arg.startswith('(') or re.match('^nc_(tmp|ptr)(\\+1)?$', arg):
        return 2
    return 3

def source_function(num):
    start = next((i for i, s in enumerate(BASELINE) if s.strip().lower() == f'__f{num:02x}:'))
    end = next((i for i in range(start + 1, len(BASELINE)) if re.match('^__f[0-9a-f]{2}:', BASELINE[i])), len(BASELINE))
    lines = BASELINE[start:end]
    instructions, _ = parse_lines(lines)
    return instructions

class Machine:

    def __init__(self, code, mem=None, arrays=None):
        ins, labels = parse_lines(code)
        self.ins, self.labels = (ins, labels)
        self.mem = mem or {}
        self.arrays = arrays or {}
        self.A = 0
        self.X = 0
        self.Y = 0
        self.C = 0
        self.Z = 0
        self.pc = 0
        self.stack = []
        self.steps = 0

    def read(self, arg):
        if arg.startswith('#$'):
            return int(arg[2:], 16)
        if ',y' in arg:
            name = arg.split(',')[0]
            return self.arrays[name][self.Y]
        return self.mem.get(arg, 0)

    def step(self):
        op, arg = self.ins[self.pc]
        self.pc += 1
        self.steps += 1
        if self.steps > 10000:
            raise RuntimeError('execution exceeded 10000 instructions')
        if op in ('lda', 'ldx', 'ldy'):
            v = self.read(arg)
            setattr(self, op[-1].upper(), v)
            self.Z = int(v == 0)
        elif op == 'sta':
            self.mem[arg] = self.A
        elif op in ('cmp', 'cpy'):
            a = self.A if op == 'cmp' else self.Y
            b = self.read(arg)
            self.C = int(a >= b)
            self.Z = int(a == b)
        elif op == 'sec':
            self.C = 1
        elif op == 'clc':
            self.C = 0
        elif op == 'sbc':
            d = self.A - self.read(arg) - (1 - self.C)
            self.C = int(d >= 0)
            self.A = d & 255
            self.Z = int(self.A == 0)
        elif op == 'adc':
            d = self.A + self.read(arg) + self.C
            self.C = int(d > 255)
            self.A = d & 255
            self.Z = int(self.A == 0)
        elif op == 'iny':
            self.Y = self.Y + 1 & 255
            self.Z = int(self.Y == 0)
        elif op == 'tya':
            self.A = self.Y
            self.Z = int(self.A == 0)
        elif op in ('bcc', 'bcs', 'bne', 'beq'):
            take = {'bcc': not self.C, 'bcs': self.C, 'bne': not self.Z, 'beq': self.Z}[op]
            if take:
                self.pc = self.labels[arg]
        elif op == 'jmp':
            self.pc = self.labels[arg]
        elif op == 'jsr':
            self.stack.append(self.pc)
            self.pc = self.labels[arg]
        elif op == 'rts':
            if self.stack:
                self.pc = self.stack.pop()
            else:
                return False
        else:
            raise NotImplementedError(f'{op} {arg}')
        return True

    def run(self, entry):
        self.pc = self.labels[entry]
        while self.step():
            pass
        return self.A | self.X << 8
