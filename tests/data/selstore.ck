// select stores and multi-assignment if-conversion: merges, counted selects, equal keys
fn merge(src: [i64], dst: mut [i64], lo: i64, mid: i64, hi: i64) {
  let mut i = lo; let mut j = mid; let mut o = lo;
  while i < mid && j < hi {
    if src[j] < src[i] { dst[o] = src[j]; j += 1; } else { dst[o] = src[i]; i += 1; }
    o += 1;
  }
  while i < mid { dst[o] = src[i]; i += 1; o += 1; }
  while j < hi { dst[o] = src[j]; j += 1; o += 1; }
}
fn pick(a: [i64], b: [i64], c: mut [i64], n: i64) -> i64 {
  let mut lo = 0; let mut hi = 0; let mut s = 0;
  for k in 0..n {
    if a[k] <= b[k] { c[k] = a[k]; lo += 1; s = s + k; } else { c[k] = b[k] + 1; hi += 1; }
    if a[k] != b[k] { s -= 1; lo = hi; } else { hi = lo + 2; }
  }
  return lo * 1000 + hi * 10 + s;
}
fn main() {
  let n = 37;
  let a = alloc<i64>(n); let b = alloc<i64>(n); let c = alloc<i64>(n);
  let mut x: u64 = 12345;
  for k in 0..n { x = x * 6364136223846793005 + 1442695040888963407; a[k] = ((x >> 33) % 11) as i64 - 5; b[k] = ((x >> 45) % 7) as i64 - 3; }
  print(pick(a, b, c, n));
  let mut h = 0; for k in 0..n { h = h * 7 + c[k]; } print(h);
  let mut w = 1; let mut f = 0;
  while w < n {
    let mut lo = 0;
    while lo < n {
      let mut mid = lo + w; if mid > n { mid = n; }
      let mut hi = lo + 2 * w; if hi > n { hi = n; }
      if f == 0 { merge(a, c, lo, mid, hi); } else { merge(c, a, lo, mid, hi); }
      lo += 2 * w;
    }
    f = 1 - f; w *= 2;
  }
  h = 0; for k in 0..n { if f == 0 { h = h * 13 + a[k]; } else { h = h * 13 + c[k]; } } print(h);
}
