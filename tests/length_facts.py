#!/usr/bin/env python3
"""Runtime-length access proofs, independent integer oracles and trap controls.

SKITE selects a frozen compiler. Checks both normal and --scalar output;
proof counters are mandatory for positive loops and incomplete for negatives.
"""
import os,pathlib,re,resource,shutil,signal,struct,subprocess,tempfile
ROOT=pathlib.Path(__file__).resolve().parents[1]
SKITE=pathlib.Path(os.environ.get('SKITE',ROOT/'skite')).resolve()
MASK=(1<<64)-1
LENGTHS=[0,1,2,3,4,7,15,16,17,31,32,33,64,65,127,128,129,255,256,257]
def i64(x):
 x &= MASK
 return x if x<1<<63 else x-(1<<64)
VALUES=[i64(i*9223372036854775783-9223372036854775500) for i in range(max(LENGTHS))]

def disable_core_dumps():
 resource.setrlimit(resource.RLIMIT_CORE,(0,0))

def preserve_failure(label,cmd,src,data,exe,stdout=b'',stderr=b'',detail=''):
 root=pathlib.Path(os.environ.get('SKITE_ARTIFACT_DIR',pathlib.Path(tempfile.gettempdir())/'skite-length-facts-artifacts'))
 dest=root/label.replace('/','_')
 dest.mkdir(parents=True,exist_ok=True)
 for path in (src,data,exe):
  if path is not None and pathlib.Path(path).is_file(): shutil.copy2(path,dest/pathlib.Path(path).name)
 (dest/'failure.txt').write_text(
  f'command: {cmd!r}\nsource: {src}\ninput: {data}\nexecutable: {exe}\n{detail}\n'
  f'stdout:\n{stdout.decode(errors="replace") if isinstance(stdout,bytes) else stdout}\n'
  f'stderr:\n{stderr.decode(errors="replace") if isinstance(stderr,bytes) else stderr}\n')
 return dest

def process_snapshot(pid):
 chunks=[]
 for name in ('status','wchan','stat','limits','coredump_filter'):
  path=pathlib.Path(f'/proc/{pid}/{name}')
  try: value=path.read_text()
  except OSError as e: value=f'<unavailable: {e}>'
  chunks.append(f'--- /proc/{pid}/{name} ---\n{value}')
 for name in ('core_pattern','core_pipe_limit'):
  path=pathlib.Path('/proc/sys/kernel')/name
  try: value=path.read_text()
  except OSError as e: value=f'<unavailable: {e}>'
  chunks.append(f'--- /proc/sys/kernel/{name} ---\n{value}')
 return '\n'.join(chunks)

def run(cmd,timeout,label,src,data=None,exe=None,text=False):
 proc=None
 try:
  proc=subprocess.Popen(cmd,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=text,
                        start_new_session=True,preexec_fn=disable_core_dumps)
  stdout,stderr=proc.communicate(timeout=timeout)
  return subprocess.CompletedProcess(cmd,proc.returncode,stdout,stderr)
 except subprocess.TimeoutExpired as e:
  snapshot=process_snapshot(proc.pid) if proc is not None else '<process was not started>'
  if proc is not None:
   try: os.killpg(proc.pid,signal.SIGKILL)
   except ProcessLookupError: pass
   stdout,stderr=proc.communicate()
  else: stdout,stderr=e.stdout or b'',e.stderr or b''
  detail=f'timed out after {timeout}s; process state before kill:\n{snapshot}'
  dest=preserve_failure(label,cmd,src,data,exe,stdout or e.stdout or b'',stderr or e.stderr or b'',detail)
  raise AssertionError(f'{label}: subprocess timed out after {timeout}s; artifacts={dest}') from e

def require(ok,label,cmd,src,data=None,exe=None,stdout=b'',stderr=b'',detail=''):
 if not ok:
  dest=preserve_failure(label,cmd,src,data,exe,stdout,stderr,detail)
  raise AssertionError(f'{label}: {detail}; artifacts={dest}')
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
 data=t/'data.bin'
 for name,body,oracle in CASES:
  src=t/(name+'.ck');src.write_text('fn main(){let raw=file(1);let a=view<i64>(raw);'+body+'}\n')
  for flag in [[],['--scalar']]:
   mode='scalar' if flag else 'normal'
   exe=t/(name+mode)
   cmd=[str(SKITE),str(src),str(exe),*flag]
   cp=run(cmd,30,f'{name}-{mode}-compile',src,data,exe,text=True)
   require(cp.returncode==0,f'{name}-{mode}-compile',cmd,src,data,exe,cp.stdout,cp.stderr,f'compiler returned {cp.returncode}')
   m=re.search(r'(\d+)/(\d+) bounds checks elided',cp.stdout)
   require(bool(m and int(m[2])>0 and m[1]==m[2]),f'{name}-{mode}-proof',cmd,src,data,exe,cp.stdout,cp.stderr,'positive-loop proof counter missing or incomplete')
   for n in LENGTHS:
    data.write_bytes(b''.join(struct.pack('<q',v) for v in VALUES[:n]))
    cmd=[str(exe),str(data)]
    run_result=run(cmd,5,f'{name}-{mode}-n{n}',src,data,exe)
    want=f'{i64(oracle(VALUES[:n]))}\n'.encode()
    require(run_result.returncode==0 and run_result.stdout==want,f'{name}-{mode}-n{n}',cmd,src,data,exe,run_result.stdout,run_result.stderr,f'got status {run_result.returncode}, expected output {want!r}')
    checks+=1
 for name,body,traps,oracle in NEGATIVES:
  src=t/(name+'.ck');src.write_text('fn main(){let raw=file(1);let a=view<i64>(raw);'+body+'}\n')
  for flag in [[],['--scalar']]:
   mode='scalar' if flag else 'normal'
   exe=t/(name+mode)
   cmd=[str(SKITE),str(src),str(exe),*flag]
   cp=run(cmd,30,f'{name}-{mode}-compile',src,data,exe,text=True)
   require(cp.returncode==0,f'{name}-{mode}-compile',cmd,src,data,exe,cp.stdout,cp.stderr,f'compiler returned {cp.returncode}')
   m=re.search(r'(\d+)/(\d+) bounds checks elided',cp.stdout)
   require(bool(m and int(m[1])<int(m[2])),f'{name}-{mode}-proof',cmd,src,data,exe,cp.stdout,cp.stderr,'unsafe checks were fully elided')
   for n in LENGTHS:
    data.write_bytes(b''.join(struct.pack('<q',v) for v in VALUES[:n]))
    cmd=[str(exe),str(data)]
    run_result=run(cmd,5,f'{name}-{mode}-n{n}',src,data,exe)
    if traps(n):
     ok=run_result.returncode in (-signal.SIGILL,132)
     detail=f'expected SIGILL, got status {run_result.returncode}'
    else:
     want=oracle(VALUES[:n])
     ok=run_result.returncode==0 and run_result.stdout==want
     detail=f'got status {run_result.returncode} and output {run_result.stdout!r}, expected 0 and {want!r}'
    require(ok,f'{name}-{mode}-n{n}',cmd,src,data,exe,run_result.stdout,run_result.stderr,detail)
    checks+=1
 # A store value's observable output occurs before its invalid index traps.
 src=t/'store_order.ck';src.write_text('fn rhs()->i64 {print(71);return 9;}fn main(){let a=alloc<i64>(argc());let i=argc()-1;if i<len(a){a[i-1]=rhs();}}')
 for flag in [[],['--scalar']]:
  mode='scalar' if flag else 'normal'
  exe=t/('store'+mode)
  cmd=[str(SKITE),str(src),str(exe),*flag]
  cp=run(cmd,30,f'store-order-{mode}-compile',src,None,exe,text=True)
  require(cp.returncode==0,f'store-order-{mode}-compile',cmd,src,None,exe,cp.stdout,cp.stderr,f'compiler returned {cp.returncode}')
  cmd=[str(exe)]
  run_result=run(cmd,5,f'store-order-{mode}-run',src,None,exe)
  ok=run_result.returncode in (-signal.SIGILL,132) and run_result.stdout==b'71\n'
  require(ok,f'store-order-{mode}-run',cmd,src,None,exe,run_result.stdout,run_result.stderr,f'expected SIGILL after printing 71, got status {run_result.returncode} and {run_result.stdout!r}')
  checks+=1
print(f'PASS {checks} runtime-length output/trap cases; positive accesses fully proven, negative controls retain checks (normal and --scalar)')
