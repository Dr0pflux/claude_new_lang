#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#pragma STDC FP_CONTRACT OFF
int main(int argc, char **argv) {
  long n = 768 + argc - 1;
  double *a = malloc(n * n * 8), *b = malloc(n * n * 8), *c = calloc(n * n, 8);
  for (long i = 0; i < n * n; i++) { a[i] = (double)((i * 7 + 3) % 13) * 0.25; b[i] = (double)((i * 5 + 1) % 11) * 0.5; }
  for (long i = 0; i < n; i++) for (long k = 0; k < n; k++) {
    double aik = a[i * n + k];
    for (long j = 0; j < n; j++) c[i * n + j] += aik * b[k * n + j];
  }
  double s = 0.0; for (long i = 0; i < n * n; i++) s += c[i];
  printf("%lld\n%lld\n", (long long)s, (long long)c[n * n - 1]); return 0;
}
