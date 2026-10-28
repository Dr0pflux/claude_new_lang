// Benchmarks Game n-body (same algorithm as nbody.cock / nbody.c). usage: nbody N
const PI: f64 = 3.141592653589793;
const SOLAR: f64 = 4.0 * PI * PI;
const DPY: f64 = 365.24;
#[derive(Clone, Copy)]
struct Body { x: f64, y: f64, z: f64, vx: f64, vy: f64, vz: f64, m: f64 }
fn body(x: f64, y: f64, z: f64, vx: f64, vy: f64, vz: f64, m: f64) -> Body {
  Body { x, y, z, vx: vx * DPY, vy: vy * DPY, vz: vz * DPY, m: m * SOLAR }
}
fn advance(b: &mut [Body], dt: f64) {
  let n = b.len();
  for i in 0..n {
    for j in i + 1..n {
      let dx = b[i].x - b[j].x; let dy = b[i].y - b[j].y; let dz = b[i].z - b[j].z;
      let d2 = dx * dx + dy * dy + dz * dz;
      let mag = dt / (d2 * d2.sqrt());
      let mj = b[j].m * mag; let mi = b[i].m * mag;
      b[i].vx -= dx * mj; b[i].vy -= dy * mj; b[i].vz -= dz * mj;
      b[j].vx += dx * mi; b[j].vy += dy * mi; b[j].vz += dz * mi;
    }
  }
  for p in b.iter_mut() { p.x += dt * p.vx; p.y += dt * p.vy; p.z += dt * p.vz; }
}
fn energy(b: &[Body]) -> f64 {
  let mut e = 0.0;
  for i in 0..b.len() {
    e += 0.5 * b[i].m * (b[i].vx * b[i].vx + b[i].vy * b[i].vy + b[i].vz * b[i].vz);
    for j in i + 1..b.len() {
      let dx = b[i].x - b[j].x; let dy = b[i].y - b[j].y; let dz = b[i].z - b[j].z;
      e -= b[i].m * b[j].m / (dx * dx + dy * dy + dz * dz).sqrt();
    }
  }
  e
}
fn main() {
  let n: i64 = std::env::args().nth(1).map(|s| s.parse().unwrap()).unwrap_or(1000);
  let mut b = [
    body(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0),
    body(4.84143144246472090e+00, -1.16032004402742839e+00, -1.03622044471123109e-01,
         1.66007664274403694e-03, 7.69901118419740425e-03, -6.90460016972063023e-05, 9.54791938424326609e-04),
    body(8.34336671824457987e+00, 4.12479856412430479e+00, -4.03523417114321381e-01,
         -2.76742510726862411e-03, 4.99852801234917238e-03, 2.30417297573763929e-05, 2.85885980666130812e-04),
    body(1.28943695621391310e+01, -1.51111514016986312e+01, -2.23307578892655734e-01,
         2.96460137564761618e-03, 2.37847173959480950e-03, -2.96589568540237556e-05, 4.36624404335156298e-05),
    body(1.53796971148509165e+01, -2.59193146099879641e+01, 1.79258772950371181e-01,
         2.68067772490389322e-03, 1.62824170038242295e-03, -9.51592254519715870e-05, 5.15138902046611451e-05),
  ];
  let (mut px, mut py, mut pz) = (0.0, 0.0, 0.0);
  for p in b.iter() { px += p.vx * p.m; py += p.vy * p.m; pz += p.vz * p.m; }
  b[0].vx = -px / SOLAR; b[0].vy = -py / SOLAR; b[0].vz = -pz / SOLAR;
  println!("{:.9}", energy(&b));
  for _ in 0..n { advance(&mut b, 0.01); }
  println!("{:.9}", energy(&b));
}
