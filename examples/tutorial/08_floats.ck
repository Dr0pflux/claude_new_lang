fn mean(a: [f64]) -> f64 {
  let mut s = 0.0;
  let mut i = 0;
  while i < len(a) { s += a[i]; i += 1; }
  return s / len(a) as f64;
}
fn main() {
  let x = alloc<f64>(4);
  x[0] = 1.5; x[1] = 2.5; x[2] = 3.0; x[3] = 5.0;
  let m = mean(x);
  print(m);                    // 3.000000
  print(sqrt(m * 3.0));        // 3.000000
  print((m * 100.0) as i64);   // 300
}
