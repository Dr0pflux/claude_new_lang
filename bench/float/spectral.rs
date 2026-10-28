// Same algorithm as spectral.cock / spectral.c (safe indexing).
fn a(i: i64, j: i64) -> f64 { 1.0 / (((i + j) * (i + j + 1) / 2 + i + 1) as f64) }
fn av(v: &[f64], o: &mut [f64], n: usize) { for i in 0..n { let mut s = 0.0; for j in 0..n { s += a(i as i64, j as i64) * v[j]; } o[i] = s; } }
fn atv(v: &[f64], o: &mut [f64], n: usize) { for i in 0..n { let mut s = 0.0; for j in 0..n { s += a(j as i64, i as i64) * v[j]; } o[i] = s; } }
fn main() {
  let a_: Vec<String> = std::env::args().collect();
  let n: usize = std::fs::read_to_string(&a_[1]).unwrap().trim().parse().unwrap();
  let mut u = vec![1.0f64; n]; let mut v = vec![0.0f64; n]; let mut t = vec![0.0f64; n];
  for _ in 0..10 { av(&u, &mut t, n); atv(&t, &mut v, n); av(&v, &mut t, n); atv(&t, &mut u, n); }
  let (mut vbv, mut vv) = (0.0, 0.0);
  for i in 0..n { vbv += u[i] * v[i]; vv += v[i] * v[i]; }
  println!("{:.6}", (vbv / vv).sqrt());
}
