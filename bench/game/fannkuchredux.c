// Benchmarks Game fannkuch-redux (same algorithm as fannkuchredux.cock / .rs). usage: fannkuchredux N
#include <stdio.h>
#include <stdlib.h>
int main(int argc, char **argv) {
  long n = argc > 1 ? atol(argv[1]) : 7;
  long perm[16], perm1[16], count[16];
  for (long i = 0; i < n; i++) perm1[i] = i;
  long maxflips = 0, checksum = 0, permcount = 0, r = n;
  for (;;) {
    while (r != 1) { count[r - 1] = r; r--; }
    for (long i = 0; i < n; i++) perm[i] = perm1[i];
    long flips = 0, k = perm[0];
    while (k != 0) {
      for (long lo = 0, hi = k; lo < hi; lo++, hi--) { long t = perm[lo]; perm[lo] = perm[hi]; perm[hi] = t; }
      flips++;
      k = perm[0];
    }
    if (flips > maxflips) maxflips = flips;
    checksum += permcount % 2 == 0 ? flips : -flips;
    int done = 1;
    while (r != n) {
      long p0 = perm1[0];
      for (long i = 0; i < r; i++) perm1[i] = perm1[i + 1];
      perm1[r] = p0;
      if (--count[r] > 0) { done = 0; break; }
      r++;
    }
    if (done) break;
    permcount++;
  }
  printf("%ld\nPfannkuchen(%ld) = %ld\n", checksum, n, maxflips);
  return 0;
}
