fn main() {
    let n: i64 = 1500000 + std::env::args().count() as i64 - 1;
    let (mut best, mut arg): (i64, i64) = (0, 0);
    for s in 1..n {
        let mut x = s; let mut steps: i64 = 0;
        while x != 1 { if x & 1 == 0 { x = x >> 1; } else { x = 3 * x + 1; } steps += 1; }
        if steps > best { best = steps; arg = s; }
    }
    println!("{}\n{}", arg, best);
}
