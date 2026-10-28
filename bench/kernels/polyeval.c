#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#pragma STDC FP_CONTRACT OFF
int main(int argc, char **argv) {
  long n = 4096 + argc - 1; double co[17];
  double *x = malloc(n * 8), *y = malloc(n * 8);
  for (long k = 0; k < 17; k++) co[k] = 1.0 / (double)(k + 1);
  for (long i = 0; i < n; i++) x[i] = (double)((i * 37) % 1024) / 1024.0 - 0.5;
  double acc = 0.0;
  for (long p = 0; p < 36000; p++) {
    double s = (double)(p & 63) * 0.001;
    for (long i = 0; i < n; i++) {
      double t = x[i] + s, r = co[16];
      for (long k = 0; k < 16; k++) r = r * t + co[15 - k];
      y[i] = r;
    }
    for (long i = 0; i < n; i++) acc += y[i];
  }
  printf("%lld\n", (long long)(acc * 1000.0)); return 0;
}
