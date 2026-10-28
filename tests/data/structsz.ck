// struct widths 16/32/64: alloc<S>(n) must reserve n * width bytes and
// view<S>(bytes) must have length bytes / width (power-of-two log2 scaling)
struct Slot { key: u64, count: u32 }                          // 16 bytes
struct Quad { a: u64, b: u64, c: u64, d: u64 }                 // 32 bytes
struct Oct { a: u64, b: u64, c: u64, d: u64, e: u64, f: u64, g: u64, h: u64 }   // 64 bytes
fn slots(n: i64) -> i64 {
  let a = alloc<Slot>(n);
  let b = alloc<Slot>(4);
  let mut j = 0;
  while j < n { a[j].key = (100 + j) as u64; a[j].count = j as u32; j += 1; }
  j = 0;
  while j < 4 { b[j].key = 7; b[j].count = 7; j += 1; }
  let mut bad = 0;
  j = 0;
  while j < n { if a[j].key != (100 + j) as u64 || a[j].count != j as u32 { bad += 1; } j += 1; }
  return bad;
}
fn quads(n: i64) -> i64 {
  let a = alloc<Quad>(n);
  let b = alloc<Quad>(n);
  let mut j = 0;
  while j < n { a[j].a = j as u64; a[j].d = (j + 1000) as u64; j += 1; }
  j = 0;
  while j < n { b[j].a = 9; b[j].b = 9; b[j].c = 9; b[j].d = 9; j += 1; }
  let mut bad = 0;
  j = 0;
  while j < n { if a[j].a != j as u64 || a[j].d != (j + 1000) as u64 || a[j].b != 0 { bad += 1; } j += 1; }
  return bad;
}
fn octs(n: i64) -> i64 {
  let a = alloc<Oct>(n);
  let b = alloc<Oct>(n);
  let mut j = 0;
  while j < n { a[j].h = (j + 1) as u64; j += 1; }
  j = 0;
  while j < n { b[j].a = 5; b[j].h = 5; j += 1; }
  let mut bad = 0;
  j = 0;
  while j < n { if a[j].h != (j + 1) as u64 || a[j].a != 0 { bad += 1; } j += 1; }
  return bad;
}
fn views(n: i64) {
  let bytes = alloc<u8>(n * 64);
  let s = view<Slot>(bytes);
  let q = view<Quad>(bytes);
  let o = view<Oct>(bytes);
  print(len(s)); print(len(q)); print(len(o));
}
fn main() {
  print(slots(16));
  print(slots(argc() + 20));
  print(quads(12));
  print(quads(argc() + 8));
  print(octs(10));
  print(octs(argc() + 6));
  views(5);
  views(argc() + 2);
}
