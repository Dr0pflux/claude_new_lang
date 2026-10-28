#!/usr/bin/env python3
"""Runtime-length access proofs, independent integer oracles and trap controls.

SKITE selects a frozen compiler. Checks both normal and --scalar output;
proof counters are mandatory for positive loops and incomplete for negatives.
"""
import os,pathlib,re,signal,struct,subprocess,tempfile
ROOT=pathlib.Path(__file__).resolve().parents[1]
SKITE=pathlib.Path(os.environ.get('SKITE',ROOT/'skite')).resolve()
MASK=(1<<64)-1
LENGTHS=[0,1,2,3,4,7,15,16,17,31,32,33,64,65,127,128,129,255,256,257]
def i64(x):
 x &= MASK
 return x if x<1<<63 else x-(1<<64)
VALUES=[i64(i*9223372036854775783-9223372036854775500) for i in range(max(LENGTHS))]
CASES=[
 ('zero_start','let mut s=0;for i in 0..len(a) {s+=a[i];}print(s);',lambda a:sum(a)),
 ('predecessor','let mut s=0;for i in 1..len(a) {s+=a[i-1];}print(s);',lambda a:sum(a[:-1])),
 ('both','let mut s=0;for i in 1..len(a) {s+=a[i]+a[i-1];}print(s);',lambda a:sum(a[1:])+sum(a[:-1])),
 ('offset_zero','let mut s=0;for i in 0..len(a) {s+=a[i-0];}print(s);',lambda a:sum(a)),
 ('offset_three','let mut s=0;for i in 3..len(a) {s+=a[i-3];}print(s);',lambda a:sum(a[:max(0,len(a)-3)])),
 ('unsigned_index','let mut s=0;for i in (1 as u64)..(len(a) as u64) {s+=a[i-(1 as u64)];}print(s);',lambda a:sum(a[:-1])),
 ('identity_cast','let mut s=0;for i in 1..len(a) {s+=a[(i-1) as i64];}print(s);',lambda a:sum(a[:-1])),
 ('narrow_identity','let mut s=0;for i in 1..len(a) {if i<128 {s+=a[((i-1) as u8) as i64];}}print(s);',lambda a:sum(a[:min(max(0,len(a)-1),127)])),
]
NEGATIVES=[
 ('negative_index','for i in 0..len(a) {print(a[i-1]);}',lambda n:n>0,lambda a:b''),
 ('past_end','let i=len(a);print(a[i]);',lambda n:True,lambda a:b''),
 ('negative_offset','for i in 1..len(a) {let x=a[i-(-1)];}',lambda n:n>1,lambda a:b''),
 ('lost_fact','let mut i=1;if i<len(a) {i=len(a)+1;print(a[i-1]);}',lambda n:n>1,lambda a:b''),
 ('different_array','let b=alloc<i64>(1);for i in 1..len(a) {let x=b[i-1];}',lambda n:n>2,lambda a:b''),
 ('large_positive_offset','for i in 1..len(a) {let x=a[i-9223372036854775807];}',lambda n:n>1,lambda a:b''),
 ('large_unsigned_offset','for i in (1 as u64)..(len(a) as u64) {let x=a[i-(9223372036854775808 as u64)];}',lambda n:n>1,lambda a:b''),
 ('offset_before_start','for i in 2..len(a) {let x=a[i-3];}',lambda n:n>2,lambda a:b''),
 ('min_offset','for i in 1..len(a) {let x=a[i-(-9223372036854775807-1)];}',lambda n:n>1,lambda a:b''),
 ('max_unsigned_offset','for i in (1 as u64)..(len(a) as u64) {let x=a[i-(18446744073709551615 as u64)];}',lambda n:n>1,lambda a:b''),
 ('runtime_offset','let k=argc()-1;for i in 1..len(a) {let x=a[i-k];}',lambda n:False,lambda a:b''),
 ('same_memory_shorter_view','for i in 1..len(raw) {let x=a[i-1];}',lambda n:n>0,lambda a:b''),
 ('cast_changes_value','for i in 1..len(a) {let x=a[(i as i8) as i64];}',lambda n:n>128,lambda a:b''),
]
# Loads in let bindings may be DCE'd after proving a successful earlier check;
# the first invalid load must still trap. No output in these negative loops.
checks=0
with tempfile.TemporaryDirectory(prefix='skite-length-facts-') as td:
 t=pathlib.Path(td)
 for name,body,oracle in CASES:
  src=t/(name+'.ck');src.write_text('fn main(){let raw=file(1);let a=view<i64>(raw);'+body+'}\n')
  for flag in [[],['--scalar']]:
   exe=t/(name+('scalar' if flag else 'normal'))
   cp=subprocess.run([str(SKITE),str(src),str(exe),*flag],capture_output=True,text=True,timeout=30)
   assert cp.returncode==0,(name,cp.stderr)
   m=re.search(r'(\d+)/(\d+) bounds checks elided',cp.stdout)
   assert m and int(m[2])>0 and m[1]==m[2],(name,flag,cp.stdout)
   for n in LENGTHS:
    data=t/'data.bin';data.write_bytes(b''.join(struct.pack('<q',v) for v in VALUES[:n]))
    run=subprocess.run([str(exe),str(data)],capture_output=True,timeout=5)
    want=f'{i64(oracle(VALUES[:n]))}\n'.encode()
    assert run.returncode==0 and run.stdout==want,(name,flag,n,run.returncode,run.stdout,want)
    checks+=1
 for name,body,traps,oracle in NEGATIVES:
  src=t/(name+'.ck');src.write_text('fn main(){let raw=file(1);let a=view<i64>(raw);'+body+'}\n')
  for flag in [[],['--scalar']]:
   exe=t/(name+('scalar' if flag else 'normal'))
   cp=subprocess.run([str(SKITE),str(src),str(exe),*flag],capture_output=True,text=True,timeout=30)
   assert cp.returncode==0,(name,cp.stderr)
   m=re.search(r'(\d+)/(\d+) bounds checks elided',cp.stdout)
   assert m and int(m[1])<int(m[2]),(name,'unsafe checks vanished',cp.stdout)
   for n in LENGTHS:
    data=t/'data.bin';data.write_bytes(b''.join(struct.pack('<q',v) for v in VALUES[:n]))
    run=subprocess.run([str(exe),str(data)],capture_output=True,timeout=5)
    if traps(n):assert run.returncode in (-signal.SIGILL,132),(name,flag,n,run.returncode,run.stdout)
    else:assert run.returncode==0 and run.stdout==oracle(VALUES[:n]),(name,flag,n,run.returncode,run.stdout)
    checks+=1
 # A store value's observable output occurs before its invalid index traps.
 src=t/'store_order.ck';src.write_text('fn rhs()->i64 {print(71);return 9;}fn main(){let a=alloc<i64>(argc());let i=argc()-1;if i<len(a){a[i-1]=rhs();}}')
 for flag in [[],['--scalar']]:
  exe=t/('store'+str(len(flag)));cp=subprocess.run([str(SKITE),str(src),str(exe),*flag],capture_output=True,timeout=30)
  assert cp.returncode==0,cp.stderr
  run=subprocess.run([str(exe)],capture_output=True,timeout=5)
  assert run.returncode in (-signal.SIGILL,132) and run.stdout==b'71\n',(flag,run.returncode,run.stdout)
  checks+=1
print(f'PASS {checks} runtime-length output/trap cases; positive accesses fully proven, negative controls retain checks (normal and --scalar)')
