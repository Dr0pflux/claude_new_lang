// SSE2 store pairs: bit-identical lanes, no pairing across a dependence, checks kept
struct V { x: f64, y: f64, z: f64 }
let G = alloc<f64>(64);
fn bitsout(v: f64) { print(bits(v)); }
fn swapdep(a: mut [V], i: i64) { a[i].x = a[i].y * 2.0; a[i].y = a[i].x * 3.0; }   // lane 2 reads lane 1's store
fn upd(a: mut [V], i: i64, s: f64) { a[i].x = a[i].x * s + a[i].z; a[i].y = a[i].y * s + a[i].z; }
fn ops(a: mut [V], i: i64, d: f64) { a[i].x = sqrt(a[i].x) / d; a[i].y = sqrt(a[i].y) / d; a[i].y = -a[i].y; a[i].z = -a[i].z; }
fn tail(a: mut [V], i: i64, s: f64) { a[i].x = a[i].x * s; a[i].y = a[i].y * s; }   // unproven index: trap kept
fn main() {
  let n = 8 + argc() - 1;
  let a = alloc<V>(n);
  let mut i = 0;
  while i < n { a[i].x = i as f64 + 0.25; a[i].y = 2.0 * i as f64 - 1.5; a[i].z = 0.125 * i as f64; i += 1; }
  swapdep(a, 1); print(a[1].x); print(a[1].y);
  upd(a, 2, 1.0 / 3.0); bitsout(a[2].x); bitsout(a[2].y);
  ops(a, 3, 7.0); bitsout(a[3].x); bitsout(a[3].y); bitsout(a[3].z);
  a[4].x = 0.0 - 0.0; a[4].y = 0.0;
  ops(a, 4, 0.0); bitsout(a[4].x); bitsout(a[4].y);   // 0/0 and -0/0 NaN patterns, -inf
  i = 0;
  while i < 62 { G[i] = G[i + 1] * 0.5 + 1.0; G[i + 1] = G[i + 2] * 0.5 + 2.0; i += 2; }
  bitsout(G[0]); bitsout(G[61]);
  tail(a, 5, 4.0); bitsout(a[5].x);
  tail(a, n, 4.0);
  print(999);
}
