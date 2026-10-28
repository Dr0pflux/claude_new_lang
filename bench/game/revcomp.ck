// Benchmarks Game reverse-complement (same algorithm as revcomp.c / .rs). usage: revcomp FASTA
// Each sequence is found by scanning forward to the next '>', then walked backward from its end,
// complementing each residue through a 256-entry table and emitting 60-column lines.
fn revcomp(inp: [u8], start: i64, end: i64, tab: [u8], obuf: mut [u8]) {
  let mut on = 0;
  let mut col = 0;
  let mut p = end;
  while p > start {
    p -= 1;
    let c = inp[p];
    if c != 10 {
      obuf[on] = tab[c];
      on += 1;
      col += 1;
      if col == 60 {
        obuf[on] = 10;
        on += 1;
        col = 0;
        if on >= 65536 { write(obuf, 0, on); on = 0; }
      }
    }
  }
  if col > 0 { obuf[on] = 10; on += 1; }
  write(obuf, 0, on);
}
fn main() {
  let inp = file(1);
  let n = len(inp);
  let tab = alloc<u8>(256);
  let obuf = alloc<u8>(65600);
  let from = "ACBDGHKMNSRUTWVYacbdghkmnsrutwvy";
  let to = "TGVHCDMKNSYAAWBRTGVHCDMKNSYAAWBR";
  let mut i = 0;
  while i < 256 { tab[i] = i as u8; i += 1; }
  i = 0;
  while i < 32 { tab[from[i]] = to[i]; i += 1; }
  let mut pos = 0;
  while pos < n {
    let mut e = pos;
    while e < n && inp[e] != 10 { e += 1; }
    write(inp, pos, e - pos);
    putc(10);
    pos = e + 1;
    let start = pos;
    while pos < n && inp[pos] != 62 { pos += 1; }
    if start < pos { revcomp(inp, start, pos, tab, obuf); }
  }
}
