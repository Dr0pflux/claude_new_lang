fn gcd(a: i64, b: i64) -> i64 {
  if b == 0 { return a; }
  return gcd(b, a % b);
}
fn shout(n: i64) {            // no return type: returns nothing
  print(n);
}
fn main() {
  shout(gcd(84, 36));         // 12
}
