// vectorized loops in a function whose array parameters alias at run time (f(x, x)) must match scalar
fn f(a: [i64], b: mut [i64], n: i64, m: i64) {
  if m > 1000 { f(a, b, n, m - 1); return; }
  let mut i = 1;
  while i < n {
    let mut s = 0; let mut j = 0;
    while j < m { s += a[i - 1] + j; j += 1; }
    b[i] = s;
    i += 1;
  }
}
fn main() {
  let x = alloc<i64>(40); let y = alloc<i64>(40);
  let mut i = 0; while i < 40 { x[i] = 1; y[i] = 2; i += 1; }
  f(x, x, 40, argc() + 2);
  f(x, y, 40, argc() + 2);
  print(x[5]); print(x[20]); print(y[7]); print(y[39]);
}
