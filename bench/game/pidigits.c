// Benchmarks Game pi-digits (same algorithm as pidigits.ck / .rs). usage: pidigits N
// Gibbons' unbounded spigot on a schoolbook bignum: base 2^32 limbs, a[0] = number of limbs, a[1..] =
// limbs (least significant first, no leading zero limb, every limb above a[0] is 0). The only big
// operations are multiply / add-multiple / subtract-multiple by a small number, comparison, and a
// quotient digit found by repeated subtraction. The usual accumulator r can go negative, so the
// program tracks s = r + 3 * numer instead, which never does:
//   term k:  s = s * (2k+1) + numer * (k-1);  denom *= 2k+1;  numer *= k
//   skip the term while 4 * numer > s;  digit d = s / denom, valid when (s + numer) / denom == d
//   emit d:  s = 10 * (s - d * denom);  numer *= 10
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

// a *= c  (0 < c < 2^32)
static void mul_small(uint32_t *a, uint64_t c) {
  long n = a[0];
  uint64_t carry = 0;
  for (long i = 1; i <= n; i++) {
    uint64_t p = a[i] * c + carry;
    a[i] = (uint32_t)p;
    carry = p >> 32;
  }
  if (carry != 0) { a[n + 1] = (uint32_t)carry; a[0] = (uint32_t)(n + 1); }
}

// a += b * c  (0 < c < 2^32)
static void addmul_small(uint32_t *a, const uint32_t *b, uint64_t c) {
  long na = a[0], nb = b[0];
  uint64_t carry = 0;
  long i = 1;
  for (; i <= nb; i++) {
    uint64_t p = a[i] + b[i] * c + carry;
    a[i] = (uint32_t)p;
    carry = p >> 32;
  }
  while (carry != 0) {
    uint64_t p = a[i] + carry;
    a[i] = (uint32_t)p;
    carry = p >> 32;
    i++;
  }
  long nn = na;
  if (i - 1 > nn) nn = i - 1;
  a[0] = (uint32_t)nn;
}

// a -= b * c  (requires a >= b * c; 0 < c < 2^32); the borrow out of each limb is (a[i] < subtrahend)
static void submul_small(uint32_t *a, const uint32_t *b, uint64_t c) {
  long nb = b[0];
  uint64_t carry = 0;
  long i = 1;
  for (; i <= nb; i++) {
    uint64_t p = b[i] * c + carry;
    uint64_t lo = p & 4294967295ull;
    carry = p >> 32;
    uint64_t ai = a[i];
    a[i] = (uint32_t)(ai - lo);
    carry += ai < lo;
  }
  while (carry != 0) {
    uint64_t ai = a[i];
    a[i] = (uint32_t)(ai - carry);
    carry = ai < carry;
    i++;
  }
  long n = a[0];
  while (n > 0 && a[n] == 0) n--;
  a[0] = (uint32_t)n;
}

// -1, 0, 1
static int cmp_big(const uint32_t *a, const uint32_t *b) {
  long na = a[0], nb = b[0];
  if (na != nb) return na < nb ? -1 : 1;
  for (long i = na; i > 0; i--) {
    if (a[i] != b[i]) return a[i] < b[i] ? -1 : 1;
  }
  return 0;
}

static void copy_big(uint32_t *dst, const uint32_t *src) {
  long ns = src[0], nd = dst[0];
  long i = 0;
  for (; i <= ns; i++) dst[i] = src[i];
  for (; i <= nd; i++) dst[i] = 0;
}

// floor((s + extra * numer) / denom), by repeated subtraction
static long extract_digit(uint32_t *tmp, const uint32_t *s, const uint32_t *numer, const uint32_t *denom, uint64_t extra) {
  copy_big(tmp, s);
  if (extra != 0) addmul_small(tmp, numer, extra);
  long d = 0;
  while (cmp_big(tmp, denom) >= 0) { submul_small(tmp, denom, 1); d++; }
  return d;
}

int main(int argc, char **argv) {
  long n = argc > 1 ? atol(argv[1]) : 27;
  long cap = 2 * n + 64;
  uint32_t *numer = calloc(cap, 4), *s = calloc(cap, 4), *denom = calloc(cap, 4), *tmp = calloc(cap, 4);
  numer[0] = 1; numer[1] = 1;
  denom[0] = 1; denom[1] = 1;
  s[0] = 1; s[1] = 3;
  long k = 0, i = 0;
  while (i < n) {
    k++;
    uint64_t k2 = (uint64_t)(2 * k + 1);
    mul_small(s, k2);
    if (k > 1) addmul_small(s, numer, (uint64_t)(k - 1));
    mul_small(denom, k2);
    mul_small(numer, (uint64_t)k);
    copy_big(tmp, numer);
    mul_small(tmp, 4);
    if (cmp_big(tmp, s) > 0) continue;
    long d = extract_digit(tmp, s, numer, denom, 0);
    if (d != extract_digit(tmp, s, numer, denom, 1)) continue;
    putchar((int)(d + '0'));
    i++;
    if (i % 10 == 0) printf("\t:%ld\n", i);
    submul_small(s, denom, (uint64_t)d);
    mul_small(s, 10);
    mul_small(numer, 10);
  }
  if (n % 10 != 0) {
    for (long pad = n % 10; pad < 10; pad++) putchar(' ');
    printf("\t:%ld\n", n);
  }
  return 0;
}
