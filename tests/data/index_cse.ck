// index CSE: a repeated pure index is computed once, but never across a change of its variables
let A = alloc<i64>(64);
let B = alloc<i64>(64);
let C = alloc<i64>(8);
fn fill() { let mut i = 0; while i < 64 { A[i] = i * 10; B[i] = i * 100; i += 1; } }
fn same(x: i64, i: i64) -> i64 { return A[x + i] + B[x + i] + A[x + i]; }
fn reassigned(x0: i64, i: i64) -> i64 {
  let mut x = x0;
  let a = A[x + i];
  x += 1;
  return a + A[x + i];          // x changed: must read A[x0 + 1 + i]
}
fn nested(x0: i64, i: i64, flip: bool) -> i64 {
  let mut x = x0;
  let a = A[x + i];
  if flip { x = x + 2; }
  return a + B[x + i];          // changed inside the if on one path
}
fn stores(x: i64, i: i64) {
  A[x + i] = 7; B[x + i] = A[x + i] + 1;
  A[x * 2 + i] = B[x + i] * 3;
}
fn shorter(x: i64, i: i64) -> i64 { print(A[x + i]); return C[x + i]; }   // C keeps its own check
fn main() {
  fill();
  print(same(argc(), 3));
  print(reassigned(argc(), 3));
  print(nested(argc(), 3, true)); print(nested(argc(), 3, false));
  stores(argc(), 5); print(A[argc() + 5]); print(B[argc() + 5]); print(A[2 * argc() + 5]);
  print(shorter(argc(), 4));
  print(shorter(argc(), 20));   // A[22] fine, C[22] traps after printing 220
}
