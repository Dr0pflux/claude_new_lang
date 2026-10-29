import random, sys, tempfile, os
from harness_common import HarnessFailure, run_pair
TY=['u64','i64','u64','i64']
def term(v):
    c=random.randint(1,63); c2=64-c if random.random()<0.7 else random.randint(1,63)
    op=random.choice(['|','^','+'])
    x=random.choice([v,f'({v} + 3)',f'({v} ^ q)'])
    l=f'({x} << {c})'; r=f'({x} >> {c2})'
    return f'({l} {op} {r})' if random.random()<0.5 else f'({r} {op} {l})'
def prog():
    ty=random.choice(TY)
    lines=[]
    for k in range(random.randint(2,6)):
        v=random.choice(['a','b'])
        r=random.random()
        if r<0.4: lines.append(f'{v} = {term(v)};')
        elif r<0.7: lines.append(f'{v} = {v} ^ ({v} << {random.randint(1,40)});')
        elif r<0.85: lines.append(f'{v} = {v} - ({v} >> {random.randint(1,40)}) * q;')
        else: lines.append(f'q = q + {v};')
    body=' '.join(lines)
    return f'''fn main() {{
  let mut a: {ty} = ({random.randint(1,2**31)} + argc()) as {ty}; let mut b: {ty} = ({random.randint(1,2**31)} * 7 + argc()) as {ty}; let mut q: {ty} = 3 as {ty};
  let mut i = 0; while i < {random.randint(1,50)} {{ {body} i += 1; }}
  print(a); print(b); print(q);
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
