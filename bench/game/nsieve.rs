// Benchmarks Game nsieve (same algorithm as nsieve.ck / .c). usage: nsieve N
// Sieve of Eratosthenes over a byte array of "is composite" flags, for 10000 << N, 10000 << (N-1) and
// 10000 << (N-2); crossing-out starts at i*i.
fn nsieve(m: usize) {
  let mut comp = vec![0u8; m + 1];
  let mut count = 0;
  let mut i = 2;
  while i <= m {
    if comp[i] == 0 {
      count += 1;
      let mut j = i * i;
      while j <= m { comp[j] = 1; j += i; }
    }
    i += 1;
  }
  println!("Primes up to {:8} {:8}", m, count);
}

fn main() {
  let n: usize = std::env::args().nth(1).map(|s| s.parse().unwrap()).unwrap_or(9);
  if n < 2 || n > 20 { return; }
  nsieve(10000 << n);
  nsieve(10000 << (n - 1));
  nsieve(10000 << (n - 2));
}
