// Wrapping 64-bit complementary-shift addition, matched with mix.c.
fn main(){let n=100000000+argc()-1;let mut x:u64=88172645463325252;for i in 0..n{x=((x<<5)+(x>>>59))^(i as u64);}print(x);}
