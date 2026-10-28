// Benchmarks Game mandelbrot (same algorithm as mandelbrot.ck / .rs). usage: mandelbrot N
#include <stdio.h>
#include <stdlib.h>
int main(int argc, char **argv) {
  long n = argc > 1 ? atol(argv[1]) : 200;
  printf("P4\n%ld %ld\n", n, n);
  unsigned char *row = malloc((n + 7) / 8);
  for (long y = 0; y < n; y++) {
    double ci = 2.0 * (double)y / (double)n - 1.0;
    long bits = 0;
    for (long x = 0; x < n; x++) {
      double cr = 2.0 * (double)x / (double)n - 1.5;
      double zr = 0, zi = 0, tr = 0, ti = 0;
      for (int i = 0; i < 50 && tr + ti <= 4.0; i++) {
        zi = 2.0 * zr * zi + ci;
        zr = tr - ti + cr;
        tr = zr * zr;
        ti = zi * zi;
      }
      bits <<= 1;
      if (tr + ti <= 4.0) bits |= 1;
      if (x % 8 == 7) { row[x / 8] = (unsigned char)bits; bits = 0; }
    }
    if (n % 8) row[n / 8] = (unsigned char)(bits << (8 - n % 8));
    fwrite(row, 1, (n + 7) / 8, stdout);
  }
  return 0;
}
