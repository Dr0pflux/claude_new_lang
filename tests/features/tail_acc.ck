// tail recursion modulo +: `return A + f(B)` runs as a loop; results, wrap-around and evaluation order must not change
let lft = alloc<i32>(64);
let rgt = alloc<i32>(64);
let mut top: i64 = 0;
fn tr_make(d: i64) -> i64 {
  let me = top; top += 1;
  if d > 0 { lft[me] = tr_make(d - 1) as i32; rgt[me] = tr_make(d - 1) as i32; } else { lft[me] = -1; rgt[me] = -1; }
  return me;
}
fn tr_check(t: i64) -> i64 {
  let l = lft[t] as i64;
  if l < 0 { return 1; }
  return 1 + tr_check(l) + tr_check(rgt[t] as i64);
}
fn tag(c: i64, v: i64) -> i64 { putc(c); return v; }
// arguments swap (needs temporaries) and side effects in A and B keep their order
fn swp(a: i64, b: i64, n: i64) -> i64 {
  if n == 0 { return a * 10 + b; }
  if n % 3 == 1 { return tag(97 + n, n) + swp(b, tag(65 + n, a), n - 1); }
  return swp(b, a, n - 1);
}
// tail return in the middle of the body, plain return inside a loop, wrap-around
fn mid(x: i64, k: i64) -> i64 {
  if k > 0 {
    if (k & 1) == 0 { return 9223372036854775807 + mid(x + 1, k - 1); }
    let mut i = 0;
    while i < 3 { if x == 1000 { return i; } i += 1; }
    return x + mid(x * 3, k - 1);
  }
  return x;
}
fn um(x: u64, k: i64) -> u64 { if k == 0 { return x; } return x * 7 + um(x + 18446744073709551615, k - 1); }
// a trap inside A happens before the tail call's arguments are evaluated
fn deep(n: i64, d: i64) -> i64 { if n == 0 { return 0; } return 1 + deep(n - 1, d); }
fn main() {
  let r = tr_make(4);
  print(tr_check(r));
  print(swp(1, 2, 7)); putc(10);
  print(mid(5, 9));
  print(mid(1000, 1));
  print(um(3, 12) as i64);
  print(deep(50000, 0));
}
