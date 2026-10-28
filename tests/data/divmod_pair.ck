// a / b and a % b on the same operands share one division; MIN / -1 must still raise SIGFPE
fn main() {
  let a = argc();
  let vals = alloc<i64>(8);
  vals[0] = 17; vals[1] = 0 - 17; vals[2] = 9223372036854775807; vals[3] = 0 - 9223372036854775807 - 1; vals[4] = 5; vals[5] = 0 - 3; vals[6] = 1; vals[7] = 1000003;
  let mut i = 0; let mut s = 0;
  while i < 8 { let mut j = 0; while j < 8 { let x = vals[i]; let k = vals[j]; if k != 0 && !(x == vals[3] && k == 0 - 1) { s = s * 31 + x / k + x % k; } j += 1; } i += 1; }
  print(s);
  let x = vals[3] + a - 1; let k = 0 - a;
  print(x / k + x % k);
}
