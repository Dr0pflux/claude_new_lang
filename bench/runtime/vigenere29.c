#include <stdint.h>
#include <stdio.h>
int main(int argc,char **argv){(void)argv;
  uint64_t seed=777+(uint64_t)argc; uint64_t acc=0;
  for(int64_t i=0;i<200000000;i++){
    seed=seed*6364136223846793005ULL+1442695040888963407ULL;
    int64_t p=(int64_t)(seed>>40)%29;
    int64_t k=(i%7)*11+3;
    int64_t c=(p+k)%29;
    acc=acc*31+(uint64_t)c;
  }
  printf("%lld\n",(long long)acc);return 0;}
