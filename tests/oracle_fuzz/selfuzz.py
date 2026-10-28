import random, subprocess, sys, os
NEW=sys.argv[1]; OLD=sys.argv[2]; N=int(sys.argv[3]); seed=int(sys.argv[4])
random.seed(seed)
import tempfile
D=tempfile.mkdtemp(prefix='skite-ofz-')
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
def runc(cc, src, out):
    r=subprocess.run([cc, src, out], capture_output=True)
    if r.returncode: return 'CE'+r.stderr.decode()[:200]
    r=subprocess.run([out], capture_output=True, timeout=10)
    return (r.returncode, r.stdout)
bad=0; chg=0
for t in range(N):
    p=prog(); src=f'{D}/t{seed}.ck'; open(src,'w').write(p)
    a=runc(NEW, src, f'{D}/n{seed}'); b=runc(OLD, src, f'{D}/o{seed}')
    chg += open(f'{D}/n{seed}','rb').read()!=open(f'{D}/o{seed}','rb').read()
    if a!=b:
        bad+=1; open(f'{D}/bad{seed}_{t}.ck','w').write(p); print('MISMATCH', t, f'{D}/bad{seed}_{t}.ck', a, b)
print('done', N, 'bad', bad, 'changed', chg)
