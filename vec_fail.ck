fn main() {
  let ia = alloc<i64>(16); let fa = alloc<f64>(16);
  let ib = alloc<i64>(15 + argc()); let fb = alloc<f64>(15 + argc());
  let mut k = 0;
  while k < 16 { ia[k] = k * 7919 - 50000 + argc(); fa[k] = (k as f64) * 0.37 - 2.5; ib[k] = ia[k] * 3 + 1; fb[k] = fa[k] * 1.5 + 0.25; k += 1; }
  let n = 100 + argc() - 1;
  let u = argc() * 3;
  let uf = 1.5 + (argc() as f64);
  let mut acc = 0; let mut facc: u64 = 0;
  let mut i = 0;
  while i < n {
    let mut x1 = (((0 - ia[6]) - ((ia[10] * (ia[10] + 0)) >>> 51)) << 5);
    let mut x2 = (((ia[15] | (ib[(u) & 15] % 16)) % 8) - (((ia[15] | (ib[(u) & 15] % 16)) % 8) + u));
    let mut x3 = (3 >> 7);
    let mut f4 = fb[(u) & 15];
    let mut t5 = 0;
    while t5 < 4 && ((-128 as f64) - sqrt(f4)) >= 1e300 {
      x1 = x1;
      if ((((ia[2] + x3) >> 3) < (t5 % 1024) && uf == (uf - (-(x1 as f64)))) || u >= ia[4]) {
        x1 = ((((2 << 58) >>> 40) << 31) & (~((((ib[(u) & 15]) as i8 as i64)) as u16 as i64)));
        f4 = ((sqrt((1.0 + (1.0 * 1.0))) * f4) * (((1.0 / (x1 as f64)) / uf) + uf));
        f4 = (((((t5) as f64 as i64) << 41) as f64) + (((1e300 / 0.5) - ((1e300 / 0.5) * 1.0)) / f4));
      }
      t5 += 1;
    }
    acc = acc * 31 + x1;
    acc = acc * 31 + x2;
    acc = acc * 31 + x3;
    acc = acc * 31 + t5;
    facc = facc * 31 + bits(f4);
    if x1 > 0 { print(x1); }
    i += 1;
  }
  print(acc); print(facc);
}
