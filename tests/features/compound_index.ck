struct P { x: f32, y: u8 }
let mut global_ix: i64 = 0;
let global_data = alloc<f64>(3);
let rhs_data = alloc<f64>(3);
let mut order: i64 = 0;
let mut calls: i64 = 0;
let pts = alloc<P>(2);
fn change_ix() -> f64 { global_ix = 1; return 2.5; }
fn rhs_order() -> f64 { order = order * 10 + 1; return 3.0; }
fn index_once() -> i64 { calls += 1; order = order * 10 + 2; return 0; }
fn write_rhs() -> f64 { rhs_data[1] = 2.0; return 3.0; }
fn main() {
  global_data[global_ix] += change_ix();
  let mut j: i64 = argc() - 1;
  rhs_data[j] += write_rhs();
  global_data[index_once()] += rhs_order();
  let mut i: i64 = argc() - 1;
  pts[1].x = 1.5;
  pts[1].y = 200;
  pts[i].x += 1.25;
  pts[i].y *= 3;
  print(global_data[0]); print(global_data[1]);
  print(rhs_data[0]); print(rhs_data[1]);
  print(order); print(calls);
  print(pts[1].x); print(pts[1].y);
}
