// scoped heap: allocation in functions and loops, released automatically
fn hist(t: [u8]) -> i64 {
  let c = alloc<i32>(256);          // scratch: freed when hist returns
  let mut i = 0;
  while i < len(t) { c[t[i]] += 1; i += 1; }
  let mut best = 0;
  let mut k = 0;
  while k < 256 { if c[k] > c[best] { best = k; } k += 1; }
  return best;
}
fn depth(n: i64) -> i64 {
  let buf = alloc<u8>(n + 1);       // one per recursion level
  buf[n] = n as u8;
  if n == 0 { return 0; }
  return buf[n] + depth(n - 1);
}
fn main() {
  let s = "hello world, lllll";
  let mut total = 0;
  let mut r = 0;
  while r < 20000 {                  // 200k x 1 MiB would be 200 GiB without release
    let big = alloc<u8>(1048576);
    big[r % 1048576] = 7;
    total += big[r % 1048576] + big[(r + 1) % 1048576];
    r += 1;
  }
  print(total);
  print(hist(s));
  print(depth(100));
  let out = alloc<u8>(6);
  out[0] = 104; out[1] = 105; out[2] = 10;
  save(1, out, 3);
}
