// v0.7 type system regression: every scalar type, casts, unsigned ops, floats
fn mean(a: [f64], n: i64) -> f64 {
  let mut s = 0.0;
  let mut i = 0;
  while i < n { s += a[i]; i += 1; }
  return s / n as f64;
}
fn shout(x: u8) { putc(x as i64 - 32); putc(10); }
fn main() {
  let b: u8 = 200;
  print(b as i8);                       // -56
  print((b + 100) as u8);               // 44: arithmetic is 64-bit, `as` wraps
  let w = alloc<u16>(4);
  w[1] = 65535;
  w[1] += 2;                            // compound store wraps: 1
  print(w[1]);
  let big: u64 = 18446744073709551615;
  print(big);
  print(big / 10);                      // unsigned division
  print(big > 1);                       // unsigned compare: true
  print(big >> 60);                     // logical: 15
  print(-8 >> 1);                       // arithmetic: -4
  let x: i32 = -5;
  print(x as u32);                      // 4294967291
  print(x as u64 >> 63);                // 1
  let f = alloc<f64>(3);
  f[0] = 1.5; f[1] = 2.25; f[2] = -0.75;
  print(mean(f, 3));                    // 1.000000
  let h: f32 = 0.1;
  print(h as f64);                      // 0.100000 (f32 0.1 widened)
  print(bits(h));                       // 1036831949
  print(300.7 as u8);                   // saturating: 255
  print(-1.0e30 as i64);                // -9223372036854775808
  print((0.0 / 0.0) as i32);            // NaN -> 0
  print(sqrt(2.0) * sqrt(2.0) > 1.9999);
  print(1.0 / 0.0);                     // inf
  print(-2.5);
  shout(104);                           // H
  let flags = alloc<bool>(2);
  flags[1] = !flags[0];
  print(flags[1] && 3 < 4);
}
