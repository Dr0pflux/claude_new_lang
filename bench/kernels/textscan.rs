// Text statistics kernel (same algorithm as textscan.ck / textscan.c)
fn main() {
    let n: usize = 1 << 20;
    let mut t = vec![0u8; n]; let mut low = vec![0u8; n];
    let mut x: u64 = 88172645463325252;
    for i in 0..n { x ^= x << 13; x ^= x >> 7; x ^= x << 17; t[i] = (32 + (x >> 58) * 3 / 2) as u8; }
    let (mut sp, mut up, mut dig): (i64, i64, i64) = (0, 0, 0);
    for _ in 0..300 {
        for i in 0..n { if t[i] == 32 { sp += 1; } }
        for i in 0..n { if t[i] >= 65 && t[i] <= 90 { up += 1; } }
        for i in 0..n { if t[i] >= 48 && t[i] <= 57 { dig += t[i] as i64; } }
        for i in 0..n { low[i] = if t[i] >= 65 && t[i] <= 90 { t[i] + 32 } else { t[i] }; }
    }
    let mut h: i64 = 0; for i in 0..n { h = h.wrapping_mul(31).wrapping_add(low[i] as i64); }
    println!("{}\n{}\n{}\n{}", sp, up, dig, h);
}
