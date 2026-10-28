#!/usr/bin/env python3
"""Boundary/tail and wrapping-reduction checks for stream-vector plans."""
import os, re, subprocess, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SKITE = os.environ.get("SKITE", os.path.abspath(os.path.join(HERE, "../skite")))
MASK = (1 << 64) - 1
MIN = -(1 << 63)
MAX = (1 << 63) - 1
LENS = list(range(21)) + [31, 32, 33]
OPS = {"+": lambda a,b: a+b, "-":lambda a,b:a-b,
       "&":lambda a,b:a&b, "|":lambda a,b:a|b, "^":lambda a,b:a^b}

def i64(x):
    x &= MASK
    return x if x < (1 << 63) else x - (1 << 64)

VALUES = [i64(j * 9223372036854775783 - 9223372036854775500) for j in range(40)]

def source(op, seed):
    seed_expr = str(seed) if seed >= 0 else ("(0 - 9223372036854775807 - 1)" if seed == MIN else f"(0 - {abs(seed)})")
    init = "\n".join(f"  a[{j}] = {v};" for j,v in enumerate(VALUES))
    return f'''fn main() {{
  let n = argc() - 1;
  let a = alloc<i64>(40);
{init}
  let mut s: i64 = {seed_expr};
  let mut i = 0;
  while i < n {{ s {op}= a[i]; i += 1; }}
  print(s);
}}
'''

def expected(op, seed, n):
    s = seed
    for v in VALUES[:n]:
        s = i64(OPS[op](s, v))
    return f"{s}\n".encode()

def run(args):
    p = subprocess.run(args, capture_output=True, timeout=10)
    if p.returncode:
        raise RuntimeError(f"failed {args}: {p.returncode}\n{p.stdout!r}\n{p.stderr!r}")
    return p.stdout

cases = 0
with tempfile.TemporaryDirectory(prefix="stream-boundaries-") as td:
    for oi, op in enumerate(OPS):
        seed = {"+":MAX, "-":MIN, "&":-1, "|":MIN, "^":MAX}[op]
        src = os.path.join(td, f"op{oi}.ck")
        with open(src, "w") as f:
            f.write(source(op, seed))
        exes=[]
        for suffix, flag in (("vec", []), ("scalar", ["--scalar"])):
            exe=os.path.join(td,f"{suffix}{oi}")
            cp=subprocess.run([SKITE,src,exe,*flag],capture_output=True,text=True,timeout=20)
            if cp.returncode:
                raise RuntimeError(f"compile failed {op} {flag}:\n{cp.stdout}\n{cp.stderr}")
            if suffix == "vec":
                m = re.search(r"(\d+) loops vectorized \((\d+) element-wise", cp.stdout)
                if not m or int(m.group(2)) < 1:
                    raise AssertionError(f"reduction loop did not emit an element-wise plan for {op}: {cp.stdout}")
            exes.append(exe)
        for n in LENS:
            # argc includes the executable; n dummy args select a runtime loop bound of n.
            argv=["x"]*n
            want=expected(op,seed,n)
            got=[run([exe,*argv]) for exe in exes]
            if got != [want,want]:
                raise AssertionError(f"op={op} n={n} want={want!r} got={got!r}")
            cases += 1
print(f"PASS {cases} length/operator cases (0..20, 31..33), normal and --scalar match Python i64 oracle")
print("Each reduction loop emitted >=1 element-wise plan. Native AVX-512 execution depends on host CPU support.")
