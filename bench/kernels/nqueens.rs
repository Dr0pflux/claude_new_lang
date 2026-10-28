fn place(r: i64, n: i64, c: &mut [u8], d1: &mut [u8], d2: &mut [u8]) -> i64 {
    if r == n { return 1; }
    let mut cnt = 0;
    for col in 0..n {
        let (ci, a, b) = (col as usize, (r + col) as usize, (r - col + n) as usize);
        if c[ci] == 0 && d1[a] == 0 && d2[b] == 0 {
            c[ci] = 1; d1[a] = 1; d2[b] = 1;
            cnt += place(r + 1, n, c, d1, d2);
            c[ci] = 0; d1[a] = 0; d2[b] = 0;
        }
    }
    cnt
}
fn main() {
    let n: i64 = 13 + std::env::args().count() as i64 - 1;
    let (mut c, mut d1, mut d2) = ([0u8; 64], [0u8; 64], [0u8; 64]);
    println!("{}", place(0, n, &mut c, &mut d1, &mut d2));
}
