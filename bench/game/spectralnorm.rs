// Benchmarks Game spectral-norm (same algorithm as spectralnorm.cock / .c). usage: spectralnorm N
fn a(i: i64, j: i64) -> f64 { 1.0 / (((i + j) * (i + j + 1) / 2 + i + 1) as f64) }
fn av(v: &[f64], o: &mut [f64], n: usize) {
  for i in 0..n { let mut s = 0.0; for j in 0..n { s += a(i as i64, j as i64) * v[j]; } o[i] = s; }
}
fn atv(v: &[f64], o: &mut [f64], n: usize) {
  for i in 0..n { let mut s = 0.0; for j in 0..n { s += a(j as i64, i as i64) * v[j]; } o[i] = s; }
}
fn atav(v: &[f64], o: &mut [f64], t: &mut [f64], n: usize) { av(v, t, n); atv(t, o, n); }
fn main() {
  let n: usize = std::env::args().nth(1).map(|s| s.parse().unwrap()).unwrap_or(100);
  let mut u = vec![1.0f64; n]; let mut v = vec![0.0f64; n]; let mut t = vec![0.0f64; n];
  for _ in 0..10 { atav(&u, &mut v, &mut t, n); atav(&v, &mut u, &mut t, n); }
  let (mut vbv, mut vv) = (0.0, 0.0);
  for i in 0..n { vbv += u[i] * v[i]; vv += v[i] * v[i]; }
  println!("{:.9}", (vbv / vv).sqrt());
}
