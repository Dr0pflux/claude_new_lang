fn main() {
  let ia = alloc<i64>(16); let fa = alloc<f64>(16);
  let ib = alloc<i64>(15 + argc()); let fb = alloc<f64>(15 + argc());
  let mut k = 0;
  while k < 16 { ia[k] = k * 7919 - 50000 + argc(); fa[k] = (k as f64) * 0.37 - 2.5; ib[k] = ia[k] * 3 + 1; fb[k] = fa[k] * 1.5 + 0.25; k += 1; }
  let n = 100 + argc() - 1;
  let u = argc() * 3;
  let mut acc = 0;
  let mut i = 0;
  while i < n {
    let mut x1 = i;
    let mut x2 = ((ia[15] | (ib[(u) & 15] % 16)) % 8);
    let mut t5 = 0;
    while t5 < 4 && i > 1000 {
      x1 = x1 + 1;
      t5 += 1;
    }
    acc = acc * 31 + x1;
    acc = acc * 31 + x2;
    i += 1;
  }
  print(acc);
}
