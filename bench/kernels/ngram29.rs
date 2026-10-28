fn main(){
  let argc=std::env::args().count() as i64;
  let mut seed:i64=12345+argc; let mut h:i64=0; let mut sum:i64=0; let mut i:i64=0;
  while i<200000000 {
    seed=seed.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
    let sym=((seed as u64)>>33) as i64 % 29;
    h=(h*29+sym)%20511149;
    sum=sum.wrapping_add(((h.wrapping_mul(2654435761)) as u64 >> 20) as i64);
    i+=1;
  }
  println!("{}",sum);
}
