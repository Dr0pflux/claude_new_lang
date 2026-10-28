// Benchmarks Game fasta (same algorithm as fasta.cock / .c). usage: fasta N
use std::io::Write;
const ALU: &[u8] = b"GGCCGGGCGCGGTGGCTCACGCCTGTAATCCCAGCACTTTGGGAGGCCGAGGCGGGCGGATCACCTGAGGTCAGGAGTTCGAGACCAGCCTGGCCAACATGGTGAAACCCCGTCTCTACTAAAAATACAAAAATTAGCCGGGCGTGGTGGCGCGCGCCTGTAATCCCAGCTACTCGGGAGGCTGAGGCAGGAGAATCGCTTGAACCCGGGAGGCGGAGGTTGCAGTGAGCCGAGATCGCGCCACTGCACTCCAGCCTGGGCGACAGAGCGAGACTCCGTCTCAAAAA";
const IM: i64 = 139968; const IA: i64 = 3877; const IC: i64 = 29573;
struct St { last: i64, line: [u8; 61], cum: [f64; 16], chars: [u8; 16] }
fn repeat_fasta<W: Write>(o: &mut W, st: &mut St, mut n: i64) {
  let mut k = 0;
  while n > 0 {
    let m = if n < 60 { n } else { 60 } as usize;
    for i in 0..m { st.line[i] = ALU[k]; k += 1; if k == ALU.len() { k = 0; } }
    st.line[m] = b'\n';
    o.write_all(&st.line[..m + 1]).unwrap();
    n -= m as i64;
  }
}
fn random_fasta<W: Write>(o: &mut W, st: &mut St, mut n: i64, nc: usize) {
  while n > 0 {
    let m = if n < 60 { n } else { 60 } as usize;
    for i in 0..m {
      st.last = (st.last * IA + IC) % IM;
      let r = st.last as f64 / 139968.0;
      let mut c = 0;
      while c < nc - 1 && st.cum[c] <= r { c += 1; }
      st.line[i] = st.chars[c];
    }
    st.line[m] = b'\n';
    o.write_all(&st.line[..m + 1]).unwrap();
    n -= m as i64;
  }
}
fn setup(st: &mut St, cs: &[u8], p: &[f64]) {
  let mut s = 0.0;
  for i in 0..cs.len() { s += p[i]; st.cum[i] = s; st.chars[i] = cs[i]; }
}
fn main() {
  let n: i64 = std::env::args().nth(1).map(|s| s.parse().unwrap()).unwrap_or(1000);
  let out = std::io::stdout();
  let mut o = std::io::BufWriter::new(out.lock());
  let mut st = St { last: 42, line: [0; 61], cum: [0.0; 16], chars: [0; 16] };
  let iub = [0.27, 0.12, 0.12, 0.27, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02];
  let hs = [0.3029549426680, 0.1979883004921, 0.1975473066391, 0.3015094502008];
  o.write_all(b">ONE Homo sapiens alu\n").unwrap();
  repeat_fasta(&mut o, &mut st, 2 * n);
  o.write_all(b">TWO IUB ambiguity codes\n").unwrap();
  setup(&mut st, b"acgtBDHKMNRSVWY", &iub);
  random_fasta(&mut o, &mut st, 3 * n, 15);
  o.write_all(b">THREE Homo sapiens frequency\n").unwrap();
  setup(&mut st, b"acgt", &hs);
  random_fasta(&mut o, &mut st, 5 * n, 4);
}
