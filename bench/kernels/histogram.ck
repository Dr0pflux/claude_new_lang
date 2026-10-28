// Byte frequency table (256 counters) over generated ASCII text.
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
  let cnt = alloc<i64>(256);
  for r in 0..80 { for i in 0..n { cnt[t[i]] += 1; } }
  let mut s = 0; let mut mx = 0; let mut mb = 0;
  for b in 0..256 { s = s * 31 + cnt[b]; if cnt[b] > mx { mx = cnt[b]; mb = b; } }
  print(s); print(mx); print(mb);
}
