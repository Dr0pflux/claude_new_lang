// bounds versioning: loops over i + k run without checks only when a guard before the loop
// proves every index in range; otherwise the checked copy runs (zero trips, short arrays, i0 < 0)
fn win(t: [u8], n: i64, lo: i64) -> i64 {
  let mut s = 0; let mut i = lo;
  while i < n - 2 { s = s * 7 + ((t[i] as i64) << 16 | (t[i + 1] as i64) << 8 | (t[i + 2] as i64)) % 1000003; i += 1; }
  return s;
}
fn back(a: [i64], b: mut [i64], m: i64, lo: i64) -> i64 {
  let mut s = 0; let mut i = lo;
  while i <= m { b[i] = a[i - 1] + a[i] * 2; s += b[i]; i += 1; }
  return s;
}
fn main() {
  let t = alloc<u8>(40); for k in 0..40 { t[k] = (k * 7 % 26 + 97) as u8; }
  let a = alloc<i64>(20); let b = alloc<i64>(20); for k in 0..20 { a[k] = k * k - 9; }
  print(win(t, 40, 0)); print(win(t, 2, 0)); print(win(t, 41 - argc(), 3));
  print(back(a, b, 19, 1)); print(back(a, b, 0, 1)); print(back(a, b, 10, 5));
  let mut h = 0; for k in 0..20 { h = h * 31 + b[k]; } print(h);
  print(win(t, 41, 0));
}
