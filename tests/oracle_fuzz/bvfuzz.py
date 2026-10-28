import random, subprocess, sys, os
NEW=sys.argv[1]; OLD=sys.argv[2]; N=int(sys.argv[3]); seed=int(sys.argv[4])
random.seed(seed); import tempfile
D=tempfile.mkdtemp(prefix='skite-ofz-')
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
def runc(cc, src, out):
    r=subprocess.run([cc, src, out], capture_output=True)
    if r.returncode: return ('CE', r.returncode)
    r=subprocess.run([out], capture_output=True, timeout=10)
    return (r.returncode, r.stdout)
bad=0; chg=0; ce=0
for t in range(N):
    p=prog(); src=f'{D}/b{seed}.ck'; open(src,'w').write(p)
    a=runc(NEW, src, f'{D}/bn{seed}'); b=runc(OLD, src, f'{D}/bo{seed}')
    if a[0]=='CE': ce+=1
    else: chg += open(f'{D}/bn{seed}','rb').read()!=open(f'{D}/bo{seed}','rb').read()
    if a!=b: bad+=1; open(f'{D}/bbad{seed}_{t}.ck','w').write(p); print('MISMATCH', t, f'{D}/bbad{seed}_{t}.ck', a[0], b[0])
print('done', N, 'bad', bad, 'changed', chg, 'ce', ce)
