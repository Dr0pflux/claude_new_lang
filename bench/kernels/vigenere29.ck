// Alphabet<29> periodic-key (Vigenere-style) transform: c = (p + k[i mod 7]) mod 29,
// key derived arithmetically; checksum over ciphertext symbols.
fn main() -> i64 {
  let mut seed = 777 + argc();
  let mut acc = 0;
  let mut i = 0;
  while i < 200000000 {
    seed = seed * 6364136223846793005 + 1442695040888963407;
    let p = (seed >>> 40) % 29;
    let k = (i % 7) * 11 + 3;
    let c = (p + k) % 29;
    acc = acc * 31 + c;
    i += 1;
  }
  return acc;
}
