// Benchmarks Game spectral-norm (same algorithm as spectralnorm.c / .rs). usage: spectralnorm N
fn a(i: i64, j: i64) -> f64 { return 1.0 / (((i + j) * (i + j + 1) / 2 + i + 1) as f64); }
fn av(v: [f64], o: mut [f64], n: i64) {
  let mut i = 0;
  while i < n { let mut s = 0.0; let mut j = 0; while j < n { s += a(i, j) * v[j]; j += 1; } o[i] = s; i += 1; }
}
fn atv(v: [f64], o: mut [f64], n: i64) {
  let mut i = 0;
  while i < n { let mut s = 0.0; let mut j = 0; while j < n { s += a(j, i) * v[j]; j += 1; } o[i] = s; i += 1; }
}
fn atav(v: [f64], o: mut [f64], t: mut [f64], n: i64) { av(v, t, n); atv(t, o, n); }
fn arg_int(s: [u8]) -> i64 {
  let mut n = 0; let mut k = 0;
  while k < len(s) && s[k] >= 48 && s[k] <= 57 { n = n * 10 + (s[k] - 48); k += 1; }
  return n;
}
fn print9(x: f64) {
  let mut ip = x as i64;
  let mut t = ((x - ip as f64) * 1000000000.0 + 0.5) as i64;
  if t >= 1000000000 { ip += 1; t -= 1000000000; }
  put_int(ip); putc('.');
  let mut p = 100000000;
  while p > 0 { putc(t / p % 10 + 48); p = p / 10; }
  putc(10);
}
fn put_int(x: i64) { if x >= 10 { put_int(x / 10); } putc(x % 10 + 48); }
fn main() {
  let a1 = argv(1);
  let n = arg_int(a1);
  if n < 1 || n > 100000 { return; }
  let u = alloc<f64>(n);
  let v = alloc<f64>(n);
  let t = alloc<f64>(n);
  let mut i = 0;
  while i < n { u[i] = 1.0; i += 1; }
  i = 0;
  while i < 10 { atav(u, v, t, n); atav(v, u, t, n); i += 1; }
  let mut vbv = 0.0;
  let mut vv = 0.0;
  i = 0;
  while i < n { vbv += u[i] * v[i]; vv += v[i] * v[i]; i += 1; }
  print9(sqrt(vbv / vv));
}
