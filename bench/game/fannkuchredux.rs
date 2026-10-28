// Benchmarks Game fannkuch-redux (same algorithm as fannkuchredux.ck / .c). usage: fannkuchredux N
fn main() {
  let n: usize = std::env::args().nth(1).map(|s| s.parse().unwrap()).unwrap_or(7);
  let mut perm = [0usize; 16];
  let mut perm1 = [0usize; 16];
  let mut count = [0usize; 16];
  for i in 0..n { perm1[i] = i; }
  let (mut maxflips, mut checksum, mut permcount, mut r) = (0i64, 0i64, 0i64, n);
  loop {
    while r != 1 { count[r - 1] = r; r -= 1; }
    perm[..n].copy_from_slice(&perm1[..n]);
    let mut flips = 0i64;
    let mut k = perm[0];
    while k != 0 {
      let (mut lo, mut hi) = (0, k);
      while lo < hi { perm.swap(lo, hi); lo += 1; hi -= 1; }
      flips += 1;
      k = perm[0];
    }
    if flips > maxflips { maxflips = flips; }
    checksum += if permcount % 2 == 0 { flips } else { -flips };
    let mut done = true;
    while r != n {
      let p0 = perm1[0];
      for i in 0..r { perm1[i] = perm1[i + 1]; }
      perm1[r] = p0;
      count[r] -= 1;
      if count[r] > 0 { done = false; break; }
      r += 1;
    }
    if done { break; }
    permcount += 1;
  }
  println!("{}\nPfannkuchen({}) = {}", checksum, n, maxflips);
}
