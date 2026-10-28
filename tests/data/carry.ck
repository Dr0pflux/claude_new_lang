// loop-carried a[i - 1] (prefix sums, DP rows): kept in a variable; traps and empty loops unchanged
fn pre(a: mut [i64], n: i64) { let mut i = 1; while i < n { a[i] += a[i - 1]; i += 1; } }
fn fpre(f: mut [f64], n: i64) { let mut i = 1; while i < n { f[i] = f[i] * 0.5 + f[i - 1]; i += 1; } }
fn dp(r: mut [i64], w: [i64], n: i64) {
  let mut j = 1;
  while j <= n { let mut v = r[j] + w[j]; if r[j - 1] + 1 < v { v = r[j - 1] + 1; } r[j] = v; j += 1; }
}
fn main() {
  let n = 40 + argc();
  let a = alloc<i64>(n); let f = alloc<f64>(n); let r = alloc<i64>(n + 1); let w = alloc<i64>(n + 1);
  let mut i = 0;
  while i < n { a[i] = i * 7 % 11 - 5; f[i] = (i % 9) as f64 * 0.25; i += 1; }
  i = 0; while i <= n { r[i] = (i * 13) % 17; w[i] = i % 3; i += 1; }
  pre(a, n); pre(a, n); fpre(f, n); dp(r, w, n);
  let mut h = 0; i = 0; while i < n { h = h * 31 + a[i]; i += 1; } print(h);
  print(bits(f[n - 1]) as i64);
  h = 0; i = 0; while i <= n { h = h * 31 + r[i]; i += 1; } print(h);
  pre(a, 1); pre(a, 0);                       // loops that do not run
  let mut k = argc() - 1; let mut s = 0;     // k = 0 with no arguments: a[-1] traps on the first iteration
  while k < 5 { s += k; a[k] += a[k - 1]; k += 1; }
  print(s);
}
