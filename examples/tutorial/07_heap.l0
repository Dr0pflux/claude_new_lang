// alloc works anywhere; scratch arrays are freed automatically
fn reversed_copy_sum(a: [i64]) -> i64 {
  let tmp = alloc<i64>(len(a));     // freed when this function returns
  let mut i = 0;
  while i < len(a) { tmp[i] = a[len(a) - 1 - i]; i += 1; }
  let mut s = 0;
  i = 0;
  while i < len(a) { s += tmp[i] * (i + 1); i += 1; }
  return s;
}
fn main() {
  let v = alloc<i64>(5);
  let mut i = 0;
  while i < 5 { v[i] = i + 1; i += 1; }    // 1 2 3 4 5
  print(reversed_copy_sum(v));             // 5*1+4*2+3*3+2*4+1*5 = 35
}
