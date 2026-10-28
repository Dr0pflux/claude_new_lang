// Sum of gcd(i, j) for 1 <= i, j < N, Euclid with %.
fn main() {
  let n = 2600 + argc() - 1;
  let mut sum = 0;
  for i in 1..n { for j in 1..n {
    let mut a = i; let mut b = j;
    while b != 0 { let t = a % b; a = b; b = t; }
    sum += a;
  } }
  print(sum);
}
