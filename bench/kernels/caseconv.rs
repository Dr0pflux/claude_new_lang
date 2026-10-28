fn gen(t: &mut [u8]) {
    let mut x: u64 = 88172645463325252;
    for i in 0..t.len() {
        x ^= x << 13; x ^= x >> 7; x ^= x << 17;
        let v = (x >> 58) as i64;
        let c: i64 = if v < 44 { 97 + v % 26 } else if v < 54 { 32 } else if v < 56 { 10 }
            else if v < 58 { 46 } else if v < 60 { 44 } else if v < 62 { 65 + v % 26 } else { 48 + v % 10 };
        t[i] = c as u8;
    }
}
fn main() {
    let n: usize = 4194304 + std::env::args().count() - 1;
    let mut t = vec![0u8; n];
    gen(&mut t);
    let mut low = vec![0u8; n]; let mut acc: i64 = 0;
    for _ in 0..100 {
        for i in 0..n { low[i] = if t[i] >= 65 && t[i] <= 90 { t[i] + 32 } else { t[i] }; }
        for i in 0..n { acc += low[i] as i64; }
    }
    let mut h: i64 = 0; for i in 0..n { h = h.wrapping_mul(31).wrapping_add(low[i] as i64); }
    println!("{}\n{}", acc, h);
}
