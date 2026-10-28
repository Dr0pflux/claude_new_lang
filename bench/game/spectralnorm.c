// Benchmarks Game spectral-norm (same algorithm as spectralnorm.cock / .rs). usage: spectralnorm N
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
static double a(long i, long j) { return 1.0 / (double)((i + j) * (i + j + 1) / 2 + i + 1); }
static void av(const double *v, double *o, long n) {
  for (long i = 0; i < n; i++) { double s = 0; for (long j = 0; j < n; j++) s += a(i, j) * v[j]; o[i] = s; }
}
static void atv(const double *v, double *o, long n) {
  for (long i = 0; i < n; i++) { double s = 0; for (long j = 0; j < n; j++) s += a(j, i) * v[j]; o[i] = s; }
}
static void atav(const double *v, double *o, double *t, long n) { av(v, t, n); atv(t, o, n); }
int main(int argc, char **argv) {
  long n = argc > 1 ? atol(argv[1]) : 100;
  double *u = malloc(8 * n), *v = malloc(8 * n), *t = malloc(8 * n);
  for (long i = 0; i < n; i++) u[i] = 1;
  for (int i = 0; i < 10; i++) { atav(u, v, t, n); atav(v, u, t, n); }
  double vbv = 0, vv = 0;
  for (long i = 0; i < n; i++) { vbv += u[i] * v[i]; vv += v[i] * v[i]; }
  printf("%.9f\n", sqrt(vbv / vv));
  return 0;
}
