fn main() {
    let n: usize = 262144 + std::env::args().count() - 1; let mut a = vec![0i64; n];
    for i in 0..n { a[i] = (i as i64 * 7) % 1000 - 500; }
    for _ in 0..1500 { for i in 1..n { a[i] = a[i].wrapping_add(a[i - 1]); } }
    let mut s: i64 = 0; for i in 0..n { s = s.wrapping_mul(31).wrapping_add(a[i]); }
    println!("{}\n{}", s, a[n - 1]);
}
