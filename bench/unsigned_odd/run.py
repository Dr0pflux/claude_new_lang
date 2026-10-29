#!/usr/bin/env python3
"""Matched unsigned-odd diagnostic; compiler orchestration, no interpreted kernel."""
import argparse, hashlib, json, os, pathlib, random, shutil, statistics, subprocess, tempfile, time
ROOT=pathlib.Path(__file__).resolve().parents[2]
def digest(p):return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()
def run(xs):return subprocess.run(list(map(str,xs)),capture_output=True,check=True,timeout=30)
p=argparse.ArgumentParser()
for key in ['before','after','before-source','before-sha','after-sha','output']:p.add_argument('--'+key,required=True)
a=p.parse_args();allowed=sorted(os.sched_getaffinity(0));os.sched_setaffinity(0,{allowed[0]})
cpu=pathlib.Path('/proc/cpuinfo').read_text()
report=dict(before_commit=a.before_sha,after_code_commit=a.after_sha,runs=11,pinned_cpu=allowed[0],allowed_cpus=allowed,
 cpu_model=next(x.split(':',1)[1].strip() for x in cpu.splitlines() if x.startswith('model name')),
 cpu_flags=next(x.split(':',1)[1].strip() for x in cpu.splitlines() if x.startswith('flags')),
 source_sha256=dict(before=digest(a.before_source),after=digest(ROOT/'skite.ck')),
 compiler_sha256=dict(before=digest(a.before),after=digest(a.after)),compilers={},binaries={},outputs=[],orders=[],timings={})
with tempfile.TemporaryDirectory(prefix='skite-unsigned-odd-bench-') as td:
 t=pathlib.Path(td);exes={}
 for name,compiler in [('before',a.before),('after',a.after)]:
  exe=t/name;cp=run([compiler,ROOT/'bench/unsigned_odd/mod29.ck',exe]);exes[name]=exe
  report['binaries'][name]=dict(bytes=exe.stat().st_size,sha256=digest(exe),compiler_report=cp.stdout.decode().strip())
 flags=['-O3','-march=native','-ffp-contract=off'];report['c_flags']=flags
 for name in ['gcc','clang']:
  compiler=shutil.which(name);report['compilers'][name]=run([compiler,'--version']).stdout.decode().splitlines()[0] if compiler else None
  if compiler:
   exe=t/name;run([compiler,*flags,ROOT/'bench/unsigned_odd/mod29.c','-o',exe]);exes[name]=exe
   report['binaries'][name]=dict(bytes=exe.stat().st_size,sha256=digest(exe))
 report['compilers']['rustc']=shutil.which('rustc')
 report['scope']='Diagnostic before/after Skite kernel; available C controls. No universal or Game performance claim.'
 for args in [[],['a'],['a','b','c']]:
  obs={name:run([exe,*args]).stdout for name,exe in exes.items()};assert len(set(obs.values()))==1,obs
  report['outputs'].append(dict(argc=len(args)+1,output=obs['before'].decode()))
 samples={name:[] for name in exes}
 for i in range(11):
  order=list(exes);random.Random(44+i).shuffle(order);report['orders'].append(order)
  for name in order:
   start=time.perf_counter_ns();run([exes[name]]);samples[name].append((time.perf_counter_ns()-start)/1e6)
 for name,xs in samples.items():
  q=statistics.quantiles(xs,n=4,method='inclusive');report['timings'][name]=dict(median_ms=statistics.median(xs),q1_ms=q[0],q3_ms=q[2],samples_ms=xs)
report['kernel_sha256']={ext:digest(ROOT/('bench/unsigned_odd/mod29.'+ext)) for ext in ['ck','c']}
pathlib.Path(a.output).write_text(json.dumps(report,indent=2)+'\n')
print({k:v['median_ms'] for k,v in report['timings'].items()})
