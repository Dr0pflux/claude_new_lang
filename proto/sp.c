#include <immintrin.h>
#include <stdio.h>
#include <time.h>
static double now(){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec+t.tv_nsec*1e-9;}
#define N 3000
static double v[N], o[N];
static inline __m512d rcpx(__m512d b){
  const __m512d one=_mm512_set1_pd(1.0);
  __m512d y0=_mm512_rcp14_pd(b), e0=_mm512_fnmadd_pd(b,y0,one), t0=_mm512_fmadd_pd(e0,e0,e0), y1=_mm512_fmadd_pd(y0,t0,y0);
  __m512d e1=_mm512_fnmadd_pd(b,y1,one), y2=_mm512_fmadd_pd(y1,e1,y1), e2=_mm512_fnmadd_pd(b,y2,one), y3=_mm512_fmadd_pd(y2,e2,y2);
  __m512d r=_mm512_fnmadd_pd(b,y3,one);
  __m512d qn=_mm512_castsi512_pd(_mm512_add_epi64(_mm512_castpd_si512(y3),_mm512_set1_epi64(1)));
  __mmask8 k=_mm512_cmp_pd_mask(_mm512_add_pd(r,r),_mm512_mul_pd(b,_mm512_sub_pd(qn,y3)),_CMP_GT_OQ);
  return _mm512_mask_blend_pd(k,y3,qn);
}
static inline __m256d rcpy(__m256d b){
  const __m256d one=_mm256_set1_pd(1.0);
  __m256d y0=_mm256_rcp14_pd(b), e0=_mm256_fnmadd_pd(b,y0,one), t0=_mm256_fmadd_pd(e0,e0,e0), y1=_mm256_fmadd_pd(y0,t0,y0);
  __m256d e1=_mm256_fnmadd_pd(b,y1,one), y2=_mm256_fmadd_pd(y1,e1,y1), e2=_mm256_fnmadd_pd(b,y2,one), y3=_mm256_fmadd_pd(y2,e2,y2);
  __m256d r=_mm256_fnmadd_pd(b,y3,one);
  __m256d qn=_mm256_castsi256_pd(_mm256_add_epi64(_mm256_castpd_si256(y3),_mm256_set1_epi64x(1)));
  __mmask8 k=_mm256_cmp_pd_mask(_mm256_add_pd(r,r),_mm256_mul_pd(b,_mm256_sub_pd(qn,y3)),_CMP_GT_OQ);
  return _mm256_mask_blend_pd(k,y3,qn);
}
static inline __m512d dz(__m512i I, __m512i J){ __m512i t=_mm512_add_epi64(I,J); __m512i p=_mm512_mullo_epi64(t,_mm512_add_epi64(t,_mm512_set1_epi64(1)));
  p=_mm512_add_epi64(_mm512_add_epi64(_mm512_srai_epi64(p,1),I),_mm512_set1_epi64(1)); return _mm512_cvtepi64_pd(p); }
static inline __m256d dy(__m256i I, __m256i J){ __m256i t=_mm256_add_epi64(I,J); __m256i p=_mm256_mullo_epi64(t,_mm256_add_epi64(t,_mm256_set1_epi64x(1)));
  p=_mm256_add_epi64(_mm256_add_epi64(_mm256_srai_epi64(p,1),I),_mm256_set1_epi64x(1)); return _mm256_cvtepi64_pd(p); }
double run(int mode){
  double t=now();
  for(int rep=0;rep<40;rep++){
   for(long i=0;i+16<=N;i+=16){
    __m512i I0=_mm512_add_epi64(_mm512_set1_epi64(i),_mm512_set_epi64(7,6,5,4,3,2,1,0)), I1=_mm512_add_epi64(I0,_mm512_set1_epi64(8));
    __m256i Y0=_mm512_castsi512_si256(I0),Y1=_mm512_extracti64x4_epi64(I0,1),Y2=_mm512_castsi512_si256(I1),Y3=_mm512_extracti64x4_epi64(I1,1);
    __m512d s0=_mm512_setzero_pd(),s1=s0; __m256d a0=_mm256_setzero_pd(),a1=a0,a2=a0,a3=a0;
    for(long j=0;j<N;j++){
      __m512i J=_mm512_set1_epi64(j);
      if(mode==0){
        s0=_mm512_add_pd(s0,_mm512_mul_pd(_mm512_div_pd(_mm512_set1_pd(1.0),dz(I0,J)),_mm512_set1_pd(v[j])));
        s1=_mm512_add_pd(s1,_mm512_mul_pd(_mm512_div_pd(_mm512_set1_pd(1.0),dz(I1,J)),_mm512_set1_pd(v[j])));
      } else if(mode==1){
        __m512d d0=dz(I0,J),d1=dz(I1,J); __m256d one=_mm256_set1_pd(1.0);
        __m512d q0=_mm512_insertf64x4(_mm512_castpd256_pd512(_mm256_div_pd(one,_mm512_castpd512_pd256(d0))),_mm256_div_pd(one,_mm512_extractf64x4_pd(d0,1)),1);
        __m512d q1=_mm512_insertf64x4(_mm512_castpd256_pd512(_mm256_div_pd(one,_mm512_castpd512_pd256(d1))),_mm256_div_pd(one,_mm512_extractf64x4_pd(d1,1)),1);
        s0=_mm512_add_pd(s0,_mm512_mul_pd(q0,_mm512_set1_pd(v[j]))); s1=_mm512_add_pd(s1,_mm512_mul_pd(q1,_mm512_set1_pd(v[j])));
      } else if(mode==2){
        __m256i JY=_mm256_set1_epi64x(j); __m256d one=_mm256_set1_pd(1.0), V=_mm256_set1_pd(v[j]);
        a0=_mm256_add_pd(a0,_mm256_mul_pd(_mm256_div_pd(one,dy(Y0,JY)),V)); a1=_mm256_add_pd(a1,_mm256_mul_pd(_mm256_div_pd(one,dy(Y1,JY)),V));
        a2=_mm256_add_pd(a2,_mm256_mul_pd(_mm256_div_pd(one,dy(Y2,JY)),V)); a3=_mm256_add_pd(a3,_mm256_mul_pd(_mm256_div_pd(one,dy(Y3,JY)),V));
      } else if(mode==3){
        __m256i JY=_mm256_set1_epi64x(j); __m256d one=_mm256_set1_pd(1.0), V=_mm256_set1_pd(v[j]);
        a0=_mm256_add_pd(a0,_mm256_mul_pd(_mm256_div_pd(one,dy(Y0,JY)),V)); a1=_mm256_add_pd(a1,_mm256_mul_pd(_mm256_div_pd(one,dy(Y1,JY)),V));
        a2=_mm256_add_pd(a2,_mm256_mul_pd(_mm256_div_pd(one,dy(Y2,JY)),V)); a3=_mm256_add_pd(a3,_mm256_mul_pd(rcpy(dy(Y3,JY)),V));
      } else if(mode==4){
        __m512d d0=dz(I0,J),d1=dz(I1,J); __m256d one=_mm256_set1_pd(1.0);
        __m512d q0=_mm512_insertf64x4(_mm512_castpd256_pd512(_mm256_div_pd(one,_mm512_castpd512_pd256(d0))),_mm256_div_pd(one,_mm512_extractf64x4_pd(d0,1)),1);
        s0=_mm512_add_pd(s0,_mm512_mul_pd(q0,_mm512_set1_pd(v[j]))); s1=_mm512_add_pd(s1,_mm512_mul_pd(rcpx(d1),_mm512_set1_pd(v[j])));
      } else if(mode==5){
        __m256i JY=_mm256_set1_epi64x(j); __m256d one=_mm256_set1_pd(1.0), V=_mm256_set1_pd(v[j]);
        a0=_mm256_add_pd(a0,_mm256_mul_pd(_mm256_div_pd(one,dy(Y0,JY)),V)); a1=_mm256_add_pd(a1,_mm256_mul_pd(_mm256_div_pd(one,dy(Y1,JY)),V));
        a2=_mm256_add_pd(a2,_mm256_mul_pd(rcpy(dy(Y2,JY)),V)); a3=_mm256_add_pd(a3,_mm256_mul_pd(rcpy(dy(Y3,JY)),V));
      } else if(mode==6){ // zmm x2 both sw
        s0=_mm512_add_pd(s0,_mm512_mul_pd(rcpx(dz(I0,J)),_mm512_set1_pd(v[j])));
        s1=_mm512_add_pd(s1,_mm512_mul_pd(rcpx(dz(I1,J)),_mm512_set1_pd(v[j])));
      }
    }
    _mm512_storeu_pd(o+i,_mm512_add_pd(s0,_mm512_insertf64x4(_mm512_castpd256_pd512(a0),a1,1)));
    _mm512_storeu_pd(o+i+8,_mm512_add_pd(s1,_mm512_insertf64x4(_mm512_castpd256_pd512(a2),a3,1)));
   }
  }
  return now()-t;
}
int main(){ for(int i=0;i<N;i++) v[i]=1.0+i*1e-4;
  const char*nm[]={"zmm hw div","zmm, ymm-split div","ymm x4 hw","ymm x4: 3hw+1sw","zmm: 1 split-hw + 1 sw","ymm x4: 2hw+2sw","zmm x2 sw"};
  for(int m=0;m<7;m++){ double t=run(m); printf("%-26s %6.1f ms  (%.2f cyc/elem)\n",nm[m],t*1e3,t*2.8e9/(40.0*N*N)); } }
