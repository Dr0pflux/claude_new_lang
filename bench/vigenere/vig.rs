// Same algorithm as vig.cock (i64 arithmetic, safe indexing = bounds checked).
use std::io::Write;
fn main(){
  let a:Vec<String>=std::env::args().collect();
  let tb=std::fs::read(&a[1]).unwrap();
  let q:Vec<i16>=tb.chunks_exact(2).map(|b|i16::from_le_bytes([b[0],b[1]])).collect();
  if q.len()<456976{println!("-1");return;}
  let ct=std::fs::read(&a[2]).unwrap();
  let uni:[i64;26]=[8167,1492,2782,4253,12702,2228,2015,6094,6966,153,772,4025,2406,6749,7507,1929,95,5987,6327,9056,2758,978,2360,150,1974,74];
  let mut c=vec![0u8;4096];let mut p=vec![0u8;4096];let mut key=[0u8;32];let mut cnt=[0i32;520];let mut ioc=[0i64;21];
  let ctlen=ct.len() as i64;let mut pos:i64=0;let mut total:i64=0;
  let out=std::io::stdout();let mut o=std::io::BufWriter::new(out.lock());
  while pos<ctlen{
    let mut n:i64=0;
    while pos<ctlen&&ct[pos as usize]!=10{let ch=ct[pos as usize] as i64;if ch>=65&&ch<=90&&n<4096{c[n as usize]=(ch-65) as u8;n+=1;}pos+=1;}
    pos+=1;
    if n<8{continue;}
    let mut bests:i64=0;
    for pp in 1..=20i64{
      for z in 0..26*pp{cnt[z as usize]=0;}
      for i in 0..n{cnt[((i%pp)*26+c[i as usize] as i64) as usize]+=1;}
      let mut num:i64=0;let mut den:i64=0;
      for col in 0..pp{let mut nc:i64=0;for l in 0..26{let f=cnt[(col*26+l) as usize] as i64;num+=f*(f-1);nc+=f;}den+=nc*(nc-1);}
      let mut sc:i64=0;if den>0{sc=num*10000/den;}
      ioc[pp as usize]=sc;if sc>bests{bests=sc;}
    }
    let mut per:i64=1;
    for pp in 1..=20i64{if ioc[pp as usize]*10>=bests*9{per=pp;break;}}
    for z in 0..26*per{cnt[z as usize]=0;}
    for i in 0..n{cnt[((i%per)*26+c[i as usize] as i64) as usize]+=1;}
    for j in 0..per{
      let mut bk:i64=0;let mut bv:i64=-1;
      for k in 0..26i64{let mut v:i64=0;for l in 0..26i64{v+=cnt[(j*26+(l+k)%26) as usize] as i64*uni[l as usize];}if v>bv{bv=v;bk=k;}}
      key[j as usize]=bk as u8;
    }
    for i in 0..n{p[i as usize]=((c[i as usize] as i64-key[(i%per) as usize] as i64+26)%26) as u8;}
    let mut pass=0;let mut improved=1;
    while pass<4&&improved!=0{
      improved=0;
      for j in 0..per{
        let mut bestk=key[j as usize] as i64;let mut bestsc:i64=-i64::MAX;
        for k in 0..26i64{
          let mut i=j;while i<n{p[i as usize]=((c[i as usize] as i64-k+26)%26) as u8;i+=per;}
          let mut sc:i64=0;
          let g=|s:i64,p:&Vec<u8>|->i64{let s=s as usize;q[(((p[s] as i64*26+p[s+1] as i64)*26+p[s+2] as i64)*26+p[s+3] as i64) as usize] as i64};
          if per>=4{
            let mut i=j;
            while i<n{let mut s=i-3;if s<0{s=0;}let mut e=i;if e>n-4{e=n-4;}while s<=e{sc+=g(s,&p);s+=1;}i+=per;}
          }else{let mut s=0;while s<=n-4{sc+=g(s,&p);s+=1;}}
          if sc>bestsc{bestsc=sc;bestk=k;}
        }
        if bestk!=key[j as usize] as i64{key[j as usize]=bestk as u8;improved=1;}
        let mut i=j;while i<n{p[i as usize]=((c[i as usize] as i64-bestk+26)%26) as u8;i+=per;}
      }
      pass+=1;
    }
    let mut s=0;while s<=n-4{let u=s as usize;total+=q[(((p[u] as i64*26+p[u+1] as i64)*26+p[u+2] as i64)*26+p[u+3] as i64) as usize] as i64;s+=1;}
    for j in 0..per{o.write_all(&[key[j as usize]+65]).unwrap();}
    o.write_all(b"\n").unwrap();
  }
  writeln!(o,"{}",total).unwrap();
}
