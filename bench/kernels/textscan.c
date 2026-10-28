// Text statistics kernel (same algorithm as textscan.ck / textscan.rs)
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
int main(void) {
  long n = 1L << 20; uint8_t *t = malloc(n), *low = malloc(n);
  uint64_t x = 88172645463325252ULL;
  for (long i = 0; i < n; i++) { x ^= x << 13; x ^= x >> 7; x ^= x << 17; t[i] = (uint8_t)(32 + (x >> 58) * 3 / 2); }
  long sp = 0, up = 0, dig = 0;
  for (int r = 0; r < 300; r++) {
    for (long i = 0; i < n; i++) if (t[i] == 32) sp++;
    for (long i = 0; i < n; i++) if (t[i] >= 65 && t[i] <= 90) up++;
    for (long i = 0; i < n; i++) if (t[i] >= 48 && t[i] <= 57) dig += t[i];
    for (long i = 0; i < n; i++) low[i] = (t[i] >= 65 && t[i] <= 90) ? t[i] + 32 : t[i];
  }
  long h = 0; for (long i = 0; i < n; i++) h = h * 31 + low[i];
  printf("%ld\n%ld\n%ld\n%ld\n", sp, up, dig, h);
  return 0;
}
