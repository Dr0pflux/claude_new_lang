#include <stdint.h>
#include <stdio.h>
int main(int argc,char **argv){uint64_t x=88172645463325252ULL;long n=100000000+argc-1;for(long i=0;i<n;i++)x=((x<<5)+(x>>59))^(uint64_t)i;printf("%llu\n",(unsigned long long)x);return 0;}
