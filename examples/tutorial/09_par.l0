fn work(k: i64) -> i64 { let mut s = 0; let mut i = 0; while i < 1000000 { s += (i * k) % 7; i += 1; } return s; }
fn main() {
  let res = shared<i64>(4);
  par w in 0..4 { res[w] = work(w + 1); }   // 4 workers in parallel
  let mut i = 0;
  while i < 4 { print(res[i]); i += 1; }
}
