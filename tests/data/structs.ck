struct Tok { kind: u8, len: u16, start: i32, val: f64 }
struct Tri { a: u8, b: u8, c: u8 }
let N = 1000;
let toks = alloc<Tok>(N);
let tris = alloc<Tri>(64);
let mut count: i64 = 5;
let mut flag: bool = true;
let LIMIT: u16 = 300;
fn add(k: u8, start: i64) {
  toks[count].kind = k;
  toks[count].start = start as i32;
  toks[count].len = LIMIT;
  toks[count].val = start as f64 * 0.5;
  count += 1;
}
fn sum(t: [Tok], n: i64) -> f64 {
  let mut s = 0.0;
  let mut i = 0;
  while i < n { s += t[i].val + t[i].len as f64; i += 1; }
  return s;
}
fn main() {
  add(7, 10); add(9, 21);
  print(count);
  print(toks[5].kind); print(toks[6].start); print(toks[6].len); print(toks[6].val);
  toks[6].len += 10;
  toks[6].val *= 4.0;
  print(toks[6].len); print(toks[6].val);
  print(sum(toks, count));
  tris[3].b = 200; tris[3].c = 255; tris[4].a = 1;
  print(tris[3].b + tris[3].c + tris[4].a + tris[3].a);
  print(flag);
  flag = !flag;
  print(flag && count > 6);
  let local = alloc<Tri>(10);
  local[9].c = 77;
  print(local[9].c);
  print(len(toks));
}
