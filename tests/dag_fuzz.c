/* Independent DAG fuzzer for skite (Opus review): locals reference arbitrary
 * earlier locals, x+x and x/x sharing, negative divisors, immediate-encoding
 * boundary constants on either side. Oracle = C wrapping i64. Not in compile path. */
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static uint64_t s;
static uint32_t r(void){s^=s<<13;s^=s>>7;s^=s<<17;return (uint32_t)(s>>16);}
static int64_t I(uint64_t v){int64_t x;memcpy(&x,&v,8);return x;}
static uint64_t U(int64_t v){uint64_t x;memcpy(&x,&v,8);return x;}
#define NA 4
int main(int argc,char**argv){
  if(argc!=4)return 2;
  s=strtoull(argv[3],0,10)*0x9E3779B97F4A7C15ULL+1;
  int cases=atoi(argv[2]);
  for(int t=0;t<cases;t++){
    char p[512];snprintf(p,sizeof p,"%s/f%04d.ck",argv[1],t);FILE*f=fopen(p,"w");
    snprintf(p,sizeof p,"%s/f%04d.exp",argv[1],t);FILE*e=fopen(p,"w");
    int k=2+(int)(r()%60); uint64_t v[64][NA];
    fprintf(f,"fn main() -> i64 {\n");
    for(int i=0;i<k;i++){
      int a=i?(int)(r()%(uint32_t)i):-1,b=i?(int)(r()%(uint32_t)i):-1; int op=(int)(r()%9);
      if(i==0||op==8){ fprintf(f," let v%d = argc();\n",i); for(int x=0;x<NA;x++)v[i][x]=1+x; continue; }
      if(op==7){ /* constant operand, either side; immediate-encoding boundaries */
        static const int64_t K[]={0,1,2,127,128,-128,-129,255,256,32767,-32768,
          2147483647LL,2147483648LL,-2147483647LL-1,-2147483647LL-2,4294967295LL,4294967296LL,
          -4294967296LL,INT64_MAX,-INT64_MAX};
        int64_t c=(r()%3)?K[r()%(sizeof K/sizeof K[0])]:(int64_t)(r()%2000)-1000;
        char oc="+-*"[r()%3]; int left=r()&1; char lit[48];
        if(c<0)snprintf(lit,sizeof lit,"(-%" PRId64 ")",-c);else snprintf(lit,sizeof lit,"%" PRId64,c);
        if(left)fprintf(f," let v%d = %s %c v%d;\n",i,lit,oc,a);else fprintf(f," let v%d = v%d %c %s;\n",i,a,oc,lit);
        for(int x=0;x<NA;x++){uint64_t A=left?U(c):v[a][x],B=left?v[a][x]:U(c);
          v[i][x]=oc=='+'?A+B:oc=='-'?A-B:A*B;}
        continue; }
      if(op==6&&r()%3==0)b=a; /* same operand */
      const char*o="+-*/%"; char oc;
      if(op==5){ fprintf(f," let v%d = -v%d;\n",i,a); for(int x=0;x<NA;x++)v[i][x]=0-v[a][x]; continue; }
      oc=o[op%5];
      int bad=0;
      for(int x=0;x<NA;x++){ uint64_t A=v[a][x],B=v[b][x];
        if(oc=='/'||oc=='%'){ if(B==0||(I(A)==INT64_MIN&&I(B)==-1)){bad=1;break;}
          v[i][x]=U(oc=='/'?I(A)/I(B):I(A)%I(B)); }
        else v[i][x]=oc=='+'?A+B:oc=='-'?A-B:A*B; }
      if(bad){ fprintf(f," let v%d = v%d + v%d;\n",i,a,b); for(int x=0;x<NA;x++)v[i][x]=v[a][x]+v[b][x]; }
      else fprintf(f," let v%d = v%d %c v%d;\n",i,a,oc,b);
    }
    /* return: sum of many locals to keep them live (pressure) */
    fprintf(f," return v%d",k-1); uint64_t tot[NA]; for(int x=0;x<NA;x++)tot[x]=v[k-1][x];
    for(int i=0;i<k-1;i++) if(r()%2){ fprintf(f," - v%d",i); for(int x=0;x<NA;x++)tot[x]-=v[i][x]; }
    fprintf(f,";\n}\n");
    for(int x=0;x<NA;x++)fprintf(e,"%" PRId64 "\n",I(tot[x]));
    fclose(f);fclose(e);
  }
  return 0;
}
