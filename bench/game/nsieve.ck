// Benchmarks Game nsieve (same algorithm as nsieve.c / .rs). usage: nsieve N
// Sieve of Eratosthenes over a byte array of "is composite" flags, for 10000 << N, 10000 << (N-1) and
// 10000 << (N-2); crossing-out starts at i*i.
fn arg_int(s: [u8]) -> i64 {
  let mut n = 0; let mut k = 0;
  while k < len(s) && s[k] >= 48 && s[k] <= 57 { n = n * 10 + (s[k] - 48); k += 1; }
  return n;
}
fn put_int(x: i64) { if x >= 10 { put_int(x / 10); } putc(x % 10 + 48); }
fn put_pad(x: i64, w: i64) {
  let mut d = 1;
  let mut t = x;
  while t >= 10 { t /= 10; d += 1; }
  while d < w { putc(32); d += 1; }
  put_int(x);
}
fn nsieve(m: i64) {
  let comp = alloc<u8>(m + 1);
  let mut count = 0;
  let mut i = 2;
  while i < len(comp) {
    if comp[i] == 0 {
      count += 1;
      let mut j = i * i;
      while j < len(comp) { comp[j] = 1; j += i; }
    }
    i += 1;
  }
  write("Primes up to ");
  put_pad(m, 8);
  putc(32);
  put_pad(count, 8);
  putc(10);
}
fn main() {
  let a1 = argv(1);
  let n = arg_int(a1);
  if n < 2 || n > 20 { return; }
  nsieve(10000 << n);
  nsieve(10000 << (n - 1));
  nsieve(10000 << (n - 2));
}
