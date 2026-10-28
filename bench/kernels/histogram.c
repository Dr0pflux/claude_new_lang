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
  int64_t *cnt = calloc(256, 8);
  for (int r = 0; r < 80; r++) for (long i = 0; i < n; i++) cnt[t[i]] += 1;
  uint64_t s = 0; int64_t mx = 0, mb = 0;
  for (long b = 0; b < 256; b++) { s = s * 31 + (uint64_t)cnt[b]; if (cnt[b] > mx) { mx = cnt[b]; mb = b; } }
  printf("%lld\n%lld\n%lld\n", (long long)s, (long long)mx, (long long)mb);
  return 0;
}
