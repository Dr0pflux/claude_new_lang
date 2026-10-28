#!/usr/bin/env python3
"""Differential fuzzer for the SIMD vectorizer: random loop nests built to be
vectorizable (varying masks, inner loops, int/float mixes) are compiled twice,
normally and with --scalar, and must print identical output.
usage: tests/vec_fuzz.py [CASES] [SEED]"""
import os, random, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKITE = os.environ.get("SKITE", os.path.join(ROOT, "skite"))

class Gen:
    def __init__(self, rnd):
        self.r = rnd
        self.n = 0
    def name(self, p):
        self.n += 1
        return f"{p}{self.n}"
    def iexpr(self, ints, d=0):
        r = self.r
        if d > 3 or r.random() < 0.3:
            c = r.random()
            if c < 0.45 and ints: return r.choice(ints)
            if c < 0.6: return str(r.choice([0, 1, 2, 3, 7, 100, 1000003, -5, -128, 255, 65535]))
            if c < 0.75: return f"ia[{r.randrange(16)}]"
            uni = [v for v in ints if v == "u" or v.startswith("t")]
            if c < 0.82 and uni: return f"ib[({r.choice(uni)}) & 15]"   # bounds-checked, often uniform
            return r.choice(ints) if ints else "1"
        op = r.choice(["+", "-", "*", "&", "|", "^", "<<", ">>", ">>>", "/", "%", "cast", "neg", "not", "f2i", "same"])
        a = self.iexpr(ints, d + 1)
        if op == "same": return f"({a} {r.choice(['+', '-', '*', '^'])} ({a} + {r.choice(['0', '1', 'u'])}))"   # repeated subexpression
        if op in ("<<", ">>", ">>>"): return f"({a} {op} {r.randrange(64)})"
        if op in ("/", "%"): return f"({a} {op} {r.choice([1, 2, 4, 8, 16, 1024])})"
        if op == "cast": return f"(({a}) as {r.choice(['i8', 'i16', 'i32', 'u8', 'u16', 'u32'])} as i64)"
        if op == "neg": return f"(0 - {a})"
        if op == "not": return f"(~{a})"
        if op == "f2i": return f"(({a}) as f64 as i64)"   # int -> f64 -> int (exact for |x| < 2^53 only; cast saturates)
        b = self.iexpr(ints, d + 1)
        return f"({a} {op} {b})"
    def fexpr(self, fls, ints, d=0):
        r = self.r
        if d > 3 or r.random() < 0.3:
            c = r.random()
            if c < 0.5 and fls: return r.choice(fls)
            if c < 0.7: return r.choice(["0.0", "1.0", "2.0", "0.5", "-3.25", "1e300", "1e-300", "0.1"])
            if c < 0.85: return f"fa[{r.randrange(16)}]"
            uni = [v for v in ints if v == "u" or v.startswith("t")]
            if c < 0.92 and uni: return f"fb[({r.choice(uni)}) & 15]"
            return f"({self.iexpr(ints, d + 1)} as f64)"
        op = r.choice(["+", "-", "*", "/", "sqrt", "neg", "i2d", "same", "recip"])
        if op == "recip": return f"(1.0 / ({self.iexpr(ints, d + 1)} as f64))"
        a = self.fexpr(fls, ints, d + 1)
        if op == "same": return f"({a} {r.choice(['+', '-', '*', '/'])} ({a} * {r.choice(['1.0', '0.5', 'uf'])}))"
        if op == "sqrt": return f"sqrt({a})"
        if op == "neg": return f"(-{a})"
        if op == "i2d": return f"({self.iexpr(ints, d + 1)} as f64)"
        return f"({a} {op} {self.fexpr(fls, ints, d + 1)})"
    def cond(self, fls, ints, d=0):
        r = self.r
        c = r.random()
        if d < 2 and c < 0.15: return f"({self.cond(fls, ints, d + 1)} && {self.cond(fls, ints, d + 1)})"
        if d < 2 and c < 0.25: return f"({self.cond(fls, ints, d + 1)} || {self.cond(fls, ints, d + 1)})"
        if d < 2 and c < 0.3: return f"!({self.cond(fls, ints, d + 1)})"
        op = r.choice(["<", "<=", ">", ">=", "==", "!="])
        if fls and r.random() < 0.5: return f"{self.fexpr(fls, ints, 2)} {op} {self.fexpr(fls, ints, 2)}"
        return f"{self.iexpr(ints, 2)} {op} {self.iexpr(ints, 2)}"
    def block(self, af, ai, rf, ri, depth, out, ind):
        """assigns only af/ai (PRE's own mutable variables); reads rf/ri"""
        r = self.r
        for _ in range(r.randrange(1, 4)):
            c = r.random()
            if c < 0.35 and ai: out.append(f"{ind}{r.choice(ai)} = {self.iexpr(ri)};")
            elif c < 0.7 and af: out.append(f"{ind}{r.choice(af)} = {self.fexpr(rf, ri)};")
            elif c < 0.85 and depth < 2:
                out.append(f"{ind}if {self.cond(rf, ri)} {{")
                self.block(af, ai, rf, ri, depth + 1, out, ind + "  ")
                if r.random() < 0.5:
                    out.append(f"{ind}}} else {{")
                    self.block(af, ai, rf, ri, depth + 1, out, ind + "  ")
                out.append(f"{ind}}}")
            elif depth < 2:
                t = self.name("t")
                lim = r.choice([1, 3, 10, 30])
                out.append(f"{ind}let mut {t} = 0;")
                extra = f" && {self.cond(rf, ri)}" if r.random() < 0.6 else ""
                out.append(f"{ind}while {t} < {lim}{extra} {{")
                self.block(af, ai, rf, ri + [t], depth + 1, out, ind + "  ")
                out.append(f"{ind}  {t} += 1;")
                out.append(f"{ind}}}")
    def program(self):
        r = self.r
        n = r.choice([0, 1, 7, 8, 9, 15, 16, 17, 33, 100])
        start = r.choice([0, 0, 0, -3, 5])
        L = []
        L.append("fn main() {")
        L.append("  let ia = alloc<i64>(16); let fa = alloc<f64>(16);")
        L.append("  let ib = alloc<i64>(15 + argc()); let fb = alloc<f64>(15 + argc());")
        L.append("  let mut k = 0;")
        L.append("  while k < 16 { ia[k] = k * 7919 - 50000 + argc(); fa[k] = (k as f64) * 0.37 - 2.5; ib[k] = ia[k] * 3 + 1; fb[k] = fa[k] * 1.5 + 0.25; k += 1; }")
        L.append(f"  let n = {n} + argc() - 1;")
        L.append("  let u = argc() * 3;")
        L.append("  let uf = 1.5 + (argc() as f64);")
        L.append("  let mut acc = 0; let mut facc: u64 = 0;")
        L.append(f"  let mut i = {start};")
        L.append("  while i < n {")
        ints = ["i", "u"]; fls = ["uf"]
        body = []
        for _ in range(r.randrange(1, 4)):
            v = self.name("x"); body.append(f"    let mut {v} = {self.iexpr(ints)};"); ints = ints + [v]
        for _ in range(r.randrange(1, 4)):
            v = self.name("f"); body.append(f"    let mut {v} = {self.fexpr(fls, ints)};"); fls = fls + [v]
        mut_i = [v for v in ints if v not in ("i", "u")]
        mut_f = [v for v in fls if v != "uf"]
        # one inner loop is required for vectorization
        t = self.name("t")
        body.append(f"    let mut {t} = 0;")
        extra = f" && {self.cond(fls, ints)}" if r.random() < 0.6 else ""
        body.append(f"    while {t} < {r.choice([1, 4, 20])}{extra} {{")
        inner = []
        self.block(mut_f, mut_i, fls, ints + [t], 1, inner, "      ")
        body += inner
        body.append(f"      {t} += 1;")
        body.append("    }")
        L += body
        post = []
        for v in mut_i + [t]: post.append(f"    acc = acc * 31 + {v};")
        for v in mut_f: post.append(f"    facc = facc * 31 + bits({v});")
        if r.random() < 0.3: post.append(f"    if {mut_i[0]} > 0 {{ print({mut_i[0]}); }}")
        L += post
        L.append("    i += 1;")
        L.append("  }")
        L.append("  print(acc); print(facc);")
        L.append("}")
        return "\n".join(L) + "\n"

def main():
    cases = int(sys.argv[1]) if len(sys.argv) > 1 else 200
    seed = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    rnd = random.Random(seed)
    tmp = tempfile.mkdtemp()
    vec = 0
    for c in range(cases):
        src = Gen(rnd).program()
        p = os.path.join(tmp, "v.ck")
        open(p, "w").write(src)
        r1 = subprocess.run([SKITE, p, os.path.join(tmp, "a")], capture_output=True, text=True)
        r2 = subprocess.run([SKITE, p, os.path.join(tmp, "b"), "--scalar"], capture_output=True, text=True)
        if r1.returncode or r2.returncode:
            print("COMPILE FAIL", r1.stderr, r2.stderr); print(src); sys.exit(1)
        if " 0 loops vectorized" not in r1.stdout: vec += 1
        try: o2 = subprocess.run([os.path.join(tmp, "b")], capture_output=True, timeout=10)
        except subprocess.TimeoutExpired: continue
        try: o1 = subprocess.run([os.path.join(tmp, "a")], capture_output=True, timeout=60)
        except subprocess.TimeoutExpired:
            print(f"VECTOR HANG case {c}"); print(src); open(os.path.join(ROOT, "vec_fail.ck"), "w").write(src); sys.exit(1)
        if o1.stdout != o2.stdout or o1.returncode != o2.returncode:
            print(f"MISMATCH case {c} (rc {o1.returncode} vs {o2.returncode})")
            print(src)
            print("vector:", o1.stdout[-300:]); print("scalar:", o2.stdout[-300:])
            open(os.path.join(ROOT, "vec_fail.ck"), "w").write(src)
            sys.exit(1)
    print(f"PASS {cases} programs ({vec} vectorized), seed {seed}")

main()
