// Same wrapping adjacent-window accumulator as window.c; bounds are runtime len(a).
fn main() {
  let n = 262144 + argc() - 1;
  let a = alloc<i64>(n);
  for i in 0..len(a) { a[i] = (i * 7) % 1000 - 500; }
  let mut h = argc();
  for r in 0..300 {
    for i in 1..len(a) { h = (h ^ a[i - 1]) + a[i]; }
  }
  print(h);
}
