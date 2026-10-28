// Benchmarks Game reverse-complement (same algorithm as revcomp.ck / .c). usage: revcomp FASTA
// Each sequence is found by scanning forward to the next '>', then walked backward from its end,
// complementing each residue through a 256-entry table and emitting 60-column lines.
use std::io::Write;

fn revcomp<W: Write>(o: &mut W, inp: &[u8], start: usize, end: usize, tab: &[u8; 256], obuf: &mut [u8; 65600]) {
  let mut on = 0;
  let mut col = 0;
  let mut p = end;
  while p > start {
    p -= 1;
    let c = inp[p];
    if c != b'\n' {
      obuf[on] = tab[c as usize];
      on += 1;
      col += 1;
      if col == 60 {
        obuf[on] = b'\n';
        on += 1;
        col = 0;
        if on >= 65536 { o.write_all(&obuf[..on]).unwrap(); on = 0; }
      }
    }
  }
  if col > 0 { obuf[on] = b'\n'; on += 1; }
  o.write_all(&obuf[..on]).unwrap();
}

fn main() {
  let path = std::env::args().nth(1).expect("usage: revcomp FASTA");
  let inp = std::fs::read(path).unwrap();
  let n = inp.len();
  let out = std::io::stdout();
  let mut o = std::io::BufWriter::with_capacity(65536, out.lock());
  let mut tab = [0u8; 256];
  let mut obuf = [0u8; 65600];
  let from = b"ACBDGHKMNSRUTWVYacbdghkmnsrutwvy";
  let to = b"TGVHCDMKNSYAAWBRTGVHCDMKNSYAAWBR";
  for i in 0..256 { tab[i] = i as u8; }
  for i in 0..32 { tab[from[i] as usize] = to[i]; }
  let mut pos = 0;
  while pos < n {
    let mut e = pos;
    while e < n && inp[e] != b'\n' { e += 1; }
    o.write_all(&inp[pos..e]).unwrap();
    o.write_all(b"\n").unwrap();
    pos = e + 1;
    let start = pos;
    while pos < n && inp[pos] != b'>' { pos += 1; }
    if start < pos { revcomp(&mut o, &inp, start, pos, &tab, &mut obuf); }
  }
  o.flush().unwrap();
}
