// usage: ./letters book.txt   -> count of each letter A-Z
fn main() {
  let text = file(1);                  // the whole file as [u8]
  let count = alloc<u32>(26);          // 26 zeroed counters
  for i in 0..len(text) {
    let c = text[i];
    if c >= 97 && c <= 122 { count[c - 97] += 1; }      // a-z
    else if c >= 65 && c <= 90 { count[c - 65] += 1; }  // A-Z
  }
  for k in 0..26 { putc(k + 65); putc(32); print(count[k]); }
}
