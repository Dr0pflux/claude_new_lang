/* Deterministic, independent C reference oracle for ling0 scalar arithmetic.
 * Constructs expressions and checks wrapping i64 semantics, signed div/mod.
 * Not part of the language compilation path.
 */
#define _POSIX_C_SOURCE 200809L
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static uint64_t seed=0x6a09e667f3bcc909ULL;
static uint32_t rnd(void){seed^=seed<<13;seed^=seed>>7;seed^=seed<<17;return (uint32_t)(seed>>16);}
static int64_t as_i64(uint64_t v){int64_t x;memcpy(&x,&v,8);return x;}
static uint64_t as_u64(int64_t v){uint64_t x;memcpy(&x,&v,8);return x;}
int main(int argc,char **argv){
    if(argc!=3){fprintf(stderr,"usage: %s OUT_DIR CASES\n",argv[0]);return 2;}
    int cases=atoi(argv[2]);if(cases<1||cases>2000)return 2;
    for(int t=0;t<cases;t++){
        char src[1024],expected[1024];
        snprintf(src,sizeof src,"%s/case_%03d.l0",argv[1],t);
        snprintf(expected,sizeof expected,"%s/case_%03d.expected",argv[1],t);
        FILE *f=fopen(src,"w");FILE *e=fopen(expected,"w");
        if(!f||!e){perror("differential generator");return 1;}
        fprintf(f,"fn main() -> i64 {\n  let n: i64 = argc();\n");
        int k=12+(int)(rnd()%30);
        uint64_t vals[64][4]={0};
        for(int i=0;i<k;i++){
            uint64_t c=1+rnd()%32767;
            int mode=(int)(rnd()%7);
            if(mode==0){
                fprintf(f,"  let v%d = n + %" PRIu64 ";\n",i,c);
                for(int x=0;x<4;x++)vals[i][x]=(uint64_t)(1+x*2)+c;
            }else if(mode==1){
                fprintf(f,"  let v%d = n * %" PRIu64 " - %" PRIu64 ";\n",i,c,c/3);
                for(int x=0;x<4;x++)vals[i][x]=(uint64_t)(1+x*2)*c-c/3;
            }else if(mode==2){
                fprintf(f,"  let v%d = -(n * %" PRIu64 ");\n",i,c);
                for(int x=0;x<4;x++)vals[i][x]=0-(uint64_t)(1+x*2)*c;
            }else if(mode==3){
                fprintf(f,"  let v%d = (n * %" PRIu64 ") / %u;\n",i,c,2+(unsigned)(c%11));
                for(int x=0;x<4;x++)vals[i][x]=as_u64((int64_t)((1+x*2)*c)/(int64_t)(2+c%11));
            }else if(mode==4){
                fprintf(f,"  let v%d = -(n * %" PRIu64 ") %% %u;\n",i,c,2+(unsigned)(c%13));
                for(int x=0;x<4;x++)vals[i][x]=as_u64((int64_t)(-((int64_t)(1+x*2)*c))%(int64_t)(2+c%13));
            }else if(mode==5){
                fprintf(f,"  let v%d = n + n * %" PRIu64 ";\n",i,c);
                for(int x=0;x<4;x++)vals[i][x]=(uint64_t)(1+x*2)*(1+c);
            }else{
                fprintf(f,"  let v%d = (n - %" PRIu64 ") * (n + %" PRIu64 ");\n",i,c,c%97);
                for(int x=0;x<4;x++)vals[i][x]=((uint64_t)(1+x*2)-c)*((uint64_t)(1+x*2)+c%97);
            }
        }
        fprintf(f,"  return v0");
        uint64_t total[4];for(int x=0;x<4;x++)total[x]=vals[0][x];
        for(int i=1;i<k;i++){
            unsigned mode=rnd()%3;
            if(mode==0){fprintf(f," + v%d",i);for(int x=0;x<4;x++)total[x]+=vals[i][x];}
            if(mode==1){fprintf(f," - v%d",i);for(int x=0;x<4;x++)total[x]-=vals[i][x];}
            if(mode==2){fprintf(f," + v%d + v%d",i,i);for(int x=0;x<4;x++)total[x]+=vals[i][x]*2;}
        }
        fprintf(f,";\n}\n");
        for(int x=0;x<4;x++)fprintf(e,"%" PRId64 "%s",as_i64(total[x]),x==3?"\n":" ");
        fclose(e);fclose(f);
    }
    return 0;
}
