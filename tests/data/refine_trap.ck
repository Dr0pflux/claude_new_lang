// b[m] in a comparison must keep its bounds check: refining the branch environments evaluated
// the comparison again under the assumption that its own check had passed (m reaches -1 here)
fn run(b: [i64], n: i64) -> i64 {
  let mut m = 1; let mut o = 0; let mut i = 0;
  let hh = b[2];
  while o < n { m -= 1; if b[m] >= hh { i += 1; } o += 1; }
  return i * 7 + m * 13 + o;
}
fn main() {
  let n = 18;
  let b = alloc<i64>(n + 8);
  for k in 0..n + 8 { b[k] = k % 3 - 1; }
  print(7);
  print(run(b, n));
}
