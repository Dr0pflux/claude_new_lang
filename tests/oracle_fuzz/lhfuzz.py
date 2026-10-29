import random, sys, tempfile, os
from harness_common import HarnessFailure, run_pair
def inv(): return random.choice(['k','k + 1','k - 1','k * 2','m','3','k + m'])
def ex(d=0):
    r=random.random()
    if d>2 or r<0.25: return random.choice(['j','s','k','m',str(random.randint(-3,9))])
    if r<0.55: return f'{random.choice(["p","q"])}[{inv()}]'
    if r<0.65: return f'{random.choice(["p","q"])}[j]'
    if r<0.72: return f'({ex(d+1)} / {random.choice(["3","7","m"])})'
    return f'({ex(d+1)} {random.choice(["+","-","*","^"])} {ex(d+1)})'
def stmt():
    r=random.random()
    if r<0.35: return f's = s + {ex()};'
    if r<0.65: return f'{random.choice(["q","p2"])}[j] = {ex()};'
    if r<0.8: return f'if {ex()} < {ex()} {{ s += {ex()}; }}'
    if r<0.85: return f'if {ex()} > 5 && {ex()} < 2 {{ s += 1; }}'
    if r<0.9: return f'print(s);'
    return f'let t = {ex()}; s = s ^ t;'
def prog():
    body=' '.join(stmt() for _ in range(random.randint(1,4)))
    calls=[]
    for _ in range(5):
        x=random.choice(['a','b']); y=random.choice(['a','b']); z=random.choice(['a','b'])
        calls.append(f'  print(f({x}, {y}, {z}, {random.randint(-2,12)}, {random.randint(0,3)} + argc() - 1, {random.randint(0,12)} + argc() - 1));')
    return f'''fn f(p: [i64], q: mut [i64], p2: mut [i64], k: i64, m: i64, n: i64) -> i64 {{
  let mut s = 0;
  let mut j = 0; while j < n {{ {body} j += 1; }} j = 0;
  let mut r = 0; while r < 2 {{ j = 0; while j < n {{ {body} j += 1; }} r += 1; }}
  return s;
}}
fn main() {{
  let a = alloc<i64>(12); let b = alloc<i64>(12);
  let mut iw1 = 0; while iw1 < 12 {{ a[iw1] = iw1 * 3 - 5; b[iw1] = 20 - iw1 * iw1;  iw1 += 1; }}
{chr(10).join(calls)}
  let mut h = 0; let mut iw2 = 0; while iw2 < 12 {{ h = h * 31 + a[iw2] + 7 * b[iw2];  iw2 += 1; }} print(h);
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
