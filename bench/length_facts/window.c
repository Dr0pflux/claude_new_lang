#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(int argc,char **argv){
 (void)argv;size_t n=262144+(unsigned)argc-1;
 int64_t *a=calloc(n,sizeof *a);if(!a)return 1;
 for(size_t i=0;i<n;i++)a[i]=(int64_t)((i*7)%1000)-500;
 uint64_t h=(unsigned)argc;
 for(int r=0;r<300;r++){
  for(size_t i=1;i<n;i++)h=(h^(uint64_t)a[i-1])+(uint64_t)a[i];
 }
 int64_t result;memcpy(&result,&h,sizeof result);printf("%lld\n",(long long)result);free(a);return 0;
}
