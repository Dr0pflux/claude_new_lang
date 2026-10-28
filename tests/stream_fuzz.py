#!/usr/bin/env python3
"""Differential fuzzer for element-wise ("stream") vector loops: array stores a[i] = e,
compound stores a[i] op= e, integer reductions s op= e, loads a[i + c] of every element type,
unproven bounds (guards), out-of-bounds traps, and array parameters that alias at run time.
Each program is compiled normally and with --scalar; output and exit status must match.
usage: tests/stream_fuzz.py [CASES] [SEED]"""
import os, random, subprocess, sys, tempfile, shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKITE = os.environ.get("SKITE", os.path.join(ROOT, "skite"))
CT = float(os.environ.get("SKITE_COMPILE_TIMEOUT", "10"))
TYPES = ["i64", "u64", "f64", "i32", "u32", "i16", "u16", "i8", "u8"]
LEN = 48

class Gen:
    def __init__(self, r):
        self.r = r
    def ival(self, arrs, temps, d=0):
        """an i64-typed expression"""
        r = self.r
        if d > 2 or r.random() < 0.35:
            c = r.random()
            if c < 0.45:
                ints = [a for a in arrs if a[1] != "f64"]
                if ints:
                    nm, t = r.choice(ints)
                    x = f"{nm}[i{self.off()}]"
                    return f"({x} as i64)" if t == "u64" else x
            if c < 0.6: return "i"
            if c < 0.7 and temps: return r.choice(temps)
            if c < 0.8: return r.choice(["k1", "k2"])
            return str(r.choice([0, 1, 2, 3, 5, 7, 100, -1, -9, 255, 65535, 1000003]))
        op = r.choice(["+", "-", "*", "&", "|", "^", "<<", ">>", "neg", "not", "nar"])
        a = self.ival(arrs, temps, d + 1)
        if op in ("<<", ">>"): return f"({a} {op} {r.randrange(64)})"
        if op == "neg": return f"(0 - {a})"
        if op == "not": return f"(~{a})"
        if op == "nar": return f"(({a}) as {r.choice(['i8', 'u8', 'i16', 'u16', 'i32', 'u32'])} as i64)"
        return f"({a} {op} {self.ival(arrs, temps, d + 1)})"
    def fval(self, arrs, ftemps, d=0):
        r = self.r
        if d > 2 or r.random() < 0.35:
            c = r.random()
            fl = [a for a in arrs if a[1] == "f64"]
            if c < 0.45 and fl: return f"{r.choice(fl)[0]}[i{self.off()}]"
            if c < 0.55 and ftemps: return r.choice(ftemps)
            if c < 0.7: return "(i as f64)"
            if c < 0.8: return "kf"
            return r.choice(["1.5", "0.25", "-3.0", "1000.0", "0.1"])
        op = r.choice(["+", "-", "*", "/", "sqrt", "neg"])
        a = self.fval(arrs, ftemps, d + 1)
        if op == "sqrt": return f"sqrt({a})"
        if op == "neg": return f"(0.0 - {a})"
        return f"({a} {op} {self.fval(arrs, ftemps, d + 1)})"
    def off(self):
        r = self.r.random()
        if r < 0.6: return ""
        c = self.r.choice([1, 2, 3, -1, -2, -3])
        return f" + {c}" if c > 0 else f" - {-c}"
    def body(self, arrs, stored, reds, depth=0):
        r = self.r
        temps, ftemps, out = [], [], []
        nt = 0
        for _ in range(r.randrange(1, 6)):
            c = r.random()
            if c < 0.15:
                nt += 1; t = f"t{nt}"; out.append(f"let {t} = {self.ival(arrs, temps)};"); temps.append(t)
            elif c < 0.25:
                nt += 1; t = f"g{nt}"; out.append(f"let {t} = {self.fval(arrs, ftemps)};"); ftemps.append(t)
            elif c < 0.45 and reds:
                s, op = r.choice(reds)
                out.append(f"{s} {op}= {self.ival(arrs, temps)};")
            else:
                nm, t = r.choice(stored)
                if t == "f64":
                    if r.random() < 0.3: out.append(f"{nm}[i] {r.choice(['+', '*', '-'])}= {self.fval(arrs, ftemps)};")
                    else: out.append(f"{nm}[i] = {self.fval(arrs, ftemps)};")
                else:
                    v = self.ival(arrs, temps)
                    if t == "u64": v = f"({v}) as u64"
                    if r.random() < 0.35: out.append(f"{nm}[i] {r.choice(['+', '-', '^', '|', '&', '*'])}= {v};")
                    elif t in ("i64", "u64"): out.append(f"{nm}[i] = {v};")
                    else: out.append(f"{nm}[i] = ({v}) as {t};")
        if r.random() < 0.08: out.append("if i == 5 { k3 += 1; }")   # uniform-free branch on i: masked
        if r.random() < 0.3:   # masked block: stores / reductions under a varying condition
            inner = self.body(arrs, stored, reds, depth + 1) if depth < 1 else []
            inner = [x for x in inner if not x.startswith("let ")][:2] or [f"k3 += 1;"]
            c = self.cond(arrs, temps)
            if r.random() < 0.4:
                other = [x for x in self.body(arrs, stored, reds, 2) if not x.startswith("let ")][:1] or ["k3 -= 1;"]
                out.append(f"if {c} {{ {' '.join(inner)} }} else {{ {' '.join(other)} }}")
            else: out.append(f"if {c} {{ {' '.join(inner)} }}")
        if r.random() < 0.25:   # max/min reduction
            x = self.ival(arrs, temps)
            m = r.choice(["mx", "mn"])
            cmp = (">" if m == "mx" else "<") + r.choice(["", "="])
            if r.random() < 0.5: out.append(f"if {x} {cmp} {m} {{ {m} = {x}; }}")
            else:
                flip = {">": "<", ">=": "<=", "<": ">", "<=": ">="}[cmp]
                out.append(f"if {m} {flip} {x} {{ {m} = {x}; }}")
        return out
    def cond(self, arrs, temps):
        r = self.r
        c = f"({self.ival(arrs, temps)} {r.choice(['<', '<=', '>', '>=', '==', '!='])} {self.ival(arrs, temps)})"
        if r.random() < 0.3: c = f"({c} {r.choice(['&&', '||'])} ({self.ival(arrs, temps)} {r.choice(['<', '>', '=='])} {r.choice(['0', '7', 'k1'])}))"
        if r.random() < 0.15: c = f"!{c}"
        return c

def text_program(r):
    """byte-lane loops: u8/i8 arrays, comparisons with in-range constants, counts, byte sums"""
    na = r.randrange(1, 4)
    arrs = [(f"a{j}", r.choice(["u8", "u8", "i8"])) for j in range(na)]
    stored = arrs[:r.randrange(1, na + 1)]
    def load():
        nm, t = r.choice(arrs)
        c = r.random()
        off = "" if c < 0.7 else f" + {r.choice([1, 2, 3])}"
        return f"{nm}[i{off}]", t
    def const(t):
        return str(r.randrange(0, 256) if t == "u8" else r.randrange(-128, 128))
    def bval(d=0):
        if d > 1 or r.random() < 0.4:
            x, t = load(); return x
        op = r.choice(["+", "-", "&", "|", "^"])
        x, t = load()
        return f"({x} {op} {bval(d + 1) if r.random() < 0.5 else const(t)})"
    def cond():
        x, t = load()
        c = f"({x} {r.choice(['==', '!=', '<', '<=', '>', '>='])} {const(t)})"
        if r.random() < 0.3:
            y, u = load()
            if u == t: c = f"({c} {r.choice(['&&', '||'])} ({y} {r.choice(['==', '<', '>='])} {const(u)}))"
        if r.random() < 0.15: c = f"!{c}"
        return c
    def stmt(d=0):
        c = r.random()
        if c < 0.3:
            nm, t = r.choice(stored)
            if r.random() < 0.3: return f"{nm}[i] {r.choice(['+', '-', '^', '|', '&'])}= {bval()};"
            return f"{nm}[i] = ({bval()}) as {t};"
        if c < 0.5: return f"k3 {r.choice(['+', '-'])}= {r.choice([1, 2, 7])};"
        if c < 0.65:
            u = [a for a in arrs if a[1] == "u8"]
            if u: return f"s0 += {r.choice(u)[0]}[i];"
            return "k3 += 1;"
        if d < 2:
            body = " ".join(stmt(d + 1) for _ in range(r.randrange(1, 3)))
            if r.random() < 0.4: return f"if {cond()} {{ {body} }} else {{ {stmt(d + 1)} }}"
            return f"if {cond()} {{ {body} }}"
        return "k3 += 1;"
    n = LEN * 4
    L = [f"fn main() {{", f"  let n = {n} - 4 + argc() * {r.choice([1, 3, 37])};", f"  let mut k3 = 0; let mut s0 = 0; let mut st = {r.choice([0, 1, 0, 2])};"]
    for nm, t in arrs:
        L.append(f"  let {nm} = alloc<{t}>({n + 200});")
        L.append(f"  let mut j{nm} = 0; while j{nm} < {n + 200} {{ {nm}[j{nm}] = ((j{nm} * 1103515245 + 12345 + j{nm} * j{nm} * 97) % 1000003) as {t}; j{nm} += 1; }}")
    s0 = r.choice([0, 0, 1, 5])
    end = r.choice(["n", "n", "n - 7", "n + 300"])   # n + 300 runs past the arrays: traps
    L.append(f"  let mut i = {s0};")
    L.append(f"  while i < {end} {{")
    for _ in range(r.randrange(1, 4)): L.append("    " + stmt())
    if r.random() < 0.5:   # 0/1 state flag (first-order recurrence), sometimes in shapes that must stay scalar
        a, b = r.choice([(0, 1), (1, 0)])
        use = f"if st == {r.choice([0, 1])} {{ {stmt(2)} }}"
        shape = r.random()
        if shape < 0.6: L.append(f"    if {cond()} {{ st = {a}; }} else {{ {use} st = {b}; }}")
        elif shape < 0.75: L.append(f"    {use} if {cond()} {{ st = {a}; }} else {{ st = {b}; }}")
        elif shape < 0.85: L.append(f"    if {cond()} {{ st = {a}; }} {use}")              # not assigned on every path
        else: L.append(f"    if st == 0 {{ st = 1; }} else {{ st = 0; }}")                  # depends on itself
    L.append("    i += 1;\n  }")
    L.append("  print(k3); print(s0); print(st);")
    for nm, t in arrs:
        L.append(f"  let mut h{nm} = 0; let mut q{nm} = 0; while q{nm} < {n + 200} {{ h{nm} = h{nm} * 31 + {nm}[q{nm}]; q{nm} += 1; }} print(h{nm});")
    L.append("}")
    return "\n".join(L) + "\n"

def program(r, fn_mode):
    g = Gen(r)
    na = r.randrange(2, 5)
    mixed = fn_mode and r.random() < 0.4      # parameters of different widths, passed views of one buffer
    if fn_mode and not mixed:
        t = r.choice(TYPES); types = [t] * na
    else:
        types = [r.choice(TYPES) for _ in range(na)]
    names = [f"a{j}" for j in range(na)]
    arrs = list(zip(names, types))
    nstore = r.randrange(1, na + 1)
    stored = arrs[:nstore]
    reds = [(f"s{j}", op) for j, op in enumerate(r.sample(["+", "-", "^", "|", "&"], r.randrange(0, 3)))]
    s0 = r.choice([0, 0, 0, 1, 2, 3])
    nexpr = r.choice(["n", "n", "n - 3", "n + 2", "3", "0"])
    lines = []
    if fn_mode:
        params = ", ".join(f"{nm}: mut [{t}]" if (nm, t) in stored else f"{nm}: [{t}]" for nm, t in arrs)
        lines.append(f"fn kern({params}, n: i64, k1: i64, k2: i64, kf: f64, d: i64) -> i64 {{")
        lines.append(f"  if d > 0 {{ return kern({', '.join(names)}, n, k1, k2, kf, d - 1); }}")
        lines.append("  let mut k3 = 0; let mut mx = 0 - 5; let mut mn = 5;")
        for s, op in reds: lines.append(f"  let mut {s}: i64 = {'-1' if op == '&' else '7'};")
        lines.append(f"  let mut i = {s0};")
        lines.append(f"  while i < {nexpr} {{")
        lines += ["    " + x for x in g.body(arrs, stored, reds)]
        lines.append("    i += 1;\n  }")
        lines.append(f"  return k3 + mx * 3 + mn * 5{''.join(' + ' + s for s, _ in reds)};")
        lines.append("}")
    lines.append("fn main() {")
    lines.append(f"  let n = {LEN} - 4 + argc();")   # 45: not a multiple of the vector width
    lines.append("  let k1 = argc() + 2; let k2 = 0 - argc() * 3; let kf = (argc() as f64) * 0.5;")
    views = (not fn_mode and r.random() < 0.3) or mixed   # arrays share one byte buffer through views of different widths
    if views: lines.append(f"  let buf = alloc<u8>({LEN * 8});")
    for nm, t in arrs:
        if views: lines.append(f"  let {nm} = view<{t}>(buf);")
        else: lines.append(f"  let {nm} = alloc<{t}>({LEN});")
        if t == "f64": lines.append(f"  let mut j = 0; while j < {LEN} {{ {nm}[j] = ((j * 37 + 11) % 23) as f64 * 0.75 - 4.0; j += 1; }}")
        elif t == "i64": lines.append(f"  let mut j = 0; while j < {LEN} {{ {nm}[j] = j * 1000003 - 99991 * (j % 7); j += 1; }}")
        else: lines.append(f"  let mut j = 0; while j < {LEN} {{ {nm}[j] = ((j * 1103515245 + 12345 + j * j * 97) % 1000003) as {t}; j += 1; }}")
        lines[-1] = lines[-1].replace("let mut j", "let mut j" if nm == "a0" else "j").replace("j = 0; while", "j = 0; while", 1)
    if fn_mode:
        alias = r.random() < 0.6 and not mixed   # mixed: the views alias by construction
        args = [r.choice(names) if alias else nm for nm in names]
        lines.append(f"  let res = kern({', '.join(args)}, n, k1, k2, kf, {r.choice([1, 8])});")
        lines.append("  print(res);")
    else:
        lines.append("  let mut k3 = 0; let mut mx = 0 - 5; let mut mn = 5;")
        for s, op in reds: lines.append(f"  let mut {s}: i64 = {'-1' if op == '&' else '7'};")
        lines.append(f"  let mut i = {s0};")
        lines.append(f"  while i < {nexpr} {{")
        lines += ["    " + x for x in g.body(arrs, stored, reds)]
        lines.append("    i += 1;\n  }")
        lines.append("  print(k3); print(mx); print(mn);")
        for s, _ in reds: lines.append(f"  print({s});")
    for nm, t in arrs:
        conv = f"bits({nm}[j]) as i64" if t == "f64" else (f"{nm}[j] as i64" if t == "u64" else f"{nm}[j]")
        lines.append(f"  let mut h_{nm} = 0; j = 0; while j < {LEN} {{ h_{nm} = h_{nm} * 31 + {conv}; j += 1; }} print(h_{nm});")
    lines.append("}")
    return "\n".join(lines) + "\n"

def run(exe):
    try:
        p = subprocess.run([exe], capture_output=True, timeout=10)
        return p.returncode, p.stdout
    except subprocess.TimeoutExpired:
        return "timeout", b""

def main():
    cases = int(sys.argv[1]) if len(sys.argv) > 1 else 200
    seed = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    r = random.Random(seed)
    d = tempfile.mkdtemp()
    vec = 0; traps = 0; skipped = 0; byt = 0
    try:
        for c in range(cases):
            src = text_program(r) if r.random() < 0.3 else program(r, r.random() < 0.4)
            f = os.path.join(d, "p.ck"); open(f, "w").write(src)
            res = []
            for flag in ([], ["--scalar"]):
                exe = os.path.join(d, "v" if not flag else "s")
                p = subprocess.run([SKITE, f, exe] + flag, capture_output=True, text=True, timeout=CT)
                if p.returncode != 0:
                    if "error" in p.stdout + p.stderr and not flag:
                        res = None; break   # generator produced an ill-typed program: skip it
                    print("COMPILE FAIL", flag, p.stdout, p.stderr); print(src); sys.exit(1)
                if not flag:
                    if "(0 element-wise," not in p.stdout: vec += 1
                    if " 0 byte-lane" not in p.stdout: byt += 1
                res.append(run(exe))
            if res is None: skipped += 1; continue
            if res[0] != res[1]:
                keep = os.path.join(os.environ.get("SKITE_ARTIFACT_DIR", tempfile.gettempdir()), f"stream_fail_{seed}_{c}.ck")
                open(keep, "w").write(src)
                print(f"MISMATCH case {c} (seed {seed}): vector {res[0]} scalar {res[1]}; saved {keep}")
                sys.exit(1)
            if res[0][0] != 0: traps += 1
    finally:
        shutil.rmtree(d, ignore_errors=True)
    print(f"PASS {cases - skipped} programs ({vec} with element-wise vector loops, {byt} byte-lane, {traps} trapped, {skipped} ill-typed skipped), seed {seed}")
    if skipped * 4 > cases: print("too many ill-typed programs"); sys.exit(1)

main()
