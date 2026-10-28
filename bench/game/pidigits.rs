// Benchmarks Game pi-digits (same algorithm as pidigits.ck / .c). usage: pidigits N
// Gibbons' unbounded spigot on a schoolbook bignum: base 2^32 limbs, a[0] = number of limbs, a[1..] =
// limbs (least significant first, no leading zero limb, every limb above a[0] is 0). The only big
// operations are multiply / add-multiple / subtract-multiple by a small number, comparison, and a
// quotient digit found by repeated subtraction. The usual accumulator r can go negative, so the
// program tracks s = r + 3 * numer instead, which never does:
//   term k:  s = s * (2k+1) + numer * (k-1);  denom *= 2k+1;  numer *= k
//   skip the term while 4 * numer > s;  digit d = s / denom, valid when (s + numer) / denom == d
//   emit d:  s = 10 * (s - d * denom);  numer *= 10
use std::io::Write;

// a *= c  (0 < c < 2^32)
fn mul_small(a: &mut [u32], c: u64) {
  let n = a[0] as usize;
  let mut carry = 0u64;
  for i in 1..=n {
    let p = a[i] as u64 * c + carry;
    a[i] = p as u32;
    carry = p >> 32;
  }
  if carry != 0 { a[n + 1] = carry as u32; a[0] = (n + 1) as u32; }
}

// a += b * c  (0 < c < 2^32)
fn addmul_small(a: &mut [u32], b: &[u32], c: u64) {
  let na = a[0] as usize;
  let nb = b[0] as usize;
  let mut carry = 0u64;
  let mut i = 1;
  while i <= nb {
    let p = a[i] as u64 + b[i] as u64 * c + carry;
    a[i] = p as u32;
    carry = p >> 32;
    i += 1;
  }
  while carry != 0 {
    let p = a[i] as u64 + carry;
    a[i] = p as u32;
    carry = p >> 32;
    i += 1;
  }
  let mut nn = na;
  if i - 1 > nn { nn = i - 1; }
  a[0] = nn as u32;
}

// a -= b * c  (requires a >= b * c; 0 < c < 2^32); the borrow out of each limb is (a[i] < subtrahend)
fn submul_small(a: &mut [u32], b: &[u32], c: u64) {
  let nb = b[0] as usize;
  let mut carry = 0u64;
  let mut i = 1;
  while i <= nb {
    let p = b[i] as u64 * c + carry;
    let lo = p & 4294967295;
    carry = p >> 32;
    let ai = a[i] as u64;
    a[i] = ai.wrapping_sub(lo) as u32;
    carry += (ai < lo) as u64;
    i += 1;
  }
  while carry != 0 {
    let ai = a[i] as u64;
    a[i] = ai.wrapping_sub(carry) as u32;
    carry = (ai < carry) as u64;
    i += 1;
  }
  let mut n = a[0] as usize;
  while n > 0 && a[n] == 0 { n -= 1; }
  a[0] = n as u32;
}

// -1, 0, 1
fn cmp_big(a: &[u32], b: &[u32]) -> i32 {
  let na = a[0] as usize;
  let nb = b[0] as usize;
  if na != nb { return if na < nb { -1 } else { 1 }; }
  let mut i = na;
  while i > 0 {
    if a[i] != b[i] { return if a[i] < b[i] { -1 } else { 1 }; }
    i -= 1;
  }
  0
}

fn copy_big(dst: &mut [u32], src: &[u32]) {
  let ns = src[0] as usize;
  let nd = dst[0] as usize;
  let mut i = 0;
  while i <= ns { dst[i] = src[i]; i += 1; }
  while i <= nd { dst[i] = 0; i += 1; }
}

// floor((s + extra * numer) / denom), by repeated subtraction
fn extract_digit(tmp: &mut [u32], s: &[u32], numer: &[u32], denom: &[u32], extra: u64) -> i64 {
  copy_big(tmp, s);
  if extra != 0 { addmul_small(tmp, numer, extra); }
  let mut d = 0;
  while cmp_big(tmp, denom) >= 0 { submul_small(tmp, denom, 1); d += 1; }
  d
}

fn main() {
  let n: usize = std::env::args().nth(1).map(|s| s.parse().unwrap()).unwrap_or(27);
  let out = std::io::stdout();
  let mut o = std::io::BufWriter::new(out.lock());
  let cap = 2 * n + 64;
  let mut numer = vec![0u32; cap];
  let mut s = vec![0u32; cap];
  let mut denom = vec![0u32; cap];
  let mut tmp = vec![0u32; cap];
  numer[0] = 1; numer[1] = 1;
  denom[0] = 1; denom[1] = 1;
  s[0] = 1; s[1] = 3;
  let mut k = 0u64;
  let mut i = 0;
  while i < n {
    k += 1;
    let k2 = 2 * k + 1;
    mul_small(&mut s, k2);
    if k > 1 { addmul_small(&mut s, &numer, k - 1); }
    mul_small(&mut denom, k2);
    mul_small(&mut numer, k);
    copy_big(&mut tmp, &numer);
    mul_small(&mut tmp, 4);
    if cmp_big(&tmp, &s) > 0 { continue; }
    let d = extract_digit(&mut tmp, &s, &numer, &denom, 0);
    if d != extract_digit(&mut tmp, &s, &numer, &denom, 1) { continue; }
    o.write_all(&[(d + 48) as u8]).unwrap();
    i += 1;
    if i % 10 == 0 { writeln!(o, "\t:{}", i).unwrap(); }
    submul_small(&mut s, &denom, d as u64);
    mul_small(&mut s, 10);
    mul_small(&mut numer, 10);
  }
  if n % 10 != 0 {
    for _ in n % 10..10 { o.write_all(b" ").unwrap(); }
    writeln!(o, "\t:{}", n).unwrap();
  }
  o.flush().unwrap();
}
