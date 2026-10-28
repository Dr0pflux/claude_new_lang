#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#pragma STDC FP_CONTRACT OFF
static long lev(const uint8_t *t, long o1, long la, long o2, long lb, long *row) {
  for (long j = 0; j <= lb; j++) row[j] = j;
  for (long i = 1; i <= la; i++) {
    long diag = row[0]; row[0] = i;
    for (long j = 1; j <= lb; j++) {
      long up = row[j];
      long cost = t[o1 + i - 1] != t[o2 + j - 1] ? 1 : 0;
      long v = diag + cost;
      if (row[j - 1] + 1 < v) v = row[j - 1] + 1;
      if (up + 1 < v) v = up + 1;
      row[j] = v; diag = up;
    }
  }
  return row[lb];
}
static void gen(uint8_t *t, long n) {
  uint64_t x = 88172645463325252ULL;
  for (long i = 0; i < n; i++) {
    x ^= x << 13; x ^= x >> 7; x ^= x << 17;
    long v = (long)(x >> 58), c;
    if (v < 44) c = 97 + v % 26; else if (v < 54) c = 32; else if (v < 56) c = 10;
    else if (v < 58) c = 46; else if (v < 60) c = 44; else if (v < 62) c = 65 + v % 26; else c = 48 + v % 10;
    t[i] = (uint8_t)c;
  }
}
int main(int argc, char **argv) {
  long n = 4194304 + argc - 1; uint8_t *t = malloc(n);
  gen(t, n);
  long row[32], tot = 0, x = 0;
  for (long p = 0; p < 1000000; p++) {
    long o1 = (p * 40503) % (n - 32), o2 = (p * 65537 + 12345) % (n - 32);
    long la = 6 + p % 8, lb = 6 + (p >> 3) % 8;
    long d = lev(t, o1, la, o2, lb, row);
    tot += d; x = x ^ (d << (p & 31));
  }
  printf("%ld\n%ld\n", tot, x);
  return 0;
}
