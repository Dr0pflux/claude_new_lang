// Naive substring search for several patterns, total match count.
fn count(t: [u8], p: [u8]) -> i64 {
  let n = len(t); let m = len(p);
  let mut cnt = 0; let mut i = 0;
  while i + m <= n {
    let mut j = 0;
    while j < m && t[i + j] == p[j] { j += 1; }
    if j == m { cnt += 1; }
    i += 1;
  }
  return cnt;
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
  let p1 = "the"; let p2 = "ab"; let p3 = "e a"; let p4 = "qxz"; let p5 = "ing.";
  let mut s1 = 0; let mut s2 = 0; let mut s3 = 0; let mut s4 = 0; let mut s5 = 0;
  for r in 0..10 {
    s1 += count(t, p1); s2 += count(t, p2); s3 += count(t, p3); s4 += count(t, p4); s5 += count(t, p5);
  }
  print(s1); print(s2); print(s3); print(s4); print(s5);
}
