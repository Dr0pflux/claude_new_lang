#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#pragma STDC FP_CONTRACT OFF
int main(int argc, char **argv) {
  long n = 262144 + argc - 1; int64_t *a = malloc(n * 8);
  for (long i = 0; i < n; i++) a[i] = (i * 7) % 1000 - 500;
  for (int r = 0; r < 1500; r++) for (long i = 1; i < n; i++) a[i] = (int64_t)((uint64_t)a[i] + (uint64_t)a[i - 1]);
  uint64_t s = 0; for (long i = 0; i < n; i++) s = s * 31 + (uint64_t)a[i];
  printf("%lld\n%lld\n", (long long)s, (long long)a[n - 1]); return 0;
}
