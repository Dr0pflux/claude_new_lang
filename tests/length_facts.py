#!/usr/bin/env python3
"""Runtime-length access proofs, independent integer oracles and trap controls.

SKITE selects a frozen compiler. Checks both normal and --scalar output;
proof counters are mandatory for positive loops and incomplete for negatives.
"""
import ctypes,os,pathlib,re,resource,shutil,signal,struct,subprocess,sys,tempfile,time
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

def trace_child_runtime():
 disable_core_dumps()
 libc=ctypes.CDLL(None,use_errno=True)
 libc.ptrace.argtypes=(ctypes.c_uint,ctypes.c_int,ctypes.c_void_p,ctypes.c_void_p)
 libc.ptrace.restype=ctypes.c_long
 if libc.ptrace(0,0,None,None)==-1: # PTRACE_TRACEME
  err=ctypes.get_errno()
  raise OSError(err,os.strerror(err),'ptrace(PTRACE_TRACEME)')

def ptrace_call(request,pid,data=0):
 libc=ctypes.CDLL(None,use_errno=True)
 libc.ptrace.argtypes=(ctypes.c_uint,ctypes.c_int,ctypes.c_void_p,ctypes.c_void_p)
 libc.ptrace.restype=ctypes.c_long
 if libc.ptrace(request,pid,None,ctypes.c_void_p(data))==-1:
  err=ctypes.get_errno()
  raise OSError(err,os.strerror(err),f'ptrace request {request} for pid {pid}')

def wait_runtime(proc,timeout):
 deadline=time.monotonic()+timeout
 exec_trap_seen=False
 while True:
  if time.monotonic()>=deadline:
   raise subprocess.TimeoutExpired(proc.args,timeout)
  try: pid,status=os.waitpid(proc.pid,os.WNOHANG|os.WUNTRACED)
  except InterruptedError: continue
  if pid:
   if os.WIFEXITED(status): code=os.WEXITSTATUS(status)
   elif os.WIFSIGNALED(status): code=-os.WTERMSIG(status)
   elif os.WIFSTOPPED(status):
    sig=os.WSTOPSIG(status)
    if sig==signal.SIGILL:
     # Consume SIGILL instead of delivering it to the kernel core-dump path.
     try: os.killpg(proc.pid,signal.SIGKILL)
     except ProcessLookupError: pass
     os.waitpid(proc.pid,0)
     code=-signal.SIGILL
    else:
     deliver=0 if sig==signal.SIGTRAP and not exec_trap_seen else sig
     if sig==signal.SIGTRAP: exec_trap_seen=True
     ptrace_call(7,proc.pid,deliver) # PTRACE_CONT
     continue
   else: continue
   proc.returncode=code
   return code
  if time.monotonic()>=deadline:
   raise subprocess.TimeoutExpired(proc.args,timeout)
  time.sleep(0.001)

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

def run(cmd,timeout,label,src,data=None,exe=None,text=False,trace_ill=False):
 proc=None
 def kill_reap():
  if proc is None or proc.returncode is not None: return
  try: os.killpg(proc.pid,signal.SIGKILL)
  except ProcessLookupError: pass
  try: proc.wait()
  except (ChildProcessError,OSError): pass
 with tempfile.TemporaryFile() as out,tempfile.TemporaryFile() as err:
  try:
   setup=trace_child_runtime if trace_ill else disable_core_dumps
   proc=subprocess.Popen(cmd,stdout=out,stderr=err,start_new_session=True,preexec_fn=setup)
   if trace_ill: wait_runtime(proc,timeout)
   else: proc.wait(timeout=timeout)
  except subprocess.TimeoutExpired as e:
   snapshot=process_snapshot(proc.pid) if proc is not None else '<process was not started>'
   if proc is not None:
    try: os.killpg(proc.pid,signal.SIGKILL)
    except ProcessLookupError: pass
    proc.wait()
   out.seek(0);stdout=out.read()
   err.seek(0);stderr=err.read()
   if text:
    stdout=stdout.decode(errors='replace');stderr=stderr.decode(errors='replace')
   detail=f'timed out after {timeout}s; process state before kill:\n{snapshot}'
   dest=preserve_failure(label,cmd,src,data,exe,stdout,stderr,detail)
   raise AssertionError(f'{label}: subprocess timed out after {timeout}s; artifacts={dest}') from e
  except subprocess.SubprocessError as e:
   if trace_ill:
    kill_reap()
    raise RuntimeError(f'{label}: runtime ptrace supervision unavailable; refusing to skip: {e}') from e
   raise
  except BaseException:
   if trace_ill: kill_reap()
   raise
  out.seek(0);stdout=out.read()
  err.seek(0);stderr=err.read()
  if text:
   stdout=stdout.decode(errors='replace');stderr=stderr.decode(errors='replace')
  return subprocess.CompletedProcess(cmd,proc.returncode,stdout,stderr)

def require(ok,label,cmd,src,data=None,exe=None,stdout=b'',stderr=b'',detail=''):
 if not ok:
  dest=preserve_failure(label,cmd,src,data,exe,stdout,stderr,detail)
  raise AssertionError(f'{label}: {detail}; artifacts={dest}')

def supervisor_selftest():
 with tempfile.TemporaryDirectory(prefix='length-facts-ptrace-test-') as td:
  t=pathlib.Path(td);os.environ['SKITE_ARTIFACT_DIR']=str(t/'artifacts')
  src=t/'program.ck';exe=t/'program';pidfile=t/'child.pid'
  src.write_text('selftest input')
  exe.write_text(f'#!{sys.executable}\nimport os,signal\nprint("before-ill",flush=True)\nos.kill(os.getpid(),signal.SIGILL)\n');exe.chmod(0o755)
  result=run([str(exe)],2,'expected-sigill',src,None,exe,trace_ill=True)
  assert result.returncode==-signal.SIGILL and result.stdout==b'before-ill\n',(result.returncode,result.stdout)
  try: require(result.returncode==0,'positive-sigill',[str(exe)],src,None,exe,result.stdout,result.stderr,'positive case unexpectedly trapped')
  except AssertionError as e: assert 'artifacts=' in str(e)
  else: raise AssertionError('positive case did not reject injected SIGILL')

  exe.write_text(f'#!{sys.executable}\nimport os,signal,sys\ncount=0\ndef caught(sig,frame):\n global count\n count+=1\n if count==32:\n  print("caught-fpe-32",flush=True)\n  sys.exit(136)\n os.kill(os.getpid(),signal.SIGFPE)\nsignal.signal(signal.SIGFPE,caught)\nos.kill(os.getpid(),signal.SIGFPE)\n');exe.chmod(0o755)
  result=run([str(exe)],2,'sigfpe-handler',src,None,exe,trace_ill=True)
  assert result.returncode==136 and result.stdout==b'caught-fpe-32\n',(result.returncode,result.stdout)

  exe.write_text(f'#!{sys.executable}\nprint("normal",flush=True)\n');exe.chmod(0o755)
  result=run([str(exe)],2,'normal-exit',src,None,exe,trace_ill=True)
  assert result.returncode==0 and result.stdout==b'normal\n',(result.returncode,result.stdout)

  exe.write_text(f'#!{sys.executable}\nimport os,subprocess,sys,time\np=subprocess.Popen([sys.executable,"-c","import time;time.sleep(30)"])\nopen(os.environ["LENGTH_FACTS_CHILD_PID"],"w").write(str(p.pid))\ntime.sleep(30)\n');exe.chmod(0o755)
  os.environ['LENGTH_FACTS_CHILD_PID']=str(pidfile)
  try: run([str(exe)],0.1,'timeout-cleanup',src,None,exe,trace_ill=True)
  except AssertionError as e: assert 'artifacts=' in str(e)
  else: raise AssertionError('timeout smoke unexpectedly completed')
  child=int(pidfile.read_text())
  for _ in range(50):
   try:
    state=pathlib.Path(f'/proc/{child}/stat').read_text().split(') ',1)[1][0]
   except FileNotFoundError: break
   if state=='Z': break
   time.sleep(0.02)
  else: raise AssertionError(f'timeout descendant {child} survived')
 print('PASS runtime ptrace supervisor smoke (SIGILL, SIGFPE, normal exit, timeout cleanup)')

if os.environ.get('SKITE_LENGTH_FACTS_SUPERVISOR_TEST')=='1':
 supervisor_selftest()
 raise SystemExit(0)

CASES=[
 ('terminal_parameter','print(tail(a));',lambda a:a[-1] if a else 0),
 ('terminal_one','if len(a)>0 {print(a[len(a)-1]);}else {print(0);}',lambda a:a[-1] if a else 0),
 ('terminal_three','if len(a)>=3 {print(a[len(a)-3]);}else {print(0);}',lambda a:a[-3] if len(a)>=3 else 0),
 ('terminal_cast','if len(a)>0 {print(a[(len(a)-1) as i64]);}else {print(0);}',lambda a:a[-1] if a else 0),
 ('terminal_store','if len(a)>0 {a[len(a)-1]=71;print(a[len(a)-1]);}else {print(0);}',lambda a:71 if a else 0),
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
 ('terminal_mutated_copy','let mut n=len(a);if n>0 {n=len(a)+1;print(a[n-1]);}',lambda n:n>0,lambda a:b''),
 ('terminal_huge','if len(a)>0 {print(a[len(a)-9223372036854775807]);}',lambda n:n>0,lambda a:b''),
 ('terminal_unsigned_huge','if len(a)>0 {print(a[(len(a) as u64)-(18446744073709551615 as u64)]);}',lambda n:n>0,lambda a:b''),
 ('terminal_guard_too_small','if len(a)>0 {print(a[len(a)-3]);}',lambda n:0<n<3,lambda a:f'{a[-3]}\n'.encode() if len(a)>=3 else b''),
 ('terminal_empty','print(a[len(a)-1]);',lambda n:n==0,lambda a:f'{a[-1]}\n'.encode()),
 ('terminal_zero','print(a[len(a)-0]);',lambda n:True,lambda a:b''),
 ('terminal_negative','print(a[len(a)-(-1)]);',lambda n:True,lambda a:b''),
 ('terminal_different','let b=alloc<i64>(1);if len(a)>1 {print(b[len(a)-1]);}',lambda n:n>1,lambda a:b''),
 ('terminal_short_view','let b=view<i64>(raw);if len(raw)>0 {print(b[len(raw)-1]);}',lambda n:n>0,lambda a:b''),
 ('terminal_narrow','if len(a)>0 {print(a[((len(a)-1) as i8) as i64]);}',lambda n:n>=129 and n<=256,lambda a:f'{a[((len(a)-1)+128)%256-128]}\n'.encode() if a else b''),
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
  src=t/(name+'.ck');prefix='fn tail(a: [i64])->i64 {if len(a)>0 {return a[len(a)-1];}return 0;}' if name=='terminal_parameter' else ''
  src.write_text(prefix+'fn main(){let raw=file(1);let a=view<i64>(raw);'+body+'}\n')
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
    run_result=run(cmd,5,f'{name}-{mode}-n{n}',src,data,exe,trace_ill=True)
    want=f'{i64(oracle(VALUES[:n]))}\n'.encode()
    require(run_result.returncode==0 and run_result.stdout==want,f'{name}-{mode}-n{n}',cmd,src,data,exe,run_result.stdout,run_result.stderr,f'got status {run_result.returncode}, expected output {want!r}')
    checks+=1
 for name,body,traps,oracle in NEGATIVES:
  src=t/(name+'.ck');prefix='fn tail(a: [i64])->i64 {if len(a)>0 {return a[len(a)-1];}return 0;}' if name=='terminal_parameter' else ''
  src.write_text(prefix+'fn main(){let raw=file(1);let a=view<i64>(raw);'+body+'}\n')
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
    run_result=run(cmd,5,f'{name}-{mode}-n{n}',src,data,exe,trace_ill=True)
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
  run_result=run(cmd,5,f'store-order-{mode}-run',src,None,exe,trace_ill=True)
  ok=run_result.returncode in (-signal.SIGILL,132) and run_result.stdout==b'71\n'
  require(ok,f'store-order-{mode}-run',cmd,src,None,exe,run_result.stdout,run_result.stderr,f'expected SIGILL after printing 71, got status {run_result.returncode} and {run_result.stdout!r}')
  checks+=1
print(f'PASS {checks} runtime-length output/trap cases; positive accesses fully proven, negative controls retain checks (normal and --scalar)')
