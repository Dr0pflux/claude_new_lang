// Text statistics over a generated 1 MiB ASCII-like buffer, 300 passes: spaces, upper-case letters,
// byte sum of digits, lower-casing into a second buffer. Same algorithm as textscan.c / textscan.rs.
fn main() {
  let n = 1 << 20;
  let t = alloc<u8>(n);
  let low = alloc<u8>(n);
  let mut x: u64 = 88172645463325252;
  let mut i = 0;
  while i < n { x = x ^ (x << 13); x = x ^ (x >> 7); x = x ^ (x << 17); t[i] = (32 + (x >> 58) * 3 / 2) as u8; i += 1; }
  let mut sp = 0; let mut up = 0; let mut dig = 0; let mut r = 0;
  while r < 300 {
    i = 0; while i < n { if t[i] == 32 { sp += 1; } i += 1; }
    i = 0; while i < n { if t[i] >= 65 && t[i] <= 90 { up += 1; } i += 1; }
    i = 0; while i < n { if t[i] >= 48 && t[i] <= 57 { dig += t[i]; } i += 1; }
    i = 0; while i < n { if t[i] >= 65 && t[i] <= 90 { low[i] = (t[i] + 32) as u8; } else { low[i] = t[i]; } i += 1; }
    r += 1;
  }
  let mut h = 0; i = 0; while i < n { h = h * 31 + low[i]; i += 1; }
  print(sp); print(up); print(dig); print(h);
}
