// Benchmarks Game fasta (same algorithm as fasta.c / .rs). usage: fasta N
let ALU = "GGCCGGGCGCGGTGGCTCACGCCTGTAATCCCAGCACTTTGGGAGGCCGAGGCGGGCGGATCACCTGAGGTCAGGAGTTCGAGACCAGCCTGGCCAACATGGTGAAACCCCGTCTCTACTAAAAATACAAAAATTAGCCGGGCGTGGTGGCGCGCGCCTGTAATCCCAGCTACTCGGGAGGCTGAGGCAGGAGAATCGCTTGAACCCGGGAGGCGGAGGTTGCAGTGAGCCGAGATCGCGCCACTGCACTCCAGCCTGGGCGACAGAGCGAGACTCCGTCTCAAAAA";
let IUB_C = "acgtBDHKMNRSVWY";
let HS_C = "acgt";
let IM = 139968; let IA = 3877; let IC = 29573;
let mut last: i64 = 42;
let line = alloc<u8>(61);
let cum = alloc<f64>(16);
let chars = alloc<u8>(16);

fn arg_int(s: [u8]) -> i64 {
  let mut n = 0; let mut k = 0;
  while k < len(s) && s[k] >= 48 && s[k] <= 57 { n = n * 10 + (s[k] - 48); k += 1; }
  return n;
}
fn repeat_fasta(n0: i64) {
  let mut n = n0;
  let mut k = 0;
  while n > 0 {
    let mut m = 60; if n < 60 { m = n; }
    let mut i = 0;
    while i < m { line[i] = ALU[k]; k += 1; if k == len(ALU) { k = 0; } i += 1; }
    line[m] = 10;
    write(line, 0, m + 1);
    n -= m;
  }
}
fn random_fasta(n0: i64, nc: i64) {
  let mut n = n0;
  while n > 0 {
    let mut m = 60; if n < 60 { m = n; }
    let mut i = 0;
    while i < m {
      last = (last * IA + IC) % IM;
      let r = (last as f64) / 139968.0;
      let mut c = 0;
      while c < nc - 1 && cum[c] <= r { c += 1; }
      line[i] = chars[c];
      i += 1;
    }
    line[m] = 10;
    write(line, 0, m + 1);
    n -= m;
  }
}
fn setup(cs: [u8], p: [f64]) {
  let mut s = 0.0;
  let mut i = 0;
  while i < len(cs) { s += p[i]; cum[i] = s; chars[i] = cs[i]; i += 1; }
}
fn main() {
  let a1 = argv(1);
  let n = arg_int(a1);
  let iub = alloc<f64>(15);
  iub[0] = 0.27; iub[1] = 0.12; iub[2] = 0.12; iub[3] = 0.27;
  let mut i = 4;
  while i < 15 { iub[i] = 0.02; i += 1; }
  let hs = alloc<f64>(4);
  hs[0] = 0.3029549426680; hs[1] = 0.1979883004921; hs[2] = 0.1975473066391; hs[3] = 0.3015094502008;
  write(">ONE Homo sapiens alu\n");
  repeat_fasta(2 * n);
  write(">TWO IUB ambiguity codes\n");
  setup(IUB_C, iub);
  random_fasta(3 * n, 15);
  write(">THREE Homo sapiens frequency\n");
  setup(HS_C, hs);
  random_fasta(5 * n, 4);
}
