// Sum of x / k and x % k with a runtime-varying divisor.
fn main() {
  let n = 60000000 + argc() - 1;
  let mut sum = 0;
  for i in 0..n {
    let k = ((i >> 3) & 1023) + 3;
    let x = (i * 2654435761) & 0x7fffffffffff;
    sum += x / k + x % k;
  }
  print(sum);
}
