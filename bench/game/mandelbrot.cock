// Benchmarks Game mandelbrot (same algorithm as mandelbrot.c / .rs): PBM bitmap of N x N. usage: mandelbrot N
fn arg_int(s: [u8]) -> i64 {
  let mut n = 0; let mut k = 0;
  while k < len(s) && s[k] >= 48 && s[k] <= 57 { n = n * 10 + (s[k] - 48); k += 1; }
  return n;
}
fn put_int(x: i64) { if x >= 10 { put_int(x / 10); } putc(x % 10 + 48); }
fn main() {
  let a1 = argv(1);
  let n = arg_int(a1);
  if n < 8 || n > 100000 { return; }
  write("P4\n"); put_int(n); putc(32); put_int(n); putc(10);
  let row = alloc<u8>((n + 7) / 8);
  let fn_ = n as f64;
  let mut y = 0;
  while y < n {
    let ci = 2.0 * (y as f64) / fn_ - 1.0;
    let mut acc = 0;
    let mut x = 0;
    while x < n {
      let cr = 2.0 * (x as f64) / fn_ - 1.5;
      let mut zr = 0.0; let mut zi = 0.0; let mut tr = 0.0; let mut ti = 0.0;
      let mut i = 0;
      while i < 50 && tr + ti <= 4.0 {
        zi = 2.0 * zr * zi + ci;
        zr = tr - ti + cr;
        tr = zr * zr;
        ti = zi * zi;
        i += 1;
      }
      acc = acc << 1;
      if tr + ti <= 4.0 { acc = acc | 1; }
      if x % 8 == 7 { row[x / 8] = acc as u8; acc = 0; }
      x += 1;
    }
    if n % 8 != 0 { row[n / 8] = (acc << (8 - n % 8)) as u8; }
    write(row);
    y += 1;
  }
}
