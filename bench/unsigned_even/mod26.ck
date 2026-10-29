// Dependent wrapping modulo recurrence, matched with mod26.c.
fn main(){let n=50000000+argc()-1;let mut x:u64=88172645463325252;for i in 0..n{x=(x%(26 as u64))^(i as u64)^0xFEDCBA9876543210;}print(x);}
