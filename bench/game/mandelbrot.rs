// Benchmarks Game mandelbrot (same algorithm as mandelbrot.ck / .c). usage: mandelbrot N
use std::io::Write;
fn main() {
  let n: usize = std::env::args().nth(1).map(|s| s.parse().unwrap()).unwrap_or(200);
  let out = std::io::stdout();
  let mut o = std::io::BufWriter::new(out.lock());
  write!(o, "P4\n{} {}\n", n, n).unwrap();
  let mut row = vec![0u8; (n + 7) / 8];
  for y in 0..n {
    let ci = 2.0 * y as f64 / n as f64 - 1.0;
    let mut bits: u32 = 0;
    for x in 0..n {
      let cr = 2.0 * x as f64 / n as f64 - 1.5;
      let (mut zr, mut zi, mut tr, mut ti) = (0.0f64, 0.0f64, 0.0f64, 0.0f64);
      let mut i = 0;
      while i < 50 && tr + ti <= 4.0 {
        zi = 2.0 * zr * zi + ci;
        zr = tr - ti + cr;
        tr = zr * zr;
        ti = zi * zi;
        i += 1;
      }
      bits <<= 1;
      if tr + ti <= 4.0 { bits |= 1; }
      if x % 8 == 7 { row[x / 8] = bits as u8; bits = 0; }
    }
    if n % 8 != 0 { row[n / 8] = (bits << (8 - n % 8)) as u8; }
    o.write_all(&row).unwrap();
  }
}
