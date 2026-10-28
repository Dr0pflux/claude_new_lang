#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#pragma STDC FP_CONTRACT OFF
int main(int argc, char **argv) {
  long n = 2600 + argc - 1, sum = 0;
  for (long i = 1; i < n; i++) for (long j = 1; j < n; j++) {
    long a = i, b = j;
    while (b != 0) { long t = a % b; a = b; b = t; }
    sum += a;
  }
  printf("%ld\n", sum); return 0;
}
