#include <stdint.h>
#include <stdio.h>
int main(int argc,char **argv){long n=50000000+argc-1;uint64_t x=88172645463325252ULL;for(long i=0;i<n;i++)x=(x%29)^(uint64_t)i^0xFEDCBA9876543210ULL;printf("%llu\n",(unsigned long long)x);return 0;}
