#include <immintrin.h>
#include <stdio.h>
#include <time.h>
#include <stdint.h>
#include <string.h>
static double now(){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec+t.tv_nsec*1e-9;}
#define N 3000
static double v[N], o[N];
// RN(1/x) for x = integer-valued double, significand neither zero nor all-ones (caller checks)
static inline __m512d rcpm(__m512d x){
  const __m512d one=_mm512_set1_pd(1.0);
  __m512d y0=_mm512_rcp14_pd(x);
  __m512d e0=_mm512_fnmadd_pd(x,y0,one);
  __m512d q1=_mm512_fmadd_pd(e0,e0,e0);
  __m512d q2=_mm512_fmadd_pd(q1,e0,e0);
  __m512d y=_mm512_fmadd_pd(y0,q2,y0);
  __m512d e=_mm512_fnmadd_pd(x,y,one);
  return _mm512_fmadd_pd(y,e,y);
}
static inline __m256d rcpmy(__m256d x){
  const __m256d one=_mm256_set1_pd(1.0);
  __m256d y0=_mm256_rcp14_pd(x);
  __m256d e0=_mm256_fnmadd_pd(x,y0,one);
  __m256d q1=_mm256_fmadd_pd(e0,e0,e0);
  __m256d q2=_mm256_fmadd_pd(q1,e0,e0);
  __m256d y=_mm256_fmadd_pd(y0,q2,y0);
  __m256d e=_mm256_fnmadd_pd(x,y,one);
  return _mm256_fmadd_pd(y,e,y);
}
static inline __m512i dzi(__m512i I, __m512i J){ __m512i t=_mm512_add_epi64(I,J); __m512i p=_mm512_mullo_epi64(t,_mm512_add_epi64(t,_mm512_set1_epi64(1)));
  return _mm512_add_epi64(_mm512_add_epi64(_mm512_srai_epi64(p,1),I),_mm512_set1_epi64(1)); }
static inline __m256i dyi(__m256i I, __m256i J){ __m256i t=_mm256_add_epi64(I,J); __m256i p=_mm256_mullo_epi64(t,_mm256_add_epi64(t,_mm256_set1_epi64x(1)));
  return _mm256_add_epi64(_mm256_add_epi64(_mm256_srai_epi64(p,1),I),_mm256_set1_epi64x(1)); }
static long nexc;
double run(int mode){
  double t=now();
  const __m512i M=_mm512_set1_epi64(0xFFFFFFFFFFFFFull), ONE=_mm512_set1_epi64(1), TWO=_mm512_set1_epi64(2);
  for(int rep=0;rep<40;rep++){
   if(mode>=3){
    for(long i=0;i+8<=N;i+=8){
     __m256i I0=_mm256_add_epi64(_mm256_set1_epi64x(i),_mm256_set_epi64x(3,2,1,0)), I1=_mm256_add_epi64(I0,_mm256_set1_epi64x(4));
     __m256d s0=_mm256_setzero_pd(),s1=s0;
     for(long j=0;j<N;j++){
      __m256i J=_mm256_set1_epi64x(j); __m256d V=_mm256_set1_pd(v[j]);
      __m256d d0=_mm256_cvtepi64_pd(dyi(I0,J)), d1=_mm256_cvtepi64_pd(dyi(I1,J));
      if(mode==3){
       s0=_mm256_add_pd(s0,_mm256_mul_pd(_mm256_div_pd(_mm256_set1_pd(1.0),d0),V));
       s1=_mm256_add_pd(s1,_mm256_mul_pd(_mm256_div_pd(_mm256_set1_pd(1.0),d1),V));
      } else {
       __m256i b=_mm256_castpd_si256(d1);
       __mmask8 k=_mm256_cmplt_epu64_mask(_mm256_and_si256(_mm256_add_epi64(b,_mm256_set1_epi64x(1)),_mm256_set1_epi64x(0xFFFFFFFFFFFFFull)),_mm256_set1_epi64x(2));
       __m256d r1=rcpmy(d1);
       if(__builtin_expect(k!=0,0)){ nexc++; r1=_mm256_mask_div_pd(r1,k,_mm256_set1_pd(1.0),d1); }
       s0=_mm256_add_pd(s0,_mm256_mul_pd(_mm256_div_pd(_mm256_set1_pd(1.0),d0),V));
       s1=_mm256_add_pd(s1,_mm256_mul_pd(r1,V));
      }
     }
     _mm256_storeu_pd(o+i,s0); _mm256_storeu_pd(o+i+4,s1);
    }
    continue;
   }
   for(long i=0;i+16<=N;i+=16){
    __m512i I0=_mm512_add_epi64(_mm512_set1_epi64(i),_mm512_set_epi64(7,6,5,4,3,2,1,0)), I1=_mm512_add_epi64(I0,_mm512_set1_epi64(8));
    __m512d s0=_mm512_setzero_pd(),s1=s0;
    for(long j=0;j<N;j++){
      __m512i J=_mm512_set1_epi64(j);
      __m512d V=_mm512_set1_pd(v[j]);
      __m512d d0=_mm512_cvtepi64_pd(dzi(I0,J)), d1=_mm512_cvtepi64_pd(dzi(I1,J));
      if(mode==0){
        s0=_mm512_add_pd(s0,_mm512_mul_pd(_mm512_div_pd(_mm512_set1_pd(1.0),d0),V));
        s1=_mm512_add_pd(s1,_mm512_mul_pd(_mm512_div_pd(_mm512_set1_pd(1.0),d1),V));
      } else if(mode==1){ // half hw, half sw
        __m512i b=_mm512_castpd_si512(d1);
        __mmask8 k=_mm512_cmplt_epu64_mask(_mm512_and_si512(_mm512_add_epi64(b,ONE),M),TWO);
        __m512d r1=rcpm(d1);
        if(__builtin_expect(k!=0,0)){ nexc++; r1=_mm512_mask_div_pd(r1,k,_mm512_set1_pd(1.0),d1); }
        s0=_mm512_add_pd(s0,_mm512_mul_pd(_mm512_div_pd(_mm512_set1_pd(1.0),d0),V));
        s1=_mm512_add_pd(s1,_mm512_mul_pd(r1,V));
      } else if(mode==2){ // both sw
        __m512i b0=_mm512_castpd_si512(d0), b1=_mm512_castpd_si512(d1);
        __mmask8 k0=_mm512_cmplt_epu64_mask(_mm512_and_si512(_mm512_add_epi64(b0,ONE),M),TWO);
        __mmask8 k1=_mm512_cmplt_epu64_mask(_mm512_and_si512(_mm512_add_epi64(b1,ONE),M),TWO);
        __m512d r0=rcpm(d0), r1=rcpm(d1);
        if(__builtin_expect((k0|k1)!=0,0)){ nexc++; r0=_mm512_mask_div_pd(r0,k0,_mm512_set1_pd(1.0),d0); r1=_mm512_mask_div_pd(r1,k1,_mm512_set1_pd(1.0),d1); }
        s0=_mm512_add_pd(s0,_mm512_mul_pd(r0,V));
        s1=_mm512_add_pd(s1,_mm512_mul_pd(r1,V));
      }
    }
    _mm512_storeu_pd(o+i,s0); _mm512_storeu_pd(o+i+8,s1);
   }
  }
  return now()-t;
}
// exactness check vs hardware division
static int check(long iters){
  long bad=0; const __m512d one=_mm512_set1_pd(1.0);
  const __m512i M=_mm512_set1_epi64(0xFFFFFFFFFFFFFull), ONE=_mm512_set1_epi64(1), TWO=_mm512_set1_epi64(2);
  uint64_t s=88172645463325252ull;
  for(long it=0; it<iters; it++){
    int64_t xs[8];
    for(int l=0;l<8;l++){ s^=s<<13; s^=s>>7; s^=s<<17;
      int sh=(int)(s>>58); int64_t x=(int64_t)((s*0x9E3779B97F4A7C15ull)>>sh);
      if((it&3)==1) x=it*8+l;
      if((it&3)==2) x=((int64_t)1<<(s>>59&63)) + (int64_t)((s>>8)&15) - 8;
      if((s>>3)&1) x=-x; xs[l]=x; }
    __m512d d=_mm512_cvtepi64_pd(_mm512_loadu_si512(xs));
    __m512i b=_mm512_castpd_si512(d);
    __mmask8 k=_mm512_cmplt_epu64_mask(_mm512_and_si512(_mm512_add_epi64(b,ONE),M),TWO);
    __m512d r=rcpm(d); r=_mm512_mask_div_pd(r,k,one,d);
    __m512d h=_mm512_div_pd(one,d);
    __mmask8 ne=_mm512_cmpneq_epi64_mask(_mm512_castpd_si512(r),_mm512_castpd_si512(h));
    if(ne){ bad++; if(bad<10){ for(int l=0;l<8;l++) if(ne>>l&1) printf("mismatch x=%ld\n",(long)xs[l]); } }
  }
  printf("check: %ld bad of %ld\n",bad,iters*8); return bad!=0;
}
int main(int argc,char**argv){ for(int i=0;i<N;i++) v[i]=1.0+i*1e-4;
  if(argc>2){ int exh(long,long); return exh(atol(argv[1]),atol(argv[2])); }
  if(argc>1){ return check(atol(argv[1])); }
  const char*nm[]={"zmm hw div x2","zmm hw + sw","zmm sw x2","ymm hw div x2","ymm hw + sw"};
  for(int m=0;m<5;m++){ double t=run(m); printf("%-24s %6.1f ms  (%.2f cyc/elem) exc=%ld\n",nm[m],t*1e3,t*2.8e9/(40.0*N*N),nexc); } }
// exhaustive over [lo, hi)
int exh(long lo, long hi){
  long bad=0; const __m512d one=_mm512_set1_pd(1.0);
  const __m512i M=_mm512_set1_epi64(0xFFFFFFFFFFFFFull), ONE=_mm512_set1_epi64(1), TWO=_mm512_set1_epi64(2);
  __m512i X=_mm512_add_epi64(_mm512_set1_epi64(lo),_mm512_set_epi64(7,6,5,4,3,2,1,0)), E=_mm512_set1_epi64(8);
  for(long x=lo;x<hi;x+=8){
    __m512d d=_mm512_cvtepi64_pd(X); X=_mm512_add_epi64(X,E);
    __m512i b=_mm512_castpd_si512(d);
    __mmask8 k=_mm512_cmplt_epu64_mask(_mm512_and_si512(_mm512_add_epi64(b,ONE),M),TWO);
    __m512d r=rcpm(d); r=_mm512_mask_div_pd(r,k,one,d);
    __m512d h=_mm512_div_pd(one,d);
    if(_mm512_cmpneq_epi64_mask(_mm512_castpd_si512(r),_mm512_castpd_si512(h))) bad++;
  }
  printf("exh [%ld,%ld): %ld bad\n",lo,hi,bad); return bad!=0;
}
