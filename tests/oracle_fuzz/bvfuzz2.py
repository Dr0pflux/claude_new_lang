import random, sys, tempfile, os
from harness_common import HarnessFailure, run_pair
def off(v):
    k=random.choice([0,0,0,1,-1,2,-2])
    return v if k==0 else (f'{v} + {k}' if k>0 else f'{v} - {-k}')
def acc(): return f'{random.choice(["a","b","c"])}[{off(random.choice(["i","j","o"]))}]'
def stmt(depth=0):
    r=random.random()
    if r<0.3: return f's = s * 3 + {acc()};'
    if r<0.5: return f'{random.choice(["b","c"])}[{off(random.choice(["i","j","o"]))}] = s + {acc()};'
    if r<0.62 and depth==0: return f'if {acc()} < {acc()} {{ {stmt(1)} s += 1; }} else {{ {stmt(1)} s -= 1; }}'
    if r<0.7 and depth==0: return f'if s > 1000000 {{ break; }}'
    if r<0.78 and depth==0: return f'if {acc()} > 3 {{ s += 2; }}'
    return f's = s ^ {acc()};'
def prog():
    pre=' '.join(stmt() for _ in range(random.randint(0,2)))
    mid=' '.join(stmt() for _ in range(random.randint(1,2)))
    inc=random.choice(['i += 1; j += 1;','if s % 2 == 0 { i += 1; } else { j += 1; }','if c[o % 3 + 1] > 0 { i += 1; } else { j += 1; }','i += 1;','j += 1;','if s > 5 { i += 1; }'])
    cnt=random.choice(['o += 1;','o += 1;',''])
    cond=random.choice(['i < n && j < m','i < n && j <= m','i <= n && j < m && s < 100000000','j < m && i < n'])
    calls=' '.join(f'print(f(a, b, c, {random.randint(-3,14)} + argc() - 1, {random.randint(-3,14)} + argc() - 1, {random.randint(-2,4)}, {random.randint(-2,4)}, {random.randint(-2,6)}));' for _ in range(4))
    return f'''fn f(a: [i64], b: mut [i64], c: mut [i64], n: i64, m: i64, i0: i64, j0: i64, o0: i64) -> i64 {{
  let mut s = 0; let mut i = i0; let mut j = j0; let mut o = o0;
  while {cond} {{ {pre} {mid} {inc} {cnt} }}
  return s * 7 + i * 3 + j + o;
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
