// element-wise vector loops in a function whose u8 and u64 parameters are views of one buffer
fn widen(src: [u8], dst: mut [u64], n: i64, d: i64) {
  if d > 0 { widen(src, dst, n, d - 1); return; }
  let mut i = 0;
  while i < n { dst[i] = src[i] as u64 + 1; i += 1; }
}
fn narrow(src: [u64], dst: mut [u8], n: i64, d: i64) {
  if d > 0 { narrow(src, dst, n, d - 1); return; }
  let mut i = 0;
  while i < n { dst[i] = (src[i] * 3) as u8; i += 1; }
}
fn main() {
  let bytes = alloc<u8>(512);
  let wide = view<u64>(bytes);
  let other = alloc<u64>(64);
  let mut i = 0;
  while i < 512 { bytes[i] = (i * 7 + 1) as u8; i += 1; }
  widen(bytes, wide, 64, argc() + 10);      // aliased: must run in order
  widen(bytes, other, 64, argc() + 10);     // distinct: may vectorize
  narrow(wide, bytes, 64, argc() + 10);     // aliased the other way
  let mut h = 0;
  i = 0; while i < 512 { h = h * 31 + bytes[i]; i += 1; }
  print(h);
  i = 0; while i < 64 { h = h * 31 + (other[i] as i64); i += 1; }
  print(h);
}
