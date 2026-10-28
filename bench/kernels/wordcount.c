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
  long lines = 0, words = 0, chars = 0;
  for (int r = 0; r < 20; r++) {
    int inw = 0;
    for (long i = 0; i < n; i++) {
      uint8_t c = t[i];
      chars++;
      if (c == 10) lines++;
      if (c == 32 || c == 10 || c == 9) inw = 0; else { if (inw == 0) words++; inw = 1; }
    }
  }
  printf("%ld\n%ld\n%ld\n", lines, words, chars);
  return 0;
}
