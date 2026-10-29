import random, sys, tempfile, os
from harness_common import HarnessFailure, run_pair
def cmpop(): return random.choice(['<','<=','>','>=','==','!='])
def idx(v): return random.choice([v, v, f'{v} + 1', f'{v} % 7', 'o', f'{v} * 2', f'{v} - 1'])
def val(arrs, vs):
    r=random.random()
    if r<0.4: return f'{random.choice(arrs)}[{idx(random.choice(vs))}]'
    if r<0.6: return random.choice(vs)
    if r<0.8: return f'{random.choice(vs)} + {random.randint(-3,3)}'
    return str(random.randint(-5,5))
def branch(arrs, vs, st, x):
    s=''
    if st: s+=f'{st}[o] = {x}; '
    for _ in range(random.randint(0,3)):
        v=random.choice(['i','j','m','p'])
        r=random.random()
        if r<0.5: s+=f'{v} += 1; '
        elif r<0.6: s+=f'{v} -= 1; '
        elif r<0.8: s+=f'{v} = {random.choice(["i","j","m","p","q"])}; '
        else: s+=f'{v} = {random.choice(["i","j","m","p"])} + {random.randint(-2,2)}; '
    return s
def prog():
    arrs=['a','b']
    vs=['i','j','m','p','q']
    body=''
    for _ in range(random.randint(1,3)):
        st=random.choice(['c','c','d',None])
        x=f'{random.choice(arrs)}[{idx(random.choice(vs))}]'; y=f'{random.choice(arrs)}[{idx(random.choice(vs))}]'
        if random.random()<0.3: x=val(arrs,vs)
        if random.random()<0.3: y=val(arrs,vs)
        cond=f'{x} {cmpop()} {y}' if random.random()<0.7 else f'{val(arrs,vs)} {cmpop()} {val(arrs,vs)}'
        st2 = st if random.random()<0.85 else random.choice(['c','d'])
        x2 = x if random.random()<0.5 else val(arrs,vs); y2 = y if random.random()<0.5 else val(arrs,vs)
        els = ' else { '+branch(arrs,vs,st2,y2)+'}' if random.random()<0.9 else ''
        body+=f'    if {cond} {{ {branch(arrs,vs,st,x2)}}}{els}\n'
    n=random.randint(5,40)
    return f'''fn run(a: [i64], b: [i64], c: mut [i64], d: mut [i64], n: i64) -> i64 {{
  let mut i = 0; let mut j = 0; let mut m = 1; let mut p = 2; let q = 3; let mut o = 0;
  while o < n && i < n && j < n && m < n && p < n && i >= 0 && j >= 0 && m >= 0 && p >= 0 {{
{body}    o += 1;
  }}
  let mut h = i * 7 + j * 11 + m * 13 + p * 17 + o;
  let mut kw1 = 0; while kw1 < len(c) {{ h = h * 31 + c[kw1] + 3 * d[kw1];  kw1 += 1; }}
  return h;
}}
fn main() {{
  let n = {n};
  let a = alloc<i64>(n + 8); let b = alloc<i64>(n + 8); let c = alloc<i64>(n + 8); let d = alloc<i64>(n + 8);
  let mut x: u64 = {random.randint(1,10**9)};
  let mut kw2 = 0; while kw2 < n + 8 {{ x = x * 6364136223846793005 + 1442695040888963407; a[kw2] = ((x >> 40) % 9) as i64 - 4; x = x * 6364136223846793005 + 1; b[kw2] = ((x >> 40) % 9) as i64 - 4;  kw2 += 1; }}
  print(run(a, b, c, d, n));
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
