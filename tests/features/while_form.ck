// The hand-written counter loops of for_form.ck: both must compile to identical machine code.
fn main() {
  let n = 1000 + argc();
  let a = alloc<f64>(n); let b = alloc<f64>(n);
  let mut i = 0;
  while i < n { b[i] = i as f64; i += 1; }
  let mut j = 0;
  while j < n { a[j] = b[j] * 2.0 + 1.0; j += 1; }
  let mut s = 0.0;
  let mut k = 0;
  while k < n { s += a[k]; k += 1; }
  print(s);
  let mut t = 0;
  let mut m = 0;
  while m < 8 { t += m * 3; m += 1; }
  print(t);
  let x = alloc<u8>(argc() * 100);
  let mut p = 0;
  while p < len(x) { x[p] = (p * 7) as u8; p += 1; }
  let mut h = 0;
  let mut q = 0;
  while q < len(x) { if x[q] > 100 { q += 1; continue; } h += x[q] as i64; q += 1; }
  print(h);
  // escape-time kernel (vectorized)
  let mut acc = 0;
  let mut px = 0;
  while px < n {
    let cr = (px as f64) * 0.003 - 2.0;
    let mut zr = 0.0; let mut zi = 0.0; let mut it = 0;
    while it < 50 && zr * zr + zi * zi <= 4.0 {
      let nz = zr * zr - zi * zi + cr;
      zi = 2.0 * zr * zi + 0.5; zr = nz; it += 1;
    }
    acc += it;
    px += 1;
  }
  print(acc);
  let mut r = 0;
  let mut e = 1;
  while e <= 10 { r += e; e += 1; }
  print(r);
  let mut tri = 0;
  let mut y = 0;
  while y < n { let mut z = 0; while z < y { tri += z ^ y; z += 1; } y += 1; }
  print(tri);
}
