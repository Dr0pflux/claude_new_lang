// `for` loops of while_form.ck: both must compile to identical machine code.
fn main() {
  let n = 1000 + argc();
  let a = alloc<f64>(n); let b = alloc<f64>(n);
  for i in 0..n { b[i] = i as f64; }
  for j in 0..n { a[j] = b[j] * 2.0 + 1.0; }
  let mut s = 0.0;
  for k in 0..n { s += a[k]; }
  print(s);
  let mut t = 0;
  for m in 0..8 { t += m * 3; }
  print(t);
  let x = alloc<u8>(argc() * 100);
  for p in 0..len(x) { x[p] = (p * 7) as u8; }
  let mut h = 0;
  for q in 0..len(x) { if x[q] > 100 { continue; } h += x[q] as i64; }
  print(h);
  // escape-time kernel (vectorized)
  let mut acc = 0;
  for px in 0..n {
    let cr = (px as f64) * 0.003 - 2.0;
    let mut zr = 0.0; let mut zi = 0.0; let mut it = 0;
    while it < 50 && zr * zr + zi * zi <= 4.0 {
      let nz = zr * zr - zi * zi + cr;
      zi = 2.0 * zr * zi + 0.5; zr = nz; it += 1;
    }
    acc += it;
  }
  print(acc);
  let mut r = 0;
  for e in 1..=10 { r += e; }
  print(r);
  let mut tri = 0;
  for y in 0..n { for z in 0..y { tri += z ^ y; } }
  print(tri);
}
