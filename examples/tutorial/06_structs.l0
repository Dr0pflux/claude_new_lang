// a table of words found in a file: structs + globals
struct Word { start: i32, len: u16, count: u32 }

let MAX = 4096;
let words = alloc<Word>(MAX);   // global: visible in every function
let mut nwords: i64 = 0;

fn same(t: [u8], a: i64, b: i64, n: i64) -> bool {
  let mut i = 0;
  while i < n { if t[a + i] != t[b + i] { return false; } i += 1; }
  return true;
}
fn add(t: [u8], start: i64, n: i64) {
  let mut w = 0;
  while w < nwords {
    if words[w].len as i64 == n && same(t, words[w].start, start, n) { words[w].count += 1; return; }
    w += 1;
  }
  if nwords < MAX {
    words[nwords].start = start as i32;
    words[nwords].len = n as u16;
    words[nwords].count = 1;
    nwords += 1;
  }
}
fn main() {
  let t = file(1);
  let mut i = 0;
  while i < len(t) {
    while i < len(t) && (t[i] < 97 || t[i] > 122) { i += 1; }   // skip non-letters
    let start = i;
    while i < len(t) && t[i] >= 97 && t[i] <= 122 { i += 1; }
    if i > start && i - start < 60000 { add(t, start, i - start); }
  }
  let mut w = 0;
  while w < nwords {
    if words[w].count > 1 {
      write(t, words[w].start, words[w].len); putc(32); print(words[w].count);
    }
    w += 1;
  }
}
