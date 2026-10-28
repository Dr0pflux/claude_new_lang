// Insertion sort of 16-element blocks, then bottom-up merge sort of n i64 values.
fn merge(src: [i64], dst: mut [i64], lo: i64, mid: i64, hi: i64) {
  let mut i = lo; let mut j = mid; let mut o = lo;
  while i < mid && j < hi {
    if src[j] < src[i] { dst[o] = src[j]; j += 1; } else { dst[o] = src[i]; i += 1; }
    o += 1;
  }
  while i < mid { dst[o] = src[i]; i += 1; o += 1; }
  while j < hi { dst[o] = src[j]; j += 1; o += 1; }
}
fn pass(src: [i64], dst: mut [i64], n: i64, w: i64) {
  let mut lo = 0;
  while lo < n {
    let mut mid = lo + w; if mid > n { mid = n; }
    let mut hi = lo + 2 * w; if hi > n { hi = n; }
    merge(src, dst, lo, mid, hi);
    lo += 2 * w;
  }
}
fn chk(a: [i64]) {
  let n = len(a);
  let mut s = 0; let mut ok = 1;
  for i in 0..n { s = s * 31 + a[i]; if i > 0 { if a[i - 1] > a[i] { ok = 0; } } }
  print(s); print(ok); print(a[0]); print(a[n - 1]);
}
fn main() {
  let n = 2000000 + argc() - 1;
  let a = alloc<i64>(n); let b = alloc<i64>(n);
  let mut x: u64 = 88172645463325252;
  for i in 0..n { x = x ^ (x << 13); x = x ^ (x >> 7); x = x ^ (x << 17); a[i] = (x >> 20) as i64; }
  let mut lo = 0;
  while lo < n {
    let mut hi = lo + 16; if hi > n { hi = n; }
    for i in lo + 1..hi {
      let v = a[i]; let mut j = i - 1;
      while j >= lo && a[j] > v { a[j + 1] = a[j]; j -= 1; }
      a[j + 1] = v;
    }
    lo += 16;
  }
  let mut w = 16; let mut flip = 0;
  while w < n {
    if flip == 0 { pass(a, b, n, w); } else { pass(b, a, n, w); }
    flip = 1 - flip; w = w * 2;
  }
  if flip == 0 { chk(a); } else { chk(b); }
}
