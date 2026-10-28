/* Parallel version of vig.c: same algorithm, OpenMP over ciphertexts with the
 * same static stride distribution as vigp.ck (worker w takes t = w, w+W, ...). */
#include <omp.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
static const uint8_t *map(const char *path,int64_t *len){
  int fd=open(path,O_RDONLY);if(fd<0){perror(path);exit(1);}
  struct stat st;fstat(fd,&st);*len=st.st_size;
  void *p=mmap(0,(size_t)st.st_size,PROT_READ,MAP_PRIVATE,fd,0);close(fd);
  if(p==MAP_FAILED){perror("mmap");exit(1);}return p;
}
int main(int argc,char **argv){
  if(argc<3)return 2;
  int64_t tlen,ctlen;const int16_t *q=(const int16_t*)map(argv[1],&tlen);const uint8_t *ct=map(argv[2],&ctlen);
  if(tlen/2<456976){printf("-1\n");return 0;}
  static const int32_t uni[26]={8167,1492,2782,4253,12702,2228,2015,6094,6966,153,772,4025,2406,6749,7507,1929,95,5987,6327,9056,2758,978,2360,150,1974,74};
  int64_t nt=0;for(int64_t i=0;i<ctlen;i++)if(ct[i]==10)nt++;
  if(ctlen>0&&ct[ctlen-1]!=10)nt++;
  int64_t *start=malloc(sizeof(int64_t)*(size_t)(nt+1));int64_t t=0;start[0]=0;
  for(int64_t i=0;i<ctlen&&t<nt;i++)if(ct[i]==10){t++;start[t]=i+1;}
  uint8_t *keys=calloc((size_t)nt*32,1);int64_t *klen=calloc((size_t)nt,8),*score=calloc((size_t)nt,8);
  int W=omp_get_max_threads();
  #pragma omp parallel num_threads(W)
  {
    int w=omp_get_thread_num();
    uint8_t c[4096],p[4096],key[32];int32_t cnt[520];int64_t ioc[21];
    for(int64_t tt=w;tt<nt;tt+=W){
      int64_t n=0,pos=start[tt];
      while(pos<ctlen&&ct[pos]!=10){int64_t ch=ct[pos];if(ch>=65&&ch<=90&&n<4096){c[n]=(uint8_t)(ch-65);n++;}pos++;}
      if(n<8)continue;
      int64_t bests=0;
      for(int64_t pp=1;pp<=20;pp++){
        for(int64_t z=0;z<26*pp;z++)cnt[z]=0;
        for(int64_t i=0;i<n;i++)cnt[(i%pp)*26+c[i]]++;
        int64_t num=0,den=0;
        for(int64_t col=0;col<pp;col++){int64_t nc=0;for(int64_t l=0;l<26;l++){int64_t f=cnt[col*26+l];num+=f*(f-1);nc+=f;}den+=nc*(nc-1);}
        int64_t sc=0;if(den>0)sc=num*10000/den;
        ioc[pp]=sc;if(sc>bests)bests=sc;
      }
      int64_t per=1;
      for(int64_t pp=1;pp<=20;pp++)if(ioc[pp]*10>=bests*9){per=pp;break;}
      for(int64_t z=0;z<26*per;z++)cnt[z]=0;
      for(int64_t i=0;i<n;i++)cnt[(i%per)*26+c[i]]++;
      for(int64_t j=0;j<per;j++){
        int64_t bk=0,bv=-1;
        for(int64_t k=0;k<26;k++){int64_t v=0;for(int64_t l=0;l<26;l++)v+=(int64_t)cnt[j*26+(l+k)%26]*uni[l];if(v>bv){bv=v;bk=k;}}
        key[j]=(uint8_t)bk;
      }
      for(int64_t i=0;i<n;i++)p[i]=(uint8_t)((c[i]-key[i%per]+26)%26);
      int64_t pass=0,improved=1;
      while(pass<4&&improved!=0){
        improved=0;
        for(int64_t j=0;j<per;j++){
          int64_t bestk=key[j],bestsc=-INT64_MAX;
          for(int64_t k=0;k<26;k++){
            for(int64_t i=j;i<n;i+=per)p[i]=(uint8_t)((c[i]-k+26)%26);
            int64_t sc=0;
            if(per>=4){
              for(int64_t i=j;i<n;i+=per){
                int64_t s=i-3;if(s<0)s=0;int64_t e=i;if(e>n-4)e=n-4;
                for(;s<=e;s++)sc+=q[((p[s]*26+p[s+1])*26+p[s+2])*26+p[s+3]];
              }
            }else{
              for(int64_t s=0;s<=n-4;s++)sc+=q[((p[s]*26+p[s+1])*26+p[s+2])*26+p[s+3]];
            }
            if(sc>bestsc){bestsc=sc;bestk=k;}
          }
          if(bestk!=key[j]){key[j]=(uint8_t)bestk;improved=1;}
          for(int64_t i=j;i<n;i+=per)p[i]=(uint8_t)((c[i]-bestk+26)%26);
        }
        pass++;
      }
      int64_t sc=0;for(int64_t s=0;s<=n-4;s++)sc+=q[((p[s]*26+p[s+1])*26+p[s+2])*26+p[s+3]];
      for(int64_t j=0;j<per;j++)keys[tt*32+j]=key[j];
      klen[tt]=per;score[tt]=sc;
    }
  }
  int64_t total=0;
  for(int64_t tt=0;tt<nt;tt++)if(klen[tt]>0){for(int64_t j=0;j<klen[tt];j++)putchar(keys[tt*32+j]+65);putchar(10);total+=score[tt];}
  printf("%lld\n",(long long)total);
  return 0;
}
