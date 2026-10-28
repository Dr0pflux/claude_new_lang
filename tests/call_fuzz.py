#!/usr/bin/env python3
"""Differential fuzzer for calls, the inliner and the calling convention.

Each case is a random program made of many small functions (0..6 scalar
parameters of mixed i64/i32/u8/f64/bool types, [T] / mut [T] array and struct
array parameters, unit/i64/i32/f64/bool results) with nested calls, bounded
direct and mutual recursion, mutable globals and global arrays written by
callees, mut parameters, early returns inside loops, calls inside && / || and
loop conditions, and output (print/putc) everywhere so that the order of side
effects is observable.  Division by zero and out-of-bounds indices trap.

The reference is the same program translated to C (GNU statement expressions
pin the left-to-right evaluation order; helpers give wrapping arithmetic,
saturating float->int casts and the two traps) and built with gcc -O0.
Output bytes and the exit status (0, 132 bounds trap, 136 division trap) must
match.

usage: tests/call_fuzz.py [CASES] [SEED]      (env SKITE: compiler to test)
"""
import os, random, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKITE = os.environ.get("SKITE", os.path.join(ROOT, "skite"))
CC = os.environ.get("CC", "cc")

M64 = (1 << 64) - 1
IMIN = -(1 << 63)
IMAX = (1 << 63) - 1


def wrap(v):
    v &= M64
    return v - (1 << 64) if v >> 63 else v


INT_TYS = ("i64", "i32", "u8")
CT = {"i64": "I", "i32": "I", "u8": "I", "bool": "I", "f64": "double"}
ET_C = {"i64": "I", "i32": "I", "f64": "double", "S": "S"}

C_PRELUDE = r"""
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <math.h>
typedef int64_t I; typedef uint64_t U;
typedef struct { I x; double y; I z; } S;
static long steps;
static void trap_fpe(void) { fflush(stdout); _exit(136); }
static void trap_ill(void) { fflush(stdout); _exit(132); }
static void step(void) { if (++steps > 400000) { fflush(stdout); _exit(99); } }
static I ADD(I a, I b) { return (I)((U)a + (U)b); }
static I SUB(I a, I b) { return (I)((U)a - (U)b); }
static I MUL(I a, I b) { return (I)((U)a * (U)b); }
static I DIV(I a, I b) { if (b == 0 || (a == INT64_MIN && b == -1)) trap_fpe(); return a / b; }
static I MOD(I a, I b) { if (b == 0 || (a == INT64_MIN && b == -1)) trap_fpe(); return a % b; }
static I AND(I a, I b) { return a & b; }
static I OR(I a, I b) { return a | b; }
static I XOR(I a, I b) { return a ^ b; }
static I SHL(I a, I b) { return (I)((U)a << (b & 63)); }
static I SAR(I a, I b) { return a >> (b & 63); }
static I SHRU(I a, I b) { return (I)((U)a >> (b & 63)); }
static I NEG(I a) { return (I)(0 - (U)a); }
static I I32(I a) { return (I)(int32_t)(uint32_t)(U)a; }
static I U8(I a) { return (I)(uint8_t)(U)a; }
static I D2I(double x) { if (x != x) return 0; if (x >= 9223372036854775808.0) return INT64_MAX; if (x < -9223372036854775808.0) return INT64_MIN; return (I)x; }
static U BITS(double x) { U u; memcpy(&u, &x, 8); return u; }
static I CHK(I i, I n) { if ((U)i >= (U)n) trap_ill(); return i; }
static void PRI(I v) { printf("%lld\n", (long long)v); }
static void PRU(U v) { printf("%llu\n", (unsigned long long)v); }
static void PRB(I v) { fputs(v ? "true\n" : "false\n", stdout); }
static void PUTC(I v) { putchar((int)(65 + (v & 15))); }
"""

BINOPS = {"+": "ADD", "-": "SUB", "*": "MUL", "/": "DIV", "%": "MOD", "&": "AND", "|": "OR",
          "^": "XOR", "<<": "SHL", ">>": "SAR", ">>>": "SHRU"}


UNK = "unk"   # a compile-time constant (the compiler folds it) of a value not tracked here


def known(c):
    return c is not None and c is not UNK


def cjoin(a, b):
    return None if a is None or b is None else UNK


def cmap(a, f):
    return f(a) if known(a) else a


def cfold(op, a, b):
    if known(a) and known(b):
        v = fold_bin(op, a, b)
        return UNK if v is None else v
    return cjoin(a, b)


def fold_bin(op, a, b):
    if op == "+": return wrap(a + b)
    if op == "-": return wrap(a - b)
    if op == "*": return wrap(a * b)
    if op in ("/", "%"):
        if b == 0 or (a == IMIN and b == -1): return None
        q = abs(a) // abs(b)
        if (a < 0) != (b < 0): q = -q
        return wrap(q) if op == "/" else wrap(a - q * b)
    if op == "&": return a & b
    if op == "|": return a | b
    if op == "^": return a ^ b
    if op == "<<": return wrap(a << (b & 63))
    if op == ">>": return a >> (b & 63)
    if op == ">>>": return wrap((a & M64) >> (b & 63))
    return None


class Var:
    def __init__(self, name, ty, mut, const=None, counter=False, glob=False):
        self.name, self.ty, self.mut, self.const, self.counter, self.glob = name, ty, mut, const, counter, glob


class Arr:
    def __init__(self, name, et, writable, clen, cptr, const_len=None):
        self.name, self.et, self.writable, self.clen, self.cptr, self.const_len = name, et, writable, clen, cptr, const_len


class Fn:
    def __init__(self, idx):
        self.idx = idx
        self.name = f"f{idx}"
        self.has_d = False
        self.params = []      # ("s", name, ty, mut) / ("a", name, et, mut)
        self.ret = "i64"
        self.leaf = False     # body is a single `return expr;` (expression inlining)


class Ctx:
    def __init__(self, fn, scope, arrays):
        self.fn = fn          # None for main
        self.scope = scope    # list of Var (innermost last)
        self.arrays = arrays  # list of Arr
        self.base = False     # inside `if d <= 0` (only downward calls)
        self.loop = 0
        self.calls = 0        # calls emitted in the current statement


class Gen:
    def __init__(self, rnd):
        self.r = rnd
        self.nid = 0
        self.tid = 0

    def name(self, p):
        self.nid += 1
        return f"{p}{self.nid}"

    def tmp(self):
        self.tid += 1
        return f"_t{self.tid}"

    # ------------------------------------------------------------ expressions
    # each returns (ck_text, c_text, const_value_or_None)
    def lit_i(self):
        r = self.r
        c = r.random()
        if c < 0.5: v = r.randrange(-20, 40)
        elif c < 0.8: v = r.choice([0, 1, 2, 3, 7, 29, 127, 128, 255, 256, 1000, 65536, -1, -2, -128, -129, 2147483647, -2147483648, 4294967295])
        else: v = r.choice([IMAX, IMIN, -IMAX, 1 << 62, 6364136223846793005, 20511149, 1 << 32])
        return self.lit_v(v)

    def lit_v(self, v):
        if v == IMIN: return ("(-9223372036854775807 - 1)", "INT64_MIN", v)
        if v < 0: return (f"(-{-v})", f"((I){v}LL)", v)
        return (str(v), f"((I){v}LL)", v)

    def lit_f(self):
        s = self.r.choice(["0.0", "1.0", "2.0", "0.5", "1.5", "2.5", "0.1", "100.25", "1e300", "3.0e-7", "1e18", "1e19", "123456.789", "0.333"])
        if self.r.random() < 0.3: return (f"(-{s})", f"(-{s})", UNK)
        return (s, s, UNK)

    def vars_of(self, ctx, tys):
        return [v for v in ctx.scope if v.ty in tys]

    def iexpr(self, ctx, d):
        """an integer expression of type i64 (narrow values widen implicitly)"""
        r = self.r
        if d <= 0 or r.random() < 0.22:
            vs = self.vars_of(ctx, INT_TYS)
            if vs and r.random() < 0.7:
                v = r.choice(vs)
                return (v.name, v.name, v.const)
            return self.lit_i()
        c = r.random()
        if c < 0.40:
            op = r.choice(list(BINOPS))
            a = self.iexpr(ctx, d - 1)
            if op in ("/", "%"):
                b = self.divisor(ctx, d - 1)
                if b[2] is UNK or (known(b[2]) and (b[2] == 0 or (b[2] == -1 and a[2] is not None and (a[2] is UNK or a[2] == IMIN)))):
                    b = self.lit_v(7)
            else:
                b = self.iexpr(ctx, d - 1)
            return (f"({a[0]} {op} {b[0]})", self.cbin(BINOPS[op], "I", a[1], b[1]), cfold(op, a[2], b[2]))
        if c < 0.47:
            a = self.iexpr(ctx, d - 1)
            if r.random() < 0.5:
                return (f"(-{a[0]})", f"NEG({a[1]})", cmap(a[2], lambda x: wrap(-x)))
            return (f"(~{a[0]})", f"(~{a[1]})", cmap(a[2], lambda x: ~x))
        if c < 0.62:
            e = self.call(ctx, d, ("i64", "i32", "u8"))
            if e: return e
            return self.iexpr(ctx, d - 1)
        if c < 0.72 and ctx.arrays:
            return self.load(ctx, d, ("i64", "i32"))
        if c < 0.76:
            a = self.fexpr(ctx, d - 1)
            return (f"(({a[0]}) as i64)", f"D2I({a[1]})", cjoin(a[2], a[2]))
        if c < 0.80:
            a = self.bexpr(ctx, d - 1)
            return (f"(({a[0]}) as i64)", f"((I)({a[1]}))", cjoin(a[2], a[2]))
        if c < 0.86:
            a = self.iexpr(ctx, d - 1)
            t = r.choice(["i32", "u8"])
            fn = "I32" if t == "i32" else "U8"
            cv = cmap(a[2], (lambda x: wrap(((x & 0xFFFFFFFF) ^ 0x80000000) - 0x80000000)) if t == "i32" else (lambda x: x & 255))
            return (f"((({a[0]}) as {t}) as i64)", f"{fn}({a[1]})", cv)
        if c < 0.89 and ctx.arrays:
            a = r.choice(ctx.arrays)
            return (f"len({a.name})", f"({a.clen})", a.const_len)
        a = self.iexpr(ctx, d - 1)
        b = self.iexpr(ctx, d - 1)
        op = r.choice(["+", "-", "^"])
        return (f"({a[0]} {op} {b[0]})", self.cbin(BINOPS[op], "I", a[1], b[1]), cfold(op, a[2], b[2]))

    def divisor(self, ctx, d):
        r = self.r
        c = r.random()
        if c < 0.55:
            return self.lit_v(r.choice([1, 2, 3, 5, 7, 10, 16, 29, 1000, -1, -3, -7, 4294967296]))
        e = self.iexpr(ctx, d)
        if c < 0.85:
            return (f"({e[0]} | 1)", self.cbin("OR", "I", e[1], "((I)1)"), cmap(e[2], lambda x: x | 1))
        if e[2] is not None and (e[2] is UNK or e[2] == 0): return self.lit_v(3)
        return e

    def cbin(self, fn, ty, a, b):
        ta, tb = self.tmp(), self.tmp()
        return f"({{ {ty} {ta} = {a}; {ty} {tb} = {b}; {fn}({ta}, {tb}); }})"

    def fexpr(self, ctx, d):
        r = self.r
        if d <= 0 or r.random() < 0.25:
            vs = self.vars_of(ctx, ("f64",))
            if vs and r.random() < 0.65:
                v = r.choice(vs)
                return (v.name, v.name, v.const)
            return self.lit_f()
        c = r.random()
        if c < 0.45:
            op = r.choice(["+", "-", "*", "/"])
            a = self.fexpr(ctx, d - 1); b = self.fexpr(ctx, d - 1)
            ta, tb = self.tmp(), self.tmp()
            return (f"({a[0]} {op} {b[0]})", f"({{ double {ta} = {a[1]}; double {tb} = {b[1]}; {ta} {op} {tb}; }})", cjoin(a[2], b[2]))
        if c < 0.52:
            a = self.fexpr(ctx, d - 1)
            return (f"(-{a[0]})", f"(-({a[1]}))", cjoin(a[2], a[2]))
        if c < 0.57:
            a = self.fexpr(ctx, d - 1)
            return (f"sqrt({a[0]})", f"sqrt({a[1]})", cjoin(a[2], a[2]))
        if c < 0.67:
            a = self.iexpr(ctx, d - 1)
            return (f"(({a[0]}) as f64)", f"((double)({a[1]}))", cjoin(a[2], a[2]))
        if c < 0.82:
            e = self.call(ctx, d, ("f64",))
            if e: return e
        if c < 0.92 and any(a.et in ("f64", "S") for a in ctx.arrays):
            return self.load(ctx, d, ("f64",))
        return self.fexpr(ctx, d - 1)

    def bexpr(self, ctx, d):
        r = self.r
        c = r.random()
        if d <= 0 or c < 0.12:
            vs = self.vars_of(ctx, ("bool",))
            if vs and r.random() < 0.7:
                v = r.choice(vs)
                return (v.name, v.name, v.const)
            if r.random() < 0.3: return ("true", "1", UNK) if r.random() < 0.5 else ("false", "0", UNK)
        if c < 0.55 or d <= 0:
            op = r.choice(["<", "<=", ">", ">=", "==", "!="])
            if r.random() < 0.25:
                a = self.fexpr(ctx, max(d - 1, 0)); b = self.fexpr(ctx, max(d - 1, 0)); ty = "double"
            else:
                a = self.iexpr(ctx, max(d - 1, 0)); b = self.iexpr(ctx, max(d - 1, 0)); ty = "I"
            ta, tb = self.tmp(), self.tmp()
            return (f"({a[0]} {op} {b[0]})", f"({{ {ty} {ta} = {a[1]}; {ty} {tb} = {b[1]}; (I)({ta} {op} {tb}); }})", cjoin(a[2], b[2]))
        if c < 0.72:
            op = r.choice(["&&", "||"])
            a = self.bexpr(ctx, d - 1); b = self.bexpr(ctx, d - 1)
            return (f"({a[0]} {op} {b[0]})", f"((I)(({a[1]}) {op} ({b[1]})))", cjoin(a[2], a[2]))
        if c < 0.78:
            a = self.bexpr(ctx, d - 1)
            return (f"(!{a[0]})", f"((I)!({a[1]}))", cjoin(a[2], a[2]))
        if c < 0.82:
            a = self.bexpr(ctx, d - 1); b = self.bexpr(ctx, d - 1)
            op = r.choice(["==", "!="])
            ta, tb = self.tmp(), self.tmp()
            return (f"({a[0]} {op} {b[0]})", f"({{ I {ta} = {a[1]}; I {tb} = {b[1]}; (I)({ta} {op} {tb}); }})", cjoin(a[2], b[2]))
        e = self.call(ctx, d, ("bool",))
        if e: return e
        return self.bexpr(ctx, d - 1)

    def expr_of(self, ctx, ty, d):
        """an expression convertible to type ty"""
        r = self.r
        if ty == "i64": return self.iexpr(ctx, d)
        if ty == "f64": return self.fexpr(ctx, d)
        if ty == "bool": return self.bexpr(ctx, d)
        # narrow: a narrow variable of a compatible type, or a cast
        ok = ("u8",) if ty == "u8" else ("u8", "i32")
        vs = self.vars_of(ctx, ok)
        if vs and r.random() < 0.3:
            v = r.choice(vs)
            return (v.name, v.name, v.const)
        if r.random() < 0.15:
            e = self.call(ctx, d, ok)
            if e: return e
        a = self.iexpr(ctx, d)
        fn = "I32" if ty == "i32" else "U8"
        cv = cmap(a[2], (lambda x: wrap(((x & 0xFFFFFFFF) ^ 0x80000000) - 0x80000000)) if ty == "i32" else (lambda x: x & 255))
        return (f"(({a[0]}) as {ty})", f"{fn}({a[1]})", cv)

    def index(self, ctx, a, d):
        r = self.r
        c = r.random()
        e = self.iexpr(ctx, d)
        if c < 0.35 and a.const_len:
            m = 1
            while m * 2 <= a.const_len: m *= 2
            return (f"({e[0]} & {m - 1})", self.cbin("AND", "I", e[1], f"((I){m - 1})"))
        if c < 0.8:
            ln = f"len({a.name})"
            t1, t2 = self.tmp(), self.tmp()
            return (f"((({e[0]} % {ln}) + {ln}) % {ln})", f"({{ I {t1} = {e[1]}; I {t2} = ({a.clen}); MOD(ADD(MOD({t1}, {t2}), {t2}), {t2}); }})")
        if c < 0.985:
            k = r.randrange(a.const_len) if a.const_len else 0
            return (str(k), f"((I){k})")
        return (e[0], e[1])

    def load(self, ctx, d, want):
        r = self.r
        cands = []
        for a in ctx.arrays:
            if a.et in want: cands.append((a, None))
            if a.et == "S":
                if "i64" in want: cands.append((a, "x"))
                if "i32" in want: cands.append((a, "z"))
                if "f64" in want: cands.append((a, "y"))
        if not cands:
            return self.iexpr(ctx, 0) if "f64" not in want else self.lit_f()
        a, fld = r.choice(cands)
        ix = self.index(ctx, a, d - 1)
        t = self.tmp()
        ety = "double" if (a.et == "f64" or fld == "y") else "I"
        acc = f".{fld}" if fld else ""
        return (f"{a.name}[{ix[0]}]{acc}", f"({{ I {t} = CHK({ix[1]}, {a.clen}); ({a.cptr})[{t}]{acc}; }})", None)

    # ------------------------------------------------------------ calls
    def callees(self, ctx, rets):
        out = []
        f = ctx.fn
        for g in self.fns:
            if g.ret not in rets: continue
            if f is None: out.append(g); continue
            if g.idx < f.idx:
                out.append(g)
            elif f.has_d and g.has_d and not ctx.base:
                out.append(g)
        return out

    def call(self, ctx, d, rets):
        if ctx.calls >= 3 or d <= 0: return None
        cs = self.callees(ctx, rets)
        if not cs: return None
        g = self.r.choice(cs)
        ctx.calls += 1
        return self.call_to(ctx, g, d)

    def call_to(self, ctx, g, d):
        r = self.r
        f = ctx.fn
        cks, cs, pre = [], [], []
        for p in g.params:
            if p[0] == "a":
                _, pn, et, mut = p
                cands = [a for a in ctx.arrays if a.et == et and (a.writable or not mut)]
                a = r.choice(cands)
                cks.append(a.name); cs.append(f"{a.cptr}, {a.clen}")
                continue
            _, pn, ty, mut = p
            if pn == "d":
                if f is None: e = self.lit_v(r.randrange(0, 5))
                elif not f.has_d: e = self.lit_v(0)
                elif g.idx >= f.idx or r.random() < 0.5: e = ("(d - 1)", "SUB(d, 1)", None)
                else: e = ("d", "d", None)
            else:
                e = self.expr_of(ctx, ty, min(d - 1, 2))
            t = self.tmp()
            pre.append(f"{CT[ty]} {t} = {e[1]};")
            cks.append(e[0]); cs.append(t)
        return (f"{g.name}({', '.join(cks)})", f"({{ {' '.join(pre)} {g.name}({', '.join(cs)}); }})", None)

    # ------------------------------------------------------------ statements
    def stmt(self, ctx, depth, out_ck, out_c, ind):
        r = self.r
        ctx.calls = 0
        def emit(ck, c):
            out_ck.append(ind + ck); out_c.append(ind + c)
        c = r.random()
        muts = [v for v in ctx.scope if v.mut and not v.counter]
        warr = [a for a in ctx.arrays if a.writable]
        f = ctx.fn
        if c < 0.10 and depth < 3:
            b = self.bexpr(ctx, 3)
            emit(f"if {b[0]} {{", f"if ({b[1]}) {{")
            self.block(ctx, depth + 1, out_ck, out_c, ind + "  ")
            if r.random() < 0.4:
                emit("} else {", "} else {")
                self.block(ctx, depth + 1, out_ck, out_c, ind + "  ")
            emit("}", "}")
            return
        if c < 0.17 and depth < 3:
            cv = self.name("c"); lim = r.randrange(1, 7)
            emit(f"let mut {cv}: i64 = 0;", f"I {cv} = 0;")
            cond_ck, cond_c = f"({cv} < {lim})", f"({cv} < {lim})"
            if r.random() < 0.45:
                b = self.bexpr(ctx, 2)
                cond_ck += f" && {b[0]}"; cond_c += f" && ({b[1]})"
            emit(f"while {cond_ck} {{", f"while ({cond_c}) {{ step();")
            emit(f"  {cv} += 1;", f"  {cv} += 1;")
            ctx.scope.append(Var(cv, "i64", True, counter=True))
            ctx.loop += 1
            self.block(ctx, depth + 1, out_ck, out_c, ind + "  ")
            ctx.loop -= 1
            emit("}", "}")
            return
        if c < 0.21 and ctx.loop:
            b = self.bexpr(ctx, 2)
            k = r.choice(["break", "continue"])
            emit(f"if {b[0]} {{ {k}; }}", f"if ({b[1]}) {{ {k}; }}")
            return
        if c < 0.27 and f is not None:
            b = self.bexpr(ctx, 2)
            if f.ret == "unit":
                emit(f"if {b[0]} {{ return; }}", f"if ({b[1]}) {{ return; }}")
            else:
                e = self.expr_of(ctx, f.ret, 2)
                emit(f"if {b[0]} {{ return {e[0]}; }}", f"if ({b[1]}) {{ return {e[1]}; }}")
            return
        if c < 0.37:
            # a call statement: f(..); / let v = f(..); / print(f(..));
            cs = self.callees(ctx, ("unit", "i64", "i32", "u8", "f64", "bool"))
            if cs:
                g = r.choice(cs)
                e = self.call_to(ctx, g, 3)
                if g.ret == "unit" or r.random() < 0.3:
                    emit(f"{e[0]};", f"{e[1]};")
                elif g.ret == "f64":
                    emit(f"print(bits({e[0]}));", f"PRU(BITS({e[1]}));")
                elif g.ret == "bool":
                    emit(f"print({e[0]});", f"PRB({e[1]});")
                else:
                    if r.random() < 0.5:
                        emit(f"print({e[0]});", f"PRI({e[1]});")
                    else:
                        v = self.name("v")
                        emit(f"let {v}: {g.ret} = {e[0]};", f"I {v} = {e[1]};")
                        ctx.scope.append(Var(v, g.ret, False))
                return
        if c < 0.47 and muts:
            v = r.choice(muts)
            self.assign(ctx, v, emit)
            return
        if c < 0.55 and warr:
            self.store(ctx, r.choice(warr), emit)
            return
        if c < 0.62:
            k = r.random()
            if k < 0.6:
                e = self.iexpr(ctx, 3)
                emit(f"print({e[0]});", f"PRI({e[1]});")
            elif k < 0.75:
                e = self.fexpr(ctx, 3)
                emit(f"print(bits({e[0]}));", f"PRU(BITS({e[1]}));")
            elif k < 0.85:
                e = self.bexpr(ctx, 2)
                emit(f"print({e[0]});", f"PRB({e[1]});")
            else:
                e = self.iexpr(ctx, 2)
                emit(f"putc(65 + (({e[0]}) & 15));", f"PUTC({e[1]});")
            return
        # let
        ty = r.choice(["i64", "i64", "i64", "i32", "u8", "f64", "f64", "bool"])
        mut = r.random() < 0.55
        v = self.name("v")
        if r.random() < 0.3:
            # statement-inlinable forms: let v = f(..) / let v = w op f(..)
            cs = self.callees(ctx, (ty,))
            if cs:
                g = r.choice(cs)
                e = self.call_to(ctx, g, 3)
                if ty in ("i64",) and r.random() < 0.5:
                    vs = self.vars_of(ctx, INT_TYS)
                    if vs:
                        w = r.choice(vs)
                        op = r.choice(["+", "-", "*", "^", "/", "%"])
                        emit(f"let {'mut ' if mut else ''}{v}: i64 = {w.name} {op} {e[0]};", f"I {v} = {self.cbin(BINOPS[op], 'I', w.name, e[1])};")
                        ctx.scope.append(Var(v, ty, mut))
                        return
                emit(f"let {'mut ' if mut else ''}{v}: {ty} = {e[0]};", f"{CT[ty]} {v} = {e[1]};")
                ctx.scope.append(Var(v, ty, mut))
                return
        if ty == "i64" and not mut and r.random() < 0.15:
            # untyped constant / alias
            imm = [w for w in ctx.scope if not w.mut and w.ty == "i64"]
            if imm and r.random() < 0.5:
                w = r.choice(imm)
                emit(f"let {v} = {w.name};", f"I {v} = {w.name};")
                ctx.scope.append(Var(v, "i64", False, const=w.const))
                return
            k = r.randrange(-5, 30)
            lv = self.lit_v(k)
            emit(f"let {v} = {lv[0]};", f"I {v} = {lv[1]};")
            ctx.scope.append(Var(v, "i64", False, const=k))
            return
        e = self.expr_of(ctx, ty, 3)
        emit(f"let {'mut ' if mut else ''}{v}: {ty} = {e[0]};", f"{CT[ty]} {v} = {e[1]};")
        ctx.scope.append(Var(v, ty, mut, const=None if mut else e[2]))

    def assign(self, ctx, v, emit):
        r = self.r
        c = r.random()
        if v.glob:
            # global scalar: like an array element, `g op= e` evaluates e first
            if v.ty == "i64" and c < 0.35:
                op = r.choice(list(BINOPS))
                e = self.divisor(ctx, 2) if op in ("/", "%") else self.iexpr(ctx, 3)
                t = self.tmp()
                emit(f"{v.name} {op}= {e[0]};", f"{{ I {t} = {e[1]}; {v.name} = {BINOPS[op]}({v.name}, {t}); }}")
                return
            if v.ty == "f64" and c < 0.35:
                op = r.choice(["+", "-", "*", "/"])
                e = self.fexpr(ctx, 3)
                t = self.tmp()
                emit(f"{v.name} {op}= {e[0]};", f"{{ double {t} = {e[1]}; {v.name} = {v.name} {op} {t}; }}")
                return
            e = self.expr_of(ctx, v.ty, 3)
            emit(f"{v.name} = {e[0]};", f"{v.name} = {e[1]};")
            return
        if v.ty in INT_TYS and c < 0.4:
            op = r.choice(list(BINOPS))
            e = self.divisor(ctx, 2) if op in ("/", "%") else self.iexpr(ctx, 3)
            wr = {"i64": "", "i32": "I32", "u8": "U8"}[v.ty]
            emit(f"{v.name} {op}= {e[0]};", f"{v.name} = {wr}({self.cbin(BINOPS[op], 'I', v.name, e[1])});")
            return
        if v.ty == "f64" and c < 0.3:
            op = r.choice(["+", "-", "*", "/"])
            e = self.fexpr(ctx, 3)
            ta, tb = self.tmp(), self.tmp()
            emit(f"{v.name} {op}= {e[0]};", f"{v.name} = ({{ double {ta} = {v.name}; double {tb} = {e[1]}; {ta} {op} {tb}; }});")
            return
        if c < 0.7:
            cs = self.callees(ctx, (v.ty,))
            if cs:
                g = r.choice(cs)
                e = self.call_to(ctx, g, 3)
                if v.ty == "i64" and r.random() < 0.4:
                    vs = self.vars_of(ctx, INT_TYS)
                    w = r.choice(vs)
                    op = r.choice(["+", "-", "*", "&", "/"])
                    emit(f"{v.name} = {w.name} {op} {e[0]};", f"{v.name} = {self.cbin(BINOPS[op], 'I', w.name, e[1])};")
                    return
                emit(f"{v.name} = {e[0]};", f"{v.name} = {e[1]};")
                return
        e = self.expr_of(ctx, v.ty, 3)
        emit(f"{v.name} = {e[0]};", f"{v.name} = {e[1]};")

    def store(self, ctx, a, emit):
        r = self.r
        fld = None
        et = a.et
        if et == "S":
            fld = r.choice(["x", "y", "z"])
            et = {"x": "i64", "y": "f64", "z": "i32"}[fld]
        acc = f".{fld}" if fld else ""
        compound = r.random() < 0.35
        if r.random() < 0.3 and not compound:
            cs = self.callees(ctx, (et,) if et != "i32" else ("i32", "u8"))
            if cs:
                e = self.call_to(ctx, r.choice(cs), 3)
            else:
                e = self.expr_of(ctx, et, 3)
        elif compound and et != "f64":
            op = r.choice(list(BINOPS))
            e = self.divisor(ctx, 2) if op in ("/", "%") else self.iexpr(ctx, 3)
        elif compound:
            op = r.choice(["+", "-", "*", "/"])
            e = self.fexpr(ctx, 3)
        else:
            e = self.expr_of(ctx, et, 3)
        ix = self.index(ctx, a, 2)
        tv, ti = self.tmp(), self.tmp()
        cty = "double" if et == "f64" else "I"
        lhs = f"({a.cptr})[{ti}]{acc}"
        wr = "I32" if et == "i32" else ""
        if compound:
            if et == "f64": val = f"{lhs} {op} {tv}"
            else: val = f"{wr}({BINOPS[op]}({lhs}, {tv}))"
            emit(f"{a.name}[{ix[0]}]{acc} {op}= {e[0]};", f"{{ {cty} {tv} = {e[1]}; I {ti} = CHK({ix[1]}, {a.clen}); {lhs} = {val}; }}")
        else:
            emit(f"{a.name}[{ix[0]}]{acc} = {e[0]};", f"{{ {cty} {tv} = {e[1]}; I {ti} = CHK({ix[1]}, {a.clen}); {lhs} = {tv}; }}")

    def block(self, ctx, depth, out_ck, out_c, ind, n=None):
        mark = len(ctx.scope)
        if n is None: n = self.r.randrange(1, 5 if depth else 7)
        for _ in range(n):
            self.stmt(ctx, depth, out_ck, out_c, ind)
        del ctx.scope[mark:]

    # ------------------------------------------------------------ program
    def program(self):
        r = self.r
        ck, c = [], [C_PRELUDE]
        use_struct = r.random() < 0.5
        if use_struct: ck.append("struct S { x: i64, y: f64, z: i32 }")
        globs = []
        for i in range(r.randrange(1, 4)):
            v = r.randrange(-3, 10)
            lv = self.lit_v(v)
            ck.append(f"let mut g{i}: i64 = {lv[0]};"); c.append(f"static I g{i} = {lv[1]};")
            globs.append(Var(f"g{i}", "i64", True, glob=True))
        if r.random() < 0.6:
            ck.append("let mut gf: f64 = 1.5;"); c.append("static double gf = 1.5;")
            globs.append(Var("gf", "f64", True, glob=True))
        if r.random() < 0.4:
            ck.append("let gk = 3;"); c.append("static const I gk = 3;")
            globs.append(Var("gk", "i64", False, const=3, glob=True))
        garr = []
        for nm, et, n in (("ga", "i64", 8), ("gb", "i32", 5), ("gd", "f64", 4), ("gs", "S", 3)):
            if et == "S" and not use_struct: continue
            ck.append(f"let {nm} = alloc<{et}>({n});"); c.append(f"static {ET_C[et]} {nm}[{n}];")
            garr.append(Arr(nm, et, True, str(n), nm, n))
        nf = r.randrange(3, 10)
        self.fns = []
        for i in range(nf):
            g = Fn(i)
            g.leaf = r.random() < 0.25
            g.has_d = not g.leaf and r.random() < 0.7
            ps = []
            ns = r.choice([0, 0, 1, 1, 1, 2, 2, 3, 4, 6])
            for k in range(ns):
                ty = r.choice(["i64", "i64", "i64", "f64", "f64", "i32", "u8", "bool"])
                ps.append(("s", self.name("p"), ty, (not g.leaf) and r.random() < 0.3))
            if not g.leaf or r.random() < 0.5:
                for k in range(r.choice([0, 0, 0, 1, 1, 2])):
                    ets = ["i64", "i64", "i32", "f64"] + (["S"] if use_struct else [])
                    ps.append(("a", self.name("q"), r.choice(ets), r.random() < 0.6))
            r.shuffle(ps)
            if g.has_d: ps.insert(0, ("s", "d", "i64", False))
            g.params = ps
            g.ret = r.choice(["i64", "i64", "i64", "f64", "bool", "i32", "unit", "unit"]) if not g.leaf else r.choice(["i64", "i64", "f64", "bool"])
            self.fns.append(g)
        for g in self.fns:
            c.append(self.sig(g)[1][:-2] + ";")
        for g in self.fns:
            self.function(g, globs, garr, ck, c)
        self.main(globs, garr, ck, c)
        return "\n".join(ck) + "\n", "\n".join(c) + "\n"

    def sig(self, g):
        ps_ck, ps_c = [], []
        for p in g.params:
            if p[0] == "a":
                _, pn, et, mut = p
                ps_ck.append(f"{pn}: {'mut ' if mut else ''}[{et}]"); ps_c.append(f"{ET_C[et]} *{pn}_p, I {pn}_n")
            else:
                _, pn, ty, mut = p
                ps_ck.append(f"{'mut ' if mut else ''}{pn}: {ty}"); ps_c.append(f"{CT[ty]} {pn}")
        rt = "" if g.ret == "unit" else f" -> {g.ret}"
        crt = "void" if g.ret == "unit" else CT[g.ret]
        return f"fn {g.name}({', '.join(ps_ck)}){rt} {{", f"static {crt} {g.name}({', '.join(ps_c)}) {{"

    def function(self, g, globs, garr, ck, c):
        r = self.r
        scope = list(globs)
        arrays = list(garr)
        for p in g.params:
            if p[0] == "a":
                _, pn, et, mut = p
                arrays.append(Arr(pn, et, mut, f"{pn}_n", f"{pn}_p"))
            else:
                _, pn, ty, mut = p
                scope.append(Var(pn, ty, mut))
        ctx = Ctx(g, scope, arrays)
        hck, hc = self.sig(g)
        ck.append(hck); c.append(hc); c.append("  step();")
        if g.leaf:
            ctx.base = True
            e = self.expr_of(ctx, g.ret, 3)
            ck.append(f"  return {e[0]};"); c.append(f"  return {e[1]};")
            ck.append("}"); c.append("}")
            return
        if g.has_d:
            ctx.base = True
            if g.ret == "unit":
                ck.append("  if d <= 0 { return; }"); c.append("  if (d <= 0) { return; }")
            else:
                ctx.calls = 0
                e = self.expr_of(ctx, g.ret, 2)
                ck.append(f"  if d <= 0 {{ return {e[0]}; }}"); c.append(f"  if (d <= 0) {{ return {e[1]}; }}")
            ctx.base = False
        else:
            ctx.base = True   # no depth guard: only downward calls
        self.block(ctx, 0, ck, c, "  ", r.randrange(1, 6))
        ctx.calls = 0
        if g.ret == "unit":
            if r.random() < 0.5: ck.append("  return;"); c.append("  return;")
        else:
            e = self.expr_of(ctx, g.ret, 3)
            ck.append(f"  return {e[0]};"); c.append(f"  return {e[1]};")
        ck.append("}"); c.append("}")

    def main(self, globs, garr, ck, c):
        r = self.r
        scope = list(globs)
        arrays = list(garr)
        ck.append("fn main() -> i64 {")
        cm = ["static I ck_main(I argc_v) {"]
        ck.append("  let one = argc();"); cm.append("  I one = argc_v;")
        scope.append(Var("one", "i64", False))
        ck.append("  let ma = alloc<i64>(6);"); c.append("static I ma[6];")
        arrays.append(Arr("ma", "i64", True, "6", "ma", 6))
        ck.append("  let mb = alloc<f64>(argc() + 2);"); c.append("static double mb[3];")
        arrays.append(Arr("mb", "f64", True, "(argc_v + 2)", "mb"))
        ck.append("  let mut acc: i64 = one * 7;"); cm.append("  I acc = MUL(one, 7);")
        scope.append(Var("acc", "i64", True))
        ctx = Ctx(None, scope, arrays)
        self.block(ctx, 0, ck, cm, "  ", r.randrange(4, 12))
        # call every function at least once, at the top level
        for g in self.fns:
            ctx.calls = 0
            e = self.call_to(ctx, g, 3)
            if g.ret == "unit": ck.append(f"  {e[0]};"); cm.append(f"  {e[1]};")
            elif g.ret == "f64": ck.append(f"  print(bits({e[0]}));"); cm.append(f"  PRU(BITS({e[1]}));")
            elif g.ret == "bool": ck.append(f"  print({e[0]});"); cm.append(f"  PRB({e[1]});")
            else: ck.append(f"  acc = acc * 31 + {e[0]};"); cm.append(f"  acc = ADD(MUL(acc, 31), {e[1]});")
        for v in globs:
            if v.ty == "i64": ck.append(f"  print({v.name});"); cm.append(f"  PRI({v.name});")
            else: ck.append(f"  print(bits({v.name}));"); cm.append(f"  PRU(BITS({v.name}));")
        for a in arrays:
            fl = [".x", ".y", ".z"] if a.et == "S" else [""]
            n = a.const_len or 3
            for k in range(n):
                for fd in fl:
                    if a.et == "f64" or fd == ".y": ck.append(f"  print(bits({a.name}[{k}]{fd}));"); cm.append(f"  PRU(BITS({a.cptr}[{k}]{fd}));")
                    else: ck.append(f"  print({a.name}[{k}]{fd});"); cm.append(f"  PRI({a.cptr}[{k}]{fd});")
        ck.append("  return acc;"); cm.append("  return acc;")
        ck.append("}"); cm.append("}")
        c.extend(cm)
        c.append("int main(int argc, char **argv) { (void)argv; static char buf[1 << 16]; setvbuf(stdout, buf, _IOFBF, sizeof buf); I r = ck_main(argc); PRI(r); fflush(stdout); return 0; }")


def run(cmd, **kw):
    return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kw)


def main():
    cases = int(sys.argv[1]) if len(sys.argv) > 1 else 100
    seed = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    keep = os.environ.get("KEEP")
    tmp = tempfile.mkdtemp(prefix="callfuzz")
    stats = {"ok": 0, "trap": 0, "skip": 0, "inl": 0, "calls": 0}
    for t in range(cases):
        rnd = random.Random(seed * 1000003 + t)
        for attempt in range(20):
            g = Gen(rnd)
            src, csrc = g.program()
            ckp = os.path.join(tmp, f"k{t}.ck"); cp = os.path.join(tmp, f"k{t}.c")
            with open(ckp, "w") as fh: fh.write(src)
            with open(cp, "w") as fh: fh.write(csrc)
            cr = run([CC, "-std=gnu11", "-O0", "-ffp-contract=off", "-w", cp, "-o", cp + ".bin", "-lm"])
            if cr.returncode != 0:
                print(f"C COMPILE FAIL case {t}: {cp}\n{cr.stderr.decode()[:3000]}"); sys.exit(1)
            try:
                ref = run([cp + ".bin"], timeout=10)
            except subprocess.TimeoutExpired:
                stats["skip"] += 1; continue
            if ref.returncode == 99:
                stats["skip"] += 1; continue
            break
        else:
            print(f"case {t}: could not generate a terminating program"); sys.exit(1)
        kr = run([SKITE, ckp, ckp + ".bin"])
        if kr.returncode != 0:
            print(f"SKITE COMPILE FAIL case {t}: {ckp}\n{kr.stderr.decode()[:3000]}"); sys.exit(1)
        log = kr.stdout.decode()
        if " calls inlined" in log:
            try: stats["inl"] += int(log.split(" calls inlined")[0].rsplit(" ", 1)[1])
            except ValueError: pass
        try:
            got = run([ckp + ".bin"], timeout=10)
        except subprocess.TimeoutExpired:
            print(f"TIMEOUT case {t}: {ckp}"); sys.exit(1)
        grc = got.returncode if got.returncode >= 0 else 128 - got.returncode
        if grc != ref.returncode or got.stdout != ref.stdout:
            print(f"MISMATCH case {t} (seed {seed}): {ckp}  rc skite={grc} ref={ref.returncode}")
            a = got.stdout.decode(errors="replace").splitlines(); b = ref.stdout.decode(errors="replace").splitlines()
            for i in range(max(len(a), len(b))):
                x = a[i] if i < len(a) else "<eof>"; y = b[i] if i < len(b) else "<eof>"
                if x != y: print(f"  first difference at line {i + 1}: skite [{x}] ref [{y}]"); break
            sys.exit(1)
        stats["ok"] += 1
        if ref.returncode != 0: stats["trap"] += 1
        if not keep:
            for p in (ckp, cp, cp + ".bin", ckp + ".bin"):
                try: os.remove(p)
                except OSError: pass
    print(f"PASS {stats['ok']} call programs ({stats['trap']} trap, {stats['skip']} regenerated, {stats['inl']} calls inlined)")


if __name__ == "__main__":
    main()
