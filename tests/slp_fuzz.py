#!/usr/bin/env python3
"""SSE2 store pairs must not change results: random adjacent f64 store sequences (struct fields
and a[k], a[k + 1]) with dependences, negation, sqrt and division, compiled normally (pairs on)
and with --scalar (pairs off). Outputs are bit patterns and must be identical.
usage: tests/slp_fuzz.py [N] [SEED]"""
import os, random, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKITE = os.environ.get("SKITE", os.path.join(ROOT, "skite"))
F = ["x", "y", "z", "w"]

def leaf(r, lane, idx):
    k = r.randrange(6)
    if k == 0: return f"{r.choice(['0.5', '-1.25', '3.0', '1e300', '-0.0'])}"
    if k == 1: return r.choice(["s", "t"])
    if k == 2: return f"a[{idx}].{F[(r.randrange(4) + lane) % 4]}"
    if k == 3: return f"a[{r.choice(['j', 'i', '(i + 1)'])}].{r.choice(F)}"
    if k == 4: return f"g[{r.choice(['k', '(k + 1)', '(k + 2)'])}]"
    return f"a[{idx}].{F[lane]}"

def tree(r, d, lane, idx, shape):
    op = shape[0]
    if op == "l": return leaf(r, lane, idx)
    if op == "n": return f"(-{tree(r, d + 1, lane, idx, shape[1])})"
    if op == "q": return f"sqrt({tree(r, d + 1, lane, idx, shape[1])})"
    return f"({tree(r, d + 1, lane, idx, shape[1])} {op} {tree(r, d + 1, lane, idx, shape[2])})"

def shape(r, d):
    if d > 3 or r.random() < 0.3: return ("l",)
    c = r.choice("+-*/nq")
    if c in "nq": return (c, shape(r, d + 1))
    return (c, shape(r, d + 1), shape(r, d + 1))

def program(r):
    lines = []
    for _ in range(r.randrange(3, 9)):
        if r.random() < 0.7:
            f0 = r.randrange(3); idx = r.choice(["i", "j", "(i + 1)"])
            sh = shape(r, 0); rr = random.Random(r.random())
            l0 = tree(rr, 0, 0, idx, sh); rr2 = random.Random(r.random()); l1 = tree(rr2, 0, 1, idx, sh)
            op = r.choice(["=", "-=", "+=", "*="])
            lines.append(f"a[{idx}].{F[f0]} {op} {l0}; a[{idx}].{F[f0 + 1]} {op} {l1};")
        else:
            sh = shape(r, 0); rr = random.Random(r.random())
            lines.append(f"g[k] = {tree(rr, 0, 0, 'i', sh)}; g[k + 1] = {tree(random.Random(r.random()), 0, 1, 'i', sh)};")
    body = "\n    ".join(lines)
    return f"""struct V {{ x: f64, y: f64, z: f64, w: f64 }}
fn step(a: mut [V], g: mut [f64], i: i64, j: i64, k: i64, s: f64, t: f64) {{
    {body}
}}
fn main() {{
  let n = 6 + argc() - 1;
  let a = alloc<V>(n); let g = alloc<f64>(16);
  let mut q = 0;
  while q < n {{ a[q].x = q as f64 + 0.5; a[q].y = 1.0 - q as f64; a[q].z = 0.25 * q as f64; a[q].w = 3.0; q += 1; }}
  q = 0; while q < 16 {{ g[q] = 0.5 * q as f64 - 2.0; q += 1; }}
  let mut r = 0;
  while r < 3 {{ step(a, g, r, r + 2, r * 3, 1.5 + r as f64, -0.75); r += 1; }}
  q = 0;
  while q < n {{ print(bits(a[q].x)); print(bits(a[q].y)); print(bits(a[q].z)); print(bits(a[q].w)); q += 1; }}
  q = 0; while q < 16 {{ print(bits(g[q])); q += 1; }}
}}
"""

def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 100
    seed = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    r = random.Random(seed)
    packed = 0
    with tempfile.TemporaryDirectory(prefix="skite-slp-") as td:
        for c in range(n):
            src = os.path.join(td, "p.ck")
            open(src, "w").write(program(r))
            outs = []
            for flag in ([], ["--scalar"]):
                exe = os.path.join(td, "p" + "".join(flag))
                p = subprocess.run([SKITE, src, exe] + flag, capture_output=True, text=True, timeout=60)
                if p.returncode != 0: sys.exit(f"FAIL: compile case {c} {flag}: {p.stderr}\n{open(src).read()}")
                if not flag and "store pairs packed" in p.stdout:
                    packed += int(p.stdout.split(" store pairs packed")[0].rsplit(" ", 1)[1])
                q = subprocess.run([exe], capture_output=True, timeout=60)
                outs.append((q.returncode, q.stdout))
            if outs[0] != outs[1]:
                keep = os.path.join(os.environ.get("SKITE_ARTIFACT_DIR", tempfile.gettempdir()), f"slp_fail_{seed}_{c}.ck")
                open(keep, "w").write(open(src).read())
                sys.exit(f"FAIL: case {c}: paired and scalar results differ (source kept at {keep})")
    if packed == 0: sys.exit("FAIL: no store pairs were packed (the test exercises nothing)")
    print(f"PASS {n} programs ({packed} store pairs packed), identical bits to --scalar, seed {seed}")

main()
