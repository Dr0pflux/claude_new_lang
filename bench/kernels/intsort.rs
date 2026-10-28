fn merge(src: &[i64], dst: &mut [i64], lo: usize, mid: usize, hi: usize) {
    let (mut i, mut j, mut o) = (lo, mid, lo);
    while i < mid && j < hi {
        if src[j] < src[i] { dst[o] = src[j]; j += 1; } else { dst[o] = src[i]; i += 1; }
        o += 1;
    }
    while i < mid { dst[o] = src[i]; i += 1; o += 1; }
    while j < hi { dst[o] = src[j]; j += 1; o += 1; }
}
fn pass(src: &[i64], dst: &mut [i64], n: usize, w: usize) {
    let mut lo = 0;
    while lo < n {
        let mid = if lo + w > n { n } else { lo + w };
        let hi = if lo + 2 * w > n { n } else { lo + 2 * w };
        merge(src, dst, lo, mid, hi);
        lo += 2 * w;
    }
}
fn chk(a: &[i64]) {
    let n = a.len(); let mut s: i64 = 0; let mut ok = 1;
    for i in 0..n { s = s.wrapping_mul(31).wrapping_add(a[i]); if i > 0 && a[i - 1] > a[i] { ok = 0; } }
    println!("{}\n{}\n{}\n{}", s, ok, a[0], a[n - 1]);
}
fn main() {
    let n: usize = 2000000 + std::env::args().count() - 1;
    let mut a = vec![0i64; n]; let mut b = vec![0i64; n];
    let mut x: u64 = 88172645463325252;
    for i in 0..n { x ^= x << 13; x ^= x >> 7; x ^= x << 17; a[i] = (x >> 20) as i64; }
    let mut lo = 0;
    while lo < n {
        let hi = if lo + 16 > n { n } else { lo + 16 };
        for i in lo + 1..hi {
            let v = a[i]; let mut j = i as isize - 1;
            while j >= lo as isize && a[j as usize] > v { a[j as usize + 1] = a[j as usize]; j -= 1; }
            a[(j + 1) as usize] = v;
        }
        lo += 16;
    }
    let mut w = 16; let mut flip = 0;
    while w < n {
        if flip == 0 { pass(&a, &mut b, n, w); } else { pass(&b, &mut a, n, w); }
        flip = 1 - flip; w *= 2;
    }
    if flip == 0 { chk(&a); } else { chk(&b); }
}
