// Benchmarks Game k-nucleotide (same algorithm as knucleotide.ck / .c). usage: knucleotide FASTA
// Reads the THREE section of the FASTA file, packs it to 2-bit symbols (A=0 C=1 G=2 T=3) and counts
// k-mers in a hand-written open-addressing hash table: linear probing, multiplicative hash of the
// integer-encoded k-mer, 2^lg slots with 2^lg >= 2 * (number of possible distinct k-mers). Slot h is the
// word pair tab[2h] = k-mer code, tab[2h+1] = count (0 means the slot is empty).
use std::io::Write;

const GOLD: u64 = 0x9E3779B97F4A7C15;

// Offset just past the ">THREE" header line (or the end of the file if there is none).
fn find_three(inp: &[u8]) -> usize {
  let n = inp.len();
  let mut p = 0;
  while p + 6 <= n {
    if inp[p] == b'>' && inp[p + 1] == b'T' && inp[p + 2] == b'H' && inp[p + 3] == b'R' && inp[p + 4] == b'E' && inp[p + 5] == b'E' {
      while p < n && inp[p] != b'\n' { p += 1; }
      return p;
    }
    p += 1;
  }
  n
}

// log2 of the slot count for k-mers of length k in a sequence of m symbols.
fn table_lg(m: usize, k: usize) -> u32 {
  let mut distinct = m as i64 - k as i64 + 1;
  if 2 * k < 62 {
    let lim = 1i64 << (2 * k);
    if lim < distinct { distinct = lim; }
  }
  let mut lg = 4;
  while (1i64 << lg) < 2 * distinct { lg += 1; }
  lg
}

// Count every k-mer of seq[..m] into tab (2^(64 - shift) slots).
fn build(seq: &[u8], m: usize, k: usize, tab: &mut [u64], shift: u32) {
  let kmask = (1u64 << (2 * k)) - 1;
  let mask = (tab.len() / 2 - 1) as u64;
  let mut code = 0u64;
  let mut i = 0;
  while i + 1 < k { code = (code << 2) | seq[i] as u64; i += 1; }
  while i < m {
    code = ((code << 2) | seq[i] as u64) & kmask;
    let mut h = code.wrapping_mul(GOLD) >> shift;
    loop {
      let s = (h * 2) as usize;
      if tab[s + 1] == 0 { tab[s] = code; tab[s + 1] = 1; break; }
      if tab[s] == code { tab[s + 1] += 1; break; }
      h = (h + 1) & mask;
    }
    i += 1;
  }
}

fn lookup(tab: &[u64], code: u64, shift: u32) -> i64 {
  let mask = (tab.len() / 2 - 1) as u64;
  let mut h = code.wrapping_mul(GOLD) >> shift;
  while tab[(h * 2 + 1) as usize] != 0 {
    if tab[(h * 2) as usize] == code { return tab[(h * 2 + 1) as usize] as i64; }
    h = (h + 1) & mask;
  }
  0
}

// Frequencies of all k-mers (k <= 2), most frequent first, ties in alphabetical order.
fn frequencies<W: Write>(o: &mut W, seq: &[u8], m: usize, k: usize) {
  let total = m as i64 - k as i64 + 1;
  if total > 0 {
    let lg = table_lg(m, k);
    let mut tab = vec![0u64; 2usize << lg];
    build(seq, m, k, &mut tab, 64 - lg);
    let mut ek = [0u64; 16];
    let mut ec = [0u64; 16];
    let mut ne = 0;
    let mut j = 0;
    while j < tab.len() {
      if tab[j + 1] != 0 { ek[ne] = tab[j]; ec[ne] = tab[j + 1]; ne += 1; }
      j += 2;
    }
    for a in 1..ne {
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
    }
    let letters = b"ACGT";
    for a in 0..ne {
      let mut name = [0u8; 2];
      for s in 0..k { name[s] = letters[((ek[a] >> (2 * (k - 1 - s))) & 3) as usize]; }
      let pct = (ec[a] as i64 * 100000 + total / 2) / total;
      writeln!(o, "{} {}.{:03}", std::str::from_utf8(&name[..k]).unwrap(), pct / 1000, pct % 1000).unwrap();
    }
  }
  writeln!(o).unwrap();
}

// Number of occurrences of the nucleotide string pat, printed as "count<TAB>pat".
fn count_kmer<W: Write>(o: &mut W, seq: &[u8], m: usize, enc: &[u8; 256], pat: &str) {
  let k = pat.len();
  let mut c = 0;
  if m >= k {
    let lg = table_lg(m, k);
    let mut tab = vec![0u64; 2usize << lg];
    build(seq, m, k, &mut tab, 64 - lg);
    let mut code = 0u64;
    for &b in pat.as_bytes() { code = (code << 2) | enc[b as usize] as u64; }
    c = lookup(&tab, code, 64 - lg);
  }
  writeln!(o, "{}\t{}", c, pat).unwrap();
}

fn main() {
  let path = std::env::args().nth(1).expect("usage: knucleotide FASTA");
  let inp = std::fs::read(path).unwrap();
  let n = inp.len();
  let out = std::io::stdout();
  let mut o = std::io::BufWriter::new(out.lock());
  let mut enc = [255u8; 256];
  enc[b'A' as usize] = 0; enc[b'C' as usize] = 1; enc[b'G' as usize] = 2; enc[b'T' as usize] = 3;
  enc[b'a' as usize] = 0; enc[b'c' as usize] = 1; enc[b'g' as usize] = 2; enc[b't' as usize] = 3;
  let mut seq = vec![0u8; n + 1];
  let mut m = 0;
  let mut p = find_three(&inp);
  while p < n && inp[p] != b'>' {
    let s = enc[inp[p] as usize];
    if s != 255 { seq[m] = s; m += 1; }
    p += 1;
  }
  frequencies(&mut o, &seq, m, 1);
  frequencies(&mut o, &seq, m, 2);
  count_kmer(&mut o, &seq, m, &enc, "GGT");
  count_kmer(&mut o, &seq, m, &enc, "GGTA");
  count_kmer(&mut o, &seq, m, &enc, "GGTATT");
  count_kmer(&mut o, &seq, m, &enc, "GGTATTTTAATT");
  count_kmer(&mut o, &seq, m, &enc, "GGTATTTTAATTTATAGT");
  o.flush().unwrap();
}
