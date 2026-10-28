#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#pragma STDC FP_CONTRACT OFF
int main(int argc, char **argv) {
  long n = 60000000 + argc - 1, sum = 0;
  for (long i = 0; i < n; i++) {
    long k = ((i >> 3) & 1023) + 3;
    long x = (i * 2654435761L) & 0x7fffffffffffL;
    sum += x / k + x % k;
  }
  printf("%ld\n", sum); return 0;
}
