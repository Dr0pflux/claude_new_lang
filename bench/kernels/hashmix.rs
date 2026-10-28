fn main() {
    let n: i64 = 100000000 + std::env::args().count() as i64 - 1;
    let mut x: u64 = 88172645463325252; let mut h: u64 = 14695981039346656037;
    for _ in 0..n {
        x ^= x << 13; x ^= x >> 7; x ^= x << 17;
        h ^= x & 255;
        h = h.wrapping_mul(1099511628211);
        h = ((h << 5) | (h >> 59)) ^ x.wrapping_mul(0x9E3779B97F4A7C15);
    }
    println!("{}", h);
}
