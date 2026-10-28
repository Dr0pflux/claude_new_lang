fn main() {
    let n: i64 = 2600 + std::env::args().count() as i64 - 1; let mut sum: i64 = 0;
    for i in 1..n { for j in 1..n {
        let (mut a, mut b) = (i, j);
        while b != 0 { let t = a % b; a = b; b = t; }
        sum += a;
    } }
    println!("{}", sum);
}
