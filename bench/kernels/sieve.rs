fn main() {
    let n: usize = 40000000 + std::env::args().count() - 1; let mut c = vec![0u8; n];
    let mut i = 2; while i * i < n { if c[i] == 0 { let mut j = i * i; while j < n { c[j] = 1; j += i; } } i += 1; }
    let mut cnt: i64 = 0; for i in 2..n { if c[i] == 0 { cnt += 1; } }
    println!("{}", cnt);
}
