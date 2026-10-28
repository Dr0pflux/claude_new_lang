// Rolling 29-ary 5-gram index over a pseudo-random Alphabet<29> stream.
// Arithmetic-only proxy (no memory yet): the "score" is a multiplicative hash
// of the 5-gram index instead of a table lookup.
fn main() -> i64 {
  let mut seed = 12345 + argc();
  let mut h = 0;
  let mut sum = 0;
  let mut i = 0;
  while i < 200000000 {
    seed = seed * 6364136223846793005 + 1442695040888963407;
    let sym = (seed >>> 33) % 29;
    h = (h * 29 + sym) % 20511149;
    sum += (h * 2654435761) >>> 20;
    i += 1;
  }
  return sum;
}
