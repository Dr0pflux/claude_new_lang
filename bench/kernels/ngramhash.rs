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
    let mut cnt = vec![0u32; 65536];
    for _ in 0..40 {
        for i in 0..n - 2 {
            let g = ((t[i] as i64) << 16) | ((t[i + 1] as i64) << 8) | t[i + 2] as i64;
            let h = ((g * 2654435761) >> 16) & 65535;
            cnt[h as usize] += 1;
        }
    }
    let (mut s, mut nz, mut mx): (i64, i64, i64) = (0, 0, 0);
    for k in 0..65536 {
        let c = cnt[k] as i64;
        s = s.wrapping_mul(31).wrapping_add(c); if c != 0 { nz += 1; } if c > mx { mx = c; }
    }
    println!("{}\n{}\n{}", s, nz, mx);
}
