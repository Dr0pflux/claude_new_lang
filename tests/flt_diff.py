#!/usr/bin/env python3
"""Differential fuzzer for skite's floating-point semantics against C.

Random programs over f64 / f32 (arithmetic, comparisons, unary -, sqrt, casts
float<->int including out-of-range and NaN, f32<->f64, bit reinterpretation,
literals that stress correct rounding, arrays and loops that the vectorizer
picks up, calls, globals) are emitted twice from one IR:
  * as a skite program, compiled normally and with --scalar;
  * as a C program (gcc -O0 -ffp-contract=off -fno-fast-math -fwrapv); skite's
    saturating float->int casts are emulated by explicit helper functions and
    every constant is opaque to gcc (noinline wrappers), so C executes pure
    hardware IEEE arithmetic.
Both print raw IEEE bit patterns, so the comparison is bit exact.  Runtime values
come from an input file (special values, random patterns) so that skite can only
fold what the program text makes constant.

usage: tests/flt_diff.py [CASES] [SEED] [--keep DIR] [--fmt] [--nonan] [--no-reduce]
       tests/flt_diff.py --replay FILE.json   (re-run a saved failing case)
"""
import json, os, random, struct, subprocess, sys, tempfile, shutil
from decimal import Decimal, getcontext
from fractions import Fraction

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKITE = os.environ.get("SKITE", os.path.join(ROOT, "skite"))
CC = os.environ.get("CC", "gcc")
getcontext().prec = 900

FLT = ("f64", "f32")
CTY = {"f64": "double", "f32": "float", "i8": "int8_t", "i16": "int16_t", "i32": "int32_t", "i64": "int64_t",
       "u8": "uint8_t", "u16": "uint16_t", "u32": "uint32_t", "u64": "uint64_t", "bool": "int"}
SIGNED_NARROW = ("i8", "i16", "i32")
UNSIGNED_NARROW = ("u8", "u16", "u32")
NARROW = SIGNED_NARROW + UNSIGNED_NARROW
IRANGE = {"i8": (-128, 127), "i16": (-32768, 32767), "i32": (-2**31, 2**31 - 1), "i64": (-2**63, 2**63 - 1),
          "u8": (0, 255), "u16": (0, 65535), "u32": (0, 2**32 - 1), "u64": (0, 2**64 - 1)}


# ---------------------------------------------------------------- IR
class N:
    """expression node. k: kind, ty: skite type name, a: children, v: payload, lit: only literals below"""
    __slots__ = ("k", "ty", "a", "v", "lit")

    def __init__(s, k, ty, a=(), v=None, lit=False):
        s.k, s.ty, s.a, s.v, s.lit = k, ty, list(a), v, lit

    def to_j(s):
        return [s.k, s.ty, [x.to_j() for x in s.a], s.v, s.lit]

    @staticmethod
    def from_j(j):
        return N(j[0], j[1], [N.from_j(x) for x in j[2]], tuple(j[3]) if isinstance(j[3], list) else j[3], j[4])


def expr_size(e):
    return 1 + sum(expr_size(x) for x in e.a)


def is_float(t):
    return t in FLT


def is_plain_lit(e):
    """a literal / untyped constant, possibly negated (the only literal shapes allowed as f32)"""
    if e.k in ("lit", "ilitf", "const"):
        return True
    return e.k == "neg" and e.a[0].k in ("lit", "ilitf", "const")


# ---------------------------------------------------------------- interesting values
def f64_bits(x):
    return struct.unpack("<Q", struct.pack("<d", x))[0]


def bits_f64(b):
    return struct.unpack("<d", struct.pack("<Q", b))[0]


def f32_bits(x):
    return struct.unpack("<I", struct.pack("<f", x))[0]


def bits_f32(b):
    return struct.unpack("<f", struct.pack("<I", b))[0]


INF64 = 0x7FF0000000000000
POOL64 = [0x0, 0x8000000000000000, f64_bits(1.0), f64_bits(-1.0), f64_bits(0.5), f64_bits(2.0), f64_bits(3.0),
          f64_bits(0.1), f64_bits(-0.1), f64_bits(1 / 3), 1, 0x8000000000000001, 0x000FFFFFFFFFFFFF, 0x0010000000000000,
          0x7FEFFFFFFFFFFFFF, 0xFFEFFFFFFFFFFFFF, INF64, INF64 | 1 << 63, 0x7FF8000000000000, 0xFFF8000000000000,
          0x7FF8000000000123, 0x7FF0000000000001, 0xFFF4000000000000,
          f64_bits(2.0 ** 53), f64_bits(2.0 ** 53 + 2), f64_bits(2.0 ** 63), f64_bits(-2.0 ** 63), f64_bits(2.0 ** 64),
          f64_bits(2.0 ** 63 - 1024), f64_bits(4294967296.0), f64_bits(4294967295.5), f64_bits(255.5), f64_bits(256.0),
          f64_bits(-128.5), f64_bits(127.9), f64_bits(65535.99), f64_bits(1e15), f64_bits(1e16), f64_bits(1e19),
          f64_bits(1.8446744073709552e19), f64_bits(123456789.123456789), f64_bits(-2147483649.0), f64_bits(2147483647.5),
          f64_bits(-0.5), f64_bits(0.99999999999999989), f64_bits(1.0000000000000002), f64_bits(6.5), f64_bits(-3.75)]
POOL32 = [0x0, 0x80000000, f32_bits(1.0), f32_bits(-1.0), f32_bits(0.5), f32_bits(2.0), f32_bits(3.0), f32_bits(0.1),
          f32_bits(-0.1), f32_bits(1 / 3), 1, 0x80000001, 0x007FFFFF, 0x00800000, 0x7F7FFFFF, 0xFF7FFFFF,
          0x7F800000, 0xFF800000, 0x7FC00000, 0xFFC00000, 0x7FC00123, 0x7F800001, 0xFFA00000,
          f32_bits(16777216.0), f32_bits(16777218.0), f32_bits(2.0 ** 31), f32_bits(-2.0 ** 31), f32_bits(2.0 ** 32),
          f32_bits(2.0 ** 63), f32_bits(2.0 ** 64), f32_bits(2.0 ** 24 - 1), f32_bits(255.5), f32_bits(256.0),
          f32_bits(-128.5), f32_bits(127.9), f32_bits(65535.5), f32_bits(3e38), f32_bits(9.99e18), f32_bits(1.8e19),
          f32_bits(-0.5), f32_bits(0.99999994), f32_bits(1.0000001), f32_bits(6.5), f32_bits(-3.75), f32_bits(4294967040.0)]
POOLI = [0, 1, -1, -2**63, 2**63 - 1, 2**53, 2**53 + 1, -(2**53) - 1, 2**24 + 1, 2**24, 2**31, -2**31, 2**32, 2**32 - 1,
         2**62, 2**63 - 1024, 2**63 - 513, 2**63 - 512, 255, 256, 65535, 127, -128, 12345678901234567, 3, 7, 100, -100,
         0x7FFFFFFFFFFFFC00, 0x7FFFFFFFFFFFFE00, -2**63 + 1, 2**64 - 1 - 2**63]  # last one = 2**63 - 1 (kept for count)


def build_input(rnd):
    """bytes of the input file: 40 f64, 40 f32, 24 i64"""
    d = list(POOL64)
    while len(d) < 40:
        d.append(rnd.getrandbits(64) if rnd.random() < 0.3 else f64_bits(rnd.uniform(-1000, 1000) * 10 ** rnd.randint(-20, 20)))
    rnd.shuffle(d)
    s = list(POOL32)
    while len(s) < 40:
        s.append(rnd.getrandbits(32) if rnd.random() < 0.3 else f32_bits(rnd.uniform(-1000, 1000) * 10 ** rnd.randint(-10, 10)))
    rnd.shuffle(s)
    ii = list(POOLI)
    rnd.shuffle(ii)
    ii = [x & (2**64 - 1) for x in ii[:16]] + [rnd.getrandbits(64) for _ in range(8)]
    rnd.shuffle(ii)
    return struct.pack("<40Q", *d[:40]) + struct.pack("<40I", *s[:40]) + struct.pack("<24Q", *ii[:24])


# ---------------------------------------------------------------- literal text
def dec_text(fr, digits=70):
    """decimal text of a Fraction, rounded to `digits` significant digits"""
    from decimal import localcontext
    with localcontext() as ctx:
        ctx.prec = digits
        d = Decimal(fr.numerator) / Decimal(fr.denominator)
        return format(d, "f") if abs(d) > Decimal("1e-5") and abs(d) < Decimal("1e30") else format(d, "e")


def fix_dot(t):
    if "." not in t and "e" not in t and "E" not in t:
        t += ".0"
    return t


def midpoint_lit(rnd, ty):
    """decimal text just around the midpoint of two adjacent floats of type ty (stresses correct rounding).
    skite limits a literal to 127 characters, so only moderate exponents are used."""
    for _ in range(20):
        if ty == "f32":
            b = (rnd.randint(127 - 40, 127 + 60) << 23) | rnd.getrandbits(23)
            lo = Fraction(bits_f32(b))
            hi = Fraction(bits_f32(b + 1))
            slack = Fraction(1, 2**40)
        else:
            b = (rnd.randint(1023 - 30, 1023 + 60) << 52) | rnd.getrandbits(52)
            lo = Fraction(bits_f64(b))
            hi = Fraction(bits_f64(b + 1))
            slack = Fraction(1, 2**70)
        mid = (lo + hi) / 2
        c = rnd.random()
        if c < 0.3:
            v = mid
        else:
            eps = (hi - lo) * slack * rnd.choice([1, 3, 1000])
            v = mid + eps if c < 0.65 else mid - eps
        t = fix_dot(dec_text(v))
        if len(t) <= 120:
            return t
    return "0.1"


def bits_bits64(b):
    return bits_f64(b)


def rand_digits(rnd, n):
    return str(rnd.randint(1, 9)) + "".join(rnd.choice("0123456789") for _ in range(n - 1))


def lit_text(rnd, ty):
    c = rnd.random()
    if c < 0.30:
        return rnd.choice(["0.0", "1.0", "0.5", "2.0", "3.0", "10.0", "0.1", "0.25", "100.0", "1.5", "0.2", "7.0e-3",
                           "0.3333333333333333", "255.0", "256.5", "65536.0", "4294967296.0", "2.5", "0.75", "1e10"])
    if c < 0.42:
        if ty == "f32":
            return rnd.choice(["3.4028235e38", "3.4028236e38", "3.4028235677973366e38", "1e39", "1.17549435e-38", "1.4e-45",
                               "7e-46", "7.1e-46", "1.0e-45", "16777217.0", "16777216.0", "1.00000005960464477539062500001",
                               "0.99999997019767761230468750000", "2147483648.0", "9223372036854775808.0", "1.8446744073709552e19"])
        return rnd.choice(["1e308", "1.7976931348623157e308", "1.7976931348623159e308", "1e309", "2.2250738585072014e-308",
                           "5e-324", "1e-320", "4.9e-324", "2.4703282292062328e-324", "2.4703282292062327e-324", "1e-400",
                           "9007199254740993.0", "9007199254740992.0", "18446744073709551616.0", "9223372036854775808.0",
                           "4.35e-5", "123456789.123456789", "0.30000000000000004", "1.7976931348623158e308"])
    if c < 0.62:
        e = rnd.randint(-45, 38) if ty == "f32" else rnd.choice([rnd.randint(-30, 30), rnd.randint(-320, 308)])
        n = rnd.choice([1, 2, 3, 6, 9, 10, 17, 18, 19, 20, 25, 40])
        return fix_dot(rand_digits(rnd, n) + "e" + str(e))
    if c < 0.75:
        if ty == "f32":
            x = bits_f32(rnd.getrandbits(32) & 0x7F7FFFFF)
            return fix_dot("%.9g" % x)
        x = bits_f64(rnd.getrandbits(64) & 0x7FEFFFFFFFFFFFFF)
        return fix_dot(repr(x))
    return midpoint_lit(rnd, ty)


def c_float_lit(text, ty):
    """C spelling of a skite float literal for type ty, wrapped to be opaque to gcc's constant folder"""
    if ty == "f32":
        return "K32(%sf)" % text
    return "K64(%s)" % text


# ---------------------------------------------------------------- emitters (expressions)
def sk(e):
    k = e.k
    if k == "lit":
        return e.v
    if k == "ilitf" or k == "ilit":
        return str(e.v)
    if k == "const" or k == "var":
        return e.v[0] if isinstance(e.v, tuple) else e.v
    if k == "bin":
        return "(%s %s %s)" % (sk(e.a[0]), e.v, sk(e.a[1]))
    if k == "neg":
        return "(-%s)" % sk(e.a[0])
    if k == "cast":
        return "(%s as %s)" % (sk(e.a[0]), e.ty)
    if k == "sqrt":
        return "sqrt(%s)" % sk(e.a[0])
    if k == "cmp":
        return "(%s %s %s)" % (sk(e.a[0]), e.v, sk(e.a[1]))
    if k == "and":
        return "(%s && %s)" % (sk(e.a[0]), sk(e.a[1]))
    if k == "or":
        return "(%s || %s)" % (sk(e.a[0]), sk(e.a[1]))
    if k == "not":
        return "(!%s)" % sk(e.a[0])
    if k == "ld":
        return "%s[%s]" % (e.v, sk(e.a[0]))
    if k == "call":
        return "%s(%s)" % (e.v[0], ", ".join(sk(x) for x in e.a))
    if k == "frombits":
        return "%s_from_bits(%s)" % (e.ty, sk(e.a[0]))
    if k == "bits":
        return "bits(%s)" % sk(e.a[0])
    if k == "shift":
        return "(%s %s %d)" % (sk(e.a[0]), e.v[0], e.v[1])
    if k == "idiv":
        return "(%s %s %d)" % (sk(e.a[0]), e.v[0], e.v[1])
    raise ValueError(k)


def cx(e, ctx=None):
    """C spelling; ctx: the float type an untyped literal adapts to"""
    k = e.k
    t = e.ty
    if k == "lit":
        return c_float_lit(e.v, ctx or t)
    if k == "ilitf":
        return c_float_lit("%d.0" % e.v, ctx or t)
    if k == "ilit":
        if t == "u64":
            return "(uint64_t)%dULL" % e.v
        return "(int64_t)%dLL" % e.v if e.v != -2**63 else "(-9223372036854775807LL-1)"
    if k == "const":
        return c_float_lit(e.v[1], ctx or t)
    if k == "var":
        return e.v
    if k == "bin":
        a, b = e.a
        if is_float(t):
            return "(%s %s %s)" % (cx(a, t), e.v, cx(b, t))
        ct = CTY[t]
        return "((%s)((%s)%s %s (%s)%s))" % (ct, ct, cx(a), e.v, ct, cx(b))
    if k == "neg":
        return "(-%s)" % cx(e.a[0], ctx or t)
    if k == "cast":
        a = e.a[0]
        if is_float(t):
            if is_float(a.ty):
                # literal operand of a cast defaults to f64
                return "((%s)%s)" % (CTY[t], cx(a, "f64" if is_plain_lit(a) else None))
            return "((%s)%s)" % (CTY[t], cx(a))
        if is_float(a.ty):
            return "d2%s((double)%s)" % (t, cx(a, "f64" if is_plain_lit(a) else None))
        return "((%s)%s)" % (CTY[t], cx(a))
    if k == "sqrt":
        a = e.a[0]
        if t == "f32":
            return "__builtin_sqrtf(%s)" % cx(a, "f32")
        return "__builtin_sqrt(%s)" % cx(a, "f64")
    if k == "cmp":
        a, b = e.a
        ft = a.ty if is_float(a.ty) else None
        if ft is None:
            ft = b.ty if is_float(b.ty) else None
        if ft:
            return "(%s %s %s)" % (cx(a, ft), e.v, cx(b, ft))
        return "(%s %s %s)" % (cx_cmpint(a), e.v, cx_cmpint(b))
    if k == "and":
        return "(%s && %s)" % (cx(e.a[0]), cx(e.a[1]))
    if k == "or":
        return "(%s || %s)" % (cx(e.a[0]), cx(e.a[1]))
    if k == "not":
        return "(!%s)" % cx(e.a[0])
    if k == "ld":
        return "%s[%s]" % (e.v, cx_idx(e.a[0]))
    if k == "call":
        return "%s(%s)" % (e.v[0], ", ".join(cx(x, p) if is_float(p) else cx(x) for x, p in zip(e.a, e.v[1])))
    if k == "frombits":
        return "%s(%s)" % ("bits_to_d" if t == "f64" else "bits_to_f", cx(e.a[0]))
    if k == "bits":
        return "%s(%s)" % ("d_to_bits" if e.a[0].ty == "f64" else "f_to_bits", cx(e.a[0], e.a[0].ty))
    if k == "shift":
        op, c = e.v
        ct = CTY[t]
        if op == "<<":
            return "((%s)((uint64_t)%s << %d))" % (ct, cx(e.a[0]), c)
        if op == ">>":
            if t == "u64":
                return "((uint64_t)%s >> %d)" % (cx(e.a[0]), c)
            return "((int64_t)%s >> %d)" % (cx(e.a[0]), c)
        return "((%s)((uint64_t)%s >> %d))" % (ct, cx(e.a[0]), c)
    if k == "idiv":
        op, c = e.v
        ct = CTY[t]
        return "((%s)((%s)%s %s %d))" % (ct, ct, cx(e.a[0]), op, c)
    raise ValueError(k)


def cx_cmpint(a):
    if a.ty == "u64":
        return "(uint64_t)%s" % cx(a)
    return "(int64_t)%s" % cx(a)


def cx_idx(i):
    return "(uint64_t)%s" % cx(i) if i.ty != "u64" else cx(i)


# ---------------------------------------------------------------- statements
# ('let', name, ty, mut, expr, annot) ('set', name, expr) ('opset', name, op, expr) ('if', cond, then, else)
# ('while', cname, limit, extra, body, step_first) ('store', arr, idx, expr) ('pf', expr) ('pi', expr) ('pb', expr)
# ('pp', expr) ('break',) ('continue',) ('vwhile', iname, limit_text, body)


def stmt_to_j(s):
    k = s[0]
    out = []
    for x in s:
        if isinstance(x, N):
            out.append({"N": x.to_j()})
        elif isinstance(x, list) and x and isinstance(x[0], tuple):
            out.append({"B": [stmt_to_j(y) for y in x]})
        elif isinstance(x, list) and not x:
            out.append({"B": []})
        else:
            out.append(x)
    return out


def stmt_from_j(j):
    out = []
    for x in j:
        if isinstance(x, dict) and "N" in x:
            out.append(N.from_j(x["N"]))
        elif isinstance(x, dict) and "B" in x:
            out.append([stmt_from_j(y) for y in x["B"]])
        else:
            out.append(x)
    return tuple(out)


def emit_stmts(lang, stmts, ind, out):
    for s in stmts:
        emit_stmt(lang, s, ind, out)


def sk_init(e, ty):
    return sk(e)


def emit_stmt(lang, s, ind, out):
    k = s[0]
    sp = "  " * ind
    if k == "let":
        _, name, ty, mut, e, annot = s
        if lang == "sk":
            a = ": %s" % ty if annot else ""
            out.append("%slet %s%s%s = %s;" % (sp, "mut " if mut else "", name, a, sk(e)))
        else:
            out.append("%s%s%s %s = %s;" % (sp, "" if mut else "", CTY[ty], name, cx(e, ty if is_float(ty) else None)))
    elif k == "set":
        _, name, e, ty = s
        if lang == "sk":
            out.append("%s%s = %s;" % (sp, name, sk(e)))
        else:
            out.append("%s%s = %s;" % (sp, name, cx(e, ty if is_float(ty) else None)))
    elif k == "opset":
        _, name, op, e, ty = s
        if lang == "sk":
            out.append("%s%s %s= %s;" % (sp, name, op, sk(e)))
        else:
            out.append("%s%s %s= %s;" % (sp, name, op, cx(e, ty)))
    elif k == "if":
        _, c, t, f = s
        if lang == "sk":
            out.append("%sif %s {" % (sp, sk(c)))
        else:
            out.append("%sif (%s) {" % (sp, cx(c)))
        emit_stmts(lang, t, ind + 1, out)
        if f:
            out.append("%s} else {" % sp)
            emit_stmts(lang, f, ind + 1, out)
        out.append("%s}" % sp)
    elif k == "while":
        _, cn, lim, extra, body, first = s
        if lang == "sk":
            out.append("%slet mut %s = 0;" % (sp, cn))
            ex = " && %s" % sk(extra) if extra is not None else ""
            out.append("%swhile %s < %d%s {" % (sp, cn, lim, ex))
        else:
            out.append("%sint64_t %s = 0;" % (sp, cn))
            ex = " && %s" % cx(extra) if extra is not None else ""
            out.append("%swhile (%s < %d%s) {" % (sp, cn, lim, ex))
        if first:
            out.append("%s  %s += 1;" % (sp, cn))
        emit_stmts(lang, body, ind + 1, out)
        if not first:
            out.append("%s  %s += 1;" % (sp, cn))
        out.append("%s}" % sp)
    elif k == "vwhile":
        _, iv, lim, body = s
        if lang == "sk":
            out.append("%swhile %s < %s {" % (sp, iv, lim))
        else:
            out.append("%swhile (%s < %s) {" % (sp, iv, lim))
        emit_stmts(lang, body, ind + 1, out)
        out.append("%s  %s += 1;" % (sp, iv))
        out.append("%s}" % sp)
    elif k == "vwhile2":
        _, cn, lim, extra, body = s
        if lang == "sk":
            ex = " && %s" % sk(extra) if extra is not None else ""
            out.append("%swhile %s < %d%s {" % (sp, cn, lim, ex))
        else:
            ex = " && %s" % cx(extra) if extra is not None else ""
            out.append("%swhile (%s < %d%s) {" % (sp, cn, lim, ex))
        emit_stmts(lang, body, ind + 1, out)
        out.append("%s  %s += 1;" % (sp, cn))
        out.append("%s}" % sp)
    elif k == "store":
        _, arr, idx, e, ty = s
        if lang == "sk":
            out.append("%s%s[%s] = %s;" % (sp, arr, sk(idx), sk(e)))
        else:
            out.append("%s%s[%s] = %s;" % (sp, arr, cx_idx(idx), cx(e, ty if is_float(ty) else None)))
    elif k == "pf":
        e = s[1]
        if lang == "sk":
            out.append("%sputc(%d); print(bits(%s));" % (sp, 100 if e.ty == "f64" else 115, sk(e)))
        else:
            out.append("%s%s(%s);" % (sp, "pf64" if e.ty == "f64" else "pf32", cx(e)))
    elif k == "pi":
        e = s[1]
        if lang == "sk":
            out.append("%sprint(%s);" % (sp, sk(e)))
        else:
            out.append("%spint(%s, %d);" % (sp, cx(e), 1 if e.ty == "u64" else 0))
    elif k == "pb":
        e = s[1]
        if lang == "sk":
            out.append("%sprint(%s);" % (sp, sk(e)))
        else:
            out.append("%spbool(%s);" % (sp, cx(e)))
    elif k == "pp":
        e = s[1]
        v = s[2]
        if lang == "sk":
            out.append("%sif !(%s >= 18000000000000000000.0 || %s <= -18000000000000000000.0) { putc(112); print(%s); }" % (sp, v, v, v))
        else:
            out.append("%sif (!(%s >= 18000000000000000000.0 || %s <= -18000000000000000000.0)) ppr((double)%s);" % (sp, v, v, v))
    elif k == "break":
        out.append("%sbreak;" % sp)
    elif k == "continue":
        out.append("%scontinue;" % sp)
    elif k == "raw":
        out.append(sp + (s[1] if lang == "sk" else s[2]))
    else:
        raise ValueError(k)


class Func:
    def __init__(s, name, params, ret, body, rexpr):
        s.name, s.params, s.ret, s.body, s.rexpr = name, params, ret, body, rexpr

    def emit(self, lang, out):
        if lang == "sk":
            ps = ", ".join("%s: %s" % (n, t) for n, t in self.params)
            out.append("fn %s(%s) -> %s {" % (self.name, ps, self.ret))
            emit_stmts(lang, self.body, 1, out)
            out.append("  return %s;" % sk(self.rexpr))
        else:
            ps = ", ".join("%s %s" % (CTY[t], n) for n, t in self.params)
            out.append("static %s %s(%s) {" % (CTY[self.ret], self.name, ps))
            emit_stmts(lang, self.body, 1, out)
            out.append("  return %s;" % cx(self.rexpr, self.ret if is_float(self.ret) else None))
        out.append("}")


C_PRELUDE = r"""#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
__attribute__((noinline)) static double K64(double x) { return x; }
__attribute__((noinline)) static float K32(float x) { return x; }
static uint64_t d_to_bits(double x) { uint64_t b; memcpy(&b, &x, 8); return b; }
static uint32_t f_to_bits(float x) { uint32_t b; memcpy(&b, &x, 4); return b; }
static double bits_to_d(uint64_t b) { double x; memcpy(&x, &b, 8); return x; }
static float bits_to_f(uint32_t b) { float x; memcpy(&x, &b, 4); return x; }
static void pf64(double x) { printf("d%llu\n", (unsigned long long)d_to_bits(x)); }
static void pf32(float x) { printf("s%u\n", (unsigned)f_to_bits(x)); }
static void pint(int64_t x, int u) { if (u) printf("%llu\n", (unsigned long long)x); else printf("%lld\n", (long long)x); }
static void pbool(int b) { puts(b ? "true" : "false"); }
static void ppr(double v) { if (v != v) puts("p" "NaN"); else printf("p%.6f\n", v); }
static int64_t d2i64(double x) { if (x != x) return 0; if (x >= 9223372036854775808.0) return INT64_MAX; if (x <= -9223372036854775808.0) return INT64_MIN; return (int64_t)x; }
static uint64_t d2u64(double x) { if (!(x > 0)) return 0; if (x >= 18446744073709551616.0) return UINT64_MAX; return (uint64_t)x; }
#define SAT(NAME, T, LO, HI) static T NAME(double x) { if (x != x) return 0; if (x <= (double)(LO)) return (T)(LO); if (x >= (double)(HI)) return (T)(HI); return (T)(int64_t)x; }
SAT(d2i8, int8_t, -128, 127)
SAT(d2i16, int16_t, -32768, 32767)
SAT(d2i32, int32_t, -2147483648LL, 2147483647LL)
SAT(d2u8, uint8_t, 0, 255)
SAT(d2u16, uint16_t, 0, 65535)
SAT(d2u32, uint32_t, 0, 4294967295LL)
"""


class Prog:
    def __init__(s):
        s.funcs = []
        s.globals = []     # (name, ty, init_text)
        s.main = []
        s.input = b""
        s.fmt = False

    def skite(self):
        out = []
        for n, t, it in self.globals:
            out.append("let mut %s: %s = %s;" % (n, t, it))
        for f in self.funcs:
            f.emit("sk", out)
        out.append("fn main() {")
        out += PROLOGUE_SK
        emit_stmts("sk", self.main, 1, out)
        out.append("}")
        return "\n".join(out) + "\n"

    def c(self):
        out = [C_PRELUDE]
        for n, t, it in self.globals:
            out.append("static %s %s = %s%s;" % (CTY[t], n, it, "f" if t == "f32" else ""))
        for f in self.funcs:
            f.emit("c", out)
        out.append("int main(int argc, char **argv) {")
        out += PROLOGUE_C
        emit_stmts("c", self.main, 1, out)
        out.append("  return 0;\n}")
        return "\n".join(out) + "\n"

    def to_j(self):
        return {"funcs": [[f.name, f.params, f.ret, [stmt_to_j(x) for x in f.body], f.rexpr.to_j()] for f in self.funcs],
                "globals": self.globals, "main": [stmt_to_j(x) for x in self.main], "input": self.input.hex()}

    @staticmethod
    def from_j(j):
        p = Prog()
        p.funcs = [Func(f[0], [tuple(x) for x in f[1]], f[2], [stmt_from_j(x) for x in f[3]], N.from_j(f[4])) for f in j["funcs"]]
        p.globals = [tuple(x) for x in j["globals"]]
        p.main = [stmt_from_j(x) for x in j["main"]]
        p.input = bytes.fromhex(j["input"])
        return p


PROLOGUE_SK = """  let inp = file(1);
  let dv = view<f64>(inp);
  let sv = view<f32>(inp);
  let iv = view<i64>(inp);
  let fa = alloc<f64>(64); let fb = alloc<f64>(64); let fo = alloc<f64>(64);
  let ga = alloc<f32>(64); let ia = alloc<i64>(64);
  let mut k0 = 0;
  while k0 < 64 {
    fa[k0] = dv[(k0 * 7) % 40]; fb[k0] = dv[(k0 * 11 + 5) % 40]; fo[k0] = dv[(k0 * 3 + 1) % 40];
    ga[k0] = sv[80 + (k0 * 3) % 40]; ia[k0] = iv[60 + (k0 * 5) % 24];
    k0 += 1;
  }""".split("\n")

PROLOGUE_C = """  FILE *fp = fopen(argv[1], "rb"); static unsigned char buf[4096]; size_t nb = fread(buf, 1, sizeof buf, fp); (void)nb; fclose(fp);
  double *dv = (double *)buf; float *sv = (float *)buf; int64_t *iv = (int64_t *)buf;
  static double fa[64], fb[64], fo[64]; static float ga[64]; static int64_t ia[64];
  int64_t k0 = 0;
  while (k0 < 64) {
    fa[k0] = dv[(k0 * 7) % 40]; fb[k0] = dv[(k0 * 11 + 5) % 40]; fo[k0] = dv[(k0 * 3 + 1) % 40];
    ga[k0] = sv[80 + (k0 * 3) % 40]; ia[k0] = iv[60 + (k0 * 5) % 24];
    k0 += 1;
  }""".split("\n")


# ---------------------------------------------------------------- generator
class Gen:
    def __init__(self, rnd, opts=None):
        self.r = rnd
        self.opts = opts or {}
        self.cnt = 0
        self.scopes = [[]]            # list of lists of (name, ty, mutable)
        self.glob = []                # (name, ty)
        self.funcs = []               # Func objects (callable ones)
        self.fsig = {}                # name -> (params types, ret)
        self.in_func = None
        self.loop_depth = 0
        self.nonan = bool(self.opts.get("nonan"))
        self.vec = None               # vector mode state
        self.consts = {"f64": [], "f32": []}
        self.cont_ok = [False]

    def name(self, p):
        self.cnt += 1
        return "%s%d" % (p, self.cnt)

    # ----- variables
    def push(self):
        self.scopes.append([])

    def pop(self):
        self.scopes.pop()

    def declare(self, name, ty, mut):
        self.scopes[-1].append((name, ty, mut))

    def vars_of(self, ty, mut=False):
        res = [(n, t, m) for sc in self.scopes for (n, t, m) in sc if t == ty and (m or not mut)]
        if self.vec is None:
            res += [(n, t, True) for (n, t) in self.glob if t == ty]
        return res

    def pick_var(self, ty, mut=False):
        vs = self.vars_of(ty, mut)
        if not vs:
            return None
        return self.r.choice(vs)

    # ----- leaves
    def lit(self, ty):
        r = self.r
        t = lit_text(r, ty)
        return N("lit", ty, v=t, lit=True)

    def ilitf(self, ty):
        lim = 2**24 if ty == "f32" else 2**53
        v = self.r.choice([0, 1, 2, 3, 10, 100, 255, 256, 65535, 65536, 1000000, 2**20, 2**24, 2**24 - 1, self.r.randint(0, 100000)])
        if ty == "f64":
            v = self.r.choice([v, 2**31, 2**32, 2**53, 2**52 + 1])
        return N("ilitf", ty, v=min(v, lim), lit=True)

    def ilit(self, ty="i64"):
        r = self.r
        if ty == "u64":
            v = r.choice([0, 1, 7, 255, 2**32, 2**63, 2**64 - 1, 2**53 + 1, r.getrandbits(64), 2**63 + 1025])
        else:
            v = r.choice([0, 1, 2, 3, 7, 10, 255, 256, 65535, 2**31, 2**32, 2**53 + 1, 2**62, -1, -7, -256, -2**31 - 1,
                          r.randint(-1000, 1000), r.randint(-2**40, 2**40)])
            v = max(v, -2**62)
        return N("ilit", ty, v=v, lit=True)

    def index(self):
        r = self.r
        if r.random() < 0.4 or self.vec is not None:
            return N("ilit", "i64", v=r.randrange(64), lit=True)
        i = self.gen_i(2)
        return N("bin", "i64", [i, N("ilit", "i64", v=63, lit=True)], "&")

    def idx_in_range(self, name):
        """an index expression provably inside 0..63 for the vectorizer: variable counters are masked"""
        return self.index()

    # ----- float expressions
    def gen_f(self, ty, d, allow_lit_only=True):
        for _ in range(8):
            e = self._gen_f(ty, d)
            if ty == "f32" and e.lit and not is_plain_lit(e):
                continue
            if e.lit and not allow_lit_only:
                continue
            return e
        v = self.pick_var(ty) if self.vec is None else None
        if v:
            return N("var", ty, v=v[0])
        if not allow_lit_only:
            if ty == "f64":
                return N("frombits", ty, [self.ilit("u64")])
            return N("frombits", ty, [N("cast", "u32", [self.ilit("i64")])])
        return self.lit(ty)

    def _gen_f(self, ty, d):
        r = self.r
        if self.vec is not None:
            return self._gen_f_vec(ty, d)
        leaf = d <= 0 or r.random() < 0.2 + 0.1 * (3 - min(d, 3)) / 3
        if leaf:
            c = r.random()
            if c < 0.45:
                v = self.pick_var(ty)
                if v:
                    return N("var", ty, v=v[0])
            if c < 0.62:
                return self.lit(ty)
            if c < 0.68:
                return self.ilitf(ty)
            if c < 0.80 and not self.in_func:
                arr = "fa" if ty == "f64" else "ga"
                if ty == "f64" and r.random() < 0.4:
                    arr = r.choice(["fb", "fo"])
                return N("ld", ty, [self.index()], arr)
            if c < 0.86 and self.consts.get(ty):
                nm, tx = r.choice(self.consts[ty])
                return N("const", ty, v=(nm, tx), lit=True)
            if c < 0.93:
                if ty == "f64":
                    return N("frombits", ty, [self.gen_u(1)])
                return N("frombits", ty, [N("cast", "u32", [self.gen_i(1)])])
            v = self.pick_var(ty)
            if v:
                return N("var", ty, v=v[0])
            return self.lit(ty)
        c = r.random()
        if c < 0.55:
            op = r.choice(["+", "-", "*", "/", "+", "-", "*"])
            return N("bin", ty, [self.gen_f(ty, d - 1), self.gen_f(ty, d - 1)], op)
        if c < 0.63:
            e = self.gen_f(ty, d - 1, False)
            return N("neg", ty, [e], lit=e.lit)
        if c < 0.70:
            return N("sqrt", ty, [self.gen_f(ty, d - 1, False)])
        if c < 0.82:
            o = "f32" if ty == "f64" else "f64"
            return N("cast", ty, [self.gen_f(o, d - 1)])
        if c < 0.92:
            src = r.choice(["i", "u"])
            if src == "u":
                return N("cast", ty, [self.gen_u(d - 1)])
            return N("cast", ty, [self.gen_i(d - 1)])
        if self.funcs and not self.in_func:
            cands = [f for f in self.funcs if f.ret == ty]
            if cands:
                f = r.choice(cands)
                return self.call(f)
        return N("bin", ty, [self.gen_f(ty, d - 1), self.gen_f(ty, d - 1)], r.choice(["+", "*", "-"]))

    def call(self, f):
        args = []
        ptys = [t for _, t in f.params]
        for n, t in f.params:
            if n == "d":
                args.append(N("ilit", "i64", v=self.r.randint(0, 4), lit=True))
            elif is_float(t):
                args.append(self.gen_f(t, 1))
            elif t == "u64":
                args.append(self.gen_u(1))
            else:
                args.append(N("cast", t, [self.gen_i(1)]))
        return N("call", f.ret, args, (f.name, ptys))

    def _gen_f_vec(self, ty, d):
        """f64 expressions that the vectorizer accepts"""
        r = self.r
        st = self.vec
        if d <= 0 or r.random() < 0.25:
            c = r.random()
            if c < 0.45 and st["vars"]:
                return N("var", "f64", v=r.choice(st["vars"]))
            if c < 0.6:
                return self.lit("f64")
            if c < 0.75:
                return N("ld", "f64", [N("var", "i64", v=st["iv"])], r.choice(["fa", "fb"]))
            if c < 0.82:
                off = r.randint(1, 7)
                return N("ld", "f64", [N("bin", "i64", [N("var", "i64", v=st["iv"]), N("ilit", "i64", v=off, lit=True)], "+")], r.choice(["fa", "fb"]))
            if c < 0.9 and st["uni"]:
                return N("var", "f64", v=r.choice(st["uni"]))
            if c < 0.95:
                return N("cast", "f64", [N("var", "i64", v=r.choice([st["iv"]] + st["ints"]))])
            return self.ilitf("f64")
        c = r.random()
        if c < 0.75:
            return N("bin", "f64", [self.gen_f("f64", d - 1), self.gen_f("f64", d - 1)], r.choice(["+", "-", "*", "/"]))
        if c < 0.85:
            return N("neg", "f64", [self.gen_f("f64", d - 1, False)])
        if c < 0.95:
            return N("sqrt", "f64", [self.gen_f("f64", d - 1, False)])
        return N("cast", "f64", [N("bin", "i64", [N("var", "i64", v=st["iv"]), N("ilit", "i64", v=r.randint(1, 100), lit=True)], r.choice(["*", "+", "-"]))])

    # ----- integer expressions
    def gen_i(self, d):
        """an expression of an integer type other than u64 (promotes to i64 in arithmetic)"""
        r = self.r
        if self.vec is not None:
            return N("var", "i64", v=self.vec["iv"])
        if d <= 0 or r.random() < 0.3:
            c = r.random()
            if c < 0.4:
                tys = ["i64"] + list(NARROW)
                r.shuffle(tys)
                for t in tys:
                    v = self.pick_var(t)
                    if v:
                        return N("var", t, v=v[0])
            if c < 0.6:
                return self.ilit("i64")
            if c < 0.75 and not self.in_func:
                return N("ld", "i64", [self.index()], "ia")
            f = self.gen_f(r.choice(FLT), 1, False)
            return N("cast", r.choice(("i64",) + NARROW + ("i64", "i32")), [f])
        c = r.random()
        if c < 0.35:
            op = r.choice(["+", "-", "*", "&", "|", "^"])
            return N("bin", "i64", [self.gen_i(d - 1), self.gen_i(d - 1)], op)
        if c < 0.45:
            op = r.choice(["<<", ">>", ">>>"])
            return N("shift", "i64", [self.gen_i(d - 1)], (op, r.randint(0, 63)))
        if c < 0.52:
            op = r.choice(["/", "%"])
            return N("idiv", "i64", [self.gen_i(d - 1)], (op, r.choice([1, 2, 3, 7, 10, 1000, 65536])))
        if c < 0.75:
            f = self.gen_f(r.choice(FLT), d - 1, False)
            return N("cast", r.choice(("i64", "i32", "i16", "i8", "u8", "u16", "u32", "i64")), [f])
        if c < 0.85:
            return N("cast", r.choice(NARROW), [self.gen_i(d - 1)])
        if c < 0.92:
            return N("cast", r.choice(NARROW + ("i64",)), [self.gen_u(d - 1)])
        e = self.gen_f(r.choice(FLT), d - 1, False)
        return N("bits", "u32" if e.ty == "f32" else "u64", [e]) if e.ty == "f32" else N("cast", "i64", [N("bits", "u64", [e])])

    def gen_u(self, d):
        r = self.r
        if self.vec is not None:
            return N("cast", "u64", [N("var", "i64", v=self.vec["iv"])])
        if d <= 0 or r.random() < 0.3:
            c = r.random()
            if c < 0.4:
                v = self.pick_var("u64")
                if v:
                    return N("var", "u64", v=v[0])
            if c < 0.55:
                return self.ilit("u64")
            if c < 0.7 and not self.in_func:
                return N("cast", "u64", [N("ld", "i64", [self.index()], "ia")])
            return N("cast", "u64", [self.gen_f(r.choice(FLT), 1, False)])
        c = r.random()
        if c < 0.35:
            return N("bin", "u64", [self.gen_u(d - 1), self.gen_u(d - 1)], r.choice(["+", "-", "*", "&", "|", "^"]))
        if c < 0.45:
            return N("shift", "u64", [self.gen_u(d - 1)], (r.choice(["<<", ">>", ">>>"]), r.randint(0, 63)))
        if c < 0.52:
            return N("idiv", "u64", [self.gen_u(d - 1)], (r.choice(["/", "%"]), r.choice([1, 2, 3, 7, 10, 1000, 65536])))
        if c < 0.75:
            return N("cast", "u64", [self.gen_f(r.choice(FLT), d - 1, False)])
        if c < 0.85:
            return N("cast", "u64", [self.gen_i(d - 1)])
        e = self.gen_f("f64", d - 1, False)
        return N("bits", "u64", [e])

    # ----- booleans
    def gen_b(self, d):
        r = self.r
        if self.vec is not None:
            return self.gen_b_vec(d)
        c = r.random()
        if d > 0 and c < 0.15:
            return N("and", "bool", [self.gen_b(d - 1), self.gen_b(d - 1)])
        if d > 0 and c < 0.28:
            return N("or", "bool", [self.gen_b(d - 1), self.gen_b(d - 1)])
        if d > 0 and c < 0.34:
            return N("not", "bool", [self.gen_b(d - 1)])
        op = r.choice(["<", "<=", ">", ">=", "==", "!="])
        if c < 0.85:
            ty = r.choice(FLT)
            a = self.gen_f(ty, 2, False)
            b = self.gen_f(ty, 2)
            if r.random() < 0.3:
                a, b = b, a
                if a.lit and not is_plain_lit(a) or a.lit and b.lit:
                    a, b = b, a
            if a.lit and b.lit:
                a = self.gen_f(ty, 1, False)
            return N("cmp", "bool", [a, b], op)
        if c < 0.93:
            return N("cmp", "bool", [self.gen_i(1), self.gen_i(1)], op)
        return N("cmp", "bool", [self.gen_u(1), self.gen_u(1)], op)

    def gen_b_vec(self, d):
        r = self.r
        c = r.random()
        if d > 0 and c < 0.2:
            return N("and", "bool", [self.gen_b(d - 1), self.gen_b(d - 1)])
        if d > 0 and c < 0.35:
            return N("or", "bool", [self.gen_b(d - 1), self.gen_b(d - 1)])
        if d > 0 and c < 0.4:
            return N("not", "bool", [self.gen_b(d - 1)])
        op = r.choice(["<", "<=", ">", ">=", "==", "!="])
        a = self.gen_f("f64", 2, False)
        b = self.gen_f("f64", 2)
        if a.lit and b.lit:
            a = self.gen_f("f64", 1, False)
        return N("cmp", "bool", [a, b], op)

    # ----- statements
    def new_var_stmt(self, ty=None, mut=None):
        r = self.r
        if ty is None:
            ty = r.choice(["f64", "f64", "f32", "f32", "i64", "u64", "i32", "u8", "u32", "i16", "i8", "u16"])
        if mut is None:
            mut = r.random() < 0.7
        name = self.name({"f64": "x", "f32": "y"}.get(ty, "n"))
        if is_float(ty):
            e = self.gen_f(ty, r.randint(1, 4))
            annot = e.lit or r.random() < 0.4
        elif ty == "u64":
            e = self.gen_u(r.randint(0, 3))
            annot = True
        else:
            e = self.gen_i(r.randint(0, 3))
            if e.ty != ty:
                e = N("cast", ty, [e])
            annot = True
        self.declare(name, ty, mut)
        return ("let", name, ty, mut, e, annot)

    def assign_stmt(self):
        r = self.r
        ty = r.choice(["f64", "f64", "f32", "f32", "i64", "u64"])
        v = self.pick_var(ty, True)
        if not v:
            return None
        if is_float(ty):
            e = self.gen_f(ty, r.randint(1, 4))
            if r.random() < 0.25:
                op = r.choice(["+", "-", "*", "/"])
                e = self.gen_f(ty, r.randint(0, 3), r.random() < 0.5)
                if e.lit and not is_plain_lit(e) and ty == "f32":
                    e = self.gen_f(ty, 1, False)
                return ("opset", v[0], op, e, ty)
            return ("set", v[0], e, ty)
        if ty == "u64":
            return ("set", v[0], self.gen_u(r.randint(0, 3)), ty)
        e = self.gen_i(r.randint(0, 3))
        if e.ty != "i64":
            e = N("cast", "i64", [e])
        return ("set", v[0], e, ty)

    def store_stmt(self):
        r = self.r
        c = r.random()
        if c < 0.6:
            arr = r.choice(["fa", "fb", "fo"])
            return ("store", arr, self.index(), self.gen_f("f64", r.randint(1, 3)), "f64")
        if c < 0.85:
            return ("store", "ga", self.index(), self.gen_f("f32", r.randint(1, 3)), "f32")
        e = self.gen_i(2)
        if e.ty != "i64":
            e = N("cast", "i64", [e])
        return ("store", "ia", self.index(), e, "i64")

    def block(self, depth, n):
        self.push()
        out = []
        for _ in range(n):
            out += self.stmt(depth)
        self.pop()
        return out

    def stmt(self, depth):
        r = self.r
        c = r.random()
        if c < 0.22:
            return [self.new_var_stmt()]
        if c < 0.50:
            s = self.assign_stmt()
            return [s] if s else []
        if c < 0.58:
            if self.in_func:
                return [self.new_var_stmt()]
            return [self.store_stmt()]
        if c < 0.70 and depth < 3:
            cond = self.gen_b(2)
            t = self.block(depth + 1, r.randint(1, 3))
            f = self.block(depth + 1, r.randint(1, 3)) if r.random() < 0.5 else []
            if self.loop_depth > 0 and r.random() < 0.2:
                t.append((r.choice(["break", "continue"] if self.cont_ok[-1] else ["break"]),))
            return [("if", cond, t, f)]
        if c < 0.80 and depth < 3:
            cn = self.name("t")
            lim = r.choice([1, 2, 3, 5, 8, 12])
            extra = self.gen_b(1) if r.random() < 0.4 else None
            self.declare(cn, "i64", False)
            self.loop_depth += 1
            first = r.random() < 0.3
            self.cont_ok.append(first)
            body = self.block(depth + 1, r.randint(1, 4))
            if r.random() < 0.5:
                body.append(self.print_stmt())
            self.cont_ok.pop()
            self.loop_depth -= 1
            return [("while", cn, lim, extra, body, first)]
        if c < 0.88 and depth < 3 and self.vec is None and not self.in_func:
            return self.vec_loop()
        if c < 0.93:
            return [self.print_stmt()]
        s = self.assign_stmt()
        return [s] if s else []

    def print_stmt(self):
        r = self.r
        c = r.random()
        if self.opts.get("fmt") and c < 0.6:
            ty = r.choice(FLT)
            v = self.pick_var(ty)
            if v:
                return ("pp", None, v[0])
        if c < 0.7:
            ty = r.choice(FLT)
            v = self.pick_var(ty)
            if v:
                return ("pf", N("var", ty, v=v[0]))
        if c < 0.85:
            return ("pb", self.gen_b(2))
        ty = r.choice(["i64", "u64", "i32", "u8"])
        v = self.pick_var(ty)
        if v:
            return ("pi", N("var", ty, v=v[0]))
        v = self.pick_var("f64")
        if v:
            return ("pf", N("var", "f64", v=v[0]))
        return ("pb", self.gen_b(1))

    def vec_loop(self):
        r = self.r
        out = []
        iv = self.name("ix")
        lim = r.choice([8, 9, 15, 16, 17, 31, 33, 40, 56])
        out.append(("let", iv, "i64", True, N("ilit", "i64", v=r.choice([0, 0, 0, 1, 3]), lit=True), False))
        # uniforms: outer f64 variables never assigned inside the loop (immutable ones)
        uni = [n for (n, t, m) in self.vars_of("f64") if not m]
        accs = [n for (n, t, m) in self.vars_of("f64", True)[:] if m]
        accs = [a for a in accs if a not in uni]
        r.shuffle(accs)
        accs = accs[:r.randint(0, 2)]
        uni = uni + [n for (n, t, m) in self.vars_of("f64", True) if n not in accs and False]
        self.push()
        st = {"iv": iv, "vars": [], "uni": uni, "ints": []}
        self.vec = st
        body = []
        pv = []
        for _ in range(r.randint(1, 3)):
            nm = self.name("v")
            e = self.gen_f("f64", r.randint(0, 3))
            body.append(("let", nm, "f64", True, e, True))
            st["vars"].append(nm)
            pv.append(nm)
        # inner loop
        cn = self.name("t")
        st["ints"].append(cn)
        body.append(("let", cn, "i64", True, N("ilit", "i64", v=0, lit=True), False))
        inner = []
        for _ in range(r.randint(1, 4)):
            c = r.random()
            if c < 0.5 and pv:
                inner.append(("set", r.choice(pv), self.gen_f("f64", r.randint(1, 3)), "f64"))
            else:
                cond = self.gen_b(2)
                t = [("set", r.choice(pv), self.gen_f("f64", r.randint(1, 3)), "f64") for _ in range(r.randint(1, 2))]
                f = [("set", r.choice(pv), self.gen_f("f64", r.randint(1, 2)), "f64")] if r.random() < 0.5 else []
                inner.append(("if", cond, t, f))
        extra = self.gen_b(1) if r.random() < 0.5 else None
        lim2 = r.choice([1, 2, 4, 9])
        body.append(("vwhile", cn, "%d%s" % (lim2, (" && " + "@@") if extra is not None else ""), inner))
        # keep `extra` for emission
        body[-1] = ("vwhile2", cn, lim2, extra, inner)
        # POST
        self.vec = None
        post = []
        for a in accs:
            e = N("var", "f64", v=r.choice(pv))
            if r.random() < 0.5:
                post.append(("opset", a, r.choice(["+", "-", "*"]), e, "f64"))
            else:
                post.append(("set", a, N("bin", "f64", [N("bin", "f64", [N("var", "f64", v=a), N("lit", "f64", v=r.choice(["0.5", "0.999", "1.5"]), lit=True)], "*"), e], "+"), "f64"))
        post.append(("store", "fo", N("var", "i64", v=iv), N("var", "f64", v=pv[0]), "f64"))
        if r.random() < 0.3:
            post.append(("pf", N("var", "f64", v=r.choice(pv))))
        if r.random() < 0.1:
            post.append(("store", "fb", N("var", "i64", v=iv), N("var", "f64", v=r.choice(pv)), "f64"))
        self.pop()
        out.append(("vwhile", iv, str(lim), body + post))
        out.append(("pf", N("var", "f64", v=accs[0]))) if accs else None
        return [x for x in out if x]

    # ----- functions
    def gen_func(self, recursive):
        r = self.r
        name = self.name("h")
        np_ = r.randint(1, 6)
        params = []
        for i in range(np_):
            t = r.choice(["f64", "f64", "f32", "f32", "i64", "u64", "i32"])
            params.append((self.name("p"), t))
        if recursive:
            params.append(("d", "i64"))
        ret = r.choice(["f64", "f32"])
        saved = (self.scopes, self.in_func, self.loop_depth, self.cont_ok)
        self.cont_ok = [False]
        self.scopes = [[]]
        self.in_func = name
        self.loop_depth = 0
        for n, t in params:
            self.declare(n, t, False)
        body = []
        if recursive:
            body.append(("raw", "if d <= 0 { return %s; }" % "@LEAF@", "if (d <= 0) return %s;" % "@LEAF@"))
        body += self.block(1, r.randint(0, 4))
        rexpr = self.gen_f(ret, r.randint(1, 4))
        if ret == "f32" and rexpr.lit:
            rexpr = N("cast", "f32", [self.gen_f("f64", 1, False)])
        if rexpr.lit and ret == "f64" and False:
            pass
        if recursive:
            # add a self call into the result
            ptys = [t for _, t in params]
            args = []
            for n, t in params:
                if n == "d":
                    args.append(N("bin", "i64", [N("var", "i64", v="d"), N("ilit", "i64", v=1, lit=True)], "-"))
                elif is_float(t):
                    args.append(self.gen_f(t, 2, False))
                elif t == "u64":
                    args.append(self.gen_u(1))
                else:
                    args.append(N("cast", t, [self.gen_i(1)]))
            call = N("call", ret, args, (name, ptys))
            other = self.gen_f(ret, 2, False)
            rexpr = N("bin", ret, [call, other], r.choice(["+", "-", "*"])) if r.random() < 0.8 else N("bin", ret, [other, call], r.choice(["+", "-", "*", "/"]))
            leaf = self.gen_f(ret, 1, False)
            body[0] = ("raw", "if d <= 0 { return %s; }" % sk(leaf), "if (d <= 0) return %s;" % cx(leaf, ret))
        self.scopes, self.in_func, self.loop_depth, self.cont_ok = saved
        f = Func(name, params, ret, body, rexpr)
        self.funcs.append(f)
        return f

    # ----- program
    def program(self):
        r = self.r
        p = Prog()
        p.fmt = bool(self.opts.get("fmt"))
        p.input = build_input(r)
        # globals
        for _ in range(r.randint(0, 3)):
            ty = r.choice(FLT)
            nm = self.name("g")
            tx = lit_text(r, ty)
            p.globals.append((nm, ty, tx))
            self.glob.append((nm, ty))
        # functions
        for _ in range(r.randint(0, 3)):
            self.gen_func(False)
        for _ in range(r.randint(0, 2)):
            self.gen_func(True)
        p.funcs = list(self.funcs)
        main = []
        self.in_func = None
        # initial variables from runtime data (unknown to the compiler) and literals
        for i in range(r.randint(3, 8)):
            nm = self.name("x")
            ty = r.choice(FLT)
            if ty == "f64":
                e = N("ld", "f64", [], "dv"); e.a = [N("ilit", "i64", v=r.randrange(40), lit=True)]
            else:
                e = N("ld", "f32", [], "sv"); e.a = [N("ilit", "i64", v=80 + r.randrange(40), lit=True)]
            self.declare(nm, ty, r.random() < 0.8)
            main.append(("let", nm, ty, self.scopes[-1][-1][2], e, True))
        for i in range(r.randint(1, 4)):
            nm = self.name("n")
            ty = r.choice(["i64", "u64", "i32", "u8", "u32", "i16", "u16", "i8"])
            e = N("ld", "i64", [N("ilit", "i64", v=60 + r.randrange(24), lit=True)], "iv")
            if ty != "i64":
                e = N("cast", ty, [e])
            self.declare(nm, ty, r.random() < 0.7)
            main.append(("let", nm, ty, self.scopes[-1][-1][2], e, True))
        # untyped constants
        for i in range(r.randint(0, 3)):
            nm = self.name("k")
            tx = lit_text(r, "f64")
            if r.random() < 0.5:
                tx = r.choice(["0.1", "0.2", "1.5", "2.5", "0.3333333333333333", "10.0", "0.7"])
            self.consts["f64"].append((nm, tx))
            self.consts["f32"].append((nm, tx))
            main.append(("raw", "let %s = %s;" % (nm, tx), ""))
        for i in range(r.randint(1, 4)):
            ty = r.choice(FLT)
            nm = self.name("c")
            e = self.lit(ty)
            self.declare(nm, ty, False)
            main.append(("let", nm, ty, False, e, True))
        for _ in range(r.randint(8, 28)):
            main += self.stmt(0)
        # final output: every top-level variable, plus the arrays
        for (n, t, m) in self.scopes[0]:
            if is_float(t):
                main.append(("pf", N("var", t, v=n)))
            elif t == "u64":
                main.append(("pi", N("var", t, v=n)))
            else:
                main.append(("pi", N("var", t, v=n)))
        for (n, t) in self.glob:
            main.append(("pf", N("var", t, v=n)))
        main += self.dump_arrays()
        p.main = main
        return p

    def dump_arrays(self):
        out = [("raw",
                "let mut kk = 0; while kk < 64 { putc(100); print(bits(fo[kk])); putc(100); print(bits(fb[kk])); putc(100); print(bits(fa[kk])); putc(115); print(bits(ga[kk])); print(ia[kk]); kk += 1; }",
                "for (int64_t kk = 0; kk < 64; kk++) { pf64(fo[kk]); pf64(fb[kk]); pf64(fa[kk]); pf32(ga[kk]); pint(ia[kk], 0); }")]
        return out


# ---------------------------------------------------------------- driver
def run(cmd, timeout=20, **kw):
    try:
        return subprocess.run(cmd, capture_output=True, timeout=timeout, **kw)
    except subprocess.TimeoutExpired:
        return None


class Case:
    def __init__(self, prog, tmp):
        self.p = prog
        self.tmp = tmp


def canon_nan(out_bytes):
    """map every NaN bit pattern in 'd'/'s' tagged lines to one value"""
    res = []
    for ln in out_bytes.split(b"\n"):
        if ln[:1] == b"d" and ln[1:].isdigit():
            b = int(ln[1:])
            if (b >> 52) & 0x7FF == 0x7FF and b & ((1 << 52) - 1):
                ln = b"dNaN"
        elif ln[:1] == b"s" and ln[1:].isdigit():
            b = int(ln[1:])
            if (b >> 23) & 0xFF == 0xFF and b & ((1 << 23) - 1):
                ln = b"sNaN"
        res.append(ln)
    return b"\n".join(res)


def build_and_run(prog, tmp, tag="t", want_c=True):
    """returns dict with outputs or an error string"""
    ck = os.path.join(tmp, tag + ".ck")
    cf = os.path.join(tmp, tag + ".c")
    inp = os.path.join(tmp, tag + ".in")
    open(ck, "w").write(prog.skite())
    open(cf, "w").write(prog.c())
    open(inp, "wb").write(prog.input)
    res = {}
    r1 = run([SKITE, ck, os.path.join(tmp, tag + ".v")])
    r2 = run([SKITE, ck, os.path.join(tmp, tag + ".s"), "--scalar"])
    if r1 is None or r2 is None or r1.returncode or r2.returncode:
        err = (r1.stderr if r1 is not None and r1.returncode else r2.stderr if r2 is not None else b"timeout").decode(errors="replace")
        return {"error": "SKITE COMPILE: " + err[:600]}
    res["stats"] = r1.stdout.decode(errors="replace")
    if want_c:
        r3 = run([CC, "-O0", "-ffp-contract=off", "-fno-fast-math", "-fwrapv", "-fno-math-errno", "-w", "-o", os.path.join(tmp, tag + ".c.exe"), cf, "-lm"], timeout=60)
        if r3 is None or r3.returncode:
            return {"error": "GCC COMPILE: " + (r3.stderr.decode(errors="replace")[:600] if r3 else "timeout")}
    for nm, exe in (("v", tag + ".v"), ("s", tag + ".s"), ("c", tag + ".c.exe")):
        if nm == "c" and not want_c:
            continue
        r = run([os.path.join(tmp, exe), inp], timeout=10)
        if r is None:
            res[nm] = (None, b"")
        else:
            res[nm] = (r.returncode, r.stdout)
    return res


def check(res):
    """returns None if all agree, else a description. NaN payload-only differences are reported separately"""
    if "error" in res:
        return res["error"]
    rv, rs = res["v"], res["s"]
    if rv != rs:
        return "VECTOR!=SCALAR rc %s/%s" % (rv[0], rs[0])
    if "c" in res:
        rc = res["c"]
        if rc[0] != rs[0] or rc[1] != rs[1]:
            if rc[0] == rs[0] and canon_nan(rc[1]) == canon_nan(rs[1]):
                return "NANBITS"
            return "SKITE!=C rc %s/%s" % (rs[0], rc[0])
    return None


def first_diff(a, b):
    la, lb = a.split(b"\n"), b.split(b"\n")
    for i in range(max(len(la), len(lb))):
        x = la[i] if i < len(la) else b"<eof>"
        y = lb[i] if i < len(lb) else b"<eof>"
        if x != y:
            return i, x, y
    return None


def fails(prog, tmp, kind=None):
    res = build_and_run(prog, tmp, "r")
    d = check(res)
    if d is None or d == "NANBITS":
        return False
    if "COMPILE" in d:
        return False
    return d if kind is None else (d.split()[0] == kind.split()[0])


# ---------------------------------------------------------------- reducer
def sub_exprs(e, path=()):
    yield path, e
    for i, c in enumerate(e.a):
        yield from sub_exprs(c, path + (i,))


def replace_at(e, path, new):
    if not path:
        return new
    e2 = N(e.k, e.ty, e.a, e.v, e.lit)
    e2.a = list(e.a)
    e2.a[path[0]] = replace_at(e.a[path[0]], path[1:], new)
    return e2


def is_block(x):
    return isinstance(x, list) and (not x or isinstance(x[0], tuple))


def expr_variants(e):
    """strictly smaller expressions of the same type"""
    subs = sorted(sub_exprs(e), key=lambda t: len(t[0]))
    for path, se in subs:
        if se.k in ("lit", "var", "ilit", "ilitf", "const"):
            continue
        reps = [c for c in se.a if c.ty == se.ty and c.k != "bool"]
        if is_float(se.ty):
            reps.append(N("lit", se.ty, v="1.5", lit=True))
            reps.append(N("lit", se.ty, v="0.0", lit=True))
        elif se.ty in IRANGE:
            reps.append(N("ilit", se.ty, v=1, lit=True))
        for rep in reps:
            yield replace_at(e, path, rep)


def mut_stmts(stmts):
    """yield smaller variants of a statement list"""
    for i in range(len(stmts) - 1, -1, -1):
        s = stmts[i]
        yield stmts[:i] + stmts[i + 1:]
        if s[0] == "if":
            yield stmts[:i] + list(s[2]) + stmts[i + 1:]
            if s[3]:
                yield stmts[:i] + list(s[3]) + stmts[i + 1:]
                yield stmts[:i] + [s[:3] + ([],)] + stmts[i + 1:]
        for j, x in enumerate(s):
            if is_block(x):
                for nx in mut_stmts(x):
                    ns = list(s); ns[j] = nx
                    yield stmts[:i] + [tuple(ns)] + stmts[i + 1:]
            elif isinstance(x, N) and not (s[0] == "let" and j == 4 and False):
                for ne in expr_variants(x):
                    ns = list(s); ns[j] = ne
                    yield stmts[:i] + [tuple(ns)] + stmts[i + 1:]


def reduce_prog(prog, tmp, kind, log=print, budget=400):
    import copy
    cur = prog
    tries = 0
    changed = True
    while changed and tries < budget:
        changed = False
        for nm in mut_stmts(cur.main):
            tries += 1
            if tries >= budget:
                break
            q = copy.copy(cur)
            q.main = nm
            if fails(q, tmp, kind):
                cur = q
                changed = True
                log("  reduced: %d lines" % len(cur.skite().split("\n")))
                break
    # drop unused functions
    for f in list(cur.funcs):
        q = copy.copy(cur)
        q.funcs = [g for g in cur.funcs if g is not f]
        if fails(q, tmp, kind):
            cur = q
    return cur


def main():
    args = sys.argv[1:]
    opts = {}
    keep = None
    if "--keep" in args:
        i = args.index("--keep"); keep = args[i + 1]; del args[i:i + 2]
    for flag in ("--fmt", "--nonan", "--no-reduce", "--nanbits"):
        if flag in args:
            opts[flag[2:].replace("-", "")] = True
            args.remove(flag)
    if "--replay" in args:
        i = args.index("--replay")
        prog = Prog.from_j(json.load(open(args[i + 1])))
        tmp = tempfile.mkdtemp(prefix="fltdiff")
        res = build_and_run(prog, tmp, "r")
        print(check(res) or "OK")
        shutil.rmtree(tmp)
        return
    cases = int(args[0]) if args else 200
    seed = int(args[1]) if len(args) > 1 else 1
    tmp = tempfile.mkdtemp(prefix="fltdiff")
    nfail = nvec = nnan = 0
    try:
        for c in range(cases):
            rnd = random.Random(seed * 1000003 + c)
            g = Gen(rnd, opts)
            prog = g.program()
            res = build_and_run(prog, tmp, "t")
            d = check(res)
            if "stats" in res and " 0 loops vectorized" not in res["stats"]:
                nvec += 1
            if d == "NANBITS":
                nnan += 1
                if not opts.get("nanbits"):
                    continue
            if d is None:
                continue
            nfail += 1
            print("FAIL case %d (seed %d): %s" % (c, seed, d))
            if keep:
                os.makedirs(keep, exist_ok=True)
                base = os.path.join(keep, "fail_s%d_c%d" % (seed, c))
                json.dump(prog.to_j(), open(base + ".json", "w"))
                open(base + ".ck", "w").write(prog.skite())
                open(base + ".c", "w").write(prog.c())
                open(base + ".in", "wb").write(prog.input)
            if "COMPILE" in d:
                print(d)
                print(prog.skite() if "SKITE" in d else prog.c())
                if nfail >= 3:
                    break
                continue
            for nm in ("v", "s", "c"):
                pass
            fd = first_diff(res["s"][1], res["c"][1]) if "c" in res else None
            if d.startswith("VECTOR"):
                fd = first_diff(res["v"][1], res["s"][1])
            print("  first diff (line, a, b):", fd)
            if not opts.get("noreduce"):
                small = reduce_prog(prog, tmp, d)
                print("  --- reduced skite program ---")
                print(small.skite())
                if keep:
                    json.dump(small.to_j(), open(base + ".min.json", "w"))
                    open(base + ".min.ck", "w").write(small.skite())
                    open(base + ".min.c", "w").write(small.c())
                    open(base + ".min.in", "wb").write(small.input)
            if nfail >= 5:
                break
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print("%s %d programs (%d vectorized, %d NaN-payload-only diffs), %d failures, seed %d" %
          ("FAIL" if nfail else "PASS", cases, nvec, nnan, nfail, seed))
    sys.exit(1 if nfail else 0)


if __name__ == "__main__":
    main()
