// Benchmarks Game binary-trees, node-pool version (same algorithm as binarytrees.ck / .rs). usage: binarytrees N
#include <stdio.h>
#include <stdlib.h>
#define CAP 8388608
static int lft[CAP], rgt[CAP];
static long top;
static long make(long d) {
  long me = top++;
  if (d > 0) { lft[me] = (int)make(d - 1); rgt[me] = (int)make(d - 1); }
  else { lft[me] = -1; rgt[me] = -1; }
  return me;
}
static long check(long t) {
  long l = lft[t];
  if (l < 0) return 1;
  return 1 + check(l) + check(rgt[t]);
}
int main(int argc, char **argv) {
  long n = argc > 1 ? atol(argv[1]) : 10;
  long maxd = n < 6 ? 6 : n;
  if (maxd > 21) return 0;
  top = 0;
  long st = make(maxd + 1);
  printf("stretch tree of depth %ld\t check: %ld\n", maxd + 1, check(st));
  top = 0;
  long longlived = make(maxd);
  long base = top;
  for (long d = 4; d <= maxd; d += 2) {
    long iters = 1L << (maxd - d + 4), chk = 0;
    for (long i = 0; i < iters; i++) { top = base; chk += check(make(d)); }
    printf("%ld\t trees of depth %ld\t check: %ld\n", iters, d, chk);
  }
  printf("long lived tree of depth %ld\t check: %ld\n", maxd, check(longlived));
  return 0;
}
