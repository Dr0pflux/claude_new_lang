// invariant loads hoisted out of inner loops: the stored array may be the loaded one (same
// array passed twice, or a view of it), and the loop may run zero times or trap
fn f(t: [i64], row: mut [i64], k: i64, n: i64) -> i64 {
  let mut s = 0;
  for j in 0..n { row[j] = row[j] + t[k] * 3 + j; s += t[k]; }
  for j in 0..n { if row[j] > t[k + 1] { s += 1; } row[(j + 1) % n] = s; }
  return s;
}
fn g(t: [u8], row: mut [i64], k: i64, n: i64) -> i64 {
  let mut s = 0;
  for j in 0..n { row[j] = row[j] * 7 + (t[k] as i64); s = s * 3 + (t[k] as i64); }
  return s;
}
fn big(a: [i64], b: mut [i64], k: i64, n: i64) -> i64 {
  let mut s = 0; let mut r = 0;
  while r < 3 {
    let mut j = 0;
    while j < n { b[j] = b[j] + a[k]; if a[k] > j { s += a[k + r]; } j += 1; }
    s = s * 5 + b[r]; r += 1;
  }
  return s + f(a, b, k, n) + f(b, b, k, n);
}
fn main() {
  let n = 16;
  let a = alloc<i64>(n); let b = alloc<i64>(n);
  for i in 0..n { a[i] = i * 3 - 7; b[i] = 100 - i; }
  print(f(a, b, 2, n)); print(f(b, b, 2, n)); print(f(a, a, 5, n)); print(f(a, b, 3, 0));
  let mut h = 0; for i in 0..n { h = h * 31 + a[i] + 7 * b[i]; } print(h);
  let by = alloc<u8>(n * 8); for i in 0..n * 8 { by[i] = (i * 5) as u8; }
  let wv = view<i64>(by);
  print(g(by, wv, 9, n)); print(g(by, wv, 0, n)); print(g(by, b, 3, n));
  print(big(a, b, 4, n)); print(big(b, b, 4, n)); print(big(a, a, 1, n));
  h = 0; for i in 0..n { h = h * 31 + a[i] + 7 * b[i]; } print(h);
}
