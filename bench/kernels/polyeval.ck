// Horner evaluation of a degree-16 polynomial over an array of f64, many passes.
fn main() {
  let n = 4096 + argc() - 1;
  let co = alloc<f64>(17); let x = alloc<f64>(n); let y = alloc<f64>(n);
  for k in 0..17 { co[k] = 1.0 / ((k + 1) as f64); }
  for i in 0..n { x[i] = ((i * 37) % 1024) as f64 / 1024.0 - 0.5; }
  let mut acc = 0.0;
  for p in 0..36000 {
    let s = (p & 63) as f64 * 0.001;
    for i in 0..n {
      let t = x[i] + s;
      let mut r = co[16];
      for k in 0..16 { r = r * t + co[15 - k]; }
      y[i] = r;
    }
    for i in 0..n { acc += y[i]; }
  }
  print((acc * 1000.0) as i64);
}
