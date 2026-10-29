fn decimal_arg(s: [u8]) -> i64 { let mut v: i64 = 0; let mut i: i64 = 0; while i < len(s) && s[i] >= 48 && s[i] <= 57 { v = v * 10 + (s[i] - 48); i += 1; } return v; }
fn put_decimal(v: i64) { if v >= 10 { put_decimal(v / 10); } putc(v % 10 + 48); }
fn main() {
 let mut n: i64 = 16000;
 if len(argv(1)) > 0 { n = decimal_arg(argv(1)); }
 if n < 1 || n > 100000 { return; }
 let mut workers = ncpu();
 if workers < 1 { workers = 1; } if workers > 256 { workers = 256; }
 let width = ((n + 7) / 8) * 8;
 let height = ((n + workers - 1) / workers) * workers;
 let row_bytes = width / 8;
 let result = shared<u8>(row_bytes * height);
 let dx: f64 = 2.0 / (width as f64);
 let dy: f64 = 2.0 / (height as f64);
 let cr = alloc<f64>(width);
 for x in 0..width { cr[x] = -1.5 + (x as f64) * dx; }
 par worker in 0..workers {
  let mut y = worker;
  while y < height {
   let ci: f64 = -1.0 + (y as f64) * dy;
   let mut byte_x: i64 = 0;
   while byte_x < row_bytes {
    let x0 = byte_x * 8; let mut bits: i64 = 0;
    for lane in 0..8 {
     let cre = cr[x0 + lane];
     let mut zr = cre; let mut zi = ci;
     let mut escaped = false; let mut last_abs2: f64 = 0.0;
     let mut iter: i64 = 0;
     while iter < 50 {
      let r2 = zr * zr; let i2 = zi * zi;
      let abs2 = r2 + i2; last_abs2 = abs2;
      if abs2 > 4.0 { escaped = true; break; }
      let ri = zr * zi;
      zr = r2 - i2 + cre; zi = ri + ri + ci;
      iter += 1;
     }
     bits = bits << 1;
     if !escaped && last_abs2 <= 4.0 { bits = bits | 1; }
    }
    result[y * row_bytes + byte_x] = bits as u8;
    byte_x += 1;
   }
   y += workers;
  }
 }
 write("P4\n"); put_decimal(width); putc(32); put_decimal(height); putc(10); write(result);
}
