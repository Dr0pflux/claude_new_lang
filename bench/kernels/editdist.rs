fn lev(t: &[u8], o1: usize, la: usize, o2: usize, lb: usize, row: &mut [i64]) -> i64 {
    for j in 0..=lb { row[j] = j as i64; }
    for i in 1..=la {
        let mut diag = row[0]; row[0] = i as i64;
        for j in 1..=lb {
            let up = row[j];
            let cost = if t[o1 + i - 1] != t[o2 + j - 1] { 1 } else { 0 };
            let mut v = diag + cost;
            if row[j - 1] + 1 < v { v = row[j - 1] + 1; }
            if up + 1 < v { v = up + 1; }
            row[j] = v; diag = up;
        }
    }
    row[lb]
}
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
    let mut row = [0i64; 32]; let (mut tot, mut x): (i64, i64) = (0, 0);
    for p in 0..1000000 as usize {
        let o1 = (p * 40503) % (n - 32); let o2 = (p * 65537 + 12345) % (n - 32);
        let la = 6 + p % 8; let lb = 6 + (p >> 3) % 8;
        let d = lev(&t, o1, la, o2, lb, &mut row);
        tot += d; x = x ^ (d << (p & 31));
    }
    println!("{}\n{}", tot, x);
}
