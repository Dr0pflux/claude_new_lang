// Benchmarks Game fannkuch-redux (same algorithm as fannkuchredux.c / .rs). usage: fannkuchredux N
fn arg_int(s: [u8]) -> i64 {
  let mut n = 0; let mut k = 0;
  while k < len(s) && s[k] >= 48 && s[k] <= 57 { n = n * 10 + (s[k] - 48); k += 1; }
  return n;
}
fn main() {
  let a1 = argv(1);
  let n = arg_int(a1);
  if n < 3 || n > 15 { return; }
  let perm = alloc<i64>(16);
  let perm1 = alloc<i64>(16);
  let count = alloc<i64>(16);
  let mut i = 0;
  while i < n { perm1[i] = i; i += 1; }
  let mut maxflips = 0;
  let mut checksum = 0;
  let mut permcount = 0;
  let mut r = n;
  while true {
    while r != 1 { count[r - 1] = r; r -= 1; }
    i = 0;
    while i < n { perm[i] = perm1[i]; i += 1; }
    let mut flips = 0;
    let mut k = perm[0];
    while k != 0 {
      let mut lo = 0; let mut hi = k;
      while lo < hi { let t = perm[lo]; perm[lo] = perm[hi]; perm[hi] = t; lo += 1; hi -= 1; }
      flips += 1;
      k = perm[0];
    }
    if flips > maxflips { maxflips = flips; }
    if permcount % 2 == 0 { checksum += flips; } else { checksum -= flips; }
    // next permutation
    let mut done = true;
    while r != n {
      let p0 = perm1[0];
      i = 0;
      while i < r { perm1[i] = perm1[i + 1]; i += 1; }
      perm1[r] = p0;
      count[r] -= 1;
      if count[r] > 0 { done = false; break; }
      r += 1;
    }
    if done { break; }
    permcount += 1;
  }
  print(checksum);
  write("Pfannkuchen("); print_int(n); write(") = "); print(maxflips);
}
fn print_int(x: i64) { if x >= 10 { print_int(x / 10); } putc(x % 10 + 48); }
