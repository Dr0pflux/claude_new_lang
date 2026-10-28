#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#pragma STDC FP_CONTRACT OFF
static long place(long r, long n, uint8_t *c, uint8_t *d1, uint8_t *d2) {
  if (r == n) return 1;
  long cnt = 0;
  for (long col = 0; col < n; col++) {
    if (c[col] == 0 && d1[r + col] == 0 && d2[r - col + n] == 0) {
      c[col] = 1; d1[r + col] = 1; d2[r - col + n] = 1;
      cnt += place(r + 1, n, c, d1, d2);
      c[col] = 0; d1[r + col] = 0; d2[r - col + n] = 0;
    }
  }
  return cnt;
}
int main(int argc, char **argv) {
  long n = 13 + argc - 1; uint8_t c[64] = {0}, d1[64] = {0}, d2[64] = {0};
  printf("%ld\n", place(0, n, c, d1, d2)); return 0;
}
