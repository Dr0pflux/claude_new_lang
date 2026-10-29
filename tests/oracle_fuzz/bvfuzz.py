import random, sys, tempfile, os
from harness_common import HarnessFailure, run_pair
def idx():
    k=random.choice([0,0,1,2,-1,-2,3,5])
    base='i' if k==0 else (f'i + {k}' if k>0 else f'i - {-k}')
    r=random.random()
    if r<0.2: return f'{base} + m'
    if r<0.3: return f'm + {base}'
    if r<0.4: return f'({base} + lo) - 2'
    if r<0.45: return f'{base} - m'
    if r<0.5: return f'{base} + m + lo'
    return base
def stmt():
    a=random.choice(['a','b','c']); r=random.random()
    if r<0.3: return f's = s + {a}[{idx()}];'
    if r<0.55: return f'{random.choice(["b","c"])}[{idx()}] = s + {a}[{idx()}];'
    if r<0.65: return f'if {a}[{idx()}] > 3 {{ s += 1; }} else {{ c[{idx()}] = s; }}'
    if r<0.72: return f'if s > 100 {{ break; }}'
    if r<0.78: return f'print(s);'
    if r<0.85: return f'let mut q = 0; while q < 2 {{ s += {a}[{idx()}]; q += 1; }}'
    return f's = s * 3 + {a}[{idx()}] % 5;'
def prog():
    body=' '.join(stmt() for _ in range(random.randint(1,4)))
    op=random.choice(['<','<='])
    lo=random.choice(['0','1','2','3','lo'])
    E=random.choice(['n','n - 1','n - 2','len(a)','len(b)','len(a) - 3','m','n + 1'])
    calls=' '.join(f'print(f(a, b, c, {random.randint(-1,14)} + argc() - 1, {random.randint(-6,16)} + argc() - 1, {random.randint(-2,5)}));' for _ in range(4))
    return f'''fn f(a: [i64], b: mut [i64], c: mut [i64], n: i64, m: i64, lo: i64) -> i64 {{
  let mut s = 0;
  let mut i = {lo};
  while i {op} {E} {{ {body} i += 1; }}
  return s;
}}
fn main() {{
  let a = alloc<i64>(12); let b = alloc<i64>(10 + argc()); let c = alloc<i64>(14);
  let mut kw1 = 0; while kw1 < 12 {{ a[kw1] = kw1 * 3 - 5;  kw1 += 1; }}
  {calls}
  let mut h = 0; let mut kw2 = 0; while kw2 < len(b) {{ h = h * 31 + b[kw2];  kw2 += 1; }} let mut kw3 = 0; while kw3 < 14 {{ h = h * 7 + c[kw3];  kw3 += 1; }} print(h);
}}
'''
def main():
    if len(sys.argv) != 5:
        print(f"usage: {os.path.basename(sys.argv[0])} NEW_COMPILER OLD_COMPILER N SEED", file=sys.stderr)
        return 2
    new_compiler, old_compiler = sys.argv[1:3]
    try:
        count = int(sys.argv[3]); seed = int(sys.argv[4])
    except ValueError:
        print("N and seed must be integers", file=sys.stderr)
        return 2
    if count < 0:
        print("N must be nonnegative", file=sys.stderr)
        return 2
    random.seed(seed)
    directory = tempfile.mkdtemp(prefix="skite-ofz-")
    bad = changed = 0
    for t in range(count):
        program = prog()
        source = os.path.join(directory, f"case_{seed}_{t}.ck")
        new_output = os.path.join(directory, f"new_{seed}_{t}")
        old_output = os.path.join(directory, f"old_{seed}_{t}")
        with open(source, "w") as f:
            f.write(program)
        try:
            new_result, old_result, binary_changed = run_pair(
                new_compiler, old_compiler, source, new_output, old_output)
        except HarnessFailure as exc:
            print(f"ERROR case={t}: {exc}; source={source}; artifacts={directory}", file=sys.stderr)
            return 2
        changed += binary_changed
        if new_result != old_result:
            bad += 1
            print(f"MISMATCH case={t} new={new_result[0]} old={old_result[0]} source={source}", file=sys.stderr)
    print(f"done {count} bad {bad} changed {changed} artifacts {directory}")
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
