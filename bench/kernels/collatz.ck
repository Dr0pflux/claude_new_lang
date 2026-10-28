// Longest Collatz chain below 3e6 (no memoization).
fn main() {
  let n = 1500000 + argc() - 1;
  let mut best = 0; let mut arg = 0;
  for s in 1..n {
    let mut x = s; let mut steps = 0;
    while x != 1 { if x & 1 == 0 { x = x >> 1; } else { x = 3 * x + 1; } steps += 1; }
    if steps > best { best = steps; arg = s; }
  }
  print(arg); print(best);
}
