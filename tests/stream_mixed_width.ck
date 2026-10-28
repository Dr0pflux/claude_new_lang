fn main() {
  let bytes = alloc<u8>(512);
  let wide = view<u64>(bytes);
  let mut i: i64 = 0;
  while i < 512 { bytes[i] = (i + 1) as u8; i += 1; }
  i = 0;
  while i < 64 { wide[i] = bytes[i] as u64; i += 1; }
  i = 0;
  while i < 64 { print(wide[i]); i += 1; }
}
