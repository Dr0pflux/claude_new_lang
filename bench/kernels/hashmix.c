#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#pragma STDC FP_CONTRACT OFF
int main(int argc, char **argv) {
  long n = 100000000 + argc - 1;
  uint64_t x = 88172645463325252ULL, h = 14695981039346656037ULL;
  for (long i = 0; i < n; i++) {
    x ^= x << 13; x ^= x >> 7; x ^= x << 17;
    h ^= x & 255;
    h *= 1099511628211ULL;
    h = ((h << 5) | (h >> 59)) ^ (x * 0x9E3779B97F4A7C15ULL);
  }
  printf("%llu\n", (unsigned long long)h); return 0;
}
