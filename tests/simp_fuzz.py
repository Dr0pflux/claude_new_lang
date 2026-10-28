#!/usr/bin/env python3
"""Differential fuzzer for skite's AST simplification passes (G-simplify gate).

Generates random typed programs that are heavy in constants, global scalars and small fixed-count loops
(constant propagation + folding, full unrolling, global promotion, periodic-index strength reduction),
runs them through an independent reference interpreter written here (language rules of docs/LANGUAGE.md:
64-bit promotion, wrapping, narrow-type canonical forms, saturating float->int casts, IEEE f32/f64,
division/bounds traps, left-to-right evaluation) and compares stdout + exit status of the compiled binary
for argc = 1, 2 and 4.  Floats are observed through bits() with NaNs canonicalised (the language does not
define NaN payloads).

usage: tests/simp_fuzz.py [CASES] [SEED] [--keep DIR]    (compiler from $SKITE, default ./skite)
"""
import math
import os
import random
import struct
import subprocess
import sys
import tempfile

M64 = (1 << 64) - 1
INTS = ['i8', 'i16', 'i32', 'i64', 'u8', 'u16', 'u32', 'u64']
SIG = INTS[:4]
UNS = INTS[4:]
FLT = ['f32', 'f64']
ALLT = INTS + ['bool'] + FLT
W = dict(i8=8, i16=16, i32=32, i64=64, u8=8, u16=16, u32=32, u64=64)
NAN64 = 0x7FF8000000000000
NAN32 = 0x7FC00000


def is_int(t): return t in W
def is_flt(t): return t in FLT
def prom(t): return 'u64' if t == 'u64' else 'i64'
def sgn(v): return v - (1 << 64) if v >> 63 else v


def widens(s, t):
    if s == t:
        return True
    if s in SIG:
        return t in SIG and W[t] >= W[s]
    if s in UNS:
        return (t in UNS and W[t] >= W[s]) or (t in SIG and W[t] > W[s])
    return False


def canon(v, t):
    v &= M64
    if t in ('i8', 'i16', 'i32'):
        b = W[t]
        v &= (1 << b) - 1
        if v >> (b - 1):
            v |= M64 ^ ((1 << b) - 1)
        return v
    if t in ('u8', 'u16', 'u32'):
        return v & ((1 << W[t]) - 1)
    if t == 'bool':
        return v & 1
    if t == 'f32':
        return v & 0xFFFFFFFF
    return v


class Trap(Exception):
    def __init__(self, rc): self.rc = rc
class Abort(Exception): pass
class Brk(Exception): pass
class Cont(Exception): pass
class Ret(Exception):
    def __init__(self, v): self.v = v


# ------------------------------------------------------------------ float helpers
def fv(t, b):
    if t == 'f64':
        return struct.unpack('<d', struct.pack('<Q', b & M64))[0]
    return struct.unpack('<f', struct.pack('<I', b & 0xFFFFFFFF))[0]


def fb(t, x):
    if x != x:
        return NAN64 if t == 'f64' else NAN32
    if t == 'f64':
        return struct.unpack('<Q', struct.pack('<d', x))[0]
    try:
        return struct.unpack('<I', struct.pack('<f', x))[0]
    except OverflowError:
        return 0x7F800000 if x > 0 else 0xFF800000


def int_to_float(n, t):
    if t == 'f64':
        return fb('f64', float(n))
    neg = n < 0
    a = -n if neg else n
    if a >= (1 << 24):
        sh = a.bit_length() - 24
        q = a >> sh
        rem = a & ((1 << sh) - 1)
        half = 1 << (sh - 1)
        if rem > half or (rem == half and (q & 1)):
            q += 1
        a = q << sh
    x = float(a)
    return fb('f32', -x if neg else x)


def fdiv(a, b):
    if b == 0:
        if a == 0 or a != a:
            return float('nan')
        return math.copysign(math.inf, a) * math.copysign(1.0, b)
    return a / b


def fbin(op, t, x, y):
    a, b = fv(t, x), fv(t, y)
    if op == '+': r = a + b
    elif op == '-': r = a - b
    elif op == '*': r = a * b
    else: r = fdiv(a, b)
    return fb(t, r)


def sat_i64(x):
    if x != x: return 0
    if x >= 9223372036854775808.0: return (1 << 63) - 1
    if x <= -9223372036854775808.0: return -(1 << 63)
    return int(x)


def lo_hi(t):
    b = W[t]
    return (-(1 << (b - 1)), (1 << (b - 1)) - 1) if t in SIG else (0, (1 << b) - 1)


def cast(v, s, t):
    if s == t: return v
    if s == 'bool': return v
    if is_int(s) and is_int(t): return canon(v, t)
    if is_int(s) and is_flt(t):
        return int_to_float(v if s == 'u64' else sgn(v), t)
    if is_flt(s) and is_flt(t): return fb(t, fv(s, v))
    x = fv(s, v)
    if t == 'u64':
        if x != x or x <= 0: return 0
        if x >= 18446744073709551616.0: return M64
        return int(x)
    i = sat_i64(x)
    if t != 'i64':
        lo, hi = lo_hi(t)
        i = max(lo, min(hi, i))
    return i & M64


def ibin(op, P, x, y):
    if op == '+': return (x + y) & M64
    if op == '-': return (x - y) & M64
    if op == '*': return (x * y) & M64
    if op == '&': return x & y
    if op == '|': return x | y
    if op == '^': return x ^ y
    if op == '<<': return (x << (y & 63)) & M64
    if op == '>>>': return x >> (y & 63)
    if op == '>>':
        if P == 'u64': return x >> (y & 63)
        return (sgn(x) >> (y & 63)) & M64
    if op in ('/', '%'):
        if P == 'u64':
            if y == 0: raise Trap(136)
            return x // y if op == '/' else x % y
        a, b = sgn(x), sgn(y)
        if b == 0 or (a == -(1 << 63) and b == -1): raise Trap(136)
        q = abs(a) // abs(b)
        if (a < 0) != (b < 0): q = -q
        return (q if op == '/' else a - q * b) & M64
    raise AssertionError(op)


def icmp(op, pt, x, y):
    if pt in ('f32', 'f64'):
        a, b = fv(pt, x), fv(pt, y)
    elif pt == 'i64':
        a, b = sgn(x), sgn(y)
    else:
        a, b = x, y
    return int({'==': a == b, '!=': a != b, '<': a < b, '<=': a <= b, '>': a > b, '>=': a >= b}[op])


# ------------------------------------------------------------------ expression / statement construction
# expression tuples: (kind, type, ...)
def T(e): return e[1]


def lit(t, v): return ('lit', t, v)


def fmt_lit(t, v):
    if t == 'bool': return 'true' if v else 'false'
    if t in ('f32', 'f64'):
        x = fv(t, v)
        if x != x or math.isinf(x) or (x != 0 and abs(x) < 1e-290) or abs(x) > 1e300 or t == 'f32' and (x != 0 and (abs(x) < 1e-30 or abs(x) > 1e30)):
            return '%s_from_bits(%d)' % (t, v)
        s = repr(abs(x))
        if 'e' in s:
            m, ex = s.split('e')
            if '.' not in m: m += '.0'
            s = '%se%d' % (m, int(ex))
        elif '.' not in s:
            s += '.0'
        if math.copysign(1.0, x) < 0: return '(-%s)' % s
        return s
    if t == 'u64': return str(v)
    s = sgn(v)
    if s == -(1 << 63): return '(-9223372036854775807 - 1)'
    if s < 0: return '(-%d)' % -s
    return str(s)


def show(e):
    k = e[0]
    if k == 'lit': return fmt_lit(e[1], e[2])
    if k in ('var', 'glob'): return e[2]
    if k == 'argc': return 'argc()'
    if k == 'aload': return '%s[%s]' % (e[2], show(e[3]))
    if k in ('ibin', 'fbin'): return '(%s %s %s)' % (show(e[3]), e[2], show(e[4]))
    if k == 'cmp': return '(%s %s %s)' % (show(e[4]), e[2], show(e[5]))
    if k == 'land': return '(%s && %s)' % (show(e[2]), show(e[3]))
    if k == 'lor': return '(%s || %s)' % (show(e[2]), show(e[3]))
    if k in ('neg', 'fneg'): return '(-%s)' % show(e[2])
    if k == 'not': return '(~%s)' % show(e[2])
    if k == 'lnot': return '(!%s)' % show(e[2])
    if k == 'cast': return '(%s as %s)' % (show(e[2]), e[1])
    if k == 'sqrt': return 'sqrt(%s)' % show(e[2])
    if k == 'frombits': return '%s_from_bits(%s)' % (e[1], show(e[2]))
    if k == 'call': return '%s(%s)' % (e[2], ', '.join(show(a) for a in e[3]))
    raise AssertionError(k)


class Interp:
    def __init__(self, fns, garrs, gvars, argc, limit=300000):
        self.fns = fns
        self.garrs = {n: [0] * ln for n, (t, ln) in garrs.items()}
        self.garrt = {n: t for n, (t, ln) in garrs.items()}
        self.g = {n: v for n, (t, v) in gvars.items()}
        self.gt = {n: t for n, (t, v) in gvars.items()}
        self.argc = argc
        self.steps = 0
        self.limit = limit
        self.out = []
        self.frames = [{}]
        self.arrs = {}

    def tick(self, n=1):
        self.steps += n
        if self.steps > self.limit: raise Abort()

    def arr(self, name):
        return self.garrs[name] if name in self.garrs else self.arrs[name]

    def ev(self, e):
        k = e[0]
        if k == 'lit': return e[2]
        if k == 'var': return self.frames[-1][e[2]]
        if k == 'glob': return self.g[e[2]]
        if k == 'argc': return self.argc
        if k == 'aload':
            a = self.arr(e[2])
            i = self.ev(e[3])
            if i >= len(a): raise Trap(132)
            return a[i]
        if k == 'ibin':
            x = self.ev(e[3]); y = self.ev(e[4])
            return ibin(e[2], e[1], x, y)
        if k == 'fbin':
            x = self.ev(e[3]); y = self.ev(e[4])
            return fbin(e[2], e[1], x, y)
        if k == 'cmp':
            x = self.ev(e[4]); y = self.ev(e[5])
            return icmp(e[2], e[3], x, y)
        if k == 'land':
            return 1 if (self.ev(e[2]) and self.ev(e[3])) else 0
        if k == 'lor':
            return 1 if (self.ev(e[2]) or self.ev(e[3])) else 0
        if k == 'neg': return (-self.ev(e[2])) & M64
        if k == 'not': return (~self.ev(e[2])) & M64
        if k == 'lnot': return 1 if self.ev(e[2]) == 0 else 0
        if k == 'fneg':
            v = self.ev(e[2])
            return v ^ (1 << 63) if e[1] == 'f64' else v ^ 0x80000000
        if k == 'cast':
            v = self.ev(e[2])
            return cast(v, T(e[2]), e[1])
        if k == 'sqrt':
            x = fv(e[1], self.ev(e[2]))
            return fb(e[1], math.sqrt(x) if x >= 0 else float('nan'))
        if k == 'frombits': return self.ev(e[2])
        if k == 'call': return self.call(e)
        raise AssertionError(k)

    def call(self, e):
        name = e[2]
        args = [self.ev(a) for a in e[3]]
        self.tick(5)
        if len(self.frames) > 40: raise Abort()
        params, ret, body = self.fns[name]
        fr = {}
        for (pn, pt, pm), a in zip(params, args): fr[pn] = a
        self.frames.append(fr)
        try:
            self.block(body)
            r = 0
        except Ret as r_:
            r = r_.v
        finally:
            self.frames.pop()
        return r

    def block(self, stmts):
        for s in stmts: self.stmt(s)

    def stmt(self, s):
        k = s[0]
        self.tick()
        fr = self.frames[-1]
        if k == 'let':
            fr[s[1]] = self.ev(s[4])
        elif k == 'set':
            v = self.ev(s[3])
            if s[1] == 'v': fr[s[2]] = v
            else: self.g[s[2]] = v
        elif k == 'opset':
            kind, name, op, ex, t = s[1], s[2], s[3], s[4], s[5]
            cur = fr[name] if kind == 'v' else self.g[name]
            y = self.ev(ex)
            if is_flt(t): r = fbin(op, t, cur, y)
            else: r = canon(ibin(op, prom(t), cur, y), t)
            if kind == 'v': fr[name] = r
            else: self.g[name] = r
        elif k == 'store':
            name, idx, op, ex, t = s[1], s[2], s[3], s[4], s[5]
            y = self.ev(ex)           # value first, then index (language rule)
            i = self.ev(idx)
            a = self.arr(name)
            if i >= len(a): raise Trap(132)
            if op is None: a[i] = y
            elif is_flt(t): a[i] = fbin(op, t, a[i], y)
            else: a[i] = canon(ibin(op, prom(t), a[i], y), t)
        elif k == 'if':
            if self.ev(s[1]): self.block(s[2])
            elif s[3] is not None: self.block(s[3])
        elif k == 'while':
            while self.ev(s[1]):
                self.tick(2)
                try:
                    self.block(s[2])
                except Brk:
                    break
                except Cont:
                    continue
        elif k == 'break': raise Brk()
        elif k == 'continue': raise Cont()
        elif k == 'ret': raise Ret(self.ev(s[1]) if s[1] is not None else 0)
        elif k == 'print':
            v = self.ev(s[1])
            t = T(s[1])
            if t == 'bool': self.out.append('true' if v else 'false')
            elif t == 'u64': self.out.append(str(v))
            elif is_flt(t):
                x = fv(t, v)
                self.out.append(str(fb(t, x) if x != x else v))
            else: self.out.append(str(sgn(v)))
        elif k == 'callst': self.ev(s[1])
        elif k == 'alloc':
            self.arrs[s[1]] = [0] * s[3]
        else:
            raise AssertionError(k)


# ------------------------------------------------------------------ generator
LITS = {
    'i8': [0, 1, -1, 2, 3, 7, -7, 31, 64, 100, 127, -128, -127, -64],
    'i16': [0, 1, -1, 5, 255, 256, 1000, 32767, -32768, -300, 12345],
    'i32': [0, 1, -1, 2, 7, 255, 65535, 65536, 100000, 2147483647, -2147483648, -2147483647, 123456789],
    'i64': [0, 1, -1, 2, 3, 5, 7, 8, 10, 26, 29, 31, 63, 64, 100, 255, 1000, 65535, 4294967295, 4294967296, 1 << 40,
            (1 << 62), (1 << 63) - 1, -(1 << 63), -(1 << 63) + 1, 6364136223846793005, -3, -29, 20511149, 9223372036854775800],
    'u8': [0, 1, 2, 3, 7, 15, 31, 100, 127, 128, 200, 254, 255],
    'u16': [0, 1, 2, 255, 256, 1000, 32767, 32768, 65534, 65535],
    'u32': [0, 1, 2, 255, 65535, 65536, 1000000, 2147483647, 2147483648, 4294967294, 4294967295],
    'u64': [0, 1, 2, 3, 7, 10, 255, 1000, 4294967295, 4294967296, (1 << 63) - 1, 1 << 63, (1 << 63) + 1, M64 - 1, M64],
}
FLITS = [0.0, 1.0, 2.0, 0.5, 0.25, 3.0, 10.0, 100.0, 1.5, 7.0, 0.125, 1024.0, 65536.0, 16777216.0, 4294967296.0, 3.75, 255.0, 1e10, 123456.0, 0.1, 1e-5]


class Gen:
    def __init__(self, seed):
        self.r = random.Random(seed)
        self.uid = 0
        self.fns = {}           # name -> (params, ret, body)
        self.order = []
        self.garrs = {}         # name -> (type, len)
        self.gvars = {}         # name -> (type, init)
        self.gconsts = {}
        self.cur = None         # name of function being generated (None = main)
        self.scope = []         # list of dicts name -> (type, mutable, protected)
        self.loopdepth = 0
        self.larrs = {}
        self.budget = 0
        self.inmain = False
        self.hasret = False

    # -- helpers
    def R(self, n): return self.r.randrange(n)
    def chance(self, p): return self.r.random() < p
    def name(self, p):
        self.uid += 1
        return '%s_%d' % (p, self.uid)

    def visible(self):
        d = {}
        for sc in self.scope: d.update(sc)
        return d

    def declare(self, name, t, mut, prot=False):
        self.scope[-1][name] = (t, mut, prot)

    def rlit(self, t):
        r = self.r
        if t == 'bool': return r.randrange(2)
        if is_flt(t):
            c = r.randrange(7)
            if c < 4: x = r.choice(FLITS)
            elif c == 4: x = (r.randrange(2001) - 1000) / 8.0
            elif c == 5: x = r.choice([-1, 1]) * r.choice(FLITS)
            else:
                x = r.uniform(-1000, 1000) if t == 'f64' else r.randrange(-100000, 100000) / 64.0
            if t == 'f32': return fb('f32', x)
            return fb('f64', x)
        c = r.randrange(5)
        if c < 3: return canon(r.choice(LITS[t]), t)
        if c == 3: return canon(r.randrange(-8, 9), t)
        return canon(r.getrandbits(W[t]), t)

    def flit_special(self, t):
        c = self.R(8)
        if t == 'f64':
            return [0x8000000000000000, 0x7FF0000000000000, 0xFFF0000000000000, 0x7FF8000000000000, 0x0000000000000001, 0x7FEFFFFFFFFFFFFF, 0x3FF0000000000000, 0xC000000000000000][c]
        return [0x80000000, 0x7F800000, 0xFF800000, 0x7FC00000, 0x00000001, 0x7F7FFFFF, 0x3F800000, 0xC0000000][c]

    # -- expressions
    def vars_of(self, t, exact=True):
        out = []
        for n, (vt, m, p) in self.visible().items():
            if vt == t or (not exact and is_int(t) and is_int(vt) and widens(vt, t)):
                out.append((n, vt))
        return out

    def leaf(self, t, allow_lit=True):
        r = self.R(12)
        if allow_lit and r < 3: return self.mklit(t)
        if r < 8:
            vs = self.vars_of(t)
            if vs:
                n, vt = self.r.choice(vs)
                return ('var', vt, n)
        if r < 10:
            gs = [n for n, (gt, _) in self.gvars.items() if gt == t]
            if gs: return ('glob', t, self.r.choice(gs))
        if r < 11:
            e = self.aload(t)
            if e: return e
        if t == 'i64' and self.inmain and self.chance(0.3): return ('argc', 'i64')
        if t == 'bool': return self.mklit(t)
        if is_flt(t) and self.chance(0.5):
            return ('cast', t, self.leaf('i32' if self.chance(0.5) else 'i64', True))
        return self.mklit(t)

    def mklit(self, t):
        if is_flt(t) and self.chance(0.08): return lit(t, self.flit_special(t))
        return lit(t, self.rlit(t))

    def arrays_visible(self):
        out = dict((n, (t, ln)) for n, (t, ln) in self.garrs.items())
        if self.inmain:
            for n, (t, ln) in self.larrs.items(): out[n] = (t, ln)
        return out

    def aload(self, t):
        cands = [(n, ln) for n, (at, ln) in self.arrays_visible().items() if at == t]
        if not cands: return None
        n, ln = self.r.choice(cands)
        return ('aload', t, n, self.gidx(ln))

    def gidx(self, ln):
        r = self.R(20)
        if r < 12:      # provably in range: (e as u64) % ln
            e = self.gexpr(self.r.choice(['u64', 'i64', 'u8', 'i32', 'u32']), 1)
            e = e if T(e) == 'u64' else ('cast', 'u64', e)
            return ('ibin', 'u64', '%', e, lit('u64', ln))
        if r < 17:      # loop counters / small vars, usually in range
            vs = [n for n, (vt, m, p) in self.visible().items() if vt == 'i64']
            if vs:
                n = self.r.choice(vs)
                return ('ibin', 'i64', '%', ('var', 'i64', n), lit('i64', ln))
        if r < 19: return lit('i64', self.R(ln))
        e = self.gexpr(self.r.choice(INTS), 1)   # possibly out of range -> trap
        return e

    def int_operand_ty(self, P):
        if P == 'u64': return self.r.choice(UNS)
        return self.r.choice(SIG + ['u8', 'u16', 'u32'])

    def safe_div(self, b, P):
        # ((b & 127) + 1) : never 0 and never -1
        m = ('ibin', P, '&', b, lit(P, 127))
        return ('ibin', P, '+', m, lit(P, 1))

    def nonlit(self, t, d):
        for _ in range(4):
            e = self.gexpr(t, d)
            if e[0] != 'lit': return e
        vs = self.vars_of(t)
        if vs:
            n, vt = self.r.choice(vs)
            return ('var', vt, n)
        if t == 'bool': return e
        src = 'f64' if (is_flt(t) and self.chance(0.5)) else 'i32'
        if is_flt(t): return ('cast', t, lit(src, self.rlit(src) if src == 'f64' else canon(self.R(100) - 20, 'i32')))
        return ('cast', t, lit(self.r.choice([x for x in INTS if x != t]), 0) if False else lit('i64', canon(self.R(300) - 100, 'i64')))

    def pair(self, ta, tb, d, op_lit_ok=True):
        """two operands of static types ta, tb, never both literals; a literal operand fits the other's type"""
        r = self.r
        if op_lit_ok and self.chance(0.25):
            if self.chance(0.5):
                a = self.nonlit(ta, d - 1)
                return a, self.mklit(T(a))
            b = self.nonlit(tb, d - 1)
            return self.mklit(T(b)), b
        a = self.gexpr(ta, d - 1)
        b = self.gexpr(tb, d - 1)
        if a[0] == 'lit' and b[0] == 'lit': a = self.nonlit(ta, d - 1)
        return a, b

    def ibin_expr(self, P, d):
        r = self.r
        ops = ['+', '+', '-', '-', '*', '/', '%', '&', '|', '^', '<<', '>>', '>>>']
        op = r.choice(ops)
        if op in ('<<', '>>', '>>>'):
            lt = 'u64' if P == 'u64' else self.int_operand_ty('i64')
            a = self.nonlit(lt, d - 1)
            if self.chance(0.4): b = lit('i64', canon(self.R(70) - 3, 'i64'))
            else: b = self.gexpr(r.choice(INTS), d - 1)
            return ('ibin', P, op, a, b)
        ta = 'u64' if P == 'u64' else self.int_operand_ty('i64')
        tb = self.int_operand_ty(P)
        if P == 'u64' and self.chance(0.5): ta, tb = tb, ta
        if op in ('/', '%'):
            a = self.nonlit(ta, d - 1)
            return ('ibin', P, op, a, self.divisor(P, d))
        a, b = self.pair(ta, tb, d)
        return ('ibin', P, op, a, b)

    def divisor(self, P, d):
        c = self.R(10)
        if c < 6: return self.safe_div(self.nonlit(P, d - 1), P)
        if c < 7:
            v = self.r.choice([1, 2, 3, 5, 7, 10, 26, 29, 100, 255, 1000])
            return lit(P, v)
        if c < 8 and P == 'i64': return lit(P, canon(-1, 'i64')) if self.chance(0.3) else lit(P, canon(-self.r.choice([2, 3, 7]), 'i64'))
        # raw: may be zero / -1 at run time (trap) but not a literal zero
        e = self.gexpr(self.int_operand_ty(P) if P != 'u64' else 'u64', d - 1)
        if e[0] == 'lit' and e[2] == 0: return lit(P, 3)
        return e

    def fbin_expr(self, t, d):
        op = self.r.choice(['+', '-', '*', '/', '+', '*'])
        a, b = self.pair(t, t, d)
        return ('fbin', t, op, a, b)

    def anyint(self):
        vs = [n for n, (vt, m, p) in self.visible().items() if vt == 'i64']
        return self.r.choice(vs) if vs else None

    def cmp_expr(self, d):
        r = self.R(10)
        ops = ['==', '!=', '<', '<=', '>', '>=']
        if r < 2:
            t = self.r.choice(FLT)
            a, b = self.pair(t, t, d)
            return ('cmp', 'bool', self.r.choice(ops), t, a, b)
        if r < 3:
            return ('cmp', 'bool', self.r.choice(['==', '!=']), 'bool', self.gexpr('bool', d - 1), self.gexpr('bool', d - 1))
        P = 'u64' if self.chance(0.25) else 'i64'
        ta = 'u64' if P == 'u64' else self.int_operand_ty('i64')
        tb = self.int_operand_ty(P)
        if P == 'u64' and self.chance(0.5): ta, tb = tb, ta
        a, b = self.pair(ta, tb, d)
        return ('cmp', 'bool', self.r.choice(ops), P, a, b)

    def gexpr(self, t, d):
        r = self.R(10)
        if d <= 0 or r < 3: return self.leaf(t)
        if self.fns_avail() and self.chance(0.12):
            c = self.gcall(t, d)
            if c: return c
        if t == 'bool':
            if r < 6: return self.cmp_expr(d)
            if r < 8: return ('land' if self.chance(0.5) else 'lor', 'bool', self.gexpr('bool', d - 1), self.gexpr('bool', d - 1))
            if r < 9: return ('lnot', 'bool', self.gexpr('bool', d - 1))
            return self.leaf(t)
        if is_flt(t):
            if r < 6: return self.fbin_expr(t, d)
            if r < 7: return ('fneg', t, self.gexpr(t, d - 1))
            if r < 8: return ('sqrt', t, self.gexpr(t, d - 1))
            if r < 9 and self.chance(0.5): return ('frombits', t, self.gexpr('u64' if t == 'f64' else 'u32', d - 1))
            s = self.r.choice(INTS + FLT)
            return ('cast', t, self.gexpr(s, d - 1))
        if t in ('i64', 'u64') and r < 7: return self.ibin_expr(t, d)
        if t == 'i64' and r < 8: return ('neg', 'i64', self.gexpr(self.int_operand_ty('i64'), d - 1))
        if r < 8 and t in ('i64', 'u64'):
            return ('not', t, self.gexpr('u64' if t == 'u64' else self.int_operand_ty('i64'), d - 1))
        s = self.r.choice(ALLT)
        return ('cast', t, self.gexpr(s, d - 1))

    def fns_avail(self): return bool(self.order)

    def gcall(self, t, d):
        cands = [n for n in self.order if self.fns[n][1] == t and n != self.cur]
        if not cands: return None
        n = self.r.choice(cands)
        params = self.fns[n][0]
        return ('call', t, n, [self.gexpr(pt, d - 1) for (pn, pt, pm) in params])

    # -- statements
    def gblock(self, d, n=None):
        self.scope.append({})
        out = []
        cnt = n if n is not None else 1 + self.R(4)
        for _ in range(cnt):
            if self.budget <= 0: break
            out.extend(self.gstmt(d))
        self.scope.pop()
        return out

    def assignable(self, mut=True):
        return [(n, t) for n, (t, m, p) in self.visible().items() if m and not p]

    def opeq_ops(self, t):
        if is_flt(t): return ['+', '-', '*', '/']
        return ['+', '-', '*', '/', '%', '&', '|', '^', '<<', '>>']

    def opset(self, kind, name, t):
        op = self.r.choice(self.opeq_ops(t))
        if is_flt(t): ex = self.gexpr(t, 2)
        elif op in ('<<', '>>'): ex = self.gexpr(self.r.choice(INTS), 1) if self.chance(0.6) else lit('i64', self.R(70))
        elif op in ('/', '%'): ex = self.divisor(prom(t), 2)
        else:
            P = prom(t)
            ex = self.gexpr(self.int_operand_ty(P) if P != 'u64' else self.r.choice(UNS), 2)
        return ('opset', kind, name, op, ex, t)

    def gstmt(self, d):
        self.budget -= 1
        r = self.R(100)
        if r < 12:      # new local
            t = self.r.choice(ALLT)
            n = self.name('v')
            mut = self.chance(0.6)
            e = self.gexpr(t, 3)
            self.declare(n, t, mut)
            return [('let', n, t, mut, e)]
        if r < 24:
            cs = self.assignable()
            if cs:
                n, t = self.r.choice(cs)
                if t != 'bool' and self.chance(0.4): return [self.opset('v', n, t)]
                return [('set', 'v', n, self.gexpr(t, 3))]
        if r < 36 and self.gvars:
            n = self.r.choice(list(self.gvars))
            t = self.gvars[n][0]
            if t != 'bool' and self.chance(0.45): return [self.opset('g', n, t)]
            return [('set', 'g', n, self.gexpr(t, 3))]
        if r < 43:
            arrs = list(self.arrays_visible().items())
            if arrs:
                n, (t, ln) = self.r.choice(arrs)
                if t != 'bool' and self.chance(0.4):
                    op = self.r.choice(self.opeq_ops(t))
                    if is_flt(t): ex = self.gexpr(t, 2)
                    elif op in ('<<', '>>'): ex = self.gexpr(self.r.choice(INTS), 1)
                    elif op in ('/', '%'): ex = self.divisor(prom(t), 2)
                    else: ex = self.gexpr(self.int_operand_ty(prom(t)) if prom(t) != 'u64' else self.r.choice(UNS), 2)
                    return [('store', n, self.gidx(ln), op, ex, t)]
                return [('store', n, self.gidx(ln), None, self.gexpr(t, 3), t)]
        if r < 52 and d > 0:
            c = self.gexpr('bool', 3)
            th = self.gblock(d - 1)
            if self.loopdepth and self.chance(0.12): th.append(self.r.choice([('break',), ('continue',)]) if self.cont_ok() else ('break',))
            el = self.gblock(d - 1) if self.chance(0.4) else None
            return [('if', c, th, el)]
        if r < 66 and d > 0 and self.loopdepth < 3:
            return self.counted_loop(d)
        if r < 70 and d > 0 and self.loopdepth < 2:
            return self.generic_loop(d)
        if r < 76 and self.order:
            n = self.r.choice(self.order)
            params, ret, body = self.fns[n]
            call = ('call', ret if ret else 'unit', n, [self.gexpr(pt, 2) for (pn, pt, pm) in params])
            if ret is None or self.chance(0.4): return [('callst', call)]
            v = self.name('v')
            self.declare(v, ret, self.chance(0.5))
            return [('let', v, ret, self.visible()[v][1], call)]
        if r < 80 and self.loopdepth and d >= 0:
            return [('if', self.gexpr('bool', 2), [self.r.choice([('break',), ('continue',)]) if self.cont_ok() else ('break',)], None)]
        if r < 83 and self.cur_ret_ok():
            return [('if', self.gexpr('bool', 2), [self.mk_ret()], None)]
        return [self.mk_print()]

    def cont_ok(self):
        return False    # a bare `continue` could skip the increment (infinite loop); loops handle it explicitly

    def cur_ret_ok(self):
        return self.inmain or self.cur_rett is not None or self.cur_unit

    def mk_ret(self):
        if self.inmain: return ('ret', self.gexpr('i64', 2))
        if self.cur_rett is None: return ('ret', None)
        return ('ret', self.gexpr(self.cur_rett, 2))

    def mk_print(self):
        t = self.r.choice(ALLT)
        return ('print', self.gexpr(t, 3))

    # loops
    def counted_loop(self, d):
        r = self.r
        iv = self.name('i')
        c0 = r.choice([0, 0, 0, 0, 1, 2, -1, -3, 5, 10, 100])
        trip = r.choice([0, 1, 1, 2, 2, 3, 3, 4, 5, 6, 7, 8, 9, 12, 16, 17, 20])
        cmpop = '<' if self.chance(0.7) else '<='
        c1 = c0 + trip - (1 if cmpop == '<=' else 0)
        stmts = []
        # bound: literal / runtime value (not foldable) / mutable variable
        bk = r.choice(['lit', 'lit', 'lit', 'argc', 'var', 'glob'])
        prot = []
        if bk == 'lit' or (bk == 'argc' and not self.inmain):
            bound = lit('i64', canon(c1, 'i64'))
        elif bk == 'argc':
            # argc is 1,2,4 at run time; the bound is c1 - 1 + argc-dependent... keep exact trip for argc==1
            bound = ('ibin', 'i64', '+', ('argc', 'i64'), lit('i64', canon(c1 - 1, 'i64')))
        elif bk == 'var':
            n = self.name('n')
            stmts.append(('let', n, 'i64', True, lit('i64', canon(c1, 'i64'))))
            self.declare(n, 'i64', True, True)
            bound = ('var', 'i64', n)
            prot.append(n)
        else:
            gs = [g for g, (gt, _) in self.gvars.items() if gt == 'i64']
            if gs:
                g = r.choice(gs)
                stmts.append(('set', 'g', g, lit('i64', canon(c1, 'i64'))))
                bound = ('glob', 'i64', g)
            else:
                bound = lit('i64', canon(c1, 'i64'))
        stmts.append(('let', iv, 'i64', True, lit('i64', canon(c0, 'i64'))))
        self.scope.append({})
        self.declare(iv, 'i64', True, True)
        cond = ('cmp', 'bool', cmpop, 'i64', ('var', 'i64', iv), bound)
        shape = r.choice(['std', 'std', 'std', 'std', 'break', 'cont', 'extra', 'shrink', 'brk_inc'])
        self.loopdepth += 1
        body = self.gblock(d - 1, 1 + self.R(4))
        pre = []
        if shape == 'break':
            body.insert(self.R(len(body) + 1), ('if', self.gexpr('bool', 2), [('break',)], None))
        elif shape == 'cont':
            pre.append(('if', self.gexpr('bool', 2), [('opset', 'v', iv, '+', lit('i64', 1), 'i64'), ('continue',)], None))
        elif shape == 'extra':
            body.insert(self.R(len(body) + 1), ('if', self.gexpr('bool', 2), [('opset', 'v', iv, '+', lit('i64', 1), 'i64')], None))
        elif shape == 'shrink' and bk == 'var':
            body.insert(self.R(len(body) + 1), ('if', self.gexpr('bool', 2), [('opset', 'v', prot[0], '-', lit('i64', 1), 'i64')], None))
        elif shape == 'brk_inc':
            body.append(('opset', 'v', iv, '+', lit('i64', 1), 'i64'))
            body.insert(0, ('if', self.gexpr('bool', 2), [('break',)], None))
            body = body[:]
            self.loopdepth -= 1
            self.scope.pop()
            # increment already added (not last-statement unroll shape)
            return stmts + [('while', cond, pre + body)]
        # a use of the periodic-index pattern
        if self.chance(0.35):
            m = r.choice([lit('i64', r.choice([2, 3, 5, 7, 26, 29])), ('var', 'i64', self.anyint()) if self.anyint() else lit('i64', 7)])
            if m[0] == 'var' and m[2] == iv: m = lit('i64', 7)
            e = r.choice([('var', 'i64', iv), ('ibin', 'i64', '+', ('var', 'i64', iv), lit('i64', r.choice([0, 1, 3, 100, 5000])))])
            if m[0] == 'var':
                m = ('ibin', 'i64', '+', ('ibin', 'i64', '&', m, lit('i64', 31)), lit('i64', 1))
            pe = ('ibin', 'i64', '%', e, m)
            tgt = self.assignable()
            tg = [(n, t) for (n, t) in tgt if t == 'i64']
            if tg and self.chance(0.6):
                n, t = r.choice(tg)
                body.insert(self.R(len(body) + 1), ('set', 'v', n, ('ibin', 'i64', '+', ('ibin', 'i64', '*', ('var', 'i64', n), lit('i64', 3)), pe)))
            else:
                body.insert(self.R(len(body) + 1), ('print', pe))
        inc = ('opset', 'v', iv, '+', lit('i64', 1), 'i64')
        self.loopdepth -= 1
        self.scope.pop()
        res = stmts + [('while', cond, pre + body + [inc])]
        if self.chance(0.3):
            res.append(('print', ('var', 'i64', iv)))
        return res

    def generic_loop(self, d):
        # while x < K { ...; x += step }  with a runtime-dependent start
        r = self.r
        x = self.name('x')
        t = r.choice(['i64', 'i64', 'i32', 'u8', 'u16'])
        start = {'i64': r.choice([0, 3, -5, 100]), 'i32': r.choice([0, -7, 1000]), 'u8': r.choice([0, 3, 100]), 'u16': r.choice([0, 7, 300])}[t]
        lim = {'i64': start + r.randrange(1, 40), 'i32': start + r.randrange(1, 40), 'u8': min(250, start + r.randrange(1, 60)), 'u16': start + r.randrange(1, 60)}[t]
        step = r.choice([1, 2, 3, 5])
        stmts = [('let', x, t, True, lit(t, canon(start, t)))]
        self.scope.append({})
        self.declare(x, t, True, True)
        cond = ('cmp', 'bool', r.choice(['<', '<=']), 'i64', ('var', t, x), lit(t, canon(lim, t)))
        if t == 'u8' or t == 'u16' or t == 'i32':
            cond = ('cmp', 'bool', '<', 'i64', ('var', t, x), lit(t, canon(lim, t)))
        self.loopdepth += 1
        body = self.gblock(d - 1, 1 + self.R(3))
        self.loopdepth -= 1
        self.scope.pop()
        if self.chance(0.3):
            body.insert(self.R(len(body) + 1), ('if', self.gexpr('bool', 2), [('break',)], None))
        body.append(('opset', 'v', x, '+', lit(t, step), t))
        return stmts + [('while', cond, body), ('print', ('var', t, x))]

    # -- program
    def gen_function(self, idx):
        n = 'h%d' % idx
        self.cur = n
        self.inmain = False
        ret = None if self.chance(0.25) else self.r.choice(ALLT)
        self.cur_rett = ret
        self.cur_unit = ret is None
        np_ = 1 + self.R(3)
        params = []
        self.scope = [{}]
        for i in range(np_):
            pn = self.name('p')
            pt = self.r.choice(ALLT)
            pm = self.chance(0.25)
            params.append((pn, pt, pm))
            self.declare(pn, pt, pm)
        self.budget = 4 + self.R(8)
        body = []
        for _ in range(1 + self.R(4)):
            if self.budget <= 0: break
            body.extend(self.gstmt(2))
        if ret is not None: body.append(('ret', self.gexpr(ret, 3)))
        self.fns[n] = (params, ret, body)
        self.order.append(n)
        self.scope = []
        self.cur = None

    def generate(self):
        r = self.r
        # globals
        for i in range(r.randrange(2, 7)):
            t = r.choice(ALLT)
            self.gvars['G%d' % i] = (t, self.rlit(t))
        # keep an i64 global for loop bounds
        if not any(t == 'i64' for t, _ in self.gvars.values()):
            self.gvars['G%d' % 9] = ('i64', self.rlit('i64'))
        for i in range(r.randrange(0, 3)):
            t = r.choice(ALLT)
            self.garrs['GA%d' % i] = (t, r.choice([1, 2, 3, 5, 8]))
        for i in range(r.randrange(0, 4)):
            self.gen_function(i)
        self.cur = None
        self.inmain = True
        self.cur_rett = 'i64'
        self.cur_unit = False
        self.scope = [{}]
        self.budget = 12 + self.R(20)
        main = []
        for i in range(r.randrange(0, 3)):
            t = r.choice(ALLT)
            ln = r.choice([1, 2, 3, 5, 8, 13])
            n = self.name('a')
            self.larrs[n] = (t, ln)
            main.append(('alloc', n, t, ln))
        for t in ALLT:
            if self.chance(0.5):
                n = self.name('v')
                main.append(('let', n, t, True, lit(t, self.rlit(t))))
                self.declare(n, t, True)
        # opaque runtime value
        on = self.name('v')
        main.append(('let', on, 'i64', True, ('ibin', 'i64', '*', ('argc', 'i64'), lit('i64', r.choice([1, 3, 7])))))
        self.declare(on, 'i64', True)
        while self.budget > 0:
            main.extend(self.gstmt(3))
        # observe all state
        for n, (t, _) in self.gvars.items(): main.append(('print', ('glob', t, n)))
        for n, (t, m, p) in self.visible().items():
            if not p: main.append(('print', ('var', t, n)))
        for n, (t, ln) in list(self.garrs.items()) + list(self.larrs.items()):
            for i in range(min(ln, 8)): main.append(('print', ('aload', t, n, lit('i64', i))))
        main.append(('ret', self.gexpr('i64', 3)))
        return main

    # -- output
    def source(self, main):
        L = []
        L.append('fn pf64(x: f64) { if x != x { print(9221120237041090560); } else { print(bits(x)); } }')
        L.append('fn pf32(x: f32) { if x != x { print(2143289344); } else { print(bits(x)); } }')
        for n, (t, v) in self.gvars.items():
            L.append('let mut %s: %s = %s;' % (n, t, fmt_lit(t, v)))
        for n, (t, ln) in self.garrs.items():
            L.append('let %s = alloc<%s>(%d);' % (n, t, ln))

        def emit(stmts, ind):
            for s in stmts:
                k = s[0]
                p = '  ' * ind
                if k == 'let':
                    L.append('%slet %s%s: %s = %s;' % (p, 'mut ' if s[3] else '', s[1], s[2], show(s[4])))
                elif k == 'set':
                    L.append('%s%s = %s;' % (p, s[2], show(s[3])))
                elif k == 'opset':
                    L.append('%s%s %s= %s;' % (p, s[2], s[3], show(s[4])))
                elif k == 'store':
                    L.append('%s%s[%s] %s= %s;' % (p, s[1], show(s[2]), s[3] or '', show(s[4])))
                elif k == 'if':
                    L.append('%sif %s {' % (p, show(s[1])))
                    emit(s[2], ind + 1)
                    if s[3] is not None:
                        L.append('%s} else {' % p)
                        emit(s[3], ind + 1)
                    L.append('%s}' % p)
                elif k == 'while':
                    L.append('%swhile %s {' % (p, show(s[1])))
                    emit(s[2], ind + 1)
                    L.append('%s}' % p)
                elif k == 'break': L.append('%sbreak;' % p)
                elif k == 'continue': L.append('%scontinue;' % p)
                elif k == 'ret':
                    L.append('%sreturn%s;' % (p, '' if s[1] is None else ' ' + show(s[1])))
                elif k == 'print':
                    t = T(s[1])
                    if is_flt(t): L.append('%spf%s(%s);' % (p, W_F[t], show(s[1])))
                    else: L.append('%sprint(%s);' % (p, show(s[1])))
                elif k == 'callst': L.append('%s%s;' % (p, show(s[1])))
                elif k == 'alloc': L.append('%slet %s = alloc<%s>(%d);' % (p, s[1], s[2], s[3]))
                else: raise AssertionError(k)

        for n in self.order:
            params, ret, body = self.fns[n]
            L.append('fn %s(%s)%s {' % (n, ', '.join('%s%s: %s' % ('mut ' if pm else '', pn, pt) for pn, pt, pm in params), (' -> ' + ret) if ret else ''))
            emit(body, 1)
            L.append('}')
        L.append('fn main() -> i64 {')
        emit(main, 1)
        L.append('}')
        return '\n'.join(L) + '\n'


W_F = {'f32': '32', 'f64': '64'}


def oracle(g, main, argc):
    it = Interp(g.fns, g.garrs, g.gvars, argc)
    fns = dict(g.fns)
    fns['main'] = ([], 'i64', main)
    it.fns = fns
    rc = 0
    try:
        it.frames = [{}]
        ret = None
        try:
            it.block(main)
        except Ret as r_:
            ret = r_.v
        it.out.append(str(sgn(ret)))
    except Trap as t:
        rc = t.rc
    return rc, ''.join(s + '\n' for s in it.out)


def build_case(seed):
    g = Gen(seed)
    main = g.generate()
    return g, main


def main():
    args = sys.argv[1:]
    keep = None
    if '--keep' in args:
        i = args.index('--keep')
        keep = args[i + 1]
        del args[i:i + 2]
    sk = os.environ.get('SKITE', './skite')
    if args and args[0] == '--one':      # debugging aid: --one SEED -> program, expected and actual output per argc
        seed = int(args[1])
        g, main_ = build_case(seed)
        src = g.source(main_)
        sys.stdout.write(src)
        tmp = tempfile.mkdtemp(prefix='simpfuzz')
        path = os.path.join(tmp, 'one.ck')
        open(path, 'w').write(src)
        subprocess.run([sk, path, path + '.bin'], check=True, capture_output=True)
        for ac in (1, 2, 4):
            erc, eout = oracle(g, main_, ac)
            q = subprocess.run([path + '.bin'] + ['a'] * (ac - 1), capture_output=True, timeout=10)
            out = q.stdout.decode('latin1')
            rc = q.returncode if q.returncode >= 0 else 128 - q.returncode
            print('--- argc=%d expected rc=%s got rc=%s' % (ac, erc, rc))
            el, gl = eout.splitlines(), out.splitlines()
            for i in range(max(len(el), len(gl))):
                a = el[i] if i < len(el) else '<none>'
                b = gl[i] if i < len(gl) else '<none>'
                print('%4d %s %-24s %-24s' % (i + 1, ' ' if a == b else '*', a, b))
        return
    n = int(args[0]) if args else 100
    seed0 = int(args[1]) if len(args) > 1 else 1
    tmp = tempfile.mkdtemp(prefix='simpfuzz')
    stats = dict(ok=0, skip=0, genfail=0, abort=0, traps=0, runs=0)
    msgs = {}
    for c in range(n):
        seed = seed0 * 1000003 + c
        g, main_ = build_case(seed)
        src = g.source(main_)
        exp = []
        try:
            for ac in (1, 2, 4):
                exp.append(oracle(g, main_, ac))
        except Abort:
            stats['abort'] += 1
            continue
        path = os.path.join(tmp, 's%d.ck' % c)
        with open(path, 'w') as f: f.write(src)
        exe = os.path.join(tmp, 's%d.bin' % c)
        p = subprocess.run([sk, path, exe], capture_output=True, text=True)
        if p.returncode != 0:
            msg = (p.stderr.strip().splitlines() or ['?'])[0]
            key = msg.split(': ', 2)[-1] if ': ' in msg else msg
            if 'division by zero' in msg or 'signed division overflows' in msg:
                stats['skip'] += 1
                continue
            if p.returncode == 1 and 'error' in msg:
                stats['genfail'] += 1
                msgs[key] = msgs.get(key, 0) + 1
                if msgs[key] <= 1 and os.environ.get('SHOWGEN'):
                    print('GENFAIL seed=%d: %s' % (seed, msg))
                continue
            print('COMPILER CRASH seed=%d rc=%d\n%s' % (seed, p.returncode, p.stderr[:500]))
            os.replace(path, 'simp_crash_%d.ck' % seed)
            sys.exit(1)
        bad = None
        for ac, (erc, eout) in zip((1, 2, 4), exp):
            try:
                q = subprocess.run([exe] + ['a'] * (ac - 1), capture_output=True, timeout=10)
                rc, out = (q.returncode if q.returncode >= 0 else 128 - q.returncode), q.stdout.decode('latin1')
            except subprocess.TimeoutExpired:
                rc, out = 'TIMEOUT', ''
            stats['runs'] += 1
            if erc: stats['traps'] += 1
            if rc != erc or out != eout:
                bad = (ac, erc, eout, rc, out)
                break
        if bad:
            ac, erc, eout, rc, out = bad
            fn = keep + '/' if keep else ''
            name = '%ssimp_fail_%d.ck' % (fn, seed)
            with open(name, 'w') as f: f.write(src)
            print('MISMATCH seed=%d argc=%d: expected rc=%s got rc=%s -> %s' % (seed, ac, erc, rc, name))
            el, gl = eout.splitlines(), out.splitlines()
            for i in range(max(len(el), len(gl))):
                a = el[i] if i < len(el) else '<none>'
                b = gl[i] if i < len(gl) else '<none>'
                if a != b:
                    print('  first diff at output line %d: expected %s got %s' % (i + 1, a, b))
                    break
            sys.exit(1)
        stats['ok'] += 1
    print('PASS %(ok)d programs (%(runs)d runs, %(traps)d expected traps); skipped %(skip)d (literal div), %(abort)d (too long), %(genfail)d (generator type errors)' % stats)
    if msgs:
        print('generator rejects: ' + '; '.join('%s x%d' % (k, v) for k, v in sorted(msgs.items(), key=lambda kv: -kv[1])[:5]))


if __name__ == '__main__':
    main()
