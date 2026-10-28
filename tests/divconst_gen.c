/* Division/modulo-by-constant validation for skite (magic-number, power-of-2
 * and idiv-fallback paths). For each divisor d: boundary dividends plus 20000
 * pseudo-random runtime dividends of varying magnitude, folded into a checksum.
 * The C oracle computes the same checksum. usage: divconst_gen OUT_DIR
 */
#define _POSIX_C_SOURCE 200809L
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static int64_t I(uint64_t v){int64_t x;memcpy(&x,&v,8);return x;}
static uint64_t U(int64_t v){uint64_t x;memcpy(&x,&v,8);return x;}
static uint64_t sar(uint64_t x,unsigned k){return I(x)<0?~(~x>>k):x>>k;}
static int64_t ds[4096];static int nd;
static void add(int64_t d){if(d!=0)ds[nd++]=d;}
static void lit(FILE *f,int64_t v){if(v==INT64_MIN)fprintf(f,"(-9223372036854775807 - 1)");else if(v<0)fprintf(f,"(-%" PRId64 ")",-v);else fprintf(f,"%" PRId64,v);}
static int trap;
static uint64_t qd(uint64_t y,int64_t d){int64_t a=I(y);if(a==INT64_MIN&&d==-1){trap=1;return 0;}return U(a/d);}
static uint64_t rd(uint64_t y,int64_t d){int64_t a=I(y);if(a==INT64_MIN&&d==-1){trap=1;return 0;}return U(a%d);}
int main(int argc,char **argv){
    if(argc!=2)return 2;
    for(int64_t d=1;d<=300;d++){add(d);add(-d);}
    for(int k=9;k<63;k++){add((int64_t)1<<k);add(-((int64_t)1<<k));add(((int64_t)1<<k)+1);add(((int64_t)1<<k)-1);add(-(((int64_t)1<<k)+1));}
    int64_t extra[]={INT64_MAX,-INT64_MAX,INT64_MIN,INT64_MAX-1,641,6700417,20511149,24389,707281,1000000007,
        2147483647,2147483648LL,-2147483648LL,4294967295LL,4294967297LL,6364136223846793005LL,
        3074457345618258602LL,3074457345618258603LL,-3074457345618258603LL};
    for(size_t i=0;i<sizeof extra/sizeof extra[0];i++)add(extra[i]);
    uint64_t rs=0x9E3779B97F4A7C15ULL;
    for(int i=0;i<200;i++){rs^=rs<<13;rs^=rs>>7;rs^=rs<<17;add(I(rs>>(rs%60)));}
    int per=8,prog=0;
    for(int base=0;base<nd;base+=per,prog++){
        char p[600];snprintf(p,sizeof p,"%s/d%04d.cock",argv[1],prog);FILE *f=fopen(p,"w");
        snprintf(p,sizeof p,"%s/d%04d.exp",argv[1],prog);FILE *e=fopen(p,"w");
        int cnt=nd-base<per?nd-base:per;
        fprintf(f,"fn main() -> i64 {\n  let z = argc() - 1;\n  let mut acc = 0;\n");
        uint64_t acc=0;trap=0;
        /* boundary dividends: runtime values (z = 0) so they are not folded */
        for(int j=0;j<cnt;j++){
            int64_t d=ds[base+j];
            int64_t bs[]={INT64_MIN,INT64_MIN+1,-1,0,1,INT64_MAX,INT64_MAX-1,d,d+1,d-1,-d};
            for(size_t b=0;b<sizeof bs/sizeof bs[0];b++){
                int64_t y=bs[b];if(y==INT64_MIN&&d==-1)continue;
                if(d==INT64_MIN&&(b==7||b==9||b==10))continue; /* avoid literal overflow in -d / d-1 */
                fprintf(f,"  acc = acc * 31 + (z + ");lit(f,y);fprintf(f,") / ");lit(f,d);
                fprintf(f,";\n  acc = acc ^ ((z + ");lit(f,y);fprintf(f,") %% ");lit(f,d);fprintf(f,");\n");
                acc=acc*31+qd(U(y),d);acc^=rd(U(y),d);
            }
        }
        fprintf(f,"  let mut x = 88172645463325252 + z;\n  let mut i = 0;\n  while i < 20000 {\n");
        fprintf(f,"    x = x * 6364136223846793005 + 1442695040888963407;\n    let y = x >> (i & 63);\n    let u = x >>> 1;\n    let w = x >>> 40;\n");
        uint64_t x=88172645463325252ULL;
        for(int j=0;j<cnt;j++){
            int64_t d=ds[base+j];
            fprintf(f,"    acc = acc * 31 + y / ");lit(f,d);fprintf(f,";\n    acc = acc ^ (y %% ");lit(f,d);fprintf(f,");\n");
            fprintf(f,"    acc = acc + u / ");lit(f,d);fprintf(f," - u %% ");lit(f,d);fprintf(f,";\n");
            fprintf(f,"    acc = acc ^ (w / ");lit(f,d);fprintf(f,") + w %% ");lit(f,d);fprintf(f,";\n");
        }
        fprintf(f,"    i += 1;\n  }\n  return acc;\n}\n");
        for(int i=0;i<20000&&!trap;i++){
            x=x*6364136223846793005ULL+1442695040888963407ULL;
            uint64_t y=sar(x,(unsigned)(i&63));
            uint64_t u=x>>1,w=x>>40;
            for(int j=0;j<cnt;j++){int64_t d=ds[base+j];acc=acc*31+qd(y,d);acc^=rd(y,d);
                acc=acc+qd(u,d)-rd(u,d);acc=acc^(qd(w,d)+rd(w,d));}
        }
        if(trap)fprintf(e,"TRAP\n");else fprintf(e,"%" PRId64 "\n",I(acc));
        fclose(f);fclose(e);
    }
    fprintf(stderr,"%d divisors in %d programs\n",nd,prog);
    return 0;
}
