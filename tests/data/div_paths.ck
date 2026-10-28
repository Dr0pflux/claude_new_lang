// 32-bit fast path and out-of-line 64-bit divide; Euclid rotation; traps keep SIGFPE
fn gcd(x: i64, y: i64) -> i64 { let mut a = x; let mut b = y; while b != 0 { let t = a % b; a = b; b = t; } return a; }
fn ugcd(x: u64, y: u64) -> u64 { let mut a = x; let mut b = y; while b != 0 { let t = a % b; a = b; b = t; } return a; }
fn main() {
  let k = argc() as i64;
  print(gcd(1071 * k, 462 * k)); print(gcd(-1071 * k, 462 * k)); print(gcd(1071 * k, -462 * k));
  print(gcd(9223372036854775807 - k, 6000000000 * k)); print(gcd(1 << (40 + k), 3 << (20 + k)));
  print(ugcd(18446744073709551615 - (k as u64), 12345678901 * (k as u64)));
  let mut q = 0; let mut r = 0; let mut i = 1;
  while i < 200 { let a = (i * 7919 * k) << (i % 50); let b = i * k - 1000; q += a / b; r = r ^ (a % b); i += 1; }
  print(q); print(r);
  let m = 0 - 9223372036854775807 - k;
  let d = 0 - k;
  print(9);
  print(m / d);   // MIN / -1: SIGFPE
}
