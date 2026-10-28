// for / loop / const / 0b / 0o regression (expected output in features.expected)
const N = 10;
const MASK: u64 = 0b1111_0000;
const PERM = 0o755;
const SCALE = 1.5;
let table = alloc<i64>(N);
let mut calls = 0;
fn bound(n: i64) -> i64 { calls += 1; return n; }
fn sum_to(n: i64) -> i64 {
  let mut s = 0;
  for i in 0..n { s += i; }
  return s;
}
fn first_neg(a: [i64]) -> i64 {
  for i in 0..len(a) { if a[i] < 0 { return i; } }
  return -1;
}
fn collatz(n0: i64) -> i64 {
  let mut n = n0; let mut steps = 0;
  loop {
    if n == 1 { return steps; }
    if n % 2 == 0 { n /= 2; } else { n = 3 * n + 1; }
    steps += 1;
  }
}
fn first_square_above(n: i64) -> f64 {   // ends in a loop whose only break leaves an inner loop
  let mut k = 0;
  loop {
    for i in 0..k { if i * i > n { break; } }
    if k * k > n { return k as f64; }
    k += 1;
  }
}
fn main() {
  print(sum_to(N));                         // 45
  let mut s = 0;
  for i in 1..=N { s += i; }
  print(s);                                 // 55
  s = 0;
  for i in 0..20 { if i % 3 == 0 { continue; } s += i; }
  print(s);                                 // 127: continue still steps i
  s = 0;
  for i in 0..100 { if i == 7 { break; } s += 1; }
  print(s);                                 // 7
  let mut k = 0;
  loop { k += 1; if k * k > 50 { break; } }
  print(k);                                 // 8
  print(collatz(27));                       // 111
  print(first_square_above(50));            // 8
  print(MASK as i64);                       // 240
  print(PERM);                              // 493
  print(0b1 + 0B10 + 0O7 + 0x_f);           // 25
  print(0b1111111111111111111111111111111111111111111111111111111111111111 == 18446744073709551615);
  print(0o1777777777777777777777 == 18446744073709551615);
  print(SCALE * 2.0);                       // 3
  const C = 3 * 4 + N;
  print(C);                                 // 22
  for i in 0..N { table[i] = i * i; }
  print(table[N - 1]);                      // 81
  let a = alloc<i64>(5);
  for i in 0..5 { a[i] = 2 - i; }
  print(first_neg(a));                      // 3
  let mut c = 0;
  for i in 0..4 { for j in 0..4 { if j > i { continue; } c += 1; } }
  print(c);                                 // 10: continue steps only the inner loop
  let mut n = 5; let mut t = 0;
  for i in 0..n { n += 1; t += 1; }
  print(t);                                 // 5: the bound is evaluated once
  t = 0;
  for i in bound(2)..bound(6) { t += i; }
  print(t * 100 + calls);                   // 1402
  for i in 5..5 { print(999); }
  for i in 5..2 { print(999); }
  for i in -3..=-3 { print(i); }            // -3
  let big: u64 = 3;
  let mut u: u64 = 0;
  for i in 0..big { u += i; }
  print(u);                                 // 3
  let w8: u8 = 4; let w32: i32 = -2;
  t = 0;
  for i in w32..w8 { t += i; }
  print(t);                                 // -2 + -1 + 0 + 1 + 2 + 3 = 3
  let mut z = 0;
  loop { z += 2; if z >= 10 { break; } continue; }
  print(z);                                 // 10
  let mut q = 0;
  for i in 0..10 { let sq = i * i; q += sq; }
  print(q);                                 // 285
  // compound ops on array elements of every element type
  let f = alloc<f64>(3);
  for i in 0..3 { f[i] = 1.5; f[i] *= 2.0; f[i] -= 0.5; }
  print(f[2]);                              // 2.5
  let g = alloc<f32>(2); g[1] = 4.0; g[1] /= 8.0; print(g[1] as f64);
  let b8 = alloc<u8>(2); b8[0] = 250; b8[0] += 10; print(b8[0]);   // 4 (wraps)
  b8[1] = 3; b8[1] <<= 2; b8[1] |= 1; print(b8[1]);                 // 13
  let i16a = alloc<i16>(1); i16a[0] = -7; i16a[0] %= 4; print(i16a[0]);   // -3
  let u64a = alloc<u64>(1); u64a[0] = 1; u64a[0] <<= 63; u64a[0] >>>= 62; print(u64a[0]);   // 2
}
