// XMM expression stack: right-nested trees deeper than xmm2..xmm15, trees nested in int subexpressions
fn main() {
  let mut a = 1.0;
  let s = (a + (a + (a + (a + (a + (a + (a + (a + (a + (a + (a + (a + (a + (a + (a + (a + (a + (a + (a + a)))))))))))))))))));
  print(s);
  let t = (a * ((((a * ((((a * ((((a * ((((a * ((((a * ((((a * ((((a * ((((a * ((((a * ((((a * ((((a * ((((a * ((((a * ((((a * ((((a * (((a * 2.0) as i64) as f64) - 1.0) * 2.0) as i64) as f64) - 1.0) * 2.0) as i64) as f64) - 1.0) * 2.0) as i64) as f64) - 1.0) * 2.0) as i64) as f64) - 1.0) * 2.0) as i64) as f64) - 1.0) * 2.0) as i64) as f64) - 1.0) * 2.0) as i64) as f64) - 1.0) * 2.0) as i64) as f64) - 1.0) * 2.0) as i64) as f64) - 1.0) * 2.0) as i64) as f64) - 1.0) * 2.0) as i64) as f64) - 1.0) * 2.0) as i64) as f64) - 1.0) * 2.0) as i64) as f64) - 1.0) * 2.0) as i64) as f64) - 1.0) * 2.0) as i64) as f64) - 1.0);
  print(t);
  let mut g: f32 = 0.5;
  g = -(((g * 4.0) as i32) as f32 + sqrt(g * 8.0)) / 2.0;
  print(g);
  print(bits(((1176299.0 / -1.0) + a) as f32));
  if s > t && !(s == t) { print(1); }
}
