#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#pragma STDC FP_CONTRACT OFF
static void merge(const int64_t *src, int64_t *dst, long lo, long mid, long hi) {
  long i = lo, j = mid, o = lo;
  while (i < mid && j < hi) { if (src[j] < src[i]) dst[o] = src[j++]; else dst[o] = src[i++]; o++; }
  while (i < mid) dst[o++] = src[i++];
  while (j < hi) dst[o++] = src[j++];
}
static void pass(const int64_t *src, int64_t *dst, long n, long w) {
  for (long lo = 0; lo < n; lo += 2 * w) {
    long mid = lo + w; if (mid > n) mid = n;
    long hi = lo + 2 * w; if (hi > n) hi = n;
    merge(src, dst, lo, mid, hi);
  }
}
static void chk(const int64_t *a, long n) {
  uint64_t s = 0; int ok = 1;
  for (long i = 0; i < n; i++) { s = s * 31 + (uint64_t)a[i]; if (i > 0 && a[i - 1] > a[i]) ok = 0; }
  printf("%lld\n%d\n%lld\n%lld\n", (long long)s, ok, (long long)a[0], (long long)a[n - 1]);
}
int main(int argc, char **argv) {
  long n = 2000000 + argc - 1; int64_t *a = malloc(n * 8), *b = malloc(n * 8);
  uint64_t x = 88172645463325252ULL;
  for (long i = 0; i < n; i++) { x ^= x << 13; x ^= x >> 7; x ^= x << 17; a[i] = (int64_t)(x >> 20); }
  for (long lo = 0; lo < n; lo += 16) {
    long hi = lo + 16; if (hi > n) hi = n;
    for (long i = lo + 1; i < hi; i++) {
      int64_t v = a[i]; long j = i - 1;
      while (j >= lo && a[j] > v) { a[j + 1] = a[j]; j--; }
      a[j + 1] = v;
    }
  }
  long w = 16; int flip = 0;
  while (w < n) { if (flip == 0) pass(a, b, n, w); else pass(b, a, n, w); flip = 1 - flip; w *= 2; }
  if (flip == 0) chk(a, n); else chk(b, n);
  return 0;
}
