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
    def body(self, arrs, stored, reds):
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
        if r.random() < 0.08: out.append("if i == 5 { k3 += 1; }")   # not a stream loop: general path
        return out

def program(r, fn_mode):
    g = Gen(r)
    na = r.randrange(2, 5)
    if fn_mode:
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
        lines.append("  let mut k3 = 0;")
        for s, op in reds: lines.append(f"  let mut {s}: i64 = {'-1' if op == '&' else '7'};")
        lines.append(f"  let mut i = {s0};")
        lines.append(f"  while i < {nexpr} {{")
        lines += ["    " + x for x in g.body(arrs, stored, reds)]
        lines.append("    i += 1;\n  }")
        lines.append(f"  return k3{''.join(' + ' + s for s, _ in reds)};")
        lines.append("}")
    lines.append("fn main() {")
    lines.append(f"  let n = {LEN} - 4 + argc();")   # 45: not a multiple of the vector width
    lines.append("  let k1 = argc() + 2; let k2 = 0 - argc() * 3; let kf = (argc() as f64) * 0.5;")
    views = not fn_mode and r.random() < 0.3   # arrays share one byte buffer through views of different widths
    if views: lines.append(f"  let buf = alloc<u8>({LEN * 8});")
    for nm, t in arrs:
        if views: lines.append(f"  let {nm} = view<{t}>(buf);")
        else: lines.append(f"  let {nm} = alloc<{t}>({LEN});")
        if t == "f64": lines.append(f"  let mut j = 0; while j < {LEN} {{ {nm}[j] = ((j * 37 + 11) % 23) as f64 * 0.75 - 4.0; j += 1; }}")
        elif t == "i64": lines.append(f"  let mut j = 0; while j < {LEN} {{ {nm}[j] = j * 1000003 - 99991 * (j % 7); j += 1; }}")
        else: lines.append(f"  let mut j = 0; while j < {LEN} {{ {nm}[j] = ((j * 1103515245 + 12345 + j * j * 97) % 1000003) as {t}; j += 1; }}")
        lines[-1] = lines[-1].replace("let mut j", "let mut j" if nm == "a0" else "j").replace("j = 0; while", "j = 0; while", 1)
    if fn_mode:
        alias = r.random() < 0.6
        args = [r.choice(names) if alias else nm for nm in names]
        lines.append(f"  let res = kern({', '.join(args)}, n, k1, k2, kf, 1);")
        lines.append("  print(res);")
    else:
        lines.append("  let mut k3 = 0;")
        for s, op in reds: lines.append(f"  let mut {s}: i64 = {'-1' if op == '&' else '7'};")
        lines.append(f"  let mut i = {s0};")
        lines.append(f"  while i < {nexpr} {{")
        lines += ["    " + x for x in g.body(arrs, stored, reds)]
        lines.append("    i += 1;\n  }")
        lines.append("  print(k3);")
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
    vec = 0; traps = 0; skipped = 0
    try:
        for c in range(cases):
            src = program(r, r.random() < 0.4)
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
                    if "(0 element-wise)" not in p.stdout: vec += 1
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
    print(f"PASS {cases - skipped} programs ({vec} with element-wise vector loops, {traps} trapped, {skipped} ill-typed skipped), seed {seed}")
    if skipped * 4 > cases: print("too many ill-typed programs"); sys.exit(1)

main()
