// Letter-frequency profile and index of coincidence of a text file.
// usage: wordfreq FILE
fn count_letters(t: [u8], freq: mut [i64]) -> i64 {
  let mut n = 0;
  let mut i = 0;
  while i < len(t) {
    let c = t[i];
    if c >= 97 && c <= 122 { freq[c - 97] += 1; n += 1; }
    else if c >= 65 && c <= 90 { freq[c - 65] += 1; n += 1; }
    i += 1;
  }
  return n;
}
// index of coincidence x 10000
fn ioc(freq: [i64], n: i64) -> i64 {
  if n < 2 { return 0; }
  let mut s = 0;
  let mut k = 0;
  while k < 26 { s += freq[k] * (freq[k] - 1); k += 1; }
  return s * 10000 / (n * (n - 1));
}
fn main() -> i64 {
  let text = file(1);
  let freq = alloc64(26);
  let n = count_letters(text, freq);
  let mut k = 0;
  while k < 26 {
    if freq[k] > 0 { putc(k + 65); write(" "); print(freq[k] * 1000 / n); }
    k += 1;
  }
  write("IoC x10000: ");
  print(ioc(freq, n));
  return n;
}
