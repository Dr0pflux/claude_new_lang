// Naive i-k-j f64 matrix multiply, n x n. Inputs are small multiples of 1/4 so every sum is exact.
fn main() {
  let n = 768 + argc() - 1;
  let a = alloc<f64>(n * n); let b = alloc<f64>(n * n); let c = alloc<f64>(n * n);
  for i in 0..n * n { a[i] = ((i * 7 + 3) % 13) as f64 * 0.25; b[i] = ((i * 5 + 1) % 11) as f64 * 0.5; }
  for i in 0..n {
    for k in 0..n {
      let aik = a[i * n + k];
      for j in 0..n { c[i * n + j] += aik * b[k * n + j]; }
    }
  }
  let mut s = 0.0;
  for i in 0..n * n { s += c[i]; }
  print(s as i64); print(c[n * n - 1] as i64);
}
