#!/usr/bin/env python3
"""Unsigned even-divisor lowering against arbitrary-precision integer oracles."""
import os, pathlib, random, struct, subprocess, tempfile
ROOT=pathlib.Path(__file__).resolve().parents[1]
SKITE=pathlib.Path(os.environ.get('SKITE',ROOT/'skite')).resolve()
MASK=(1<<64)-1
rng=random.Random(45)
DIVISORS=sorted(set([1,2,3,6,10,14,26,28,29,30,58,102,256,(1<<32)-2,(1<<32)+2,
 (1<<63)-2,1<<63,(1<<63)+2,MASK-1,MASK]+[rng.getrandbits(64)&~1 for _ in range(64)]))
def run(xs):return subprocess.run(list(map(str,xs)),capture_output=True,check=True,timeout=30)
checks=0
with tempfile.TemporaryDirectory(prefix='skite-unsigned-even-') as td:
 t=pathlib.Path(td)
 for d in DIVISORS:
  values={0,1,2,3,(1<<31)-1,1<<31,(1<<32)-1,1<<32,(1<<63)-1,1<<63,MASK}
  for q in [1,2,3,17,65537,MASK//d]:
   n=q*d
   for k in [-1,0,1]:
    if 0<=n+k<=MASK:values.add(n+k)
  values.update(rng.getrandbits(64) for _ in range(16));values=sorted(values)
  (t/'data').write_bytes(b''.join(struct.pack('<Q',x) for x in values))
  src=t/'case.ck';src.write_text('fn main(){let raw=file(1);let a=view<u64>(raw);for i in 0..len(a){let x=a[i];print(x/(%d as u64));print(x%%(%d as u64));let mut q=x;q/=(%d as u64);let mut r=x;r%%=(%d as u64);print((q^r)+x);print((x%%(%d as u64))^((x/(%d as u64))+3));}}' % (d,d,d,d,d,d))
  expected=[]
  for x in values:
   q,r=divmod(x,d);expected.extend([q,r,((q^r)+x)&MASK,r^((q+3)&MASK)])
  want=''.join(f'{x}\n' for x in expected).encode()
  for flags in [[],['--scalar']]:
   run([SKITE,src,t/'case',*flags]);assert run([t/'case',t/'data']).stdout==want,(d,flags)
   checks+=len(expected)
 # Calls on the dividend must retain evaluation order and count.
 src=t/'effects.ck';src.write_text('let mut hits=0;fn value()->u64 {hits+=1;return 18446744073709551615;}fn main(){print(value()/(26 as u64));print(value()%(26 as u64));print(hits);}')
 for flags in [[],['--scalar']]:
  run([SKITE,src,t/'effects',*flags]);q,r=divmod(MASK,26)
  assert run([t/'effects']).stdout==f'{q}\n{r}\n2\n'.encode();checks+=3
print(f'PASS {checks} unsigned quotient/remainder outputs over {len(DIVISORS)} divisors, normal/scalar')
