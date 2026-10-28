// FNV-1a style multiply, xorshift and multiply-rotate mixing.
fn main() {
  let n = 100000000 + argc() - 1;
  let mut x: u64 = 88172645463325252;
  let mut h: u64 = 14695981039346656037;
  for i in 0..n {
    x = x ^ (x << 13); x = x ^ (x >> 7); x = x ^ (x << 17);
    h = h ^ (x & 255);
    h = h * 1099511628211;
    h = ((h << 5) | (h >> 59)) ^ (x * 0x9E3779B97F4A7C15);
  }
  print(h);
}
