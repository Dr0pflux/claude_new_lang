#!/usr/bin/env python3
"""Differential fuzzer for skite's INTEGER semantics against C.

Generates random typed programs over i8..u64 (straight-line code, loops, ifs,
arrays, globals, helper functions, deliberate division traps), translates each
to an equivalent C program (every operation spelled out on uint64_t/int64_t so
the C side has no undefined behaviour and models skite's rules: arithmetic in
64 bits, narrow values canonical 64-bit, shift counts mod 64, division traps
exit 136, out-of-bounds exits 132), then compares stdout and exit status.

usage:
  int_diff_gen.py fuzz N SEED [-j JOBS] [--skite PATH] [--keep DIR]
  int_diff_gen.py show SEED          # print the skite + C program for a seed
  int_diff_gen.py reduce SEED        # minimise the mismatch for a seed
"""
import os, sys, random, subprocess, tempfile, shutil, argparse, copy, time

M64 = (1 << 64) - 1
MAXI = (1 << 63) - 1
MINI = -(1 << 63)


def s64(v):
    v &= M64
    return v - (1 << 64) if v >> 63 else v


TYPES = ['i8', 'i16', 'i32', 'i64', 'u8', 'u16', 'u32', 'u64']
BITS = dict(i8=8, i16=16, i32=32, i64=64, u8=8, u16=16, u32=32, u64=64)
CST = dict(i8='int8_t', i16='int16_t', i32='int32_t', i64='int64_t',
           u8='uint8_t', u16='uint16_t', u32='uint32_t', u64='uint64_t',
           bool='int', lit='int64_t')


def signed(t):
    return t[0] == 'i'


def tmin(t):
    return -(1 << (BITS[t] - 1)) if signed(t) else 0


def tmax(t):
    return (1 << (BITS[t] - 1)) - 1 if signed(t) else (1 << BITS[t]) - 1


def fits(v, t):
    return tmin(t) <= v <= tmax(t)


def widens(s, t):
    if s == t:
        return True
    if s in ('bool', 'lit') or t in ('bool', 'lit'):
        return False
    if signed(s):
        return signed(t) and BITS[t] >= BITS[s]
    return (not signed(t) and BITS[t] >= BITS[s]) or (signed(t) and BITS[t] > BITS[s])


def promote(t):
    return 'u64' if t == 'u64' else 'i64'


def binres(a, b):
    """promoted type of an arithmetic/compare op, or None (compile error)."""
    if a == 'lit' and b == 'lit':
        return 'lit'
    if a == 'lit':
        return promote(b)
    if b == 'lit':
        return promote(a)
    pa, pb = promote(a), promote(b)
    if pa == pb:
        return pa
    if (pa == 'u64' and not signed(b)) or (pb == 'u64' and not signed(a)):
        return 'u64'
    return None


def wrapv(v, t):
    """canonical 64-bit value (python int) of v as type t."""
    if t in ('i64', 'lit'):
        return s64(v)
    if t == 'u64':
        return v & M64
    if t == 'bool':
        return v & 1
    b = BITS[t]
    v &= (1 << b) - 1
    if signed(t) and v >> (b - 1):
        v -= 1 << b
    return v


class Invalid(Exception):
    pass


# ---------------------------------------------------------------- expressions
PREC = {'||': 1, '&&': 2, '==': 3, '!=': 3, '<': 3, '<=': 3, '>': 3, '>=': 3,
        '|': 4, '^': 5, '&': 6, '<<': 7, '>>': 7, '>>>': 7,
        '+': 8, '-': 8, '*': 9, '/': 9, '%': 9}
CMP = ('==', '!=', '<', '<=', '>', '>=')
SHIFTS = ('<<', '>>', '>>>')


class Var:
    def __init__(s, name, ty, mut=False, const=False, val=None, ro=False, glob=False):
        s.name, s.ty, s.mut, s.const, s.val, s.ro, s.glob = name, ty, mut, const, val, ro, glob


class Arr:
    def __init__(s, name, ety, n=16, view=False, glob=False, mut=True):
        s.name, s.ety, s.n, s.view, s.glob, s.mut = name, ety, n, view, glob, mut


class Fn:
    def __init__(s, name, params, ret):
        s.name, s.params, s.ret = name, params, ret   # params: list of (Var | Arr)
        s.body = []
        s.retstmt = None


class E:
    __slots__ = ('k', 'ty', 'kids', 'const', 'val', 'op', 'var', 'arr', 'fn')

    def __init__(s, k, ty, kids=(), const=False, val=None, op=None, var=None, arr=None, fn=None):
        s.k, s.ty, s.kids, s.const, s.val, s.op, s.var, s.arr, s.fn = k, ty, list(kids), const, val, op, var, arr, fn


def Lit(v):
    """integer literal expression; v may be anything representable."""
    if v == MINI:
        return Bin('-', Lit(-MAXI), Lit(1))
    if v > MAXI:
        return E('lit', 'u64', const=True, val=v)
    return E('lit', 'lit', const=True, val=v)


def BoolLit(b):
    return E('blit', 'bool', const=True, val=int(b))


def VarRef(v):
    if v.const:
        return E('var', v.ty, const=True, val=v.val, var=v)
    return E('var', v.ty, var=v)


def ArgcE():
    return E('argc', 'i64')


def Load(arr, idx):
    return E('load', arr.ety, [idx], arr=arr)


def Call(fn, args):
    return E('call', fn.ret, args, fn=fn)


def Cast(a, t):
    if a.ty == t and False:
        return a
    e = E('cast', t, [a], op=t)
    if a.const:
        v = a.val
        e.const, e.val = True, wrapv(v, t)
    return e


def Un(op, a):
    if op == '!':
        e = E('un', 'bool', [a], op=op)
        if a.const:
            e.const, e.val = True, int(a.val == 0)
        return e
    if op == '+':
        e = E('un', a.ty, [a], op=op)
        if a.const:
            e.const, e.val = True, a.val
        return e
    if op == '-' and a.ty == 'u64':
        raise Invalid
    ty = 'lit' if a.ty == 'lit' else promote(a.ty)
    e = E('un', ty, [a], op=op)
    if a.const:
        v = a.val
        e.const = True
        if ty == 'u64':
            e.val = (~v) & M64
        else:
            e.val = s64(-v if op == '-' else ~v)
    return e


def cbin(op, x, y, P):
    """x, y python ints (canonical); P in 'I','U'. returns python int, or raises Invalid on trap."""
    if P == 'U':
        x &= M64
        y &= M64
    else:
        x, y = s64(x), s64(y)
    if op == '+':
        r = x + y
    elif op == '-':
        r = x - y
    elif op == '*':
        r = x * y
    elif op in ('/', '%'):
        if y == 0 or (P == 'I' and x == MINI and y == -1):
            raise Invalid
        if P == 'U':
            r = x // y if op == '/' else x % y
        else:
            q = abs(x) // abs(y)
            if (x < 0) != (y < 0):
                q = -q
            r = q if op == '/' else x - q * y
    elif op == '&':
        r = x & y
    elif op == '|':
        r = x | y
    elif op == '^':
        r = x ^ y
    elif op == '<<':
        r = x << (y & 63)
    elif op == '>>':
        r = x >> (y & 63)          # python >> on negative int is arithmetic
    elif op == '>>>':
        r = (x & M64) >> (y & 63)
    elif op == '==':
        return int(x == y)
    elif op == '!=':
        return int(x != y)
    elif op == '<':
        return int(x < y)
    elif op == '<=':
        return int(x <= y)
    elif op == '>':
        return int(x > y)
    elif op == '>=':
        return int(x >= y)
    else:
        raise AssertionError(op)
    return r & M64 if P == 'U' else s64(r)


def Bin(op, a, b):
    if op in ('&&', '||'):
        assert a.ty == 'bool' and b.ty == 'bool'
        e = E('bin', 'bool', [a, b], op=op)
        if a.const and op == '&&' and not a.val:
            e.const, e.val = True, 0
        elif a.const and op == '||' and a.val:
            e.const, e.val = True, 1
        elif a.const and b.const:
            e.const, e.val = True, int(bool(a.val and b.val) if op == '&&' else bool(a.val or b.val))
        elif a.const:
            pass
        return e
    if a.ty == 'bool' or b.ty == 'bool':
        assert a.ty == b.ty and op in ('==', '!=', '&', '|', '^')
        e = E('bin', 'bool', [a, b], op=op)
        if a.const and b.const:
            e.const = True
            x, y = a.val, b.val
            e.val = {'==': int(x == y), '!=': int(x != y), '&': x & y, '|': x | y, '^': x ^ y}[op]
        return e
    if op in SHIFTS:
        ty = 'lit' if (a.ty == 'lit' and b.ty == 'lit') else promote(a.ty)
        P = 'U' if ty == 'u64' else 'I'
        if ty == 'u64' and op == '>>':
            pass
        e = E('bin', ty, [a, b], op=op)
    else:
        ty = binres(a.ty, b.ty)
        if ty is None:
            raise Invalid
        P = 'U' if ty == 'u64' else 'I'
        if op in CMP:
            e = E('bin', 'bool', [a, b], op=op)
        else:
            e = E('bin', ty, [a, b], op=op)
    # compile-time trap checks (the parser rejects constant divisors of zero / MIN/-1 folds)
    if op in ('/', '%'):
        if b.const and b.val == 0:
            raise Invalid
        if b.const and a.const:
            cbin(op, a.val, b.val, P)    # may raise Invalid
    if P == 'U' and ty == 'u64' or ty == 'lit':
        # literal operands adopting u64 must be non-negative
        pass
    if op not in SHIFTS:
        for x in (a, b):
            if x.ty == 'lit' and ty == 'u64' and x.val < 0:
                raise Invalid
    if a.const and b.const:
        e.const = True
        try:
            e.val = cbin(op, a.val, b.val, P)
        except Invalid:
            raise
    return e


def coerce(e, t):
    """make e implicitly convertible to int type / bool t, adding a cast if necessary."""
    if t == 'bool':
        assert e.ty == 'bool'
        return e
    if e.ty == 'lit':
        if e.const and fits(e.val, t):
            return e
        return Cast(e, t)
    if widens(e.ty, t):
        return e
    return Cast(e, t)


# ---------------------------------------------------------------- skite text
def prec_of(e):
    if e.k == 'bin':
        return PREC[e.op]
    if e.k == 'cast':
        return 10
    if e.k == 'un':
        return 11
    if e.k == 'lit':
        return 11 if (e.val < 0) else 12
    return 12


def litstr(v, rnd=None):
    neg = v < 0
    a = abs(v)
    if rnd is not None and rnd.random() < 0.2 and a >= 0:
        s = hex(a)
    elif rnd is not None and rnd.random() < 0.05 and a >= 1000:
        t = str(a)
        s = ''
        while len(t) > 3:
            s = '_' + t[-3:] + s
            t = t[:-3]
        s = t + s
    else:
        s = str(a)
    return ('-' if neg else '') + s


def sk(e, minp=0, full=False):
    t = _sk(e, full)
    p = prec_of(e)
    if p < minp or (full and p < 12 and minp > 0):
        return '(' + t + ')'
    return t


def _sk(e, full):
    k = e.k
    if k == 'lit':
        return litstr(e.val, random.Random(e.val * 31 + 7))
    if k == 'blit':
        return 'true' if e.val else 'false'
    if k == 'var':
        return e.var.name
    if k == 'argc':
        return 'argc()'
    if k == 'load':
        return '%s[%s]' % (e.arr.name, sk(e.kids[0], 0, full))
    if k == 'call':
        return '%s(%s)' % (e.fn.name, ', '.join(a if isinstance(a, str) else sk(a, 0, full) for a in e.kids))
    if k == 'cast':
        return '%s as %s' % (sk(e.kids[0], 10, full), e.op)
    if k == 'un':
        c = sk(e.kids[0], 11, full)
        if e.op in '-+' and c[0] in '-+':
            c = '(' + c + ')'
        return e.op + c
    if k == 'bin':
        p = PREC[e.op]
        if e.op in CMP:
            return '%s %s %s' % (sk(e.kids[0], p + 1, full), e.op, sk(e.kids[1], p + 1, full))
        return '%s %s %s' % (sk(e.kids[0], p, full), e.op, sk(e.kids[1], p + 1, full))
    raise AssertionError(k)


# ---------------------------------------------------------------- C text
def P_of(ty):
    return 'U' if ty == 'u64' else 'I'


def clit(v):
    if v == MINI:
        return '(-INT64_C(9223372036854775807)-1)'
    if v > MAXI:
        return 'UINT64_C(%d)' % v
    if v < 0:
        return '(-INT64_C(%d))' % -v
    return 'INT64_C(%d)' % v


def cconv(x, P):
    return '((%s)(%s))' % (P, x)


def ce(e):
    k = e.k
    if k == 'raw':
        return e.op
    if k == 'lit':
        return clit(e.val)
    if k == 'blit':
        return '1' if e.val else '0'
    if k == 'var':
        v = e.var
        if v.ty in ('u64', 'lit', 'bool') or v.ty == 'i64':
            return v.name
        return '((I)%s)' % v.name
    if k == 'argc':
        return '((I)argc)'
    if k == 'load':
        a = e.arr
        idx = '(U)(%s)' % ce(e.kids[0])
        if a.view:
            x = 'ld_%s(%s)' % (a.ety, idx)
        else:
            x = '%s[chk(%s, %d)]' % (a.name, idx, a.n)
        return x if a.ety in ('u64', 'i64') else '((I)%s)' % x
    if k == 'call':
        args = []
        for p, a in zip(e.fn.params, e.kids):
            if isinstance(p, Arr):
                args.append(a)         # array name strings
            else:
                args.append('(%s)(%s)' % (CST[p.ty], ce(a)))
        x = '%s(%s)' % (e.fn.name, ', '.join(args))
        return x if e.ty in ('u64', 'i64') else '((I)%s)' % x
    if k == 'cast':
        a = e.kids[0]
        t = e.op
        if t == 'u64':
            return '((U)(%s))' % ce(a)
        if t == 'i64':
            return '((I)(%s))' % ce(a)
        return '((I)(%s)(%s))' % (CST[t], ce(a))
    if k == 'un':
        a = e.kids[0]
        P = P_of(e.ty)
        if e.op == '!':
            return '(!(%s))' % ce(a)
        if e.op == '+':
            return ce(a)
        if e.op == '-':
            return '((%s)(0 - (U)(%s)))' % (P, ce(a))
        return '((%s)(~(U)(%s)))' % (P, ce(a))
    if k == 'bin':
        a, b = e.kids
        op = e.op
        if op in ('&&', '||'):
            return '(%s %s %s)' % (ce(a), op, ce(b))
        if a.ty == 'bool':
            cop = {'&': '&', '|': '|', '^': '^', '==': '==', '!=': '!='}[op]
            return '((I)(%s %s %s))' % (ce(a), cop, ce(b))
        A, B = ce(a), ce(b)
        if op in SHIFTS:
            P = P_of(e.ty)
            cnt = '((U)(%s) & 63)' % B
            if op == '<<':
                return '((%s)((U)(%s) << %s))' % (P, A, cnt)
            if op == '>>':
                return '((%s)(%s) >> %s)' % (P, A, cnt)
            return '((%s)((U)(%s) >> %s))' % (P, A, cnt)
        rt = binres(a.ty, b.ty)
        P = P_of(rt)
        if op in CMP:
            return '((I)(%s %s %s))' % (cconv(A, P), op, cconv(B, P))
        if op in ('+', '-', '*'):
            return '((%s)((U)(%s) %s (U)(%s)))' % (P, A, op, B)
        if op == '/':
            return ('div_u(%s, %s)' if P == 'U' else 'div_s(%s, %s)') % (cconv(A, P), cconv(B, P))
        if op == '%':
            return ('mod_u(%s, %s)' if P == 'U' else 'mod_s(%s, %s)') % (cconv(A, P), cconv(B, P))
        return '(%s %s %s)' % (cconv(A, P), op, cconv(B, P))
    raise AssertionError(k)


# ---------------------------------------------------------------- statements
class S:
    pass


def ind(n):
    return '    ' * n


def cty(v):
    return CST[v.ty]


class SLet(S):
    def __init__(s, var, e, ann=True):
        s.var, s.e, s.ann = var, e, ann

    def sk(s, n, full):
        v = s.var
        kw = 'let mut' if v.mut else 'let'
        ann = ': %s' % v.ty if (s.ann and v.ty not in ('lit', 'bool')) else (': bool' if (s.ann and v.ty == 'bool') else '')
        return [ind(n) + '%s %s%s = %s;' % (kw, v.name, ann, sk(s.e, 0, full))]

    def c(s, n):
        v = s.var
        cv = '' if v.mut else 'const '
        return [ind(n) + '%s%s %s = (%s)(%s);' % (cv, cty(v), v.name, cty(v), ce(s.e))]


class SAssign(S):
    def __init__(s, var, e):
        s.var, s.e = var, e

    def sk(s, n, full):
        return [ind(n) + '%s = %s;' % (s.var.name, sk(s.e, 0, full))]

    def c(s, n):
        return [ind(n) + '%s = (%s)(%s);' % (s.var.name, cty(s.var), ce(s.e))]


def Bin_nofold(op, a, b):
    if op in SHIFTS:
        ty = 'lit' if (a.ty == 'lit' and b.ty == 'lit') else promote(a.ty)
    else:
        ty = binres(a.ty, b.ty)
        assert ty is not None
    e = E('bin', ty, [a, b], op=op)
    return e


class SOpAssign(S):
    def __init__(s, var, op, e):
        s.var, s.op, s.e = var, op, e

    def sk(s, n, full):
        return [ind(n) + '%s %s= %s;' % (s.var.name, s.op, sk(s.e, 0, full))]

    def c(s, n):
        v = s.var
        cur = E('var', v.ty, var=v)
        b = Bin_nofold(s.op, cur, s.e)
        x = ce(b)
        if v.ty == 'bool':
            return [ind(n) + '%s = (%s)(%s);' % (v.name, cty(v), x)]
        return [ind(n) + '%s = (%s)(%s);' % (v.name, cty(v), x)]


class SStore(S):
    def __init__(s, arr, idx, e, op=None):
        s.arr, s.idx, s.e, s.op = arr, idx, e, op

    def sk(s, n, full):
        return [ind(n) + '%s[%s] %s= %s;' % (s.arr.name, sk(s.idx, 0, full), s.op or '', sk(s.e, 0, full)) if s.op
                else ind(n) + '%s[%s] = %s;' % (s.arr.name, sk(s.idx, 0, full), sk(s.e, 0, full))]

    def c(s, n):
        a = s.arr
        ct = CST[a.ety]
        # value first, then index, then bounds check (skite order)
        valx = ce(s.e)
        out = [ind(n) + '{']
        out.append(ind(n + 1) + '%s val_ = %s;' % ('U' if s.e.ty == 'u64' else 'I', valx))
        out.append(ind(n + 1) + 'U k_ = chk((U)(%s), %d);' % (ce(s.idx), a.n))
        if s.op:
            cur = E('raw', a.ety)
            cur.op = '%s[k_]' % a.name
            val = E('raw', s.e.ty)
            val.op = 'val_'
            out.append(ind(n + 1) + '%s[k_] = (%s)(%s);' % (a.name, ct, ce(Bin_nofold(s.op, cur, val))))
        else:
            out.append(ind(n + 1) + '%s[k_] = (%s)val_;' % (a.name, ct))
        out.append(ind(n) + '}')
        return out


class SPrint(S):
    def __init__(s, e):
        s.e = e

    def sk(s, n, full):
        return [ind(n) + 'print(%s);' % sk(s.e, 0, full)]

    def c(s, n):
        t = s.e.ty
        f = 'prb' if t == 'bool' else ('pru' if t == 'u64' else 'pri')
        return [ind(n) + '%s(%s);' % (f, ce(s.e))]


class SBreak(S):
    def __init__(s, kw):
        s.kw = kw

    def sk(s, n, full):
        return [ind(n) + s.kw + ';']

    def c(s, n):
        return [ind(n) + s.kw + ';']


class SReturn(S):
    def __init__(s, e, ret):
        s.e, s.ret = e, ret

    def sk(s, n, full):
        return [ind(n) + 'return %s;' % sk(s.e, 0, full)]

    def c(s, n):
        return [ind(n) + 'return (%s)(%s);' % (CST[s.ret], ce(s.e))]


class SCall(S):
    def __init__(s, call):
        s.call = call

    def sk(s, n, full):
        return [ind(n) + sk(s.call, 0, full) + ';']

    def c(s, n):
        return [ind(n) + ce_call_stmt(s.call) + ';']


def ce_call_stmt(e):
    args = []
    for p, a in zip(e.fn.params, e.kids):
        if isinstance(p, Arr):
            args.append(a)
        else:
            args.append('(%s)(%s)' % (CST[p.ty], ce(a)))
    return '%s(%s)' % (e.fn.name, ', '.join(args))


class SIf(S):
    def __init__(s, cond, then, els):
        s.cond, s.then, s.els = cond, then, els

    def sk(s, n, full):
        out = [ind(n) + 'if %s {' % sk(s.cond, 0, full)]
        for st in s.then:
            out += st.sk(n + 1, full)
        if s.els:
            out.append(ind(n) + '} else {')
            for st in s.els:
                out += st.sk(n + 1, full)
        out.append(ind(n) + '}')
        return out

    def c(s, n):
        out = [ind(n) + 'if (%s) {' % ce(s.cond)]
        for st in s.then:
            out += st.c(n + 1)
        if s.els:
            out.append(ind(n) + '} else {')
            for st in s.els:
                out += st.c(n + 1)
        out.append(ind(n) + '}')
        return out


class SWhile(S):
    """while cond { [cur=ctr; step;] body [step;] }  (step is not reducible: guarantees termination)"""
    def __init__(s, cond, body, step, step_first, cur=None):
        s.cond, s.body, s.step, s.step_first, s.cur = cond, body, step, step_first, cur

    def sk(s, n, full):
        out = [ind(n) + 'while %s {' % sk(s.cond, 0, full)]
        if s.step_first:
            out += s.cur.sk(n + 1, full)
            out += s.step.sk(n + 1, full)
        for st in s.body:
            out += st.sk(n + 1, full)
        if not s.step_first:
            out += s.step.sk(n + 1, full)
        out.append(ind(n) + '}')
        return out

    def c(s, n):
        out = [ind(n) + 'while (%s) {' % ce(s.cond)]
        if s.step_first:
            out += s.cur.c(n + 1)
            out += s.step.c(n + 1)
        for st in s.body:
            out += st.c(n + 1)
        if not s.step_first:
            out += s.step.c(n + 1)
        out.append(ind(n) + '}')
        return out


# ---------------------------------------------------------------- program
class Program:
    def __init__(s):
        s.full = False
        s.gvars = []       # global Var decls (SLet-like): (var, init literal expr)
        s.garrs = []
        s.fns = []
        s.decls = []       # main top-level decl statements (not reduced as lists)
        s.views = []
        s.body = []
        s.data = b''

    def skite(s):
        f = s.full
        out = []
        for v in s.gvars:
            kw = 'let mut' if v.mut else 'let'
            ann = '' if v.ty == 'lit' else ': ' + v.ty
            out.append('%s %s%s = %s;' % (kw, v.name, ann, litstr(v.val)))
        for a in s.garrs:
            out.append('let %s = alloc<%s>(%d);' % (a.name, a.ety, a.n))
        for fn in s.fns:
            ps = []
            for p in fn.params:
                if isinstance(p, Arr):
                    ps.append('%s: %s[%s]' % (p.name, 'mut ' if p.mut else '', p.ety))
                else:
                    ps.append('%s%s: %s' % ('mut ' if p.mut else '', p.name, p.ty))
            ps = ', '.join(ps)
            out.append('fn %s(%s)%s {' % (fn.name, ps, (' -> ' + fn.ret) if fn.ret else ''))
            for st in fn.body:
                out += st.sk(1, f)
            if fn.retstmt:
                out += fn.retstmt.sk(1, f)
            out.append('}')
        out.append('fn main() {')
        out.append('    let f = file(1);')
        for a in s.views:
            out.append('    let %s = view<%s>(f);' % (a.name, a.ety))
        for st in s.decls:
            out += st.sk(1, f)
        for st in s.body:
            out += st.sk(1, f)
        out.append('}')
        return '\n'.join(out) + '\n'

    def c(s):
        o = [C_PRELUDE]
        for a in s.views:
            o.append('LDV(%s, ld_%s)' % (CST[a.ety], a.ety))
        for v in s.gvars:
            o.append('static %s%s %s = %s;' % ('' if v.mut else 'const ', CST[v.ty], v.name, clit(v.val)))
        for a in s.garrs:
            o.append('static %s %s[%d];' % (CST[a.ety], a.name, a.n))
        for fn in s.fns:
            o.append('static %s %s(%s);' % (CST[fn.ret] if fn.ret else 'void', fn.name, cparams(fn)))
        for fn in s.fns:
            o.append('static %s %s(%s) {' % (CST[fn.ret] if fn.ret else 'void', fn.name, cparams(fn)))
            for st in fn.body:
                o += st.c(1)
            if fn.retstmt:
                o += fn.retstmt.c(1)
            o.append('}')
        o.append('int main(int argc, char **argv) {')
        o.append('    FILE *fp = fopen(argv[1], "rb"); if (!fp || fread(data, 1, sizeof data, fp) != sizeof data) return 99; fclose(fp);')
        o.append('    (void)argc;')
        for a in s.decls:
            o += a.c(1)
        for st in s.body:
            o += st.c(1)
        o.append('    fflush(stdout);')
        o.append('    return 0;')
        o.append('}')
        return '\n'.join(o) + '\n'


def cparams(fn):
    ps = []
    for p in fn.params:
        if isinstance(p, Arr):
            ps.append('%s *%s' % (CST[p.ety], p.name))
        else:
            ps.append('%s %s' % (CST[p.ty], p.name))
    return ', '.join(ps) or 'void'


C_PRELUDE = r'''#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <inttypes.h>
typedef int64_t I;
typedef uint64_t U;
static void trap(int rc) { fflush(stdout); _exit(rc); }
static I div_s(I a, I b) { if (b == 0 || (a == INT64_MIN && b == -1)) trap(136); return a / b; }
static I mod_s(I a, I b) { if (b == 0 || (a == INT64_MIN && b == -1)) trap(136); return a % b; }
static U div_u(U a, U b) { if (b == 0) trap(136); return a / b; }
static U mod_u(U a, U b) { if (b == 0) trap(136); return a % b; }
static U chk(U i, U n) { if (i >= n) trap(132); return i; }
static unsigned char data[1024];
#define LDV(T, N) static T N(U i) { T x; if (i >= 1024 / sizeof(T)) trap(132); memcpy(&x, data + i * sizeof(T), sizeof(T)); return x; }
static void pri(I x) { printf("%" PRId64 "\n", x); }
static void pru(U x) { printf("%" PRIu64 "\n", x); }
static void prb(I x) { puts(x ? "true" : "false"); }
'''


# ---------------------------------------------------------------- program generator
LITV = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 15, 16, 17, 31, 32, 33, 63, 64, 65, 100, 127, 128, 129, 200,
        255, 256, 257, 1000, 4096, 10000, 32767, 32768, 65535, 65536, 65537, 1000000, 0x7fffff, 0xffffff,
        0x7fffffff, 0x80000000, 0xffffffff, 0x100000000, 0x123456789abcdef, MAXI]
DIVV = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 25, 31, 32, 33, 60, 63, 64, 100, 127, 128, 255,
        256, 641, 1000, 1024, 3600, 4095, 4096, 10000, 32767, 32768, 65535, 65536, 65537, 1000000, 1000003,
        0x7fffffff, 0x80000000, 0xffffffff, 0x100000000, 0xfffffffff, 1 << 40, 1 << 62, 3 << 61, MAXI, MAXI - 1,
        0x5555555555555555, 0x123456789abcdef]


class Scope:
    def __init__(s):
        s.vars, s.arrs, s.fns = [], [], []
        s.loop = 0              # loop nesting
        s.cont_ok = False       # `continue` allowed here
        s.fn = None             # enclosing Fn (for return)
        s.ismain = True
        s.pure = False          # inside a side-effect-free function: no output, no global/array stores

    def child(s):
        c = Scope()
        c.vars, c.arrs, c.fns = list(s.vars), list(s.arrs), list(s.fns)
        c.loop, c.cont_ok, c.fn, c.ismain, c.pure = s.loop, s.cont_ok, s.fn, s.ismain, s.pure
        return c


class SDeclArr(S):
    def __init__(s, arr):
        s.arr = arr

    def sk(s, n, full):
        return [ind(n) + 'let %s = alloc<%s>(%d);' % (s.arr.name, s.arr.ety, s.arr.n)]

    def c(s, n):
        return [ind(n) + '%s %s[%d] = {0};' % (CST[s.arr.ety], s.arr.name, s.arr.n)]


def gen_data(R):
    words = []
    specials = [0, 1, 2, 3, 0x7f, 0x80, 0xff, 0x100, 0x7fff, 0x8000, 0xffff, 0x10000, 0x7fffffff, 0x80000000,
                0xffffffff, 0x100000000, MAXI, 1 << 63, M64, M64 - 1, 10, 100, 1000, 0x5555555555555555,
                0xaaaaaaaaaaaaaaaa, 0x00ff00ff00ff00ff, 0x0123456789abcdef]
    for _ in range(128):
        r = R.random()
        if r < 0.22:
            w = R.randint(-8, 8)
        elif r < 0.5:
            w = R.choice(specials) + R.choice([0, 0, 0, 1, -1])
            if R.random() < 0.3:
                w = -w
        elif r < 0.6:
            w = (1 << R.randrange(64)) + R.randint(-1, 1)
        else:
            bits = R.choice([8, 16, 32, 64, 64])
            w = R.getrandbits(bits)
            if R.random() < 0.4 and bits < 64:
                w = wrapv(w, 'i%d' % bits)
        words.append(w & M64)
    return b''.join(w.to_bytes(8, 'little') for w in words)


class Gen:
    def __init__(self, seed):
        self.seed = seed
        self.R = R = random.Random(seed * 7919 + 13)
        self.n = 0
        self.pconst = R.choice([0.03, 0.12, 0.3, 0.6])
        self.depth = R.choice([2, 3, 3, 4])
        self.nstmts = R.choice([6, 12, 20, 30])
        self.p = Program()
        self.p.full = R.random() < 0.3
        self.p.data = gen_data(R)
        self.views = {}
        self.divmix = R.choice([0.03, 0.08, 0.2])
        self.ntrap = 0

    # -- naming
    def nm(self, pre):
        self.n += 1
        return '%s%d' % (pre, self.n)

    def rtype(self):
        R = self.R
        return R.choice(TYPES + ['i64', 'u64', 'i32', 'u8', 'u32'])

    # -- literals
    def lit_val(self, nonneg=False, allow_big=True):
        R = self.R
        r = R.random()
        if r < 0.45:
            v = R.choice(LITV)
        elif r < 0.65:
            v = (1 << R.randrange(1, 64)) + R.choice([-1, 0, 1])
        elif r < 0.75:
            t = R.choice(TYPES)
            v = R.choice([tmin(t), tmax(t), tmin(t) + 1, tmax(t) - 1])
        elif r < 0.9:
            v = R.getrandbits(R.choice([4, 8, 16, 32, 63]))
        else:
            v = R.randint(0, 20)
        if not nonneg and R.random() < 0.3:
            v = -v
        if v > MAXI and not allow_big:
            v = MAXI
        if v < MINI:
            v = MINI
        if v > M64:
            v = M64
        if allow_big and R.random() < 0.03:
            v = R.choice([1 << 63, M64, M64 - 1, (1 << 63) + 1, R.getrandbits(64) | (1 << 63)])
        return v

    def lit(self, nonneg=False, allow_big=True):
        R = self.R
        v = self.lit_val(nonneg, allow_big)
        if abs(v) <= MAXI and R.random() < 0.08:
            # constant expression of two literals (folded by the parser)
            for _ in range(5):
                try:
                    a = Lit(self.lit_val(False, False))
                    b = Lit(self.lit_val(False, False) if R.random() < 0.6 else R.randint(0, 70))
                    op = R.choice(['+', '-', '*', '&', '|', '^', '<<', '>>', '>>>', '/', '%'])
                    e = Bin(op, a, b)
                    if nonneg and e.val < 0:
                        continue
                    return e
                except Invalid:
                    pass
        return Lit(v)

    # -- leaves
    def dyn_vars(self, sc):
        return [v for v in sc.vars if not v.const and v.ty != 'bool']

    def load(self, sc, arr=None):
        R = self.R
        if arr is None:
            arrs = sc.arrs
            if not arrs:
                return None
            arr = R.choice(arrs)
        mask = arr.n - 1
        if R.random() < 0.35:
            idx = Lit(R.randrange(arr.n))
        else:
            idx = Bin('&', self.gen_int(sc, 1), Lit(mask))
        return Load(arr, idx)

    def leaf(self, sc):
        R = self.R
        r = R.random()
        if r < self.pconst:
            cons = [v for v in sc.vars if v.const and v.ty != 'bool']
            if cons and R.random() < 0.5:
                return VarRef(R.choice(cons))
            e = self.lit()
            if R.random() < 0.3:
                e = Cast(e, self.rtype())
            return e
        dv = self.dyn_vars(sc)
        r = R.random()
        if r < 0.7 and dv:
            return VarRef(R.choice(dv))
        if r < 0.95 and sc.arrs:
            return self.load(sc)
        if sc.ismain and R.random() < 0.5:
            return ArgcE()
        return self.lit() if not dv else VarRef(R.choice(dv))

    def dyn_expr(self, sc, d=1):
        """an integer expression that is not a parse-time constant"""
        for _ in range(6):
            e = self.gen_int(sc, d)
            if not e.const:
                return e
        dv = self.dyn_vars(sc)
        if dv:
            return VarRef(self.R.choice(dv))
        return ArgcE()

    # -- pairing
    def fix_pair(self, a, b):
        R = self.R
        for _ in range(3):
            ty = binres(a.ty, b.ty)
            if ty is None:
                if R.random() < 0.5:
                    if a.ty == 'u64':
                        b = Cast(b, 'u64')
                    else:
                        a = Cast(a, 'u64')
                else:
                    if a.ty == 'u64':
                        a = Cast(a, 'i64')
                    else:
                        b = Cast(b, 'i64')
                continue
            if ty == 'u64':
                if a.ty == 'lit' and a.val < 0:
                    a = Cast(a, 'u64')
                if b.ty == 'lit' and b.val < 0:
                    b = Cast(b, 'u64')
            break
        return a, b

    # -- expressions
    def gen_int(self, sc, d):
        for _ in range(8):
            try:
                return self._gen_int(sc, d)
            except Invalid:
                continue
        return VarRef(self.R.choice(self.dyn_vars(sc))) if self.dyn_vars(sc) else Lit(1)

    def _gen_int(self, sc, d):
        R = self.R
        if d <= 0 or R.random() < 0.12:
            return self.leaf(sc)
        r = R.random()
        if r < 0.30:
            a = self.gen_int(sc, d - 1)
            b = self.gen_int(sc, d - 1)
            a, b = self.fix_pair(a, b)
            return Bin(R.choice(['+', '-', '*', '+', '-', '&', '|', '^']), a, b)
        if r < 0.40:
            return self.gen_div(sc, d)
        if r < 0.54:
            a = self.gen_int(sc, d - 1)
            q = R.random()
            if q < 0.4:
                b = Lit(R.choice([0, 1, 2, 3, 4, 7, 8, 12, 15, 16, 17, 24, 31, 32, 33, 40, 48, 56, 62, 63, 64, 65, 100, 127, 128, 255, -1, -2, -63, -64, -65]))
            elif q < 0.6:
                b = Bin('&', self.gen_int(sc, d - 1), Lit(R.choice([7, 15, 31, 63, 63, 63, 127])))
            else:
                b = self.gen_int(sc, d - 1)
            return Bin(R.choice(SHIFTS), a, b)
        if r < 0.62:
            a = self.gen_int(sc, d - 1)
            op = R.choice(['-', '~', '~', '+', '-'])
            if op == '-' and a.ty == 'u64':
                return Un('~', a) if R.random() < 0.5 else Un('-', Cast(a, 'i64'))
            return Un(op, a)
        if r < 0.80:
            a = self.gen_int(sc, d - 1)
            return Cast(a, self.rtype())
        if r < 0.86:
            return Cast(self.gen_bool(sc, d - 1), self.rtype())
        if r < 0.92 and sc.fns:
            c = self.gen_call(sc, d)
            if c is not None:
                return c
        if r < 0.95 and sc.arrs:
            return self.load(sc)
        return self.leaf(sc)

    def gen_div(self, sc, d):
        R = self.R
        op = R.choice(['/', '%'])
        a = self.gen_int(sc, d - 1)
        q = R.random()
        if q < 0.5:
            nonneg = (a.ty == 'u64')
            v = R.choice(DIVV)
            if R.random() < 0.8 and not nonneg:
                v = -v if R.random() < 0.4 else v
            if R.random() < 0.08:
                v = -1 if not nonneg else 1
            if R.random() < 0.02:
                v = MINI if not nonneg else M64
            b = self.lit(nonneg=False) if False else Lit(v)
            if b.ty == 'lit' and v == -1 and a.const:
                a = self.dyn_expr(sc, d - 1)
        elif q < 0.65:
            b = Bin('|', self.dyn_expr(sc, d - 1), Lit(1))
        elif q < 0.65 + self.divmix:
            b = self.dyn_expr(sc, d - 1)
        elif q < 0.88:
            b = Bin('+', Bin('&', self.dyn_expr(sc, d - 1), Lit(R.choice([3, 7, 15, 255]))), Lit(R.choice([1, 1, 2, 5])))
        else:
            b = Bin('|', Cast(self.dyn_expr(sc, d - 1), R.choice(['u8', 'i8', 'u16', 'i16', 'u32', 'i32'])), Lit(1))
        a, b = self.fix_pair(a, b)
        return Bin(op, a, b)

    def gen_call(self, sc, d):
        R = self.R
        fns = [f for f in sc.fns if f.ret]
        if not fns:
            return None
        f = R.choice(fns)
        args = []
        for p in f.params:
            if isinstance(p, Arr):
                cands = [a for a in sc.arrs if a.ety == p.ety and not a.view and a.n == p.n]
                if not cands:
                    return None
                args.append(R.choice(cands).name)
            else:
                args.append(coerce(self.gen_int(sc, max(0, d - 1)), p.ty))
        return Call(f, args)

    def gen_bool(self, sc, d):
        R = self.R
        bv = [v for v in sc.vars if v.ty == 'bool']
        r = R.random()
        if d <= 0 and r < 0.2 and bv:
            return VarRef(R.choice(bv))
        if r < 0.58 or d <= 0:
            a = self.gen_int(sc, max(0, d - 1))
            if R.random() < 0.3:
                b = self.lit()
            else:
                b = self.gen_int(sc, max(0, d - 1))
            a, b = self.fix_pair(a, b)
            return Bin(R.choice(CMP), a, b)
        if r < 0.68 and bv:
            return VarRef(R.choice(bv))
        if r < 0.78:
            return Un('!', self.gen_bool(sc, d - 1))
        if r < 0.80:
            return BoolLit(R.random() < 0.5)
        a = self.gen_bool(sc, d - 1)
        b = self.gen_bool(sc, d - 1)
        return Bin(R.choice(['&&', '||', '&', '|', '^', '==', '!=']), a, b)

    def gen_for(self, sc, t, d=None):
        """expression convertible to int type t (or bool)"""
        d = self.depth if d is None else d
        if t == 'bool':
            return self.gen_bool(sc, d)
        return coerce(self.gen_int(sc, d), t)

    # -- statements
    def gen_assign(self, sc):
        R = self.R
        muts = [v for v in sc.vars if v.mut and not v.ro]
        if not muts:
            return None
        v = R.choice(muts)
        r = R.random()
        if v.ty == 'bool':
            if r < 0.7:
                return SAssign(v, self.gen_bool(sc, self.depth))
            return SOpAssign(v, R.choice(['&', '|', '^']), self.gen_bool(sc, self.depth - 1))
        if r < 0.45:
            return SAssign(v, self.gen_for(sc, v.ty))
        op = R.choice(['+', '-', '*', '/', '%', '&', '|', '^', '<<', '>>', '>>>', '+', '-', '<<', '>>'])
        d = max(1, self.depth - 1)
        if op in SHIFTS:
            e = self.gen_int(sc, d)
            if R.random() < 0.4:
                e = Lit(R.choice([0, 1, 3, 7, 8, 15, 16, 31, 32, 63, 64, 65, -1]))
        elif op in ('/', '%'):
            e = self.gen_div_operand(sc, v.ty, d)
        else:
            e = self.gen_int(sc, d)
        if op not in SHIFTS:
            if binres(v.ty, e.ty) is None:
                e = Cast(e, v.ty)
            elif e.ty == 'lit' and v.ty == 'u64' and e.val < 0:
                e = Cast(e, 'u64')
        return SOpAssign(v, op, e)

    def gen_div_operand(self, sc, vty, d):
        """divisor for `x op= e` with x of type vty"""
        R = self.R
        q = R.random()
        if q < 0.5:
            v = R.choice(DIVV)
            if vty != 'u64' and R.random() < 0.4:
                v = -v
            if R.random() < 0.08 and vty != 'u64':
                v = -1
            return Lit(v)
        if q < 0.75:
            return Bin('|', self.dyn_expr(sc, d), Lit(1))
        if q < 0.75 + self.divmix:
            return self.dyn_expr(sc, d)
        return Bin('+', Bin('&', self.dyn_expr(sc, d), Lit(R.choice([3, 7, 15, 255]))), Lit(1))

    def gen_store(self, sc):
        R = self.R
        arrs = [a for a in sc.arrs if not a.view and a.mut]
        if not arrs:
            return None
        a = R.choice(arrs)
        if R.random() < 0.04:
            idx = self.gen_int(sc, 2)                  # raw index: may trap (SIGILL)
        elif R.random() < 0.3:
            idx = Lit(R.randrange(a.n))
        else:
            idx = Bin('&', self.gen_int(sc, 2), Lit(a.n - 1))
        if R.random() < 0.55:
            return SStore(a, idx, self.gen_for(sc, a.ety))
        op = R.choice(['+', '-', '*', '&', '|', '^', '<<', '>>', '>>>', '/', '%', '+', '-'])
        d = max(1, self.depth - 1)
        if op in SHIFTS:
            e = self.gen_int(sc, d)
        elif op in ('/', '%'):
            e = self.gen_div_operand(sc, a.ety, d)
        else:
            e = self.gen_int(sc, d)
        if op not in SHIFTS:
            if binres(a.ety, e.ty) is None:
                e = Cast(e, a.ety)
            elif e.ty == 'lit' and a.ety == 'u64' and e.val < 0:
                e = Cast(e, 'u64')
        return SStore(a, idx, e, op)

    def gen_print(self, sc):
        R = self.R
        r = R.random()
        if r < 0.35:
            cands = [v for v in sc.vars if not v.const or R.random() < 0.3]
            if cands:
                return SPrint(VarRef(R.choice(cands)))
        if r < 0.5:
            return SPrint(self.gen_bool(sc, self.depth))
        return SPrint(self.gen_int(sc, self.depth))

    def gen_let(self, sc):
        R = self.R
        if R.random() < 0.15:
            e = self.gen_bool(sc, self.depth)
        else:
            e = self.gen_int(sc, self.depth)
        name = self.nm('tmp')
        if R.random() < 0.3 and not e.const:
            # mutable local
            ty = 'i64' if e.ty == 'lit' else e.ty
            v = Var(name, ty, mut=True)
            sc.vars.append(v)
            return SLet(v, e, ann=R.random() < 0.5)
        if e.const:
            v = Var(name, e.ty, const=True, val=e.val)
            ann = False
            if e.ty != 'lit' and e.ty != 'bool' and R.random() < 0.5:
                ann = True
            sc.vars.append(v)
            return SLet(v, e, ann=ann)
        v = Var(name, e.ty)
        sc.vars.append(v)
        return SLet(v, e, ann=R.random() < 0.3)

    def gen_if(self, sc, depth):
        R = self.R
        cond = self.gen_bool(sc, self.depth)
        then = self.gen_block(sc, R.randint(1, 3), depth - 1)
        els = self.gen_block(sc, R.randint(1, 2), depth - 1) if R.random() < 0.4 else None
        return SIf(cond, then, els)

    def gen_while(self, sc, depth):
        R = self.R
        pre = []
        up = R.random() < 0.65
        cty_ = R.choice(['i64', 'i32', 'u8', 'i8', 'u32', 'u16', 'i16', 'u64', 'i64', 'u8', 'i32'])
        ctr = Var(self.nm('ctr'), cty_, mut=True, ro=True)
        nest = sc.loop
        big = R.random() < 0.2 and nest == 0
        lim = 70 if cty_ in ('i8',) else 200
        if big:
            N = R.randint(20, 60)
        else:
            N = R.randint(1, 8 if nest else 16)
        bound = None
        if R.random() < 0.2:
            nv = Var(self.nm('nb'), 'i64')
            e = Bin('&', self.gen_int(sc, 1), Lit(R.choice([3, 7, 15])))
            if cty_ == 'u64':
                e = Cast(e, 'u64')
            else:
                e = Cast(e, cty_) if binres(cty_, e.ty) is None else e
            nv = Var(self.nm('nb'), e.ty, const=e.const, val=e.val)
            pre.append(SLet(nv, e))
            sc.vars.append(nv)
            bound = VarRef(nv)
        else:
            bound = Lit(N)
        if up:
            step = R.choice([1, 1, 1, 2, 3])
            pre.append(SLet(ctr, Lit(0), ann=True))
            c = VarRef(ctr)
            a, b = self.fix_pair(c, bound)
            cond = Bin(R.choice(['<', '<', '!=' if step == 1 and bound.const or step == 1 else '<']) if step == 1 else '<', a, b)
            stp = SOpAssign(ctr, '+', Lit(step))
        else:
            pre.append(SLet(ctr, coerce(bound, cty_) if bound.ty == 'lit' else Cast(bound, cty_), ann=True))
            c = VarRef(ctr)
            cond = Bin(R.choice(['>', '>', '!=']), c, Lit(0))
            stp = SOpAssign(ctr, '-', Lit(1))
        if R.random() < 0.2:
            cond = Bin('&&', cond, self.gen_bool(sc, 1))
        sc2 = sc.child()
        sc2.loop += 1
        step_first = R.random() < 0.4
        cur = None
        if step_first:
            cv = Var(self.nm('cur'), cty_)
            cur = SLet(cv, VarRef(ctr))
            sc2.vars.append(cv)
            sc2.cont_ok = True
        else:
            sc2.cont_ok = False
        sc2.vars.append(ctr)
        early = None
        if R.random() < 0.35:
            kw = 'break' if (not sc2.cont_ok or R.random() < 0.6) else 'continue'
            early = SIf(self.gen_bool(sc2, 2), [SBreak(kw)], None)     # built before the body: sees only earlier names
        body = self.gen_block(sc2, R.randint(2, 6), depth - 1, new_scope=False)
        if early:
            body.insert(R.randint(0, len(body)), early)
        return pre + [SWhile(cond, body, stp, step_first, cur)]

    def gen_trap(self, sc):
        R = self.R
        self.ntrap += 1
        zero_kinds = []
        dv = self.dyn_vars(sc)
        v = VarRef(R.choice(dv)) if dv else ArgcE()
        k = R.randrange(8)
        if k == 0 and sc.ismain:
            z = Bin('-', ArgcE(), Lit(2))
        elif k == 1:
            z = Bin('-', v, v) if dv else Bin('-', ArgcE(), Lit(2))
        elif k == 2:
            z = Bin('&', v, Lit(0))
        elif k == 3:
            z = Cast(Bin('<<', v, Lit(R.choice([8, 16, 32]))), R.choice(['u8', 'i8']))
        elif k == 4:
            z = Bin('*', v, Lit(0))
        elif k == 5 and sc.arrs:
            z = self.load(sc, R.choice(sc.arrs))
        else:
            z = Bin('>>', v, Lit(R.choice([60, 63]))) if dv else Bin('-', ArgcE(), Lit(2))
        if z is None:
            z = Bin('-', v, v)
        if R.random() < 0.3:
            z = Cast(z, R.choice(TYPES))
        x = self.gen_int(sc, 2)
        if R.random() < 0.25 and dv:
            # MIN / -1 flavours
            m = Bin('<<', Lit(1), Lit(63)) if R.random() < 0.5 else Lit(MINI)
            mv = [x_ for x_ in sc.vars if x_.mut and not x_.ro and x_.ty == 'i64']
            q = Bin('-', ArgcE(), Lit(3)) if sc.ismain and R.random() < 0.5 else Lit(-1)
            if mv:
                var = R.choice(mv)
                return [SAssign(var, m), SPrint(Bin(R.choice(['/', '%']), VarRef(var), q))]
            return [SPrint(Bin(R.choice(['/', '%']), Cast(self.dyn_expr(sc, 1), 'i64') if False else Cast(m, 'i64'), q))] \
                if q.k != 'lit' else []
        op = R.choice(['/', '%'])
        x, z = self.fix_pair(x, z)
        form = R.randrange(4)
        try:
            e = Bin(op, x, z)
        except Invalid:
            return []
        if form == 0:
            return [SPrint(e)]
        if form == 1:
            name = self.nm('dead')
            var = Var(name, e.ty if e.ty != 'lit' else 'i64')
            sc.vars.append(var)
            return [SLet(var, e)]                   # dead trapping division
        if form == 2:
            muts = [x_ for x_ in sc.vars if x_.mut and not x_.ro and x_.ty != 'bool']
            if muts:
                tv = R.choice(muts)
                zz = z
                if binres(tv.ty, zz.ty) is None:
                    zz = Cast(zz, tv.ty)
                return [SOpAssign(tv, op, zz)]
        arrs = [a for a in sc.arrs if not a.view and a.mut]
        if arrs:
            a = R.choice(arrs)
            zz = z if binres(a.ety, z.ty) is not None else Cast(z, a.ety)
            return [SStore(a, Lit(R.randrange(a.n)), zz, op)]
        return [SPrint(e)]

    def gen_stmt(self, sc, depth):
        R = self.R
        r = R.random()
        out = None
        if r < 0.28:
            out = self.gen_assign(sc)
        elif r < 0.42:
            out = self.gen_store(sc)
        elif r < 0.56:
            out = self.gen_print(sc) if not sc.pure else self.gen_assign(sc)
        elif r < 0.64:
            out = self.gen_let(sc)
        elif r < 0.72 and depth > 0:
            out = self.gen_if(sc, depth)
        elif r < 0.80 and depth > 0 and sc.loop < 2:
            out = self.gen_while(sc, depth)
        elif r < 0.84 and sc.fns and not sc.pure:
            fs = [f for f in sc.fns if not f.ret]
            if fs:
                f = R.choice(fs)
                args = []
                ok = True
                for p in f.params:
                    if isinstance(p, Arr):
                        cands = [a for a in sc.arrs if a.ety == p.ety and not a.view and a.n == p.n]
                        if not cands:
                            ok = False
                            break
                        args.append(R.choice(cands).name)
                    else:
                        args.append(coerce(self.gen_int(sc, 2), p.ty))
                if ok:
                    out = SCall(Call(f, args))
        elif r < 0.89 and self.ntrap < 3 and R.random() < self.trap_rate and not sc.pure:
            out = self.gen_trap(sc)
        elif r < 0.93 and sc.fn is not None and sc.fn.ret and depth > 0:
            out = SIf(self.gen_bool(sc, 2), [SReturn(self.gen_for(sc, sc.fn.ret, 2), sc.fn.ret)], None)
        if out is None:
            return self.gen_print(sc) if not sc.pure else self.gen_let(sc)
        return out

    def gen_block(self, sc, n, depth, new_scope=True):
        s2 = sc.child() if new_scope else sc
        out = []
        for _ in range(n):
            st = self.gen_stmt(s2, depth)
            if isinstance(st, list):
                out += st
            else:
                out.append(st)
        return out

    # -- functions
    def gen_fn(self, sc, idx):
        R = self.R
        np_ = R.randint(1, 4)
        params = []
        for i in range(np_):
            params.append(Var(self.nm('par'), self.rtype(), mut=R.random() < 0.25))
        if R.random() < 0.2:
            ety = self.rtype()
            ap = Arr(self.nm('parr'), ety, 16, mut=True)
            params.append(ap)
        ret = R.choice(TYPES + ['i64', 'u64']) if R.random() < 0.8 else None
        fn = Fn(self.nm('fun'), params, ret)
        fs = Scope()
        fs.ismain = False
        fs.pure = ret is not None
        gv = [v for v in sc.vars if v.glob]
        ga = [a for a in sc.arrs if a.glob]
        if fs.pure:
            # value-returning functions may only read globals, so call order inside an expression is unobservable
            gv = [Var(v.name, v.ty, mut=False, const=v.const, val=v.val, glob=True) for v in gv]
            ga = [Arr(a.name, a.ety, a.n, glob=True, mut=False) for a in ga]
            for p_ in params:
                if isinstance(p_, Arr):
                    p_.mut = False
        fs.vars = gv + [p for p in params if isinstance(p, Var)]
        fs.arrs = ga + [p for p in params if isinstance(p, Arr)]
        fs.fns = [f for f in sc.fns if f.ret] if fs.pure else list(sc.fns)
        fs.fn = fn
        fn.body = self.gen_block(fs, R.randint(0, 5), 1, new_scope=False)
        if ret:
            fn.retstmt = SReturn(self.gen_for(fs, ret, self.depth), ret)
        return fn

    # -- whole program
    def build(self):
        R = self.R
        p = self.p
        self.trap_rate = R.choice([0.0, 0.0, 0.1, 0.35])
        sc = Scope()
        # globals
        for i in range(R.randint(0, 4)):
            t = self.rtype()
            if R.random() < 0.5:
                v = Var(self.nm('glob'), t, mut=True, glob=True, val=R.choice([0, 1, -1, 5, 100, 200, 12345]) if signed(t) else R.choice([0, 1, 5, 100, 200]))
                v.val = wrapv(v.val, t)
            else:
                val = self.lit_val(nonneg=(not signed(t)), allow_big=False)
                if not fits(val, t):
                    val = wrapv(val, t)
                if R.random() < 0.3:
                    v = Var(self.nm('GC'), 'lit', const=True, val=val if fits(val, 'i64') else 7, glob=True)
                else:
                    v = Var(self.nm('GC'), t, const=True, val=val, glob=True)
            p.gvars.append(v)
            sc.vars.append(v)
        for i in range(R.randint(0, 2)):
            a = Arr(self.nm('garr'), self.rtype(), 16, glob=True)
            p.garrs.append(a)
            sc.arrs.append(a)
        # views over the input file
        for t in TYPES:
            sz = BITS[t] // 8
            a = Arr('d_' + t, t, 1024 // sz, view=True, mut=False)
            p.views.append(a)
            self.views[t] = a
        # functions
        nf = R.choice([0, 0, 1, 2, 3])
        for i in range(nf):
            fn = self.gen_fn(sc, i)
            p.fns.append(fn)
            sc.fns.append(fn)
        # main variables
        ms = sc.child()
        ms.arrs += p.views
        for i in range(R.randint(0, 3)):
            a = Arr(self.nm('arr'), self.rtype(), 16)
            p.decls.append(SDeclArr(a))
            ms.arrs.append(a)
        nv = R.randint(3, 9)
        for i in range(nv):
            t = self.rtype() if R.random() < 0.85 else 'bool'
            v = Var(self.nm('var'), t, mut=R.random() < 0.85)
            r = R.random()
            if t == 'bool':
                e = Bin('!=', Load(self.views['u8'], Lit(R.randrange(64))), Lit(0)) if R.random() < 0.5 else BoolLit(R.random() < 0.5)
            elif r < 0.7:
                src = R.choice(TYPES)
                arr = self.views[src]
                e = coerce(Load(arr, Lit(R.randrange(arr.n if R.random() < 0.2 else 64))), t)
            elif r < 0.85:
                e = coerce(self.lit(allow_big=(t == 'u64')), t)
            else:
                e = self.gen_for(ms, t, 2)
            if not v.mut and e.const:
                v.const, v.val = True, e.val
            p.decls.append(SLet(v, e))
            ms.vars.append(v)
        # immutable constants
        for i in range(R.randint(0, 4)):
            if R.random() < 0.5:
                e = self.lit()
                v = Var(self.nm('kon'), e.ty, const=True, val=e.val)
                p.decls.append(SLet(v, e))
            else:
                t = self.rtype()
                val = self.lit_val(nonneg=(not signed(t)), allow_big=(t == 'u64'))
                if not fits(val, t):
                    val = wrapv(val, t)
                e = Lit(val)
                v = Var(self.nm('kon'), t, const=True, val=val)
                p.decls.append(SLet(v, e))
            ms.vars.append(v)
        # body
        p.body = self.gen_block(ms, self.nstmts, 2, new_scope=False)
        # final dump of all state
        for v in ms.vars:
            if not v.glob or v.mut:
                if not v.ro:
                    p.body.append(SPrint(VarRef(v)))
        for v in p.gvars:
            if v.mut:
                p.body.append(SPrint(VarRef(v)))
        for a in ms.arrs:
            if a.view:
                continue
            z = Var(self.nm('zz'), 'i64', mut=True, ro=True)
            p.body.append(SLet(z, Lit(0), ann=False))
            p.body.append(SWhile(Bin('<', VarRef(z), Lit(a.n)),
                                 [SPrint(Load(a, VarRef(z)))], SOpAssign(z, '+', Lit(1)), False))
        return p


def make(seed):
    g = Gen(seed)
    return g.build()


# ---------------------------------------------------------------- running and reducing
SKITE = os.environ.get('SKITE', './skite')
CC = os.environ.get('CC', 'cc')
TIMEOUT = 10


def norm_rc(rc):
    return 128 - rc if rc < 0 else rc


def run_prog(prog, wd, tag='p'):
    """compile + run both; returns (verdict, detail). verdict in OK, MISMATCH, SKCOMPILE, CCOMPILE, REJECT, TIMEOUT"""
    ck, cf, data = (os.path.join(wd, tag + e) for e in ('.ck', '.c', '.bin'))
    with open(ck, 'w') as f:
        f.write(prog.skite())
    with open(cf, 'w') as f:
        f.write(prog.c())
    with open(data, 'wb') as f:
        f.write(prog.data)
    sk_exe, c_exe = os.path.join(wd, tag + '.sk'), os.path.join(wd, tag + '.cx')
    r = subprocess.run([SKITE, ck, sk_exe], capture_output=True, text=True, timeout=60)
    if r.returncode != 0:
        msg = r.stderr
        if 'division by zero' in msg or 'signed division overflows' in msg:
            return 'REJECT', msg
        return 'SKCOMPILE', msg or ('rc=%d' % r.returncode)
    r = subprocess.run([CC, '-O0', '-w', '-fwrapv', '-o', c_exe, cf], capture_output=True, text=True, timeout=60)
    if r.returncode != 0:
        return 'CCOMPILE', r.stderr
    try:
        a = subprocess.run([sk_exe, data], capture_output=True, timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        return 'TIMEOUT', 'skite binary timed out'
    try:
        b = subprocess.run([c_exe, data], capture_output=True, timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        return 'CTIMEOUT', 'C binary timed out'
    ra, rb = norm_rc(a.returncode), norm_rc(b.returncode)
    if a.stdout != b.stdout or ra != rb:
        return 'MISMATCH', 'skite rc=%d C rc=%d\n%s' % (ra, rb, first_diff(a.stdout, b.stdout))
    return 'OK', 'rc=%d' % ra


def first_diff(x, y):
    xs, ys = x.decode(errors='replace').split('\n'), y.decode(errors='replace').split('\n')
    for i in range(max(len(xs), len(ys))):
        l, r = (xs[i] if i < len(xs) else '<eof>'), (ys[i] if i < len(ys) else '<eof>')
        if l != r:
            return 'first differing output line %d: skite=%r C=%r' % (i + 1, l, r)
    return 'outputs equal'


def stmt_lists(prog):
    """every reducible statement list in the program"""
    out = []

    def walk(lst):
        out.append(lst)
        for st in lst:
            if isinstance(st, SIf):
                walk(st.then)
                if st.els:
                    walk(st.els)
            elif isinstance(st, SWhile):
                walk(st.body)
    walk(prog.body)
    for fn in prog.fns:
        walk(fn.body)
    out.append(prog.decls)
    return out


def expr_slots(prog):
    """(getter, setter) for every expression position"""
    slots = []

    def add_e(get, set_):
        slots.append((get, set_))
        e = get()
        if isinstance(e, E):
            for i in range(len(e.kids)):
                if isinstance(e.kids[i], E):
                    add_e(lambda e=e, i=i: e.kids[i], lambda v, e=e, i=i: e.kids.__setitem__(i, v))

    def walk(lst):
        for st in lst:
            if isinstance(st, (SLet, SAssign, SOpAssign, SPrint, SReturn, SStore)):
                add_e(lambda st=st: st.e, lambda v, st=st: setattr(st, 'e', v))
                if isinstance(st, SStore):
                    add_e(lambda st=st: st.idx, lambda v, st=st: setattr(st, 'idx', v))
            elif isinstance(st, SCall):
                for i in range(len(st.call.kids)):
                    if isinstance(st.call.kids[i], E):
                        add_e(lambda st=st, i=i: st.call.kids[i], lambda v, st=st, i=i: st.call.kids.__setitem__(i, v))
            elif isinstance(st, SIf):
                add_e(lambda st=st: st.cond, lambda v, st=st: setattr(st, 'cond', v))
                walk(st.then)
                if st.els:
                    walk(st.els)
            elif isinstance(st, SWhile):
                add_e(lambda st=st: st.cond, lambda v, st=st: setattr(st, 'cond', v))
                walk(st.body)
    walk(prog.body)
    for fn in prog.fns:
        walk(fn.body)
        if fn.retstmt:
            walk([fn.retstmt])
    walk(prog.decls)
    return slots


def reduce_prog(prog, wd, log=print, budget=400):
    """greedy minimisation preserving a MISMATCH verdict"""
    runs = [0]

    def bad(p):
        runs[0] += 1
        try:
            v, _ = run_prog(p, wd, 'r')
        except Exception:
            return False
        return v == 'MISMATCH'

    assert bad(prog), 'program does not mismatch'
    progress = True
    while progress and runs[0] < budget:
        progress = False
        # 1. statement removal (chunks, then singles)
        for li in range(len(stmt_lists(prog))):
            lst = stmt_lists(prog)[li]
            n = len(lst)
            chunk = max(1, n // 2)
            while chunk >= 1 and runs[0] < budget:
                i = 0
                while i < len(lst) and runs[0] < budget:
                    saved = lst[i:i + chunk]
                    del lst[i:i + chunk]
                    if bad(prog):
                        progress = True
                    else:
                        lst[i:i] = saved
                        i += chunk
                chunk //= 2
        # 2. unwrap if/while: replace by their bodies
        # 3. expression simplification
        slots = expr_slots(prog)
        for get, set_ in slots:
            if runs[0] >= budget:
                break
            try:
                cur = get()
            except IndexError:
                continue
            if not isinstance(cur, E) or cur.k in ('lit', 'blit') and cur.val in (0, 1):
                continue
            cands = [k for k in cur.kids if isinstance(k, E) and k.ty == cur.ty]
            if cur.ty == 'bool':
                cands += [BoolLit(False), BoolLit(True)]
            elif cur.ty == 'lit':
                cands += [Lit(0), Lit(1)]
            else:
                cands += [Cast(Lit(0), cur.ty), Cast(Lit(1), cur.ty)]
            for c in cands:
                set_(c)
                if bad(prog):
                    progress = True
                    break
                set_(cur)
    return prog


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('mode', choices=['fuzz', 'show', 'reduce'])
    ap.add_argument('a', type=int, help='N (fuzz) or SEED')
    ap.add_argument('b', type=int, nargs='?', default=1, help='SEED (fuzz)')
    ap.add_argument('-j', type=int, default=2)
    ap.add_argument('--keep', default=None)
    ap.add_argument('--skite', default=None)
    ap.add_argument('--stop', action='store_true', help='stop at first failure')
    ap.add_argument('--no-reduce', action='store_true')
    args = ap.parse_args()
    global SKITE
    if args.skite:
        SKITE = args.skite
    if args.mode == 'show':
        p = make(args.a)
        print(p.skite())
        print('/* ---- C ---- */')
        print(p.c())
        return 0
    if args.mode == 'reduce':
        wd = tempfile.mkdtemp(prefix='intdiff')
        try:
            p = reduce_prog(make(args.a), wd)
            print(p.skite())
            print('/* ---- C ---- */')
            print(p.c())
            v, d = run_prog(p, wd, 'r')
            print(v, d)
        finally:
            shutil.rmtree(wd, ignore_errors=True)
        return 0
    # fuzz
    from concurrent.futures import ThreadPoolExecutor
    n, seed0 = args.a, args.b
    wd0 = tempfile.mkdtemp(prefix='intdiff')
    counts = {}
    traps = [0]
    fails = []

    def one(i):
        seed = seed0 * 1000003 + i
        wd = os.path.join(wd0, 'w%d' % (i % max(1, args.j)))
        os.makedirs(wd, exist_ok=True)
        prog = make(seed)
        try:
            v, d = run_prog(prog, wd, 'p%d' % i)
        except subprocess.TimeoutExpired:
            v, d = 'TOOLONG', 'compile timed out'
        return seed, v, d, prog

    try:
        with ThreadPoolExecutor(args.j) as ex:
            for seed, v, d, prog in ex.map(one, range(n)):
                counts[v] = counts.get(v, 0) + 1
                if v == 'OK' and d != 'rc=0':
                    traps[0] += 1
                if v not in ('OK', 'REJECT'):
                    print('FAIL seed=%d %s: %s' % (seed, v, d.strip()[:2000]))
                    fails.append(seed)
                    if args.keep:
                        os.makedirs(args.keep, exist_ok=True)
                        with open(os.path.join(args.keep, 's%d.ck' % seed), 'w') as f:
                            f.write(prog.skite())
                        with open(os.path.join(args.keep, 's%d.c' % seed), 'w') as f:
                            f.write(prog.c())
                        with open(os.path.join(args.keep, 's%d.bin' % seed), 'wb') as f:
                            f.write(prog.data)
                    if args.stop:
                        break
        print('int_diff: %d programs, %s, %d trapped as expected, %d failures' % (n, counts, traps[0], len(fails)))
        if fails and not args.no_reduce and fails[0] is not None:
            wd = os.path.join(wd0, 'red')
            os.makedirs(wd, exist_ok=True)
            seed = fails[0]
            prog = make(seed)
            v, _ = run_prog(prog, wd, 'r')
            if v == 'MISMATCH':
                print('reducing seed %d ...' % seed)
                p = reduce_prog(prog, wd)
                print('---- minimised skite ----')
                print(p.skite())
                print('---- minimised C ----')
                print(p.c())
                v, d = run_prog(p, wd, 'r')
                print(v, d)
        return 1 if fails else 0
    finally:
        shutil.rmtree(wd0, ignore_errors=True)


if __name__ == '__main__':
    sys.exit(main())
