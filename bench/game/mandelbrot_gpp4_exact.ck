// Skite port of the Computer Language Benchmarks Game C++ g++ #4 Mandelbrot.
// Original implementation: Markus Flad (3-Clause BSD), with 8-pixel groups,
// five iterations per block, last-byte escape shortcut, and interlaced rows.
fn decimal_arg(s: [u8]) -> i64 {
    let mut v: i64 = 0;
    let mut i: i64 = 0;
    while i < len(s) && s[i] >= 48 && s[i] <= 57 {
        v = v * 10 + (s[i] - 48);
        i += 1;
    }
    return v;
}
fn put_decimal(v: i64) {
    if v >= 10 { put_decimal(v / 10); }
    putc(v % 10 + 48);
}
fn main() {
    let arg = argv(1);
    let n = decimal_arg(arg);
    if n < 1 || n > 100000 { return; }
    let mut workers = ncpu();
    if workers < 1 { workers = 1; }
    if workers > 256 { workers = 256; }
    let width = ((n + 7) / 8) * 8;
    let height = ((n + workers - 1) / workers) * workers;
    let row_bytes = width / 8;
    let result = shared<u8>(row_bytes * height);
    let dx: f64 = 2.0 / (width as f64);
    let dy: f64 = 2.0 / (height as f64);
    let cr = alloc<f64>(width);
    for x in 0..width {
        cr[x] = -1.5 + (x as f64) * dx;
    }
    let zr = alloc<f64>(8);
    let zi = alloc<f64>(8);
    let squared_abs = alloc<f64>(8);
    par worker in 0..workers {
        let mut y = worker;
        while y < height {
            let ci: f64 = -1.0 + (y as f64) * dy;
            let mut previous_byte: i64 = 0;
            let mut byte_x: i64 = 0;
            while byte_x < row_bytes {
                let x0 = byte_x * 8;
                for lane in 0..8 {
                    zr[lane] = cr[x0 + lane];
                    zi[lane] = ci;
                }
                let mut skipped = false;
                let mut block: i64 = 0;
                while block < 10 {
                    for step in 0..5 {
                        for lane in 0..8 {
                            let ar = zr[lane];
                            let ai = zi[lane];
                            let r2 = ar * ar;
                            let i2 = ai * ai;
                            let ri = ar * ai;
                            zr[lane] = r2 - i2 + cr[x0 + lane];
                            zi[lane] = ri + ri + ci;
                            squared_abs[lane] = r2 + i2;
                        }
                    }
                    block += 1;
                    if previous_byte == 0 && block <= 8 {
                        let mut all_out = true;
                        for lane in 0..8 {
                            if !(squared_abs[lane] > 4.0) { all_out = false; }
                        }
                        if all_out {
                            skipped = true;
                            break;
                        }
                    }
                }
                let mut bits: i64 = 0;
                if !skipped {
                    for lane in 0..8 {
                        bits = bits << 1;
                        if squared_abs[lane] <= 4.0 { bits = bits | 1; }
                    }
                }
                result[y * row_bytes + byte_x] = bits as u8;
                previous_byte = bits;
                byte_x += 1;
            }
            y += workers;
        }
    }
    write("P4\n");
    put_decimal(width);
    putc(32);
    put_decimal(height);
    putc(10);
    write(result);
}
