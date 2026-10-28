// a hoisted invariant load runs only when the loop does: k is out of bounds in both loops, the
// first runs zero times (no trap), the second traps after the output before it
fn f(t: [i64], q: mut [i64], k: i64, n: i64) -> i64 {
  let mut s = 0;
  for j in 0..n { q[j] = s; s += t[k] * 2 + j; }
  return s;
}
fn main() {
  let a = alloc<i64>(8); let b = alloc<i64>(8);
  print(f(a, b, 9, argc() - 1));
  print(f(a, a, 9, argc() - 1));
  print(f(a, b, 9, argc() + 3));
  print(5);
}
