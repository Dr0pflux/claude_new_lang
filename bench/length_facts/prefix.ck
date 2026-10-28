// Inclusive prefix sums with runtime length facts, identical to prefix.c.
fn main() {
  let n = 262144 + argc() - 1;
  let a = alloc<i64>(n);
  for i in 0..len(a) { a[i] = (i * 7) % 1000 - 500; }
  for r in 0..1500 { for i in 1..len(a) { a[i] += a[i - 1]; } }
  let mut s = 0;
  for i in 0..len(a) { s = s * 31 + a[i]; }
  print(s); print(a[len(a) - 1]);
}
