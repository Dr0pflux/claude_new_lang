#include <stdint.h>
#include <stdio.h>
int main(int argc,char **argv){(void)argv;
  uint64_t seed=12345+(uint64_t)argc; int64_t h=0; uint64_t sum=0;
  for(int64_t i=0;i<200000000;i++){
    seed=seed*6364136223846793005ULL+1442695040888963407ULL;
    int64_t sym=(int64_t)(seed>>33)%29;
    h=(h*29+sym)%20511149;
    sum+=((uint64_t)h*2654435761ULL)>>20;
  }
  printf("%lld\n",(long long)sum);return 0;}
