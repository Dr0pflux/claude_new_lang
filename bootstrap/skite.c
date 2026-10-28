/* skite v0.7: independent native Linux x86-64 compiler (bootstrap S2/G1).
 * Source -> typed AST (static types, constant folding) -> loop-aware liveness -> linear-scan
 * register allocation -> direct x86-64 encoding -> ELF64 executable.
 * No assembler, linker, LLVM/GCC backend, or libc in the output.
 * C is used ONLY to bootstrap this compiler.
 */
#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <limits.h>
#include <sys/stat.h>
#include <stdarg.h>

enum { MAX_NODES=1<<20, MAX_VARS=1<<16, MAX_BYTES=1<<24, MAX_DEPTH=256,
       MAX_LOOPS=1<<16, MAX_PAIRS=1<<20, MAX_PATCH=1<<20, MAX_ACTIVE=10 };
/* 12 allocatable registers, at most 10 hold variables: >= 2 always remain
 * for expression temporaries (a store needs value + index). */

static const char *source,*pos,*tstart,*srcname="input";   /* tstart: first byte of the current token */
static int parsing_src;
/* file:line:col: error: message, then the source line with a caret */
static int node_src(int e);
static int errnode=-1;   /* type errors point at the start of this expression */
static void fail(const char *s){
    if(errnode>=0&&parsing_src&&node_src(errnode)>=0)tstart=source+node_src(errnode);
    if(!parsing_src||!tstart||tstart<source||tstart>source+strlen(source)){fprintf(stderr,"skite: error: %s\n",s);exit(1);}
    int line=1;const char *ls=source;
    for(const char *p=source;p<tstart;p++)if(*p=='\n'){line++;ls=p+1;}
    int col=(int)(tstart-ls)+1;const char *le=ls;while(*le&&*le!='\n')le++;
    fprintf(stderr,"%s:%d:%d: error: %s\n  %.*s\n  %*s^\n",parsing_src==2?"<runtime library>":srcname,line,col,s,(int)(le-ls),ls,col-1,"");
    exit(1);
}
static void failf(const char *fmt,...){
    char b[256];va_list ap;va_start(ap,fmt);vsnprintf(b,sizeof b,fmt,ap);va_end(ap);fail(b);
}
static int64_t I(uint64_t v){int64_t s;memcpy(&s,&v,sizeof s);return s;}
static int fits_s32(uint64_t v);
static uint64_t U(int64_t s){uint64_t v;memcpy(&v,&s,sizeof v);return v;}

/* ------------------------------------------------------------------ lexer */
enum { T_EOF=256,T_ID,T_NUM,T_ARROW,T_FN,T_LET,T_MUT,T_RETURN,T_IF,T_ELSE,
       T_WHILE,T_BREAK,T_CONTINUE,T_EQ,T_NE,T_LE,T_GE,T_SHL,T_SHR,T_SHRU,
       T_LAND,T_LOR,T_OPEQ,T_STR,T_PAR,T_IN,T_DOTDOT,T_AS,T_TRUE,T_FALSE,T_FNUM,T_STRUCT };
/* string literal data (read-only, emitted after the code in the RX segment) */
enum { MAX_SDATA=1<<20 };
static uint8_t sdata[MAX_SDATA];static size_t sdlen;
/* O_SHR = logical >>>, O_SAR = arithmetic >>. Shift counts are taken mod 64. */
/* Typed operators: the parser picks the variant from the operand types, so
 * every later pass sees exact semantics in the opcode (DIVU = unsigned 64-bit,
 * F* = f64, G* = f32). Comparisons O_EQ..O_GEU are integer (signed/unsigned). */
enum { O_ADD,O_SUB,O_MUL,O_DIV,O_MOD,O_AND,O_OR,O_XOR,O_SHL,O_SHR,O_SAR,O_DIVU,O_MODU,
       O_EQ,O_NE,O_LT,O_LE,O_GT,O_GE,O_LTU,O_LEU,O_GTU,O_GEU,O_LAND,O_LOR,
       O_FADD,O_FSUB,O_FMUL,O_FDIV,O_FEQ,O_FNE,O_FLT,O_FLE,O_FGT,O_FGE,
       O_GADD,O_GSUB,O_GMUL,O_GDIV,O_GEQ,O_GNE,O_GLT,O_GLE,O_GGT,O_GGE,
       U_NEG,U_NOT,U_LNOT,U_SX8,U_SX16,U_SX32,U_ZX8,U_ZX16,U_ZX32,
       U_SATS8,U_SATS16,U_SATS32,U_SATU8,U_SATU16,U_SATU32,U_FNEG,U_GNEG,
       U_I2D,U_U2D,U_I2S,U_U2S,U_D2I,U_D2U,U_S2I,U_S2U,U_D2S,U_S2D,U_SQRTD,U_SQRTS };
static int is_fop(int op){return op>=O_FADD&&op<=O_GGE;}
static int is_fcmp(int op){return (op>=O_FEQ&&op<=O_FGE)||(op>=O_GEQ&&op<=O_GGE);}
static int fop_dbl(int op){return op<=O_FGE;}
static int fop_base(int op){return op>=O_GADD?op-(O_GADD-O_FADD):op;}   /* f32 op -> f64 op */
/* Scalar types. Values live in 64-bit registers in canonical form: signed
 * narrow ints sign-extended, unsigned narrow ints zero-extended, bool 0/1,
 * f64 as its bit pattern, f32 bits zero-extended. Widening is therefore free. */
enum { TY_NONE,TY_I8,TY_I16,TY_I32,TY_I64,TY_U8,TY_U16,TY_U32,TY_U64,TY_BOOL,TY_F32,TY_F64,
       TY_ILIT,TY_FLIT,TY_UNIT,NTY };
static const char *tyname[NTY]={"?","i8","i16","i32","i64","u8","u16","u32","u64","bool","f32","f64",
    "integer literal","float literal","()"};
static int ty_sint(int t){return t>=TY_I8&&t<=TY_I64;}
static int ty_uint(int t){return t>=TY_U8&&t<=TY_U64;}
static int ty_int(int t){return ty_sint(t)||ty_uint(t)||t==TY_ILIT;}
static int ty_flt(int t){return t==TY_F32||t==TY_F64;}
static int ty_num(int t){return ty_int(t)||ty_flt(t)||t==TY_FLIT;}
/* struct types: TY_STRUCT0 + index; used as array element types */
enum { TY_STRUCT0=64, MAX_STRUCTS=64, MAX_FIELDS=32 };
typedef struct {char name[64];int nf,fty[MAX_FIELDS],foff[MAX_FIELDS],size;char fname[MAX_FIELDS][64];} Struct;
static Struct sts[MAX_STRUCTS];static int nst;
static int is_struct(int t){return t>=TY_STRUCT0&&t<TY_STRUCT0+nst;}
static const char *type_name(int t){return t>=TY_STRUCT0?sts[t-TY_STRUCT0].name:tyname[t];}
static int ty_width(int t){
    if(is_struct(t))return sts[t-TY_STRUCT0].size;
    switch(t){case TY_I8:case TY_U8:case TY_BOOL:return 1;case TY_I16:case TY_U16:return 2;
    case TY_I32:case TY_U32:case TY_F32:return 4;default:return 8;}
}
typedef struct {int kind,op,big;uint64_t value;double fval;char name[64];size_t soff,slen;} Token;
static Token tok;
static const struct {const char *s;int kind,op;} punct[]={
    {">>>=",T_OPEQ,O_SHR},{">>>",T_SHRU,0},{">>=",T_OPEQ,O_SAR},{"<<=",T_OPEQ,O_SHL},
    {">>",T_SHR,0},{"<<",T_SHL,0},{">=",T_GE,0},{"<=",T_LE,0},{"==",T_EQ,0},
    {"!=",T_NE,0},{"&&",T_LAND,0},{"||",T_LOR,0},{"->",T_ARROW,0},{"..",T_DOTDOT,0},
    {"+=",T_OPEQ,O_ADD},{"-=",T_OPEQ,O_SUB},{"*=",T_OPEQ,O_MUL},{"/=",T_OPEQ,O_DIV},
    {"%=",T_OPEQ,O_MOD},{"&=",T_OPEQ,O_AND},{"|=",T_OPEQ,O_OR},{"^=",T_OPEQ,O_XOR},
};
static void next(void){
    while(*pos){
        if(isspace((unsigned char)*pos)){pos++;continue;}
        if(pos[0]=='/'&&pos[1]=='/'){while(*pos&&*pos!='\n')pos++;continue;}
        break;
    }
    memset(&tok,0,sizeof tok);tstart=pos;
    if(!*pos){tok.kind=T_EOF;return;}
    if(isalpha((unsigned char)*pos)||*pos=='_'){
        size_t i=0;
        while(isalnum((unsigned char)*pos)||*pos=='_'){
            if(i>=sizeof(tok.name)-1)fail("identifier too long");
            tok.name[i++]=*pos++;
        }
        static const struct {const char *s;int k;} kw[]={{"fn",T_FN},{"let",T_LET},
            {"mut",T_MUT},{"return",T_RETURN},{"if",T_IF},{"else",T_ELSE},
            {"while",T_WHILE},{"break",T_BREAK},{"continue",T_CONTINUE},{"par",T_PAR},{"in",T_IN},
            {"as",T_AS},{"true",T_TRUE},{"false",T_FALSE},{"struct",T_STRUCT}};
        tok.kind=T_ID;
        for(size_t k=0;k<sizeof kw/sizeof kw[0];k++)if(!strcmp(tok.name,kw[k].s))tok.kind=kw[k].k;
        return;
    }
    if(*pos=='"'){ /* "..." with \n \t \r \0 \\ \" \xHH */
        pos++;tok.kind=T_STR;tok.soff=sdlen;
        while(*pos!='"'){
            if(!*pos||*pos=='\n')fail("unterminated string literal");
            int c=(unsigned char)*pos++;
            if(c=='\\'){
                c=(unsigned char)*pos++;
                if(c=='n')c=10;else if(c=='t')c=9;else if(c=='r')c=13;else if(c=='0')c=0;
                else if(c=='\\'||c=='"'){}
                else if(c=='x'&&isxdigit((unsigned char)pos[0])&&isxdigit((unsigned char)pos[1])){
                    char h[3]={pos[0],pos[1],0};c=(int)strtol(h,0,16);pos+=2;}
                else fail("bad escape in string literal");
            }
            if(sdlen>=MAX_SDATA)fail("string data limit reached");
            sdata[sdlen++]=(uint8_t)c;
        }
        pos++;tok.slen=sdlen-tok.soff;
        if(!tok.slen)fail("empty string literal");
        return;
    }
    if(*pos=='\''){ /* 'a', '\n', '\x41': an untyped integer literal */
        pos++;int c=(unsigned char)*pos++;
        if(c=='\''||c=='\n'||!c)fail("empty or unterminated character literal");
        if(c=='\\'){
            c=(unsigned char)*pos++;
            if(c=='n')c=10;else if(c=='t')c=9;else if(c=='r')c=13;else if(c=='0')c=0;
            else if(c=='\\'||c=='\''||c=='"'){}
            else if(c=='x'&&isxdigit((unsigned char)pos[0])&&isxdigit((unsigned char)pos[1])){char h[3]={pos[0],pos[1],0};c=(int)strtol(h,0,16);pos+=2;}
            else fail("bad escape in character literal");
        }
        if(*pos!='\'')fail("character literal must be one byte");
        pos++;tok.kind=T_NUM;tok.value=(uint64_t)c;return;
    }
    if(isdigit((unsigned char)*pos)){
        /* 123, 1_000, 0xff (up to u64 max; above i64 max the literal is u64),
         * 1.5, 2e10, 3.0e-7 (float literals; `1..n` stays an integer range) */
        tok.kind=T_NUM;uint64_t v=0;const char *st=pos;
        if(pos[0]=='0'&&(pos[1]=='x'||pos[1]=='X')){
            pos+=2;int nd_=0;
            while(isxdigit((unsigned char)*pos)||*pos=='_'){
                if(*pos=='_'){pos++;continue;}
                int d=isdigit((unsigned char)*pos)?*pos-'0':(tolower((unsigned char)*pos)-'a'+10);pos++;
                if(v>>60)fail("integer literal exceeds u64 maximum");
                v=v*16+(unsigned)d;nd_++;
            }
            if(!nd_)fail("malformed number");
        }else{
            int ovf=0;
            while(isdigit((unsigned char)*pos)||*pos=='_'){
                if(*pos=='_'){pos++;continue;}
                unsigned d=(unsigned)(*pos++-'0');
                if(v>(UINT64_MAX-d)/10ULL)ovf=1;
                v=v*10+d;
            }
            if(ovf&&!((pos[0]=='.'&&isdigit((unsigned char)pos[1]))||*pos=='e'||*pos=='E'))fail("integer literal exceeds u64 maximum");
            if((pos[0]=='.'&&isdigit((unsigned char)pos[1]))||*pos=='e'||*pos=='E'){
                char buf[128];size_t k=0;const char *q=st;
                if(*pos=='.'){pos++;while(isdigit((unsigned char)*pos)||*pos=='_')pos++;}
                if(*pos=='e'||*pos=='E'){pos++;if(*pos=='+'||*pos=='-')pos++;
                    if(!isdigit((unsigned char)*pos))fail("malformed float literal");
                    while(isdigit((unsigned char)*pos))pos++;}
                for(;q<pos;q++){if(*q=='_')continue;if(k>=sizeof buf-1)fail("float literal too long");buf[k++]=*q;}
                buf[k]=0;tok.kind=T_FNUM;tok.fval=strtod(buf,0);
                if(isalpha((unsigned char)*pos)||*pos=='_')fail("malformed number");
                return;
            }
        }
        if(isalpha((unsigned char)*pos)||*pos=='_')fail("malformed number");
        tok.value=v;tok.big=v>(uint64_t)INT64_MAX;return;
    }
    for(size_t k=0;k<sizeof punct/sizeof punct[0];k++){
        size_t n=strlen(punct[k].s);
        if(!strncmp(pos,punct[k].s,n)){pos+=n;tok.kind=punct[k].kind;tok.op=punct[k].op;return;}
    }
    if(strchr("+-*/%(){};:=<>!~&|^[],.",*pos)){tok.kind=(unsigned char)*pos++;return;}
    fail("unexpected character");
}
static void expect(int t){if(tok.kind!=t)fail("unexpected token");next();}

/* ------------------------------------------------------------------ AST */
enum { N_CONST,N_VAR,N_UN,N_BIN,N_LOAD,N_CALL,N_ARR,S_LET,S_ASSIGN,S_IF,S_WHILE,S_RET,S_BRK,S_CONT,S_BLOCK,
       S_ARR,S_STORE,S_PRINT,S_PUTC,S_EXPR,S_WRITE,S_INL,S_IRET,S_PAR,N_NCPU,S_SAVE };
/* S_SAVE: save(k, a, n): var = u8 array, a = argv index, b = byte count */
/* S_PAR: par k in a..b { c }  (var = k, op = hidden end variable). N_NCPU: ncpu(). */
/* S_INL: inlined call body (a = first statement, var = result variable).
 * S_IRET: `return e` inside an inlined body: var = e, then leave the S_INL. */
/* N_CALL: var = function, a = first argument (arguments chained through next).
 * N_ARR: array argument (var = array). S_WRITE: var = u8 array, a = offset, b = count (-1: whole). */
/* N_LOAD: var=array, a=index. S_STORE: var=array, a=index, b=value, op=-1 or ALU op.
 * S_ARR: var=array, a=size/argv-index expr (or -1), op=A_ALLOC/A_FILE/A_VIEW, c=source array.
 * chk: bounds check required (cleared when range analysis proves the index in range). */
typedef struct {int k,op,a,b,c,next,var,pos,chk,nn,ty,src;uint64_t v;int64_t dlo,dhi;} Node;   /* src: source offset (-1: none) */
/* ty: static type (set by the parser; later passes rely on the typed opcodes) */
/* nn (DIV/MOD): dividend proven >= 0 at this program point */
enum { A_ALLOC,A_FILE,A_VIEW,A_STR };
/* functions */
enum { MAX_FUNCS=4096, MAX_PARAMS=16 };
typedef struct {char name[64];int np,pvar[MAX_PARAMS],pw[MAX_PARAMS],pmut[MAX_PARAMS],pty[MAX_PARAMS],body,used,exit_list;size_t addr;int calls,nret,rett,mark;} Func;
/* mark: hidden variable holding the arena top at entry (functions with scoped allocations), else -1 */
/* pty: scalar parameter type, or element type of an array parameter (pw = element bytes) */
static Func fns[MAX_FUNCS];static int nfn,curfn,mainfn;
static Node nd[MAX_NODES];static int nn;
static int node_src(int e){return nd[e].src;}
static int mk(int k){
    if(nn>=MAX_NODES)fail("program too large");
    nd[nn]=(Node){.k=k,.a=-1,.b=-1,.c=-1,.next=-1,.var=-1,.dhi=-1,.ty=TY_I64,.src=parsing_src&&tstart?(int)(tstart-source):-1};
    return nn++;
}
typedef struct {char name[64];int mut,isconst,alias,hoist,reads,start,end,reg,slot;uint64_t cval;int64_t weight;
    int arr,ro,basev,lenv,shared;int64_t alen;   /* arrays: elem bytes, read-only, base/len vars, MAP_SHARED, const len */
    int lenof,aid;                                /* len var: 1+array; array alias-class bit (-1: none) */
    int ty,et;                                    /* scalar type; array element type */
    int owner;                                    /* declaring function (-1: compiler-made later) */
    int glob,garr;} Var;                          /* static (bss) array; global scalar -> its 1-element array */
/* hoist: 1+loop id for a loop-invariant constant pseudo-variable (cval = value) */
static Var vars[MAX_VARS];static int nv;
static int vis[MAX_VARS],nvis;
static int is_const(int e){return nd[e].k==N_CONST;}
static int is_cmp_op(int op){return op>=O_EQ&&op<=O_GEU;}
static int mkconst(uint64_t v){int e=mk(N_CONST);nd[e].v=v;return e;}
static int mkconst_t(uint64_t v,int t){int e=mkconst(v);nd[e].ty=t;return e;}
static uint64_t sar64(uint64_t x,unsigned n){return I(x)<0?~(~x>>n):x>>n;}
/* float bit helpers: the compiler folds with the host's IEEE binary32/64
 * (SSE on x86-64, round-to-nearest, no contraction under -std=c11) */
static double D(uint64_t v){double d;memcpy(&d,&v,8);return d;}
static uint64_t DB(double d){uint64_t v;memcpy(&v,&d,8);return v;}
static float S(uint64_t v){float f;uint32_t u=(uint32_t)v;memcpy(&f,&u,4);return f;}
static uint64_t SB(float f){uint32_t u;memcpy(&u,&f,4);return u;}
static uint64_t eval_fbin(int op,uint64_t x,uint64_t y){
    int dbl=fop_dbl(op);op=fop_base(op);
    double a=dbl?D(x):S(x),b=dbl?D(y):S(y);
    switch(op){
    case O_FEQ:return a==b; case O_FNE:return a!=b; case O_FLT:return a<b;
    case O_FLE:return a<=b; case O_FGT:return a>b; case O_FGE:return a>=b;
    }
    if(dbl){double r=op==O_FADD?a+b:op==O_FSUB?a-b:op==O_FMUL?a*b:a/b;return DB(r);}
    float fa=(float)a,fb=(float)b,r=op==O_FADD?fa+fb:op==O_FSUB?fa-fb:op==O_FMUL?fa*fb:fa/fb;
    return SB(r);
}
static uint64_t eval_bin(int op,uint64_t x,uint64_t y){
    int64_t a=I(x),b=I(y);
    if(is_fop(op))return eval_fbin(op,x,y);
    switch(op){
        case O_DIVU:case O_MODU:
            if(y==0)fail("division by zero");
            return op==O_DIVU?x/y:x%y;
        case O_LTU:return x<y; case O_LEU:return x<=y; case O_GTU:return x>y; case O_GEU:return x>=y;
        case O_ADD:return x+y; case O_SUB:return x-y; case O_MUL:return x*y;
        case O_DIV:case O_MOD:
            if(b==0)fail("division by zero");
            if(a==INT64_MIN&&b==-1)fail("signed division overflows");
            return U(op==O_DIV?a/b:a%b);
        case O_AND:return x&y; case O_OR:return x|y; case O_XOR:return x^y;
        case O_SHL:return x<<(y&63); case O_SHR:return x>>(y&63); case O_SAR:return sar64(x,(unsigned)(y&63));
        case O_EQ:return a==b; case O_NE:return a!=b; case O_LT:return a<b;
        case O_LE:return a<=b; case O_GT:return a>b; case O_GE:return a>=b;
        case O_LAND:return x&&y; case O_LOR:return x||y;
    }
    fail("internal fold error");return 0;
}
/* float -> int conversions saturate; NaN -> 0 (same as the generated code) */
static int64_t sat_i64(double d){if(d!=d)return 0;if(d>=9223372036854775808.0)return INT64_MAX;if(d<=-9223372036854775808.0)return INT64_MIN;return (int64_t)d;}
static uint64_t sat_u64(double d){if(d!=d||d<=0)return 0;if(d>=18446744073709551616.0)return UINT64_MAX;return (uint64_t)d;}
static int64_t clampi(int64_t v,int64_t lo,int64_t hi){return v<lo?lo:v>hi?hi:v;}
static uint64_t eval_un(int op,uint64_t v){
    switch(op){
    case U_NEG:return 0-v; case U_NOT:return ~v; case U_LNOT:return v==0;
    case U_SX8:return U((int8_t)v); case U_SX16:return U((int16_t)v); case U_SX32:return U((int32_t)v);
    case U_ZX8:return (uint8_t)v; case U_ZX16:return (uint16_t)v; case U_ZX32:return (uint32_t)v;
    case U_SATS8:return U(clampi(I(v),-128,127)); case U_SATS16:return U(clampi(I(v),-32768,32767));
    case U_SATS32:return U(clampi(I(v),INT32_MIN,INT32_MAX)); case U_SATU8:return U(clampi(I(v),0,255));
    case U_SATU16:return U(clampi(I(v),0,65535)); case U_SATU32:return U(clampi(I(v),0,UINT32_MAX));
    case U_FNEG:return v^(1ULL<<63); case U_GNEG:return (v^0x80000000ULL)&0xffffffffULL;
    case U_I2D:return DB((double)I(v)); case U_U2D:return DB((double)v);
    case U_I2S:return SB((float)I(v)); case U_U2S:return SB((float)v);
    case U_D2I:return U(sat_i64(D(v))); case U_D2U:return sat_u64(D(v));
    case U_S2I:return U(sat_i64(S(v))); case U_S2U:return sat_u64(S(v));
    case U_D2S:return SB((float)D(v)); case U_S2D:return DB((double)S(v));
    }
    fail("internal fold error");return 0;
}
/* result type of a (typed) binary node: comparisons give bool, else the left type */
static int bin_rty(int op,int a){
    if(is_cmp_op(op)||is_fcmp(op)||op==O_LAND||op==O_LOR)return TY_BOOL;
    return nd[a].ty;
}
static int mk_bin(int op,int a,int b){
    /* Trap rule (review D2, option A): a literal zero integer divisor is always an error. */
    if((op==O_DIV||op==O_MOD||op==O_DIVU||op==O_MODU)&&is_const(b)&&nd[b].v==0)fail("division by zero");
    if(op==O_LAND&&is_const(a))return nd[a].v?b:mkconst_t(0,TY_BOOL);   /* operands are bool (0/1) */
    if(op==O_LOR&&is_const(a))return nd[a].v?mkconst_t(1,TY_BOOL):b;
    int rt=bin_rty(op,a);
    if(is_const(a)&&is_const(b))return mkconst_t(eval_bin(op,nd[a].v,nd[b].v),rt);
    int e=mk(N_BIN);nd[e].op=op;nd[e].a=a;nd[e].b=b;nd[e].ty=rt;return e;
}
static int mk_un(int op,int a,int t){
    if(is_const(a)&&op!=U_SQRTD&&op!=U_SQRTS)return mkconst_t(eval_un(op,nd[a].v),t);   /* sqrt: not folded (no libm in the seed) */
    int e=mk(N_UN);nd[e].op=op;nd[e].a=a;nd[e].ty=t;return e;
}

/* ---------------------------------------------------- value ranges */
/* Flow-sensitive interval analysis over the structured AST (abstract
 * interpretation): assignments update the environment, if/while conditions
 * refine it per branch, loops iterate to a fixpoint with widening, and each
 * scalar also carries "known < len(array k)" facts. Array contents are tracked
 * per alias class (join of all stored ranges). Results: bounds checks that are
 * proven redundant (chk=0) and non-negative dividends (nn=1). Sound under
 * wrapping arithmetic: any bound computation that could overflow gives FULL. */
typedef struct {int64_t lo,hi;int bot;} Rg;
static Rg RG(int64_t lo,int64_t hi){return (Rg){lo,hi,0};}
static const Rg FULL={INT64_MIN,INT64_MAX,0},BOT={0,0,1};
static int ov_add(int64_t a,int64_t b,int64_t *r){if((b>0&&a>INT64_MAX-b)||(b<0&&a<INT64_MIN-b))return 1;*r=a+b;return 0;}
static int ov_sub(int64_t a,int64_t b,int64_t *r){if((b<0&&a>INT64_MAX+b)||(b>0&&a<INT64_MIN+b))return 1;*r=a-b;return 0;}
static int ov_mul(int64_t a,int64_t b,int64_t *r){
    if(a==0||b==0){*r=0;return 0;}
    if((a==-1&&b==INT64_MIN)||(b==-1&&a==INT64_MIN))return 1;
    if(a>0?(b>0?a>INT64_MAX/b:b<INT64_MIN/a):(b>0?a<INT64_MIN/b:a<INT64_MAX/b))return 1;
    *r=a*b;return 0;
}
static int64_t mx(int64_t a,int64_t b){return a>b?a:b;}
static int64_t mn(int64_t a,int64_t b){return a<b?a:b;}
static int64_t pmask(int64_t v){uint64_t m=0;while(m<(uint64_t)v)m=m*2+1;return (int64_t)m;}
static Rg rjoin(Rg a,Rg b){if(a.bot)return b;if(b.bot)return a;return RG(mn(a.lo,b.lo),mx(a.hi,b.hi));}
static Rg type_rg(int t){ /* values of type t (floats: any bit pattern) */
    switch(t){
    case TY_I8:return RG(-128,127); case TY_I16:return RG(-32768,32767); case TY_I32:return RG(INT32_MIN,INT32_MAX);
    case TY_U8:return RG(0,255); case TY_U16:return RG(0,65535); case TY_U32:case TY_F32:return RG(0,UINT32_MAX);
    case TY_BOOL:return RG(0,1);
    }
    return FULL;
}
static Rg rclamp(Rg a,Rg t){ /* monotone clamp of every value into t */
    if(a.bot)return a;
    return RG(clampi(a.lo,t.lo,t.hi),clampi(a.hi,t.lo,t.hi));
}
static Rg rbin(int op,Rg a,Rg b,int bc,int64_t c){
    if(is_cmp_op(op)||is_fcmp(op)||op==O_LAND||op==O_LOR)return RG(0,1);
    if(a.bot||b.bot)return BOT;
    if(op==O_DIVU||op==O_MODU){ /* unsigned: identical to signed when both sides are >= 0 */
        if(bc&&c>0){
            if(op==O_MODU)return RG(0,c-1);
            if(a.lo>=0)return RG(a.lo/c,a.hi/c);
            return c>1?RG(0,(int64_t)(UINT64_MAX/(uint64_t)c)):FULL;
        }
        if(a.lo>=0&&b.lo>=0)op=op==O_DIVU?O_DIV:O_MOD;else return FULL;
    }
    int64_t l,h,p[4];
    switch(op){
    case O_ADD:if(ov_add(a.lo,b.lo,&l)||ov_add(a.hi,b.hi,&h))return FULL;return RG(l,h);
    case O_SUB:if(ov_sub(a.lo,b.hi,&l)||ov_sub(a.hi,b.lo,&h))return FULL;return RG(l,h);
    case O_MUL:
        if(ov_mul(a.lo,b.lo,&p[0])||ov_mul(a.lo,b.hi,&p[1])||ov_mul(a.hi,b.lo,&p[2])||ov_mul(a.hi,b.hi,&p[3]))return FULL;
        return RG(mn(mn(p[0],p[1]),mn(p[2],p[3])),mx(mx(p[0],p[1]),mx(p[2],p[3])));
    case O_DIV:
        if(bc&&c>0)return RG(a.lo/c,a.hi/c);
        if(bc&&c<-1)return RG(a.hi/c,a.lo/c);
        if(a.lo>=0&&b.lo>=0)return RG(0,a.hi);
        if(a.lo==INT64_MIN)return FULL;
        {int64_t m=mx(-a.lo,a.hi);return RG(-m,m);}
    case O_MOD:{
        int64_t lim=INT64_MAX;
        if(bc)lim=c==INT64_MIN?INT64_MAX:(c<0?-c:c)-1;
        else if(b.lo>INT64_MIN){int64_t m=mx(b.hi,-b.lo);if(m>0)lim=m-1;}   /* |a % b| < |b| */
        if(a.lo>=0)return RG(0,mn(a.hi,lim));
        if(a.hi<=0)return RG(mx(a.lo,-lim),0);
        return RG(mx(a.lo,-lim),mn(a.hi,lim));}
    case O_AND:
        if(a.lo>=0&&b.lo>=0)return RG(0,mn(a.hi,b.hi));
        if(a.lo>=0)return RG(0,a.hi);
        if(b.lo>=0)return RG(0,b.hi);
        return FULL;
    case O_OR:case O_XOR:
        if(a.lo>=0&&b.lo>=0)return RG(0,pmask(mx(a.hi,b.hi)));
        return FULL;
    case O_SHL:{
        if(!bc)return FULL;
        int k=(int)(c&63);if(!k)return a;
        if(k==63)return FULL;
        int64_t m=(int64_t)1<<k;
        if(ov_mul(a.lo,m,&l)||ov_mul(a.hi,m,&h))return FULL;
        return RG(l,h);}
    case O_SHR:{
        if(!bc)return a.lo>=0?RG(0,a.hi):FULL;
        int k=(int)(c&63);if(!k)return a;
        if(a.lo>=0)return RG(a.lo>>k,a.hi>>k);
        return RG(0,(int64_t)(UINT64_MAX>>k));}
    case O_SAR:{
        if(!bc)return RG(a.lo<0?a.lo:0,a.hi>0?a.hi:0);
        unsigned k=(unsigned)(c&63);
        return RG(I(sar64(U(a.lo),k)),I(sar64(U(a.hi),k)));}
    }
    return FULL;
}
static int body;
typedef struct {Rg r;uint64_t lt;} VR;   /* range + bitmask of arrays k with v < len(a_k) */
static int an_annot,an_changed;
static Rg arr_rg[MAX_VARS];               /* content range per array (alias class leader) */
static int arr_chg[MAX_VARS];
static VR *wcache[MAX_NODES];             /* per-loop converged head, reused across outer iterations */
static VR *wentry[MAX_NODES];
enum { WCACHE_MAX=256<<20 };              /* convergence cache budget (bytes): beyond it, loops re-converge */
static int64_t wcache_bytes;
static void wcache_free(void){for(int i=0;i<nn;i++)if(wcache[i]){free(wcache[i]);wcache[i]=NULL;}wcache_bytes=0;}
static int has_mod(int e){ /* contains a signed % (periodic-index candidates) */
    if(e<0)return 0;
    Node *x=&nd[e];
    if(x->k==N_BIN&&x->op==O_MOD)return 1;
    if(x->k==N_CALL){for(int a=x->a;a>=0;a=nd[a].next)if(has_mod(a))return 1;return 0;}
    if(x->k==S_BLOCK||x->k==S_INL){for(int c=x->a;c>=0;c=nd[c].next)if(has_mod(c))return 1;return 0;}
    if(x->k==S_PAR)return has_mod(x->a)||has_mod(x->b)||has_mod(x->c);
    return has_mod(x->a)||has_mod(x->b)||(x->k==S_IF&&has_mod(x->c));
}
static int wfn[MAX_NODES],an_fn;          /* function whose variable map a wentry uses */             /* per-loop entry state from the final (annotating) pass */
static int arr_leader[MAX_VARS];
/* Environments are sized by env_n = variable count when analysis starts;
 * variables created later (strength reduction) are never looked up in them. */
static int env_n;
/* Environments are per function: lmap numbers the variables one function's
 * analysis can touch (0..env_n-1), so cost scales with the function, not the program. */
static int lmap[MAX_VARS],lvars[MAX_VARS],nlvars,lmap_fn=-2;
static int LV(int v){int i=lmap[v];if(i<0)fail("internal: variable outside the analyzed function");return i;}
static void lv_add(int v){if(v>=0&&lmap[v]<0){lmap[v]=nlvars;lvars[nlvars++]=v;}}
static void lv_arr(int a){if(vars[a].lenv>=0)lv_add(vars[a].lenv);}
static void lv_stmt(int s);
static void lv_expr(int e){
    if(e<0)return;
    Node *x=&nd[e];
    switch(x->k){
    case N_VAR:lv_add(x->var);return;
    case N_LOAD:lv_arr(x->var);lv_expr(x->a);return;
    case N_ARR:lv_arr(x->var);return;
    case N_CALL:for(int a=x->a;a>=0;a=nd[a].next)lv_expr(a);return;
    case N_CONST:case N_NCPU:return;
    }
    lv_expr(x->a);lv_expr(x->b);
}
static void lv_stmt(int s){
    if(s<0)return;
    Node *x=&nd[s];
    switch(x->k){
    case S_LET:case S_ASSIGN:case S_IRET:lv_add(x->var);lv_expr(x->a);return;
    case S_ARR:lv_arr(x->var);lv_expr(x->a);return;
    case S_STORE:case S_WRITE:case S_SAVE:if(x->var>=0)lv_arr(x->var);lv_expr(x->a);lv_expr(x->b);return;
    case S_PAR:lv_add(x->var);lv_add(x->op);lv_expr(x->a);lv_expr(x->b);lv_stmt(x->c);return;
    case S_IF:lv_expr(x->a);lv_stmt(x->b);lv_stmt(x->c);return;
    case S_WHILE:lv_expr(x->a);lv_stmt(x->b);return;
    case S_BLOCK:case S_INL:for(int c=x->a;c>=0;c=nd[c].next)lv_stmt(c);return;
    }
    lv_expr(x->a);
}
/* the numbering is fixed at first use (later passes add variables; old envs must stay valid) */
static int *fl_vars[MAX_FUNCS],fl_n[MAX_FUNCS];
static void lmap_for(int f){
    if(lmap_fn==f)return;
    for(int i=0;i<nlvars;i++)lmap[lvars[i]]=-1;
    nlvars=0;lmap_fn=f;
    if(fl_vars[f]){for(int i=0;i<fl_n[f];i++)lv_add(fl_vars[f][i]);env_n=nlvars;return;}
    if(f==mainfn)lv_add(0);
    for(int i=0;i<fns[f].np;i++){int v=fns[f].pvar[i];if(fns[f].pw[i])lv_add(vars[v].lenv);else lv_add(v);}
    lv_stmt(fns[f].body);
    env_n=nlvars;
    fl_vars[f]=malloc(sizeof(int)*(size_t)(nlvars+1));if(!fl_vars[f]){perror("malloc");exit(1);}
    memcpy(fl_vars[f],lvars,sizeof(int)*(size_t)nlvars);fl_n[f]=nlvars;
}
static VR *env_new(void){VR *e=calloc((size_t)env_n+1,sizeof(VR));if(!e){perror("calloc");exit(1);}return e;}
static int dead(VR *e){return e[env_n].r.lo!=0;}
static void set_dead(VR *e){e[env_n].r.lo=1;}
static void env_copy(VR *d,VR *s){memcpy(d,s,sizeof(VR)*((size_t)env_n+1));}
static void env_join(VR *d,VR *s){ /* d = d join s */
    if(dead(s))return;
    if(dead(d)){env_copy(d,s);return;}
    for(int v=0;v<env_n;v++){d[v].r=rjoin(d[v].r,s[v].r);d[v].lt&=s[v].lt;}
}
static int env_eq(VR *a,VR *b){
    if(dead(a)!=dead(b))return 0;
    for(int v=0;v<env_n;v++)if(a[v].lt!=b[v].lt||a[v].r.bot!=b[v].r.bot||(!a[v].r.bot&&(a[v].r.lo!=b[v].r.lo||a[v].r.hi!=b[v].r.hi)))return 0;
    return 1;
}
/* Widening with thresholds: a growing bound jumps to the next program
 * constant (c-1, c, c+1) instead of straight to +/-inf. Finite set, so the
 * ascending chain still terminates. */
enum { MAX_THR=4096 };
static int64_t thr[MAX_THR];static int nthr;
static void add_thr(int64_t c){
    for(int64_t d=-1;d<=1;d++){
        int64_t v;if(ov_add(c,d,&v))continue;
        int i=0;while(i<nthr&&thr[i]<v)i++;
        if(i<nthr&&thr[i]==v)continue;
        if(nthr>=MAX_THR)return;
        memmove(thr+i+1,thr+i,sizeof thr[0]*(size_t)(nthr-i));thr[i]=v;nthr++;
    }
}
static void env_widen(VR *old,VR *nw,int use_thr){ /* nw = old widen nw */
    if(dead(old))return;
    for(int v=0;v<env_n;v++){
        Rg o=old[v].r,*n=&nw[v].r;
        if(o.bot||n->bot)continue;
        if(n->lo<o.lo){int64_t t=INT64_MIN;if(use_thr)for(int i=nthr-1;i>=0;i--)if(thr[i]<=n->lo){t=thr[i];break;}n->lo=t;}
        if(n->hi>o.hi){int64_t t=INT64_MAX;if(use_thr)for(int i=0;i<nthr;i++)if(thr[i]>=n->hi){t=thr[i];break;}n->hi=t;}
    }
}
static Rg er(int e,VR *env);
static int proven(int a,int idx,Rg r,VR *env){
    Var *A=&vars[a];
    if(r.bot||r.lo<0)return 0;
    if(A->lenv<0)return r.hi<A->alen;
    if(nd[idx].k==N_VAR&&A->aid>=0&&(env[LV(nd[idx].var)].lt>>A->aid&1))return 1;
    Rg L=env[LV(A->lenv)].r;return !L.bot&&r.hi<L.lo;
}
static void refine(VR *env,int c,int sense);
static Rg er(int e,VR *env){
    Node *x=&nd[e];
    switch(x->k){
    case N_CONST:return RG(I(x->v),I(x->v));
    case N_VAR:return env[LV(x->var)].r;
    case N_ARR:return BOT;
    case N_NCPU:return RG(1,1024);
    case N_CALL:
        for(int a=x->a;a>=0;a=nd[a].next)if(nd[a].k!=N_ARR)er(a,env);
        return FULL;
    case N_LOAD:{
        Rg r=er(x->a,env);
        if(an_annot)x->chk=!proven(x->var,x->a,r,env);
        if(an_annot){x->dlo=r.lo;x->dhi=r.hi;}
        if(x->op>0)return type_rg(x->ty);                 /* struct field: its type's range */
        Rg c=arr_rg[arr_leader[x->var]],t=type_rg(vars[x->var].et);
        if(c.bot)return RG(0,0);
        if(c.lo<t.lo||c.hi>t.hi)return t;                /* a load never exceeds its element type */
        return c;}
    case N_UN:{
        Rg a=er(x->a,env);if(a.bot)return BOT;
        switch(x->op){
        case U_LNOT:return RG(0,1);
        case U_NOT:return RG(~a.hi,~a.lo);
        case U_NEG:return a.lo==INT64_MIN?FULL:RG(-a.hi,-a.lo);
        case U_SX8:case U_SX16:case U_SX32:case U_ZX8:case U_ZX16:case U_ZX32:
        case U_SATS8:case U_SATS16:case U_SATS32:case U_SATU8:case U_SATU16:case U_SATU32:{
            /* target from the opcode: implicit widening may have retagged x->ty */
            static const int tgt[]={TY_I8,TY_I16,TY_I32,TY_U8,TY_U16,TY_U32,TY_I8,TY_I16,TY_I32,TY_U8,TY_U16,TY_U32};
            Rg t=type_rg(tgt[x->op-U_SX8]);int in=a.lo>=t.lo&&a.hi<=t.hi;
            if(an_annot)x->nn=in;                       /* proven in range: the narrowing is a no-op */
            if(in)return a;
            return x->op>=U_SATS8?rclamp(a,t):t;}
        }
        return type_rg(x->ty);}   /* conversions: any value of the result type */
    }
    if(x->op==O_LAND||x->op==O_LOR){
        er(x->a,env);
        VR *t=env_new();env_copy(t,env);refine(t,x->a,x->op==O_LAND);
        if(!dead(t))er(x->b,t);
        free(t);return RG(0,1);
    }
    Rg a=er(x->a,env),b=er(x->b,env);
    if(an_annot&&(x->op==O_DIV||x->op==O_MOD))x->nn=!a.bot&&a.lo>=0;
    return rbin(x->op,a,b,is_const(x->b),I(nd[x->b].v));
}
static void refine_var(VR *env,int v,int op,int other){
    Rg r=er(other,env),*x=&env[LV(v)].r;
    if(r.bot||x->bot)return;
    switch(op){
    case O_LT:if(r.hi==INT64_MIN){set_dead(env);return;}x->hi=mn(x->hi,r.hi-1);
        if(nd[other].k==N_VAR&&vars[nd[other].var].lenof){int a=vars[nd[other].var].lenof-1;if(vars[a].aid>=0)env[LV(v)].lt|=1ULL<<vars[a].aid;}
        break;
    case O_LE:x->hi=mn(x->hi,r.hi);break;
    case O_GT:if(r.lo==INT64_MAX){set_dead(env);return;}x->lo=mx(x->lo,r.lo+1);break;
    case O_GE:x->lo=mx(x->lo,r.lo);break;
    case O_EQ:x->lo=mx(x->lo,r.lo);x->hi=mn(x->hi,r.hi);break;
    case O_NE:if(r.lo==r.hi){if(x->lo==r.lo&&x->lo<INT64_MAX)x->lo++;else if(x->hi==r.lo&&x->hi>INT64_MIN)x->hi--;}break;
    }
    if(x->lo>x->hi)set_dead(env);
}
static int neg_cmp(int op){switch(op){case O_LT:return O_GE;case O_GE:return O_LT;case O_LE:return O_GT;case O_GT:return O_LE;case O_EQ:return O_NE;default:return O_EQ;}}
static int swp_cmp(int op){switch(op){case O_LT:return O_GT;case O_GT:return O_LT;case O_LE:return O_GE;case O_GE:return O_LE;default:return op;}}
static void refine(VR *env,int c,int sense){
    if(dead(env))return;
    Node *x=&nd[c];
    if(x->k==N_CONST){if((x->v!=0)!=sense)set_dead(env);return;}
    if(x->k==N_UN&&x->op==U_LNOT){refine(env,x->a,!sense);return;}
    if(x->k!=N_BIN)return;
    if(x->op==O_LAND){if(sense){refine(env,x->a,1);refine(env,x->b,1);}return;}
    if(x->op==O_LOR){if(!sense){refine(env,x->a,0);refine(env,x->b,0);}return;}
    if(!is_cmp_op(x->op))return;
    int op=x->op;
    if(op>=O_LTU){ /* unsigned compare = signed compare when both sides are >= 0 */
        Rg ra=er(x->a,env),rb=er(x->b,env);
        if(ra.bot||rb.bot||ra.lo<0||rb.lo<0)return;
        op=op-O_LTU+O_LT;
    }
    op=sense?op:neg_cmp(op);
    if(nd[x->a].k==N_VAR)refine_var(env,nd[x->a].var,op,x->b);
    if(nd[x->b].k==N_VAR&&!dead(env))refine_var(env,nd[x->b].var,swp_cmp(op),x->a);
}
static VR *brk_env[MAX_LOOPS],*cont_env[MAX_LOOPS];static int an_loops;
static VR *inl_env[MAX_LOOPS];static int an_inl;
static void as_stmt(int s,VR *env);
static void arr_store(int a,Rg v){
    int L=arr_leader[a];Rg t=type_rg(vars[a].et);
    if(v.bot)return;
    if(v.lo<t.lo||v.hi>t.hi)v=t;                       /* truncating store */
    Rg n=rjoin(arr_rg[L],v);
    if(n.bot!=arr_rg[L].bot||n.lo!=arr_rg[L].lo||n.hi!=arr_rg[L].hi){arr_rg[L]=n;an_changed=1;arr_chg[L]=1;}
}
static void as_stmt(int s,VR *env){
    if(dead(env))return;
    Node *x=&nd[s];
    switch(x->k){
    case S_LET:case S_ASSIGN:{Rg r=er(x->a,env);env[LV(x->var)].r=r;env[LV(x->var)].lt=0;break;}
    case S_ARR:{
        Var *a=&vars[x->var];
        if(x->a>=0)er(x->a,env);
        if(a->lenv>=0){
            Rg L=x->op==A_ALLOC?RG(1,INT32_MAX):x->op==A_FILE?RG(0,(int64_t)1<<47):RG(0,(int64_t)1<<47);
            env[LV(a->lenv)].r=L;env[LV(a->lenv)].lt=0;
        }
        break;}
    case S_STORE:{
        Rg ri=er(x->a,env);
        if(an_annot){x->chk=!proven(x->var,x->a,ri,env);x->dlo=ri.lo;x->dhi=ri.hi;}
        Rg rv=er(x->b,env);
        if(x->op<0)arr_store(x->var,rv);else arr_store(x->var,type_rg(vars[x->var].et));
        break;}
    case S_PRINT:case S_PUTC:case S_EXPR:er(x->a,env);if(x->k==S_PUTC&&x->op==1)set_dead(env);break;
    case S_WRITE:if(x->a>=0){er(x->a,env);er(x->b,env);}break;
    case S_SAVE:er(x->a,env);er(x->b,env);break;
    case S_RET:er(x->a,env);set_dead(env);break;
    case S_BRK:env_join(brk_env[an_loops-1],env);set_dead(env);break;
    case S_IRET:{Rg r=er(x->a,env);env[LV(x->var)].r=r;env[LV(x->var)].lt=0;env_join(inl_env[an_inl-1],env);set_dead(env);break;}
    case S_PAR:{
        Rg ra=er(x->a,env),rb=er(x->b,env);
        VR *t=env_new();env_copy(t,env);
        Rg kr=FULL;
        if(!ra.bot&&!rb.bot&&rb.hi>INT64_MIN)kr=RG(ra.lo,rb.hi-1);
        if(kr.lo<=kr.hi){t[LV(x->var)].r=kr;t[LV(x->var)].lt=0;t[LV(x->op)].r=rb.bot?FULL:rb;as_stmt(x->c,t);}
        free(t);break;}   /* scalars are unchanged after the join; shared contents were joined */
    case S_INL:{
        if(an_inl>=MAX_LOOPS)fail("inlining nested too deeply");
        int L=an_inl++;inl_env[L]=env_new();set_dead(inl_env[L]);
        for(int c=x->a;c>=0;c=nd[c].next)as_stmt(c,env);
        env_join(env,inl_env[L]);
        if(!dead(env))env[env_n].r.lo=0;
        free(inl_env[L]);an_inl--;break;}
    case S_CONT:env_join(cont_env[an_loops-1],env);set_dead(env);break;
    case S_BLOCK:for(int c=x->a;c>=0;c=nd[c].next)as_stmt(c,env);break;
    case S_IF:{
        er(x->a,env);
        VR *t=env_new(),*f=env_new();env_copy(t,env);env_copy(f,env);
        refine(t,x->a,1);refine(f,x->a,0);
        as_stmt(x->b,t);if(x->c>=0)as_stmt(x->c,f);
        env_copy(env,t);env_join(env,f);
        if(dead(t)&&dead(f))set_dead(env);
        free(t);free(f);break;}
    case S_WHILE:{
        VR *entry=env_new(),*head=env_new(),*body=env_new(),*nh=env_new();
        env_copy(entry,env);env_copy(head,env);
        /* Outer iterations only grow, so a previous converged head is below
         * the new least fixpoint: starting from it is sound and fast. */
        if(wcache[s])env_join(head,wcache[s]);
        if(an_loops>=MAX_LOOPS)fail("loops nested too deeply");
        int L=an_loops++;brk_env[L]=env_new();cont_env[L]=env_new();
        for(int it=0;;it++){
            set_dead(brk_env[L]);set_dead(cont_env[L]);
            env_copy(body,head);er(x->a,body);refine(body,x->a,1);
            as_stmt(x->b,body);env_join(body,cont_env[L]);
            env_copy(nh,entry);env_join(nh,body);
            env_join(nh,head);                     /* monotone ascent: never shrink the head */
            if(it>=2)env_widen(head,nh,it<40);   /* thresholds first, then +/-inf */
            if(env_eq(nh,head))break;
            env_copy(head,nh);
            if(it>200)fail("internal: range analysis did not converge");
        }
        /* Narrowing: head is a post-fixpoint; F(head) = entry join body(head) is
         * a smaller post-fixpoint, still above the least one (sound). */
        for(int it=0;it<3;it++){
            set_dead(brk_env[L]);set_dead(cont_env[L]);
            env_copy(body,head);er(x->a,body);refine(body,x->a,1);
            as_stmt(x->b,body);env_join(body,cont_env[L]);
            env_copy(nh,entry);env_join(nh,body);
            if(env_eq(nh,head))break;
            env_copy(head,nh);
        }
        if(!wcache[s]&&wcache_bytes<WCACHE_MAX){wcache[s]=env_new();wcache_bytes+=(int64_t)(env_n+1)*(int64_t)sizeof(VR);}
        if(wcache[s])env_copy(wcache[s],head);
        if(an_annot&&has_mod(x->b)){if(!wentry[s])wentry[s]=env_new();env_copy(wentry[s],entry);wfn[s]=an_fn;}   /* strength-reduction candidates only */
        env_copy(env,head);refine(env,x->a,0);env_join(env,brk_env[L]);
        an_loops--;free(brk_env[L]);free(cont_env[L]);
        free(entry);free(head);free(body);free(nh);break;}
    }
}
static void fn_env(VR *env,int f){ /* entry state of function f */
    for(int v=0;v<env_n;v++){env[v].r=BOT;env[v].lt=0;}env[env_n].r.lo=0;
    if(f==mainfn)env[LV(0)].r=RG(1,INT32_MAX);
    for(int i=0;i<fns[f].np;i++){
        int v=fns[f].pvar[i];
        if(fns[f].pw[i])env[LV(vars[v].lenv)].r=RG(0,(int64_t)1<<47);
        else env[LV(v)].r=FULL;
    }
}
static void analyze(void){
    /* alias classes: a view shares its source's base pointer */
    for(int v=0;v<nv;v++){arr_leader[v]=v;vars[v].aid=-1;}
    int na=0;
    for(int v=0;v<nv;v++)if(vars[v].arr){
        for(int u=0;u<v;u++)if(vars[u].arr&&vars[u].basev==vars[v].basev){arr_leader[v]=arr_leader[u];break;}
        if(na<64)vars[v].aid=na++;
        if(vars[v].lenv>=0)vars[vars[v].lenv].lenof=v+1;
    }
    nthr=0;add_thr(0);
    /* thresholds: constants used in comparisons (loop/branch guards) */
    for(int i=0;i<nn;i++)if(nd[i].k==N_BIN&&is_cmp_op(nd[i].op)){
        if(is_const(nd[i].a))add_thr(I(nd[nd[i].a].v));
        if(is_const(nd[i].b))add_thr(I(nd[nd[i].b].v));
    }
    for(int v=0;v<nv;v++)if(vars[v].arr&&vars[v].lenv<0)add_thr(vars[v].alen);
    for(int v=0;v<nv;v++)arr_rg[v]=BOT;
    for(int v=0;v<nv;v++)if(vars[v].arr){
        int L=arr_leader[v];
        if(vars[v].ro)arr_rg[L]=FULL;                    /* file data: anything */
        else if(vars[v].glob)arr_rg[L]=type_rg(vars[v].et); /* static: any function may write it */
        else if(L!=v||vars[v].et!=vars[L].et)arr_rg[L]=FULL; /* writable alias of a different type */
        else if(arr_rg[L].bot)arr_rg[L]=RG(0,0);         /* zero-initialized */
    }
    /* arrays reachable through parameters, or passed to mut parameters: unknown contents */
    for(int f=0;f<nfn;f++)for(int i=0;i<fns[f].np;i++)if(fns[f].pw[i])arr_rg[arr_leader[fns[f].pvar[i]]]=type_rg(fns[f].pty[i]);
    for(int e=0;e<nn;e++)if(nd[e].k==N_CALL&&nd[e].var>=0){int i=0;
        for(int x=nd[e].a;x>=0;x=nd[x].next,i++)if(nd[x].k==N_ARR&&fns[nd[e].var].pmut[i])
            arr_rg[arr_leader[nd[x].var]]=rjoin(arr_rg[arr_leader[nd[x].var]],type_rg(vars[nd[x].var].et));}
    for(int v=0;v<MAX_VARS;v++)lmap[v]=-1;
    nlvars=0;lmap_fn=-2;
    for(int round=0;;round++){
        an_changed=0;memset(arr_chg,0,sizeof(int)*(size_t)nv);
        for(int f=0;f<nfn;f++)if(fns[f].used){lmap_for(f);an_fn=f;VR *env=env_new();fn_env(env,f);as_stmt(fns[f].body,env);free(env);wcache_free();}
        if(!an_changed)break;
        if(round>=8)for(int v=0;v<nv;v++)if(arr_chg[v]&&vars[v].arr&&arr_leader[v]==v)arr_rg[v]=rjoin(arr_rg[v],type_rg(vars[v].et));
        if(round>32)fail("internal: array range analysis did not converge");
    }
    an_annot=1;
    for(int f=0;f<nfn;f++)if(fns[f].used){lmap_for(f);an_fn=f;VR *env=env_new();fn_env(env,f);as_stmt(fns[f].body,env);free(env);wcache_free();}
    if(getenv("LING0_DEBUG"))for(int i=0;i<nn;i++)if((nd[i].k==N_LOAD||nd[i].k==S_STORE)&&nd[i].chk&&nd[i].dhi!=-1)
        fprintf(stderr,"check kept: %s %s[idx in %lld..%lld] content %lld..%lld\n",nd[i].k==N_LOAD?"load":"store",vars[nd[i].var].name,
            (long long)nd[i].dlo,(long long)nd[i].dhi,(long long)arr_rg[arr_leader[nd[i].var]].lo,(long long)arr_rg[arr_leader[nd[i].var]].hi);
}
/* ------------------------------------------------------------------ parser */
static int depth,loopdepth,inpar,par_outer_nv;
static int loopmark[MAX_DEPTH+1];   /* per open loop: arena-mark variable (-1: no scoped allocation inside) */
static int use_arena;
static void enter(void){if(++depth>MAX_DEPTH)fail("nesting too deep");}
static int gvis[MAX_VARS],ngvis;   /* top-level `let`s: visible in every function */
static int find_var(const char *name){
    for(int j=nvis-1;j>=0;j--)if(!strcmp(vars[vis[j]].name,name))return vis[j];
    for(int j=0;j<ngvis;j++)if(!strcmp(vars[gvis[j]].name,name))return gvis[j];
    return -1;
}
static int lookup(const char *name){
    int v=find_var(name);if(v<0)failf("unknown variable `%s`",name);
    return v;
}
static int peek_kind(void){ /* kind of the token after the current one */
    const char *sp=pos,*ts=tstart;Token st=tok;size_t sd=sdlen;next();int k=tok.kind;pos=sp;tok=st;sdlen=sd;tstart=ts;return k;
}
static int mk_load(int a,int idx);
static int var_ref(int v){
    while(vars[v].alias)v=vars[v].alias-1;   /* immutable copy: refer to the source */
    if(vars[v].garr){int e=mk_load(vars[v].garr,mkconst(0));nd[e].ty=vars[v].ty;return e;}   /* global scalar */
    if(vars[v].arr)fail("array used as a scalar (index it, or use len())");
    if(vars[v].isconst)return mkconst_t(vars[v].cval,vars[v].ty);
    vars[v].reads++;int e=mk(N_VAR);nd[e].var=v;nd[e].ty=vars[v].ty;return e;
}
static int mk_var(int v){vars[v].reads++;int e=mk(N_VAR);nd[e].var=v;nd[e].ty=vars[v].ty;return e;}

/* ------------------------------------------------------------ type rules
 * Literals are untyped until context fixes them (must fit, else an error);
 * alone they default to i64 / f64. Implicit conversions are only lossless
 * integer widenings (free: canonical registers). Integer arithmetic runs in
 * 64 bits: narrow operands promote to i64, or to u64 next to a u64; mixing
 * u64 with a signed type is an error. Floats never mix with ints or each
 * other implicitly. Everything else needs `as`. */
static int lit_fits(int64_t v,int t){
    switch(t){
    case TY_I8:return v>=-128&&v<=127; case TY_I16:return v>=-32768&&v<=32767;
    case TY_I32:return v>=INT32_MIN&&v<=INT32_MAX; case TY_I64:return 1;
    case TY_U8:return v>=0&&v<=255; case TY_U16:return v>=0&&v<=65535;
    case TY_U32:return v>=0&&v<=UINT32_MAX; case TY_U64:return v>=0;
    }
    return 0;
}
static int widens(int s,int t){
    if(s==t)return 1;
    if(ty_sint(s))return ty_sint(t)&&ty_width(t)>=ty_width(s);
    if(ty_uint(s))return (ty_uint(t)&&ty_width(t)>=ty_width(s))||(ty_sint(t)&&ty_width(t)>ty_width(s));
    return 0;
}
static int conv(int e,int t){
    int s=nd[e].ty;errnode=e;
    if(s==t)return e;
    if(s==TY_UNIT)fail("this function returns no value");
    if(s==TY_ILIT){   /* always a constant */
        int64_t v=I(nd[e].v);
        if(ty_int(t)){if(!lit_fits(v,t))failf("integer literal %lld out of range for %s",(long long)v,tyname[t]);nd[e].ty=t;return e;}
        if(ty_flt(t)){
            double d=t==TY_F32?(double)(float)v:(double)v;
            if(d>=9223372036854775808.0||(int64_t)d!=v)failf("integer literal %lld not exactly representable as %s",(long long)v,tyname[t]);
            nd[e].v=t==TY_F32?SB((float)d):DB(d);
            nd[e].ty=t;return e;
        }
    }
    if(s==TY_FLIT&&ty_flt(t)){if(t==TY_F32)nd[e].v=SB((float)D(nd[e].v));nd[e].ty=t;return e;}
    if(ty_int(s)&&ty_int(t)&&widens(s,t)){nd[e].ty=t;errnode=-1;return e;}   /* same bits */
    failf("type mismatch: expected %s, found %s",tyname[t],tyname[s]);return -1;
}
static int deflt(int e){ /* fix an untyped literal to its default type */
    if(nd[e].ty==TY_ILIT)return conv(e,TY_I64);
    if(nd[e].ty==TY_FLIT)return conv(e,TY_F64);
    if(nd[e].ty==TY_UNIT)fail("this function returns no value");
    return e;
}
static int need_bool(int e){errnode=e;if(nd[e].ty!=TY_BOOL)failf("condition must be bool, found %s",tyname[nd[e].ty]);return e;}
static int need_int(int e){e=deflt(e);errnode=e;if(!ty_int(nd[e].ty))failf("expected an integer, found %s",tyname[nd[e].ty]);errnode=-1;return e;}
static int promote(int t){return t==TY_U64?TY_U64:TY_I64;}
/* binary operator on typed operands: converts both operands and returns the typed opcode */
static int type_bin(int op,int *a,int *b){
    int ta=nd[*a].ty,tb=nd[*b].ty;errnode=*a;
    if(ta==TY_UNIT||tb==TY_UNIT)fail("this function returns no value");
    if(op==O_LAND||op==O_LOR){need_bool(*a);need_bool(*b);return op;}
    int fa=ty_flt(ta)||ta==TY_FLIT,fb=ty_flt(tb)||tb==TY_FLIT;
    if(fa||fb){
        if((!fa&&!ty_num(ta))||(!fb&&!ty_num(tb)))failf("operator needs numbers, found %s and %s",tyname[ta],tyname[tb]);
        int t=ty_flt(ta)?ta:ty_flt(tb)?tb:TY_FLIT;
        if(t==TY_FLIT&&((ta!=TY_ILIT&&ta!=TY_FLIT)||(tb!=TY_ILIT&&tb!=TY_FLIT)))
            failf("type mismatch: %s and %s",tyname[ta],tyname[tb]);
        if(t==TY_FLIT){ /* both untyped: fold in f64, stay untyped */
            if(ta==TY_ILIT){nd[*a].v=DB((double)I(nd[*a].v));nd[*a].ty=TY_FLIT;}
            if(tb==TY_ILIT){nd[*b].v=DB((double)I(nd[*b].v));nd[*b].ty=TY_FLIT;}
        }else{*a=conv(*a,t);*b=conv(*b,t);}
        int base;
        switch(op){case O_ADD:base=O_FADD;break;case O_SUB:base=O_FSUB;break;case O_MUL:base=O_FMUL;break;case O_DIV:base=O_FDIV;break;
        case O_EQ:base=O_FEQ;break;case O_NE:base=O_FNE;break;case O_LT:base=O_FLT;break;case O_LE:base=O_FLE;break;
        case O_GT:base=O_FGT;break;case O_GE:base=O_FGE;break;default:fail("operator not defined for floats");return -1;}
        int r=t==TY_F32?base+(O_GADD-O_FADD):base;
        if(t==TY_FLIT){nd[*a].ty=nd[*b].ty=TY_F64;}   /* fold as f64; result re-marked untyped below */
        return r;
    }
    if(ta==TY_BOOL||tb==TY_BOOL){
        if(ta!=tb)failf("type mismatch: %s and %s",tyname[ta],tyname[tb]);
        if(op!=O_EQ&&op!=O_NE&&op!=O_AND&&op!=O_OR&&op!=O_XOR)fail("operator not defined for bool");
        return op;
    }
    if(!ty_int(ta)||!ty_int(tb))failf("operator needs numbers, found %s and %s",tyname[ta],tyname[tb]);
    if(op==O_SHL||op==O_SHR||op==O_SAR){ /* result has the (promoted) left type; any integer count */
        if(ta!=TY_ILIT)*a=conv(*a,promote(ta));
        else if(tb!=TY_ILIT)*a=conv(*a,TY_I64);
        if(tb==TY_ILIT&&ta!=TY_ILIT)*b=conv(*b,TY_I64);
        if(op==O_SAR&&nd[*a].ty==TY_U64)op=O_SHR;   /* >> on u64 is logical */
        return op;
    }
    int t;
    if(ta==TY_ILIT&&tb==TY_ILIT)t=TY_ILIT;
    else if(ta==TY_ILIT)t=promote(tb);
    else if(tb==TY_ILIT)t=promote(ta);
    else{
        int pa=promote(ta),pb=promote(tb);
        if(pa==pb)t=pa;
        else if((pa==TY_U64&&ty_uint(tb))||(pb==TY_U64&&ty_uint(ta)))t=TY_U64;
        else{failf("mixed signed and unsigned operands (%s, %s): convert one with `as`",tyname[ta],tyname[tb]);return -1;}
    }
    if(t!=TY_ILIT){*a=conv(*a,t);*b=conv(*b,t);}
    if(t==TY_U64)switch(op){case O_DIV:return O_DIVU;case O_MOD:return O_MODU;case O_LT:return O_LTU;
        case O_LE:return O_LEU;case O_GT:return O_GTU;case O_GE:return O_GEU;}
    return op;
}
static int typed_bin(int op,int a,int b){
    int src=nd[a].src;
    int flit=(nd[a].ty==TY_FLIT||nd[a].ty==TY_ILIT)&&(nd[b].ty==TY_FLIT||nd[b].ty==TY_ILIT)&&(nd[a].ty==TY_FLIT||nd[b].ty==TY_FLIT);
    int o=type_bin(op,&a,&b);
    int e=mk_bin(o,a,b);
    if(flit&&nd[e].ty==TY_F64)nd[e].ty=TY_FLIT;   /* untyped float constant expression */
    nd[e].src=src;errnode=-1;return e;
}
static int typed_un(int op,int a){
    int t=nd[a].ty;errnode=a;
    if(t==TY_UNIT)fail("this function returns no value");
    if(op==U_LNOT){need_bool(a);return mk_un(U_LNOT,a,TY_BOOL);}
    if(op==U_NEG&&(ty_flt(t)||t==TY_FLIT)){
        if(t==TY_F32)return mk_un(U_GNEG,a,t);
        return mk_un(U_FNEG,a,t);   /* f64 and untyped float literals */
    }
    if(!ty_int(t))failf("operator needs an integer, found %s",tyname[t]);
    if(t==TY_ILIT)return mk_un(op,a,TY_ILIT);
    if(op==U_NEG&&t==TY_U64)fail("cannot negate an unsigned value (use 0 - x)");
    a=conv(a,promote(t));
    return mk_un(op,a,promote(t));
}
/* e as t: explicit numeric conversion (truncating/wrapping between integers,
 * saturating float -> int with NaN -> 0, round-to-nearest int -> float) */
static int typed_cast(int e,int t){
    int s=nd[e].ty;errnode=e;
    if(s==TY_UNIT)fail("this function returns no value");
    if(t==TY_BOOL)fail("cannot cast to bool (compare with 0 instead)");
    if(s==TY_ILIT)e=conv(e,TY_I64),s=TY_I64;
    if(s==TY_FLIT)e=conv(e,TY_F64),s=TY_F64;
    if(s==t)return e;
    if(s==TY_BOOL){if(!ty_int(t))fail("bool converts only to integer types");nd[e].ty=t;return e;}
    if(ty_int(s)&&ty_int(t)){
        if(t==TY_I64||t==TY_U64||widens(s,t)){nd[e].ty=t;return e;}  /* canonical bits already right */
        static const int op_of[NTY]={0,U_SX8,U_SX16,U_SX32,0,U_ZX8,U_ZX16,U_ZX32};
        return mk_un(op_of[t],e,t);
    }
    if(ty_int(s)&&ty_flt(t))return mk_un(s==TY_U64?(t==TY_F64?U_U2D:U_U2S):(t==TY_F64?U_I2D:U_I2S),e,t);
    if(ty_flt(s)&&ty_flt(t))return mk_un(t==TY_F64?U_S2D:U_D2S,e,t);
    if(ty_flt(s)&&ty_int(t)){
        if(t==TY_U64)return mk_un(s==TY_F64?U_D2U:U_S2U,e,t);
        int r=mk_un(s==TY_F64?U_D2I:U_S2I,e,TY_I64);
        if(t==TY_I64)return r;
        static const int sat_of[NTY]={0,U_SATS8,U_SATS16,U_SATS32,0,U_SATU8,U_SATU16,U_SATU32};
        return mk_un(sat_of[t],r,t);
    }
    failf("cannot cast %s to %s",tyname[s],tyname[t]);return -1;
}
static int parse_type_s(int allow_struct){
    if(tok.kind!=T_ID)fail("expected a type");
    for(int t=TY_I8;t<=TY_F64;t++)if(!strcmp(tok.name,tyname[t])){next();return t;}
    for(int i=0;i<nst;i++)if(!strcmp(tok.name,sts[i].name)){
        if(!allow_struct)failf("struct `%s` can only be an array element type",tok.name);
        next();return TY_STRUCT0+i;}
    failf("unknown type `%s`",tok.name);return -1;
}
static int parse_type(void){return parse_type_s(0);}
static int lookup_arr(const char *name){
    int v=lookup(name);if(!vars[v].arr)fail("not an array");return v;
}
static int mk_load(int a,int idx){
    vars[vars[a].basev].reads++;if(vars[a].lenv>=0)vars[vars[a].lenv].reads++;
    int e=mk(N_LOAD);nd[e].var=a;nd[e].a=idx;nd[e].chk=1;nd[e].ty=vars[a].et;return e;
}
static int clone_expr(int e){
    if(e<0)return -1;
    Node c=nd[e];int r=mk(c.k);nd[r]=c;nd[r].c=-1;
    if(c.k==N_VAR)vars[c.var].reads++;
    if(c.k==N_LOAD||c.k==N_ARR){vars[vars[c.var].basev].reads++;if(vars[c.var].lenv>=0)vars[vars[c.var].lenv].reads++;}
    nd[r].a=clone_expr(c.a);nd[r].b=clone_expr(c.b);
    if(c.k!=N_CALL){nd[r].next=-1;}
    else{ /* clone the argument chain */
        int prev=-1;nd[r].a=-1;
        for(int x=c.a;x>=0;x=nd[x].next){int y=clone_expr(x);nd[y].next=-1;if(prev<0)nd[r].a=y;else nd[prev].next=y;prev=y;}
    }
    return r;
}
static int in_prelude,nfn_decl,parsing;
static int hidden(const char *name);
static int str_array(int v,size_t soff,size_t slen);
static int find_fn(const char *name){for(int i=0;i<nfn_decl;i++)if(!strcmp(fns[i].name,name))return i;return -1;}
static int parse_expr(void);
/* calls are typed while parsing: every signature was collected by prescan() */
static int parse_call(const char *name){ /* current token is '(' */
    if(!strncmp(name,"__",2)&&!in_prelude)fail("names starting with __ are reserved");
    int f=find_fn(name);
    if(f<0){failf("call to undefined function `%s`",name);}
    if(f==mainfn)fail("main cannot be called");
    expect('(');
    int e=mk(N_CALL);nd[e].var=f;nd[e].ty=fns[f].rett;
    int prev=-1,i=0;
    while(tok.kind!=')'){
        if(i>=fns[f].np)fail("too many arguments");
        int arg;
        if(fns[f].pw[i]&&tok.kind==T_STR){ /* "literal" for a [u8] parameter */
            if(fns[f].pty[i]!=TY_U8||fns[f].pmut[i])fail("a string literal is a read-only [u8]");
            size_t so=tok.soff,sl=tok.slen;next();
            int a=str_array(hidden("#strarg"),so,sl);
            vars[vars[a].basev].reads++;
            arg=mk(N_ARR);nd[arg].var=a;nd[arg].ty=TY_NONE;
        }else if(fns[f].pw[i]){
            if(tok.kind!=T_ID||find_var(tok.name)<0||!vars[find_var(tok.name)].arr)fail("array parameter needs an array argument");
            int a=find_var(tok.name);next();
            if(vars[a].et!=fns[f].pty[i])failf("array element type mismatch: expected [%s], found [%s]",type_name(fns[f].pty[i]),type_name(vars[a].et));
            if(fns[f].pmut[i]&&vars[a].ro)fail("read-only array passed to a mut parameter");
            vars[vars[a].basev].reads++;if(vars[a].lenv>=0)vars[vars[a].lenv].reads++;
            arg=mk(N_ARR);nd[arg].var=a;nd[arg].ty=TY_NONE;
        }else{
            if(tok.kind==T_ID&&find_var(tok.name)>=0&&vars[find_var(tok.name)].arr&&(peek_kind()==','||peek_kind()==')'))
                fail("array passed where a scalar is expected");
            arg=conv(parse_expr(),fns[f].pty[i]);
        }
        nd[arg].next=-1;
        if(prev<0)nd[e].a=arg;else nd[prev].next=arg;
        prev=arg;i++;
        if(tok.kind!=',')break;
        next();
    }
    expect(')');
    if(i!=fns[f].np)fail("too few arguments");
    return e;
}
static int str_array(int v,size_t soff,size_t slen){ /* v: a read-only [u8] in the image */
    Var *a=&vars[v];a->arr=1;a->et=TY_U8;a->ty=TY_NONE;a->ro=1;a->alen=(int64_t)slen;
    int b=hidden("#sbase");vars[b].isconst=1;vars[b].cval=(uint64_t)soff;vars[b].glob=2;vars[b].owner=-1;
    a->basev=b;return v;
}
static int parse_field(int st){ /* .name after a struct element */
    Struct *S=&sts[st-TY_STRUCT0];
    if(tok.kind!='.')failf("`%s` is a struct: access a field (a[i].field)",S->name);
    next();if(tok.kind!=T_ID)fail("expected a field name");
    for(int f=0;f<S->nf;f++)if(!strcmp(S->fname[f],tok.name)){next();return f;}
    failf("struct `%s` has no field `%s`",S->name,tok.name);return -1;
}
static int mk_call1(const char *name,int arg){ /* runtime-library call (prelude function) */
    int f=find_fn(name);if(f<0)fail("internal: missing prelude function");
    int e=mk(N_CALL);nd[e].var=f;nd[e].ty=fns[f].rett;nd[e].a=arg;nd[arg].next=-1;return e;
}
static int retag(int e,int t){nd[e].ty=t;return e;}   /* reinterpretation: same bits */
static int builtin_arg(void){expect('(');int e=parse_expr();expect(')');return e;}
static int atom(void){
    if(tok.kind==T_NUM){uint64_t v=tok.value;int big=tok.big;next();return mkconst_t(v,big?TY_U64:TY_ILIT);}
    if(tok.kind==T_FNUM){double d=tok.fval;next();return mkconst_t(DB(d),TY_FLIT);}
    if(tok.kind==T_TRUE||tok.kind==T_FALSE){int v=tok.kind==T_TRUE;next();return mkconst_t((uint64_t)v,TY_BOOL);}
    if(tok.kind=='('){next();int e=parse_expr();expect(')');return e;}
    if(tok.kind==T_ID){
        char name[64];memcpy(name,tok.name,sizeof name);const char *ids=tstart;next();
        if(find_var(name)<0&&tok.kind!='('){tstart=ids;failf("unknown variable `%s`",name);}
        if(tok.kind=='('&&find_var(name)<0){
            if(!strcmp(name,"argc")){if(curfn!=mainfn)fail("argc() is only available in main");next();expect(')');return var_ref(0);}
            if(!strcmp(name,"ncpu")){next();expect(')');return mk(N_NCPU);}
            if(!strcmp(name,"len")){
                next();if(tok.kind!=T_ID)fail("len() expects an array");
                int a=lookup_arr(tok.name);next();expect(')');
                return vars[a].lenv<0?mkconst_t(U(vars[a].alen),TY_I64):var_ref(vars[a].lenv);
            }
            if(!strcmp(name,"bits")){   /* float -> its IEEE bit pattern */
                int e=builtin_arg();if(nd[e].ty==TY_FLIT)e=conv(e,TY_F64);
                if(nd[e].ty==TY_F64)return retag(e,TY_U64);
                if(nd[e].ty==TY_F32)return retag(e,TY_U32);
                fail("bits() expects a float");
            }
            if(!strcmp(name,"f64_from_bits"))return retag(conv(builtin_arg(),TY_U64),TY_F64);
            if(!strcmp(name,"f32_from_bits"))return retag(conv(builtin_arg(),TY_U32),TY_F32);
            if(!strcmp(name,"sqrt")){
                int e=builtin_arg();if(nd[e].ty==TY_FLIT)e=conv(e,TY_F64);
                if(nd[e].ty==TY_F64)return mk_un(U_SQRTD,e,TY_F64);
                if(nd[e].ty==TY_F32)return mk_un(U_SQRTS,e,TY_F32);
                fail("sqrt() expects a float");
            }
            return parse_call(name);
        }
        if(tok.kind=='['){
            int a=lookup_arr(name);next();int idx=need_int(parse_expr());expect(']');
            int e=mk_load(a,idx);
            if(is_struct(vars[a].et)){int f=parse_field(vars[a].et);nd[e].op=f+1;nd[e].ty=sts[vars[a].et-TY_STRUCT0].fty[f];}
            return e;
        }
        return var_ref(lookup(name));
    }
    fail("expected expression");return -1;
}
static int unary(void){
    enter();int r;const char *st=tstart;
    if(tok.kind=='-'){next();r=typed_un(U_NEG,unary());}
    else if(tok.kind=='~'){next();r=typed_un(U_NOT,unary());}
    else if(tok.kind=='!'){next();r=typed_un(U_LNOT,unary());}
    else if(tok.kind=='+'){next();r=unary();if(!ty_num(nd[r].ty))fail("unary + needs a number");}
    else r=atom();
    nd[r].src=(int)(st-source);errnode=-1;
    depth--;return r;
}
static int cast_level(void){ /* `as` binds tighter than binary operators, looser than prefix ones */
    int r=unary(),src=nd[r].src;
    while(tok.kind==T_AS){next();int t=parse_type();r=typed_cast(r,t);nd[r].src=src;errnode=-1;}
    return r;
}
static int binlevel(int *op){
    switch(tok.kind){
        case T_LOR:*op=O_LOR;return 1; case T_LAND:*op=O_LAND;return 2;
        case T_EQ:*op=O_EQ;return 3; case T_NE:*op=O_NE;return 3;
        case '<':*op=O_LT;return 3; case T_LE:*op=O_LE;return 3;
        case '>':*op=O_GT;return 3; case T_GE:*op=O_GE;return 3;
        case '|':*op=O_OR;return 4; case '^':*op=O_XOR;return 5; case '&':*op=O_AND;return 6;
        case T_SHL:*op=O_SHL;return 7; case T_SHR:*op=O_SAR;return 7; case T_SHRU:*op=O_SHR;return 7;
        case '+':*op=O_ADD;return 8; case '-':*op=O_SUB;return 8;
        case '*':*op=O_MUL;return 9; case '/':*op=O_DIV;return 9; case '%':*op=O_MOD;return 9;
    }
    return 0;
}
static int parse_bin(int min){
    int a=cast_level();
    for(;;){
        int op,l=binlevel(&op);
        if(!l||l<min)break;
        next();a=typed_bin(op,a,parse_bin(l+1));
        int o2;if(l==3&&binlevel(&o2)==3)fail("comparison operators cannot be chained");
    }
    return a;
}
static int parse_expr(void){return parse_bin(1);}
static const char *reserved[]={"argc","len","print","putc","write","save","exit","alloc8","alloc16","alloc32","alloc64",
    "shared8","shared16","shared32","shared64","ncpu","alloc","shared","view","bits","f64_from_bits","f32_from_bits","sqrt",
    "file","view16","view32","view64","i8","i16","i32","i64","u8","u16","u32","u64","bool","f32","f64","fn","main"};
static int hidden(const char *name){
    if(nv>=MAX_VARS)fail("too many variables");
    Var *v=&vars[nv];memset(v,0,sizeof *v);strcpy(v->name,name);v->reg=-1;v->slot=-1;v->lenv=-1;v->ty=TY_I64;
    v->owner=parsing?curfn:-1;
    return nv++;
}
static int declare(const char *name,int mut){
    for(size_t k=0;k<sizeof reserved/sizeof reserved[0];k++)if(!strcmp(name,reserved[k]))fail("reserved name");
    if(!strncmp(name,"__",2)&&!in_prelude)fail("names starting with __ are reserved");
    for(int j=0;j<nvis;j++)if(!strcmp(vars[vis[j]].name,name))fail("variable already declared (shadowing not allowed)");
    if(nv>=MAX_VARS)fail("too many variables");
    Var *v=&vars[nv];memset(v,0,sizeof *v);
    memcpy(v->name,name,sizeof v->name);v->mut=mut;v->reg=-1;v->slot=-1;v->lenv=-1;v->ty=TY_I64;v->owner=curfn;
    vis[nvis++]=nv;return nv++;
}
static int parse_block(void);
/* array constructors: alloc<T>(n), shared<T>(n), view<T>(bytes), file(k), and the
 * v0.6 spellings alloc8/16/32/64 (u8,i16,i32,i64), shared8.., view16/32/64 */
static int ctor_name(const char *s){
    static const char *c[]={"alloc","shared","view","file","alloc8","alloc16","alloc32","alloc64",
        "shared8","shared16","shared32","shared64","view16","view32","view64"};
    for(size_t k=0;k<sizeof c/sizeof c[0];k++)if(!strcmp(s,c[k]))return 1;
    return 0;
}
static int legacy_et(int bits){return bits==8?TY_U8:bits==16?TY_I16:bits==32?TY_I32:TY_I64;}
static int parse_stmt(void){
    enter();int s;
    switch(tok.kind){
    case T_LET:{
        next();int mut=0;if(tok.kind==T_MUT){mut=1;next();}
        if(tok.kind!=T_ID)fail("expected variable name");
        char name[64];memcpy(name,tok.name,sizeof name);next();
        int ann=TY_NONE,aarr=0;
        if(tok.kind==':'){next();if(tok.kind=='['){next();aarr=1;ann=parse_type_s(1);expect(']');}else ann=parse_type();}
        expect('=');
        if(tok.kind==T_STR){
            if(mut)fail("array bindings are immutable (their elements are not)");
            if(ann&&(!aarr||ann!=TY_U8))fail("a string literal is a [u8]");
            size_t so=tok.soff,sl=tok.slen;next();expect(';');
            int v=declare(name,0);Var *a=&vars[v];a->arr=1;a->et=TY_U8;a->ty=TY_NONE;a->ro=1;a->alen=(int64_t)sl;a->basev=hidden("#str");
            vars[a->basev].reads++;
            s=mk(S_ARR);nd[s].var=v;nd[s].op=A_STR;nd[s].v=so;nd[s].chk=1;
            break;
        }
        if(tok.kind==T_ID&&ctor_name(tok.name)&&find_var(tok.name)<0){
            char ctor[64];memcpy(ctor,tok.name,sizeof ctor);next();
            int kind,et,src=-1,arg=-1,shared=0;
            if(!strcmp(ctor,"alloc")||!strcmp(ctor,"shared")||!strcmp(ctor,"view")){
                expect('<');et=parse_type_s(1);expect('>');
                shared=ctor[0]=='s';kind=ctor[0]=='v'?A_VIEW:A_ALLOC;
            }else if(!strcmp(ctor,"file")){kind=A_FILE;et=TY_U8;}
            else if(!strncmp(ctor,"alloc",5)){kind=A_ALLOC;et=legacy_et(atoi(ctor+5));}
            else if(!strncmp(ctor,"shared",6)){kind=A_ALLOC;shared=1;et=legacy_et(atoi(ctor+6));}
            else{kind=A_VIEW;et=legacy_et(atoi(ctor+4));}
            int w=ty_width(et);
            if(kind==A_VIEW&&et==TY_BOOL)fail("no bool views (a byte is not always a valid bool)");
            if(ann&&(!aarr||ann!=et))fail("array type annotation does not match the constructor");
            if(inpar&&kind!=A_VIEW)fail("no allocation or file mapping inside a par block");
            if(mut)fail("array bindings are immutable (their elements are not)");
            /* Scoped heap: alloc outside main's top level comes from an arena and is
             * released at the end of each iteration of the innermost loop and when the
             * function returns. Arrays can't escape their scope (no array returns or
             * reassignment), so this never leaves a dangling reference. */
            int scoped=kind==A_ALLOC&&(curfn!=mainfn||loopdepth>0);
            if(kind==A_FILE&&(loopdepth||curfn!=mainfn))fail("file() is only available at main's top level");
            if(scoped&&shared)fail("shared arrays are allocated at main's top level");
            if(scoped){
                use_arena=1;
                if(loopdepth&&loopmark[loopdepth]<0)loopmark[loopdepth]=hidden("#loopmark");
                if(curfn!=mainfn&&fns[curfn].mark<0)fns[curfn].mark=hidden("#fnmark");
            }
            expect('(');
            if(kind==A_VIEW){if(tok.kind!=T_ID)fail("view expects an array");src=lookup_arr(tok.name);
                if(vars[src].arr!=1)fail("view source must be a byte array");
                next();}
            else arg=conv(parse_expr(),TY_I64);
            expect(')');expect(';');
            int v=declare(name,0);Var *a=&vars[v];a->arr=w;a->et=et;a->ty=TY_NONE;a->shared=shared;
            if(kind==A_VIEW){a->shared=vars[src].shared;
                a->basev=vars[src].basev;a->ro=vars[src].ro;
                if(vars[src].lenv<0){a->alen=vars[src].alen/w;}else{a->lenv=hidden("#len");vars[vars[src].lenv].reads++;}
            }else{
                a->basev=hidden("#base");a->ro=kind==A_FILE;
                if(kind==A_FILE){if(curfn!=mainfn)fail("file() is only available in main");vars[0].reads++;vars[1].reads++;a->lenv=hidden("#len");}
                else if(is_const(arg)){
                    int64_t n=I(nd[arg].v);if(n<1||n>INT32_MAX)fail("array length must be 1..2^31-1");
                    a->alen=n;
                }else a->lenv=hidden("#len");
            }
            vars[a->basev].reads++;
            s=mk(S_ARR);nd[s].var=v;nd[s].a=arg;nd[s].op=kind;nd[s].c=src;nd[s].chk=w;nd[s].v=(uint64_t)scoped;
            break;
        }
        if(aarr)fail("array type annotation needs an array constructor");
        int e=parse_expr();expect(';');
        if(ann)e=conv(e,ann);
        else if(mut)e=deflt(e);
        else if(nd[e].ty==TY_UNIT)fail("this function returns no value");
        int v=declare(name,mut);vars[v].ty=nd[e].ty;
        if(!mut&&is_const(e)){vars[v].isconst=1;vars[v].cval=nd[e].v;s=mk(S_BLOCK);}   /* literal: stays untyped */
        else if(!mut&&nd[e].k==N_VAR&&!vars[nd[e].var].mut&&nd[e].ty==vars[nd[e].var].ty){
            /* let x = y with both immutable: alias, no copy. Drop the init read. */
            vars[v].alias=nd[e].var+1;vars[nd[e].var].reads--;s=mk(S_BLOCK);}
        else{s=mk(S_LET);nd[s].var=v;nd[s].a=e;}
        break;}
    case T_IF:{
        next();int c=need_bool(parse_expr());int t=parse_block();int el=-1;
        if(tok.kind==T_ELSE){next();el=tok.kind==T_IF?parse_stmt():parse_block();}
        s=mk(S_IF);nd[s].a=c;nd[s].b=t;nd[s].c=el;break;}
    case T_WHILE:{
        next();int c=need_bool(parse_expr());loopdepth++;loopmark[loopdepth]=-1;int b=parse_block();
        int m=loopmark[loopdepth];loopdepth--;
        s=mk(S_WHILE);nd[s].a=c;nd[s].b=b;nd[s].c=m;   /* c: arena mark, reset every iteration */
        if(m>=0)vars[m].reads+=3;
        break;}
    case T_RETURN:{
        if(inpar)fail("return inside a par block");
        next();int e;
        if(fns[curfn].rett==TY_UNIT){if(tok.kind!=';')fail("this function returns no value: use `return;`");e=mkconst(0);}
        else e=conv(parse_expr(),fns[curfn].rett);
        expect(';');s=mk(S_RET);nd[s].a=e;break;}
    case T_PAR:{
        /* par k in a..b { body }: b-a workers (forked processes), k = a..b-1.
         * Workers see a snapshot; only shared arrays carry results back. */
        if(curfn!=mainfn)fail("par is only available in main");
        if(inpar)fail("nested par blocks are not allowed");
        next();if(tok.kind!=T_ID)fail("expected worker variable");
        char name[64];memcpy(name,tok.name,64);next();expect(T_IN);
        int a=conv(parse_expr(),TY_I64);expect(T_DOTDOT);int b=conv(parse_expr(),TY_I64);
        int pend=hidden("#pend");vars[pend].reads+=2;
        int mark=nvis;int k=declare(name,0);vars[k].reads+=2;
        int sv_loop=loopdepth;loopdepth=0;inpar=1;par_outer_nv=k;
        int body=parse_block();
        inpar=0;loopdepth=sv_loop;nvis=mark;
        s=mk(S_PAR);nd[s].var=k;nd[s].a=a;nd[s].b=b;nd[s].c=body;nd[s].op=pend;
        break;}
    case T_BREAK:case T_CONTINUE:{
        int k=tok.kind==T_BREAK?S_BRK:S_CONT;
        if(!loopdepth)fail("break/continue outside loop");
        next();expect(';');s=mk(k);break;}
    case '{':s=parse_block();break;
    case T_ID:{
        int isvar=find_var(tok.name)>=0;
        if(!isvar&&inpar&&(!strcmp(tok.name,"print")||!strcmp(tok.name,"putc")||!strcmp(tok.name,"write")))
            fail("no output inside a par block (write results to a shared array; print after it)");
        if(!isvar&&!strcmp(tok.name,"print")){ /* ints: decimal (u64 unsigned); bool: true/false; floats: 6 decimals */
            next();expect('(');int e=deflt(parse_expr());expect(')');expect(';');
            int t=nd[e].ty;
            if(ty_int(t)){s=mk(S_PRINT);nd[s].a=e;nd[s].op=t==TY_U64;}
            else if(t==TY_BOOL){s=mk(S_EXPR);nd[s].a=mk_call1("__print_bool",e);}
            else if(ty_flt(t)){s=mk(S_EXPR);nd[s].a=mk_call1("__print_f64",t==TY_F32?typed_cast(e,TY_F64):e);}
            else{fail("print() expects a number or bool");return -1;}
            break;
        }
        if(!isvar&&!strcmp(tok.name,"putc")){
            next();expect('(');int e=need_int(parse_expr());expect(')');expect(';');
            s=mk(S_PUTC);nd[s].a=e;break;
        }
        if(!isvar&&!strcmp(tok.name,"exit")){ /* exit(code): flush output, end the process with status code & 255 */
            if(inpar)fail("no exit inside a par block");
            next();expect('(');int e=conv(parse_expr(),TY_I64);expect(')');expect(';');
            s=mk(S_PUTC);nd[s].a=e;nd[s].op=1;break;   /* S_PUTC with op=1: exit */
        }
        if(!isvar&&!strcmp(tok.name,"save")){ /* save(k, a, n): first n bytes of a -> file argv[k] (created, 0755) */
            if(curfn!=mainfn)fail("save() is only available in main");
            if(inpar)fail("no output inside a par block");
            next();expect('(');int k=conv(parse_expr(),TY_I64);expect(',');
            if(tok.kind!=T_ID)fail("save() expects a byte array");
            int a=lookup_arr(tok.name);if(vars[a].arr!=1||vars[a].et==TY_BOOL)fail("save() expects a byte array");next();expect(',');
            int nb=conv(parse_expr(),TY_I64);expect(')');expect(';');
            vars[vars[a].basev].reads++;if(vars[a].lenv>=0)vars[vars[a].lenv].reads++;vars[0].reads++;vars[1].reads++;
            s=mk(S_SAVE);nd[s].var=a;nd[s].a=k;nd[s].b=nb;nd[s].chk=1;break;
        }
        if(!isvar&&!strcmp(tok.name,"write")){ /* write(a) | write(a, off, n) | write("literal") */
            next();expect('(');s=mk(S_WRITE);nd[s].a=nd[s].b=-1;nd[s].chk=1;
            if(tok.kind==T_STR){nd[s].var=-1;nd[s].v=tok.soff;nd[s].c=(int)tok.slen;next();}
            else{
                if(tok.kind!=T_ID)fail("write() expects a byte array");
                int a=lookup_arr(tok.name);if(vars[a].arr!=1||vars[a].et==TY_BOOL)fail("write() expects a byte array");next();
                vars[vars[a].basev].reads++;if(vars[a].lenv>=0)vars[vars[a].lenv].reads++;
                nd[s].var=a;
                if(tok.kind==','){next();nd[s].a=conv(parse_expr(),TY_I64);expect(',');nd[s].b=conv(parse_expr(),TY_I64);}
            }
            expect(')');expect(';');break;
        }
        if(!isvar&&peek_kind()=='('){ /* call statement (the result, if any, is discarded) */
            char name[64];memcpy(name,tok.name,sizeof name);next();
            int e=parse_call(name);expect(';');s=mk(S_EXPR);nd[s].a=e;break;
        }
        int v=lookup(tok.name);next();
        int gidx=-1;   /* global scalar g: stored as g's 1-element array [0] */
        if(vars[v].garr){
            if(!vars[v].mut)fail("assignment to immutable variable");
            int t=vars[v].ty;v=vars[v].garr;gidx=mkconst(0);vars[v].et=t;
        }
        if(vars[v].arr){
            if(vars[v].ro)fail("store to read-only array");
            int et=vars[v].et,fld=-1;
            int idx;
            if(gidx>=0)idx=gidx;
            else{expect('[');idx=need_int(parse_expr());expect(']');}
            if(is_struct(et)){fld=parse_field(et);et=sts[et-TY_STRUCT0].fty[fld];}
            int op=-1,val;
            if(tok.kind=='='){next();val=conv(parse_expr(),et);}
            else if(tok.kind==T_OPEQ){
                op=tok.op;next();int r=parse_expr();
                if(ty_int(et)&&(op==O_ADD||op==O_SUB||op==O_AND||op==O_OR||op==O_XOR)){
                    /* integer ALU op at element width: wraps to the element type */
                    int probe=mkconst_t(0,et);type_bin(op,&probe,&r);val=r;
                }else{
                    /* a[i] op= e  ==>  { let #v = e; let #i = i; a[#i] = (a[#i] op #v) [wrapped]; }
                     * each operand evaluated exactly once, value first (store order) */
                    expect(';');
                    int ti=hidden("#opi");vars[ti].ty=nd[idx].ty;
                    int l2=mk(S_LET);nd[l2].var=ti;nd[l2].a=idx;
                    int head=l2,rv;
                    if(is_const(r))rv=r;   /* constants: no temporary (untyped literals stay adaptable) */
                    else{
                        int tv=hidden("#opv");r=deflt(r);vars[tv].ty=nd[r].ty;
                        int l1=mk(S_LET);nd[l1].var=tv;nd[l1].a=r;nd[l1].next=l2;head=l1;rv=mk_var(tv);
                    }
                    int st=mk(S_STORE);nd[st].var=v;nd[st].a=mk_var(ti);nd[st].op=-1;nd[st].chk=1;nd[st].c=fld;
                    int ld=mk_load(v,mk_var(ti));if(fld>=0){nd[ld].op=fld+1;nd[ld].ty=et;}else if(gidx>=0)nd[ld].ty=et;
                    int val2=typed_bin(op,ld,rv);
                    if(!ty_int(et)||!ty_int(nd[val2].ty))val2=conv(val2,et);   /* int results: the store truncates */
                    nd[st].b=val2;
                    vars[vars[v].basev].reads++;if(vars[v].lenv>=0)vars[vars[v].lenv].reads++;
                    nd[l2].next=st;
                    s=mk(S_BLOCK);nd[s].a=head;break;
                }
            }else{fail("expected assignment");return -1;}
            expect(';');
            vars[vars[v].basev].reads++;if(vars[v].lenv>=0)vars[vars[v].lenv].reads++;
            s=mk(S_STORE);nd[s].var=v;nd[s].a=idx;nd[s].b=val;nd[s].op=op;nd[s].chk=1;nd[s].c=fld;break;
        }
        if(!vars[v].mut)fail("assignment to immutable variable");
        if(inpar&&v<par_outer_nv)fail("a par block cannot assign variables declared outside it (use a shared array)");
        int e,t=vars[v].ty;
        if(tok.kind=='='){next();e=conv(parse_expr(),t);}
        else if(tok.kind==T_OPEQ){
            int op=tok.op;next();int r=parse_expr();e=typed_bin(op,var_ref(v),r);
            if(ty_int(t)&&ty_int(nd[e].ty)&&nd[e].ty!=t)e=typed_cast(e,t);   /* compound assignment wraps */
            else e=conv(e,t);
        }
        else{fail("expected assignment");return -1;}
        expect(';');s=mk(S_ASSIGN);nd[s].var=v;nd[s].a=e;break;}
    default:fail("expected statement");return -1;
    }
    depth--;return s;
}
static int parse_block(void){
    enter();expect('{');
    int mark=nvis,b=mk(S_BLOCK),last=-1;
    while(tok.kind!='}'){
        if(tok.kind==T_EOF)fail("unterminated block");
        int s=parse_stmt();
        if(last<0)nd[b].a=s;else nd[last].next=s;
        last=s;
    }
    next();nvis=mark;depth--;return b;
}
/* fn name(p: T, mut q: T, a: [T], b: mut [T]) [-> T]; decl=0: signature only (prescan) */
static void parse_header(int f,int decl){
    Func *F=&fns[f];
    expect(T_FN);
    if(tok.kind!=T_ID)fail("expected function name");
    if(!strncmp(tok.name,"__",2)&&!in_prelude)fail("names starting with __ are reserved");
    memcpy(F->name,tok.name,64);next();expect('(');
    F->np=0;
    while(tok.kind!=')'){
        if(F->np>=MAX_PARAMS)fail("too many parameters");
        int mut=0;if(tok.kind==T_MUT){mut=1;next();}
        if(tok.kind!=T_ID)fail("expected parameter name");
        char name[64];memcpy(name,tok.name,64);next();expect(':');
        int w=0,amut=0,t;
        if(tok.kind==T_MUT||tok.kind=='['){
            if(tok.kind==T_MUT){amut=1;next();}
            expect('[');t=parse_type_s(1);expect(']');w=ty_width(t);
            if(mut)fail("array parameters are bindings; use `name: mut [T]` for writable elements");
        }else t=parse_type();
        if(decl){
            int v=declare(name,w?0:mut);
            if(w){Var *a=&vars[v];a->arr=w;a->et=t;a->ty=TY_NONE;a->ro=!amut;a->basev=hidden("#base");a->lenv=hidden("#len");}
            else vars[v].ty=t;
            F->pvar[F->np]=v;
        }
        F->pw[F->np]=w;F->pty[F->np]=t;F->pmut[F->np]=amut;F->np++;
        if(tok.kind!=',')break;
        next();
    }
    expect(')');
    if(tok.kind==T_ARROW){next();F->rett=parse_type();}else F->rett=TY_UNIT;
}
static void parse_function(int f){
    Func *F=&fns[f];
    curfn=f;nvis=0;F->mark=-1;
    parse_header(f,1);
    if(f==mainfn&&F->np)fail("main takes no parameters");
    if(f==mainfn&&F->rett!=TY_I64&&F->rett!=TY_UNIT)fail("main returns i64 or nothing");
    F->body=parse_block();
    if(F->mark>=0)vars[F->mark].reads+=2;
    int last=-1;for(int s=nd[F->body].a;s>=0;s=nd[s].next)last=s;
    if(last<0||nd[last].k!=S_RET){
        if(F->rett!=TY_UNIT)fail("a function must end with a return statement");
        int r=mk(S_RET);nd[r].a=mkconst(0);   /* unit function: implicit return */
        if(last<0)nd[F->body].a=r;else nd[last].next=r;
    }
}
/* ---- top-level items: struct declarations and globals ----------------- */
enum { GLOB_MAX=1<<30 };
static int64_t glob_bytes;                 /* static (bss) bytes used by global arrays */
static int ginit_head=-1,ginit_tail=-1;    /* nonzero global initial values: stores run first in main */
static void parse_struct(void){
    expect(T_STRUCT);
    if(tok.kind!=T_ID)fail("expected struct name");
    if(nst>=MAX_STRUCTS)fail("too many structs");
    for(int i=0;i<nst;i++)if(!strcmp(sts[i].name,tok.name))fail("duplicate struct");
    for(int t=TY_I8;t<=TY_F64;t++)if(!strcmp(tok.name,tyname[t]))fail("reserved name");
    Struct *S=&sts[nst];memset(S,0,sizeof *S);memcpy(S->name,tok.name,64);next();expect('{');
    int off=0,al=1;
    while(tok.kind!='}'){
        if(S->nf>=MAX_FIELDS)fail("too many fields");
        if(tok.kind!=T_ID)fail("expected field name");
        for(int f=0;f<S->nf;f++)if(!strcmp(S->fname[f],tok.name))fail("duplicate field");
        memcpy(S->fname[S->nf],tok.name,64);next();expect(':');
        int t=parse_type(),w=ty_width(t);
        off=(off+w-1)/w*w;S->foff[S->nf]=off;S->fty[S->nf]=t;S->nf++;off+=w;if(w>al)al=w;  /* natural alignment */
        if(tok.kind!=',')break;
        next();
    }
    expect('}');
    if(!S->nf)fail("a struct needs at least one field");
    S->size=(off+al-1)/al*al;nst++;
}
static int new_global(const char *name,int mut){
    for(size_t k=0;k<sizeof reserved/sizeof reserved[0];k++)if(!strcmp(name,reserved[k]))fail("reserved name");
    if(!strncmp(name,"__",2)&&!in_prelude)fail("names starting with __ are reserved");
    for(int j=0;j<ngvis;j++)if(!strcmp(vars[gvis[j]].name,name))fail("duplicate global");
    if(nv>=MAX_VARS)fail("too many variables");
    Var *v=&vars[nv];memset(v,0,sizeof *v);
    memcpy(v->name,name,64);v->mut=mut;v->reg=-1;v->slot=-1;v->lenv=-1;v->ty=TY_I64;v->owner=-1;
    gvis[ngvis++]=nv;return nv++;
}
static int static_array(int v,int et,int64_t n){ /* zeroed bss array at a fixed address */
    Var *a=&vars[v];int w=ty_width(et);
    a->arr=w;a->et=et;a->ty=TY_NONE;a->alen=n;a->glob=1;
    int64_t at=(glob_bytes+63)&~63LL;
    if(n<1||n>INT32_MAX||at+n*w>GLOB_MAX)fail("global arrays exceed the static limit (1 GiB)");
    glob_bytes=at+n*w;
    int b=hidden("#gbase");vars[b].isconst=1;vars[b].cval=(uint64_t)at;vars[b].owner=-1;vars[b].glob=1;   /* offset; GLOB_BASE added in codegen */
    a->basev=b;return v;
}
static void parse_global(void){
    expect(T_LET);int mut=0;if(tok.kind==T_MUT){mut=1;next();}
    if(tok.kind!=T_ID)fail("expected variable name");
    char name[64];memcpy(name,tok.name,64);next();
    int ann=TY_NONE,aarr=0;
    if(tok.kind==':'){next();if(tok.kind=='['){next();aarr=1;ann=parse_type_s(1);expect(']');}else ann=parse_type();}
    expect('=');
    if(tok.kind==T_ID&&!strcmp(tok.name,"alloc")){
        next();expect('<');int et=parse_type_s(1);expect('>');expect('(');int n=conv(parse_expr(),TY_I64);expect(')');expect(';');
        if(mut)fail("array bindings are immutable (their elements are not)");
        if(ann&&(!aarr||ann!=et))fail("array type annotation does not match the constructor");
        if(!is_const(n))fail("a global array needs a constant length");
        static_array(new_global(name,0),et,I(nd[n].v));
        return;
    }
    if(tok.kind==T_STR){ /* global string: read-only [u8] in the image */
        if(mut)fail("array bindings are immutable (their elements are not)");
        if(ann&&(!aarr||ann!=TY_U8))fail("a string literal is a [u8]");
        size_t so=tok.soff,sl=tok.slen;next();expect(';');
        str_array(new_global(name,0),so,sl);
        return;
    }
    if(aarr)fail("array type annotation needs alloc<T>(n)");
    int e=parse_expr();expect(';');
    if(!is_const(e))fail("a global initializer must be a constant");
    if(ann)e=conv(e,ann);else if(mut)e=deflt(e);
    int v=new_global(name,mut);vars[v].ty=nd[e].ty;
    if(!mut){vars[v].isconst=1;vars[v].cval=nd[e].v;return;}
    /* mutable global scalar: a 1-element static array, read and written in memory */
    int g=hidden("#gvar");vars[g].owner=-1;static_array(g,nd[e].ty,1);vars[v].garr=g;
    if(nd[e].v){
        int st=mk(S_STORE);nd[st].var=g;nd[st].a=mkconst(0);nd[st].b=e;nd[st].op=-1;nd[st].chk=1;
        vars[vars[g].basev].reads++;
        if(ginit_tail<0)ginit_head=st;else nd[ginit_tail].next=st;
        ginit_tail=st;
    }
}
static void skip_item(void){ /* skip a top-level item already handled in another pass */
    int d=0;
    for(;;){
        if(tok.kind==T_EOF)return;
        if(tok.kind==T_STR)sdlen-=tok.slen;      /* string bytes scanned while skipping */
        if(tok.kind=='{')d++;
        if(tok.kind=='}'&&--d==0){next();return;}
        if(tok.kind==';'&&d==0){next();return;}
        next();
    }
}
static void skip_fn(void){ /* header and body */
    while(tok.kind!='{'&&tok.kind!=T_EOF)next();
    skip_item();
}
/* Collect every signature first, so calls are typed while parsing. */
static void prescan(void){
    const char *sp=pos,*ts=tstart;Token st=tok;size_t sd=sdlen;
    int d=0;
    while(tok.kind!=T_EOF){
        if(d==0&&tok.kind==T_FN){
            if(nfn>=MAX_FUNCS)fail("too many functions");
            int f=nfn++;memset(&fns[f],0,sizeof fns[f]);fns[f].exit_list=-1;fns[f].calls=-1;
            parse_header(f,0);
            for(int i=0;i<f;i++)if(!strcmp(fns[i].name,fns[f].name))fail("duplicate function");
            if(!in_prelude&&!strcmp(fns[f].name,"main"))mainfn=f;
            continue;
        }
        if(d==0&&(tok.kind==T_STRUCT||tok.kind==T_LET)){skip_item();continue;}
        if(tok.kind=='{')d++;else if(tok.kind=='}')d--;
        next();
    }
    pos=sp;tok=st;sdlen=sd;tstart=ts;
}
static int fout_state[MAX_FUNCS]; /* 0 unknown, 1 visiting, 2 no output, 3 may output */
static int fn_outputs(int f);
static int stmt_outputs(int s);
static int expr_outputs(int e){
    if(e<0)return 0;
    if(nd[e].k==N_CALL){
        if(fn_outputs(nd[e].var))return 1;
        for(int a=nd[e].a;a>=0;a=nd[a].next)if(expr_outputs(a))return 1;
        return 0;
    }
    if(nd[e].k>N_ARR&&nd[e].k!=N_NCPU)return stmt_outputs(e);
    return expr_outputs(nd[e].a)||expr_outputs(nd[e].b);
}
static int stmt_outputs(int s){
    if(s<0)return 0;
    Node *x=&nd[s];
    if(x->k<=N_ARR||x->k==N_NCPU)return expr_outputs(s);
    if(x->k==S_PRINT||x->k==S_PUTC||x->k==S_WRITE||x->k==S_SAVE)return 1;
    if(expr_outputs(x->a))return 1;
    if(x->k==S_STORE&&expr_outputs(x->b))return 1;
    if(x->k==S_IF&&(stmt_outputs(x->b)||stmt_outputs(x->c)))return 1;
    if(x->k==S_WHILE&&stmt_outputs(x->b))return 1;
    if(x->k==S_BLOCK)for(int c=x->a;c>=0;c=nd[c].next)if(stmt_outputs(c))return 1;
    return 0;
}
static int fn_outputs(int f){
    if(fout_state[f]==1||fout_state[f]==3)return fout_state[f]==3?1:0; /* recursion: decided by other paths */
    if(fout_state[f]==2)return 0;
    fout_state[f]=1;int r=stmt_outputs(fns[f].body);fout_state[f]=r?3:2;return r;
}
static void check_par(void){
    for(int i=0;i<nn;i++)if(nd[i].k==S_PAR&&stmt_outputs(nd[i].c))
        fail("a par block calls a function that may print (output only after the par block)");
}
/* Runtime library written in skite itself; only functions a program uses are emitted. */
static const char *prelude_src=
"fn __pdig(x: u64) { if x >= 10 { __pdig(x / 10); } putc((x % 10) as i64 + 48); }\n"
"fn __print_bool(b: bool) {\n"
"  if b { putc(116); putc(114); putc(117); putc(101); }\n"
"  else { putc(102); putc(97); putc(108); putc(115); putc(101); }\n"
"  putc(10);\n"
"}\n"
/* fixed point, 6 decimals, a < 1e16: ip + fraction (exact), fraction*1e6 rounded half-even */
"fn __pfrac6(t: u64) {\n"
"  putc(46);\n"
"  let mut p: u64 = 100000;\n"
"  while p > 0 { putc((t / p % 10) as i64 + 48); p = p / 10; }\n"
"}\n"
"fn __pfix6(a: f64) {\n"
"  let mut ip = a as u64;\n"
"  let fr = a - ip as f64;\n"
"  let s = fr * 1000000.0;\n"
"  let mut t = s as u64;\n"
"  let d = s - t as f64;\n"
"  if d > 0.5 || (d == 0.5 && t % 2 == 1) { t += 1; }\n"
"  if t == 1000000 { ip += 1; t = 0; }\n"
"  __pdig(ip);\n"
"  __pfrac6(t);\n"
"}\n"
"fn __print_f64(x: f64) {\n"
"  if x != x { putc(78); putc(97); putc(78); putc(10); return; }\n"
"  let neg = bits(x) >> 63 != 0;\n"
"  if neg { putc(45); }\n"
"  let mut a = x;\n"
"  if neg { a = -x; }\n"
"  if a == f64_from_bits(0x7FF0000000000000) { putc(105); putc(110); putc(102); putc(10); return; }\n"
"  if a < 10000000000000000.0 { __pfix6(a); putc(10); return; }\n"
"  if a < 18446744073709551616.0 { __pdig(a as u64); __pfrac6(0); putc(10); return; }\n"
"  let mut e = 0;\n"
"  while a >= 10.0 { a = a / 10.0; e += 1; }\n"
"  __pfix6(a); putc(101); putc(43); __pdig(e as u64); putc(10);\n"
"}\n";
static void parse(void){
    nv=1;memset(&vars[0],0,sizeof vars[0]);strcpy(vars[0].name,"#argc");vars[0].reg=-1;vars[0].slot=-1;vars[0].lenv=-1;vars[0].ty=TY_I64;vars[0].owner=-1;
    memset(&vars[1],0,sizeof vars[1]);strcpy(vars[1].name,"#argv");vars[1].reg=-1;vars[1].slot=-1;vars[1].lenv=-1;vars[1].ty=TY_I64;vars[1].owner=-1;nv=2;
    const char *user=source,*srcs[2]={prelude_src,user};parsing=1;
    mainfn=-2;   /* set by prescan (argc/file are main-only) */
    for(int k=0;k<2;k++){   /* pass 1: structs and globals (any order relative to functions) */
        source=pos=srcs[k];in_prelude=k==0;parsing_src=k?1:2;curfn=-1;next();
        while(tok.kind!=T_EOF){
            if(tok.kind==T_STRUCT)parse_struct();
            else if(tok.kind==T_LET)parse_global();
            else if(tok.kind==T_FN)skip_fn();
            else fail("expected `fn`, `struct` or `let` at top level");
        }
    }
    for(int k=0;k<2;k++){source=pos=srcs[k];in_prelude=k==0;parsing_src=k?1:2;next();prescan();}
    if(mainfn<0)fail("no main function");
    nfn_decl=nfn;
    int fi=0;
    for(int k=0;k<2;k++){
        source=pos=srcs[k];in_prelude=k==0;parsing_src=k?1:2;next();
        while(tok.kind!=T_EOF){
            if(tok.kind==T_FN)parse_function(fi++);
            else skip_item();   /* struct / global: done in pass 1 */
        }
    }
    in_prelude=0;parsing=0;
    check_par();parsing_src=0;
    body=fns[mainfn].body;
    if(ginit_head>=0){nd[ginit_tail].next=nd[body].a;nd[body].a=ginit_head;}
}

/* ------------------------------------------------- loop-aware liveness */
typedef struct {int start,end;} Loop;
static Loop loops[MAX_LOOPS];static int nloops,lstack[MAX_LOOPS],nls,pc;
static int pair_v[MAX_PAIRS],pair_l[MAX_PAIRS],npairs;
static void touch(int v){
    Var *x=&vars[v];if(!x->reads)return;
    if(pc>x->end)x->end=pc;
    int64_t w=1;for(int i=0;i<nls&&i<6;i++)w*=8;
    x->weight+=w;
    /* Declared outside a loop and referenced inside: live for the whole loop. */
    for(int i=0;i<nls;i++)if(loops[lstack[i]].start>x->start){
        if(npairs>=MAX_PAIRS)fail("liveness table full");
        pair_v[npairs]=v;pair_l[npairs++]=lstack[i];break;
    }
}
static int hoist_var(uint64_t v,int L){
    for(int i=0;i<nv;i++)if(vars[i].hoist==L+1&&vars[i].cval==v)return i;
    if(nv>=MAX_VARS)fail("too many variables");
    Var *x=&vars[nv];memset(x,0,sizeof *x);strcpy(x->name,"#k");
    x->hoist=L+1;x->cval=v;x->reads=1;x->reg=-1;x->slot=-1;x->start=loops[L].start;
    return nv++;
}
static int nchecks,nelided;
static int opt_off(const char *name);
static void touch_arr(int a){touch(vars[a].basev);if(vars[a].lenv>=0)touch(vars[a].lenv);}
static void walk_expr(int e){
    if(e<0)return;
    Node *x=&nd[e];
    if(x->k==N_VAR)touch(x->var);
    else if(x->k==N_ARR)touch_arr(x->var);
    else if(x->k==N_CALL){for(int a=x->a;a>=0;a=nd[a].next)walk_expr(a);}
    else if(x->k==N_LOAD){
        touch_arr(x->var);walk_expr(x->a);
        nchecks++;nelided+=!x->chk;
    }
    else if(x->k==N_CONST){
        if(nls&&!fits_s32(x->v)&&(x->v&(x->v-1))&&!opt_off("hoist")){ /* powers of two stay shifts/immediates */
            int h=hoist_var(x->v,lstack[0]);x->c=h;
            int64_t w=1;for(int i=0;i<nls&&i<6;i++)w*=8;
            vars[h].weight+=w;
        }
    }
    else if(x->k==N_UN)walk_expr(x->a);
    else if(x->k==N_BIN){
        walk_expr(x->a);
        if((x->op==O_DIV||x->op==O_MOD||x->op==O_DIVU||x->op==O_MODU)&&is_const(x->b))return; /* divisors stay immediates */
        walk_expr(x->b);
    }
}
static void walk_stmt(int s){
    Node *n=&nd[s];
    switch(n->k){
    case S_LET:
        n->pos=++pc;walk_expr(n->a);
        if(vars[n->var].reads){vars[n->var].start=pc;vars[n->var].end=pc;}
        break;
    case S_ASSIGN:case S_IRET:n->pos=++pc;walk_expr(n->a);touch(n->var);break;
    case S_INL:for(int c=n->a;c>=0;c=nd[c].next)walk_stmt(c);break;
    case S_PAR:
        n->pos=++pc;walk_expr(n->a);walk_expr(n->b);
        vars[n->var].start=vars[n->var].end=pc;vars[n->op].start=vars[n->op].end=pc;
        walk_stmt(n->c);
        ++pc;touch(n->var);touch(n->op);   /* parent's fork loop spans the body */
        break;
    case S_IF:n->pos=++pc;walk_expr(n->a);walk_stmt(n->b);if(n->c>=0)walk_stmt(n->c);break;
    case S_WHILE:{
        if(nloops>=MAX_LOOPS)fail("too many loops");
        if(n->c>=0){++pc;vars[n->c].start=pc;vars[n->c].end=pc;}
        int L=nloops++;n->pos=++pc;n->var=L;loops[L].start=pc;lstack[nls++]=L;
        if(n->c>=0)touch(n->c);
        walk_expr(n->a);walk_stmt(n->b);loops[L].end=pc;nls--;
        if(n->c>=0){++pc;touch(n->c);}
        break;}
    case S_RET:case S_PRINT:case S_PUTC:case S_EXPR:n->pos=++pc;walk_expr(n->a);break;
    case S_WRITE:n->pos=++pc;if(n->var>=0)touch_arr(n->var);walk_expr(n->a);walk_expr(n->b);break;
    case S_SAVE:n->pos=++pc;touch_arr(n->var);touch(0);touch(1);walk_expr(n->a);walk_expr(n->b);break;
    case S_BRK:case S_CONT:n->pos=++pc;break;
    case S_STORE:
        n->pos=++pc;walk_expr(n->a);walk_expr(n->b);touch_arr(n->var);
        nchecks++;nelided+=!n->chk;
        break;
    case S_ARR:{
        Var *a=&vars[n->var];
        n->pos=++pc;walk_expr(n->a);
        if(n->op==A_FILE){touch(0);touch(1);}
        if(n->op==A_VIEW&&vars[n->c].lenv>=0)touch(vars[n->c].lenv);
        if(n->op!=A_VIEW&&vars[a->basev].reads){vars[a->basev].start=pc;vars[a->basev].end=pc;}
        if(a->lenv>=0&&vars[a->lenv].reads){vars[a->lenv].start=pc;vars[a->lenv].end=pc;}
        break;}
    case S_BLOCK:for(int c=n->a;c>=0;c=nd[c].next)walk_stmt(c);break;
    }
}

/* ------------------------------------------------- inlining */
/* A function whose body is a single `return e;` with no calls is inlined at
 * every call whose arguments are all simple (scalar variable, constant, array):
 * parameters are substituted directly, so there is no evaluation-order or
 * duplication change. Repeated to a fixpoint, so helpers of helpers inline too. */
static int has_call(int e){
    if(e<0)return 0;
    if(nd[e].k==N_CALL)return 1;
    return has_call(nd[e].a)||has_call(nd[e].b);
}
static int inl_expr(int f){
    int b=fns[f].body,s=nd[b].a;
    if(s<0||nd[s].next>=0||nd[s].k!=S_RET||has_call(nd[s].a))return -1;
    return nd[s].a;
}
static int subst(int e,int f,int call){
    if(e<0)return -1;
    Node c=nd[e];
    for(int i=0,x=nd[call].a;x>=0;x=nd[x].next,i++){
        int pv=fns[f].pvar[i];
        if(!fns[f].pw[i]&&c.k==N_VAR&&c.var==pv)return clone_expr(x);
        if(fns[f].pw[i]){
            int av=nd[x].var;
            if(c.k==N_VAR&&c.var==vars[pv].lenv)
                return vars[av].lenv<0?mkconst(U(vars[av].alen)):mk_var(vars[av].lenv);
            if(c.k==N_LOAD&&c.var==pv){int r=mk_load(av,subst(c.a,f,call));nd[r].op=c.op;nd[r].ty=c.ty;return r;}
        }
    }
    int r=mk(c.k);nd[r]=c;nd[r].c=-1;nd[r].next=-1;
    if(c.k==N_VAR)vars[c.var].reads++;
    nd[r].a=subst(c.a,f,call);nd[r].b=subst(c.b,f,call);
    return r;
}
static int ninlined;
/* ---- statement-level inlining: zero-cost non-recursive functions ----------
 * `let x = f(..);`, `x = f(..);`, `x op= f(..);` (as x = x op f), `f(..);` and
 * `return f(..);`-free forms: the callee body is cloned with fresh variables
 * into an S_INL block; its returns become S_IRET (assign result + jump to the
 * block end). Arguments are bound left to right before the body, exactly as a
 * call evaluates them. Afterwards range analysis sees the caller's real arrays. */
static int imap[MAX_VARS],imap_gen[MAX_VARS],igen;
static int map_var(int v){
    if(imap_gen[v]==igen)return imap[v];
    return v;   /* not a callee variable */
}
static int clone_stmt_inl(int s,int resv);
static int clone_e_inl(int e){
    if(e<0)return -1;
    Node c=nd[e];
    if(c.k==N_VAR){
        int v=c.var;
        if(imap_gen[v]==igen&&imap[v]<0){ /* length of an array parameter: -(1+arg array) */
            int av=-imap[v]-1;
            return vars[av].lenv<0?mkconst(U(vars[av].alen)):mk_var(vars[av].lenv);
        }
        return mk_var(map_var(v));
    }
    if(c.k==N_LOAD){int r=mk_load(map_var(c.var),clone_e_inl(c.a));nd[r].op=c.op;nd[r].ty=c.ty;return r;}
    if(c.k==N_ARR){int a=map_var(c.var);vars[vars[a].basev].reads++;if(vars[a].lenv>=0)vars[vars[a].lenv].reads++;
        int r=mk(N_ARR);nd[r].var=a;return r;}
    int r=mk(c.k);nd[r]=c;nd[r].c=-1;nd[r].next=-1;
    if(c.k==N_CALL){
        int prev=-1;nd[r].a=-1;
        for(int x=c.a;x>=0;x=nd[x].next){int y=clone_e_inl(x);nd[y].next=-1;if(prev<0)nd[r].a=y;else nd[prev].next=y;prev=y;}
        return r;
    }
    nd[r].a=clone_e_inl(c.a);nd[r].b=clone_e_inl(c.b);
    return r;
}
static int clone_list_inl(int first,int resv){
    int head=-1,prev=-1;
    for(int c=first;c>=0;c=nd[c].next){int y=clone_stmt_inl(c,resv);if(prev<0)head=y;else nd[prev].next=y;prev=y;}
    return head;
}
static int clone_stmt_inl(int s,int resv){
    if(s<0)return -1;
    Node c=nd[s];int r=mk(c.k);nd[r]=c;nd[r].next=-1;
    switch(c.k){
    case S_LET:{
        int nvv=hidden("#inl");vars[nvv].mut=vars[c.var].mut;
        imap[c.var]=nvv;imap_gen[c.var]=igen;
        nd[r].a=clone_e_inl(c.a);nd[r].var=nvv;break;}
    case S_ASSIGN:nd[r].var=map_var(c.var);nd[r].a=clone_e_inl(c.a);break;
    case S_RET:nd[r].k=S_IRET;nd[r].var=resv;nd[r].a=clone_e_inl(c.a);break;
    case S_IRET:nd[r].var=map_var(c.var);nd[r].a=clone_e_inl(c.a);break;
    case S_IF:nd[r].a=clone_e_inl(c.a);nd[r].b=clone_stmt_inl(c.b,resv);nd[r].c=clone_stmt_inl(c.c,resv);break;
    case S_WHILE:nd[r].a=clone_e_inl(c.a);nd[r].b=clone_stmt_inl(c.b,resv);break;
    case S_BLOCK:case S_INL:
        if(c.k==S_INL){int nvv=hidden("#inl");vars[nvv].mut=1;imap[c.var]=nvv;imap_gen[c.var]=igen;nd[r].var=nvv;}
        nd[r].a=clone_list_inl(c.a,resv);break;
    case S_STORE:{int a=map_var(c.var);nd[r].var=a;nd[r].a=clone_e_inl(c.a);nd[r].b=clone_e_inl(c.b);
        vars[vars[a].basev].reads++;if(vars[a].lenv>=0)vars[vars[a].lenv].reads++;break;}
    case S_PRINT:case S_PUTC:case S_EXPR:nd[r].a=clone_e_inl(c.a);break;
    case S_WRITE:
        if(c.var>=0){int a=map_var(c.var);nd[r].var=a;vars[vars[a].basev].reads++;if(vars[a].lenv>=0)vars[vars[a].lenv].reads++;}
        nd[r].a=clone_e_inl(c.a);nd[r].b=clone_e_inl(c.b);break;
    case S_BRK:case S_CONT:break;
    default:fail("internal: cannot inline statement");
    }
    return r;
}
static int stmt_size(int s){
    if(s<0)return 0;
    int n=1;Node *x=&nd[s];
    if(x->k==S_BLOCK||x->k==S_INL){for(int c=x->a;c>=0;c=nd[c].next)n+=stmt_size(c);return n;}
    if(x->k==S_IF)n+=stmt_size(x->b)+stmt_size(x->c);
    if(x->k==S_WHILE)n+=stmt_size(x->b);
    if(x->k==S_ARR)n+=100000;   /* views/strings in a callee: not inlined */
    return n;
}
static int reach_mark[MAX_FUNCS];
static int calls_reach(int s,int target,int depth);
static int expr_reach(int e,int target,int depth){
    if(e<0)return 0;
    if(nd[e].k==N_CALL){
        int f=nd[e].var;
        if(f==target)return 1;
        if(!reach_mark[f]){reach_mark[f]=1;if(calls_reach(fns[f].body,target,depth+1))return 1;}
        for(int a=nd[e].a;a>=0;a=nd[a].next)if(expr_reach(a,target,depth))return 1;
        return 0;
    }
    if(nd[e].k>N_ARR)return calls_reach(e,target,depth);
    return expr_reach(nd[e].a,target,depth)||expr_reach(nd[e].b,target,depth);
}
static int calls_reach(int s,int target,int depth){
    if(s<0||depth>MAX_FUNCS)return 0;
    Node *x=&nd[s];
    if(x->k<=N_ARR)return expr_reach(s,target,depth);
    if(expr_reach(x->a,target,depth))return 1;
    if((x->k==S_STORE||x->k==S_WRITE||x->k==S_SAVE)&&expr_reach(x->b,target,depth))return 1;
    if(x->k==S_IF&&(calls_reach(x->b,target,depth)||calls_reach(x->c,target,depth)))return 1;
    if(x->k==S_WHILE&&calls_reach(x->b,target,depth))return 1;
    if(x->k==S_BLOCK||x->k==S_INL)for(int c=x->a;c>=0;c=nd[c].next)if(calls_reach(c,target,depth))return 1;
    return 0;
}
static int recursive(int f){memset(reach_mark,0,sizeof reach_mark);return calls_reach(fns[f].body,f,0);}
enum { INLINE_MAX_STMTS=400, INLINE_NODE_BUDGET=MAX_NODES*3/4, INLINE_CALLER_BUDGET=2000 };
static int inl_growth;   /* statements inlined into the current caller */
static int ninl_stmt;
static int try_inline_stmt(int s){
    Node *x=&nd[s];int call=-1,holder=-1,inb=0;   /* holder: node that will read the result */
    /* a[i] = f(..): the value is evaluated before the index anyway; print/putc(f(..)) */
    if(x->k==S_STORE&&x->op<0&&x->b>=0&&nd[x->b].k==N_CALL){call=x->b;inb=1;}
    if((x->k==S_PRINT||x->k==S_PUTC)&&x->a>=0&&nd[x->a].k==N_CALL)call=x->a;
    if(call<0&&(x->k==S_LET||x->k==S_ASSIGN||x->k==S_EXPR)&&x->a>=0){
        if(nd[x->a].k==N_CALL)call=x->a;
        /* x = y op f(..) with y a variable/constant (x op= f(..)): y is unaffected by the call */
        else if(x->k!=S_EXPR&&nd[x->a].k==N_BIN&&nd[x->a].op!=O_LAND&&nd[x->a].op!=O_LOR&&nd[nd[x->a].b].k==N_CALL&&
                (nd[nd[x->a].a].k==N_VAR||nd[nd[x->a].a].k==N_CONST)){call=nd[x->a].b;holder=x->a;}
    }
    if(call<0)return 0;
    int f=nd[call].var;
    if(!strncmp(fns[f].name,"__",2))return 0;   /* runtime library (print helpers): out of line */
    int csz=stmt_size(fns[f].body);
    if(csz>INLINE_MAX_STMTS||recursive(f)||nn>INLINE_NODE_BUDGET)return 0;
    if(inl_growth+csz>INLINE_CALLER_BUDGET)return 0;   /* keep every function analyzable */
    inl_growth+=csz;
    igen++;
    int resv=hidden("#ret");vars[resv].mut=1;
    /* bind arguments left to right */
    int head=-1,prev=-1,i=0;
    for(int a=nd[call].a;a>=0;a=nd[a].next,i++){
        int pv=fns[f].pvar[i];
        if(fns[f].pw[i]){ /* arrays alias the caller's array */
            int av=nd[a].var;
            imap[pv]=av;imap_gen[pv]=igen;
            imap[vars[pv].lenv]=-(av+1);imap_gen[vars[pv].lenv]=igen;
            imap[vars[pv].basev]=vars[av].basev;imap_gen[vars[pv].basev]=igen;
            continue;
        }
        int nvv=hidden("#arg");vars[nvv].mut=vars[pv].mut;
        int l=mk(S_LET);nd[l].var=nvv;nd[l].a=a;
        imap[pv]=nvv;imap_gen[pv]=igen;
        if(prev<0)head=l;else nd[prev].next=l;
        prev=l;
    }
    int body=clone_list_inl(nd[fns[f].body].a,resv);
    if(prev<0)head=body;else nd[prev].next=body;
    int inl=mk(S_INL);nd[inl].a=head;nd[inl].var=resv;
    /* the original statement now reads the result */
    int keep_next=x->next;
    int orig=mk(x->k);nd[orig]=nd[s];nd[orig].next=-1;
    nd[call].k=N_CONST;nd[call].v=0;nd[call].a=-1;   /* the call node is gone: keep no stale facts */
    if(nd[orig].k==S_EXPR){nd[inl].next=-1;nd[s]=(Node){.k=S_BLOCK,.a=inl,.b=-1,.c=-1,.next=keep_next,.var=-1};}
    else{
        if(holder>=0)nd[holder].b=mk_var(resv);else if(inb)nd[orig].b=mk_var(resv);else nd[orig].a=mk_var(resv);
        nd[inl].next=orig;nd[s]=(Node){.k=S_BLOCK,.a=inl,.b=-1,.c=-1,.next=keep_next,.var=-1};
    }
    ninl_stmt++;
    return 1;
}
static void inline_stmts(int s){
    if(s<0)return;
    Node *x=&nd[s];
    if(x->k==S_BLOCK||x->k==S_INL){for(int c=x->a;c>=0;c=nd[c].next){inline_stmts(c);}return;}
    if(x->k==S_IF){inline_stmts(x->b);inline_stmts(x->c);return;}
    if(x->k==S_WHILE){inline_stmts(x->b);return;}
    if(x->k==S_PAR){inline_stmts(x->c);return;}
    if(try_inline_stmt(s))inline_stmts(nd[s].a);   /* nested calls inside the inlined body */
}
static void inline_calls(void){
    for(int round=0;round<8;round++){
        int changed=0,n0=nn;
        for(int e=0;e<n0;e++){
            if(nd[e].k!=N_CALL)continue;
            int f=nd[e].var,body_e=inl_expr(f);
            if(body_e<0)continue;
            int ok=1;
            for(int x=nd[e].a;x>=0;x=nd[x].next)if(nd[x].k!=N_VAR&&nd[x].k!=N_CONST&&nd[x].k!=N_ARR)ok=0;
            if(!ok)continue;
            int r=subst(body_e,f,e);
            int keep_next=nd[e].next;nd[e]=nd[r];nd[e].next=keep_next;
            changed=1;ninlined++;
        }
        if(!changed)break;
    }
}
static void mark_used_expr(int e);
static void mark_used_stmt(int s){
    if(s<0)return;
    Node *x=&nd[s];
    mark_used_expr(x->a);
    if(x->k==S_STORE||x->k==S_WRITE||x->k==S_SAVE)mark_used_expr(x->b);
    if(x->k==S_IF){mark_used_stmt(x->b);mark_used_stmt(x->c);}
    if(x->k==S_WHILE)mark_used_stmt(x->b);
    if(x->k==S_PAR){mark_used_expr(x->b);mark_used_stmt(x->c);}
    if(x->k==S_BLOCK||x->k==S_INL)for(int c=x->a;c>=0;c=nd[c].next)mark_used_stmt(c);
}
static void mark_used_expr(int e){
    if(e<0||e>=nn)return;
    Node *x=&nd[e];
    if(x->k>N_ARR)return;     /* statements (and ncpu) are handled elsewhere */
    if(x->k==N_CALL){
        int f=x->var;
        if(!fns[f].used){fns[f].used=1;mark_used_stmt(fns[f].body);}
        for(int a=x->a;a>=0;a=nd[a].next)mark_used_expr(a);
        return;
    }
    mark_used_expr(x->a);mark_used_expr(x->b);
}
static void mark_used(void){
    for(int f=0;f<nfn;f++)fns[f].used=0;
    fns[mainfn].used=1;mark_used_stmt(fns[mainfn].body);
}

/* ------------------------------------------------- periodic-index strength reduction */
/* Cyclic indexing (i % p with i stepping by 1) is the defining access pattern of
 * periodic ciphers and columnar layouts. For a loop whose only update of i is a
 * top-level `i += 1`, with p and E loop-invariant, E >= 0 and p >= 1 proven at
 * loop entry, and (i + E) proven >= 0 at entry: replace (i [+ E]) % p by a
 * shadow m, initialized before the loop and advanced in lock step with i:
 *   m += 1; if m == p { m = 0; }
 * Exact for non-negative dividends; removes one division per iteration. */
static int count_assign(int s,int v){
    if(s<0)return 0;
    Node *x=&nd[s];int c=0;
    if((x->k==S_LET||x->k==S_ASSIGN||x->k==S_IRET)&&x->var==v)c++;
    if(x->k==S_BLOCK||x->k==S_INL){for(int ch=x->a;ch>=0;ch=nd[ch].next)c+=count_assign(ch,v);return c;}
    if(x->k==S_IF){c+=count_assign(x->b,v)+count_assign(x->c,v);}
    if(x->k==S_WHILE)c+=count_assign(x->b,v);
    if(x->k==S_PAR)c+=count_assign(x->c,v)+(x->var==v);
    return c;
}
static int invariant(int e,int loop){
    if(e<0)return 1;
    Node *x=&nd[e];
    if(x->k==N_LOAD||x->k==N_CALL||x->k==N_ARR)return 0;
    if(x->k==N_VAR)return count_assign(loop,x->var)==0;
    return invariant(x->a,loop)&&invariant(x->b,loop);
}
static int is_inc1(int s,int v){
    Node *x=&nd[s];
    if(x->k!=S_ASSIGN||x->var!=v)return 0;
    Node *e=&nd[x->a];
    return e->k==N_BIN&&e->op==O_ADD&&nd[e->a].k==N_VAR&&nd[e->a].var==v&&is_const(e->b)&&nd[e->b].v==1;
}
static int nsr;
static int has_trap(int e);
static int mk_assign(int v,int e){int s=mk(S_ASSIGN);nd[s].var=v;nd[s].a=e;return s;}
static void sr_scan(int e,int loop,int ivar,int incstmt,int *init_head,int *init_tail){
    if(e<0)return;
    Node *x=&nd[e];
    if(x->k==N_BIN||x->k==N_UN||x->k==N_LOAD){sr_scan(x->a,loop,ivar,incstmt,init_head,init_tail);sr_scan(x->b,loop,ivar,incstmt,init_head,init_tail);}
    if(x->k==N_CALL)for(int a=x->a;a>=0;a=nd[a].next)sr_scan(a,loop,ivar,incstmt,init_head,init_tail);
    if(x->k!=N_BIN||x->op!=O_MOD)return;
    int d=x->a,E=-1;
    if(nd[d].k==N_VAR&&nd[d].var==ivar){}
    else if(nd[d].k==N_BIN&&nd[d].op==O_ADD&&nd[nd[d].a].k==N_VAR&&nd[nd[d].a].var==ivar){E=nd[d].b;}
    else return;
    if(!invariant(x->b,loop)||(E>=0&&!invariant(E,loop)))return;
    /* the initializer runs even if the loop body never does: it must not trap */
    if(has_trap(x->b)||(E>=0&&has_trap(E)))return;
    VR *en=wentry[loop];if(!en)return;
    lmap_for(wfn[loop]);
    if(dead(en))return;
    Rg rd=er(d,en),rp=er(x->b,en);
    if(rd.bot||rd.lo<0||rp.bot||rp.lo<1)return;
    /* m = dividend % p at entry (p >= 1: cannot trap) */
    int m=hidden("#mod");vars[m].mut=1;
    int init=mk(S_LET);nd[init].var=m;
    int c1=clone_expr(d),c2=clone_expr(x->b);   /* explicit order: node numbering must be deterministic */
    nd[init].a=mk_bin(O_MOD,c1,c2);
    nd[nd[init].a].nn=1;
    if(*init_tail<0)*init_head=init;else nd[*init_tail].next=init;
    *init_tail=init;
    /* after the increment: m += 1; if m == p { m = 0; } */
    int mv=mk_var(m),one=mkconst(1);
    int inc=mk_assign(m,mk_bin(O_ADD,mv,one));
    int reset=mk_assign(m,mkconst(0));
    int blk=mk(S_BLOCK);nd[blk].a=reset;
    int iff=mk(S_IF);
    int mv2=mk_var(m),cp=clone_expr(x->b);
    nd[iff].a=mk_bin(O_EQ,mv2,cp);nd[iff].b=blk;
    nd[inc].next=iff;nd[iff].next=nd[incstmt].next;nd[incstmt].next=inc;
    /* the MOD node becomes a read of m (operands' reads are released) */
    x->k=N_VAR;x->var=m;x->a=x->b=-1;vars[m].reads++;
    nsr++;
}
static void sr_stmts(int s,int loop,int ivar,int incstmt,int *ih,int *it){
    if(s<0)return;
    Node *x=&nd[s];
    switch(x->k){
    case S_BLOCK:case S_INL:for(int c=x->a;c>=0;c=nd[c].next)sr_stmts(c,loop,ivar,incstmt,ih,it);break;
    case S_IRET:sr_scan(x->a,loop,ivar,incstmt,ih,it);break;
    case S_PAR:sr_scan(x->a,loop,ivar,incstmt,ih,it);sr_scan(x->b,loop,ivar,incstmt,ih,it);sr_stmts(x->c,loop,ivar,incstmt,ih,it);break;
    case S_LET:case S_ASSIGN:case S_RET:case S_PRINT:case S_PUTC:case S_EXPR:sr_scan(x->a,loop,ivar,incstmt,ih,it);break;
    case S_WRITE:sr_scan(x->a,loop,ivar,incstmt,ih,it);sr_scan(x->b,loop,ivar,incstmt,ih,it);break;
    case S_STORE:sr_scan(x->a,loop,ivar,incstmt,ih,it);sr_scan(x->b,loop,ivar,incstmt,ih,it);break;
    case S_IF:sr_scan(x->a,loop,ivar,incstmt,ih,it);sr_stmts(x->b,loop,ivar,incstmt,ih,it);sr_stmts(x->c,loop,ivar,incstmt,ih,it);break;
    case S_WHILE:sr_scan(x->a,loop,ivar,incstmt,ih,it);sr_stmts(x->b,loop,ivar,incstmt,ih,it);break;
    }
}
static void strength_reduce(void){
    int n0=nn;
    for(int L=0;L<n0;L++){
        if(nd[L].k!=S_WHILE||!wentry[L])continue;
        int body_blk=nd[L].b,ih=-1,it=-1;
        for(int s=nd[body_blk].a;s>=0;s=nd[s].next){
            if(nd[s].k!=S_ASSIGN||!is_inc1(s,nd[s].var))continue;
            int v=nd[s].var;
            if(count_assign(L,v)!=1)continue;
            sr_scan(nd[L].a,L,v,s,&ih,&it);
            sr_stmts(body_blk,L,v,s,&ih,&it);
        }
        if(ih<0)continue;
        /* L becomes { inits; while ... } */
        int w=mk(S_WHILE);nd[w]=nd[L];nd[w].next=-1;
        wentry[w]=wentry[L];wentry[L]=NULL;wfn[w]=wfn[L];
        nd[it].next=w;
        int keep_next=nd[L].next;
        nd[L]=(Node){.k=S_BLOCK,.a=ih,.b=-1,.c=-1,.next=keep_next,.var=-1};
    }
    for(int i=0;i<nn;i++)if(wentry[i]){free(wentry[i]);wentry[i]=NULL;}
}

/* ------------------------------------------------- linear-scan allocation */
enum {RAX=0,RCX=1,RDX=2,RBX=3,RSP=4,RBP=5,RSI=6,RDI=7};
/* RAX/RCX/RDX are scratch (idiv, shift count, wide multiply); RSP is the frame.
 * The remaining 12 registers hold variables and expression temporaries. */
static const int allregs[12]={6,7,8,9,10,11,3,5,12,13,14,15};
static int nslots,spilled,peak_active;
static int cheaper(int a,int b){ /* spill cost: weight / interval length */
    int64_t la=vars[a].end-vars[a].start+1,lb=vars[b].end-vars[b].start+1;
    return vars[a].weight*lb<vars[b].weight*la;
}
/* LING0_NO=sr,inline,elide,hoist disables individual optimizations (debugging/bisecting) */
static int opt_off(const char *name){const char *e=getenv("LING0_NO");return e&&strstr(e,name);}
static void allocate(void){
    if(!opt_off("inline")){
        inline_calls();
        if(nfn>1){inl_growth=0;inline_stmts(fns[mainfn].body);}
        for(int f=0;f<nfn;f++)if(f!=mainfn){inl_growth=0;inline_stmts(fns[f].body);}
        inline_calls();   /* expression helpers exposed by statement inlining */
    }
    mark_used();
    for(int v=0;v<nv;v++)if(vars[v].owner>=0&&!fns[vars[v].owner].used)vars[v].reads=0;   /* unused functions */
    analyze();
    if(opt_off("elide"))for(int i=0;i<nn;i++){if(nd[i].k==N_LOAD||nd[i].k==S_STORE)nd[i].chk=1;nd[i].nn=0;}
    if(!opt_off("sr"))strength_reduce();
    for(int f=0;f<nfn;f++)if(fns[f].used){
        ++pc;   /* function entry: parameters are defined here */
        for(int i=0;i<fns[f].np;i++){
            int v=fns[f].pvar[i];int ids[2]={v,-1};
            if(fns[f].pw[i]){ids[0]=vars[v].basev;ids[1]=vars[v].lenv;}
            for(int k=0;k<2;k++)if(ids[k]>=0&&vars[ids[k]].reads){vars[ids[k]].start=pc;vars[ids[k]].end=pc;}
        }
        int fm=fns[f].mark;
        if(fm>=0){vars[fm].start=vars[fm].end=pc;}
        walk_stmt(fns[f].body);
        if(fm>=0){++pc;touch(fm);}
    }
    for(int i=0;i<npairs;i++)if(loops[pair_l[i]].end>vars[pair_v[i]].end)vars[pair_v[i]].end=loops[pair_l[i]].end;
    for(int v=0;v<nv;v++)if(vars[v].hoist)vars[v].end=loops[vars[v].hoist-1].end;
    static int order[MAX_VARS],active[MAX_ACTIVE+1];int no=0,na=0;
    for(int v=0;v<nv;v++)if(vars[v].reads&&!vars[v].isconst)order[no++]=v;
    for(int i=1;i<no;i++){int x=order[i],j=i;while(j>0&&vars[order[j-1]].start>vars[x].start){order[j]=order[j-1];j--;}order[j]=x;}
    int freer[12],nf=12;for(int i=0;i<12;i++)freer[i]=allregs[i];
    for(int i=0;i<no;i++){
        int v=order[i];
        for(int j=0;j<na;)if(vars[active[j]].end<vars[v].start){freer[nf++]=vars[active[j]].reg;active[j]=active[--na];}else j++;
        if(na<MAX_ACTIVE){vars[v].reg=freer[--nf];active[na++]=v;}
        else{
            int vi=-1;
            for(int j=0;j<na;j++)if(vi<0||cheaper(active[j],active[vi]))vi=j;
            if(cheaper(v,active[vi])){if(!vars[v].hoist){vars[v].slot=nslots++;spilled++;}}
            else{int old=active[vi];vars[v].reg=vars[old].reg;vars[old].reg=-1;
                if(!vars[old].hoist){vars[old].slot=nslots++;spilled++;}active[vi]=v;}
        }
        if(na>peak_active)peak_active=na;
    }
}
/* busy[p]: bit i set when allregs[i] holds a variable live at position p
 * (difference arrays per register, built once: O(positions + variables)) */
static uint16_t *busy;static int busy_n;
static void build_busy(void){
    busy_n=pc+2;
    int *d=calloc((size_t)busy_n*12,sizeof(int));busy=calloc((size_t)busy_n,sizeof(uint16_t));
    if(!d||!busy){perror("calloc");exit(1);}
    for(int v=0;v<nv;v++){
        if(vars[v].reg<0||vars[v].start>vars[v].end)continue;
        int i=0;while(allregs[i]!=vars[v].reg)i++;
        int a=vars[v].start<0?0:vars[v].start,b=vars[v].end+1>busy_n-1?busy_n-1:vars[v].end+1;
        d[(size_t)i*busy_n+a]++;d[(size_t)i*busy_n+b]--;
    }
    for(int i=0;i<12;i++){int c=0;for(int p=0;p<busy_n;p++){c+=d[(size_t)i*busy_n+p];if(c>0)busy[p]|=(uint16_t)(1u<<i);}}
    free(d);
}
static int temps_at(int p,int *out){
    int n=0;
    if(!busy)build_busy();
    uint16_t m=p>=0&&p<busy_n?busy[p]:0;
    for(int i=0;i<12;i++)if(!(m>>i&1))out[n++]=allregs[i];
    if(n<2)fail("internal: fewer than two temporary registers");
    return n;
}

/* ------------------------------------------------- x86-64 encoder */
static uint8_t code[MAX_BYTES];static size_t clen;
static void byte(uint8_t x){if(clen>=MAX_BYTES)fail("generated code limit reached");code[clen++]=x;}
static void u32(uint32_t x){for(int i=0;i<4;i++)byte((uint8_t)(x>>(8*i)));}
static void u64(uint64_t x){for(int i=0;i<8;i++)byte((uint8_t)(x>>(8*i)));}
static void patch32(size_t at,int32_t v){for(int i=0;i<4;i++)code[at+i]=(uint8_t)((uint32_t)v>>(8*i));}
static void rel32(size_t at,size_t target){int64_t d=(int64_t)target-(int64_t)(at+4);if(d<INT32_MIN||d>INT32_MAX)fail("branch too far");patch32(at,(int32_t)d);}
#define EMIT(...) do{const uint8_t b_[]={__VA_ARGS__};for(size_t i_=0;i_<sizeof b_;i_++)byte(b_[i_]);}while(0)
enum {K_REG,K_MEM,K_IMM};
typedef struct {int k,r;uint64_t imm;} Opnd; /* K_MEM: r = frame slot, address [rsp+8*r] */
static Opnd R(int r){return (Opnd){K_REG,r,0};}
static Opnd M(int s){return (Opnd){K_MEM,s,0};}
static Opnd IMM(uint64_t v){return (Opnd){K_IMM,0,v};}
static int fits_s32(uint64_t v){return I(v)>=INT32_MIN&&I(v)<=INT32_MAX;}
static int fits_s8(uint64_t v){return I(v)>=-128&&I(v)<=127;}
/* REX, opcode (1-2 bytes), ModRM with register-direct or [rsp+disp] operand.
 * sp_adj: extra bytes pushed below the frame during a call sequence. */
static int sp_adj;
static void enc(int w,int force_rex,int nop,uint8_t o1,uint8_t o2,int regf,Opnd rm){
    int b=rm.k==K_REG?rm.r:RSP;
    uint8_t rex=(uint8_t)(0x40|(w?8:0)|((regf&8)?4:0)|((b&8)?1:0));
    if(rex!=0x40||force_rex)byte(rex);
    byte(o1);if(nop==2)byte(o2);
    if(rm.k==K_REG){byte((uint8_t)(0xc0|((regf&7)<<3)|(rm.r&7)));return;}
    uint32_t d=(uint32_t)rm.r*8u+(uint32_t)sp_adj;
    if(d==0){byte((uint8_t)(0x04|((regf&7)<<3)));byte(0x24);}
    else if(d<128){byte((uint8_t)(0x44|((regf&7)<<3)));byte(0x24);byte((uint8_t)d);}
    else{byte((uint8_t)(0x84|((regf&7)<<3)));byte(0x24);u32(d);}
}
static void mov_rr(int d,int s){if(d!=s)enc(1,0,1,0x89,0,s,R(d));}
static void mov_ri(int d,uint64_t v){
    if(v==0){enc(0,0,1,0x31,0,d,R(d));return;}                 /* xor r32,r32 */
    if(v<=0xffffffffULL){if(d&8)byte(0x41);byte((uint8_t)(0xb8|(d&7)));u32((uint32_t)v);return;}
    if(fits_s32(v)){enc(1,0,1,0xc7,0,0,R(d));u32((uint32_t)v);return;}
    byte((uint8_t)(0x48|((d&8)?1:0)));byte((uint8_t)(0xb8|(d&7)));u64(v);
}
static void load(int d,Opnd s){
    if(s.k==K_REG)mov_rr(d,s.r);
    else if(s.k==K_MEM)enc(1,0,1,0x8b,0,d,s);
    else mov_ri(d,s.imm);
}
static void store(Opnd dst,int s){if(dst.k==K_REG)mov_rr(dst.r,s);else enc(1,0,1,0x89,0,s,dst);}
enum {A_ADD=0,A_OR=1,A_AND=4,A_SUB=5,A_XOR=6,A_CMP=7};
static void alu(int dig,Opnd dst,Opnd src){
    if(dig==7&&src.k==K_IMM&&src.imm==0&&dst.k==K_REG){enc(1,0,1,0x85,0,dst.r,dst);return;} /* cmp r,0 -> test r,r */
    if(src.k==K_IMM){
        if(!fits_s32(src.imm)){int sc=(dst.k==K_REG&&dst.r==RAX)?RDX:RAX;mov_ri(sc,src.imm);src=R(sc);}
        else if(fits_s8(src.imm)){enc(1,0,1,0x83,0,dig,dst);byte((uint8_t)src.imm);return;}
        else{enc(1,0,1,0x81,0,dig,dst);u32((uint32_t)src.imm);return;}
    }
    if(src.k==K_REG)enc(1,0,1,(uint8_t)(dig*8+1),0,src.r,dst);
    else{if(dst.k!=K_REG)fail("internal: mem-mem alu");enc(1,0,1,(uint8_t)(dig*8+3),0,dst.r,src);}
}
static void imul_r(int d,Opnd s){
    if(s.k==K_IMM){
        if(fits_s8(s.imm)){enc(1,0,1,0x6b,0,d,R(d));byte((uint8_t)s.imm);return;}
        if(fits_s32(s.imm)){enc(1,0,1,0x69,0,d,R(d));u32((uint32_t)s.imm);return;}
        int sc=d==RAX?RDX:RAX;mov_ri(sc,s.imm);s=R(sc);
    }
    enc(1,0,2,0x0f,0xaf,d,s);
}
static void shift_ri(int dig,int d,unsigned k){k&=63;if(!k)return;if(k==1)enc(1,0,1,0xd1,0,dig,R(d));else{enc(1,0,1,0xc1,0,dig,R(d));byte((uint8_t)k);}}
/* lea d, [base + index + disp]; index < 0 for none. index is never RSP here. */
static void lea(int d,int base,int index,int64_t disp){
    int md=disp==0&&(base&7)!=5?0:fits_s8(U(disp))?1:2;
    byte((uint8_t)(0x48|((d&8)?4:0)|(index>=0&&(index&8)?2:0)|((base&8)?1:0)));byte(0x8d);
    if(index<0&&(base&7)!=4)byte((uint8_t)((md<<6)|((d&7)<<3)|(base&7)));
    else{byte((uint8_t)((md<<6)|((d&7)<<3)|4));byte((uint8_t)(((index<0?4:index)&7)<<3|(base&7)));}
    if(md==1)byte((uint8_t)disp);else if(md==2)u32((uint32_t)disp);
}
/* [base + index*2^scale] operand. index is never RSP; rbp/r13 base needs disp8 0. */
static int32_t mdisp; /* displacement for the next memop (folded constant index offset) */
static void memop(int w,int p66,int force_rex,int nop,uint8_t o1,uint8_t o2,int regf,int base,int index,int scale){
    if(p66)byte(0x66);
    uint8_t rex=(uint8_t)(0x40|(w?8:0)|((regf&8)?4:0)|((index&8)?2:0)|((base&8)?1:0));
    if(rex!=0x40||force_rex)byte(rex);
    byte(o1);if(nop==2)byte(o2);
    int32_t d=mdisp;mdisp=0;
    int md=d==0&&(base&7)!=5?0:fits_s8(U(d))?1:2;
    byte((uint8_t)((md<<6)|((regf&7)<<3)|4));
    byte((uint8_t)((scale<<6)|((index&7)<<3)|(base&7)));
    if(md==1)byte((uint8_t)d);else if(md==2)u32((uint32_t)d);
}
static int lg(int w){return w==1?0:w==2?1:w==4?2:3;}
/* loads produce the canonical register form of the element type */
static void load_elem(int t,int d,int base,int idx,int sc){
    switch(t){
    case TY_U8:case TY_BOOL:memop(0,0,0,2,0x0f,0xb6,d,base,idx,sc);break;   /* movzx r32, byte */
    case TY_I8:memop(1,0,0,2,0x0f,0xbe,d,base,idx,sc);break;               /* movsx r64, byte */
    case TY_U16:memop(0,0,0,2,0x0f,0xb7,d,base,idx,sc);break;              /* movzx r32, word */
    case TY_I16:memop(1,0,0,2,0x0f,0xbf,d,base,idx,sc);break;              /* movsx r64, word */
    case TY_U32:case TY_F32:memop(0,0,0,1,0x8b,0,d,base,idx,sc);break;     /* mov r32 (zero-extends) */
    case TY_I32:memop(1,0,0,1,0x63,0,d,base,idx,sc);break;                 /* movsxd */
    default:memop(1,0,0,1,0x8b,0,d,base,idx,sc);
    }
}
/* dig < 0: plain store; else ALU op [mem], v at element width */
static void store_elem(int w,int dig,int v,int base,int idx,int sc){
    uint8_t op=dig<0?(uint8_t)(w==1?0x88:0x89):(uint8_t)(dig*8+(w==1?0:1));
    memop(w==8,w==2,w==1,1,op,0,v,base,idx,sc);
}
static void unop(int dig,Opnd d){enc(1,0,1,0xf7,0,dig,d);} /* 2 not,3 neg,5 imul,7 idiv */
static void cqo(void){EMIT(0x48,0x99);}
static void setcc_zx(int cc,int r){enc(0,1,2,0x0f,(uint8_t)(0x90|cc),0,R(r));enc(1,0,2,0x0f,0xb6,r,R(r));}
static void test_rr(int r){enc(1,0,1,0x85,0,r,R(r));}
static size_t jcc(int cc){EMIT(0x0f,(uint8_t)(0x80|cc));u32(0);return clen-4;}
static size_t jmp(void){byte(0xe9);u32(0);return clen-4;}
enum {CC_B=2,CC_AE=3,CC_BE=6,CC_A=7,CC_S=8,CC_P=0xa,CC_NP=0xb,CC_E=4,CC_NE=5,CC_L=0xc,CC_GE=0xd,CC_LE=0xe,CC_G=0xf};
static int cc_of(int op){switch(op){case O_EQ:return CC_E;case O_NE:return CC_NE;case O_LT:return CC_L;case O_LE:return CC_LE;case O_GT:return CC_G;
    case O_LTU:return CC_B;case O_LEU:return CC_BE;case O_GTU:return CC_A;case O_GEU:return CC_AE;default:return CC_GE;}}
/* Patch lists of rel32 fields awaiting a target. */
static size_t pl_at[MAX_PATCH];static int pl_next[MAX_PATCH],npl;
static void pl_add(int *list,size_t at){if(npl>=MAX_PATCH)fail("too many branches");pl_at[npl]=at;pl_next[npl]=*list;*list=npl++;}
static void pl_patch(int list,size_t target){for(;list>=0;list=pl_next[list])rel32(pl_at[list],target);}

/* ------------------------------------------------- signed division by constant */
/* Granlund-Montgomery / Hacker's Delight 10-1, 64-bit; requires |d|>=2, not a power of 2. */
static void magic(int64_t d,int64_t *M,int *s){
    const uint64_t two63=1ULL<<63;
    uint64_t ad=d<0?0-(uint64_t)d:(uint64_t)d;
    uint64_t t=two63+((uint64_t)d>>63);
    uint64_t anc=t-1-t%ad;
    int p=63;
    uint64_t q1=two63/anc,r1=two63-q1*anc,q2=two63/ad,r2=two63-q2*ad,delta;
    do{
        p++;
        q1*=2;r1*=2;if(r1>=anc){q1++;r1-=anc;}
        q2*=2;r2*=2;if(r2>=ad){q2++;r2-=ad;}
        delta=ad-r2;
    }while(q1<delta||(q1==delta&&r1==0));
    uint64_t m=q2+1;if(d<0)m=0-m;
    *M=I(m);*s=p-64;
}
static void divconst(int r,uint64_t dv,int mod,int nn){
    int64_t d=I(dv);
    if(d==1){if(mod)mov_ri(r,0);return;}
    if(d==-1||d==INT64_MIN){ /* keep the hardware trap for INT64_MIN / -1 */
        mov_ri(RCX,dv);mov_rr(RAX,r);cqo();unop(7,R(RCX));mov_rr(r,mod?RDX:RAX);return;
    }
    uint64_t ad=d<0?0-dv:dv;
    if(nn&&d>0&&!(ad&(ad-1))){ /* non-negative dividend: plain shift / mask */
        unsigned k=0;while((1ULL<<k)!=ad)k++;
        if(mod)alu(A_AND,R(r),IMM(ad-1));else shift_ri(7,r,k);
        return;
    }
    if(!(ad&(ad-1))){
        unsigned k=0;while((1ULL<<k)!=ad)k++;
        mov_rr(RAX,r);shift_ri(7,RAX,63);shift_ri(5,RAX,64-k);alu(A_ADD,R(RAX),R(r));
        if(mod){alu(A_AND,R(RAX),IMM(0-ad));alu(A_SUB,R(r),R(RAX));}
        else{shift_ri(7,RAX,k);if(d<0)unop(3,R(RAX));mov_rr(r,RAX);}
        return;
    }
    int64_t M;int s;magic(d,&M,&s);
    mov_ri(RAX,U(M));unop(5,R(r));                 /* rdx:rax = M * n */
    if(d>0&&M<0)alu(A_ADD,R(RDX),R(r));
    if(d<0&&M>0)alu(A_SUB,R(RDX),R(r));
    shift_ri(7,RDX,(unsigned)s);
    if(d>0){ /* q += (n < 0): uses n's sign, computable in parallel with the multiply */
        if(!nn){mov_rr(RAX,r);shift_ri(7,RAX,63);alu(A_SUB,R(RDX),R(RAX));}
    }else{mov_rr(RAX,RDX);shift_ri(5,RAX,63);alu(A_ADD,R(RDX),R(RAX));}
    if(!mod){mov_rr(r,RDX);return;}
    imul_r(RDX,IMM(dv));alu(A_SUB,R(r),R(RDX));
}

/* ------------------------------------------------- expression codegen */
static int tbase,tdepth,tmax;
static int tslot_push(void){int s=tbase+tdepth++;if(tdepth>tmax)tmax=tdepth;return s;}
static Opnd loc(int v){if(vars[v].reg<0&&vars[v].slot<0)fail("internal: unallocated variable");return vars[v].reg>=0?R(vars[v].reg):M(vars[v].slot);}
static int simple(int e){return nd[e].k==N_CONST||nd[e].k==N_VAR;}
static int hoisted(int e){return nd[e].k==N_CONST&&nd[e].c>=0&&vars[nd[e].c].reg>=0?vars[nd[e].c].reg:-1;}
static Opnd opnd(int e){
    if(nd[e].k==N_CONST){int h=hoisted(e);return h>=0?R(h):IMM(nd[e].v);}
    return loc(nd[e].var);
}
static int is_cmp(int op){return op>=O_EQ&&op<=O_GEU;}
static int commutes(int op){return op==O_ADD||op==O_MUL||op==O_AND||op==O_OR||op==O_XOR||op==O_EQ||op==O_NE;}
static int swap_cmp(int op){switch(op){case O_LT:return O_GT;case O_GT:return O_LT;case O_LE:return O_GE;case O_GE:return O_LE;
    case O_LTU:return O_GTU;case O_GTU:return O_LTU;case O_LEU:return O_GEU;case O_GEU:return O_LEU;
    case O_FLT:return O_FGT;case O_FGT:return O_FLT;case O_FLE:return O_FGE;case O_FGE:return O_FLE;
    case O_GLT:return O_GGT;case O_GGT:return O_GLT;case O_GLE:return O_GGE;case O_GGE:return O_GLE;default:return op;}}
static int need(int e){
    Node *n=&nd[e];
    if(n->k==N_UN||n->k==N_LOAD)return need(n->a);
    if(n->k!=N_BIN)return 1;   /* calls: arguments get the full register set */
    int na=need(n->a);
    if(n->op==O_LAND||n->op==O_LOR){int nb=need(n->b);return na>nb?na:nb;}
    if(simple(n->b))return na;
    int nb=need(n->b);return na==nb?na+1:(na>nb?na:nb);
}
static int refs(int e,int v){
    if(e<0)return 0;
    if(nd[e].k==N_VAR)return nd[e].var==v;
    if(nd[e].k==N_CALL){for(int a=nd[e].a;a>=0;a=nd[a].next)if(refs(a,v))return 1;return 0;}
    return refs(nd[e].a,v)||refs(nd[e].b,v);
}
static int has_trap(int e){
    if(e<0||nd[e].k==N_CONST||nd[e].k==N_VAR||nd[e].k==N_ARR)return 0;
    if(nd[e].k==N_CALL)return 1;   /* calls may trap, loop or print: never dropped */
    int b=nd[e].b;
    if(nd[e].k==N_LOAD&&nd[e].chk)return 1;
    if(nd[e].k==N_BIN&&(nd[e].op==O_DIV||nd[e].op==O_MOD)&&(!is_const(b)||I(nd[b].v)==-1))return 1;
    if(nd[e].k==N_BIN&&(nd[e].op==O_DIVU||nd[e].op==O_MODU)&&!is_const(b))return 1;
    return has_trap(nd[e].a)||has_trap(nd[e].b);
}
static int div_nn; /* set by callers: dividend of the next DIV/MOD is non-negative */
/* ---- SSE2 scalar float: values stay in GPRs (bit patterns); xmm0/xmm1 are scratch.
 * pfx: F2 = f64 (sd), F3 = f32 (ss). Register allocation of floats in XMM
 * registers is part of the SSA backend (Phase 3). */
static size_t j8(uint8_t op);
static void p8(size_t at,size_t target);
static void sse(uint8_t pfx,int w,uint8_t op,int regf,Opnd rm){if(pfx)byte(pfx);enc(w,0,2,0x0f,op,regf,rm);}
static void fload(int x,Opnd s,int dbl){ /* xmm x <- value */
    if(s.k==K_IMM){mov_ri(RAX,s.imm);s=R(RAX);}
    if(s.k==K_REG)sse(0x66,dbl,0x6e,x,s);        /* movq/movd xmm, r */
    else sse(0xf3,0,0x7e,x,s);                   /* movq xmm, m64 (f32 bits are zero-extended) */
}
static void fstore(int r,int x,int dbl){sse(0x66,dbl,0x7e,x,R(r));}   /* movq r64 / movd r32 (zero-extends) */
static void fcmp_xmm(int r,Opnd s,int dbl,int swap){ /* ucomis: a in r, b in s; swap: compare b with a */
    fload(0,R(r),dbl);
    if(s.k==K_MEM&&!swap){sse(dbl?0x66:0,0,0x2e,0,s);return;}
    fload(1,s,dbl);
    if(swap)sse(dbl?0x66:0,0,0x2e,1,R(0));else sse(dbl?0x66:0,0,0x2e,0,R(1));
}
static void apply_f(int op,int r,Opnd s){
    int dbl=fop_dbl(op),b=fop_base(op);uint8_t pfx=dbl?0xf2:0xf3;
    if(b<=O_FDIV){
        static const uint8_t oc[4]={0x58,0x5c,0x59,0x5e};   /* add sub mul div */
        fload(0,R(r),dbl);
        if(s.k==K_MEM)sse(pfx,0,oc[b-O_FADD],0,s);else{fload(1,s,dbl);sse(pfx,0,oc[b-O_FADD],0,R(1));}
        fstore(r,0,dbl);return;
    }
    /* compares (NaN: only != is true): a<b == b>a and a<=b == b>=a, unordered sets CF */
    int swap=b==O_FLT||b==O_FLE;
    fcmp_xmm(r,s,dbl,swap);
    switch(b){
    case O_FGT:case O_FLT:setcc_zx(CC_A,r);break;
    case O_FGE:case O_FLE:setcc_zx(CC_AE,r);break;
    case O_FEQ:setcc_zx(CC_E,r);EMIT(0x0f,0x9b,0xc0,0x0f,0xb6,0xc0);alu(A_AND,R(r),R(RAX));break;  /* sete; setnp al */
    default:setcc_zx(CC_NE,r);EMIT(0x0f,0x9a,0xc0,0x0f,0xb6,0xc0);alu(A_OR,R(r),R(RAX));break;     /* setne; setp al */
    }
}
static int u2d_calls=-1,u2s_calls=-1,d2u_calls=-1,s2u_calls=-1;
static void call_to(int *list);
static void via_rt(int r,int *list){mov_rr(RAX,r);call_to(list);mov_rr(r,RAX);}
/* float -> int, truncating, saturating, NaN -> 0 */
static void f2i(int r,int dbl){
    fload(0,R(r),dbl);
    sse(dbl?0xf2:0xf3,1,0x2c,r,R(0));            /* cvtts?2si r64, xmm0 (0x8000.. on NaN/overflow) */
    alu(A_CMP,R(r),IMM(1));size_t ok=j8(0x71);   /* r-1 overflows only for 0x8000..: jno done */
    sse(dbl?0x66:0,0,0x2e,0,R(0));size_t nan=j8(0x7a);   /* ucomis xmm0,xmm0; jp nan */
    fstore(RAX,0,dbl);if(dbl)test_rr(RAX);else EMIT(0x85,0xc0);size_t neg=j8(0x78); /* negative: keep INT64_MIN */
    unop(2,R(r));size_t d2=j8(0xeb);              /* positive overflow: INT64_MAX */
    p8(nan,clen);enc(0,0,1,0x31,0,r,R(r));
    p8(ok,clen);p8(neg,clen);p8(d2,clen);
}
static int is_narrow(int op){return op>=U_SX8&&op<=U_SATU32;}
static int ext_width(int op){return op==U_SX8||op==U_ZX8?1:op==U_SX16||op==U_ZX16?2:op==U_SX32||op==U_ZX32?4:0;}
static void apply_un(int op,int r){
    switch(op){
    case U_NEG:unop(3,R(r));break;
    case U_NOT:unop(2,R(r));break;
    case U_LNOT:alu(A_XOR,R(r),IMM(1));break;                     /* bool */
    case U_SX8:enc(1,0,2,0x0f,0xbe,r,R(r));break;                 /* movsx r64, r8 */
    case U_SX16:enc(1,0,2,0x0f,0xbf,r,R(r));break;
    case U_SX32:enc(1,0,1,0x63,0,r,R(r));break;                   /* movsxd */
    case U_ZX8:enc(0,1,2,0x0f,0xb6,r,R(r));break;                 /* movzx r32, r8 */
    case U_ZX16:enc(0,0,2,0x0f,0xb7,r,R(r));break;
    case U_ZX32:enc(0,0,1,0x89,0,r,R(r));break;                   /* mov r32, r32 */
    case U_SATS8:case U_SATS16:case U_SATS32:case U_SATU8:case U_SATU16:case U_SATU32:{
        static const int64_t lo[6]={-128,-32768,INT32_MIN,0,0,0},hi[6]={127,32767,INT32_MAX,255,65535,UINT32_MAX};
        int k=op-U_SATS8;
        mov_ri(RAX,U(lo[k]));alu(A_CMP,R(r),R(RAX));enc(1,0,2,0x0f,0x4c,r,R(RAX));   /* cmovl */
        mov_ri(RAX,U(hi[k]));alu(A_CMP,R(r),R(RAX));enc(1,0,2,0x0f,0x4f,r,R(RAX));   /* cmovg */
        break;}
    case U_FNEG:enc(1,0,2,0x0f,0xba,7,R(r));byte(63);break;       /* btc r,63 */
    case U_GNEG:enc(0,0,1,0x81,0,6,R(r));u32(0x80000000u);break;  /* xor r32, sign */
    case U_I2D:case U_I2S:
        EMIT(0x66,0x0f,0xef,0xc0);                                /* pxor xmm0,xmm0: no false dependency */
        sse(op==U_I2D?0xf2:0xf3,1,0x2a,0,R(r));fstore(r,0,op==U_I2D);break;
    case U_D2S:fload(0,R(r),1);EMIT(0xf2,0x0f,0x5a,0xc0);fstore(r,0,0);break;
    case U_S2D:fload(0,R(r),0);EMIT(0xf3,0x0f,0x5a,0xc0);fstore(r,0,1);break;
    case U_SQRTD:fload(0,R(r),1);EMIT(0xf2,0x0f,0x51,0xc0);fstore(r,0,1);break;
    case U_SQRTS:fload(0,R(r),0);EMIT(0xf3,0x0f,0x51,0xc0);fstore(r,0,0);break;
    case U_D2I:f2i(r,1);break;
    case U_S2I:f2i(r,0);break;
    case U_U2D:via_rt(r,&u2d_calls);break;
    case U_U2S:via_rt(r,&u2s_calls);break;
    case U_D2U:via_rt(r,&d2u_calls);break;
    case U_S2U:via_rt(r,&s2u_calls);break;
    default:fail("internal: bad unary operator");
    }
}
static void apply(int op,int r,Opnd s){
    int nn=div_nn;div_nn=0;   /* one-shot: never leaks to a later division */
    if(is_fop(op)){apply_f(op,r,s);return;}
    switch(op){
    case O_DIVU:case O_MODU:
        if(s.k==K_IMM&&s.imm&&!(s.imm&(s.imm-1))){
            unsigned k=0;while((1ULL<<k)!=s.imm)k++;
            if(op==O_MODU)alu(A_AND,R(r),IMM(s.imm-1));else shift_ri(5,r,k);
            break;
        }
        if(s.k==K_IMM){mov_ri(RCX,s.imm);s=R(RCX);}
        mov_rr(RAX,r);EMIT(0x31,0xd2);unop(6,s);mov_rr(r,op==O_DIVU?RAX:RDX);break;   /* xor edx,edx; div */
    case O_ADD:alu(A_ADD,R(r),s);break; case O_SUB:alu(A_SUB,R(r),s);break;
    case O_AND:alu(A_AND,R(r),s);break; case O_OR:alu(A_OR,R(r),s);break;
    case O_XOR:alu(A_XOR,R(r),s);break;
    case O_MUL:
        if(s.k==K_IMM){
            uint64_t v=s.imm;
            if(v==0){mov_ri(r,0);break;}
            if(v==1)break;
            if(I(v)==-1){unop(3,R(r));break;}
            if(!(v&(v-1))){unsigned k=0;while((1ULL<<k)!=v)k++;shift_ri(4,r,k);break;}
        }
        imul_r(r,s);break;
    case O_SHL:case O_SHR:case O_SAR:{
        int dig=op==O_SHL?4:op==O_SHR?5:7;
        if(s.k==K_IMM)shift_ri(dig,r,(unsigned)(s.imm&63));
        else{load(RCX,s);enc(1,0,1,0xd3,0,dig,R(r));}
        break;}
    case O_DIV:case O_MOD:
        if(s.k==K_IMM){divconst(r,s.imm,op==O_MOD,nn);break;}
        mov_rr(RAX,r);cqo();unop(7,s);mov_rr(r,op==O_DIV?RAX:RDX);break;
    default:
        if(!is_cmp(op))fail("internal: bad operator");
        alu(A_CMP,R(r),s);setcc_zx(cc_of(op),r);break;
    }
}
static size_t j8(uint8_t op){byte(op);byte(0);return clen-1;}
static void p8(size_t at,size_t target){int64_t d=(int64_t)target-(int64_t)(at+1);if(d<-128||d>127)fail("internal: short branch");code[at]=(uint8_t)(int8_t)d;}
static int trap_list=-1,print_calls=-1,printu_calls=-1,putc_calls=-1,write_calls=-1,ncpu_calls=-1;
/* bss layout (RW, no X): output buffer, signal action, par status */

static int use_out,use_bss,flush_calls=-1;
/* absolute addresses of string data, patched once the layout is final */
enum { MAX_SSITES=65536 };
static size_t ss_at[MAX_SSITES],ss_off[MAX_SSITES];static int nss;
static void str_site(size_t at,size_t off){if(nss>=MAX_SSITES)fail("too many string uses");ss_at[nss]=at;ss_off[nss++]=off;}
/* unsigned compare catches negative indices too; ud2 -> SIGILL */
static void bounds(int a,int r,int chk){
    if(!chk)return;
    Var *v=&vars[a];
    alu(A_CMP,R(r),v->lenv<0?IMM(U(v->alen)):loc(v->lenv));
    pl_add(&trap_list,jcc(CC_AE));
}
static void gen(int e,const int *rg,int n);
enum { BSS=0x600000, OUT_LEN=BSS, SIG_ACT=BSS+8, PAR_STATUS=BSS+48, PAR_FAIL=BSS+56, OUT_BUF=BSS+64, OUT_CAP=65536,
       ARENA_TOP=OUT_BUF+OUT_CAP, ARENA_END=ARENA_TOP+8, GLOB_BASE=ARENA_TOP+64, BSS_FIXED=GLOB_BASE-BSS };
/* array base: a register/slot variable, or the fixed address of a static (global) array */
static Opnd base_opnd(int a){int b=vars[a].basev;if(vars[b].isconst)return IMM(GLOB_BASE+vars[b].cval);return loc(b);}
static void str_site(size_t at,size_t off);
/* r = array base. String-literal arrays bound without a statement (global strings,
 * literal arguments) live in the image: their address is patched after layout. */
static void load_base(int r,int a){
    int b=vars[a].basev;
    if(vars[b].glob==2){if(r&8)byte(0x41);byte((uint8_t)(0xb8|(r&7)));str_site(clen,(size_t)vars[b].cval);u32(0);return;}
    load(r,base_opnd(a));
}/* op r64, [abs32] / op [abs32], r64 (bss words such as the arena top) */
static void abs_op(uint8_t op,int r,uint32_t addr){byte((uint8_t)(0x48|((r&8)?4:0)));byte(op);byte((uint8_t)(0x04|((r&7)<<3)));byte(0x25);u32(addr);}
static int base_reg(int a){if(vars[vars[a].basev].glob==2){load_base(RAX,a);return RAX;}Opnd b=base_opnd(a);if(b.k==K_REG)return b.r;load(RAX,b);return RAX;}
/* Index operand without a copy: a register-resident variable is used directly;
 * x + c folds c into the displacement when the access is proven in range. */
static int index_reg(int idx,int chk,int w,int *disp,const int *rg,int n){
    Node *x=&nd[idx];*disp=0;
    if(x->k==N_VAR&&vars[x->var].reg>=0)return vars[x->var].reg;
    if(!chk&&x->k==N_BIN&&(x->op==O_ADD||x->op==O_SUB)&&nd[x->a].k==N_VAR&&vars[nd[x->a].var].reg>=0&&is_const(x->b)){
        int64_t c=I(nd[x->b].v);if(x->op==O_SUB)c=-c;
        if(c>-(1<<20)&&c<(1<<20)&&w<=1024){*disp=(int)(c*w);return vars[nd[x->a].var].reg;}
    }
    gen(idx,rg,n);return rg[0];
}
/* element address [base + index*stride + field offset]: sets *b, *ri, *sc and mdisp.
 * Strides that are not 1/2/4/8 (structs) scale the index into RDX (scratch). */
static void elem_addr(int a,int idx,int chk,int foff,const int *rg,int n,int *b,int *ri,int *sc){
    int d,w=vars[a].arr;
    *ri=index_reg(idx,chk,w,&d,rg,n);
    bounds(a,*ri,chk);
    if(w==1||w==2||w==4||w==8)*sc=lg(w);
    else{ /* imul rdx, ri, w */
        if(w<128){enc(1,0,1,0x6b,0,RDX,R(*ri));byte((uint8_t)w);}else{enc(1,0,1,0x69,0,RDX,R(*ri));u32((uint32_t)w);}
        *ri=RDX;*sc=0;
    }
    *b=base_reg(a);mdisp=d+foff;
}
static int fld_off(int a,int f){return f>0?sts[vars[a].et-TY_STRUCT0].foff[f-1]:0;}   /* f: field+1 */
static void cond_jump(int e,int sense,int *list,const int *rg,int n);
/* Calls (caller-saved): every allocatable register that is not a free temporary
 * here may hold a live value, so it is pushed; the callee may use all of them.
 * Arguments go in an outgoing area just above the return address:
 *   [callee entry rsp + 8 + 8*k] = argument word k (arrays: base, length). */
static void store_out(int disp,int r){int sv=sp_adj;sp_adj=0;enc(1,0,1,0x89,0,r,M(disp/8));sp_adj=sv;}
static void push_r(int r){if(r&8)byte(0x41);byte((uint8_t)(0x50|(r&7)));}
static void pop_r(int r){if(r&8)byte(0x41);byte((uint8_t)(0x58|(r&7)));}
static void gen_call(int e,const int *rg,int n){
    Node *x=&nd[e];int f=x->var,words=0,direct=1,nscal=0;
    for(int a=x->a;a>=0;a=nd[a].next){words+=nd[a].k==N_ARR?2:1;if(nd[a].k!=N_ARR&&has_call(a))direct=0;}
    int slot[MAX_PARAMS],k=0;
    if(!direct)  /* nested calls in arguments: evaluate everything into frame slots first */
        for(int a=x->a;a>=0;a=nd[a].next)if(nd[a].k!=N_ARR){gen(a,rg,n);slot[k]=tslot_push();store(M(slot[k]),rg[0]);k++;nscal++;}
    int save[12],ns=0;
    for(int i=0;i<12;i++){int r=allregs[i],fr=0;for(int j=0;j<n;j++)if(rg[j]==r)fr=1;if(!fr)save[ns++]=r;}
    for(int i=0;i<ns;i++)push_r(save[i]);
    int A=8*words;
    if(A){EMIT(0x48,0x81,0xec);u32((uint32_t)A);}
    sp_adj=8*ns+A;
    int w=0;k=0;
    for(int a=x->a;a>=0;a=nd[a].next){
        if(nd[a].k==N_ARR){
            Var *v=&vars[nd[a].var];
            load_base(RAX,nd[a].var);store_out(8*w,RAX);
            if(v->lenv<0)mov_ri(RAX,U(v->alen));else load(RAX,loc(v->lenv));
            store_out(8*w+8,RAX);w+=2;
        }else{
            if(direct){gen(a,rg,n);store_out(8*w,rg[0]);}
            else{load(RAX,M(slot[k++]));store_out(8*w,RAX);}
            w++;
        }
    }
    sp_adj=0;
    byte(0xe8);pl_add(&fns[f].calls,clen);u32(0);
    if(A){EMIT(0x48,0x81,0xc4);u32((uint32_t)A);}
    for(int i=ns-1;i>=0;i--)pop_r(save[i]);
    mov_rr(rg[0],RAX);
    tdepth-=nscal;
}
/* ---- float expression trees in an XMM stack (xmm2..xmm15) --------------
 * Variables still live in GPRs (bit patterns); a float tree moves each leaf in
 * once and the result out once, instead of a GPR round trip per operation.
 * Trees with calls are excluded (callees clobber XMM). Left-to-right order. */
static int fprec(int e){ /* 1: f64, 0: f32 (by opcode where possible) */
    Node *x=&nd[e];
    if(x->k==N_BIN&&is_fop(x->op))return fop_dbl(x->op);
    if(x->k==N_UN)switch(x->op){   /* by opcode: bits() may have retagged the type */
        case U_D2S:case U_GNEG:case U_SQRTS:case U_I2S:return 0;
        case U_S2D:case U_FNEG:case U_SQRTD:case U_I2D:return 1;
    }
    return x->ty!=TY_F32;
}
static int ftree(int e){ /* float-valued tree worth evaluating in XMM */
    Node *x=&nd[e];
    if(x->k==N_BIN)return is_fop(x->op)&&!is_fcmp(x->op);
    if(x->k==N_UN)return x->op==U_FNEG||x->op==U_GNEG||x->op==U_S2D||x->op==U_D2S||x->op==U_SQRTD||x->op==U_SQRTS||x->op==U_I2D||x->op==U_I2S;
    return 0;
}
static int xtop=2;   /* first free stack register: nested trees (inside int subexpressions) start above live ones */
static void gen_x(int e,int x,const int *rg,int n){int sv=xtop;xtop=x+1;gen(e,rg,n);xtop=sv;}   /* int child; xmm2..x live */
static void xmov_in(int x,Opnd s){ /* xmm x <- 64-bit value */
    if(s.k==K_IMM){if(!s.imm){byte(0x66);enc(0,0,2,0x0f,0xef,x,R(x));return;}mov_ri(RAX,s.imm);s=R(RAX);}
    if(s.k==K_REG)sse(0x66,1,0x6e,x,s);else sse(0xf3,0,0x7e,x,s);
}
static void genf(int e,int x,const int *rg,int n){
    Node *t=&nd[e];int dbl=fprec(e);uint8_t pfx=dbl?0xf2:0xf3;
    switch(t->k){
    case N_CONST:{int h=hoisted(e);xmov_in(x,h>=0?R(h):IMM(t->v));return;}
    case N_VAR:xmov_in(x,loc(t->var));return;
    case N_LOAD:
        {int ft=t->op>0?sts[vars[t->var].et-TY_STRUCT0].fty[t->op-1]:vars[t->var].et;
        if(ty_flt(ft)){
            int sv=xtop;xtop=x+1;
            int b,ri,sc;elem_addr(t->var,t->a,t->chk,fld_off(t->var,t->op),rg,n,&b,&ri,&sc);
            xtop=sv;
            byte(ft==TY_F64?0xf2:0xf3);memop(0,0,0,2,0x0f,0x10,x,b,ri,sc);   /* movsd/movss xmm,[addr] */
            return;
        }}
        break;
    case N_BIN:
        if(is_fop(t->op)&&!is_fcmp(t->op)){
            static const uint8_t oc[4]={0x58,0x5c,0x59,0x5e};
            uint8_t o=oc[fop_base(t->op)-O_FADD];
            genf(t->a,x,rg,n);
            Node *b=&nd[t->b];
            if(b->k==N_VAR&&vars[b->var].reg<0){sse(pfx,0,o,x,loc(b->var));return;}   /* op xmm, [slot] */
            if(x<15){genf(t->b,x+1,rg,n);sse(pfx,0,o,x,R(x+1));return;}
            gen_x(t->b,x,rg,n);xmov_in(1,R(rg[0]));sse(pfx,0,o,x,R(1));return;        /* stack full */
        }
        break;
    case N_UN:
        switch(t->op){
        case U_FNEG:case U_GNEG:
            genf(t->a,x,rg,n);mov_ri(RAX,t->op==U_FNEG?1ULL<<63:0x80000000ULL);xmov_in(1,R(RAX));
            if(t->op==U_FNEG){byte(0x66);}
            enc(0,0,2,0x0f,0x57,x,R(1));return;                                         /* xorpd / xorps */
        case U_S2D:genf(t->a,x,rg,n);sse(0xf3,0,0x5a,x,R(x));return;
        case U_D2S:genf(t->a,x,rg,n);sse(0xf2,0,0x5a,x,R(x));return;
        case U_SQRTD:genf(t->a,x,rg,n);sse(0xf2,0,0x51,x,R(x));return;
        case U_SQRTS:genf(t->a,x,rg,n);sse(0xf3,0,0x51,x,R(x));return;
        case U_I2D:case U_I2S:
            gen_x(t->a,x-1,rg,n);byte(0x66);enc(0,0,2,0x0f,0xef,x,R(x));               /* pxor: no false dependency */
            sse(t->op==U_I2D?0xf2:0xf3,1,0x2a,x,R(rg[0]));return;
        }
        break;
    }
    gen_x(e,x-1,rg,n);xmov_in(x,R(rg[0]));
}
static int xroom(int e){return ftree(e)&&!has_call(e)&&xtop<=13;}
static void genf_root(int e,int r,const int *rg,int n){ /* float tree -> canonical bits in GPR r */
    int x=xtop;genf(e,x,rg,n);fstore(r,x,fprec(e));
}
static void gen(int e,const int *rg,int n){
    Node *x=&nd[e];int r0=rg[0];
    if(xroom(e)){genf_root(e,r0,rg,n);return;}
    switch(x->k){
    case N_CONST:if(hoisted(e)>=0)mov_rr(r0,hoisted(e));else mov_ri(r0,x->v);return;
    case N_VAR:load(r0,loc(x->var));return;
    case N_CALL:gen_call(e,rg,n);return;
    case N_NCPU:byte(0xe8);pl_add(&ncpu_calls,clen);u32(0);mov_rr(r0,RAX);return;
    case N_LOAD:{
        int b,ri,sc;elem_addr(x->var,x->a,x->chk,fld_off(x->var,x->op),rg,n,&b,&ri,&sc);
        load_elem(x->op>0?sts[vars[x->var].et-TY_STRUCT0].fty[x->op-1]:vars[x->var].et,r0,b,ri,sc);
        return;}
    case N_UN:gen(x->a,rg,n);if(!(x->nn&&is_narrow(x->op)))apply_un(x->op,r0);return;
    }
    int op=x->op,a=x->a,b=x->b;
    if(op==O_LAND||op==O_LOR){
        int f=-1,end=-1;cond_jump(e,0,&f,rg,n);
        mov_ri(r0,1);pl_add(&end,jmp());pl_patch(f,clen);mov_ri(r0,0);pl_patch(end,clen);
        return;
    }
    if(nd[a].k==N_VAR&&nd[b].k==N_CONST){
        uint64_t k=nd[b].v;Opnd la=loc(nd[a].var);
        /* imul r0, a, imm (no copy) unless a shift/neg/zero form is better */
        if(op==O_MUL&&fits_s32(k)&&k>1&&(k&(k-1))&&I(k)!=-1){
            if(fits_s8(k)){enc(1,0,1,0x6b,0,r0,la);byte((uint8_t)k);}else{enc(1,0,1,0x69,0,r0,la);u32((uint32_t)k);}
            return;
        }
        /* lea r0, [a + imm] */
        if((op==O_ADD||op==O_SUB)&&la.k==K_REG&&fits_s32(k)&&(op==O_ADD||I(k)!=INT32_MIN)&&k){
            lea(r0,la.r,-1,op==O_ADD?I(k):-I(k));return;
        }
    }
    if(op==O_ADD&&nd[a].k==N_VAR&&nd[b].k==N_VAR&&vars[nd[a].var].reg>=0&&vars[nd[b].var].reg>=0){
        lea(r0,vars[nd[a].var].reg,vars[nd[b].var].reg,0);return;   /* lea r0, [a + b] */
    }
    if(simple(b)){gen(a,rg,n);div_nn=x->nn;apply(op,r0,opnd(b));return;}
    /* Calls make evaluation order observable: then operands go strictly left to right. */
    int lr=has_call(a)||has_call(b);
    if(n>=2){
        if(lr||need(a)>=need(b)){gen(a,rg,n);gen(b,rg+1,n-1);apply(op,r0,R(rg[1]));return;}
        gen(b,rg,n);gen(a,rg+1,n-1);
        if(commutes(op))apply(op,r0,R(rg[1]));
        else if(is_cmp(op))apply(swap_cmp(op),r0,R(rg[1]));
        else{apply(op,rg[1],R(r0));mov_rr(r0,rg[1]);}
        return;
    }
    if(lr){ /* a first, parked in a slot; then b; then a op b */
        gen(a,rg,1);int sa=tslot_push();store(M(sa),r0);gen(b,rg,1);int sb=tslot_push();store(M(sb),r0);
        load(r0,M(sa));apply(op,r0,M(sb));tdepth-=2;return;
    }
    gen(b,rg,1);int s=tslot_push();store(M(s),r0);gen(a,rg,1);apply(op,r0,M(s));tdepth--;
}
static void cond_jump(int e,int sense,int *list,const int *rg,int n){
    Node *x=&nd[e];
    if(x->k==N_CONST){if((x->v!=0)==sense)pl_add(list,jmp());return;}
    if(x->k==N_UN&&x->op==U_LNOT){cond_jump(x->a,!sense,list,rg,n);return;}
    if(x->k==N_BIN&&x->op==O_LAND){
        if(sense){int f=-1;cond_jump(x->a,0,&f,rg,n);cond_jump(x->b,1,list,rg,n);pl_patch(f,clen);}
        else{cond_jump(x->a,0,list,rg,n);cond_jump(x->b,0,list,rg,n);}
        return;
    }
    if(x->k==N_BIN&&x->op==O_LOR){
        if(sense){cond_jump(x->a,1,list,rg,n);cond_jump(x->b,1,list,rg,n);}
        else{int t=-1;cond_jump(x->a,1,&t,rg,n);cond_jump(x->b,0,list,rg,n);pl_patch(t,clen);}
        return;
    }
    if(x->k==N_BIN&&is_fcmp(x->op)&&!has_call(e)&&xtop<=13){
        int bs=fop_base(x->op),dbl=fop_dbl(x->op),sw=bs==O_FLT||bs==O_FLE,xa=xtop,xb=xtop+1;
        genf(x->a,xa,rg,n);genf(x->b,xb,rg,n);
        if(sw)sse(dbl?0x66:0,0,0x2e,xb,R(xa));else sse(dbl?0x66:0,0,0x2e,xa,R(xb));   /* ucomis */
        if(bs==O_FEQ||bs==O_FNE){ /* equal = ZF && !PF */
            int eq=(bs==O_FEQ)==sense;
            if(eq){size_t sk=j8(0x7a);pl_add(list,jcc(CC_E));p8(sk,clen);}
            else{pl_add(list,jcc(CC_P));pl_add(list,jcc(CC_NE));}
            return;
        }
        int cc=(bs==O_FGT||bs==O_FLT)?CC_A:CC_AE;
        pl_add(list,jcc(sense?cc:cc^1));return;
    }
    if(x->k==N_BIN&&is_fcmp(x->op)&&fop_base(x->op)!=O_FEQ&&fop_base(x->op)!=O_FNE){
        /* a ? b with ordered relations: ucomis + ja/jae (unordered fails, so the
         * negation jbe/jb is taken for NaN, as required) */
        int a=x->a,b=x->b,bs=fop_base(x->op),dbl=fop_dbl(x->op),ra=rg[0];Opnd ob;int park=0;
        if(simple(b)){gen(a,rg,n);ob=opnd(b);}
        else if(n>=2){gen(a,rg,n);gen(b,rg+1,n-1);ob=R(rg[1]);}
        else{gen(a,rg,1);int sa=tslot_push();store(M(sa),ra);gen(b,rg,1);int sb=tslot_push();store(M(sb),ra);load(ra,M(sa));ob=M(sb);park=2;}
        fcmp_xmm(ra,ob,dbl,bs==O_FLT||bs==O_FLE);
        tdepth-=park;
        int cc=(bs==O_FGT||bs==O_FLT)?CC_A:CC_AE;
        pl_add(list,jcc(sense?cc:cc^1));return;
    }
    if(x->k==N_BIN&&is_cmp(x->op)){
        int a=x->a,b=x->b,cc=cc_of(x->op);
        Opnd la=nd[a].k==N_VAR?loc(nd[a].var):IMM(0);
        if(nd[a].k==N_VAR&&simple(b)&&(la.k==K_REG||opnd(b).k!=K_MEM))alu(A_CMP,la,opnd(b));
        else if(nd[a].k==N_VAR&&la.k==K_REG){gen(b,rg,n);alu(A_CMP,la,R(rg[0]));}   /* no copy of a */
        else if(simple(b)){gen(a,rg,n);alu(A_CMP,R(rg[0]),opnd(b));}
        else if(n>=2&&(need(a)>=need(b)||has_call(a)||has_call(b))){gen(a,rg,n);gen(b,rg+1,n-1);alu(A_CMP,R(rg[0]),R(rg[1]));}
        else if(n>=2){gen(b,rg,n);gen(a,rg+1,n-1);alu(A_CMP,R(rg[1]),R(rg[0]));}
        else if(has_call(a)||has_call(b)){
            gen(a,rg,1);int sa=tslot_push();store(M(sa),rg[0]);gen(b,rg,1);int sb=tslot_push();store(M(sb),rg[0]);
            load(rg[0],M(sa));alu(A_CMP,R(rg[0]),M(sb));tdepth-=2;}
        else{gen(b,rg,1);int s=tslot_push();store(M(s),rg[0]);gen(a,rg,1);alu(A_CMP,R(rg[0]),M(s));tdepth--;}
        pl_add(list,jcc(sense?cc:cc^1));return;
    }
    if(x->k==N_VAR&&vars[x->var].reg>=0)test_rr(vars[x->var].reg);
    else{gen(e,rg,n);test_rr(rg[0]);}
    pl_add(list,jcc(sense?CC_NE:CC_E));
}

/* ------------------------------------------------- statement codegen */

static int brk_list[MAX_LOOPS],cont_list[MAX_LOOPS],nloopctx;
static int is_alu_op(int op){return op==O_ADD||op==O_SUB||op==O_AND||op==O_OR||op==O_XOR;}
/* x = f(x, ...) where x is the leftmost leaf of a chain of two-address ops and
 * no right operand reads x: evaluate the chain in x's own register. */
static int spine(int e,int v){
    Node *x=&nd[e];
    if(x->k==N_VAR)return x->var==v;
    if(x->k==N_UN)return spine(x->a,v);
    if(x->k!=N_BIN||x->op==O_LAND||x->op==O_LOR)return 0;
    if(!spine(x->a,v)&&commutes(x->op)&&spine(x->b,v)&&!refs(x->a,v)){int t=x->a;x->a=x->b;x->b=t;}
    return spine(x->a,v)&&!refs(x->b,v);
}
static void gen_inplace(int e,int r,const int *rg,int n){
    Node *x=&nd[e];
    if(x->k==N_VAR)return;
    gen_inplace(x->a,r,rg,n);
    if(x->k==N_UN){if(!(x->nn&&is_narrow(x->op)))apply_un(x->op,r);return;}
    if(simple(x->b)){div_nn=x->nn;apply(x->op,r,opnd(x->b));}else{gen(x->b,rg,n);apply(x->op,r,R(rg[0]));}
}
static void assign(int v,int e,const int *rg,int n){
    Opnd L=loc(v);Node *x=&nd[e];
    if(xroom(e)){
        if(L.k==K_REG)genf_root(e,L.r,rg,n);else{genf_root(e,RAX,rg,n);store(L,RAX);}
        return;
    }
    if(L.k==K_REG&&x->k!=N_VAR&&spine(e,v)){gen_inplace(e,L.r,rg,n);return;}
    if(x->k==N_BIN&&(is_alu_op(x->op)||x->op==O_MUL||x->op==O_SHL||x->op==O_SHR||x->op==O_SAR)){
        int a=x->a,b=x->b;
        if(commutes(x->op)&&!(nd[a].k==N_VAR&&nd[a].var==v)&&nd[b].k==N_VAR&&nd[b].var==v){int t=a;a=b;b=t;}
        if(nd[a].k==N_VAR&&nd[a].var==v&&!refs(b,v)){ /* x = x op b, in place */
            if(L.k==K_REG){
                if(simple(b))apply(x->op,L.r,opnd(b));else{gen(b,rg,n);apply(x->op,L.r,R(rg[0]));}
                return;
            }
            if(is_alu_op(x->op)){
                Opnd s;
                if(simple(b)){s=opnd(b);if(s.k==K_MEM){load(rg[0],s);s=R(rg[0]);}}
                else{gen(b,rg,n);s=R(rg[0]);}
                alu(x->op==O_ADD?A_ADD:x->op==O_SUB?A_SUB:x->op==O_AND?A_AND:x->op==O_OR?A_OR:A_XOR,L,s);
                return;
            }
        }
    }
    if(x->k==N_CONST){
        if(L.k==K_REG)mov_ri(L.r,x->v);
        else if(fits_s32(x->v)){enc(1,0,1,0xc7,0,0,L);u32((uint32_t)x->v);}
        else{mov_ri(RAX,x->v);store(L,RAX);}
        return;
    }
    if(x->k==N_VAR){
        Opnd s=loc(x->var);
        if(L.k==K_REG)load(L.r,s);else if(s.k==K_REG)store(L,s.r);else{load(RAX,s);store(L,RAX);}
        return;
    }
    if(L.k==K_REG&&!refs(e,v)){
        int r2[13];r2[0]=L.r;for(int i=0;i<n;i++)r2[i+1]=rg[i];
        gen(e,r2,n+1);return;
    }
    gen(e,rg,n);store(L,rg[0]);
}
/* Syscalls clobber rax, rcx, r11 and use rdi/rsi/rdx/r10/r8/r9 for arguments:
 * save every allocatable register that a syscall sequence touches. */
static void sys_save(void){EMIT(0x56,0x57,0x41,0x50,0x41,0x51,0x41,0x52,0x41,0x53);}
static void sys_restore(void){EMIT(0x41,0x5b,0x41,0x5a,0x41,0x59,0x41,0x58,0x5f,0x5e);}
static void trap_if(int cc){pl_add(&trap_list,jcc(cc));}
static void gen_arr(Node *x,const int *rg,int n){
    Var *a=&vars[x->var];int w=a->arr;
    if(x->op==A_STR){
        if(vars[a->basev].reads){
            Opnd b=loc(a->basev);int r=b.k==K_REG?b.r:RAX;
            if(r&8)byte(0x41);
            byte((uint8_t)(0xb8|(r&7)));str_site(clen,(size_t)x->v);u32(0);  /* mov r32,addr (patched) */
            if(b.k!=K_REG)store(b,RAX);
        }
        return;
    }
    if(x->op==A_VIEW){
        if(a->lenv>=0&&vars[a->lenv].reads){
            load(RAX,loc(vars[x->c].lenv));
            if(!(w&(w-1)))shift_ri(5,RAX,(unsigned)lg(w));else{mov_ri(RCX,(uint64_t)w);EMIT(0x31,0xd2);unop(6,R(RCX));}   /* bytes / stride */
            store(loc(a->lenv),RAX);
        }
        return;
    }
    if(x->op==A_ALLOC){
        int rs=-1;
        if(a->lenv>=0){
            gen(x->a,rg,n);rs=rg[0];
            mov_rr(RAX,rs);lea(RCX,RAX,-1,-1);alu(A_CMP,R(RCX),IMM(INT32_MAX-1));trap_if(0x7); /* ja: n<1 or n>2^31-1 */
        }else mov_ri(RAX,U(a->alen));
        if(!(w&(w-1)))shift_ri(4,RAX,(unsigned)lg(w));else imul_r(RAX,IMM((uint64_t)w));
        if(x->v){ /* arena: bump, bounds-check, zero */
            alu(A_ADD,R(RAX),IMM(15));alu(A_AND,R(RAX),IMM((uint64_t)-16));
            abs_op(0x8b,RCX,ARENA_TOP);lea(RDX,RCX,RAX,0);
            abs_op(0x3b,RDX,ARENA_END);trap_if(0x7);                  /* ja trap: arena exhausted */
            abs_op(0x89,RDX,ARENA_TOP);
            EMIT(0x57,0x48,0x89,0xcf,0x48,0x89,0xca,0x48,0x89,0xc1,0x31,0xc0,0xf3,0xaa,0x5f,0x48,0x89,0xd0); /* push rdi; rdi=rcx; rdx=rcx; rcx=rax; eax=0; rep stosb; pop rdi; rax=rdx */
            if(vars[a->basev].reads)store(loc(a->basev),RAX);
            if(a->lenv>=0&&vars[a->lenv].reads)store(loc(a->lenv),rs);
            return;
        }
        sys_save();
        EMIT(0x48,0x89,0xc6);                    /* mov rsi,rax: length in bytes */
        EMIT(0x31,0xff);                         /* xor edi,edi: addr = NULL */
        EMIT(0xba,0x03,0,0,0);                   /* mov edx,PROT_READ|PROT_WRITE */
        EMIT(0x41,0xba,(uint8_t)(a->shared?0x21:0x22),0,0,0); /* mov r10d,MAP_SHARED|MAP_PRIVATE + MAP_ANONYMOUS */
        EMIT(0x49,0xc7,0xc0,0xff,0xff,0xff,0xff);/* mov r8,-1 */
        EMIT(0x45,0x31,0xc9);                    /* xor r9d,r9d */
        EMIT(0xb8,0x09,0,0,0,0x0f,0x05);         /* mmap */
        sys_restore();
        EMIT(0x48,0x3d,0x00,0xf0,0xff,0xff);trap_if(0x7);   /* cmp rax,-4096; ja trap */
        if(vars[a->basev].reads)store(loc(a->basev),RAX);
        if(a->lenv>=0&&vars[a->lenv].reads)store(loc(a->lenv),rs);
        return;
    }
    /* A_FILE: map argv[k] read-only */
    gen(x->a,rg,n);int rk=rg[0];
    alu(A_CMP,R(rk),loc(0));trap_if(CC_AE);                  /* k < argc */
    load(RAX,loc(1));mov_rr(RCX,rk);memop(1,0,0,1,0x8b,0,RAX,RAX,RCX,3); /* rax = argv[k] */
    sys_save();
    EMIT(0x48,0x89,0xc7,0x31,0xf6,0xb8,0x02,0,0,0,0x0f,0x05);   /* open(path,O_RDONLY) */
    test_rr(RAX);trap_if(CC_S);
    EMIT(0x49,0x89,0xc0);                                     /* mov r8,rax (fd) */
    EMIT(0x48,0x89,0xc7,0x31,0xf6,0xba,0x02,0,0,0,0xb8,0x08,0,0,0,0x0f,0x05); /* lseek(fd,0,SEEK_END) */
    test_rr(RAX);trap_if(CC_S);
    EMIT(0x48,0x89,0xc6);                                     /* mov rsi,rax (size) */
    EMIT(0x31,0xc0);test_rr(RSI);size_t jz=jcc(CC_E);         /* empty file: base 0, len 0 */
    EMIT(0x31,0xff,0xba,0x01,0,0,0,0x41,0xba,0x02,0,0,0,0x45,0x31,0xc9,0xb8,0x09,0,0,0,0x0f,0x05); /* mmap RO private */
    EMIT(0x48,0x3d,0x00,0xf0,0xff,0xff);trap_if(0x7);
    rel32(jz,clen);
    EMIT(0x49,0x89,0xc1,0x4c,0x89,0xc7,0xb8,0x03,0,0,0,0x0f,0x05); /* r9=base; close(fd) */
    EMIT(0x4c,0x89,0xc8,0x48,0x89,0xf1);                      /* rax=base, rcx=size */
    sys_restore();
    if(vars[a->basev].reads)store(loc(a->basev),RAX);
    if(vars[a->lenv].reads)store(loc(a->lenv),RCX);
}
static int inl_list[MAX_LOOPS],ninlctx;
static int terminates(int s){
    if(s<0)return 0;
    switch(nd[s].k){
    case S_RET:case S_BRK:case S_CONT:case S_IRET:return 1;
    case S_BLOCK:{int last=-1;for(int c=nd[s].a;c>=0;c=nd[c].next)last=c;return terminates(last);}
    case S_IF:return nd[s].c>=0&&terminates(nd[s].b)&&terminates(nd[s].c);
    }
    return 0;
}
static void gen_stmt(int s,int is_final){
    Node *x=&nd[s];int rg[12],n=0;
    if(x->k!=S_BLOCK&&x->k!=S_BRK&&x->k!=S_CONT&&x->k!=S_INL)n=temps_at(x->pos,rg);
    switch(x->k){
    case S_LET:case S_ASSIGN:
        if(!vars[x->var].reads){if(has_trap(x->a))gen(x->a,rg,n);break;} /* keep traps */
        assign(x->var,x->a,rg,n);break;
    case S_IF:{
        if(is_const(x->a)){if(nd[x->a].v)gen_stmt(x->b,0);else if(x->c>=0)gen_stmt(x->c,0);break;}
        int f=-1,end=-1;cond_jump(x->a,0,&f,rg,n);gen_stmt(x->b,0);
        if(x->c>=0){if(!terminates(x->b))pl_add(&end,jmp());pl_patch(f,clen);gen_stmt(x->c,0);pl_patch(end,clen);}
        else pl_patch(f,clen);
        break;}
    case S_WHILE:{
        if(is_const(x->a)&&!nd[x->a].v)break;
        int entry=-1,back=-1;
        for(int v=0;v<nv;v++)if(vars[v].hoist==x->var+1&&vars[v].reg>=0)mov_ri(vars[v].reg,vars[v].cval);
        int m=x->c;   /* arena mark: scoped arrays of one iteration are released before the next */
        if(m>=0){abs_op(0x8b,RAX,ARENA_TOP);store(loc(m),RAX);}
        if(!is_const(x->a))pl_add(&entry,jmp());   /* rotated loop: test at bottom */
        size_t top=clen;int L=nloopctx++;brk_list[L]=cont_list[L]=-1;
        if(m>=0){load(RAX,loc(m));abs_op(0x89,RAX,ARENA_TOP);}
        gen_stmt(x->b,0);
        pl_patch(cont_list[L],clen);pl_patch(entry,clen);
        cond_jump(x->a,1,&back,rg,n);pl_patch(back,top);
        pl_patch(brk_list[L],clen);nloopctx--;
        if(m>=0){load(RAX,loc(m));abs_op(0x89,RAX,ARENA_TOP);}
        break;}
    case S_RET:
        if(nd[x->a].k==N_CONST||nd[x->a].k==N_VAR)load(RAX,opnd(x->a));
        else{gen(x->a,rg,n);mov_rr(RAX,rg[0]);}
        if(!is_final)pl_add(&fns[curfn].exit_list,jmp());
        break;
    case S_EXPR:gen(x->a,rg,n);break;
    case S_WRITE:
        if(x->var<0){ /* string literal */
            byte(0xb8);str_site(clen,(size_t)x->v);u32(0);          /* mov eax,addr (patched) */
            EMIT(0xb9);u32((uint32_t)x->c);                         /* mov ecx,len */
        }else if(x->a<0){
            Var *v=&vars[x->var];
            load_base(RAX,x->var);
            if(v->lenv<0)mov_ri(RCX,U(v->alen));else load(RCX,loc(v->lenv));
        }else{ /* 0 <= off <= len, 0 <= n <= len - off (unsigned compares catch negatives) */
            Var *v=&vars[x->var];
            gen(x->a,rg,n);gen(x->b,rg+1,n-1);
            int ro=rg[0],rn=rg[1];
            Opnd L=v->lenv<0?IMM(U(v->alen)):loc(v->lenv);
            alu(A_CMP,R(ro),L);pl_add(&trap_list,jcc(0x7));         /* off > len: ja trap */
            if(L.k==K_IMM)mov_ri(RAX,L.imm);else load(RAX,L);
            alu(A_SUB,R(RAX),R(ro));alu(A_CMP,R(rn),R(RAX));pl_add(&trap_list,jcc(0x7));
            load_base(RAX,x->var);alu(A_ADD,R(RAX),R(ro));mov_rr(RCX,rn);
        }
        byte(0xe8);pl_add(&write_calls,clen);u32(0);
        break;
    case S_STORE:{
        int fs=x->c>=0;   /* struct field store */
        int rv,w=fs?ty_width(sts[vars[x->var].et-TY_STRUCT0].fty[x->c]):vars[x->var].arr,val=x->b;const int *ir=rg;int in=n;
        /* the store keeps the low w bytes: an explicit `as` to a width >= w is free */
        while(nd[val].k==N_UN&&ext_width(nd[val].op)>=w)val=nd[val].a;
        if(nd[val].k==N_VAR&&vars[nd[val].var].reg>=0){rv=vars[nd[val].var].reg;}
        else{gen(val,rg,n);rv=rg[0];ir=rg+1;in=n-1;}
        int b,ri,sc;elem_addr(x->var,x->a,x->chk,fs?sts[vars[x->var].et-TY_STRUCT0].foff[x->c]:0,ir,in,&b,&ri,&sc);
        int dig=x->op<0?-1:x->op==O_ADD?A_ADD:x->op==O_SUB?A_SUB:x->op==O_AND?A_AND:x->op==O_OR?A_OR:A_XOR;
        store_elem(w,dig,rv,b,ri,sc);
        break;}
    case S_PRINT:case S_PUTC:
        if(simple(x->a))load(RAX,opnd(x->a));else{gen(x->a,rg,n);mov_rr(RAX,rg[0]);}
        if(x->k==S_PUTC&&x->op==1){ /* exit(code) */
            EMIT(0x50);if(use_out)call_to(&flush_calls);EMIT(0x5f,0xb8,0xe7,0,0,0,0x0f,0x05);   /* push; flush; pop rdi; exit_group */
            break;
        }
        byte(0xe8);pl_add(x->k==S_PUTC?&putc_calls:x->op?&printu_calls:&print_calls,clen);u32(0);   /* call */
        break;
    case S_ARR:gen_arr(x,rg,n);break;
    case S_SAVE:{ /* open(argv[k], O_WRONLY|O_CREAT|O_TRUNC, 0755); write all n bytes; close */
        Var *v=&vars[x->var];
        gen(x->a,rg,n);gen(x->b,rg+1,n-1);int rk=rg[0],rn=rg[1];
        alu(A_CMP,R(rk),loc(0));trap_if(CC_AE);                                     /* k < argc */
        alu(A_CMP,R(rn),v->lenv<0?IMM(U(v->alen)):loc(v->lenv));trap_if(0x7);       /* n <= len (unsigned) */
        load_base(RAX,x->var);mov_rr(RDX,RAX);                                 /* rdx = data */
        load(RAX,loc(1));mov_rr(RCX,rk);memop(1,0,0,1,0x8b,0,RAX,RAX,RCX,3);       /* rax = argv[k] */
        mov_rr(RCX,rn);
        sys_save();
        EMIT(0x49,0x89,0xd2,0x49,0x89,0xc9);                                        /* r10 = data; r9 = n */
        EMIT(0x48,0x89,0xc7,0xbe,0x41,0x02,0,0,0xba,0xed,0x01,0,0,0xb8,0x02,0,0,0,0x0f,0x05); /* open */
        test_rr(RAX);trap_if(CC_S);
        EMIT(0x49,0x89,0xc0);                                                       /* r8 = fd */
        size_t top=clen;EMIT(0x4d,0x85,0xc9);size_t done=j8(0x74);
        EMIT(0x4c,0x89,0xc7,0x4c,0x89,0xd6,0x4c,0x89,0xca,0xb8,0x01,0,0,0,0x0f,0x05); /* write(fd, r10, r9) */
        test_rr(RAX);trap_if(CC_LE);
        EMIT(0x49,0x01,0xc2,0x49,0x29,0xc1);p8(j8(0xeb),top);                      /* advance */
        p8(done,clen);
        EMIT(0x4c,0x89,0xc7,0xb8,0x03,0,0,0,0x0f,0x05);                             /* close */
        sys_restore();
        break;}
    case S_BRK:pl_add(&brk_list[nloopctx-1],jmp());break;
    case S_IRET:if(vars[x->var].reads)assign(x->var,x->a,rg,n);else if(has_trap(x->a))gen(x->a,rg,n);pl_add(&inl_list[ninlctx-1],jmp());break;
    case S_PAR:{
        Opnd K=loc(x->var),E=loc(x->op);
        assign(x->var,x->a,rg,n);assign(x->op,x->b,rg,n);
        load(RAX,E);alu(A_SUB,R(RAX),K);alu(A_CMP,R(RAX),IMM(256));pl_add(&trap_list,jcc(CC_G)); /* at most 256 workers */
        size_t top=clen;
        load(RAX,K);alu(A_CMP,R(RAX),E);size_t done=jcc(CC_GE);
        sys_save();EMIT(0xb8,0x39,0,0,0,0x0f,0x05);sys_restore();           /* fork */
        test_rr(RAX);pl_add(&trap_list,jcc(CC_S));size_t child=jcc(CC_E);
        alu(A_ADD,K,IMM(1));rel32(jmp(),top);
        rel32(child,clen);                                                   /* worker */
        if(use_out){EMIT(0x48,0xc7,0x04,0x25);u32(OUT_LEN);u32(0);}          /* drop inherited unflushed output */
        gen_stmt(x->c,0);
        EMIT(0x31,0xff,0xb8,0xe7,0,0,0,0x0f,0x05);                           /* exit_group(0) */
        rel32(done,clen);                                                    /* parent: reap every worker */
        size_t wl=clen;
        sys_save();
        EMIT(0x48,0xc7,0xc7,0xff,0xff,0xff,0xff,0xbe);u32(PAR_STATUS);       /* rdi=-1; esi=&status */
        EMIT(0x31,0xd2,0x45,0x31,0xd2,0xb8,0x3d,0,0,0,0x0f,0x05);            /* wait4(-1,&st,0,0) */
        sys_restore();
        test_rr(RAX);size_t fin=jcc(CC_S);                                   /* ECHILD: all reaped */
        EMIT(0x8b,0x04,0x25);u32(PAR_STATUS);EMIT(0x85,0xc0);                /* status != 0: a worker failed */
        size_t okw=j8(0x74);EMIT(0xc6,0x04,0x25);u32(PAR_FAIL);byte(1);p8(okw,clen);
        rel32(jmp(),wl);
        rel32(fin,clen);
        EMIT(0x80,0x3c,0x25);u32(PAR_FAIL);byte(0);pl_add(&trap_list,jcc(CC_NE));
        break;}
    case S_INL:{
        int L=ninlctx++;inl_list[L]=-1;
        for(int c=x->a;c>=0;c=nd[c].next)gen_stmt(c,0);
        pl_patch(inl_list[L],clen);ninlctx--;break;}
    case S_CONT:pl_add(&cont_list[nloopctx-1],jmp());break;
    case S_BLOCK:
        for(int c=x->a;c>=0;c=nd[c].next)gen_stmt(c,is_final&&nd[c].next<0);
        break;
    }
}
static void print_body(void){
    /* RAX = signed i64 -> decimal + newline via SYS_write(1). Uses 48 bytes of stack. */
    EMIT(0x48,0x83,0xec,0x30);           /* sub rsp, 48 */
    EMIT(0x48,0x8d,0x74,0x24,0x2f);     /* lea rsi, [rsp+47] */
    EMIT(0xc6,0x06,0x0a);                /* mov byte [rsi], '\n' */
    EMIT(0xb9,0x01,0x00,0x00,0x00);     /* mov ecx, 1 */
    EMIT(0x45,0x31,0xc9);                /* xor r9d, r9d */
    EMIT(0x48,0x85,0xc0);                /* test rax,rax */
    EMIT(0x0f,0x89);size_t jns=clen;u32(0);
    EMIT(0x41,0xb9,0x01,0x00,0x00,0x00);/* mov r9d,1 */
    EMIT(0x48,0xf7,0xd8);                /* neg rax */
    rel32(jns,clen);
    EMIT(0x48,0xc7,0xc3,0x0a,0,0,0);    /* mov rbx,10 */
    size_t loop=clen;
    EMIT(0x31,0xd2);                     /* xor edx,edx */
    EMIT(0x48,0xf7,0xf3);                /* div rbx */
    EMIT(0x80,0xc2,0x30);                /* add dl,'0' */
    EMIT(0x48,0xff,0xce);                /* dec rsi */
    EMIT(0x88,0x16);                     /* mov [rsi],dl */
    EMIT(0x48,0xff,0xc1);                /* inc rcx */
    EMIT(0x48,0x85,0xc0);                /* test rax,rax */
    EMIT(0x0f,0x85);size_t jne=clen;u32(0);rel32(jne,loop);
    EMIT(0x45,0x85,0xc9);                /* test r9d,r9d */
    EMIT(0x0f,0x84);size_t je=clen;u32(0);
    EMIT(0x48,0xff,0xce);                /* dec rsi */
    EMIT(0xc6,0x06,0x2d);                /* mov byte [rsi],'-' */
    EMIT(0x48,0xff,0xc1);                /* inc rcx */
    rel32(je,clen);
    EMIT(0x48,0x89,0xca);                /* mov rdx,rcx */
    EMIT(0xb8,0x01,0,0,0);              /* mov eax,1 / SYS_write */
    EMIT(0xbf,0x01,0,0,0);              /* mov edi,1 / stdout */
    EMIT(0x0f,0x05);                     /* syscall */
}
static void print_signed_and_exit(void){
    print_body();
    EMIT(0x31,0xff);                     /* xor edi,edi */
    EMIT(0xb8,0x3c,0,0,0);              /* mov eax,60 / SYS_exit */
    EMIT(0x0f,0x05);                     /* syscall */
}
/* Buffered stdout runtime. A separate RW, non-executable PT_LOAD (bss) holds
 * the buffer; it is flushed at exit, before a bounds trap (ud2), and by a
 * SIGFPE handler, so output written before any trap is never lost.
 * All subroutines preserve every register except RAX/RCX/RDX (scratch). */
static size_t handler_imm_at,restorer_imm_at,handler_off;
static void call_to(int *list){byte(0xe8);pl_add(list,clen);u32(0);}
static void emit_ncpu(void){ /* rax = CPUs in this process's affinity mask (>= 1) */
    if(ncpu_calls<0)return;
    pl_patch(ncpu_calls,clen);
    EMIT(0x56,0x57,0x41,0x53,0x41,0x50,0x48,0x81,0xec,0x80,0,0,0);      /* push rsi,rdi,r11,r8; sub rsp,128 */
    EMIT(0x31,0xff,0xbe,0x80,0,0,0,0x48,0x89,0xe2,0xb8,0xcc,0,0,0,0x0f,0x05); /* sched_getaffinity(0,128,rsp) */
    EMIT(0x45,0x31,0xc0,0x48,0x85,0xc0);size_t le=j8(0x7e);              /* r8=0; if rax<=0 -> done */
    EMIT(0x48,0x89,0xc1,0x48,0xc1,0xe9,0x03,0x48,0x89,0xe6);             /* rcx=qwords; rsi=rsp */
    size_t lq=clen;EMIT(0x48,0x85,0xc9);size_t zq=j8(0x74);
    EMIT(0x48,0x8b,0x16);
    size_t lb=clen;EMIT(0x48,0x85,0xd2);size_t nq=j8(0x74);
    EMIT(0x48,0x8d,0x7a,0xff,0x48,0x21,0xfa,0x49,0xff,0xc0);p8(j8(0xeb),lb); /* clear lowest bit; count */
    p8(nq,clen);EMIT(0x48,0x83,0xc6,0x08,0x48,0xff,0xc9);p8(j8(0xeb),lq);
    p8(zq,clen);p8(le,clen);
    EMIT(0x4c,0x89,0xc0,0x48,0x85,0xc0,0x75,0x05,0xb8,0x01,0,0,0);       /* rax = max(count,1) */
    EMIT(0x48,0x81,0xc4,0x80,0,0,0,0x41,0x58,0x41,0x5b,0x5f,0x5e,0xc3);
}
/* numeric conversion subroutines: rax in, rax out; clobber rcx, xmm0, xmm1 */
static void emit_convert(void){
    if(u2d_calls>=0||u2s_calls>=0)for(int k=0;k<2;k++){
        int *list=k?&u2s_calls:&u2d_calls;if(*list<0)continue;
        uint8_t p=k?0xf3:0xf2;
        pl_patch(*list,clen);
        EMIT(0x48,0x85,0xc0);size_t big=j8(0x78);                          /* test rax,rax; js big */
        EMIT(0x66,0x0f,0xef,0xc0,p,0x48,0x0f,0x2a,0xc0);                   /* pxor; cvtsi2s? xmm0,rax */
        fstore(RAX,0,!k);byte(0xc3);
        p8(big,clen);                                                      /* halve, keep the sticky bit */
        EMIT(0x48,0x89,0xc1,0x48,0xd1,0xe9,0x83,0xe0,0x01,0x48,0x09,0xc1);
        EMIT(0x66,0x0f,0xef,0xc0,p,0x48,0x0f,0x2a,0xc1,p,0x0f,0x58,0xc0);  /* cvt xmm0,rcx; add xmm0,xmm0 */
        fstore(RAX,0,!k);byte(0xc3);
    }
    if(d2u_calls>=0||s2u_calls>=0){ /* saturating float -> u64, NaN -> 0 */
        size_t jb=0;
        if(s2u_calls>=0){pl_patch(s2u_calls,clen);EMIT(0x66,0x0f,0x6e,0xc0,0xf3,0x0f,0x5a,0xc0);jb=j8(0xeb);} /* movd; cvtss2sd */
        if(d2u_calls>=0)pl_patch(d2u_calls,clen);
        EMIT(0x66,0x48,0x0f,0x6e,0xc0);                                     /* movq xmm0,rax */
        if(s2u_calls>=0)p8(jb,clen);
        EMIT(0x66,0x0f,0x2e,0xc0);size_t z1=j8(0x7a);                      /* NaN */
        EMIT(0x66,0x0f,0xef,0xc9,0x66,0x0f,0x2e,0xc1);size_t z2=j8(0x76);  /* x <= 0 */
        mov_ri(RAX,0x43F0000000000000ULL);EMIT(0x66,0x48,0x0f,0x6e,0xc8,0x66,0x0f,0x2e,0xc1);size_t mxj=j8(0x73); /* >= 2^64 */
        mov_ri(RAX,0x43E0000000000000ULL);EMIT(0x66,0x48,0x0f,0x6e,0xc8,0x66,0x0f,0x2e,0xc1);size_t hi=j8(0x73);  /* >= 2^63 */
        EMIT(0xf2,0x48,0x0f,0x2c,0xc0,0xc3);
        p8(hi,clen);EMIT(0xf2,0x0f,0x5c,0xc1,0xf2,0x48,0x0f,0x2c,0xc0,0x48,0x0f,0xba,0xf8,0x3f,0xc3);  /* -2^63, cvt, +2^63 */
        p8(mxj,clen);EMIT(0x48,0xc7,0xc0,0xff,0xff,0xff,0xff,0xc3);
        p8(z1,clen);p8(z2,clen);EMIT(0x31,0xc0,0xc3);
    }
}
static void emit_print(int *list,int uns){ /* rax = value -> decimal + '\n' */
        pl_patch(*list,clen);
        EMIT(0x53,0x56,0x57,0x41,0x51);                       /* push rbx,rsi,rdi,r9 */
        EMIT(0x48,0x83,0xec,0x30,0x48,0x8d,0x74,0x24,0x2f,0xc6,0x06,0x0a); /* sub rsp,48; lea rsi,[rsp+47]; '\n' */
        EMIT(0xbf,0x01,0,0,0,0x45,0x31,0xc9);                 /* edi=1 (count); r9d=0 */
        size_t a;
        if(!uns){EMIT(0x48,0x85,0xc0);a=j8(0x79);EMIT(0x41,0xb9,0x01,0,0,0,0x48,0xf7,0xd8);p8(a,clen);} /* if neg: r9d=1; neg rax */
        EMIT(0x48,0xc7,0xc3,0x0a,0,0,0);                      /* mov rbx,10 */
        size_t loop=clen;
        EMIT(0x31,0xd2,0x48,0xf7,0xf3,0x80,0xc2,0x30,0x48,0xff,0xce,0x88,0x16,0x48,0xff,0xc7,0x48,0x85,0xc0);
        p8(j8(0x75),loop);
        EMIT(0x45,0x85,0xc9);a=j8(0x74);EMIT(0x48,0xff,0xce,0xc6,0x06,0x2d,0x48,0xff,0xc7);p8(a,clen);
        size_t em=clen;
        EMIT(0x0f,0xb6,0x06);call_to(&putc_calls);EMIT(0x48,0xff,0xc6,0x48,0xff,0xcf);p8(j8(0x75),em);
        EMIT(0x48,0x83,0xc4,0x30,0x41,0x59,0x5f,0x5e,0x5b,0xc3);
}
static void emit_runtime(void){
    emit_ncpu();
    emit_convert();
    if(!use_out){if(trap_list>=0){pl_patch(trap_list,clen);EMIT(0x0f,0x0b);}return;}
    if(print_calls>=0)emit_print(&print_calls,0);
    if(printu_calls>=0)emit_print(&printu_calls,1);
    if(write_calls>=0){ /* write_sub: rax = ptr, rcx = count */
        pl_patch(write_calls,clen);
        EMIT(0x56,0x57,0x48,0x89,0xc6,0x48,0x89,0xcf);          /* push rsi,rdi; rsi=ptr; rdi=n */
        size_t top=clen;EMIT(0x48,0x85,0xff);size_t z=j8(0x74);
        EMIT(0x0f,0xb6,0x06);call_to(&putc_calls);EMIT(0x48,0xff,0xc6,0x48,0xff,0xcf);
        p8(j8(0xeb),top);p8(z,clen);
        EMIT(0x5f,0x5e,0xc3);
    }
    /* putc_sub: al = byte */
    pl_patch(putc_calls,clen);
    EMIT(0x48,0x8b,0x0c,0x25);u32(OUT_LEN);                    /* mov rcx,[len] */
    EMIT(0x88,0x81);u32(OUT_BUF);                              /* mov [rcx+buf],al */
    EMIT(0x48,0xff,0xc1,0x48,0x89,0x0c,0x25);u32(OUT_LEN);     /* inc rcx; mov [len],rcx */
    EMIT(0x48,0x81,0xf9);u32(OUT_CAP);
    {size_t a=j8(0x72);call_to(&flush_calls);p8(a,clen);}
    byte(0xc3);
    /* flush_sub (call sites are linked at the end: some are emitted after it) */
    size_t flush_at=clen;
    EMIT(0x56,0x57,0x41,0x53,0x48,0x8b,0x14,0x25);u32(OUT_LEN); /* push rsi,rdi,r11; rdx=len */
    byte(0xbe);u32(OUT_BUF);                                   /* esi=buf */
    {size_t top=clen;EMIT(0x48,0x85,0xd2);size_t z=j8(0x74);
     EMIT(0xbf,0x01,0,0,0,0xb8,0x01,0,0,0,0x0f,0x05,0x48,0x85,0xc0);size_t e=j8(0x7e);
     EMIT(0x48,0x01,0xc6,0x48,0x29,0xc2);p8(j8(0xeb),top);p8(z,clen);p8(e,clen);}
    EMIT(0x48,0xc7,0x04,0x25);u32(OUT_LEN);u32(0);
    EMIT(0x41,0x5b,0x5f,0x5e,0xc3);
    /* SIGFPE handler: flush, exit(136) */
    handler_off=clen;
    call_to(&flush_calls);EMIT(0xbf,0x88,0,0,0,0xb8,0xe7,0,0,0,0x0f,0x05);
    if(trap_list>=0){pl_patch(trap_list,clen);call_to(&flush_calls);EMIT(0x0f,0x0b);} /* flush; ud2 */
    pl_patch(flush_calls,flush_at);
}
static void generate(void){
    allocate();
    /* Linux entry: [rsp] = argc, rsp 16-byte aligned. No push, so the frame
     * (a multiple of 16) keeps rsp 16-aligned for future calls (review D9). */
    for(int i=0;i<nn;i++)if(nd[i].k==S_PRINT||(nd[i].k==S_PUTC&&nd[i].op!=1)||nd[i].k==S_WRITE)use_out=1;
    use_bss=use_out||use_arena||glob_bytes>0;for(int i=0;i<nn;i++)if(nd[i].k==S_PAR)use_bss=1;
    if(use_arena){ /* reserve the scoped-allocation arena (pages are committed on touch) */
        EMIT(0x31,0xff,0x48,0xbe);u64(1ULL<<34);                          /* rdi=0; rsi=16 GiB */
        EMIT(0xba,0x03,0,0,0,0x41,0xba,0x22,0x40,0,0,0x49,0xc7,0xc0,0xff,0xff,0xff,0xff,0x45,0x31,0xc9,0xb8,0x09,0,0,0,0x0f,0x05);
        EMIT(0x48,0x3d,0x00,0xf0,0xff,0xff);trap_if(0x7);
        abs_op(0x89,RAX,ARENA_TOP);alu(A_ADD,R(RAX),R(RSI));abs_op(0x89,RAX,ARENA_END);
    }
    if(use_out){ /* rt_sigaction(SIGFPE, {handler,0,0,0}, NULL, 8) */
        EMIT(0x48,0xc7,0x04,0x25);u32(SIG_ACT);handler_imm_at=clen;u32(0);
        /* x86-64 requires SA_RESTORER for frame setup; the handler never returns */
        EMIT(0x48,0xc7,0x04,0x25);u32(SIG_ACT+8);u32(0x04000000);
        EMIT(0x48,0xc7,0x04,0x25);u32(SIG_ACT+16);restorer_imm_at=clen;u32(0);
        EMIT(0xbf,0x08,0,0,0,0xbe);u32(SIG_ACT);
        EMIT(0x31,0xd2,0x41,0xba,0x08,0,0,0,0xb8,0x0d,0,0,0,0x0f,0x05);
    }
    int argc_used=vars[0].reads>0,argv_used=vars[1].reads>0;
    if(argc_used)load(vars[0].reg>=0?vars[0].reg:RAX,M(0));   /* argc = [rsp] */
    if(argv_used)lea(vars[1].reg>=0?vars[1].reg:RDX,RSP,-1,8); /* argv = rsp+8 */
    size_t frame_at=clen;EMIT(0x48,0x81,0xec);u32(0); /* sub rsp,imm32 (patched) */
    if(argc_used&&vars[0].reg<0)store(loc(0),RAX);
    if(argv_used&&vars[1].reg<0)store(loc(1),RDX);
    tbase=nslots;
    curfn=mainfn;
    gen_stmt(body,1);
    pl_patch(fns[mainfn].exit_list,clen);
    int unit_main=fns[mainfn].rett==TY_UNIT;   /* main without a result prints nothing at exit */
    if(use_out){
        if(!unit_main)call_to(&print_calls);
        call_to(&flush_calls);
        EMIT(0x31,0xff,0xb8,0x3c,0,0,0,0x0f,0x05);   /* exit(0) */
    }else if(!unit_main)print_signed_and_exit();
    else EMIT(0x31,0xff,0xb8,0x3c,0,0,0,0x0f,0x05);
    /* other functions: entry rsp -> rax; [rax+8+8k] = argument word k */
    size_t fsites[2*MAX_FUNCS];int nfs=0,nfuncs=0;
    for(int f=0;f<nfn;f++){
        if(f==mainfn||!fns[f].used)continue;
        nfuncs++;curfn=f;fns[f].addr=clen;
        EMIT(0x48,0x89,0xe0);                               /* mov rax,rsp */
        EMIT(0x48,0x81,0xec);fsites[nfs++]=clen;u32(0);     /* sub rsp,frame */
        for(int i=0,w=0;i<fns[f].np;i++){
            int v=fns[f].pvar[i],ids[2]={v,-1};
            if(fns[f].pw[i]){ids[0]=vars[v].basev;ids[1]=vars[v].lenv;}
            for(int k=0;k<(fns[f].pw[i]?2:1);k++,w++){
                int id=ids[k];if(!vars[id].reads)continue;
                Opnd L=loc(id);int r=L.k==K_REG?L.r:RCX;
                int disp=8+8*w;   /* mov r,[rax+disp] */
                byte((uint8_t)(0x48|((r&8)?4:0)));byte(0x8b);
                if(disp<128){byte((uint8_t)(0x40|((r&7)<<3)));byte((uint8_t)disp);}
                else{byte((uint8_t)(0x80|((r&7)<<3)));u32((uint32_t)disp);}
                if(L.k!=K_REG)store(L,RCX);
            }
        }
        if(fns[f].mark>=0){abs_op(0x8b,RCX,ARENA_TOP);store(loc(fns[f].mark),RCX);}   /* arena mark at entry */
        gen_stmt(fns[f].body,1);
        pl_patch(fns[f].exit_list,clen);
        if(fns[f].mark>=0){load(RCX,loc(fns[f].mark));abs_op(0x89,RCX,ARENA_TOP);}    /* release (rax = result) */
        EMIT(0x48,0x81,0xc4);fsites[nfs++]=clen;u32(0);     /* add rsp,frame */
        byte(0xc3);
    }
    for(int f=0;f<nfn;f++)if(fns[f].used&&f!=mainfn)pl_patch(fns[f].calls,fns[f].addr);
    emit_runtime();
    uint32_t frame=(uint32_t)(((uint64_t)(nslots+tmax)*8+15)&~15ULL);
    size_t shift=0;
    for(int i=0;i<nfs;i++)patch32(fsites[i],(int32_t)frame);
    if(frame||nfuncs)patch32(frame_at+3,(int32_t)frame);
    else{ /* no frame: drop the 7-byte sub. Every branch/call is rel32 between
           * instructions after frame_at, so a uniform shift preserves them. */
        memmove(code+frame_at,code+frame_at+7,clen-frame_at-7);clen-=7;shift=7;
    }
    if(handler_off>frame_at)handler_off-=shift;
    for(int i=0;i<nss;i++)if(ss_at[i]>frame_at)ss_at[i]-=shift;
    /* read-only string data after the code (same RX segment) */
    size_t data_at=clen;
    for(size_t i=0;i<sdlen;i++)byte(sdata[i]);
    for(int i=0;i<nss;i++)patch32(ss_at[i],(int32_t)(0x400000+256+data_at+ss_off[i]));
    if(use_out){patch32(handler_imm_at,(int32_t)(0x400000+256+handler_off));patch32(restorer_imm_at,(int32_t)(0x400000+256+handler_off));}
}

/* ------------------------------------------------- ELF64 writer */
static void at16(uint8_t *o,size_t n,uint16_t v){o[n]=(uint8_t)v;o[n+1]=(uint8_t)(v>>8);}
static void at32(uint8_t *o,size_t n,uint32_t v){for(int i=0;i<4;i++)o[n+i]=(uint8_t)(v>>(8*i));}
static void at64(uint8_t *o,size_t n,uint64_t v){for(int i=0;i<8;i++)o[n+i]=(uint8_t)(v>>(8*i));}
static void write_elf(const char *name){
    const size_t offset=256,total=offset+clen;
    uint8_t *out=calloc(total,1);if(!out){perror("calloc");exit(1);}
    out[0]=0x7f;out[1]='E';out[2]='L';out[3]='F';out[4]=2;out[5]=1;out[6]=1;
    at16(out,16,2);at16(out,18,62);at32(out,20,1);
    at64(out,24,0x400000+offset);at64(out,32,64);
    at16(out,52,64);at16(out,54,56);at16(out,56,use_bss?3:2);
    size_t ph=64;                               /* PT_LOAD R+X */
    at32(out,ph,1);at32(out,ph+4,5);
    at64(out,ph+8,0);at64(out,ph+16,0x400000);at64(out,ph+24,0x400000);
    at64(out,ph+32,total);at64(out,ph+40,total);at64(out,ph+48,0x1000);
    ph=120;at32(out,ph,0x6474e551);at32(out,ph+4,6);at64(out,ph+48,16); /* GNU_STACK RW */
    if(use_bss){ /* PT_LOAD RW (no X): zero-filled bss for the output buffer and par status */
        ph=176;at32(out,ph,1);at32(out,ph+4,6);at64(out,ph+8,0);at64(out,ph+16,BSS);at64(out,ph+24,BSS);
        at64(out,ph+32,0);at64(out,ph+40,(uint64_t)BSS_FIXED+(uint64_t)glob_bytes);at64(out,ph+48,0x1000);
    }
    memcpy(out+offset,code,clen);
    FILE *f=fopen(name,"wb");if(!f){perror(name);free(out);exit(1);}
    if(fwrite(out,1,total,f)!=total){perror("write ELF");fclose(f);free(out);exit(1);}
    if(fclose(f)){perror("close ELF");free(out);exit(1);}
    if(chmod(name,0755)){perror("chmod");free(out);exit(1);}
    free(out);
    printf("skite: wrote %s (%zu bytes, %zu machine-code bytes, %d vars, %d spills, %d peak registers, %d/%d bounds checks elided, %d modulo reduced, %d calls inlined)\n",
           name,total,clen,nv-2,spilled,peak_active,nelided,nchecks,nsr,ninlined+ninl_stmt);
}
static char *read_source(const char *path){
    FILE *f=fopen(path,"rb");if(!f){perror(path);exit(1);}
    if(fseek(f,0,SEEK_END)){perror("fseek");exit(1);}
    long n=ftell(f);if(n<0||n>1048576){fprintf(stderr,"invalid source file size\n");exit(1);}
    rewind(f);char *s=malloc((size_t)n+1);if(!s){perror("malloc");exit(1);}
    if(fread(s,1,(size_t)n,f)!=(size_t)n){perror("fread");exit(1);}
    fclose(f);
    if(memchr(s,0,(size_t)n)){fprintf(stderr,"skite: source contains NUL byte\n");exit(1);}
    s[n]=0;return s;
}
int main(int argc,char **argv){
    if(argc!=3){fprintf(stderr,"Usage: %s input.cock output-executable\n",argv[0]);return 2;}
    char *input=read_source(argv[1]);source=input;pos=source;srcname=argv[1];
    parse();generate();write_elf(argv[2]);free(input);
    return 0;
}
