#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#pragma STDC FP_CONTRACT OFF
int main(int argc, char **argv) {
  long n = 40000000 + argc - 1; uint8_t *c = calloc(n, 1);
  for (long i = 2; i * i < n; i++) if (c[i] == 0) for (long j = i * i; j < n; j += i) c[j] = 1;
  long cnt = 0; for (long i = 2; i < n; i++) if (c[i] == 0) cnt++;
  printf("%ld\n", cnt); return 0;
}
