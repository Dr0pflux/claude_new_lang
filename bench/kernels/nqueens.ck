// N-queens solution count by recursive backtracking with column/diagonal flags.
fn place(r: i64, n: i64, c: mut [u8], d1: mut [u8], d2: mut [u8]) -> i64 {
  if r == n { return 1; }
  let mut cnt = 0;
  for col in 0..n {
    if c[col] == 0 && d1[r + col] == 0 && d2[r - col + n] == 0 {
      c[col] = 1; d1[r + col] = 1; d2[r - col + n] = 1;
      cnt += place(r + 1, n, c, d1, d2);
      c[col] = 0; d1[r + col] = 0; d2[r - col + n] = 0;
    }
  }
  return cnt;
}
fn main() {
  let n = 13 + argc() - 1;
  let c = alloc<u8>(64); let d1 = alloc<u8>(64); let d2 = alloc<u8>(64);
  print(place(0, n, c, d1, d2));
}
