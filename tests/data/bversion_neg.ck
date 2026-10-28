// a versioned loop that starts below zero: b[i] with i0 = -2 must trap in the checked copy
// (the guard needs i0 + k >= 0 also when every offset k is >= 0)
fn f(b: mut [i64], c: [i64], n: i64, lo: i64) -> i64 {
  let mut s = 0; let mut i = lo;
  while i <= n { b[i + 3] = s + c[i + 2]; s = s * 3 + b[i]; i += 1; }
  return s;
}
fn main() {
  let b = alloc<i64>(10 + argc()); let c = alloc<i64>(14);
  for k in 0..14 { c[k] = k * 3 - 5; }
  print(f(b, c, 5 + argc() - 1, 0));
  print(f(b, c, 4 + argc() - 1, argc() - 3));
  print(9);
}
