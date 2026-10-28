// Benchmarks Game nsieve (same algorithm as nsieve.ck / .rs). usage: nsieve N
// Sieve of Eratosthenes over a byte array of "is composite" flags, for 10000 << N, 10000 << (N-1) and
// 10000 << (N-2); crossing-out starts at i*i.
#include <stdio.h>
#include <stdlib.h>

static void nsieve(long m) {
  unsigned char *comp = calloc(m + 1, 1);
  long count = 0;
  for (long i = 2; i <= m; i++) {
    if (comp[i] == 0) {
      count++;
      for (long j = i * i; j <= m; j += i) comp[j] = 1;
    }
  }
  free(comp);
  printf("Primes up to %8ld %8ld\n", m, count);
}

int main(int argc, char **argv) {
  long n = argc > 1 ? atol(argv[1]) : 9;
  if (n < 2 || n > 20) return 0;
  nsieve(10000L << n);
  nsieve(10000L << (n - 1));
  nsieve(10000L << (n - 2));
  return 0;
}
