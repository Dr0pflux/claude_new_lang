// constant-bound search loops become nested ifs: same tests, same order, same traps
fn pick(cum: [f64], r: f64) -> i64 {
  let mut c = 0;
  while c < 3 && cum[c] <= r { c += 1; }
  return c;
}
fn main() {
  let cum = alloc<f64>(4); cum[0] = 0.25; cum[1] = 0.5; cum[2] = 0.75; cum[3] = 1.0;
  let a = alloc<i64>(5); for k in 0..5 { a[k] = k * k; }
  let mut h = 0;
  for i in 0..12 {
    let r = (i as f64) / 12.0;
    h = h * 5 + pick(cum, r);
    let mut c = 1;
    while c < 5 && a[c] < i { c += 1; }
    h = h * 7 + c;
  }
  print(h);
  let mut c = 2;
  while c < 7 && a[c] >= 0 { c += 1; }   // a[5] traps after the output above
  print(c);
}
