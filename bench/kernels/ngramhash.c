#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#pragma STDC FP_CONTRACT OFF
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
  uint32_t *cnt = calloc(65536, 4);
  for (int r = 0; r < 40; r++)
    for (long i = 0; i < n - 2; i++) {
      long g = ((long)t[i] << 16) | ((long)t[i + 1] << 8) | t[i + 2];
      long h = ((g * 2654435761L) >> 16) & 65535;
      cnt[h] += 1;
    }
  uint64_t s = 0; int64_t nz = 0, mx = 0;
  for (long k = 0; k < 65536; k++) { s = s * 31 + cnt[k]; if (cnt[k] != 0) nz++; if (cnt[k] > mx) mx = cnt[k]; }
  printf("%lld\n%lld\n%lld\n", (long long)s, (long long)nz, (long long)mx);
  return 0;
}
