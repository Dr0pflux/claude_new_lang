/* Control-flow + memory differential fuzzer for ling0 (G1 gate, v0.4 memory).
 * Builds a random structured program (let/let mut/assign/op-assign/if/else/
 * while/break/continue/early return, all operators), prints it as .cock source
 * and evaluates it with an independent tree interpreter. Expected output is
 * the program's stdout (print/putc lines, then the decimal result) and whether
 * it ends in a TRAP (division fault or array bounds violation).
 * MEM mode adds arrays (alloc8/16/32/64, constant and runtime lengths), loads,
 * stores, op= on elements, len(), print() and putc().
 * Not part of the compilation path. usage: cf_fuzz OUT_DIR CASES SEED [PRESSURE] [MEM]
 */
#define _POSIX_C_SOURCE 200809L
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static uint64_t rs;
static uint32_t rnd(void){rs^=rs<<13;rs^=rs>>7;rs^=rs<<17;return (uint32_t)(rs>>16);}
static int R(int n){return (int)(rnd()%(uint32_t)n);}
static int64_t I(uint64_t v){int64_t x;memcpy(&x,&v,8);return x;}
static uint64_t U(int64_t v){uint64_t x;memcpy(&x,&v,8);return x;}
enum{E_C,E_V,E_U,E_B,E_LD,E_LEN,E_CALL,E_AR, S_LET,S_SET,S_IF,S_WHILE,S_BRK,S_CONT,S_RET,S_ST,S_PR,S_PC,S_EX,S_PAR};
static int parmode,inpar,par_lo,pshared=-1,parW,parC;  /* par: slot pshared is a shared array of W*C */
/* array slots: 0..na-1 = main's arrays; na+f = function f's array parameter */
enum{MAXSLOT=16,MAXF=4};
static int na,aw[MAXSLOT],alen[MAXSLOT],art[MAXSLOT],amut[MAXSLOT];
static int avis[MAXSLOT],navis;       /* array slots visible in the function being generated */
static int memmode,funcmode,ginloop,curf=-1;
/* functions: f(d, p1.., [q]) with d a recursion-depth guard */
static int nf,fnp[MAXF],fpar[MAXF][4],fslot[MAXF],fbody[MAXF],fvlo[MAXF],fvhi[MAXF];
enum{ADD,SUB,MUL,DIV,MOD,AND,OR,XOR,SHL,SHR,SAR,EQ,NE,LT,LE,GT,GE,LAND,LOR,NOPS};
static const char *opn[]={"+","-","*","/","%","&","|","^","<<",">>>",">>","==","!=","<","<=",">",">=","&&","||"};
enum{NEG,NOT,LNOT};
typedef struct{int k,op,a,b,c,next,var,lim;uint64_t v;}N;
static N n[200000];static int nn;
static int mk(int k){if(nn>=200000){fprintf(stderr,"pool\n");exit(1);}n[nn]=(N){.k=k,.a=-1,.b=-1,.c=-1,.next=-1,.var=-1};return nn++;}
/* scope */
static int scope[512],smut[512],ns,nvars;static int vconst[100000];static uint64_t vcval[100000];static int ctr[512]; /* ctr: loop counter, never randomly assigned */
static const int64_t K[]={0,1,2,3,5,7,29,31,127,128,-1,-2,-3,-7,-29,-128,-129,1000,65536,
  2147483647LL,2147483648LL,-2147483647LL-1,4294967295LL,4294967296LL,
  1LL<<62,INT64_MAX,-INT64_MAX,-INT64_MAX-1,6364136223846793005LL,20511149};
static uint64_t sar(uint64_t x,unsigned k){return I(x)<0?~(~x>>k):x>>k;}
static uint64_t bin(int op,uint64_t x,uint64_t y,int *trap){
    int64_t a=I(x),b=I(y);
    switch(op){
    case ADD:return x+y;case SUB:return x-y;case MUL:return x*y;
    case DIV:case MOD:if(b==0||(a==INT64_MIN&&b==-1)){*trap=1;return 0;}return U(op==DIV?a/b:a%b);
    case AND:return x&y;case OR:return x|y;case XOR:return x^y;
    case SHL:return x<<(y&63);case SHR:return x>>(y&63);case SAR:return sar(x,(unsigned)(y&63));
    case EQ:return a==b;case NE:return a!=b;case LT:return a<b;case LE:return a<=b;case GT:return a>b;case GE:return a>=b;
    }
    return 0;
}
/* Mirror of the compiler's compile-time folding rules, to avoid generating
 * programs the compiler must reject (literal zero divisor, const MIN/-1). */
static int fold(int e,uint64_t *v){
    N *x=&n[e];uint64_t a,b;int t=0;
    switch(x->k){
    case E_C:*v=x->v;return 1;
    case E_V:if(vconst[x->var]){*v=vcval[x->var];return 1;}return 0;
    case E_U:if(!fold(x->a,&a))return 0;*v=x->op==NEG?0-a:x->op==NOT?~a:(uint64_t)(a==0);return 1;
    case E_LD:case E_CALL:case E_AR:return 0;
    case E_LEN:if(art[x->var])return 0;*v=(uint64_t)alen[x->var];return 1;
    }
    int fa=fold(x->a,&a),fb=fold(x->b,&b);
    if(x->op==LAND&&fa){if(!a){*v=0;return 1;}if(fb){*v=b!=0;return 1;}return 0;}
    if(x->op==LOR&&fa){if(a){*v=1;return 1;}if(fb){*v=b!=0;return 1;}return 0;}
    if(!fa||!fb)return 0;
    if(x->op==LAND){*v=a&&b;return 1;}
    if(x->op==LOR){*v=a||b;return 1;}
    *v=bin(x->op,a,b,&t);return !t;
}
static int pickvar(int want_mut){
    int c[512],k=0;for(int i=0;i<ns;i++)if((!want_mut||smut[i])&&!(want_mut&&ctr[i])&&!(want_mut&&inpar&&i<par_lo))c[k++]=i;
    return k?scope[c[R(k)]]:-1;
}
static int gexpr(int d);
static int lenof(int k){int e=mk(E_LEN);n[e].var=k;return e;}
/* Index forms: provably in range (mask), in range but unprovable (double mod),
 * and possibly out of range (trap coverage). */
static int gidx(int k,int d){
    int r=R(100),e=gexpr(d);
    if(r<45&&!art[k]){int m=1;while(m*2<=alen[k])m*=2;int b=mk(E_B);n[b].op=AND;n[b].a=e;n[b].b=mk(E_C);n[n[b].b].v=(uint64_t)(m-1);return b;}
    if(r<85){int m1=mk(E_B);n[m1].op=MOD;n[m1].a=e;n[m1].b=lenof(k);
             int ad=mk(E_B);n[ad].op=ADD;n[ad].a=m1;n[ad].b=lenof(k);
             int m2=mk(E_B);n[m2].op=MOD;n[m2].a=ad;n[m2].b=lenof(k);return m2;}
    if(r<93){int b=mk(E_B);n[b].op=SHR;n[b].a=e;n[b].b=mk(E_C);n[n[b].b].v=60;return b;}
    return e;
}
/* call fj(args): from main any function; from f only lower-numbered ones, or
 * itself (depth d - 1, never inside a loop) */
static int gcall(int d){
    int c[MAXF],k=0;
    for(int j=0;j<nf;j++){
        if(curf>=0&&j>curf)continue;
        if(j==curf&&ginloop)continue;
        if(fslot[j]>=0){ /* need a visible array of the same width (writable if mut) */
            int ok=0;for(int i=0;i<navis;i++)if(aw[avis[i]]==aw[fslot[j]]&&(!amut[fslot[j]]||amut[avis[i]]))ok=1;
            if(!ok)continue;
        }
        c[k++]=j;
    }
    if(!k)return -1;
    int j=c[R(k)],e=mk(E_CALL);n[e].var=j;
    int last=-1;
    for(int i=0;i<fnp[j]+(fslot[j]>=0);i++){
        int a;
        if(i==0){
            if(j==curf){a=mk(E_B);n[a].op=SUB;n[a].a=mk(E_V);n[n[a].a].var=fpar[curf][0];n[a].b=mk(E_C);n[n[a].b].v=1;}
            else{a=mk(E_B);n[a].op=AND;n[a].a=gexpr(d>1?1:0);n[a].b=mk(E_C);n[n[a].b].v=3;}
        }else if(i<fnp[j])a=gexpr(d>1?1:0);
        else{
            int cand[MAXSLOT],m=0;
            for(int t=0;t<navis;t++)if(aw[avis[t]]==aw[fslot[j]]&&(!amut[fslot[j]]||amut[avis[t]]))cand[m++]=avis[t];
            a=mk(E_AR);n[a].var=cand[R(m)];
        }
        if(last<0)n[e].a=a;else n[last].c=a;
        last=a;
    }
    return e;
}
static int pickctr(void){int c[512],k=0;for(int i=0;i<ns;i++)if(ctr[i]&&scope[i]!=0)c[k++]=i;return k?scope[c[R(k)]]:-1;}
static int gexpr(int d){
    int r=R(100);
    /* periodic-index patterns on loop counters: (c % D), ((c + E) % D) */
    if(d>0&&r<8){
        int cv=pickctr();
        if(cv>=0){
            int v=mk(E_V);n[v].var=cv;int div=v;
            if(R(2)){int ad=mk(E_B);n[ad].op=ADD;n[ad].a=v;n[ad].b=R(2)?gexpr(1):mk(E_C);if(n[n[ad].b].k==E_C)n[n[ad].b].v=(uint64_t)R(40);div=ad;}
            int m=mk(E_B);n[m].op=MOD;n[m].a=div;
            static const int64_t D[]={1,2,3,5,7,26,29,-3};
            if(R(3)){n[m].b=mk(E_C);n[n[m].b].v=U(D[R(8)]);}
            else{n[m].b=gexpr(1);uint64_t bv;if(fold(n[m].b,&bv)&&bv==0){n[m].b=mk(E_C);n[n[m].b].v=7;}}
            return m;
        }
    }
    if(funcmode&&!inpar&&d>0&&r>=96){int c=gcall(d);if(c>=0)return c;}
    if(memmode&&navis&&d>0&&r<12){int k=avis[R(navis)];int e=mk(E_LD);n[e].var=k;n[e].a=gidx(k,d-1);return e;}
    if(memmode&&navis&&r<15)return lenof(avis[R(navis)]);
    if(d<=0||r<30){
        if(r<12||!ns){int e=mk(E_C);int64_t c=R(3)?K[R((int)(sizeof K/sizeof K[0]))]:(int64_t)R(2001)-1000;n[e].v=U(c);return e;}
        int e=mk(E_V);n[e].var=pickvar(0);return e;
    }
    if(r<40){int e=mk(E_U);n[e].op=R(3);n[e].a=gexpr(d-1);return e;}
    for(;;){
        int e=mk(E_B);n[e].op=R(NOPS);n[e].a=gexpr(d-1);n[e].b=gexpr(d-1);
        if(n[e].op==DIV||n[e].op==MOD){
            uint64_t bv,av;
            if(fold(n[e].b,&bv)&&(bv==0||(fold(n[e].a,&av)&&I(av)==INT64_MIN&&I(bv)==-1)))continue;
        }
        if(n[e].op==DIV||n[e].op==MOD){ /* bias toward constant divisors: exercises magic division */
            if(R(2)){int c=mk(E_C);int64_t dv=K[R((int)(sizeof K/sizeof K[0]))];if(dv==0)dv=29;n[c].v=U(dv);n[e].b=c;
                uint64_t av;if(fold(n[e].a,&av)&&I(av)==INT64_MIN&&dv==-1)n[c].v=7;}
        }
        return e;
    }
}
static int gblock(int d,int inloop,int *budget);
static int gstmt(int d,int inloop,int *budget){
    int r=R(100);(*budget)--;
    if(parmode&&curf<0&&!inpar&&pshared>=0&&R(100)<8){
        /* par v in 0..W { <random worker code>; let mut j = 0; while j < C { j += 1; sh[v*C + j - 1] = e; } } */
        int sp=mk(S_PAR),kv=nvars++;n[sp].var=kv;n[sp].lim=parW;
        int mark=ns;scope[ns]=kv;smut[ns]=0;ctr[ns]=0;ns++;
        int sv_navis=navis,sv_avis[MAXSLOT];memcpy(sv_avis,avis,sizeof avis);
        int m=0;for(int i=0;i<navis;i++)if(avis[i]!=pshared)avis[m++]=avis[i];navis=m;  /* no shared access but the final slice */
        inpar=1;par_lo=ns;
        int body=gblock(d>1?d-1:1,0,budget);
        int cv=nvars++;int cl=mk(S_LET);n[cl].var=cv;n[cl].lim=1;n[cl].a=mk(E_C);n[n[cl].a].v=0;
        int w=mk(S_WHILE);n[w].var=cv;n[w].lim=parC;n[w].a=-1;
        int st=mk(S_ST);n[st].var=pshared;n[st].op=-1;
        int mul=mk(E_B);n[mul].op=MUL;n[mul].a=mk(E_V);n[n[mul].a].var=kv;n[mul].b=mk(E_C);n[n[mul].b].v=(uint64_t)parC;
        int ad=mk(E_B);n[ad].op=ADD;n[ad].a=mul;n[ad].b=mk(E_V);n[n[ad].b].var=cv;
        int sb=mk(E_B);n[sb].op=SUB;n[sb].a=ad;n[sb].b=mk(E_C);n[n[sb].b].v=1;
        n[st].a=sb;n[st].b=gexpr(2);
        int wb=mk(S_IF);n[wb].k=-1;n[wb].a=st;n[w].b=wb;
        int last=-1;for(int c=n[body].a;c>=0;c=n[c].next)last=c;
        if(last<0)n[body].a=cl;else n[last].next=cl;
        n[cl].next=w;
        n[sp].b=body;
        inpar=0;navis=sv_navis;memcpy(avis,sv_avis,sizeof avis);ns=mark;
        return sp;
    }
    if(d>0&&r<12&&*budget>0){
        int s=mk(S_IF);n[s].a=gexpr(3);n[s].b=gblock(d-1,inloop,budget);if(R(2))n[s].c=gblock(d-1,inloop,budget);return s;
    }
    if(d>0&&r<20&&*budget>0&&ns<500){
        /* let mut cK = 0; while cK < lim [&& cond] { cK = cK + 1; ... } */
        int cv=nvars++;int let=mk(S_LET);n[let].var=cv;n[let].lim=1;n[let].a=mk(E_C);n[n[let].a].v=0;
        int w=mk(S_WHILE);n[w].var=cv;n[w].lim=1+R(12);n[w].a=R(2)?gexpr(2):-1;
        scope[ns]=cv;smut[ns]=1;ctr[ns]=1;ns++;
        int sv=ginloop;ginloop=1;n[w].b=gblock(d-1,1,budget);ginloop=sv;
        n[let].next=w;return let; /* caller links after w */
    }
    if(inloop&&r<24){return mk(R(2)?S_BRK:S_CONT);}
    int wslots[MAXSLOT],nws=0;for(int i=0;i<navis;i++)if(amut[avis[i]])wslots[nws++]=avis[i];
    if(memmode&&nws&&r<40){
        int k=wslots[R(nws)],s=mk(S_ST);n[s].var=k;n[s].a=gidx(k,2);n[s].b=gexpr(3);n[s].op=R(3)?-1:(int)R(SAR+1);
        uint64_t dv;if((n[s].op==DIV||n[s].op==MOD)&&fold(n[s].b,&dv)&&dv==0)n[s].op=ADD;
        return s;
    }
    if(memmode&&!inpar&&r<44){int s=mk(R(2)?S_PR:S_PC);n[s].a=gexpr(2);return s;}
    if(memmode&&nws&&r<52&&ns<500){
        /* Range-analysis stress: let mut t = e; then a guarded access or a
         * len()-bounded loop, sometimes off by one or with a negative start. */
        int k=wslots[R(nws)],tv=nvars++;
        int let=mk(S_LET);n[let].var=tv;n[let].lim=1;
        int sm=R(4);
        if(sm==0){n[let].a=mk(E_C);n[n[let].a].v=U((int64_t)R(5)-2);}            /* small, maybe negative */
        else n[let].a=gexpr(2);
        scope[ns]=tv;smut[ns]=1;ctr[ns]=1;ns++;               /* never randomly reassigned */
        int tvar=mk(E_V);n[tvar].var=tv;
        int form=R(4),cmpop=R(4)?LT:LE;                       /* LE = deliberately off by one */
        int lo=mk(E_B);n[lo].op=GE;n[lo].a=tvar;n[lo].b=mk(E_C);n[n[lo].b].v=0;
        int tv2=mk(E_V);n[tv2].var=tv;
        int hi=mk(E_B);n[hi].op=cmpop;n[hi].a=tv2;n[hi].b=lenof(k);
        int idx=mk(E_V);n[idx].var=tv;
        int st=mk(S_ST);n[st].var=k;n[st].a=idx;n[st].b=gexpr(2);n[st].op=R(2)?-1:ADD;
        int idx2=mk(E_V);n[idx2].var=tv;
        int ld=mk(E_LD);n[ld].var=k;n[ld].a=idx2;
        int pr=mk(S_PR);n[pr].a=ld;
        if(inpar){n[pr].k=S_LET;n[pr].var=nvars++;n[pr].lim=0;}   /* no output in par: read into a local */
        n[st].next=pr;
        int blk=mk(S_IF);n[blk].k=-1;n[blk].a=st;
        if(form<2){                                           /* if t >= 0 && t < len(a) { a[t] = ..; print(a[t]); } */
            int c=mk(E_B);n[c].op=LAND;n[c].a=form==0?lo:mk(E_C);if(form==1)n[n[c].a].v=1; n[c].b=hi;
            int s=mk(S_IF);n[s].a=c;n[s].b=blk;n[let].next=s;return let;
        }
        /* while t < len(a) { a[t] = ..; print(a[t]); t += 1 }  (counter-bounded too) */
        int cv=nvars++;int cl=mk(S_LET);n[cl].var=cv;n[cl].lim=1;n[cl].a=mk(E_C);n[n[cl].a].v=0;
        scope[ns]=cv;smut[ns]=1;ctr[ns]=1;ns++;
        int w=mk(S_WHILE);n[w].var=cv;n[w].lim=1+R(12);n[w].a=hi;
        (void)ginloop;
        int inc=mk(S_SET);n[inc].var=tv;n[inc].op=ADD;n[inc].a=mk(E_C);n[n[inc].a].v=1;
        n[pr].next=inc;n[w].b=blk;
        n[let].next=cl;n[cl].next=w;return let;
    }
    if(!inpar&&r<26&&d<3){int s=mk(S_RET);n[s].a=gexpr(3);return s;}
    if(funcmode&&!inpar&&r<30){int c=gcall(2);if(c>=0){int s=mk(R(2)?S_PR:S_EX);n[s].a=c;return s;}}
    if(funcmode&&!inpar&&r<34){ /* statement-inlinable forms: let v = f(..); / v = f(..); */
        int c=gcall(2);
        if(c>=0){
            int mv2=pickvar(1);
            if(mv2>=0&&R(2)){int s=mk(S_SET);n[s].var=mv2;n[s].a=c;n[s].op=-1;return s;}
            int s=mk(S_LET);n[s].var=nvars++;n[s].a=c;n[s].lim=R(2);vconst[n[s].var]=0;
            scope[ns]=n[s].var;smut[ns]=n[s].lim;ctr[ns]=0;ns++;return s;
        }
    }
    int mv=pickvar(1);
    if(r<55&&mv>=0){int s=mk(S_SET);n[s].var=mv;n[s].a=gexpr(3);n[s].op=R(3)?-1:(int)R(SAR+1);
        uint64_t dv;if((n[s].op==DIV||n[s].op==MOD)&&fold(n[s].a,&dv)&&dv==0)n[s].op=ADD;
        return s;}
    int s=mk(S_LET);n[s].var=nvars++;n[s].a=gexpr(3);n[s].lim=R(10)<6;
    {uint64_t cv;vconst[n[s].var]=!n[s].lim&&fold(n[s].a,&cv);vcval[n[s].var]=vconst[n[s].var]?cv:0;}
    scope[ns]=n[s].var;smut[ns]=n[s].lim;ctr[ns]=0;ns++;
    return s;
}
static int gblock(int d,int inloop,int *budget){
    int mark=ns,first=-1,last=-1,cnt=1+R(5);
    for(int i=0;i<cnt&&*budget>0;i++){
        int s=gstmt(d,inloop,budget);
        if(first<0)first=s;else n[last].next=s;
        last=s;while(n[last].next>=0)last=n[last].next;
    }
    ns=mark;
    int b=mk(S_IF);n[b].k=-1;n[b].a=first;return b; /* k=-1: block */
}
/* ---- printing ---- */
static FILE *out;
static void pconst(uint64_t v){int64_t s=I(v);if(s==INT64_MIN)fprintf(out,"(-9223372036854775807 - 1)");else if(s<0)fprintf(out,"(-%" PRId64 ")",-s);else fprintf(out,"%" PRId64,s);}
static void pslot(int k){if(k<na)fprintf(out,"a%d",k);else fprintf(out,"q%d",k-na);}
static void pexpr(int e){
    N *x=&n[e];
    if(x->k==E_C)pconst(x->v);
    else if(x->k==E_V){if(x->var==0)fprintf(out,"argc()");else fprintf(out,"v%d",x->var);}
    else if(x->k==E_U&&x->op==LNOT){fprintf(out,"(((");pexpr(x->a);fprintf(out,") == 0) as i64)");}
    else if(x->k==E_U){fprintf(out,"%s(",x->op==NEG?"-":"~");pexpr(x->a);fprintf(out,")");}
    else if(x->k==E_LD){pslot(x->var);fprintf(out,"[");pexpr(x->a);fprintf(out,"]");}
    else if(x->k==E_LEN){fprintf(out,"len(");pslot(x->var);fprintf(out,")");}
    else if(x->k==E_AR)pslot(x->var);
    else if(x->k==E_CALL){fprintf(out,"f%d(",x->var);for(int a=x->a;a>=0;a=n[a].c){pexpr(a);if(n[a].c>=0)fprintf(out,", ");}fprintf(out,")");}
    else if(x->op==LAND||x->op==LOR){fprintf(out,"((((");pexpr(x->a);fprintf(out,") != 0) %s ((",opn[x->op]);pexpr(x->b);fprintf(out,") != 0)) as i64)");}
    else if(x->op>=EQ){fprintf(out,"((");pexpr(x->a);fprintf(out," %s ",opn[x->op]);pexpr(x->b);fprintf(out,") as i64)");}
    else{fprintf(out,"(");pexpr(x->a);fprintf(out," %s ",opn[x->op]);pexpr(x->b);fprintf(out,")");}
}
static int slot_w(int k){return aw[k];}
static const char *wty(int w){return w==1?"u8":w==2?"i16":w==4?"i32":"i64";}
static void ind(int d){for(int i=0;i<d;i++)fputs("  ",out);}
static void pblock(int b,int d);
static void pstmt(int s,int d){
    N *x=&n[s];ind(d);
    switch(x->k){
    case S_LET:fprintf(out,"let %sv%d: i64 = ",x->lim?"mut ":"",x->var);pexpr(x->a);fprintf(out,";\n");break;
    case S_SET:if(x->op<0){fprintf(out,"v%d = ",x->var);}else fprintf(out,"v%d %s= ",x->var,opn[x->op]);pexpr(x->a);fprintf(out,";\n");break;
    case S_IF:fprintf(out,"if (");pexpr(x->a);fprintf(out,") != 0 ");pblock(x->b,d);if(x->c>=0){fprintf(out," else ");pblock(x->c,d);}fprintf(out,"\n");break;
    case S_WHILE:fprintf(out,"while v%d < %d",x->var,x->lim);if(x->a>=0){fprintf(out," && (");pexpr(x->a);fprintf(out,") != 0");}
        fprintf(out," {\n");ind(d+1);fprintf(out,"v%d += 1;\n",x->var);for(int c=n[x->b].a;c>=0;c=n[c].next)pstmt(c,d+1);ind(d);fprintf(out,"}\n");break;
    case S_BRK:fprintf(out,"break;\n");break;
    case S_CONT:fprintf(out,"continue;\n");break;
    case S_RET:fprintf(out,"return ");pexpr(x->a);fprintf(out,";\n");break;
    case S_ST:{int w=slot_w(x->var);pslot(x->var);fprintf(out,"[");pexpr(x->a);if(x->op<0)fprintf(out,"] = ");else fprintf(out,"] %s= ",opn[x->op]);
        if(x->op<0&&w<8){fprintf(out,"(");pexpr(x->b);fprintf(out,") as %s",wty(w));}else pexpr(x->b);fprintf(out,";\n");break;}
    case S_PR:fprintf(out,"print(");pexpr(x->a);fprintf(out,");\n");break;
    case S_EX:pexpr(x->a);fprintf(out,";\n");break;
    case S_PAR:fprintf(out,"par v%d in 0..%d ",x->var,x->lim);pblock(x->b,d);fprintf(out,"\n");break;
    case S_PC:fprintf(out,"putc(65 + ((");pexpr(x->a);fprintf(out,") & 15));\n");break;
    }
}
static void pblock(int b,int d){fprintf(out,"{\n");for(int c=n[b].a;c>=0;c=n[c].next)pstmt(c,d+1);ind(d);fprintf(out,"}");}
/* ---- interpreter ---- */
static uint64_t val[100000];static int trap;static long steps;
static uint64_t mem[MAXSLOT][64];static int curlen[MAXSLOT];
static int amap[MAXSLOT];          /* slot -> actual array (main's arrays map to themselves) */
static int overflow,cdepth;enum{STEP_LIMIT=2000000};
static char obuf[1<<20];static size_t olen;
static void oput(const char *t){size_t l=strlen(t);if(olen+l<sizeof obuf){memcpy(obuf+olen,t,l);olen+=l;}}
static uint64_t canon(int w,uint64_t v){
    if(w==1)return v&0xff;
    if(w==2){uint16_t h=(uint16_t)v;int16_t s;memcpy(&s,&h,2);return U(s);}
    if(w==4){uint32_t h=(uint32_t)v;int32_t s;memcpy(&s,&h,4);return U(s);}
    return v;
}
enum{F_NONE,F_BRK,F_CONT,F_RET};static uint64_t retv;
static uint64_t call(int e);
static uint64_t ev(int e){
    N *x=&n[e];if(trap)return 0;
    switch(x->k){
    case E_C:return x->v;
    case E_V:return val[x->var];
    case E_U:{uint64_t a=ev(x->a);return x->op==NEG?0-a:x->op==NOT?~a:(uint64_t)(a==0);}
    case E_LEN:return (uint64_t)curlen[amap[x->var]];
    case E_LD:{int64_t i=I(ev(x->a));if(trap)return 0;int A=amap[x->var];if(i<0||i>=curlen[A]){trap=1;return 0;}return mem[A][i];}
    case E_CALL:return call(e);
    }
    if(x->op==LAND){uint64_t a=ev(x->a);if(trap||!a)return 0;return ev(x->b)!=0;}
    if(x->op==LOR){uint64_t a=ev(x->a);if(trap)return 0;if(a)return 1;return ev(x->b)!=0;}
    uint64_t a=ev(x->a),b=ev(x->b);if(trap)return 0;
    return bin(x->op,a,b,&trap);
}
static int exblock(int b);
static int exstmt(int s){
    N *x=&n[s];if(++steps>STEP_LIMIT){overflow=1;trap=1;return F_RET;}
    switch(x->k){
    case S_LET:val[x->var]=ev(x->a);return trap?F_RET:F_NONE;
    case S_SET:{uint64_t v=ev(x->a);if(trap)return F_RET;val[x->var]=x->op<0?v:bin(x->op,val[x->var],v,&trap);return trap?F_RET:F_NONE;}
    case S_IF:{uint64_t c=ev(x->a);if(trap)return F_RET;if(c)return exblock(x->b);if(x->c>=0)return exblock(x->c);return F_NONE;}
    case S_WHILE:
        for(;;){
            if(I(val[x->var])>=x->lim)break;
            if(x->a>=0){uint64_t c=ev(x->a);if(trap)return F_RET;if(!c)break;}
            val[x->var]+=1;
            int f=exblock(x->b);
            if(f==F_RET)return F_RET;
            if(f==F_BRK)break;
        }
        return F_NONE;
    case S_BRK:return F_BRK;
    case S_CONT:return F_CONT;
    case S_RET:retv=ev(x->a);return F_RET;
    case S_ST:{
        uint64_t v=ev(x->b);if(trap)return F_RET;
        int64_t i=I(ev(x->a));if(trap)return F_RET;
        int A=amap[x->var];
        if(i<0||i>=curlen[A]){trap=1;return F_RET;}
        uint64_t old=mem[A][i];
        uint64_t nv=x->op<0?v:bin(x->op,old,v,&trap);if(trap)return F_RET;
        mem[A][i]=canon(aw[A],nv);return F_NONE;}
    case S_EX:ev(x->a);return trap?F_RET:F_NONE;
    case S_PAR:{ /* each worker runs on a snapshot; only the shared array persists */
        static uint64_t sval[100000];static uint64_t smem[MAXSLOT][64];
        int anytrap=0;
        for(int k=0;k<x->lim;k++){
            memcpy(sval,val,sizeof(uint64_t)*(size_t)nvars);memcpy(smem,mem,sizeof mem);
            val[x->var]=(uint64_t)k;
            exblock(x->b);
            if(overflow)return F_RET;
            if(trap)anytrap=1;
            trap=0;
            uint64_t keep[64];memcpy(keep,mem[pshared],sizeof keep);
            memcpy(val,sval,sizeof(uint64_t)*(size_t)nvars);memcpy(mem,smem,sizeof mem);
            memcpy(mem[pshared],keep,sizeof keep);
        }
        if(anytrap){trap=1;return F_RET;}
        return F_NONE;}
    case S_PR:{uint64_t v=ev(x->a);if(trap)return F_RET;char t[32];snprintf(t,sizeof t,"%" PRId64 "\n",I(v));oput(t);return F_NONE;}
    case S_PC:{uint64_t v=ev(x->a);if(trap)return F_RET;char t[2]={(char)(65+(v&15)),0};oput(t);return F_NONE;}
    }
    return F_NONE;
}
static int exblock(int b){for(int c=n[b].a;c>=0;c=n[c].next){int f=exstmt(c);if(f!=F_NONE)return f;}return F_NONE;}
static uint64_t call(int e){
    int f=n[e].var;uint64_t args[8];int i=0,arr=-1;
    for(int a=n[e].a;a>=0;a=n[a].c){
        if(n[a].k==E_AR)arr=amap[n[a].var];
        else{args[i++]=ev(a);if(trap)return 0;}
    }
    if(++steps>STEP_LIMIT||cdepth>2000){overflow=1;trap=1;return 0;}
    cdepth++;
    int nv=fvhi[f]-fvlo[f];uint64_t *saved=malloc(sizeof(uint64_t)*(size_t)(nv>0?nv:1));
    memcpy(saved,val+fvlo[f],sizeof(uint64_t)*(size_t)nv);
    int savedmap=fslot[f]>=0?amap[fslot[f]]:0;
    for(int k=0;k<fnp[f];k++)val[fpar[f][k]]=args[k];
    if(fslot[f]>=0)amap[fslot[f]]=arr;
    exblock(fbody[f]);
    uint64_t r=retv;
    memcpy(val+fvlo[f],saved,sizeof(uint64_t)*(size_t)nv);free(saved);
    if(fslot[f]>=0)amap[fslot[f]]=savedmap;
    cdepth--;
    return r;
}
int main(int argc,char **argv){
    if(argc<4||argc>8){fprintf(stderr,"usage: %s OUT_DIR CASES SEED [PRESSURE] [MEM] [FUNC] [PAR]\n",argv[0]);return 2;}
    int pressure=argc>=5?atoi(argv[4]):0;memmode=argc>=6?atoi(argv[5]):0;funcmode=argc>=7?atoi(argv[6]):0;
    parmode=argc>=8?atoi(argv[7]):0;if(parmode)memmode=1;
    int cases=atoi(argv[2]);rs=strtoull(argv[3],0,10)*0x9E3779B97F4A7C15ULL+0x1234567;
    for(int t=0;t<cases;t++){
      for(int attempt=0;;attempt++){
        nn=0;ns=0;nvars=1;memset(vconst,0,sizeof vconst);curf=-1;ginloop=0;nf=0;
        scope[ns]=0;smut[ns]=0;ctr[ns]=0;ns++; /* v0 = argc() */
        int budget=10+R(50);
        na=memmode?1+R(3):0;
        for(int k=0;k<na;k++){int ws[]={1,2,4,8};aw[k]=ws[R(4)];art[k]=R(3)==0;alen[k]=art[k]?R(20):1+R(40);amut[k]=1;}
        pshared=-1;inpar=0;
        if(parmode&&na){pshared=0;parW=1+R(4);parC=1+R(6);art[0]=0;alen[0]=parW*parC;}
        /* helper functions (generated before main's body, each with its own scope) */
        nf=funcmode?1+R(MAXF-1):0;
        for(int f=0;f<nf;f++){
            curf=f;ns=0;fvlo[f]=nvars;
            fnp[f]=1+R(3);
            for(int k=0;k<fnp[f];k++){fpar[f][k]=nvars++;scope[ns]=fpar[f][k];smut[ns]=0;ctr[ns]=0;ns++;}
            fslot[f]=-1;navis=0;
            if(memmode&&na&&R(2)){int sl=na+f;int src=R(na);aw[sl]=aw[src];art[sl]=1;alen[sl]=0;amut[sl]=R(2);fslot[f]=sl;avis[navis++]=sl;}
            int fb=budget/2+3;
            /* if d <= 0 { return e; } */
            int g=mk(S_IF);int cnd=mk(E_B);n[cnd].op=LE;n[cnd].a=mk(E_V);n[n[cnd].a].var=fpar[f][0];n[cnd].b=mk(E_C);n[n[cnd].b].v=0;
            n[g].a=cnd;int gr=mk(S_RET);ginloop=1;n[gr].a=gexpr(2);ginloop=0;   /* no self-call in the base case */int gb=mk(S_IF);n[gb].k=-1;n[gb].a=gr;n[g].b=gb;
            int blk=gblock(3,0,&fb);
            int ret=mk(S_RET);n[ret].a=gexpr(3);
            int last=-1;for(int c=n[blk].a;c>=0;c=n[c].next)last=c;
            if(last<0)n[blk].a=ret;else n[last].next=ret;
            n[g].next=n[blk].a;n[blk].a=g;
            fbody[f]=blk;fvhi[f]=nvars;
        }
        curf=-1;ns=0;navis=0;for(int k=0;k<na;k++)avis[navis++]=k;
        /* Pressure mode: many mutable variables live across every loop. */
        int pro=-1,plast=-1,np=pressure?12+R(29):0,pv[64];
        for(int i=0;i<np;i++){
            int s=mk(S_LET);n[s].var=nvars++;n[s].lim=1;pv[i]=n[s].var;
            {int m=mk(E_B),c1=mk(E_C),c2=mk(E_C),a0=mk(E_V);n[a0].var=0;n[c1].v=U((int64_t)R(2001)-1000);n[c2].v=U(K[R((int)(sizeof K/sizeof K[0]))]);
             n[m].op=MUL;n[m].a=a0;n[m].b=c1;int ad=mk(E_B);n[ad].op=ADD;n[ad].a=m;n[ad].b=c2;n[s].a=ad;}
            scope[ns]=n[s].var;smut[ns]=1;ctr[ns]=0;ns++;
            if(pro<0)pro=s;else n[plast].next=s;
            plast=s;
        }
        int top=gblock(4,0,&budget);
        if(pro>=0){n[plast].next=n[top].a;n[top].a=pro;}
        int ret=mk(S_RET);n[ret].a=gexpr(4);
        for(int i=0;i<np;i++){int b=mk(E_B);n[b].op=i%3==0?SUB:i%3==1?ADD:XOR;n[b].a=n[ret].a;n[b].b=mk(E_V);n[n[b].b].var=pv[i];n[ret].a=b;}
        int last=-1;for(int c=n[top].a;c>=0;c=n[c].next)last=c;
        if(last<0)n[top].a=ret;else n[last].next=ret;
        char p[600];snprintf(p,sizeof p,"%s/c%04d.cock",argv[1],t);out=fopen(p,"w");
        for(int f=0;f<nf;f++){
            fprintf(out,"fn f%d(",f);
            for(int k=0;k<fnp[f];k++)fprintf(out,"%sv%d: i64",k?", ":"",fpar[f][k]);
            if(fslot[f]>=0)fprintf(out,", q%d: %s[%s]",f,amut[fslot[f]]?"mut ":"",aw[fslot[f]]==1?"u8":aw[fslot[f]]==2?"i16":aw[fslot[f]]==4?"i32":"i64");
            fprintf(out,") -> i64 {\n");
            for(int c=n[fbody[f]].a;c>=0;c=n[c].next)pstmt(c,1);
            fprintf(out,"}\n");
        }
        fprintf(out,"fn main() -> i64 {\n");
        for(int k=0;k<na;k++){fprintf(out,"  let a%d = %s%d(",k,k==pshared?"shared":"alloc",aw[k]*8);if(art[k])fprintf(out,"argc() + %d",alen[k]);else fprintf(out,"%d",alen[k]);fprintf(out,");\n");}
        for(int c=n[top].a;c>=0;c=n[c].next)pstmt(c,1);
        fprintf(out,"}\n");fclose(out);
        /* run all three argc values first; regenerate if any run exceeds the step budget */
        static char outs[3][1<<16];static size_t outl[3];static int traps[3];overflow=0;
        for(int a=1;a<=3&&!overflow;a++){
            memset(val,0,sizeof(uint64_t)*(size_t)nvars);val[0]=(uint64_t)a;trap=0;steps=0;olen=0;cdepth=0;
            memset(mem,0,sizeof mem);for(int k=0;k<na;k++){curlen[k]=art[k]?a+alen[k]:alen[k];amap[k]=k;}
            exblock(top);
            if(!trap){char t[32];snprintf(t,sizeof t,"%" PRId64 "\n",I(retv));oput(t);}
            if(olen>sizeof outs[0])overflow=1;
            if(!overflow){memcpy(outs[a-1],obuf,olen);outl[a-1]=olen;traps[a-1]=trap;}
        }
        if(overflow){if(attempt>50){fprintf(stderr,"generator: cannot fit step budget\n");return 1;}continue;}
        for(int a=1;a<=3;a++){
            size_t ol=outl[a-1];int tr=traps[a-1];
            memcpy(obuf,outs[a-1],ol);olen=ol;trap=tr;
            snprintf(p,sizeof p,"%s/c%04d.a%d.out",argv[1],t,a);FILE *o=fopen(p,"wb");fwrite(obuf,1,olen,o);fclose(o);
            snprintf(p,sizeof p,"%s/c%04d.a%d.rc",argv[1],t,a);o=fopen(p,"w");fprintf(o,"%s\n",trap?"TRAP":"OK");fclose(o);
        }
        break;
      }
    }
    return 0;
}
