fn count(t: &[u8], p: &[u8]) -> i64 {
    let (n, m) = (t.len(), p.len()); let mut cnt = 0; let mut i = 0;
    while i + m <= n {
        let mut j = 0;
        while j < m && t[i + j] == p[j] { j += 1; }
        if j == m { cnt += 1; }
        i += 1;
    }
    cnt
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
    let (mut s1, mut s2, mut s3, mut s4, mut s5): (i64, i64, i64, i64, i64) = (0, 0, 0, 0, 0);
    for _ in 0..10 {
        s1 += count(&t, b"the"); s2 += count(&t, b"ab"); s3 += count(&t, b"e a"); s4 += count(&t, b"qxz"); s5 += count(&t, b"ing.");
    }
    println!("{}\n{}\n{}\n{}\n{}", s1, s2, s3, s4, s5);
}
