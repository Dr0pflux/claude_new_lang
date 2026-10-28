// Benchmarks Game k-nucleotide (same algorithm as knucleotide.c / .rs). usage: knucleotide FASTA
// Reads the THREE section of the FASTA file, packs it to 2-bit symbols (A=0 C=1 G=2 T=3) and counts
// k-mers in a hand-written open-addressing hash table: linear probing, multiplicative hash of the
// integer-encoded k-mer, 2^lg slots with 2^lg >= 2 * (number of possible distinct k-mers). Slot h is the
// word pair tab[2h] = k-mer code, tab[2h+1] = count (0 means the slot is empty).

fn put_int(x: i64) { if x >= 10 { put_int(x / 10); } putc(x % 10 + 48); }

// Offset just past the ">THREE" header line (or the end of the file if there is none).
fn find_three(inp: [u8]) -> i64 {
  let n = len(inp);
  let mut p = 0;
  while p + 6 <= n {
    if inp[p] == 62 && inp[p + 1] == 84 && inp[p + 2] == 72 && inp[p + 3] == 82 && inp[p + 4] == 69 && inp[p + 5] == 69 {
      while p < n && inp[p] != 10 { p += 1; }
      return p;
    }
    p += 1;
  }
  return n;
}

// log2 of the slot count for k-mers of length k in a sequence of m symbols.
fn table_lg(m: i64, k: i64) -> i64 {
  let mut distinct = m - k + 1;
  if 2 * k < 62 {
    let lim = 1 << (2 * k);
    if lim < distinct { distinct = lim; }
  }
  let mut lg = 4;
  while (1 << lg) < 2 * distinct { lg += 1; }
  return lg;
}

// Count every k-mer of seq[0..m) into tab (2^(64 - shift) slots).
fn build(seq: [u8], m: i64, k: i64, tab: mut [u64], shift: i64) {
  let one: u64 = 1;
  let kmask = (one << (2 * k)) - 1;
  let mask = (len(tab) / 2 - 1) as u64;
  let mut code: u64 = 0;
  let mut i = 0;
  while i < k - 1 { code = (code << 2) | seq[i]; i += 1; }
  while i < m {
    code = ((code << 2) | seq[i]) & kmask;
    let mut h = (code * 0x9E3779B97F4A7C15) >> shift;
    while true {
      let s = h * 2;
      if tab[s + 1] == 0 { tab[s] = code; tab[s + 1] = 1; break; }
      if tab[s] == code { tab[s + 1] += 1; break; }
      h = (h + 1) & mask;
    }
    i += 1;
  }
}

fn lookup(tab: [u64], code: u64, shift: i64) -> i64 {
  let mask = (len(tab) / 2 - 1) as u64;
  let mut h = (code * 0x9E3779B97F4A7C15) >> shift;
  while tab[h * 2 + 1] != 0 {
    if tab[h * 2] == code { return tab[h * 2 + 1] as i64; }
    h = (h + 1) & mask;
  }
  return 0;
}

// Frequencies of all k-mers (k <= 2), most frequent first, ties in alphabetical order.
fn frequencies(seq: [u8], m: i64, k: i64) {
  let total = m - k + 1;
  if total > 0 {
    let lg = table_lg(m, k);
    let tab = alloc<u64>(2 << lg);
    build(seq, m, k, tab, 64 - lg);
    let ek = alloc<u64>(1 << (2 * k));
    let ec = alloc<u64>(1 << (2 * k));
    let mut ne = 0;
    let mut j = 0;
    while j < len(tab) {
      if tab[j + 1] != 0 { ek[ne] = tab[j]; ec[ne] = tab[j + 1]; ne += 1; }
      j += 2;
    }
    let mut a = 1;
    while a < ne {
      let ck = ek[a];
      let cc = ec[a];
      let mut b = a;
      while b > 0 && (ec[b - 1] < cc || (ec[b - 1] == cc && ek[b - 1] > ck)) {
        ek[b] = ek[b - 1];
        ec[b] = ec[b - 1];
        b -= 1;
      }
      ek[b] = ck;
      ec[b] = cc;
      a += 1;
    }
    let letters = "ACGT";
    a = 0;
    while a < ne {
      let mut s = k;
      while s > 0 { s -= 1; putc(letters[(ek[a] >> (2 * s)) & 3]); }
      putc(32);
      let pct = (ec[a] as i64 * 100000 + total / 2) / total;
      put_int(pct / 1000);
      putc(46);
      putc(pct / 100 % 10 + 48);
      putc(pct / 10 % 10 + 48);
      putc(pct % 10 + 48);
      putc(10);
      a += 1;
    }
  }
  putc(10);
}

// Number of occurrences of the nucleotide string pat, printed as "count<TAB>pat".
fn count_kmer(seq: [u8], m: i64, enc: [u8], pat: [u8]) {
  let k = len(pat);
  let mut c = 0;
  if m >= k {
    let lg = table_lg(m, k);
    let tab = alloc<u64>(2 << lg);
    build(seq, m, k, tab, 64 - lg);
    let mut code: u64 = 0;
    let mut j = 0;
    while j < k { code = (code << 2) | enc[pat[j]]; j += 1; }
    c = lookup(tab, code, 64 - lg);
  }
  put_int(c);
  putc(9);
  write(pat);
  putc(10);
}

fn main() {
  let inp = file(1);
  let n = len(inp);
  let enc = alloc<u8>(256);
  let mut i = 0;
  while i < 256 { enc[i] = 255; i += 1; }
  enc[65] = 0; enc[67] = 1; enc[71] = 2; enc[84] = 3;
  enc[97] = 0; enc[99] = 1; enc[103] = 2; enc[116] = 3;
  let seq = alloc<u8>(n + 1);
  let mut m = 0;
  let mut p = find_three(inp);
  while p < n && inp[p] != 62 {
    let s = enc[inp[p]];
    if s != 255 { seq[m] = s; m += 1; }
    p += 1;
  }
  frequencies(seq, m, 1);
  frequencies(seq, m, 2);
  count_kmer(seq, m, enc, "GGT");
  count_kmer(seq, m, enc, "GGTA");
  count_kmer(seq, m, enc, "GGTATT");
  count_kmer(seq, m, enc, "GGTATTTTAATT");
  count_kmer(seq, m, enc, "GGTATTTTAATTTATAGT");
}
