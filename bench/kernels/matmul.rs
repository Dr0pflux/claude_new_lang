fn main() {
    let n: usize = 768 + std::env::args().count() - 1;
    let mut a = vec![0f64; n * n]; let mut b = vec![0f64; n * n]; let mut c = vec![0f64; n * n];
    for i in 0..n * n { a[i] = ((i * 7 + 3) % 13) as f64 * 0.25; b[i] = ((i * 5 + 1) % 11) as f64 * 0.5; }
    for i in 0..n { for k in 0..n {
        let aik = a[i * n + k];
        for j in 0..n { c[i * n + j] += aik * b[k * n + j]; }
    } }
    let mut s = 0.0f64; for i in 0..n * n { s += c[i]; }
    println!("{}\n{}", s as i64, c[n * n - 1] as i64);
}
