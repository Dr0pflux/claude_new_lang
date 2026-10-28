// Repeated inclusive prefix sums over an i64 array (wrapping).
fn main() {
  let n = 262144 + argc() - 1;
  let a = alloc<i64>(n);
  for i in 0..n { a[i] = (i * 7) % 1000 - 500; }
  for r in 0..1500 { for i in 1..n { a[i] += a[i - 1]; } }
  let mut s = 0;
  for i in 0..n { s = s * 31 + a[i]; }
  print(s); print(a[n - 1]);
}
