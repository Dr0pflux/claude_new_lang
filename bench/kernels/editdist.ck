// Levenshtein distance between many short word pairs cut from the generated text.
fn lev(t: [u8], o1: i64, la: i64, o2: i64, lb: i64, row: mut [i64]) -> i64 {
  for j in 0..=lb { row[j] = j; }
  for i in 1..=la {
    let mut diag = row[0]; row[0] = i;
    for j in 1..=lb {
      let up = row[j];
      let mut cost = 0; if t[o1 + i - 1] != t[o2 + j - 1] { cost = 1; }
      let mut v = diag + cost;
      if row[j - 1] + 1 < v { v = row[j - 1] + 1; }
      if up + 1 < v { v = up + 1; }
      row[j] = v; diag = up;
    }
  }
  return row[lb];
}
fn gen(t: mut [u8]) {
  let n = len(t);
  let mut x: u64 = 88172645463325252;
  for i in 0..n {
    x = x ^ (x << 13); x = x ^ (x >> 7); x = x ^ (x << 17);
    let v = (x >> 58) as i64;
    let mut c: i64 = 0;
    if v < 44 { c = 97 + v % 26; } else if v < 54 { c = 32; } else if v < 56 { c = 10; }
    else if v < 58 { c = 46; } else if v < 60 { c = 44; } else if v < 62 { c = 65 + v % 26; } else { c = 48 + v % 10; }
    t[i] = c as u8;
  }
}
fn main() {
  let n = 4194304 + argc() - 1;
  let t = alloc<u8>(n);
  gen(t);
  let row = alloc<i64>(32);
  let mut tot = 0; let mut x = 0;
  for p in 0..1000000 {
    let o1 = (p * 40503) % (n - 32);
    let o2 = (p * 65537 + 12345) % (n - 32);
    let la = 6 + p % 8; let lb = 6 + (p >> 3) % 8;
    let d = lev(t, o1, la, o2, lb, row);
    tot += d; x = x ^ (d << (p & 31));
  }
  print(tot); print(x);
}
