/* Phase 1 gate: random well-typed programs over every scalar type (i8..u64,
 * bool, f32, f64) with casts, promotions, unsigned ops, float arithmetic,
 * typed arrays, typed helper functions and compound assignment, checked
 * against this independent interpreter of the v0.7 type rules.
 * usage: ty_fuzz OUT_DIR CASES SEED  -> OUT_DIR/tNNNN.ck + tNNNN.out */
#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum{I8,I16,I32,I64,U8,U16,U32,U64,BOOL,F32,F64,NT};
static const char *tn[NT]={"i8","i16","i32","i64","u8","u16","u32","u64","bool","f32","f64"};
static int isint(int t){return t<=U64;}
static int issig(int t){return t<=I64;}
static int isflt(int t){return t==F32||t==F64;}
static int wid(int t){return t==I8||t==U8||t==BOOL?1:t==I16||t==U16?2:t==I32||t==U32||t==F32?4:8;}
static int prom(int t){return t==U64?U64:I64;}
static int widens(int s,int t){
    if(s==t)return 1;
    if(issig(s))return issig(t)&&wid(t)>=wid(s);
    if(isint(s)&&!issig(s))return (isint(t)&&!issig(t)&&wid(t)>=wid(s))||(issig(t)&&wid(t)>wid(s));
    return 0;
}
static uint64_t rs=1;
static uint64_t rnd(void){rs^=rs<<13;rs^=rs>>7;rs^=rs<<17;return rs;}
static int R(int n){return (int)(rnd()%(uint64_t)n);}
static int64_t I(uint64_t v){int64_t s;memcpy(&s,&v,8);return s;}
static double D(uint64_t v){double d;memcpy(&d,&v,8);return d;}
static uint64_t DB(double d){uint64_t v;memcpy(&v,&d,8);return v;}
static float S(uint64_t v){float f;uint32_t u=(uint32_t)v;memcpy(&f,&u,4);return f;}
static uint64_t SB(float f){uint32_t u;memcpy(&u,&f,4);return u;}
static uint64_t canon(uint64_t v,int t){
    switch(t){
    case I8:return (uint64_t)(int64_t)(int8_t)v; case I16:return (uint64_t)(int64_t)(int16_t)v;
    case I32:return (uint64_t)(int64_t)(int32_t)v; case U8:return (uint8_t)v; case U16:return (uint16_t)v;
    case U32:case F32:return (uint32_t)v; case BOOL:return v&1;
    }
    return v;
}
static int64_t sat_i64(double d){if(d!=d)return 0;if(d>=9223372036854775808.0)return INT64_MAX;if(d<=-9223372036854775808.0)return INT64_MIN;return (int64_t)d;}
static uint64_t sat_u64(double d){if(d!=d||d<=0)return 0;if(d>=18446744073709551616.0)return UINT64_MAX;return (uint64_t)d;}
static int64_t lo_of(int t){return t==I8?-128:t==I16?-32768:t==I32?INT32_MIN:0;}
static int64_t hi_of(int t){return t==I8?127:t==I16?32767:t==I32?INT32_MAX:t==U8?255:t==U16?65535:(int64_t)UINT32_MAX;}
static uint64_t cast(uint64_t v,int s,int t){
    if(s==t)return v;
    if(s==BOOL)return v;
    if(isint(s)&&isint(t))return canon(v,t);
    if(isint(s)&&isflt(t)){
        if(s==U64)return t==F64?DB((double)v):SB((float)v);
        return t==F64?DB((double)I(v)):SB((float)I(v));
    }
    if(isflt(s)&&isflt(t))return t==F64?DB((double)S(v)):SB((float)D(v));
    double d=s==F64?D(v):(double)S(v);
    if(t==U64)return sat_u64(d);
    int64_t i=sat_i64(d);
    if(t!=I64){int64_t lo=lo_of(t),hi=hi_of(t);i=i<lo?lo:i>hi?hi:i;}
    return (uint64_t)i;
}

/* ---- program representation ---- */
enum{E_LIT,E_VAR,E_LOAD,E_BIN,E_CMP,E_NEG,E_NOT,E_LNOT,E_FNEG,E_CAST,E_AND,E_OR,E_SQRT,E_BITS,E_FBITS,E_CALL,
     S_ASSIGN,S_OPEQ,S_STORE,S_IF,S_WHILE,S_PRINT,S_CALLST,S_RET,S_BLOCK};
enum{ADD,SUB,MUL,DIV,MOD,AND,OR,XOR,SHL,SAR,SHR,EQ,NE,LT,LE,GT,GE};
static const char *opn[]={"+","-","*","/","%","&","|","^","<<",">>",">>>","==","!=","<","<=",">",">="};
typedef struct{int k,ty,op,a,b,c,var,next,pt,lit;uint64_t v;}N;
enum{MAXN=200000,MAXV=512,MAXA=12,MAXF=4};
static N n[MAXN];static int nn;
static int mk(int k,int ty){if(nn>=MAXN){fprintf(stderr,"too many nodes\n");exit(2);}n[nn]=(N){.k=k,.ty=ty,.a=-1,.b=-1,.c=-1,.var=-1,.next=-1};return nn++;}
static int vty[MAXV],nvars;                /* variables: type */
static int scope[MAXV],ns;                 /* visible variables */
static int smut[MAXV];
static int aty[MAXA],alen[MAXA],na;        /* arrays (main only) */
static int inmain;
static int fnp[MAXF],fpv[MAXF][3],fret[MAXF],fbody[MAXF],nf;   /* fret<0: unit */

/* ---- generator ---- */
static uint64_t rlit(int t){ /* a literal value of type t (canonical) */
    switch(t){
    case BOOL:return (uint64_t)R(2);
    case F64:case F32:{
        double d;int r=R(6);
        if(r==0)d=R(9)-4;
        else if(r==1)d=(R(64)-32)/8.0;
        else if(r==2)d=(double)(R(2000001)-1000000)/1024.0;
        else if(r==3){d=(double)(rnd()>>11)/9007199254740992.0;int e=R(40)-20;while(e>0){d*=2;e--;}while(e<0){d/=2;e++;}if(R(2))d=-d;}
        else if(r==4)d=(R(2)?1:-1)*1e30*(1+R(9));
        else d=(double)(I(rnd())>>R(60));
        return t==F64?DB(d):SB((float)d);}
    }
    uint64_t v=rnd();int r=R(4);
    if(r==0)v=(uint64_t)(R(17)-8);else if(r==1)v=rnd()>>R(64);
    return canon(v,t);
}
static int lit(int t){int e=mk(E_LIT,t);n[e].v=rlit(t);n[e].lit=1;return e;}
static int pick_var(int t,int exact,int wantmut){
    int c[MAXV],k=0;
    for(int i=0;i<ns;i++){int v=scope[i];if(wantmut&&!smut[i])continue;if(vty[v]==t||(!exact&&isint(t)&&isint(vty[v])&&widens(vty[v],t)))c[k++]=v;}
    return k?c[R(k)]:-1;
}
static int gexpr(int t,int d,int litok);
/* exactly type t (a narrower operand would promote to i64, not u64) */
static int force(int e,int t){if(n[e].ty==t)return e;int c=mk(E_CAST,t);n[c].a=e;n[c].pt=n[e].ty;return c;}
static int gexact(int t,int d){return force(gexpr(t,d,0),t);}
static int gidx(int a){ /* always in range */
    int m=mk(E_BIN,U64);n[m].op=MOD;n[m].a=gexact(U64,1);int l=mk(E_LIT,U64);n[l].v=(uint64_t)alen[a];n[l].lit=1;n[m].b=l;n[m].pt=U64;
    return m;
}
static int leaf(int t,int litok){
    int r=R(10);
    if(litok&&r<3)return lit(t);
    if(r<8){int v=pick_var(t,R(2),0);if(v>=0){int e=mk(E_VAR,vty[v]);n[e].var=v;return e;}}
    if(inmain&&na){
        int c[MAXA],k=0;for(int a=0;a<na;a++)if(aty[a]==t||(isint(t)&&isint(aty[a])&&widens(aty[a],t)))c[k++]=a;
        if(k){int a=c[R(k)];int e=mk(E_LOAD,aty[a]);n[e].var=a;n[e].a=gidx(a);return e;}
    }
    /* fallback: (literal as t) */
    if(t==BOOL)return lit(BOOL);
    int src=isflt(t)?F64:I64;int e=mk(E_CAST,t);n[e].a=lit(src);n[e].pt=src;return e;
}
static int rand_int_ty(int p){ /* operand type promoting to p */
    if(p==U64){static const int u[]={U8,U16,U32,U64};return u[R(4)];}
    static const int s[]={I8,I16,I32,I64,U8,U16,U32};return s[R(7)];
}
static int safe_div(int b,int p){ /* ((b) & 127) + 1 : never 0, never -1 */
    if(p==U64)b=force(b,U64);
    int a=mk(E_BIN,p);n[a].op=AND;n[a].a=b;n[a].b=mk(E_LIT,p);n[n[a].b].v=127;n[n[a].b].lit=1;n[a].pt=p;
    int s=mk(E_BIN,p);n[s].op=ADD;n[s].a=a;n[s].b=mk(E_LIT,p);n[n[s].b].v=1;n[n[s].b].lit=1;n[s].pt=p;
    return s;
}
static int gcall(int t,int d){
    int c[MAXF],k=0;for(int f=0;f<nf;f++)if(fret[f]==t)c[k++]=f;
    if(!k)return -1;
    int f=c[R(k)],e=mk(E_CALL,t);n[e].var=f;int prev=-1;
    for(int i=0;i<fnp[f];i++){int a=gexpr(vty[fpv[f][i]],d-1,1);if(prev<0)n[e].a=a;else n[prev].c=a;prev=a;}
    return e;
}
static int gint_bin(int p,int d){
    static const int ops[]={ADD,SUB,MUL,DIV,MOD,AND,OR,XOR,SHL,SAR,SHR};
    int op=ops[R(11)];int e=mk(E_BIN,p);n[e].op=op;n[e].pt=p;
    if(op==SHL||op==SAR||op==SHR){
        n[e].a=p==U64?gexact(U64,d-1):gexpr(rand_int_ty(I64),d-1,0);
        int cty=R(NT-3);n[e].b=gexpr(cty,d-1,1);          /* any integer type count */
        if(op==SAR&&p==U64)n[e].op=SHR;
        return e;
    }
    int ta=p==U64?U64:rand_int_ty(I64),tb=rand_int_ty(p);
    int sw=p==U64&&R(2);
    if(sw){int x=ta;ta=tb;tb=x;}
    n[e].a=(p==U64&&!sw)?gexact(U64,d-1):gexpr(ta,d-1,p!=U64);
    if(op==DIV||op==MOD)n[e].b=safe_div(gexpr(tb,d-1,0),p);
    else n[e].b=(p==U64&&sw)?gexact(U64,d-1):gexpr(tb,d-1,p!=U64&&!n[n[e].a].lit);
    return e;
}
static int gexpr(int t,int d,int litok){
    if(d<=0||R(10)<3)return leaf(t,litok);
    if(inmain&&nf&&R(12)==0){int c=gcall(t,d);if(c>=0)return c;}
    int r=R(10);
    if(t==BOOL){
        if(r<5){ /* comparison */
            int e=mk(E_CMP,BOOL);n[e].op=EQ+R(6);
            int c=R(4);
            if(c==0){n[e].pt=isflt(R(2)?F32:F64)?(R(2)?F32:F64):F64;n[e].a=gexpr(n[e].pt,d-1,1);n[e].b=gexpr(n[e].pt,d-1,!n[n[e].a].lit);}
            else if(c==1){n[e].pt=BOOL;n[e].op=EQ+R(2);n[e].a=gexpr(BOOL,d-1,0);n[e].b=gexpr(BOOL,d-1,0);}
            else{int p=R(3)?I64:U64;n[e].pt=p;
                if(p==U64){n[e].a=gexact(U64,d-1);n[e].b=gexpr(rand_int_ty(U64),d-1,0);if(R(2)){int x=n[e].a;n[e].a=n[e].b;n[e].b=x;}}
                else{n[e].a=gexpr(rand_int_ty(I64),d-1,1);n[e].b=gexpr(rand_int_ty(I64),d-1,!n[n[e].a].lit);}}
            return e;
        }
        if(r<7){int e=mk(R(2)?E_AND:E_OR,BOOL);n[e].a=gexpr(BOOL,d-1,0);n[e].b=gexpr(BOOL,d-1,0);return e;}
        if(r<8){int e=mk(E_LNOT,BOOL);n[e].a=gexpr(BOOL,d-1,0);return e;}
        return leaf(BOOL,litok);
    }
    if(isflt(t)){
        if(r<5){int e=mk(E_BIN,t);n[e].op=R(4)==0?DIV:R(3);n[e].pt=t;n[e].a=gexpr(t,d-1,1);n[e].b=gexpr(t,d-1,!n[n[e].a].lit);return e;}
        if(r<6){int e=mk(E_FNEG,t);n[e].a=gexpr(t,d-1,0);return e;}
        if(r<7){int e=mk(E_SQRT,t);n[e].a=gexpr(t,d-1,0);return e;}
        if(r<8&&R(3)==0){int e=mk(E_FBITS,t);n[e].a=gexpr(t==F64?U64:U32,d-1,0);return e;}
        int s=R(NT);if(s==BOOL)s=I32;
        int e=mk(E_CAST,t);n[e].pt=s;n[e].a=gexpr(s,d-1,0);return e;
    }
    /* integers */
    if((t==I64||t==U64)&&r<6)return gint_bin(t,d);
    if(t==I64&&r<7){int e=mk(R(2)?E_NEG:E_NOT,I64);n[e].a=gexpr(rand_int_ty(I64),d-1,0);return e;}
    if(t==U64&&r<7){int e=mk(E_NOT,U64);n[e].a=gexact(U64,d-1);return e;}
    if(r<8&&R(4)==0&&(t==U64||t==U32)){int e=mk(E_BITS,t);n[e].a=gexpr(t==U64?F64:F32,d-1,0);return e;}
    int s=R(NT);
    int e=mk(E_CAST,t);n[e].pt=s;n[e].a=gexpr(s,d-1,0);return e;
}
static int gblock(int d,int *budget,int loops);
static int gstmt(int d,int *budget,int loops){
    (*budget)--;
    int r=R(100);
    if(inmain&&r<12&&na){ /* store */
        int a=R(na),t=aty[a],s=mk(S_STORE,t);n[s].var=a;n[s].a=gidx(a);n[s].op=-1;
        if(R(3)==0&&t!=BOOL){
            if(isflt(t)){n[s].op=R(4);if(n[s].op==DIV)n[s].op=MUL;n[s].b=gexpr(t,3,1);}
            else{static const int ops[]={ADD,SUB,AND,OR,XOR,MUL,SHL,SAR};n[s].op=ops[R(8)];
                n[s].b=gexpr((n[s].op==SHL||n[s].op==SAR)?R(8):prom(t),3,1);}
        }else n[s].b=gexpr(t,3,1);
        return s;
    }
    if(r<35){
        int v=-1;for(int tries=0;tries<4&&v<0;tries++)v=pick_var(R(NT),1,1);
        if(v>=0){
            int t=vty[v];
            if(R(3)==0&&t!=BOOL){
                int s=mk(S_OPEQ,t);n[s].var=v;
                if(isflt(t)){n[s].op=R(4);n[s].b=gexpr(t,3,1);}
                else{static const int ops[]={ADD,SUB,MUL,DIV,MOD,AND,OR,XOR,SHL,SAR};n[s].op=ops[R(10)];
                    int p=prom(t);
                    if(n[s].op==SHL||n[s].op==SAR)n[s].b=gexpr(R(8),2,1);
                    else if(n[s].op==DIV||n[s].op==MOD)n[s].b=safe_div(gexpr(rand_int_ty(p),2,0),p);
                    else n[s].b=gexpr(p==U64?U64:rand_int_ty(I64),3,1);}
                return s;
            }
            int s=mk(S_ASSIGN,t);n[s].var=v;n[s].a=gexpr(t,3,1);return s;
        }
    }
    if(r<50&&d>0){int s=mk(S_IF,0);n[s].a=gexpr(BOOL,3,0);n[s].b=gblock(d-1,budget,loops);if(R(2))n[s].c=gblock(d-1,budget,loops);return s;}
    if(r<60&&d>0&&loops<2){
        int s=mk(S_WHILE,0);n[s].var=nvars++;vty[n[s].var]=I64;n[s].v=(uint64_t)(1+R(5));
        scope[ns]=n[s].var;smut[ns]=0;ns++;
        n[s].b=gblock(d-1,budget,loops+1);ns--;return s;
    }
    if(inmain&&r<66){int c=-1;for(int f=0;f<nf;f++)if(fret[f]<0&&R(2)){c=f;break;}
        if(c>=0){int s=mk(S_CALLST,0);int e=mk(E_CALL,-1);n[e].var=c;int prev=-1;
            for(int i=0;i<fnp[c];i++){int a=gexpr(vty[fpv[c][i]],2,1);if(prev<0)n[e].a=a;else n[prev].c=a;prev=a;}
            n[s].a=e;return s;}}
    int s=mk(S_PRINT,0);int t=R(NT);n[s].a=gexpr(t,3,0);return s;
}
static int gblock(int d,int *budget,int loops){
    int b=mk(S_BLOCK,0),last=-1,cnt=1+R(4);
    for(int i=0;i<cnt&&*budget>0;i++){int s=gstmt(d,budget,loops);if(last<0)n[b].a=s;else n[last].next=s;last=s;}
    return b;
}

/* ---- printing ---- */
static FILE *out;
static void plit(uint64_t v,int t){
    if(t==BOOL){fputs(v?"true":"false",out);return;}
    if(isflt(t)){
        double d=t==F64?D(v):(double)S(v);
        char b[64];snprintf(b,sizeof b,"%.17g",d<0?-d:d);
        if(!strpbrk(b,".e"))strcat(b,".0");   /* keep it a float literal (-0.0 must stay negative) */
        if(d<0||(d==0&&(DB(d)>>63)))fprintf(out,"(-%s)",b);else fputs(b,out);
        return;
    }
    if(t==U64){fprintf(out,"%" PRIu64,v);return;}
    int64_t s=I(v);
    if(s==INT64_MIN)fputs("(-9223372036854775807 - 1)",out);else if(s<0)fprintf(out,"(-%" PRId64 ")",-s);else fprintf(out,"%" PRId64,s);
}
static void pexpr(int e){
    N *x=&n[e];
    switch(x->k){
    case E_LIT:plit(x->v,x->ty);break;
    case E_VAR:fprintf(out,"v%d",x->var);break;
    case E_LOAD:fprintf(out,"a%d[",x->var);pexpr(x->a);fputs("]",out);break;
    case E_BIN:case E_CMP:fputs("(",out);pexpr(x->a);fprintf(out," %s ",opn[x->op]);pexpr(x->b);fputs(")",out);break;
    case E_AND:case E_OR:fputs("(",out);pexpr(x->a);fputs(x->k==E_AND?" && ":" || ",out);pexpr(x->b);fputs(")",out);break;
    case E_NEG:case E_FNEG:fputs("(-",out);pexpr(x->a);fputs(")",out);break;
    case E_NOT:fputs("(~",out);pexpr(x->a);fputs(")",out);break;
    case E_LNOT:fputs("(!",out);pexpr(x->a);fputs(")",out);break;
    case E_CAST:fputs("(",out);pexpr(x->a);fprintf(out," as %s)",tn[x->ty]);break;
    case E_SQRT:fputs("sqrt(",out);pexpr(x->a);fputs(")",out);break;
    case E_BITS:fputs("bits(",out);pexpr(x->a);fputs(")",out);break;
    case E_FBITS:fprintf(out,"%s_from_bits(",tn[x->ty]);pexpr(x->a);fputs(")",out);break;
    case E_CALL:fprintf(out,"h%d(",x->var);for(int a=x->a;a>=0;a=n[a].c){pexpr(a);if(n[a].c>=0)fputs(", ",out);}fputs(")",out);break;
    }
}
static void ind(int d){for(int i=0;i<d;i++)fputs("  ",out);}
static void pblock(int b,int d);
static void pstmt(int s,int d){
    N *x=&n[s];ind(d);
    switch(x->k){
    case S_ASSIGN:fprintf(out,"v%d = ",x->var);pexpr(x->a);fputs(";\n",out);break;
    case S_OPEQ:fprintf(out,"v%d %s= ",x->var,opn[x->op]);pexpr(x->b);fputs(";\n",out);break;
    case S_STORE:fprintf(out,"a%d[",x->var);pexpr(x->a);fprintf(out,"] %s= ",x->op<0?"":opn[x->op]);pexpr(x->b);fputs(";\n",out);break;
    case S_IF:fputs("if ",out);pexpr(x->a);fputs(" ",out);pblock(x->b,d);if(x->c>=0){fputs(" else ",out);pblock(x->c,d);}fputs("\n",out);break;
    case S_WHILE:fprintf(out,"let mut v%d: i64 = 0;\n",x->var);ind(d);fprintf(out,"while v%d < %d {\n",x->var,(int)x->v);
        for(int c=n[x->b].a;c>=0;c=n[c].next){pstmt(c,d+1);}
        ind(d+1);fprintf(out,"v%d += 1;\n",x->var);ind(d);fputs("}\n",out);break;
    case S_PRINT:fputs("print(",out);pexpr(x->a);fputs(");\n",out);break;
    case S_CALLST:pexpr(x->a);fputs(";\n",out);break;
    case S_RET:fputs("return ",out);pexpr(x->a);fputs(";\n",out);break;
    }
}
static void pblock(int b,int d){fputs("{\n",out);for(int c=n[b].a;c>=0;c=n[c].next)pstmt(c,d+1);ind(d);fputs("}",out);}

/* ---- interpreter ---- */
static uint64_t val[MAXV],mem[MAXA][32];
static FILE *res;
static void pdig(uint64_t x){if(x>=10)pdig(x/10);fputc((int)('0'+x%10),res);}
static void pfrac6(uint64_t t){fputc('.',res);for(uint64_t p=100000;p>0;p/=10)fputc((int)('0'+t/p%10),res);}
static void pfix6(double a){
    uint64_t ip=sat_u64(a);double fr=a-(double)ip;double s=fr*1000000.0;uint64_t t=sat_u64(s);double d=s-(double)t;
    if(d>0.5||(d==0.5&&t%2==1))t++;
    if(t==1000000){ip++;t=0;}
    pdig(ip);pfrac6(t);
}
static void print_f64(double x){ /* mirrors the prelude's __print_f64 */
    if(x!=x){fputs("NaN\n",res);return;}
    int neg=(DB(x)>>63)!=0;if(neg)fputc('-',res);
    double a=neg?-x:x;
    if(a==D(0x7FF0000000000000ULL)){fputs("inf\n",res);return;}
    if(a<10000000000000000.0){pfix6(a);fputc('\n',res);return;}
    if(a<18446744073709551616.0){pdig(sat_u64(a));pfrac6(0);fputc('\n',res);return;}
    int64_t e=0;while(a>=10.0){a=a/10.0;e++;}
    pfix6(a);fputs("e+",res);pdig((uint64_t)e);fputc('\n',res);
}
static uint64_t ibin(int op,int p,uint64_t x,uint64_t y){
    switch(op){
    case ADD:return x+y; case SUB:return x-y; case MUL:return x*y;
    case AND:return x&y; case OR:return x|y; case XOR:return x^y;
    case SHL:return x<<(y&63); case SHR:return x>>(y&63);
    case SAR:if(p==U64)return x>>(y&63);return I(x)<0?~(~x>>(y&63)):x>>(y&63);
    case DIV:return p==U64?x/y:(uint64_t)(I(x)/I(y));
    case MOD:return p==U64?x%y:(uint64_t)(I(x)%I(y));
    }
    exit(3);
}
static uint64_t fbin(int op,int t,uint64_t x,uint64_t y){
    if(t==F64){double a=D(x),b=D(y);return DB(op==ADD?a+b:op==SUB?a-b:op==MUL?a*b:a/b);}
    float a=S(x),b=S(y);return SB(op==ADD?a+b:op==SUB?a-b:op==MUL?a*b:a/b);
}
static int cmp(int op,int pt,uint64_t x,uint64_t y){
    if(isflt(pt)){double a=pt==F64?D(x):S(x),b=pt==F64?D(y):S(y);
        switch(op){case EQ:return a==b;case NE:return a!=b;case LT:return a<b;case LE:return a<=b;case GT:return a>b;default:return a>=b;}}
    if(pt==U64||pt==BOOL){switch(op){case EQ:return x==y;case NE:return x!=y;case LT:return x<y;case LE:return x<=y;case GT:return x>y;default:return x>=y;}}
    int64_t a=I(x),b=I(y);
    switch(op){case EQ:return a==b;case NE:return a!=b;case LT:return a<b;case LE:return a<=b;case GT:return a>b;default:return a>=b;}
}
static int exblock(int b);
static uint64_t ev(int e){
    N *x=&n[e];
    switch(x->k){
    case E_LIT:return x->v;
    case E_VAR:return val[x->var];
    case E_LOAD:{uint64_t i=ev(x->a);return mem[x->var][i];}
    case E_BIN:{uint64_t a=ev(x->a),b=ev(x->b);return isflt(x->pt)?fbin(x->op,x->pt,a,b):ibin(x->op,x->pt,a,b);}
    case E_CMP:{uint64_t a=ev(x->a),b=ev(x->b);return (uint64_t)cmp(x->op,x->pt,a,b);}
    case E_AND:return ev(x->a)?ev(x->b):0;
    case E_OR:return ev(x->a)?1:ev(x->b);
    case E_NEG:return 0-ev(x->a);
    case E_NOT:return ~ev(x->a);
    case E_LNOT:return !ev(x->a);
    case E_FNEG:{uint64_t v=ev(x->a);return x->ty==F64?v^(1ULL<<63):(v^0x80000000ULL);}
    case E_CAST:return cast(ev(x->a),n[x->a].ty,x->ty);
    case E_SQRT:{uint64_t v=ev(x->a);return x->ty==F64?DB(__builtin_sqrt(D(v))):SB(__builtin_sqrtf(S(v)));}
    case E_BITS:case E_FBITS:return ev(x->a);
    case E_CALL:{
        int f=x->var;uint64_t args[3];int i=0;
        for(int a=x->a;a>=0;a=n[a].c)args[i++]=ev(a);
        for(int k=0;k<fnp[f];k++)val[fpv[f][k]]=args[k];
        exblock(fbody[f]);
        return val[0];}
    }
    exit(3);
}
enum{F_NONE,F_RET};
static int exstmt(int s){
    N *x=&n[s];
    switch(x->k){
    case S_ASSIGN:val[x->var]=ev(x->a);return F_NONE;
    case S_OPEQ:{
        int t=vty[x->var];uint64_t b=ev(x->b),a=val[x->var];
        if(isflt(t))val[x->var]=fbin(x->op,t,a,b);
        else val[x->var]=canon(ibin(x->op,prom(t),a,b),t);
        return F_NONE;}
    case S_STORE:{
        int t=aty[x->var];uint64_t v=ev(x->b),i=ev(x->a);
        if(x->op<0)mem[x->var][i]=v;
        else if(isflt(t))mem[x->var][i]=fbin(x->op,t,mem[x->var][i],v);
        else mem[x->var][i]=canon(ibin(x->op,prom(t),mem[x->var][i],v),t);
        return F_NONE;}
    case S_IF:if(ev(x->a))return exblock(x->b);if(x->c>=0)return exblock(x->c);return F_NONE;
    case S_WHILE:for(val[x->var]=0;I(val[x->var])<(int64_t)x->v;val[x->var]++)if(exblock(x->b)==F_RET)return F_RET;return F_NONE;
    case S_PRINT:{
        int t=n[x->a].ty;uint64_t v=ev(x->a);
        if(t==BOOL)fputs(v?"true\n":"false\n",res);
        else if(t==F64)print_f64(D(v));
        else if(t==F32)print_f64((double)S(v));
        else if(t==U64)fprintf(res,"%" PRIu64 "\n",v);
        else fprintf(res,"%" PRId64 "\n",I(v));
        return F_NONE;}
    case S_CALLST:ev(x->a);return F_NONE;
    case S_RET:val[0]=ev(x->a);return F_RET;
    }
    return F_NONE;
}
static int exblock(int b){for(int c=n[b].a;c>=0;c=n[c].next)if(exstmt(c)==F_RET)return F_RET;return F_NONE;}

int main(int argc,char **argv){
    if(argc!=4){fprintf(stderr,"usage: %s OUT_DIR CASES SEED\n",argv[0]);return 2;}
    int cases=atoi(argv[2]);rs=0x9E3779B97F4A7C15ULL^(uint64_t)atoll(argv[3])*0x2545F4914F6CDD1DULL;
    for(int c=0;c<cases;c++){
        nn=0;nvars=1;ns=0;na=0;nf=0;   /* var 0: return value slot */
        char path[512];snprintf(path,sizeof path,"%s/t%04d.ck",argv[1],c);out=fopen(path,"w");
        snprintf(path,sizeof path,"%s/t%04d.out",argv[1],c);res=fopen(path,"w");
        if(!out||!res){perror("open");return 2;}
        /* helpers: typed parameters, a few typed locals, return of the declared type (or unit + print) */
        inmain=0;nf=R(MAXF+1);
        for(int f=0;f<nf;f++){
            ns=0;fnp[f]=1+R(3);fret[f]=R(5)==0?-1:R(NT);
            fprintf(out,"fn h%d(",f);
            for(int i=0;i<fnp[f];i++){int v=nvars++;vty[v]=R(NT);fpv[f][i]=v;scope[ns]=v;smut[ns]=0;ns++;fprintf(out,"%sv%d: %s",i?", ":"",v,tn[vty[v]]);}
            fputs(")",out);if(fret[f]>=0)fprintf(out," -> %s",tn[fret[f]]);fputs(" {\n",out);
            int b=mk(S_BLOCK,0),last=-1;
            int nl=R(3);
            for(int i=0;i<nl;i++){ /* let mut vK: T = e; (printed directly, executed as an assignment) */
                int v=nvars++;vty[v]=R(NT);int s=mk(S_ASSIGN,vty[v]);n[s].var=v;n[s].a=gexpr(vty[v],3,1);
                fprintf(out,"  let mut v%d: %s = ",v,tn[vty[v]]);pexpr(n[s].a);fputs(";\n",out);
                scope[ns]=v;smut[ns]=1;ns++;
                if(last<0)n[b].a=s;else n[last].next=s;last=s;
            }
            int budget=4;int body=gblock(1,&budget,0);
            for(int s=n[body].a;s>=0;s=n[s].next)pstmt(s,1);
            if(last<0)n[b].a=n[body].a;else n[last].next=n[body].a;
            while(last>=0&&n[last].next>=0)last=n[last].next;
            if(last<0)for(last=n[b].a;last>=0&&n[last].next>=0;last=n[last].next);
            if(fret[f]>=0){int r=mk(S_RET,0);n[r].a=gexpr(fret[f],3,1);pstmt(r,1);if(last<0)n[b].a=r;else n[last].next=r;}
            else{int p=mk(S_PRINT,0);n[p].a=gexpr(R(NT),2,0);pstmt(p,1);if(last<0)n[b].a=p;else n[last].next=p;}
            fbody[f]=b;
            fputs("}\n",out);
        }
        /* main */
        inmain=1;ns=0;
        int unit=R(3)==0;
        fprintf(out,"fn main()%s {\n",unit?"":" -> i64");
        na=1+R(MAXA-1);
        for(int a=0;a<na;a++){aty[a]=R(NT);alen[a]=1+R(32);memset(mem[a],0,sizeof mem[a]);fprintf(out,"  let a%d = alloc<%s>(%d);\n",a,tn[aty[a]],alen[a]);}
        for(int t=0;t<NT;t++)for(int k=0;k<1+R(2);k++){
            int v=nvars++;vty[v]=t;val[v]=rlit(t);scope[ns]=v;smut[ns]=1;ns++;
            fprintf(out,"  let mut v%d: %s = ",v,tn[t]);plit(val[v],t);fputs(";\n",out);
        }
        int budget=14+R(14);
        int body=gblock(3,&budget,0);
        for(int s=n[body].a;s>=0;s=n[s].next)pstmt(s,1);
        exblock(body);
        if(!unit){int r=mk(S_RET,0);n[r].a=gexpr(I64,3,0);pstmt(r,1);exstmt(r);fprintf(res,"%" PRId64 "\n",I(val[0]));}
        fputs("}\n",out);
        fclose(out);fclose(res);
    }
    return 0;
}
