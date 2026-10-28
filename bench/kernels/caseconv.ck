// Lower-case ASCII text into a second buffer (many passes), checksum.
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
  let low = alloc<u8>(n);
  let mut acc = 0;
  for r in 0..100 {
    for i in 0..n { if t[i] >= 65 && t[i] <= 90 { low[i] = (t[i] + 32) as u8; } else { low[i] = t[i]; } }
    for i in 0..n { acc += low[i]; }
  }
  let mut h = 0;
  for i in 0..n { h = h * 31 + low[i]; }
  print(acc); print(h);
}
