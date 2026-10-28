// Sieve of Eratosthenes below 2e7, prime count. Same algorithm as sieve.c / sieve.rs.
fn main() {
  let n = 40000000 + argc() - 1;
  let c = alloc<u8>(n);
  let mut i = 2;
  while i * i < n { if c[i] == 0 { let mut j = i * i; while j < n { c[j] = 1; j += i; } } i += 1; }
  let mut cnt = 0; i = 2;
  while i < n { if c[i] == 0 { cnt += 1; } i += 1; }
  print(cnt);
}
