// Benchmarks Game fasta (same algorithm as fasta.cock / .rs). usage: fasta N
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static const char *ALU = "GGCCGGGCGCGGTGGCTCACGCCTGTAATCCCAGCACTTTGGGAGGCCGAGGCGGGCGGATCACCTGAGGTCAGGAGTTCGAGACCAGCCTGGCCAACATGGTGAAACCCCGTCTCTACTAAAAATACAAAAATTAGCCGGGCGTGGTGGCGCGCGCCTGTAATCCCAGCTACTCGGGAGGCTGAGGCAGGAGAATCGCTTGAACCCGGGAGGCGGAGGTTGCAGTGAGCCGAGATCGCGCCACTGCACTCCAGCCTGGGCGACAGAGCGAGACTCCGTCTCAAAAA";
#define IM 139968
#define IA 3877
#define IC 29573
static long last = 42;
static char line[61];
static double cum[16];
static char chars[16];
static void repeat_fasta(long n) {
  long k = 0, len = (long)strlen(ALU);
  while (n > 0) {
    long m = n < 60 ? n : 60;
    for (long i = 0; i < m; i++) { line[i] = ALU[k]; if (++k == len) k = 0; }
    line[m] = '\n';
    fwrite(line, 1, m + 1, stdout);
    n -= m;
  }
}
static void random_fasta(long n, long nc) {
  while (n > 0) {
    long m = n < 60 ? n : 60;
    for (long i = 0; i < m; i++) {
      last = (last * IA + IC) % IM;
      double r = (double)last / 139968.0;
      long c = 0;
      while (c < nc - 1 && cum[c] <= r) c++;
      line[i] = chars[c];
    }
    line[m] = '\n';
    fwrite(line, 1, m + 1, stdout);
    n -= m;
  }
}
static void setup(const char *cs, const double *p) {
  double s = 0;
  for (long i = 0; cs[i]; i++) { s += p[i]; cum[i] = s; chars[i] = cs[i]; }
}
int main(int argc, char **argv) {
  long n = argc > 1 ? atol(argv[1]) : 1000;
  double iub[15] = {0.27, 0.12, 0.12, 0.27, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02};
  double hs[4] = {0.3029549426680, 0.1979883004921, 0.1975473066391, 0.3015094502008};
  fputs(">ONE Homo sapiens alu\n", stdout);
  repeat_fasta(2 * n);
  fputs(">TWO IUB ambiguity codes\n", stdout);
  setup("acgtBDHKMNRSVWY", iub);
  random_fasta(3 * n, 15);
  fputs(">THREE Homo sapiens frequency\n", stdout);
  setup("acgt", hs);
  random_fasta(5 * n, 4);
  return 0;
}
