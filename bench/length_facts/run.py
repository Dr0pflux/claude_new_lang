#!/usr/bin/env python3
"""Reproducible length-fact measurements; no cross-language win without tools.
Compiler/process orchestration only. Every timed loop is native code.
"""
import argparse,hashlib,json,os,pathlib,random,shutil,statistics,subprocess,tempfile,time
ROOT=pathlib.Path(__file__).resolve().parents[2]
def digest(p):return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()
def run(args,**kw):return subprocess.run([str(x) for x in args],check=True,capture_output=True,timeout=30,**kw)
def summary(xs):
 q=statistics.quantiles(xs,n=4,method='inclusive')
 return dict(median_ms=statistics.median(xs),q1_ms=q[0],q3_ms=q[2],min_ms=min(xs),max_ms=max(xs),samples_ms=xs)
def main():
 p=argparse.ArgumentParser();p.add_argument('--before',required=True,type=pathlib.Path);p.add_argument('--after',required=True,type=pathlib.Path)
 p.add_argument('--before-source',required=True,type=pathlib.Path);p.add_argument('--before-sha',required=True);p.add_argument('--after-sha',required=True)
 p.add_argument('--runs',type=int,default=11);p.add_argument('--output',type=pathlib.Path,required=True);a=p.parse_args()
 if a.runs<5:p.error('at least five runs')
 allowed=sorted(os.sched_getaffinity(0));os.sched_setaffinity(0,{allowed[0]})
 cpu=pathlib.Path('/proc/cpuinfo').read_text()
 tools={name:shutil.which(name) for name in ['gcc','clang','rustc']}
 report={'before_commit':a.before_sha,'after_code_commit':a.after_sha,'before_source_sha256':digest(a.before_source),'after_source_sha256':digest(ROOT/'skite.ck'),
  'compiler_sha256':{'before':digest(a.before),'after':digest(a.after)},'cpu_model':next(s.split(':',1)[1].strip() for s in cpu.splitlines() if s.startswith('model name')),
  'cpu_flags':next(s.split(':',1)[1].strip() for s in cpu.splitlines() if s.startswith('flags')),'allowed_cpus':allowed,'pinned_cpu':allowed[0],
  'runs':a.runs,'tools':{k:run([v,'--version'],text=True).stdout.splitlines()[0] if v else None for k,v in tools.items()},
  'gcc_flags':['-O3','-march=native','-ffp-contract=off'],'scope':'before/after Skite; GCC checksum/timing control; no Clang/Rust or best-compiler performance claim','kernels':{}}
 with tempfile.TemporaryDirectory(prefix='skite-length-bench-') as td:
  t=pathlib.Path(td)
  for kernel in ['window','prefix']:
   base=ROOT/'bench/length_facts'/kernel;exes={};meta={}
   for key,c in [('before',a.before),('after',a.after)]:
    e=t/(kernel+'.'+key);cp=run([c,base.with_suffix('.ck'),e],text=True);exes[key]=e
    meta[key]={'binary_sha256':digest(e),'bytes':e.stat().st_size,'compiler_report':cp.stdout.strip()}
   if tools['gcc']:
    e=t/(kernel+'.gcc');run([tools['gcc'],*report['gcc_flags'],base.with_suffix('.c'),'-o',e]);exes['gcc']=e
    meta['gcc']={'binary_sha256':digest(e),'bytes':e.stat().st_size}
   outputs=[]
   for args in [[],['a'],['a','b','c']]:
    obs={k:run([exe,*args]).stdout for k,exe in exes.items()}
    if len(set(obs.values()))!=1:raise AssertionError((kernel,args,obs))
    outputs.append({'argc':len(args)+1,'output':obs['before'].decode()})
   samples={k:[] for k in exes};orders=[]
   for i in range(a.runs):
    keys=list(exes);random.Random(0xA11+i).shuffle(keys);orders.append(keys)
    for k in keys:
     start=time.perf_counter_ns();subprocess.run([str(exes[k])],stdout=subprocess.DEVNULL,check=True,timeout=30)
     samples[k].append((time.perf_counter_ns()-start)/1e6)
   report['kernels'][kernel]={'source_sha256':{ext:digest(base.with_suffix('.'+ext)) for ext in ['ck','c']},'binaries':meta,'checksums':outputs,'timings':{k:summary(v) for k,v in samples.items()},'orders':orders}
   print(kernel,{k:round(statistics.median(v),3) for k,v in samples.items()},flush=True)
 a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(report,indent=2)+'\n')
 print(a.output,flush=True)
if __name__=='__main__':main()
