// Benchmarks Game binary-trees, node-pool version (same algorithm as binarytrees.c / .rs). usage: binarytrees N
let CAP = 8388608;
let lft = alloc<i32>(8388608);
let rgt = alloc<i32>(8388608);
let mut top: i64 = 0;

fn arg_int(s: [u8]) -> i64 {
  let mut n = 0; let mut k = 0;
  while k < len(s) && s[k] >= 48 && s[k] <= 57 { n = n * 10 + (s[k] - 48); k += 1; }
  return n;
}
fn make(d: i64) -> i64 {
  let me = top; top += 1;
  if d > 0 { lft[me] = make(d - 1) as i32; rgt[me] = make(d - 1) as i32; }
  else { lft[me] = -1; rgt[me] = -1; }
  return me;
}
fn check(t: i64) -> i64 {
  let l = lft[t] as i64;
  if l < 0 { return 1; }
  return 1 + check(l) + check(rgt[t] as i64);
}
fn put_int(x: i64) { if x >= 10 { put_int(x / 10); } putc(x % 10 + 48); }
fn main() {
  let a1 = argv(1);
  let n = arg_int(a1);
  let mut maxd = n; if maxd < 6 { maxd = 6; }
  if maxd > 21 { return; }
  top = 0;
  let st = make(maxd + 1);
  write("stretch tree of depth "); put_int(maxd + 1); write("\t check: "); print(check(st));
  top = 0;
  let longlived = make(maxd);
  let base = top;
  let mut d = 4;
  while d <= maxd {
    let iters = 1 << (maxd - d + 4);
    let mut chk = 0;
    let mut i = 0;
    while i < iters { top = base; chk += check(make(d)); i += 1; }
    put_int(iters); write("\t trees of depth "); put_int(d); write("\t check: "); print(chk);
    d += 2;
  }
  write("long lived tree of depth "); put_int(maxd); write("\t check: "); print(check(longlived));
}
