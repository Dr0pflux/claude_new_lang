#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#pragma STDC FP_CONTRACT OFF
static long count(const uint8_t *t, long n, const char *p) {
  long m = strlen(p), cnt = 0;
  for (long i = 0; i + m <= n; i++) {
    long j = 0;
    while (j < m && t[i + j] == (uint8_t)p[j]) j++;
    if (j == m) cnt++;
  }
  return cnt;
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
  long s1 = 0, s2 = 0, s3 = 0, s4 = 0, s5 = 0;
  for (int r = 0; r < 10; r++) {
    s1 += count(t, n, "the"); s2 += count(t, n, "ab"); s3 += count(t, n, "e a"); s4 += count(t, n, "qxz"); s5 += count(t, n, "ing.");
  }
  printf("%ld\n%ld\n%ld\n%ld\n%ld\n", s1, s2, s3, s4, s5);
  return 0;
}
