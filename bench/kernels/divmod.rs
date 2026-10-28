fn main() {
    let n: i64 = 60000000 + std::env::args().count() as i64 - 1; let mut sum: i64 = 0;
    for i in 0..n {
        let k = ((i >> 3) & 1023) + 3;
        let x = i.wrapping_mul(2654435761) & 0x7fffffffffff;
        sum = sum.wrapping_add(x / k + x % k);
    }
    println!("{}", sum);
}
