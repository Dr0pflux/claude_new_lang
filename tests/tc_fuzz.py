#!/usr/bin/env python3
"""Differential fuzzer for recursion and self tail calls: random recursive functions
(tail calls in if/else branches and at the end, accumulator forms `X + f(..)` /
`X * f(..)` / `f(..) + Y`, argument permutations, side-effecting and trapping
arguments, array parameters, inner loops with returns and calls, unit functions)
are compiled with skite and run; stdout and the trap status must match an
independent reference interpreter written here.
usage: tests/tc_fuzz.py [CASES] [SEED]"""
import os, random, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKITE = os.environ.get("SKITE", os.path.join(ROOT, "skite"))
M64 = (1 << 64) - 1
MIN64 = -(1 << 63)
STEP_LIMIT = 300000

def wrap(x):
    x &= M64
    return x - (1 << 64) if x >> 63 else x

class Trap(Exception): pass
class TooLong(Exception): pass
class Ret(Exception):
    def __init__(self, v): self.v = v

# ---------------------------------------------------------------- generator
class Gen:
    def __init__(self, r):
        self.r = r
        self.cnt = 0
    def fresh(self, p):
        self.cnt += 1
        return f"{p}{self.cnt}"

    def leaf(self, sc):
        r = self.r
        c = r.random()
        if c < 0.6 and sc: return ("v", r.choice(sc))
        return ("c", r.choice([0, 1, 2, 3, 5, 7, -1, -3, 100, 1000003, 2147483648, -9223372036854775807 - 1, 9223372036854775807]))

    def expr(self, F, sc, d, pure=False, calls=True):
        """an i64 expression over the scalars sc; pure: no calls, loads or traps"""
        r = self.r
        if d <= 0 or r.random() < 0.3: return self.leaf(sc)
        c = r.random()
        if not pure:
            if c < 0.08: return ("tick", r.randrange(26), self.expr(F, sc, d - 1, calls=calls))
            if c < 0.14: return ("ld", F["arr"], self.expr(F, sc, d - 1, calls=calls))
            if c < 0.20 and calls and F["lower"]:
                g = r.choice(F["lower"])
                return ("call", g["name"], [("c", r.randrange(3))] + [self.expr(F, sc, d - 2, calls=False) for _ in range(g["np"])] + ([("arr", F["arr"])] if g["arr"] else []))
            if c < 0.26:
                op = r.choice(["/", "%"])
                return ("bin", op, self.expr(F, sc, d - 1, calls=calls), ("bin", "-", ("v", r.choice(sc)), ("c", r.choice([0, 1, 3, -1]))))
        if c < 0.32: return ("neg", self.expr(F, sc, d - 1, pure, calls))
        op = r.choice(["+", "-", "*", "&", "|", "^", "+", "-", "*"])
        return ("bin", op, self.expr(F, sc, d - 1, pure, calls), self.expr(F, sc, d - 1, pure, calls))

    def cond(self, F, sc):
        r = self.r
        op = r.choice(["<", "<=", ">", ">=", "==", "!="])
        c = ("cmp", op, self.expr(F, sc, 2, calls=False), self.expr(F, sc, 1, calls=False))
        if r.random() < 0.15: c = ("and", c, ("cmp", "!=", self.leaf(sc), ("c", 0)))
        if r.random() < 0.1: c = ("not", c)
        return c

    def selfcall(self, F, sc, nested_ok):
        r = self.r
        step = r.choice([1, 1, 1, 2])
        args = [("bin", "-", ("v", "d"), ("c", step))]
        ps = F["params"]
        for i in range(F["np"]):
            c = r.random()
            if c < 0.3: args.append(("v", r.choice(ps)))           # permutation / pass-through
            elif c < 0.4 and nested_ok and F["branchy"]:
                args.append(self.selfcall(F, sc, False))            # non-tail recursion inside an argument
            else: args.append(self.expr(F, sc, 2))
        if F["arr"] is not None: args.append(("arr", F["arr"]))
        return ("call", F["name"], args)

    def tail(self, F, sc):
        r = self.r
        call = self.selfcall(F, sc, True)
        c = r.random()
        if c < 0.25: return call
        if c < 0.40: return ("bin", "+", self.expr(F, sc, 2), call)
        if c < 0.50: return ("bin", "*", self.expr(F, sc, 1), call)
        if c < 0.58: return ("bin", r.choice(["+", "*"]), call, self.expr(F, sc, 2, pure=True))
        if c < 0.64: return ("bin", "+", ("bin", "+", self.expr(F, sc, 1), call), self.expr(F, sc, 1, pure=True))
        if c < 0.70: return ("bin", "+", call, self.expr(F, sc, 2))                 # impure right operand
        if c < 0.75: return ("bin", "-", self.expr(F, sc, 1), call)
        if c < 0.80: return ("bin", "/", call, ("bin", "-", ("v", r.choice(sc)), ("c", 1)))
        if c < 0.85 and F["branchy"]: return ("bin", "+", self.selfcall(F, sc, False), call)   # fib-like
        if c < 0.90 and F["lower"]:
            g = r.choice(F["lower"])
            return ("call", g["name"], [("c", r.randrange(4))] + [self.expr(F, sc, 1, calls=False) for _ in range(g["np"])] + ([("arr", F["arr"])] if g["arr"] else []))
        return self.expr(F, sc, 2)

    def body(self, F):
        r = self.r
        sc = ["d"] + F["params"]
        out = []
        unit = F["unit"]
        base = ("retu",) if unit else ("ret", self.expr(F, sc, 2, calls=False))
        pre = [("putc", ("c", 48 + r.randrange(10)))] if unit else []
        out.append(("if", ("cmp", "<=", ("v", "d"), ("c", 0)), pre + [base], None))
        for _ in range(r.randrange(3)):
            c = r.random()
            if c < 0.3:
                x = self.fresh("x")
                if r.random() < 0.3: out.append(("let", x, ("v", r.choice(F["params"]))))   # an alias of a parameter
                else: out.append(("let", x, self.expr(F, sc, 2)))
                sc = sc + [x]
            elif c < 0.45 and F["arr"] is not None: out.append(("st", F["arr"], self.expr(F, sc, 1), self.expr(F, sc, 2)))
            elif c < 0.6: out.append(("print", self.expr(F, sc, 2)))
            elif c < 0.8:
                br = self.tail(F, sc) if not unit else None
                if unit: out.append(("if", self.cond(F, sc), [("print", self.leaf(sc)), ("expr", self.selfcall(F, sc, False)), ("retu",)], None))
                elif r.random() < 0.5: out.append(("if", self.cond(F, sc), [("ret", br)], None))
                else: out.append(("if", self.cond(F, sc), [("ret", br)], [("ret", self.tail(F, sc))]))
            else:
                # inner loop: a non-tail return, a self call (not a tail call: inside a loop) or a store
                i = self.fresh("i")
                lim = r.randrange(1, 4)
                inner = []
                c2 = r.random()
                if c2 < 0.4: inner.append(("if", self.cond(F, sc + [i]), [("retu",) if unit else ("ret", self.expr(F, sc + [i], 2))], None))
                elif c2 < 0.7 and not unit: inner.append(("if", ("cmp", "==", ("v", i), ("c", lim - 1)), [("ret", self.selfcall(F, sc, False))], None))
                else: inner.append(("print", self.expr(F, sc + [i], 1)))
                out.append(("loop", i, lim, inner))
        if unit:
            c = r.random()
            if c < 0.5: out.append(("expr", self.selfcall(F, sc, False)))
            elif c < 0.75: out.append(("if", self.cond(F, sc), [("expr", self.selfcall(F, sc, False))], [("putc", ("c", 46))]))
            else: out += [("expr", self.selfcall(F, sc, False)), ("retu",)]
        else:
            out.append(("ret", self.tail(F, sc)))
        return out

    def program(self):
        r = self.r
        nf = r.randrange(1, 4)
        funcs = []
        for j in range(nf):
            unit = r.random() < 0.25
            np_ = r.randrange(1, 4)
            F = {"name": f"f{j}", "np": np_, "params": [f"p{j}_{k}" for k in range(np_)], "unit": unit,
                 "branchy": r.random() < 0.3, "arr": f"a{j}" if r.random() < 0.4 else None,
                 "lower": [g for g in funcs if not g["unit"]]}
            F["body"] = self.body(F)
            funcs.append(F)
        main = []
        for _ in range(r.randrange(2, 5)):
            F = r.choice(funcs)
            D = r.choice([0, 1, 2, 5, 9]) if F["branchy"] else r.choice([0, 1, 3, 10, 50, 300, 1500])
            args = [("c", D)] + [("bin", "+", ("v", "n"), self.leaf([])) for _ in range(F["np"])]
            if F["arr"] is not None: args.append(("arr", r.choice(["g", "loc"])))
            call = ("call", F["name"], args)
            main.append(("expr", call) if F["unit"] else ("print", call))
        return funcs, main

# ---------------------------------------------------------------- printer
def pe(e):
    k = e[0]
    if k == "c":
        v = e[1]
        if v == MIN64: return "(-9223372036854775807 - 1)"
        return f"({v})" if v < 0 else str(v)
    if k == "v": return e[1]
    if k == "bin": return f"({pe(e[2])} {e[1]} {pe(e[3])})"
    if k == "neg": return f"(-{pe(e[1])})"
    if k == "tick": return f"tick({e[1]}, {pe(e[2])})"
    if k == "ld": return f"{e[1]}[({pe(e[2])}) & 15]"
    if k == "call": return f"{e[1]}({', '.join(pe(a) for a in e[2])})"
    if k == "arr": return e[1]
    if k == "cmp": return f"{pe(e[2])} {e[1]} {pe(e[3])}"
    if k == "and": return f"({pe(e[1])}) && ({pe(e[2])})"
    if k == "not": return f"!({pe(e[1])})"
    raise ValueError(k)

def ps(s, ind, out):
    k = s[0]
    p = "  " * ind
    if k == "ret": out.append(f"{p}return {pe(s[1])};")
    elif k == "retu": out.append(f"{p}return;")
    elif k == "let": out.append(f"{p}let {s[1]} = {pe(s[2])};")
    elif k == "st": out.append(f"{p}{s[1]}[({pe(s[2])}) & 15] = {pe(s[3])};")
    elif k == "print": out.append(f"{p}print({pe(s[1])});")
    elif k == "putc": out.append(f"{p}putc({pe(s[1])});")
    elif k == "expr": out.append(f"{p}{pe(s[1])};")
    elif k == "if":
        out.append(f"{p}if {pe(s[1])} {{")
        for t in s[2]: ps(t, ind + 1, out)
        if s[3] is not None:
            out.append(f"{p}}} else {{")
            for t in s[3]: ps(t, ind + 1, out)
        out.append(f"{p}}}")
    elif k == "loop":
        out.append(f"{p}let mut {s[1]} = 0;")
        out.append(f"{p}while {s[1]} < {s[2]} {{")
        for t in s[3]: ps(t, ind + 1, out)
        out.append(f"{p}  {s[1]} += 1;")
        out.append(f"{p}}}")
    else: raise ValueError(k)

def render(funcs, main):
    out = ["let g = alloc<i64>(16);", "fn tick(k: i64, v: i64) -> i64 { putc(k + 65); return v; }"]
    for F in funcs:
        prm = ["d: i64"] + [f"{p}: i64" for p in F["params"]] + ([f"{F['arr']}: mut [i64]"] if F["arr"] else [])
        out.append(f"fn {F['name']}({', '.join(prm)}){'' if F['unit'] else ' -> i64'} {{")
        for s in F["body"]: ps(s, 1, out)
        out.append("}")
    out.append("fn main() {")
    out.append("  let n = argc();")
    out.append("  let loc = alloc<i64>(16);")
    out.append("  let mut q = 0;")
    out.append("  while q < 16 { g[q] = q * 7 - 20; loc[q] = 100 - q * q; q += 1; }")
    for s in main: ps(s, 1, out)
    out.append("}")
    return "\n".join(out) + "\n"

# ---------------------------------------------------------------- reference interpreter
class Interp:
    def __init__(self, funcs):
        self.fn = {F["name"]: F for F in funcs}
        self.out = []
        self.steps = 0
        self.mem = {"g": [wrap(q * 7 - 20) for q in range(16)], "loc": [wrap(100 - q * q) for q in range(16)]}
    def step(self):
        self.steps += 1
        if self.steps > STEP_LIMIT: raise TooLong()
    def ev(self, e, env):
        k = e[0]
        if k == "c": return e[1]
        if k == "v": return env[e[1]]
        if k == "neg": return wrap(-self.ev(e[1], env))
        if k == "tick":
            v = self.ev(e[2], env); self.out.append(chr(e[1] + 65)); return v
        if k == "ld":
            i = self.ev(e[2], env) & 15
            return self.mem[env[e[1]]][i]
        if k == "arr": return env[e[1]]
        if k == "call": return self.call(e[1], [self.ev(a, env) for a in e[2]])
        if k == "bin":
            a = self.ev(e[2], env); b = self.ev(e[3], env); op = e[1]
            if op == "+": return wrap(a + b)
            if op == "-": return wrap(a - b)
            if op == "*": return wrap(a * b)
            if op == "&": return wrap(a & b)
            if op == "|": return wrap(a | b)
            if op == "^": return wrap(a ^ b)
            if op in "/%":
                if b == 0 or (a == MIN64 and b == -1): raise Trap()
                q = abs(a) // abs(b)
                if (a < 0) != (b < 0): q = -q
                return wrap(q) if op == "/" else wrap(a - q * b)
        if k == "cmp":
            a = self.ev(e[2], env); b = self.ev(e[3], env)
            return {"<": a < b, "<=": a <= b, ">": a > b, ">=": a >= b, "==": a == b, "!=": a != b}[e[1]]
        if k == "and": return self.ev(e[1], env) and self.ev(e[2], env)
        if k == "not": return not self.ev(e[1], env)
        raise ValueError(k)
    def run(self, body, env):
        for s in body:
            self.step()
            k = s[0]
            if k == "ret": raise Ret(self.ev(s[1], env))
            if k == "retu": raise Ret(None)
            if k == "let": env[s[1]] = self.ev(s[2], env)
            elif k == "st":
                v = self.ev(s[3], env); i = self.ev(s[2], env) & 15
                self.mem[env[s[1]]][i] = v
            elif k == "print": self.out.append(str(self.ev(s[1], env)) + "\n")
            elif k == "putc": self.out.append(chr(self.ev(s[1], env) & 255))
            elif k == "expr": self.ev(s[1], env)
            elif k == "if":
                if self.ev(s[1], env): self.run(s[2], env)
                elif s[3] is not None: self.run(s[3], env)
            elif k == "loop":
                env[s[1]] = 0
                while env[s[1]] < s[2]:
                    self.run(s[3], env)
                    env[s[1]] += 1
    def call(self, name, args):
        F = self.fn[name]
        names = ["d"] + F["params"] + ([F["arr"]] if F["arr"] else [])
        env = dict(zip(names, args))
        try: self.run(F["body"], env)
        except Ret as r: return r.v
        return None

def reference(funcs, main):
    it = Interp(funcs)
    env = {"n": 1, "g": "g", "loc": "loc"}
    trap = False
    try:
        for s in main:
            k = s[0]
            if k == "print": it.out.append(str(it.ev(s[1], env)) + "\n")
            else: it.ev(s[1], env)
    except Trap: trap = True
    return "".join(it.out), trap

def main():
    cases = int(sys.argv[1]) if len(sys.argv) > 1 else 200
    seed = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    sys.setrecursionlimit(1000000)
    r = random.Random(seed)
    tmp = tempfile.mkdtemp()
    src = os.path.join(tmp, "t.ck"); exe = os.path.join(tmp, "t")
    done = traps = 0
    while done < cases:
        funcs, mainb = Gen(r).program()
        try: want, wtrap = reference(funcs, mainb)
        except TooLong: continue
        except RecursionError: continue
        text = render(funcs, mainb)
        open(src, "w").write(text)
        cp = subprocess.run([SKITE, src, exe], capture_output=True, text=True)
        if cp.returncode != 0:
            print(f"COMPILE FAIL (seed {seed} case {done})\n{cp.stdout}{cp.stderr}\n{text}"); sys.exit(1)
        p = subprocess.run([exe], capture_output=True, timeout=20)
        got = p.stdout.decode("latin-1")
        bad = got != want or (p.returncode == 136) != wtrap or (p.returncode not in (0, 136))
        if bad:
            print(f"MISMATCH (seed {seed} case {done}): rc={p.returncode} want trap={wtrap}")
            print(f"--- got\n{got[:1500]}\n--- want\n{want[:1500]}\n--- program\n{text}")
            sys.exit(1)
        traps += wtrap
        done += 1
    print(f"PASS {cases} recursive programs ({traps} trapping)")

if __name__ == "__main__":
    main()
