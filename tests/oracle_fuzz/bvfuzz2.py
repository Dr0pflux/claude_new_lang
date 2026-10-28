import random, subprocess, sys, os
NEW=sys.argv[1]; OLD=sys.argv[2]; N=int(sys.argv[3]); seed=int(sys.argv[4])
random.seed(seed); import tempfile
D=tempfile.mkdtemp(prefix='skite-ofz-')
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
def runc(cc, src, out):
    r=subprocess.run([cc, src, out], capture_output=True)
    if r.returncode: return ('CE', r.returncode)
    try: r=subprocess.run([out], capture_output=True, timeout=10)
    except subprocess.TimeoutExpired: return ('TO',)
    return (r.returncode, r.stdout)
bad=0; chg=0; ce=0
for t in range(N):
    p=prog(); src=f'{D}/m{seed}.ck'; open(src,'w').write(p)
    a=runc(NEW, src, f'{D}/mn{seed}'); b=runc(OLD, src, f'{D}/mo{seed}')
    if a[0]=='CE': ce+=1
    else: chg += open(f'{D}/mn{seed}','rb').read()!=open(f'{D}/mo{seed}','rb').read()
    if a!=b: bad+=1; open(f'{D}/mbad{seed}_{t}.ck','w').write(p); print('MISMATCH', t, f'{D}/mbad{seed}_{t}.ck', a[0], b[0])
print('done', N, 'bad', bad, 'changed', chg, 'ce', ce)
