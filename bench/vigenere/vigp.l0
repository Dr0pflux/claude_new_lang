// Parallel Vigenere solver (par over ciphertexts, ncpu() workers): IoC period detection, unigram initial key, then quadgram
// coordinate ascent with delta scoring (only windows touching the changed
// column are rescored). usage: vig quad.bin cipher.txt  -> one key per line.
// Helpers are ordinary functions; the compiler inlines them, so array range
// facts (p holds 0..25, q has 26^4 entries) still prove every index safe.

fn q4(q: [i16], p: [u8], s: i64) -> i64 {
  return q[((p[s] * 26 + p[s + 1]) * 26 + p[s + 2]) * 26 + p[s + 3]];
}

// smallest period (1..20) whose mean column IoC is >= 90% of the best
fn find_period(c: [u8], n: i64, cnt: mut [i32], ioc: mut [i64]) -> i64 {
  let mut bests = 0;
  let mut pp = 1;
  while pp <= 20 {
    let mut z = 0;
    while z < 26 * pp { cnt[z] = 0; z += 1; }
    let mut i = 0;
    while i < n { cnt[(i % pp) * 26 + c[i]] += 1; i += 1; }
    let mut num = 0;
    let mut den = 0;
    let mut col = 0;
    while col < pp {
      let mut l = 0;
      let mut nc = 0;
      while l < 26 { let f = cnt[col * 26 + l]; num += f * (f - 1); nc += f; l += 1; }
      den += nc * (nc - 1);
      col += 1;
    }
    let mut sc = 0;
    if den > 0 { sc = num * 10000 / den; }
    ioc[pp] = sc;
    if sc > bests { bests = sc; }
    pp += 1;
  }
  pp = 1;
  while pp <= 20 { if ioc[pp] * 10 >= bests * 9 { return pp; } pp += 1; }
  return 1;
}

// per column: the shift that maximizes correlation with English unigrams
fn initial_key(c: [u8], n: i64, per: i64, cnt: mut [i32], uni: [i32], key: mut [u8]) -> i64 {
  let mut z = 0;
  while z < 26 * per { cnt[z] = 0; z += 1; }
  let mut i = 0;
  while i < n { cnt[(i % per) * 26 + c[i]] += 1; i += 1; }
  let mut j = 0;
  while j < per {
    let mut bk = 0;
    let mut bv = -1;
    let mut k = 0;
    while k < 26 {
      let mut v = 0;
      let mut l = 0;
      while l < 26 { v += cnt[j * 26 + (l + k) % 26] * uni[l]; l += 1; }
      if v > bv { bv = v; bk = k; }
      k += 1;
    }
    key[j] = bk as u8;
    j += 1;
  }
  return 0;
}

// sum of quadgram scores of the windows touching column j (per >= 4: disjoint)
fn column_score(q: [i16], p: [u8], n: i64, per: i64, j: i64) -> i64 {
  let mut sc = 0;
  let mut i = j;
  while i < n {
    let mut s = i - 3;
    if s < 0 { s = 0; }
    let mut e = i;
    if e > n - 4 { e = n - 4; }
    while s <= e { sc += q4(q, p, s); s += 1; }
    i += per;
  }
  return sc;
}

fn full_score(q: [i16], p: [u8], n: i64) -> i64 {
  let mut sc = 0;
  let mut s = 0;
  while s <= n - 4 { sc += q4(q, p, s); s += 1; }
  return sc;
}

// solve one ciphertext already decoded into c[0..n): returns the period, key in key[]
fn solve(q: [i16], c: [u8], n: i64, p: mut [u8], cnt: mut [i32], ioc: mut [i64], uni: [i32], key: mut [u8]) -> i64 {
  let per = find_period(c, n, cnt, ioc);
  initial_key(c, n, per, cnt, uni, key);
  let mut i = 0;
  while i < n { p[i] = ((c[i] - key[i % per] + 26) % 26) as u8; i += 1; }
  let mut pass = 0;
  let mut improved = 1;
  while pass < 4 && improved != 0 {
    improved = 0;
    let mut j = 0;
    while j < per {
      let mut bestk: i64 = key[j];
      let mut bestsc = -9223372036854775807;
      let mut k = 0;
      while k < 26 {
        i = j;
        while i < n { p[i] = ((c[i] - k + 26) % 26) as u8; i += per; }
        let mut sc = 0;
        if per >= 4 { sc = column_score(q, p, n, per, j); }
        else { sc = full_score(q, p, n); }
        if sc > bestsc { bestsc = sc; bestk = k; }
        k += 1;
      }
      if bestk != key[j] { key[j] = bestk as u8; improved = 1; }
      i = j;
      while i < n { p[i] = ((c[i] - bestk + 26) % 26) as u8; i += per; }
      j += 1;
    }
    pass += 1;
  }
  return per;
}

fn main() -> i64 {
  let tab = file(1);
  let q = view16(tab);
  if len(q) < 456976 { return -1; }
  let ct = file(2);
  // index the lines (one ciphertext per line)
  let mut nt = 0;
  let mut i = 0;
  while i < len(ct) { if ct[i] == 10 { nt += 1; } i += 1; }
  if len(ct) > 0 && ct[len(ct) - 1] != 10 { nt += 1; }
  if nt < 1 { return 0; }
  let start = alloc64(nt + 1);
  let mut t = 0;
  i = 0;
  start[0] = 0;
  while i < len(ct) && t < nt { if ct[i] == 10 { t += 1; start[t] = i + 1; } i += 1; }
  if t < nt { start[nt] = len(ct) + 1; }
  let uni = alloc32(26);
  uni[0] = 8167; uni[1] = 1492; uni[2] = 2782; uni[3] = 4253; uni[4] = 12702;
  uni[5] = 2228; uni[6] = 2015; uni[7] = 6094; uni[8] = 6966; uni[9] = 153;
  uni[10] = 772; uni[11] = 4025; uni[12] = 2406; uni[13] = 6749; uni[14] = 7507;
  uni[15] = 1929; uni[16] = 95; uni[17] = 5987; uni[18] = 6327; uni[19] = 9056;
  uni[20] = 2758; uni[21] = 978; uni[22] = 2360; uni[23] = 150; uni[24] = 1974;
  uni[25] = 74;
  // per-worker scratch (each worker gets a private copy)
  let c = alloc8(4096);
  let p = alloc8(4096);
  let cnt = alloc32(520);
  let ioc = alloc64(21);
  let key = alloc8(32);
  // results, written by workers
  let keys = shared8(nt * 32);
  let klen = shared64(nt);
  let score = shared64(nt);
  let w = ncpu();
  par wk in 0..w {
    let mut tt = wk;
    while tt < nt {
      let mut n = 0;
      let mut pos = start[tt];
      while pos < len(ct) && ct[pos] != 10 {
        let ch = ct[pos];
        if ch >= 65 && ch <= 90 && n < 4096 { c[n] = (ch - 65) as u8; n += 1; }
        pos += 1;
      }
      if n >= 8 {
        let per = solve(q, c, n, p, cnt, ioc, uni, key);
        let mut j = 0;
        while j < per { keys[tt * 32 + j] = key[j]; j += 1; }
        klen[tt] = per;
        score[tt] = full_score(q, p, n);
      }
      tt += w;
    }
  }
  let mut total = 0;
  t = 0;
  while t < nt {
    if klen[t] > 0 {
      let mut j = 0;
      while j < klen[t] { putc(keys[t * 32 + j] + 65); j += 1; }
      putc(10);
      total += score[t];
    }
    t += 1;
  }
  return total;
}
