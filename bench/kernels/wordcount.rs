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
    let (mut lines, mut words, mut chars): (i64, i64, i64) = (0, 0, 0);
    for _ in 0..20 {
        let mut inw = 0;
        for i in 0..n {
            let c = t[i];
            chars += 1;
            if c == 10 { lines += 1; }
            if c == 32 || c == 10 || c == 9 { inw = 0; } else { if inw == 0 { words += 1; } inw = 1; }
        }
    }
    println!("{}\n{}\n{}", lines, words, chars);
}
