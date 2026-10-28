#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#pragma STDC FP_CONTRACT OFF
int main(int argc, char **argv) {
  long n = 1500000 + argc - 1, best = 0, arg = 0;
  for (long s = 1; s < n; s++) {
    long x = s, steps = 0;
    while (x != 1) { if ((x & 1) == 0) x = x >> 1; else x = 3 * x + 1; steps++; }
    if (steps > best) { best = steps; arg = s; }
  }
  printf("%ld\n%ld\n", arg, best); return 0;
}
