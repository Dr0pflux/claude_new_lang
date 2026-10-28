// Benchmarks Game n-body (same algorithm as nbody.c / nbody.rs). usage: nbody N
struct Body { x: f64, y: f64, z: f64, vx: f64, vy: f64, vz: f64, m: f64 }
let PI = 3.141592653589793;
let SOLAR = 39.47841760435743;   // 4 * PI * PI
let DPY = 365.24;

fn arg_int(s: [u8]) -> i64 {
  let mut n = 0; let mut k = 0;
  while k < len(s) && s[k] >= 48 && s[k] <= 57 { n = n * 10 + (s[k] - 48); k += 1; }
  return n;
}
fn set(b: mut [Body], i: i64, x: f64, y: f64, z: f64, vx: f64, vy: f64, vz: f64, m: f64) {
  b[i].x = x; b[i].y = y; b[i].z = z;
  b[i].vx = vx * DPY; b[i].vy = vy * DPY; b[i].vz = vz * DPY; b[i].m = m * SOLAR;
}
fn advance(b: mut [Body], dt: f64) {
  let n = len(b);
  let mut i = 0;
  while i < n {
    let mut j = i + 1;
    while j < n {
      let dx = b[i].x - b[j].x; let dy = b[i].y - b[j].y; let dz = b[i].z - b[j].z;
      let d2 = dx * dx + dy * dy + dz * dz;
      let mag = dt / (d2 * sqrt(d2));
      let mj = b[j].m * mag; let mi = b[i].m * mag;
      b[i].vx -= dx * mj; b[i].vy -= dy * mj; b[i].vz -= dz * mj;
      b[j].vx += dx * mi; b[j].vy += dy * mi; b[j].vz += dz * mi;
      j += 1;
    }
    i += 1;
  }
  i = 0;
  while i < n { b[i].x += dt * b[i].vx; b[i].y += dt * b[i].vy; b[i].z += dt * b[i].vz; i += 1; }
}
fn energy(b: [Body]) -> f64 {
  let n = len(b);
  let mut e = 0.0;
  let mut i = 0;
  while i < n {
    e += 0.5 * b[i].m * (b[i].vx * b[i].vx + b[i].vy * b[i].vy + b[i].vz * b[i].vz);
    let mut j = i + 1;
    while j < n {
      let dx = b[i].x - b[j].x; let dy = b[i].y - b[j].y; let dz = b[i].z - b[j].z;
      e -= b[i].m * b[j].m / sqrt(dx * dx + dy * dy + dz * dz);
      j += 1;
    }
    i += 1;
  }
  return e;
}
fn offset(b: mut [Body]) {
  let mut px = 0.0; let mut py = 0.0; let mut pz = 0.0;
  let mut i = 0;
  while i < len(b) { px += b[i].vx * b[i].m; py += b[i].vy * b[i].m; pz += b[i].vz * b[i].m; i += 1; }
  b[0].vx = 0.0 - px / SOLAR; b[0].vy = 0.0 - py / SOLAR; b[0].vz = 0.0 - pz / SOLAR;
}
// fixed-point with 9 decimals (|v| < 1e9)
fn print9(v: f64) {
  let mut a = v;
  if a < 0.0 { putc('-'); a = 0.0 - a; }
  let mut ip = a as i64;
  let mut t = ((a - ip as f64) * 1000000000.0 + 0.5) as i64;
  if t >= 1000000000 { ip += 1; t -= 1000000000; }
  print_int(ip); putc('.');
  let mut p = 100000000;
  while p > 0 { putc(t / p % 10 + 48); p = p / 10; }
  putc(10);
}
fn print_int(x: i64) { if x >= 10 { print_int(x / 10); } putc(x % 10 + 48); }
fn main() {
  let a1 = argv(1);
  let n = arg_int(a1);
  let b = alloc<Body>(5);
  set(b, 0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0);
  set(b, 1, 4.84143144246472090e+00, -1.16032004402742839e+00, -1.03622044471123109e-01,
         1.66007664274403694e-03, 7.69901118419740425e-03, -6.90460016972063023e-05, 9.54791938424326609e-04);
  set(b, 2, 8.34336671824457987e+00, 4.12479856412430479e+00, -4.03523417114321381e-01,
         -2.76742510726862411e-03, 4.99852801234917238e-03, 2.30417297573763929e-05, 2.85885980666130812e-04);
  set(b, 3, 1.28943695621391310e+01, -1.51111514016986312e+01, -2.23307578892655734e-01,
         2.96460137564761618e-03, 2.37847173959480950e-03, -2.96589568540237556e-05, 4.36624404335156298e-05);
  set(b, 4, 1.53796971148509165e+01, -2.59193146099879641e+01, 1.79258772950371181e-01,
         2.68067772490389322e-03, 1.62824170038242295e-03, -9.51592254519715870e-05, 5.15138902046611451e-05);
  offset(b);
  print9(energy(b));
  let mut k = 0;
  while k < n { advance(b, 0.01); k += 1; }
  print9(energy(b));
}
