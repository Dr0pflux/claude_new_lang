fn main() {
    let n: usize = 4096 + std::env::args().count() - 1; let mut co = vec![0f64; 17];
    let mut x = vec![0f64; n]; let mut y = vec![0f64; n];
    for k in 0..17 { co[k] = 1.0 / ((k + 1) as f64); }
    for i in 0..n { x[i] = ((i * 37) % 1024) as f64 / 1024.0 - 0.5; }
    let mut acc = 0.0f64;
    for p in 0..36000 {
        let s = (p & 63) as f64 * 0.001;
        for i in 0..n {
            let t = x[i] + s; let mut r = co[16];
            for k in 0..16 { r = r * t + co[15 - k]; }
            y[i] = r;
        }
        for i in 0..n { acc += y[i]; }
    }
    println!("{}", (acc * 1000.0) as i64);
}
