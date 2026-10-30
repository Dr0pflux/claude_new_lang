import subprocess,tempfile,pathlib,sys
compiler=str(pathlib.Path(sys.argv[1]).resolve())
def test(name,s,expected=None,bad=False,compile_bad=False,args=[]):
 with tempfile.TemporaryDirectory(prefix='skite-matrix-dynamic-') as t:
  src=pathlib.Path(t)/'test.ck';out=pathlib.Path(t)/'test';src.write_text(s)
  p=subprocess.run([compiler,str(src),str(out)],capture_output=True,text=True,timeout=18)
  if compile_bad: assert p.returncode!=0,(name,'should fail compilation',p.stderr,p.stdout)
  else:
   assert p.returncode==0,(name,p.stderr,p.stdout)
   p=subprocess.run([str(out),*args],capture_output=True,text=True,timeout=10)
   if bad: assert p.returncode!=0,(name,p.stdout,p.stderr)
   else: assert p.returncode==0 and p.stdout.strip()==expected,(name,p.returncode,p.stdout,p.stderr,expected)
 print('PASS',name)
S='''fn touch(m: mut matrix[i64]) { for r in 0..rows(m) { for c in 0..cols(m) { m[r,c] = r*100+c; } } }\nfn main() { let a=alloc<i64>(argc()+2,argc()+4); touch(a); print(rows(a));print(cols(a));print(len(a));print(a[rows(a)-1,cols(a)-1]); }'''
test('runtime matrix shape transmitted through function ABI',S,'3\n5\n15\n204')
test('runtime shape function with argument',S,'4\n6\n24\n305',args=['x'])
test('constant shape through matrix parameter','''fn touch(m: mut matrix[i64]) { m[2,3] = 71; print(cols(m)); } fn main() { let m=alloc<i64>(3,4);touch(m);print(m[2,3]); }''','4\n71')
test('multiple matrix args','''fn transfer(a: matrix[i64], b: mut matrix[i64]) { for i in 0..rows(a) { for j in 0..cols(a) { b[i,j] = a[i,j] + 2; } } } fn main() { let a=alloc<i64>(3,5);let b=alloc<i64>(3,5);a[2,4]=10;transfer(a,b);print(b[2,4]);print(b[1,3]); }''','12\n2')
test('second order nested shape calls','''fn inner(m: mut matrix[i64]) { m[rows(m)-1,cols(m)-1]=123; } fn middle(m: mut matrix[i64]) { inner(m); } fn main() { let m=alloc<i64>(argc()+2,4);middle(m);print(m[rows(m)-1,3]); }''','123')
test('dimensions evaluated exactly once', '''let mut calls:i64=0;fn dim()->i64 { calls+=1;return calls+1; }fn main() { let a=alloc<i64>(dim(),dim());print(calls);print(rows(a));print(cols(a));print(len(a)); }''','2\n2\n3\n6')
for name,d in [('zero row','0,4'),('zero col','4,0'),('negative row','-1,4'),('negative col','4,-1'),('overflow product','2000000000,2')]:
 test(name,f'fn main() {{ let r=argc();let m=alloc<i64>(r*0+{d});print(len(m)); }}',bad=True)
for name,i,j in [('row exceeds but flat valid', '3','0'),('negative row but flat valid','-1','5'),('column exceeds but flat valid','0','4'),('negative column but flat valid','1','-1')]:
 test(name,f'fn main() {{ let a=alloc<i64>(argc()+2,argc()+3);a[{i},{j}]=9;print(a[0,0]); }}',bad=True)
test('non-shaped 1D rejected for matrix param','fn f(x: matrix[i64]) { print(rows(x)); } fn main() { let a=alloc<i64>(8); f(a); }',compile_bad=True)
test('non-shaped rows rejected','fn main() { let a=alloc<i64>(8); print(rows(a)); }',compile_bad=True)
test('constant 2D still works','fn main(){let a=alloc<i64>(3,4);for i in 0..3 {for j in 0..4{a[i,j]=i*4+j;}} print(a[2,3]); }','11')
test('other normal array params preserved','fn f(a: mut [i64], j: i64) { a[j] = 5; } fn main() { let m=alloc<i64>(4);f(m,3);print(m[3]); }','5')
print('ALL TESTS PASSED')
