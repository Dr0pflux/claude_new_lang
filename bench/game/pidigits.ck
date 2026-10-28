// Benchmarks Game pi-digits (same algorithm as pidigits.c / .rs). usage: pidigits N
// Gibbons' unbounded spigot on a schoolbook bignum: base 2^32 limbs, a[0] = number of limbs, a[1..] =
// limbs (least significant first, no leading zero limb, every limb above a[0] is 0). The only big
// operations are multiply / add-multiple / subtract-multiple by a small number, comparison, and a
// quotient digit found by repeated subtraction. The usual accumulator r can go negative, so the
// program tracks s = r + 3 * numer instead, which never does:
//   term k:  s = s * (2k+1) + numer * (k-1);  denom *= 2k+1;  numer *= k
//   skip the term while 4 * numer > s;  digit d = s / denom, valid when (s + numer) / denom == d
//   emit d:  s = 10 * (s - d * denom);  numer *= 10
fn arg_int(s: [u8]) -> i64 {
  let mut n = 0; let mut k = 0;
  while k < len(s) && s[k] >= 48 && s[k] <= 57 { n = n * 10 + (s[k] - 48); k += 1; }
  return n;
}

// a *= c  (0 < c < 2^32)
fn mul_small(a: mut [u32], c: u64) {
  let n = a[0] as i64;
  let mut carry: u64 = 0;
  let mut i = 1;
  while i <= n {
    let p = a[i] * c + carry;
    a[i] = p as u32;
    carry = p >> 32;
    i += 1;
  }
  if carry != 0 { a[n + 1] = carry as u32; a[0] = (n + 1) as u32; }
}

// a += b * c  (0 < c < 2^32)
fn addmul_small(a: mut [u32], b: [u32], c: u64) {
  let na = a[0] as i64;
  let nb = b[0] as i64;
  let mut carry: u64 = 0;
  let mut i = 1;
  while i <= nb {
    let p = a[i] + b[i] * c + carry;
    a[i] = p as u32;
    carry = p >> 32;
    i += 1;
  }
  while carry != 0 {
    let p = a[i] + carry;
    a[i] = p as u32;
    carry = p >> 32;
    i += 1;
  }
  let mut nn = na;
  if i - 1 > nn { nn = i - 1; }
  a[0] = nn as u32;
}

// a -= b * c  (requires a >= b * c; 0 < c < 2^32); the borrow out of each limb is (a[i] < subtrahend)
fn submul_small(a: mut [u32], b: [u32], c: u64) {
  let nb = b[0] as i64;
  let mut carry: u64 = 0;
  let mut i = 1;
  while i <= nb {
    let p = b[i] * c + carry;
    let lo = p & 4294967295;
    carry = p >> 32;
    let ai: u64 = a[i];
    a[i] = (ai - lo) as u32;
    carry += (ai < lo) as u64;
    i += 1;
  }
  while carry != 0 {
    let ai: u64 = a[i];
    a[i] = (ai - carry) as u32;
    carry = (ai < carry) as u64;
    i += 1;
  }
  let mut n = a[0] as i64;
  while n > 0 && a[n] == 0 { n -= 1; }
  a[0] = n as u32;
}

// -1, 0, 1
fn cmp_big(a: [u32], b: [u32]) -> i64 {
  let na = a[0] as i64;
  let nb = b[0] as i64;
  if na != nb { if na < nb { return -1; } return 1; }
  let mut i = na;
  while i > 0 {
    if a[i] != b[i] { if a[i] < b[i] { return -1; } return 1; }
    i -= 1;
  }
  return 0;
}

fn copy_big(dst: mut [u32], src: [u32]) {
  let ns = src[0] as i64;
  let nd = dst[0] as i64;
  let mut i = 0;
  while i <= ns { dst[i] = src[i]; i += 1; }
  while i <= nd { dst[i] = 0; i += 1; }
}

// floor((s + extra * numer) / denom), by repeated subtraction
fn extract_digit(tmp: mut [u32], s: [u32], numer: [u32], denom: [u32], extra: u64) -> i64 {
  copy_big(tmp, s);
  if extra != 0 { addmul_small(tmp, numer, extra); }
  let mut d = 0;
  while cmp_big(tmp, denom) >= 0 { submul_small(tmp, denom, 1); d += 1; }
  return d;
}

fn main() {
  let a1 = argv(1);
  let n = arg_int(a1);
  let cap = 2 * n + 64;
  let numer = alloc<u32>(cap);
  let s = alloc<u32>(cap);
  let denom = alloc<u32>(cap);
  let tmp = alloc<u32>(cap);
  numer[0] = 1; numer[1] = 1;
  denom[0] = 1; denom[1] = 1;
  s[0] = 1; s[1] = 3;
  let mut k = 0;
  let mut i = 0;
  while i < n {
    k += 1;
    let k2 = (2 * k + 1) as u64;
    mul_small(s, k2);
    if k > 1 { addmul_small(s, numer, (k - 1) as u64); }
    mul_small(denom, k2);
    mul_small(numer, k as u64);
    copy_big(tmp, numer);
    mul_small(tmp, 4);
    if cmp_big(tmp, s) > 0 { continue; }
    let d = extract_digit(tmp, s, numer, denom, 0);
    if d != extract_digit(tmp, s, numer, denom, 1) { continue; }
    putc(d + 48);
    i += 1;
    if i % 10 == 0 { write("\t:"); print(i); }
    submul_small(s, denom, d as u64);
    mul_small(s, 10);
    mul_small(numer, 10);
  }
  if n % 10 != 0 {
    let mut pad = n % 10;
    while pad < 10 { putc(32); pad += 1; }
    write("\t:");
    print(n);
  }
}
