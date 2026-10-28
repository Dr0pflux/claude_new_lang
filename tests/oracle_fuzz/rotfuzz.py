import random, subprocess, sys, os
NEW=sys.argv[1]; OLD=sys.argv[2]; N=int(sys.argv[3]); seed=int(sys.argv[4])
random.seed(seed); import tempfile
D=tempfile.mkdtemp(prefix='skite-ofz-')
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
def runc(cc, src, out):
    r=subprocess.run([cc, src, out], capture_output=True)
    if r.returncode: return ('CE', r.stderr[:80])
    r=subprocess.run([out], capture_output=True, timeout=10)
    return (r.returncode, r.stdout)
bad=0; ce=0
for t in range(N):
    p=prog(); src=f'{D}/r{seed}.ck'; open(src,'w').write(p)
    a=runc(NEW, src, f'{D}/rn{seed}'); b=runc(OLD, src, f'{D}/ro{seed}')
    if a[0]=='CE': ce+=1
    if a!=b: bad+=1; open(f'{D}/rbad{seed}_{t}.ck','w').write(p); print('MISMATCH', t, f'{D}/rbad{seed}_{t}.ck', a, b)
print('done', N, 'bad', bad, 'ce', ce)
