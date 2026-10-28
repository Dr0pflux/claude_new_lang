fn main(){
  let argc=std::env::args().count() as i64;
  let mut seed:i64=777+argc; let mut acc:i64=0; let mut i:i64=0;
  while i<200000000 {
    seed=seed.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
    let p=((seed as u64)>>40) as i64 % 29;
    let k=(i%7)*11+3;
    let c=(p+k)%29;
    acc=acc.wrapping_mul(31).wrapping_add(c);
    i+=1;
  }
  println!("{}",acc);
}
