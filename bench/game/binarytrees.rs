// Benchmarks Game binary-trees, node-pool version (same algorithm as binarytrees.cock / .c). usage: binarytrees N
struct Pool { lft: Vec<i32>, rgt: Vec<i32>, top: usize }
fn make(p: &mut Pool, d: i64) -> usize {
  let me = p.top; p.top += 1;
  if d > 0 { let l = make(p, d - 1); p.lft[me] = l as i32; let r = make(p, d - 1); p.rgt[me] = r as i32; }
  else { p.lft[me] = -1; p.rgt[me] = -1; }
  me
}
fn check(p: &Pool, t: usize) -> i64 {
  let l = p.lft[t];
  if l < 0 { return 1; }
  1 + check(p, l as usize) + check(p, p.rgt[t] as usize)
}
fn main() {
  let n: i64 = std::env::args().nth(1).map(|s| s.parse().unwrap()).unwrap_or(10);
  let maxd = if n < 6 { 6 } else { n };
  if maxd > 21 { return; }
  let mut p = Pool { lft: vec![0; 8388608], rgt: vec![0; 8388608], top: 0 };
  let st = make(&mut p, maxd + 1);
  println!("stretch tree of depth {}\t check: {}", maxd + 1, check(&p, st));
  p.top = 0;
  let longlived = make(&mut p, maxd);
  let base = p.top;
  let mut d = 4;
  while d <= maxd {
    let iters = 1i64 << (maxd - d + 4);
    let mut chk = 0;
    for _ in 0..iters { p.top = base; let t = make(&mut p, d); chk += check(&p, t); }
    println!("{}\t trees of depth {}\t check: {}", iters, d, chk);
    d += 2;
  }
  println!("long lived tree of depth {}\t check: {}", maxd, check(&p, longlived));
}
