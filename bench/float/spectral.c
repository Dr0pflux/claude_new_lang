#include <stdio.h>
#include <stdlib.h>
#include <math.h>
static double a(long i,long j){return 1.0/(double)((i+j)*(i+j+1)/2+i+1);}
static void av(const double*v,double*o,long n){for(long i=0;i<n;i++){double s=0;for(long j=0;j<n;j++)s+=a(i,j)*v[j];o[i]=s;}}
static void atv(const double*v,double*o,long n){for(long i=0;i<n;i++){double s=0;for(long j=0;j<n;j++)s+=a(j,i)*v[j];o[i]=s;}}
int main(int c,char**v_){FILE*f=fopen(v_[1],"r");long n;if(fscanf(f,"%ld",&n)!=1)return 1;
 double*u=malloc(8*n),*v=malloc(8*n),*t=malloc(8*n);for(long i=0;i<n;i++)u[i]=1;
 for(int i=0;i<10;i++){av(u,t,n);atv(t,v,n);av(v,t,n);atv(t,u,n);}
 double vbv=0,vv=0;for(long i=0;i<n;i++){vbv+=u[i]*v[i];vv+=v[i]*v[i];}printf("%.6f\n",sqrt(vbv/vv));(void)c;return 0;}
