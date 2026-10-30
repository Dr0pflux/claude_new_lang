// skite: the skite compiler written in skite (self-hosted).
// A faithful port of the C seed (skite.c): it creates AST nodes and variables
// in the same order, so for the same input both compilers emit identical bytes.
// usage: skite input.ck output-executable

// ---------------------------------------------------------------- limits
let MAX_NODES = 1048576;
let MAX_VARS = 65536;
let MAX_BYTES = 16777216;
let MAX_DEPTH = 256;
let MAX_LOOPS = 65536;
let MAX_PAIRS = 1048576;
let MAX_PATCH = 1048576;
let MAX_ACTIVE = 10;
let MAX_SDATA = 1048576;
let MAX_FUNCS = 4096;
let MAX_PARAMS = 16;
let MAX_STRUCTS = 64;
let MAX_FIELDS = 32;
let SRC_MAX = 2200000;

// ---------------------------------------------------------------- tokens
let T_EOF = 256; let T_ID = 257; let T_NUM = 258; let T_ARROW = 259; let T_FN = 260;
let T_LET = 261; let T_MUT = 262; let T_RETURN = 263; let T_IF = 264; let T_ELSE = 265;
let T_WHILE = 266; let T_BREAK = 267; let T_CONTINUE = 268; let T_EQ = 269; let T_NE = 270;
let T_LE = 271; let T_GE = 272; let T_SHL = 273; let T_SHR = 274; let T_SHRU = 275;
let T_LAND = 276; let T_LOR = 277; let T_OPEQ = 278; let T_STR = 279; let T_PAR = 280;
let T_IN = 281; let T_DOTDOT = 282; let T_AS = 283; let T_TRUE = 284; let T_FALSE = 285;
let T_FNUM = 286; let T_STRUCT = 287; let T_FOR = 288; let T_LOOP = 289; let T_CONST = 290;
let T_DOTDOTEQ = 291;

// ---------------------------------------------------------------- operators
let O_ADD = 0; let O_SUB = 1; let O_MUL = 2; let O_DIV = 3; let O_MOD = 4; let O_AND = 5;
let O_OR = 6; let O_XOR = 7; let O_SHL = 8; let O_SHR = 9; let O_SAR = 10; let O_DIVU = 11;
let O_MODU = 12; let O_EQ = 13; let O_NE = 14; let O_LT = 15; let O_LE = 16; let O_GT = 17;
let O_GE = 18; let O_LTU = 19; let O_LEU = 20; let O_GTU = 21; let O_GEU = 22; let O_LAND = 23;
let O_LOR = 24; let O_FADD = 25; let O_FSUB = 26; let O_FMUL = 27; let O_FDIV = 28; let O_FEQ = 29;
let O_FNE = 30; let O_FLT = 31; let O_FLE = 32; let O_FGT = 33; let O_FGE = 34; let O_GADD = 35;
let O_GSUB = 36; let O_GMUL = 37; let O_GDIV = 38; let O_GEQ = 39; let O_GNE = 40; let O_GLT = 41;
let O_GLE = 42; let O_GGT = 43; let O_GGE = 44;
let U_NEG = 45; let U_NOT = 46; let U_LNOT = 47; let U_SX8 = 48; let U_SX16 = 49; let U_SX32 = 50;
let U_ZX8 = 51; let U_ZX16 = 52; let U_ZX32 = 53; let U_SATS8 = 54; let U_SATS16 = 55; let U_SATS32 = 56;
let U_SATU8 = 57; let U_SATU16 = 58; let U_SATU32 = 59; let U_FNEG = 60; let U_GNEG = 61; let U_I2D = 62;
let U_U2D = 63; let U_I2S = 64; let U_U2S = 65; let U_D2I = 66; let U_D2U = 67; let U_S2I = 68;
let U_S2U = 69; let U_D2S = 70; let U_S2D = 71; let U_SQRTD = 72; let U_SQRTS = 73;

fn is_fop(op: i64) -> bool { return op >= O_FADD && op <= O_GGE; }
fn is_fcmp(op: i64) -> bool { return (op >= O_FEQ && op <= O_FGE) || (op >= O_GEQ && op <= O_GGE); }
fn fop_dbl(op: i64) -> bool { return op <= O_FGE; }
fn fop_base(op: i64) -> i64 { if op >= O_GADD { return op - (O_GADD - O_FADD); } return op; }
fn is_cmp_op(op: i64) -> bool { return op >= O_EQ && op <= O_GEU; }

// ---------------------------------------------------------------- types
let TY_NONE = 0; let TY_I8 = 1; let TY_I16 = 2; let TY_I32 = 3; let TY_I64 = 4; let TY_U8 = 5;
let TY_U16 = 6; let TY_U32 = 7; let TY_U64 = 8; let TY_BOOL = 9; let TY_F32 = 10; let TY_F64 = 11;
let TY_ILIT = 12; let TY_FLIT = 13; let TY_UNIT = 14; let NTY = 15;
let TY_STRUCT0 = 64;

fn ty_sint(t: i64) -> bool { return t >= TY_I8 && t <= TY_I64; }
fn ty_uint(t: i64) -> bool { return t >= TY_U8 && t <= TY_U64; }
fn ty_int(t: i64) -> bool { return ty_sint(t) || ty_uint(t) || t == TY_ILIT; }
fn ty_flt(t: i64) -> bool { return t == TY_F32 || t == TY_F64; }
fn ty_num(t: i64) -> bool { return ty_int(t) || ty_flt(t) || t == TY_FLIT; }

// structs (record types used as array elements)
struct StructT { noff: i64, nlen: i64, nf: i64, size: i64 }
let sts = alloc<StructT>(64);
let mut nst: i64 = 0;
let sfty = alloc<i64>(2048);        // [struct * 32 + field]
let sfoff = alloc<i64>(2048);
let sfnoff = alloc<i64>(2048);
let sfnlen = alloc<i64>(2048);
fn is_struct(t: i64) -> bool { return t >= TY_STRUCT0 && t < TY_STRUCT0 + nst; }
fn ty_width(t: i64) -> i64 {
  if is_struct(t) { return sts[t - TY_STRUCT0].size; }
  if t == TY_I8 || t == TY_U8 || t == TY_BOOL { return 1; }
  if t == TY_I16 || t == TY_U16 { return 2; }
  if t == TY_I32 || t == TY_U32 || t == TY_F32 { return 4; }
  return 8;
}

// ---------------------------------------------------------------- source text
// src holds the runtime library (prelude) at 0.., a 0 byte, then the user file, then 0.
let src = alloc<u8>(2200000);
let mut src_len: i64 = 0;
let mut source: i64 = 0;      // start of the source being parsed
let mut pos: i64 = 0;
let mut tstart: i64 = 0;
let mut parsing_src: i64 = 0; // 1 user file, 2 runtime library, 0 after parsing
let mut prelude_len: i64 = 0;

let sdata = alloc<u8>(1048576);
let mut sdlen: i64 = 0;

// current token
let mut tk_kind: i64 = 0;
let mut tk_op: i64 = 0;
let mut tk_big: bool = false;
let mut tk_value: u64 = 0;
let mut tk_fval: u64 = 0;       // f64 bits
let mut tk_fval32: u64 = 0;     // the same literal correctly rounded to f32
let mut tk_noff: i64 = 0;       // identifier: offset/length in src
let mut tk_nlen: i64 = 0;
let mut tk_soff: i64 = 0;       // string literal: offset/length in sdata
let mut tk_slen: i64 = 0;

// ---------------------------------------------------------------- diagnostics
fn putnum(v: i64) {
  if v < 0 { putc('-'); putnum(0 - v); return; }
  if v >= 10 { putnum(v / 10); }
  putc(v % 10 + 48);
}
// errors go to stderr as  file:line:col: error: message  plus the line and a caret
let emsg = alloc<u8>(4096);
let mut emlen: i64 = 0;
let srcname = alloc<u8>(4096);
let mut srcname_len: i64 = 0;
let mut errnode: i64 = -1;   // type errors point at the start of this expression
fn em_c(c: i64) { if emlen < 4000 { emsg[emlen] = c as u8; emlen += 1; } }
fn em_s(m: [u8]) { let mut i = 0; while i < len(m) { em_c(m[i] as i64); i += 1; } }
fn em_n(v: i64) {
  if v < 0 { em_c('-'); if v == INT64_MIN { em_s("9223372036854775808"); return; } em_n(0 - v); return; }
  if v >= 10 { em_n(v / 10); }
  em_c(v % 10 + 48);
}
fn em_src(off: i64, n: i64) { let mut i = 0; while i < n { em_c(src[off + i] as i64); i += 1; } }
fn em_ty(t: i64) {
  if t >= TY_STRUCT0 { em_src(sts[t - TY_STRUCT0].noff, sts[t - TY_STRUCT0].nlen); return; }
  if t == TY_I8 { em_s("i8"); } else if t == TY_I16 { em_s("i16"); } else if t == TY_I32 { em_s("i32"); } else if t == TY_I64 { em_s("i64"); }
  else if t == TY_U8 { em_s("u8"); } else if t == TY_U16 { em_s("u16"); } else if t == TY_U32 { em_s("u32"); } else if t == TY_U64 { em_s("u64"); }
  else if t == TY_BOOL { em_s("bool"); } else if t == TY_F32 { em_s("f32"); } else if t == TY_F64 { em_s("f64"); }
  else if t == TY_ILIT { em_s("integer literal"); } else if t == TY_FLIT { em_s("float literal"); } else if t == TY_UNIT { em_s("()"); }
  else { em_s("?"); }
}
fn die() {
  let msg_len = emlen;
  if errnode >= 0 && parsing_src != 0 && nd[errnode].src >= 0 { tstart = source + nd[errnode].src; }
  if parsing_src == 0 || tstart < source || tstart > src_len {
    ewrite("skite: error: "); ewrite(emsg, 0, msg_len); ewrite("\n"); exit(1);
  }
  let mut line = 1;
  let mut ls = source;
  let mut p = source;
  while p < tstart { if src[p] == 10 { line += 1; ls = p + 1; } p += 1; }
  let col = tstart - ls + 1;
  let mut le = ls;
  while le < src_len && src[le] != 10 && src[le] != 0 { le += 1; }
  if parsing_src == 2 { em_s("<runtime library>"); } else { let mut i = 0; while i < srcname_len { em_c(srcname[i] as i64); i += 1; } }
  em_c(':'); em_n(line); em_c(':'); em_n(col); em_s(": error: ");
  let hdr = emlen;
  ewrite(emsg, msg_len, hdr - msg_len); ewrite(emsg, 0, msg_len);
  emlen = 0; em_s("\n  "); em_src(ls, le - ls); em_s("\n  ");
  let mut i = 1;
  while i < col { em_c(32); i += 1; }
  em_s("^\n");
  ewrite(emsg, 0, emlen);
  exit(1);
}
fn fail(msg: [u8]) { emlen = 0; em_s(msg); die(); }
fn fail_name(msg: [u8], off: i64, n: i64) { emlen = 0; em_s(msg); em_s(" `"); em_src(off, n); em_c('`'); die(); }
fn fail_ty(msg: [u8], t: i64) { emlen = 0; em_s(msg); em_ty(t); die(); }
fn fail_ty2(msg: [u8], a: i64, mid: [u8], b: i64) { emlen = 0; em_s(msg); em_ty(a); em_s(mid); em_ty(b); die(); }

// ---------------------------------------------------------------- names
fn eqs(off: i64, n: i64, lit: [u8]) -> bool { // src[off..off+n] == lit
  if n != len(lit) { return false; }
  let mut i = 0;
  while i < n { if src[off + i] != lit[i] { return false; } i += 1; }
  return true;
}
fn eqn(a: i64, an: i64, b: i64, bn: i64) -> bool { // two src ranges
  if an != bn { return false; }
  let mut i = 0;
  while i < an { if src[a + i] != src[b + i] { return false; } i += 1; }
  return true;
}
fn starts2u(off: i64, n: i64) -> bool { return n >= 2 && src[off] == '_' && src[off + 1] == '_'; }

// ---------------------------------------------------------------- lexer
fn is_space(c: i64) -> bool { return c == 32 || (c >= 9 && c <= 13); }
fn is_digit(c: i64) -> bool { return c >= '0' && c <= '9'; }
fn is_alpha(c: i64) -> bool { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'); }
fn is_alnum(c: i64) -> bool { return is_alpha(c) || is_digit(c); }
fn is_xdigit(c: i64) -> bool { return is_digit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'); }
fn xval(c: i64) -> i64 { if is_digit(c) { return c - '0'; } if c >= 'a' { return c - 'a' + 10; } return c - 'A' + 10; }
fn ch(p: i64) -> i64 { return src[p]; }

fn kw_kind(off: i64, n: i64) -> i64 {
  if eqs(off, n, "fn") { return T_FN; } if eqs(off, n, "let") { return T_LET; }
  if eqs(off, n, "mut") { return T_MUT; } if eqs(off, n, "return") { return T_RETURN; }
  if eqs(off, n, "if") { return T_IF; } if eqs(off, n, "else") { return T_ELSE; }
  if eqs(off, n, "while") { return T_WHILE; } if eqs(off, n, "break") { return T_BREAK; }
  if eqs(off, n, "continue") { return T_CONTINUE; } if eqs(off, n, "par") { return T_PAR; }
  if eqs(off, n, "in") { return T_IN; } if eqs(off, n, "as") { return T_AS; }
  if eqs(off, n, "true") { return T_TRUE; } if eqs(off, n, "false") { return T_FALSE; }
  if eqs(off, n, "struct") { return T_STRUCT; } if eqs(off, n, "for") { return T_FOR; }
  if eqs(off, n, "loop") { return T_LOOP; } if eqs(off, n, "const") { return T_CONST; }
  return T_ID;
}
fn esc_char(c0: i64) -> i64 { // after a backslash; pos is past the escape letter
  if c0 == 'n' { return 10; } if c0 == 't' { return 9; } if c0 == 'r' { return 13; } if c0 == '0' { return 0; }
  return -1;
}
fn next() {
  while ch(pos) != 0 {
    if is_space(ch(pos)) { pos += 1; continue; }
    if ch(pos) == '/' && ch(pos + 1) == '/' { while ch(pos) != 0 && ch(pos) != 10 { pos += 1; } continue; }
    break;
  }
  tk_kind = 0; tk_op = 0; tk_big = false; tk_value = 0; tk_fval = 0; tk_fval32 = 0; tk_noff = 0; tk_nlen = 0; tk_soff = 0; tk_slen = 0;
  tstart = pos;
  let c = ch(pos);
  if c == 0 { tk_kind = T_EOF; return; }
  if is_alpha(c) || c == '_' {
    let st = pos;
    while is_alnum(ch(pos)) || ch(pos) == '_' { if pos - st >= 63 { fail("identifier too long"); } pos += 1; }
    tk_noff = st; tk_nlen = pos - st;
    tk_kind = kw_kind(st, pos - st);
    return;
  }
  if c == '"' {
    pos += 1; tk_kind = T_STR; tk_soff = sdlen;
    while ch(pos) != '"' {
      if ch(pos) == 0 || ch(pos) == 10 { fail("unterminated string literal"); }
      let mut b = ch(pos); pos += 1;
      if b == '\\' {
        b = ch(pos); pos += 1;
        let e = esc_char(b);
        if e >= 0 { b = e; }
        else if b == '\\' || b == '"' { }
        else if b == 'x' && is_xdigit(ch(pos)) && is_xdigit(ch(pos + 1)) { b = xval(ch(pos)) * 16 + xval(ch(pos + 1)); pos += 2; }
        else { fail("bad escape in string literal"); }
      }
      if sdlen >= MAX_SDATA { fail("string data limit reached"); }
      sdata[sdlen] = b as u8; sdlen += 1;
    }
    pos += 1; tk_slen = sdlen - tk_soff;
    if tk_slen == 0 { fail("empty string literal"); }
    return;
  }
  if c == 39 { // 'a'
    pos += 1;
    let mut b = ch(pos); pos += 1;
    if b == 39 || b == 10 || b == 0 { fail("empty or unterminated character literal"); }
    if b == '\\' {
      b = ch(pos); pos += 1;
      let e = esc_char(b);
      if e >= 0 { b = e; }
      else if b == '\\' || b == 39 || b == '"' { }
      else if b == 'x' && is_xdigit(ch(pos)) && is_xdigit(ch(pos + 1)) { b = xval(ch(pos)) * 16 + xval(ch(pos + 1)); pos += 2; }
      else { fail("bad escape in character literal"); }
    }
    if ch(pos) != 39 { fail("character literal must be one byte"); }
    pos += 1; tk_kind = T_NUM; tk_value = b as u64; return;
  }
  if is_digit(c) {
    tk_kind = T_NUM;
    let mut v: u64 = 0;
    let st = pos;
    if c == '0' && (ch(pos + 1) == 'x' || ch(pos + 1) == 'X') {
      pos += 2;
      let mut nd_ = 0;
      while is_xdigit(ch(pos)) || ch(pos) == '_' {
        if ch(pos) == '_' { pos += 1; continue; }
        let d = xval(ch(pos)); pos += 1;
        if v >> 60 != 0 { fail("integer literal exceeds u64 maximum"); }
        v = v * 16 + d as u64; nd_ += 1;
      }
      if nd_ == 0 { fail("malformed number"); }
    } else if c == '0' && (ch(pos + 1) == 'b' || ch(pos + 1) == 'B' || ch(pos + 1) == 'o' || ch(pos + 1) == 'O') {
      let mut sh: u64 = 3;   // bits per digit
      if ch(pos + 1) == 'b' || ch(pos + 1) == 'B' { sh = 1; }
      pos += 2;
      let mut nd_ = 0;
      while is_digit(ch(pos)) || ch(pos) == '_' {
        if ch(pos) == '_' { pos += 1; continue; }
        let d = (ch(pos) - '0') as u64;
        if d >> sh != 0 { fail("malformed number"); }
        pos += 1;
        if v >> (64 - sh) != 0 { fail("integer literal exceeds u64 maximum"); }
        v = (v << sh) | d; nd_ += 1;
      }
      if nd_ == 0 { fail("malformed number"); }
    } else {
      let mut ovf = false;
      while is_digit(ch(pos)) || ch(pos) == '_' {
        if ch(pos) == '_' { pos += 1; continue; }
        let d = (ch(pos) - '0') as u64; pos += 1;
        if v > (18446744073709551615 - d) / 10 { ovf = true; }
        v = v * 10 + d;
      }
      let isf = (ch(pos) == '.' && is_digit(ch(pos + 1))) || ch(pos) == 'e' || ch(pos) == 'E';
      if ovf && !isf { fail("integer literal exceeds u64 maximum"); }
      if isf {
        if ch(pos) == '.' { pos += 1; while is_digit(ch(pos)) || ch(pos) == '_' { pos += 1; } }
        if ch(pos) == 'e' || ch(pos) == 'E' {
          pos += 1; if ch(pos) == '+' || ch(pos) == '-' { pos += 1; }
          if !is_digit(ch(pos)) { fail("malformed float literal"); }
          while is_digit(ch(pos)) { pos += 1; }
        }
        if pos - st > 127 { fail("float literal too long"); }
        tk_kind = T_FNUM; tk_fval = parse_float(st, pos, false); tk_fval32 = parse_float(st, pos, true);
        if is_alpha(ch(pos)) || ch(pos) == '_' { fail("malformed number"); }
        return;
      }
    }
    if is_alpha(ch(pos)) || ch(pos) == '_' { fail("malformed number"); }
    tk_value = v; tk_big = v > 9223372036854775807; return;
  }
  // punctuation: longest match first
  let c1 = ch(pos + 1);
  let c2 = ch(pos + 2);
  let c3 = ch(pos + 3);
  if c == '>' && c1 == '>' && c2 == '>' && c3 == '=' { pos += 4; tk_kind = T_OPEQ; tk_op = O_SHR; return; }
  if c == '>' && c1 == '>' && c2 == '>' { pos += 3; tk_kind = T_SHRU; return; }
  if c == '>' && c1 == '>' && c2 == '=' { pos += 3; tk_kind = T_OPEQ; tk_op = O_SAR; return; }
  if c == '<' && c1 == '<' && c2 == '=' { pos += 3; tk_kind = T_OPEQ; tk_op = O_SHL; return; }
  if c == '>' && c1 == '>' { pos += 2; tk_kind = T_SHR; return; }
  if c == '<' && c1 == '<' { pos += 2; tk_kind = T_SHL; return; }
  if c == '>' && c1 == '=' { pos += 2; tk_kind = T_GE; return; }
  if c == '<' && c1 == '=' { pos += 2; tk_kind = T_LE; return; }
  if c == '=' && c1 == '=' { pos += 2; tk_kind = T_EQ; return; }
  if c == '!' && c1 == '=' { pos += 2; tk_kind = T_NE; return; }
  if c == '&' && c1 == '&' { pos += 2; tk_kind = T_LAND; return; }
  if c == '|' && c1 == '|' { pos += 2; tk_kind = T_LOR; return; }
  if c == '-' && c1 == '>' { pos += 2; tk_kind = T_ARROW; return; }
  if c == '.' && c1 == '.' && c2 == '=' { pos += 3; tk_kind = T_DOTDOTEQ; return; }
  if c == '.' && c1 == '.' { pos += 2; tk_kind = T_DOTDOT; return; }
  if c1 == '=' {
    let mut o = -1;
    if c == '+' { o = O_ADD; } else if c == '-' { o = O_SUB; } else if c == '*' { o = O_MUL; }
    else if c == '/' { o = O_DIV; } else if c == '%' { o = O_MOD; } else if c == '&' { o = O_AND; }
    else if c == '|' { o = O_OR; } else if c == '^' { o = O_XOR; }
    if o >= 0 { pos += 2; tk_kind = T_OPEQ; tk_op = o; return; }
  }
  let ok = "+-*/%(){};:=<>!~&|^[],.";
  let mut i = 0;
  while i < len(ok) { if ok[i] == c { pos += 1; tk_kind = c; return; } i += 1; }
  fail("unexpected character");
}
fn expect(t: i64) { if tk_kind != t { fail("unexpected token"); } next(); }

// ---------------------------------------------------------------- decimal -> f64 (correctly rounded)
// value = N * 10^E with N a big integer (base 2^32 limbs, little-endian).
let BIG = 160;
fn big_mul_small(a: mut [u64], n: i64, m: u64, add: u64) -> i64 { // a = a*m + add; returns limb count
  let mut carry = add;
  let mut i = 0;
  while i < n { let t = a[i] * m + carry; a[i] = t & 4294967295; carry = t >> 32; i += 1; }
  let mut k = n;
  while carry != 0 { if k >= len(a) { return -1; } a[k] = carry & 4294967295; carry = carry >> 32; k += 1; }
  return k;
}
fn big_bits(a: [u64], n: i64) -> i64 {
  let mut k = n;
  while k > 0 && a[k - 1] == 0 { k -= 1; }
  if k == 0 { return 0; }
  let mut b = 0;
  let mut t = a[k - 1];
  while t != 0 { b += 1; t = t >> 1; }
  return (k - 1) * 32 + b;
}
fn big_bit(a: [u64], n: i64, i: i64) -> u64 { if i < 0 || i / 32 >= n { return 0; } return (a[i / 32] >> ((i % 32) as u64)) & 1; }
fn big_shl(a: mut [u64], n: i64, s: i64) -> i64 { // a <<= s (a has room); returns limbs
  let w = s / 32;
  let r = (s % 32) as u64;
  let mut nn = n + w + 1;
  let mut i = nn - 1;
  while i >= 0 {
    let mut v: u64 = 0;
    let j = i - w;
    if j >= 0 && j < n { v = (a[j] << r) & 4294967295; }
    if r != 0 && j - 1 >= 0 && j - 1 < n { v = v | (a[j - 1] >> (32 - r)); }
    a[i] = v;
    i -= 1;
  }
  while nn > 1 && a[nn - 1] == 0 { nn -= 1; }
  return nn;
}
fn big_cmp(a: [u64], an: i64, b: [u64], bn: i64) -> i64 {
  let n = if_max(an, bn);
  let mut i = n - 1;
  while i >= 0 {
    let mut x: u64 = 0; let mut y: u64 = 0;
    if i < an { x = a[i]; } if i < bn { y = b[i]; }
    if x != y { if x > y { return 1; } return -1; }
    i -= 1;
  }
  return 0;
}
fn if_max(a: i64, b: i64) -> i64 { if a > b { return a; } return b; }
fn big_sub(a: mut [u64], an: i64, b: [u64], bn: i64) { // a -= b (a >= b)
  let mut borrow = 0;
  let mut i = 0;
  while i < an {
    let mut y = 0; if i < bn { y = b[i] as i64; }
    let mut t = a[i] as i64 - y - borrow;
    if t < 0 { t += 4294967296; borrow = 1; } else { borrow = 0; }
    a[i] = t as u64;
    i += 1;
  }
}
// round q (qb significant bits, 1..64) to keep bits (1..qb), half-even; sticky = nonzero bits below q
fn round_keep(q: u64, qb: i64, sticky: bool, keep: i64) -> u64 {
  if keep >= qb { return q << ((keep - qb) as u64); }
  let drop = (qb - keep) as u64;
  let r = q >> drop;
  let half: u64 = (1 as u64) << (drop - 1);
  let rem = q & ((half << 1) - 1);
  if rem > half || (rem == half && (sticky || (r & 1) == 1)) { return r + 1; }
  return r;
}
// Nearest IEEE binary64 (sg=false) or binary32 (sg=true) to q * 2^(e2 - qb + 1).
fn make_double(q: u64, qb: i64, sticky: bool, e2: i64, sg: bool) -> u64 {
  let mut mb = 53; let mut emax = 1023; let mut fb: u64 = 52;
  if sg { mb = 24; emax = 127; fb = 23; }
  let emin = 1 - emax;
  let inf = ((2 * emax + 1) as u64) << fb;
  if e2 > emax { return inf; }
  if e2 >= emin {
    let mut m = round_keep(q, qb, sticky, mb);
    let mut e = e2;
    if (m >> (mb as u64)) != 0 { m = m >> 1; e += 1; }
    if e > emax { return inf; }
    return (((e + emax) as u64) << fb) | (m & (((1 as u64) << fb) - 1));
  }
  // Subnormal unit is 2^(emin - mb + 1); keep counts retained bits below e2.
  let keep = e2 - emin + mb;
  if keep < 0 { return 0; }
  if keep == 0 {
    let half: u64 = (1 as u64) << ((qb - 1) as u64);
    if q > half || (q == half && sticky) { return 1; }
    return 0;
  }
  return round_keep(q, qb, sticky, keep);
}
fn parse_float(st: i64, en: i64, sg: bool) -> u64 {
  let mut inf: u64 = 9218868437227405312;
  if sg { inf = 2139095040; }
  let n = alloc<u64>(160);
  let mut nl = 1;
  let mut e10 = 0;
  let mut p = st;
  let mut seen_dot = false;
  let mut nz = false;
  while p < en && ch(p) != 'e' && ch(p) != 'E' {
    let c = ch(p);
    if c == '.' { seen_dot = true; }
    else if c != '_' {
      if c != '0' { nz = true; }
      if nz { nl = big_mul_small(n, nl, 10, (c - '0') as u64); if nl < 0 { fail("float literal too long"); } }
      if seen_dot { e10 -= 1; }
    }
    p += 1;
  }
  if p < en {
    p += 1;
    let mut neg = false;
    if ch(p) == '+' { p += 1; } else if ch(p) == '-' { neg = true; p += 1; }
    let mut ex = 0;
    while p < en { if ex < 100000 { ex = ex * 10 + (ch(p) - '0'); } p += 1; }
    if neg { e10 -= ex; } else { e10 += ex; }
  }
  if !nz { return 0; }
  let nb = big_bits(n, nl);
  let est = e10 + nb * 30103 / 100000;   // ~ log10(value)
  if est > 310 { return inf; }
  if est < -326 { return 0; }
  if e10 >= 0 {
    let mut k = 0;
    while k < e10 { nl = big_mul_small(n, nl, 10, 0); if nl < 0 { return inf; } k += 1; }
    let b = big_bits(n, nl);
    let top = if_min(b, 64);
    let mut q: u64 = 0;
    let mut i = 0;
    while i < top { q = (q << 1) | big_bit(n, nl, b - 1 - i); i += 1; }
    let mut sticky = false;
    i = 0;
    while i < b - top { if big_bit(n, nl, i) != 0 { sticky = true; } i += 1; }
    return make_double(q, top, sticky, b - 1, sg);
  }
  // N / 10^-E: q = floor(N * 2^sh / D) has 63 or 64 bits
  let d = alloc<u64>(160);
  d[0] = 1;
  let mut dl = 1;
  let mut k2 = 0;
  while k2 < 0 - e10 { dl = big_mul_small(d, dl, 10, 0); if dl < 0 { return 0; } k2 += 1; }
  let db = big_bits(d, dl);
  let sh = db - nb + 63;
  if sh >= 0 { nl = big_shl(n, nl, sh); } else { dl = big_shl(d, dl, 0 - sh); }
  let mut q: u64 = 0;
  let ds = alloc<u64>(160);
  let mut bit = 63;
  while bit >= 0 {
    let mut j = 0;
    while j < 160 { ds[j] = 0; j += 1; }
    j = 0;
    while j < dl { ds[j] = d[j]; j += 1; }
    let dsl = big_shl(ds, dl, bit);
    if big_cmp(n, nl, ds, dsl) >= 0 { big_sub(n, nl, ds, dsl); q = q | ((1 as u64) << (bit as u64)); }
    bit -= 1;
  }
  let mut sticky = false;
  let mut i = 0;
  while i < nl { if n[i] != 0 { sticky = true; } i += 1; }
  let mut qb = 0;
  let mut t = q;
  while t != 0 { qb += 1; t = t >> 1; }
  return make_double(q, qb, sticky, qb - 1 - sh, sg);
}
fn if_min(a: i64, b: i64) -> i64 { if a < b { return a; } return b; }
// ---------------------------------------------------------------- AST
let N_CONST = 0; let N_VAR = 1; let N_UN = 2; let N_BIN = 3; let N_LOAD = 4; let N_CALL = 5; let N_ARR = 6;
let S_LET = 7; let S_ASSIGN = 8; let S_IF = 9; let S_WHILE = 10; let S_RET = 11; let S_BRK = 12; let S_CONT = 13;
let S_BLOCK = 14; let S_ARR = 15; let S_STORE = 16; let S_PRINT = 17; let S_PUTC = 18; let S_EXPR = 19;
let S_WRITE = 20; let S_INL = 21; let S_IRET = 22; let S_PAR = 23; let N_NCPU = 24; let S_SAVE = 25;
let A_ALLOC = 0; let A_FILE = 1; let A_VIEW = 2; let A_STR = 3; let A_ARG = 4;

struct Node { k: i64, op: i64, a: i64, b: i64, c: i64, next: i64, var: i64, pos: i64, chk: i64, nn: i64, ty: i64, v: u64, dlo: i64, dhi: i64, src: i64 }
let nd = alloc<Node>(1048576);
let mut nn: i64 = 0;
let flit32 = alloc<u64>(1048576);
let vflit32 = alloc<u64>(65536);
let FLIT32_OK: u64 = 4294967296;

struct Var { noff: i64, nlen: i64, mutv: i64, isconst: i64, alias: i64, hoist: i64, reads: i64, start: i64, end: i64,
  reg: i64, slot: i64, cval: u64, weight: i64, arr: i64, ro: i64, basev: i64, lenv: i64, shared: i64, alen: i64,
  lenof: i64, aid: i64, ty: i64, et: i64, owner: i64, glob: i64, garr: i64, xr: i64 }
let vars = alloc<Var>(65536);
let mut nv: i64 = 0;

struct Func { noff: i64, nlen: i64, np: i64, body: i64, used: i64, exit_list: i64, addr: i64, calls: i64, rett: i64, mark: i64 }
let fns = alloc<Func>(4096);
let fpvar = alloc<i64>(65536);   // [f * 16 + i]
let fpw = alloc<i64>(65536);
let fpmut = alloc<i64>(65536);
let fpty = alloc<i64>(65536);
let mut nfn: i64 = 0;
let mut curfn: i64 = 0;
let mut mainfn: i64 = 0;

fn mk(k: i64) -> i64 {
  if nn >= MAX_NODES { fail("program too large"); }
  nd[nn].k = k; nd[nn].op = 0; nd[nn].a = -1; nd[nn].b = -1; nd[nn].c = -1; nd[nn].next = -1; nd[nn].var = -1;
  nd[nn].pos = 0; nd[nn].chk = 0; nd[nn].nn = 0; nd[nn].ty = TY_I64; nd[nn].v = 0; nd[nn].dlo = 0; nd[nn].dhi = -1; flit32[nn] = 0;
  if parsing_src != 0 && tstart != 0 { nd[nn].src = tstart - source; } else { nd[nn].src = -1; }
  nn += 1;
  return nn - 1;
}
fn is_const(e: i64) -> bool { return nd[e].k == N_CONST; }
fn mkconst(v: u64) -> i64 { let e = mk(N_CONST); nd[e].v = v; return e; }
fn mkconst_t(v: u64, t: i64) -> i64 { let e = mkconst(v); nd[e].ty = t; return e; }
fn sar64(x: u64, n: u64) -> u64 { if (x as i64) < 0 { return ~(~x >> n); } return x >> n; }

// ---------------------------------------------------------------- constant folding (same IEEE as the target)
fn eval_fbin(op0: i64, x: u64, y: u64) -> u64 {
  let dbl = fop_dbl(op0);
  let op = fop_base(op0);
  let mut a = 0.0;
  let mut b = 0.0;
  if dbl { a = f64_from_bits(x); b = f64_from_bits(y); }
  else { a = f32_from_bits(x as u32) as f64; b = f32_from_bits(y as u32) as f64; }
  if op == O_FEQ { return (a == b) as u64; } if op == O_FNE { return (a != b) as u64; }
  if op == O_FLT { return (a < b) as u64; } if op == O_FLE { return (a <= b) as u64; }
  if op == O_FGT { return (a > b) as u64; } if op == O_FGE { return (a >= b) as u64; }
  if dbl {
    let mut r = 0.0;
    if op == O_FADD { r = a + b; } else if op == O_FSUB { r = a - b; } else if op == O_FMUL { r = a * b; } else { r = a / b; }
    return bits(r);
  }
  let fa = a as f32;
  let fb = b as f32;
  let mut r: f32 = 0.0;
  if op == O_FADD { r = fa + fb; } else if op == O_FSUB { r = fa - fb; } else if op == O_FMUL { r = fa * fb; } else { r = fa / fb; }
  return bits(r) as u64;
}
let INT64_MIN: i64 = -9223372036854775807 - 1;
let INT64_MAX: i64 = 9223372036854775807;
fn eval_bin(op: i64, x: u64, y: u64) -> u64 {
  let a = x as i64;
  let b = y as i64;
  if is_fop(op) { return eval_fbin(op, x, y); }
  if op == O_DIVU || op == O_MODU {
    if y == 0 { fail("division by zero"); }
    if op == O_DIVU { return x / y; } return x % y;
  }
  if op == O_LTU { return (x < y) as u64; } if op == O_LEU { return (x <= y) as u64; }
  if op == O_GTU { return (x > y) as u64; } if op == O_GEU { return (x >= y) as u64; }
  if op == O_ADD { return x + y; } if op == O_SUB { return x - y; } if op == O_MUL { return x * y; }
  if op == O_DIV || op == O_MOD {
    if b == 0 { fail("division by zero"); }
    if a == INT64_MIN && b == -1 { fail("signed division overflows"); }
    if op == O_DIV { return (a / b) as u64; } return (a % b) as u64;
  }
  if op == O_AND { return x & y; } if op == O_OR { return x | y; } if op == O_XOR { return x ^ y; }
  if op == O_SHL { return x << (y & 63); } if op == O_SHR { return x >> (y & 63); } if op == O_SAR { return sar64(x, y & 63); }
  if op == O_EQ { return (a == b) as u64; } if op == O_NE { return (a != b) as u64; } if op == O_LT { return (a < b) as u64; }
  if op == O_LE { return (a <= b) as u64; } if op == O_GT { return (a > b) as u64; } if op == O_GE { return (a >= b) as u64; }
  if op == O_LAND { return (x != 0 && y != 0) as u64; } if op == O_LOR { return (x != 0 || y != 0) as u64; }
  fail("internal fold error"); return 0;
}
fn clampi(v: i64, lo: i64, hi: i64) -> i64 { if v < lo { return lo; } if v > hi { return hi; } return v; }
fn eval_un(op: i64, v: u64) -> u64 {
  if op == U_NEG { return 0 - v; } if op == U_NOT { return ~v; } if op == U_LNOT { return (v == 0) as u64; }
  if op == U_SX8 { return (v as i8) as u64; } if op == U_SX16 { return (v as i16) as u64; } if op == U_SX32 { return (v as i32) as u64; }
  if op == U_ZX8 { return (v as u8) as u64; } if op == U_ZX16 { return (v as u16) as u64; } if op == U_ZX32 { return (v as u32) as u64; }
  if op == U_SATS8 { return clampi(v as i64, -128, 127) as u64; }
  if op == U_SATS16 { return clampi(v as i64, -32768, 32767) as u64; }
  if op == U_SATS32 { return clampi(v as i64, -2147483648, 2147483647) as u64; }
  if op == U_SATU8 { return clampi(v as i64, 0, 255) as u64; }
  if op == U_SATU16 { return clampi(v as i64, 0, 65535) as u64; }
  if op == U_SATU32 { return clampi(v as i64, 0, 4294967295) as u64; }
  if op == U_FNEG { return v ^ 9223372036854775808; }
  if op == U_GNEG { return (v ^ 2147483648) & 4294967295; }
  if op == U_I2D { return bits((v as i64) as f64); } if op == U_U2D { return bits(v as f64); }
  if op == U_I2S { return bits((v as i64) as f32) as u64; } if op == U_U2S { return bits(v as f32) as u64; }
  if op == U_D2I { return (f64_from_bits(v) as i64) as u64; } if op == U_D2U { return f64_from_bits(v) as u64; }
  if op == U_S2I { return (f32_from_bits(v as u32) as i64) as u64; } if op == U_S2U { return f32_from_bits(v as u32) as u64; }
  if op == U_D2S { return bits(f64_from_bits(v) as f32) as u64; } if op == U_S2D { return bits(f32_from_bits(v as u32) as f64); }
  fail("internal fold error"); return 0;
}
fn bin_rty(op: i64, a: i64) -> i64 {
  if is_cmp_op(op) || is_fcmp(op) || op == O_LAND || op == O_LOR { return TY_BOOL; }
  return nd[a].ty;
}
fn mk_bin(op: i64, a: i64, b: i64) -> i64 {
  if (op == O_DIV || op == O_MOD || op == O_DIVU || op == O_MODU) && is_const(b) && nd[b].v == 0 { fail("division by zero"); }
  if op == O_LAND && is_const(a) { if nd[a].v != 0 { return b; } return mkconst_t(0, TY_BOOL); }
  if op == O_LOR && is_const(a) { if nd[a].v != 0 { return mkconst_t(1, TY_BOOL); } return b; }
  let rt = bin_rty(op, a);
  if is_const(a) && is_const(b) { return mkconst_t(eval_bin(op, nd[a].v, nd[b].v), rt); }
  let e = mk(N_BIN); nd[e].op = op; nd[e].a = a; nd[e].b = b; nd[e].ty = rt; return e;
}
fn mk_un(op: i64, a: i64, t: i64) -> i64 {
  if is_const(a) && op != U_SQRTD && op != U_SQRTS { return mkconst_t(eval_un(op, nd[a].v), t); }
  let e = mk(N_UN); nd[e].op = op; nd[e].a = a; nd[e].ty = t; return e;
}

// ---------------------------------------------------------------- value ranges
// A range is (lo, hi, bot). Functions "return" ranges in RLO/RHI/RBOT.
let mut RLO: i64 = 0;
let mut RHI: i64 = 0;
let mut RBOT: bool = false;
fn ret_rg(lo: i64, hi: i64) { RLO = lo; RHI = hi; RBOT = false; }
fn ret_full() { RLO = INT64_MIN; RHI = INT64_MAX; RBOT = false; }
fn ret_bot() { RLO = 0; RHI = 0; RBOT = true; }
// overflow-checked arithmetic: OVR holds the result
let mut OVR: i64 = 0;
fn ov_add(a: i64, b: i64) -> bool { if (b > 0 && a > INT64_MAX - b) || (b < 0 && a < INT64_MIN - b) { return true; } OVR = a + b; return false; }
fn ov_sub(a: i64, b: i64) -> bool { if (b < 0 && a > INT64_MAX + b) || (b > 0 && a < INT64_MIN + b) { return true; } OVR = a - b; return false; }
fn ov_mul(a: i64, b: i64) -> bool {
  if a == 0 || b == 0 { OVR = 0; return false; }
  if (a == -1 && b == INT64_MIN) || (b == -1 && a == INT64_MIN) { return true; }
  let mut o = false;
  if a > 0 { if b > 0 { o = a > INT64_MAX / b; } else { o = b < INT64_MIN / a; } }
  else { if b > 0 { o = a < INT64_MIN / b; } else { o = a < INT64_MAX / b; } }
  if o { return true; }
  OVR = a * b; return false;
}
fn mx(a: i64, b: i64) -> i64 { if a > b { return a; } return b; }
fn mn(a: i64, b: i64) -> i64 { if a < b { return a; } return b; }
fn pmask(v: i64) -> i64 { let mut m: u64 = 0; while m < v as u64 { m = m * 2 + 1; } return m as i64; }
fn type_rg(t: i64) { // -> R*
  if t == TY_I8 { ret_rg(-128, 127); return; } if t == TY_I16 { ret_rg(-32768, 32767); return; }
  if t == TY_I32 { ret_rg(-2147483648, 2147483647); return; }
  if t == TY_U8 { ret_rg(0, 255); return; } if t == TY_U16 { ret_rg(0, 65535); return; }
  if t == TY_U32 || t == TY_F32 { ret_rg(0, 4294967295); return; }
  if t == TY_BOOL { ret_rg(0, 1); return; }
  ret_full();
}
fn rbin(op0: i64, alo: i64, ahi: i64, abot: bool, blo: i64, bhi: i64, bbot: bool, bc: bool, c: i64) {
  let mut op = op0;
  if is_cmp_op(op) || is_fcmp(op) || op == O_LAND || op == O_LOR { ret_rg(0, 1); return; }
  if abot || bbot { ret_bot(); return; }
  if op == O_DIVU || op == O_MODU {
    if bc && c > 0 {
      if op == O_MODU { ret_rg(0, c - 1); return; }
      if alo >= 0 { ret_rg(alo / c, ahi / c); return; }
      if c > 1 { ret_rg(0, (18446744073709551615 / c as u64) as i64); return; }
      ret_full(); return;
    }
    if alo >= 0 && blo >= 0 { if op == O_DIVU { op = O_DIV; } else { op = O_MOD; } } else { ret_full(); return; }
  }
  if op == O_ADD {
    if ov_add(alo, blo) { ret_full(); return; } let l = OVR;
    if ov_add(ahi, bhi) { ret_full(); return; } ret_rg(l, OVR); return;
  }
  if op == O_SUB {
    if ov_sub(alo, bhi) { ret_full(); return; } let l = OVR;
    if ov_sub(ahi, blo) { ret_full(); return; } ret_rg(l, OVR); return;
  }
  if op == O_MUL {
    if ov_mul(alo, blo) { ret_full(); return; } let p0 = OVR;
    if ov_mul(alo, bhi) { ret_full(); return; } let p1 = OVR;
    if ov_mul(ahi, blo) { ret_full(); return; } let p2 = OVR;
    if ov_mul(ahi, bhi) { ret_full(); return; } let p3 = OVR;
    ret_rg(mn(mn(p0, p1), mn(p2, p3)), mx(mx(p0, p1), mx(p2, p3))); return;
  }
  if op == O_DIV {
    if bc && c > 0 { ret_rg(alo / c, ahi / c); return; }
    if bc && c < -1 { ret_rg(ahi / c, alo / c); return; }
    if alo >= 0 && blo >= 0 { ret_rg(0, ahi); return; }
    if alo == INT64_MIN { ret_full(); return; }
    let m = mx(0 - alo, ahi); ret_rg(0 - m, m); return;
  }
  if op == O_MOD {
    let mut lim = INT64_MAX;
    if bc { if c == INT64_MIN { lim = INT64_MAX; } else if c < 0 { lim = 0 - c - 1; } else { lim = c - 1; } }
    else if blo > INT64_MIN { let m = mx(bhi, 0 - blo); if m > 0 { lim = m - 1; } }
    if alo >= 0 { ret_rg(0, mn(ahi, lim)); return; }
    if ahi <= 0 { ret_rg(mx(alo, 0 - lim), 0); return; }
    ret_rg(mx(alo, 0 - lim), mn(ahi, lim)); return;
  }
  if op == O_AND {
    if alo >= 0 && blo >= 0 { ret_rg(0, mn(ahi, bhi)); return; }
    if alo >= 0 { ret_rg(0, ahi); return; }
    if blo >= 0 { ret_rg(0, bhi); return; }
    ret_full(); return;
  }
  if op == O_OR || op == O_XOR {
    if alo >= 0 && blo >= 0 { ret_rg(0, pmask(mx(ahi, bhi))); return; }
    ret_full(); return;
  }
  if op == O_SHL {
    if !bc { ret_full(); return; }
    let k = c & 63;
    if k == 0 { ret_rg(alo, ahi); return; }
    if k == 63 { ret_full(); return; }
    let m = 1 << k;
    if ov_mul(alo, m) { ret_full(); return; } let l = OVR;
    if ov_mul(ahi, m) { ret_full(); return; } ret_rg(l, OVR); return;
  }
  if op == O_SHR {
    if !bc { if alo >= 0 { ret_rg(0, ahi); return; } ret_full(); return; }
    let k = c & 63;
    if k == 0 { ret_rg(alo, ahi); return; }
    if alo >= 0 { ret_rg(alo >> k, ahi >> k); return; }
    ret_rg(0, (18446744073709551615 >> (k as u64)) as i64); return;
  }
  if op == O_SAR {
    if !bc { let mut l = 0; let mut h = 0; if alo < 0 { l = alo; } if ahi > 0 { h = ahi; } ret_rg(l, h); return; }
    let k = (c & 63) as u64;
    ret_rg(sar64(alo as u64, k) as i64, sar64(ahi as u64, k) as i64); return;
  }
  ret_full();
}

let mut body: i64 = 0;
let mut an_annot: bool = false;
let mut an_changed: bool = false;
let arr_lo = alloc<i64>(65536);     // content range per array (alias class leader)
let arr_hi = alloc<i64>(65536);
let arr_bot = alloc<bool>(65536);
let arr_chg = alloc<bool>(65536);
let wcache = alloc<i64>(1048576);   // per loop: env handle + 1 (0: none)
let wentry = alloc<i64>(1048576);
let wfn = alloc<i64>(1048576);
let mut an_fn: i64 = 0;
let WCACHE_MAX = 268435456;
let mut wcache_bytes: i64 = 0;
let arr_leader = alloc<i64>(65536);

// environments: blocks of env_n+1 entries in one pool; index env_n is the "dead" flag (lo != 0)
struct VR { lo: i64, hi: i64, lt: u64, bot: bool }
let ENV_CAP = 16000000;
let env_lo = alloc<i64>(16000000);   // analysis environments, one array per field (copies vectorize)
let env_hi = alloc<i64>(16000000);
let env_lt = alloc<u64>(16000000);
let env_bot = alloc<bool>(16000000);
let mut env_n: i64 = 0;
let mut pool_bump: i64 = 0;          // temporaries grow up from 0
let mut pool_top: i64 = 16000000;    // loop-entry snapshots (kept for strength reduction) grow down
let freeb = alloc<i64>(1048576);     // free temporary blocks (all of size env_n+1 within a function)
let mut nfreeb: i64 = 0;
fn pool_reset() { pool_bump = 0; nfreeb = 0; }
fn env_alloc() -> i64 { // raw block: caller must initialize every entry before reading it
  let bs = env_n + 1;
  let mut e = 0;
  if nfreeb > 0 { nfreeb -= 1; e = freeb[nfreeb]; }
  else { e = pool_bump; pool_bump += bs; if pool_bump > pool_top { fail("analysis memory exhausted"); } }
  return e;
}
fn env_new() -> i64 {
  let e = env_alloc();
  let bs = env_n + 1;
  let mut i = 0;
  while i < bs { env_lo[e + i] = 0; env_hi[e + i] = 0; env_lt[e + i] = 0; env_bot[e + i] = false; i += 1; }
  return e;
}
fn env_new_keep() -> i64 { // never freed
  let bs = env_n + 1;
  pool_top -= bs;
  if pool_top < pool_bump { fail("analysis memory exhausted"); }
  let e = pool_top;
  let mut i = 0;
  while i < bs { env_lo[e + i] = 0; env_hi[e + i] = 0; env_lt[e + i] = 0; env_bot[e + i] = false; i += 1; }
  return e;
}
fn env_free(e: i64) { freeb[nfreeb] = e; nfreeb += 1; }
fn dead(e: i64) -> bool { return env_lo[e + env_n] != 0; }
fn set_dead(e: i64) { env_lo[e + env_n] = 1; }
fn env_copy(d: i64, s: i64) {
  let mut i = 0;
  while i <= env_n {
    let j = d + i; let k = s + i;
    env_lo[j] = env_lo[k]; env_hi[j] = env_hi[k]; env_lt[j] = env_lt[k]; env_bot[j] = env_bot[k];
    i += 1;
  }
}
fn env_join(d: i64, s: i64) {
  if dead(s) { return; }
  if dead(d) { env_copy(d, s); return; }
  let mut v = 0;
  while v < env_n {
    if env_bot[d + v] { env_lo[d + v] = env_lo[s + v]; env_hi[d + v] = env_hi[s + v]; env_bot[d + v] = env_bot[s + v]; }
    else if !env_bot[s + v] {
      if env_lo[s + v] < env_lo[d + v] { env_lo[d + v] = env_lo[s + v]; }
      if env_hi[s + v] > env_hi[d + v] { env_hi[d + v] = env_hi[s + v]; }
    }
    env_lt[d + v] = env_lt[d + v] & env_lt[s + v];
    v += 1;
  }
}
fn env_eq(a: i64, b: i64) -> bool {
  if dead(a) != dead(b) { return false; }
  let mut v = 0;
  while v < env_n {
    if env_lt[a + v] != env_lt[b + v] || env_bot[a + v] != env_bot[b + v] { return false; }
    if !env_bot[a + v] && (env_lo[a + v] != env_lo[b + v] || env_hi[a + v] != env_hi[b + v]) { return false; }
    v += 1;
  }
  return true;
}
let wc_set = alloc<i64>(1048576);
let mut nwc_set: i64 = 0;
fn wcache_free() {
  let mut i = 0;
  while i < nwc_set { wcache[wc_set[i]] = 0; i += 1; }   // only the entries set since the last reset
  nwc_set = 0;
  wcache_bytes = 0;
  pool_reset();
}
fn has_mod(e: i64) -> bool {
  if e < 0 { return false; }
  let k = nd[e].k;
  if k == N_BIN && nd[e].op == O_MOD { return true; }
  if k == N_CALL { let mut a = nd[e].a; while a >= 0 { if has_mod(a) { return true; } a = nd[a].next; } return false; }
  if k == S_BLOCK || k == S_INL { let mut c = nd[e].a; while c >= 0 { if has_mod(c) { return true; } c = nd[c].next; } return false; }
  if k == S_PAR { return has_mod(nd[e].a) || has_mod(nd[e].b) || has_mod(nd[e].c); }
  return has_mod(nd[e].a) || has_mod(nd[e].b) || (k == S_IF && has_mod(nd[e].c));
}

// per-function variable numbering
let lmap = alloc<i64>(65536);
let lvars = alloc<i64>(65536);
let mut nlvars: i64 = 0;
let mut lmap_fn: i64 = -2;
let fl_start = alloc<i64>(4096);
let fl_n = alloc<i64>(4096);
let fl_has = alloc<bool>(4096);
let fl_store = alloc<i64>(4194304);
let mut fl_used: i64 = 0;
fn LV(v: i64) -> i64 { let i = lmap[v]; if i < 0 { fail("internal: variable outside the analyzed function"); } return i; }
fn lv_add(v: i64) { if v >= 0 && lmap[v] < 0 { lmap[v] = nlvars; lvars[nlvars] = v; nlvars += 1; } }
fn lv_arr(a: i64) { if vars[a].lenv >= 0 { lv_add(vars[a].lenv); } }
fn lv_expr(e: i64) {
  if e < 0 { return; }
  let k = nd[e].k;
  if k == N_VAR { lv_add(nd[e].var); return; }
  if k == N_LOAD { lv_arr(nd[e].var); lv_expr(nd[e].a); return; }
  if k == N_ARR { lv_arr(nd[e].var); return; }
  if k == N_CALL { let mut a = nd[e].a; while a >= 0 { lv_expr(a); a = nd[a].next; } return; }
  if k == N_CONST || k == N_NCPU { return; }
  lv_expr(nd[e].a); lv_expr(nd[e].b);
}
fn lv_stmt(s: i64) {
  if s < 0 { return; }
  let k = nd[s].k;
  if k == S_LET || k == S_ASSIGN || k == S_IRET { lv_add(nd[s].var); lv_expr(nd[s].a); return; }
  if k == S_ARR { lv_arr(nd[s].var); lv_expr(nd[s].a); return; }
  if k == S_STORE || k == S_WRITE || k == S_SAVE { if nd[s].var >= 0 { lv_arr(nd[s].var); } lv_expr(nd[s].a); lv_expr(nd[s].b); return; }
  if k == S_PAR { lv_add(nd[s].var); lv_add(nd[s].op); lv_expr(nd[s].a); lv_expr(nd[s].b); lv_stmt(nd[s].c); return; }
  if k == S_IF { lv_expr(nd[s].a); lv_stmt(nd[s].b); lv_stmt(nd[s].c); return; }
  if k == S_WHILE { lv_expr(nd[s].a); lv_stmt(nd[s].b); return; }
  if k == S_BLOCK || k == S_INL { let mut c = nd[s].a; while c >= 0 { lv_stmt(c); c = nd[c].next; } return; }
  lv_expr(nd[s].a);
}
fn lmap_for(f: i64) {
  if lmap_fn == f { return; }
  let mut i = 0;
  while i < nlvars { lmap[lvars[i]] = -1; i += 1; }
  nlvars = 0; lmap_fn = f;
  if fl_has[f] {
    i = 0;
    while i < fl_n[f] { lv_add(fl_store[fl_start[f] + i]); i += 1; }
    env_n = nlvars; return;
  }
  if f == mainfn { lv_add(0); }
  i = 0;
  while i < fns[f].np {
    let v = fpvar[f * 16 + i];
    if fpw[f * 16 + i] != 0 { lv_add(vars[v].lenv); } else { lv_add(v); }
    i += 1;
  }
  lv_stmt(fns[f].body);
  env_n = nlvars;
  fl_has[f] = true; fl_start[f] = fl_used; fl_n[f] = nlvars;
  if fl_used + nlvars > 4194304 { fail("analysis tables full"); }
  i = 0;
  while i < nlvars { fl_store[fl_used] = lvars[i]; fl_used += 1; i += 1; }
}

// widening thresholds (sorted, unique)
let thr = alloc<i64>(4096);
let mut nthr: i64 = 0;
fn add_thr(c: i64) {
  let mut d = -1;
  while d <= 1 {
    if !ov_add(c, d) {
      let v = OVR;
      let mut i = 0;
      while i < nthr && thr[i] < v { i += 1; }
      if !(i < nthr && thr[i] == v) {
        if nthr >= 4096 { return; }
        let mut j = nthr;
        while j > i { thr[j] = thr[j - 1]; j -= 1; }
        thr[i] = v; nthr += 1;
      }
    }
    d += 1;
  }
}
fn env_widen(old: i64, nw: i64, use_thr: bool) {
  if dead(old) { return; }
  let mut v = 0;
  while v < env_n {
    if !env_bot[old + v] && !env_bot[nw + v] {
      if env_lo[nw + v] < env_lo[old + v] {
        let mut t = INT64_MIN;
        if use_thr { let mut i = nthr - 1; while i >= 0 { if thr[i] <= env_lo[nw + v] { t = thr[i]; break; } i -= 1; } }
        env_lo[nw + v] = t;
      }
      if env_hi[nw + v] > env_hi[old + v] {
        let mut t = INT64_MAX;
        if use_thr { let mut i = 0; while i < nthr { if thr[i] >= env_hi[nw + v] { t = thr[i]; break; } i += 1; } }
        env_hi[nw + v] = t;
      }
    }
    v += 1;
  }
}
fn proven(a: i64, idx: i64, rlo: i64, rhi: i64, rbot: bool, env: i64) -> bool {
  if rbot || rlo < 0 { return false; }
  if vars[a].lenv < 0 { return rhi < vars[a].alen; }
  let mut x = idx;
  while nd[x].k == N_UN && nd[x].nn != 0 { x = nd[x].a; }
  // Exact length-minus-k is below the same array length when k > 0.
  // The existing rlo guard proves the result nonnegative; the length lower
  // bound also proves subtraction cannot underflow.
  if nd[x].k == N_BIN && nd[x].op == O_SUB && nd[nd[x].a].k == N_VAR && is_const(nd[x].b) {
    let k = nd[nd[x].b].v as i64;
    let lenv = vars[a].lenv;
    let L = env + LV(lenv);
    if k > 0 && nd[nd[x].a].var == lenv && !env_bot[L] && env_lo[L] >= k { return true; }
  }
  if vars[a].aid >= 0 {
    if nd[x].k == N_VAR && ((env_lt[env + LV(nd[x].var)] >> (vars[a].aid as u64)) & 1) != 0 { return true; }
    // If x is i-k, a proven i < len(a) also proves i-k < len(a), provided
    // the inferred interval shows the subtraction cannot underflow or wrap.
    if nd[x].k == N_BIN && nd[x].op == O_SUB && nd[nd[x].a].k == N_VAR && is_const(nd[x].b) {
      let k = nd[nd[x].b].v as i64;
      let v = nd[nd[x].a].var;
      let vi = env + LV(v);
      if k >= 0 && !env_bot[vi] && env_lo[vi] >= k && ((env_lt[vi] >> (vars[a].aid as u64)) & 1) != 0 { return true; }
    }
  }
  let L = env + LV(vars[a].lenv);
  return !env_bot[L] && rhi < env_lo[L];
}
fn narrow_tgt(op: i64) -> i64 {
  let k = (op - U_SX8) % 6;
  if k == 0 { return TY_I8; } if k == 1 { return TY_I16; } if k == 2 { return TY_I32; }
  if k == 3 { return TY_U8; } if k == 4 { return TY_U16; } return TY_U32;
}
fn er(e: i64, env: i64) { // range of expression e -> R*
  let k = nd[e].k;
  if k == N_CONST { ret_rg(nd[e].v as i64, nd[e].v as i64); return; }
  if k == N_VAR { let i = env + LV(nd[e].var); RLO = env_lo[i]; RHI = env_hi[i]; RBOT = env_bot[i]; return; }
  if k == N_ARR { ret_bot(); return; }
  if k == N_NCPU { ret_rg(1, 1024); return; }
  if k == N_CALL {
    let mut a = nd[e].a;
    while a >= 0 { if nd[a].k != N_ARR { er(a, env); } a = nd[a].next; }
    ret_full(); return;
  }
  if k == N_LOAD {
    er(nd[e].a, env);
    let rlo = RLO; let rhi = RHI; let rbot = RBOT;
    if an_annot { if vpre[e] || proven(nd[e].var, nd[e].a, rlo, rhi, rbot, env) { nd[e].chk = 0; } else { nd[e].chk = 1; } }
    if an_annot { nd[e].dlo = rlo; nd[e].dhi = rhi; }
    chk_refine(nd[e].var, nd[e].a, env);
    if nd[e].op > 0 { type_rg(nd[e].ty); return; }
    let L = arr_leader[nd[e].var];
    let clo = arr_lo[L]; let chi = arr_hi[L]; let cbot = arr_bot[L];
    type_rg(vars[nd[e].var].et);
    let tlo = RLO; let thi = RHI;
    if cbot { ret_rg(0, 0); return; }
    if clo < tlo || chi > thi { ret_rg(tlo, thi); return; }
    ret_rg(clo, chi); return;
  }
  if k == N_UN {
    er(nd[e].a, env);
    let alo = RLO; let ahi = RHI;
    if RBOT { ret_bot(); return; }
    let op = nd[e].op;
    if op == U_LNOT { ret_rg(0, 1); return; }
    if op == U_NOT { ret_rg(~ahi, ~alo); return; }
    if op == U_NEG { if alo == INT64_MIN { ret_full(); return; } ret_rg(0 - ahi, 0 - alo); return; }
    if op >= U_SX8 && op <= U_SATU32 {
      type_rg(narrow_tgt(op));
      let tlo = RLO; let thi = RHI;
      let inr = alo >= tlo && ahi <= thi;
      if an_annot { nd[e].nn = inr as i64; }
      if inr { ret_rg(alo, ahi); return; }
      if op >= U_SATS8 { ret_rg(clampi(alo, tlo, thi), clampi(ahi, tlo, thi)); return; }
      ret_rg(tlo, thi); return;
    }
    type_rg(nd[e].ty); return;
  }
  let op = nd[e].op;
  if op == O_LAND || op == O_LOR {
    er(nd[e].a, env);
    let t = env_alloc(); env_copy(t, env); refine(t, nd[e].a, op == O_LAND);
    if !dead(t) { er(nd[e].b, t); }
    env_free(t); ret_rg(0, 1); return;
  }
  er(nd[e].a, env);
  let alo = RLO; let ahi = RHI; let abot = RBOT;
  er(nd[e].b, env);
  let blo = RLO; let bhi = RHI; let bbot = RBOT;
  if an_annot && (op == O_DIV || op == O_MOD) { nd[e].nn = (!abot && alo >= 0) as i64; }
  rbin(op, alo, ahi, abot, blo, bhi, bbot, is_const(nd[e].b), nd[nd[e].b].v as i64);
}
// after a[v] executes, 0 <= v < len(a) on every path that continues (a failed check traps)
let mut er_refine: bool = false;
fn chk_refine(a: i64, idx: i64, env: i64) {
  if !er_refine || nd[idx].k != N_VAR || dead(env) { return; }
  let x = env + LV(nd[idx].var);
  if env_bot[x] { return; }
  if env_lo[x] < 0 { env_lo[x] = 0; }
  if vars[a].lenv < 0 { if env_hi[x] > vars[a].alen - 1 { env_hi[x] = vars[a].alen - 1; } }
  else {
    let L = env + LV(vars[a].lenv);
    if !env_bot[L] && env_hi[L] < INT64_MAX && env_hi[x] > env_hi[L] - 1 { env_hi[x] = env_hi[L] - 1; }
    if vars[a].aid >= 0 { env_lt[x] = env_lt[x] | ((1 as u64) << (vars[a].aid as u64)); }
  }
  if env_lo[x] > env_hi[x] { set_dead(env); }
}
let szmask = alloc<u64>(65536);
let sz_defs = alloc<i64>(65536);   // definitions (let / assignment) of each variable in the program
fn sz_count(s: i64) {
  if s < 0 { return; }
  let k = nd[s].k;
  if k == S_LET || k == S_ASSIGN || k == S_IRET { sz_defs[nd[s].var] += 1; }
  if k == S_PAR { sz_defs[nd[s].var] += 2; sz_defs[nd[s].op] += 2; sz_count(nd[s].c); return; }
  if k == S_BLOCK || k == S_INL { let mut c = nd[s].a; while c >= 0 { sz_count(c); c = nd[c].next; } return; }
  if k == S_IF { sz_count(nd[s].b); sz_count(nd[s].c); return; }
  if k == S_WHILE { sz_count(nd[s].b); return; }
}   // immutable variable -> arrays (aid bits) allocated with it as length
fn refine_var(env: i64, v: i64, op: i64, other: i64) {
  // the condition was annotated when it was evaluated; env already assumes its loads passed their
  // bounds checks, so evaluating `other` again must not mark them proven
  let sv = an_annot; an_annot = false; er(other, env); an_annot = sv;
  let rlo = RLO; let rhi = RHI; let rbot = RBOT;
  let x = env + LV(v);
  if rbot || env_bot[x] { return; }
  if op == O_LT {
    if rhi == INT64_MIN { set_dead(env); return; }
    env_hi[x] = mn(env_hi[x], rhi - 1);
    if nd[other].k == N_VAR && vars[nd[other].var].lenof != 0 {
      let a = vars[nd[other].var].lenof - 1;
      if vars[a].aid >= 0 { env_lt[x] = env_lt[x] | ((1 as u64) << (vars[a].aid as u64)); }
    }
    if nd[other].k == N_VAR { env_lt[x] = env_lt[x] | szmask[nd[other].var]; }   // other is the length of these arrays
  }
  else if op == O_LE { env_hi[x] = mn(env_hi[x], rhi); }
  else if op == O_GT { if rlo == INT64_MAX { set_dead(env); return; } env_lo[x] = mx(env_lo[x], rlo + 1); }
  else if op == O_GE { env_lo[x] = mx(env_lo[x], rlo); }
  else if op == O_EQ { env_lo[x] = mx(env_lo[x], rlo); env_hi[x] = mn(env_hi[x], rhi); }
  else if op == O_NE {
    if rlo == rhi {
      if env_lo[x] == rlo && env_lo[x] < INT64_MAX { env_lo[x] += 1; }
      else if env_hi[x] == rlo && env_hi[x] > INT64_MIN { env_hi[x] -= 1; }
    }
  }
  if env_lo[x] > env_hi[x] { set_dead(env); }
}
fn neg_cmp(op: i64) -> i64 {
  if op == O_LT { return O_GE; } if op == O_GE { return O_LT; } if op == O_LE { return O_GT; }
  if op == O_GT { return O_LE; } if op == O_EQ { return O_NE; } return O_EQ;
}
fn swp_cmp(op: i64) -> i64 {
  if op == O_LT { return O_GT; } if op == O_GT { return O_LT; } if op == O_LE { return O_GE; } if op == O_GE { return O_LE; }
  return op;
}
fn refine(env: i64, c: i64, sense: bool) {
  if dead(env) { return; }
  let k = nd[c].k;
  if k == N_CONST { if (nd[c].v != 0) != sense { set_dead(env); } return; }
  if k == N_UN && nd[c].op == U_LNOT { refine(env, nd[c].a, !sense); return; }
  if k != N_BIN { return; }
  let op0 = nd[c].op;
  if op0 == O_LAND { if sense { refine(env, nd[c].a, true); refine(env, nd[c].b, true); } return; }
  if op0 == O_LOR { if !sense { refine(env, nd[c].a, false); refine(env, nd[c].b, false); } return; }
  if !is_cmp_op(op0) { return; }
  let mut op = op0;
  if op >= O_LTU {
    let sv = an_annot; an_annot = false;
    er(nd[c].a, env);
    let alo = RLO; let abot = RBOT;
    er(nd[c].b, env);
    an_annot = sv;
    if abot || RBOT || alo < 0 || RLO < 0 { return; }
    op = op - O_LTU + O_LT;
  }
  if !sense { op = neg_cmp(op); }
  if nd[nd[c].a].k == N_VAR { refine_var(env, nd[nd[c].a].var, op, nd[c].b); }
  if nd[nd[c].b].k == N_VAR && !dead(env) { refine_var(env, nd[nd[c].b].var, swp_cmp(op), nd[c].a); }
}
let brk_env = alloc<i64>(65536);
let cont_env = alloc<i64>(65536);
let mut an_loops: i64 = 0;
let inl_env = alloc<i64>(65536);
let mut an_inl: i64 = 0;
fn arr_store(a: i64, vlo0: i64, vhi0: i64, vbot: bool) {
  let L = arr_leader[a];
  type_rg(vars[a].et);
  let tlo = RLO; let thi = RHI;
  if vbot { return; }
  let mut vlo = vlo0; let mut vhi = vhi0;
  if vlo < tlo || vhi > thi { vlo = tlo; vhi = thi; }
  let mut nlo = vlo; let mut nhi = vhi; let mut nbot = false;
  if !arr_bot[L] { nlo = mn(arr_lo[L], vlo); nhi = mx(arr_hi[L], vhi); }
  if nbot != arr_bot[L] || nlo != arr_lo[L] || nhi != arr_hi[L] {
    arr_lo[L] = nlo; arr_hi[L] = nhi; arr_bot[L] = nbot; an_changed = true; arr_chg[L] = true;
  }
}
fn set_var_rg(env: i64, v: i64, lo: i64, hi: i64, bot: bool) {
  let i = env + LV(v);
  env_lo[i] = lo; env_hi[i] = hi; env_bot[i] = bot; env_lt[i] = 0;
}
fn as_stmt(s: i64, env: i64) {
  if dead(env) { return; }
  let k = nd[s].k;
  if k == S_LET || k == S_ASSIGN { er(nd[s].a, env); set_var_rg(env, nd[s].var, RLO, RHI, RBOT); return; }
  if k == S_ARR {
    let a = nd[s].var;
    if nd[s].a >= 0 { er(nd[s].a, env); }
    // alloc(n) with n an immutable local: n is len(a) wherever both are visible
    if nd[s].op == A_ALLOC && nd[s].a >= 0 && nd[nd[s].a].k == N_VAR && vars[a].aid >= 0 {
      let n = nd[nd[s].a].var;
      if vars[n].mutv == 0 && vars[n].glob == 0 && ty_int(vars[n].ty) && sz_defs[n] <= 1 { szmask[n] = szmask[n] | ((1 as u64) << (vars[a].aid as u64)); }
    }
    if vars[a].lenv >= 0 {
      if nd[s].op == A_ALLOC { set_var_rg(env, vars[a].lenv, 1, 2147483647, false); }
      else { set_var_rg(env, vars[a].lenv, 0, 140737488355328, false); }
    }
    return;
  }
  if k == S_STORE {
    er(nd[s].a, env);
    let rlo = RLO; let rhi = RHI; let rbot = RBOT;
    if an_annot {
      if vpre[s] || proven(nd[s].var, nd[s].a, rlo, rhi, rbot, env) { nd[s].chk = 0; } else { nd[s].chk = 1; }
      nd[s].dlo = rlo; nd[s].dhi = rhi;
    }
    er(nd[s].b, env);
    let vlo = RLO; let vhi = RHI; let vbot = RBOT;
    chk_refine(nd[s].var, nd[s].a, env);   // the index check runs after the value is computed
    if nd[s].op < 0 { arr_store(nd[s].var, vlo, vhi, vbot); }
    else { type_rg(vars[nd[s].var].et); arr_store(nd[s].var, RLO, RHI, RBOT); }
    return;
  }
  if k == S_PRINT || k == S_PUTC || k == S_EXPR {
    er(nd[s].a, env);
    if (k == S_PUTC && nd[s].op == 1) || (k == S_EXPR && nd[nd[s].a].k == N_CALL && fn_nr[nd[nd[s].a].var]) { set_dead(env); }
    return;
  }
  if k == S_WRITE { if nd[s].a >= 0 { er(nd[s].a, env); er(nd[s].b, env); } return; }
  if k == S_SAVE { er(nd[s].a, env); er(nd[s].b, env); return; }
  if k == S_RET { er(nd[s].a, env); set_dead(env); return; }
  if k == S_BRK { env_join(brk_env[an_loops - 1], env); set_dead(env); return; }
  if k == S_IRET {
    er(nd[s].a, env); set_var_rg(env, nd[s].var, RLO, RHI, RBOT);
    env_join(inl_env[an_inl - 1], env); set_dead(env); return;
  }
  if k == S_PAR {
    er(nd[s].a, env);
    let alo = RLO; let abot = RBOT;
    er(nd[s].b, env);
    let blo = RLO; let bhi = RHI; let bbot = RBOT;
    let t = env_alloc(); env_copy(t, env);
    let mut klo = INT64_MIN; let mut khi = INT64_MAX;
    if !abot && !bbot && bhi > INT64_MIN { klo = alo; khi = bhi - 1; }
    if klo <= khi {
      set_var_rg(t, nd[s].var, klo, khi, false);
      let i = t + LV(nd[s].op);
      if bbot { env_lo[i] = INT64_MIN; env_hi[i] = INT64_MAX; env_bot[i] = false; }
      else { env_lo[i] = blo; env_hi[i] = bhi; env_bot[i] = bbot; }
      as_stmt(nd[s].c, t);
    }
    env_free(t); return;
  }
  if k == S_INL {
    if an_inl >= MAX_LOOPS { fail("inlining nested too deeply"); }
    let L = an_inl; an_inl += 1;
    inl_env[L] = env_alloc(); set_dead(inl_env[L]);
    let mut c = nd[s].a;
    while c >= 0 { as_stmt(c, env); c = nd[c].next; }
    env_join(env, inl_env[L]);
    if !dead(env) { env_lo[env + env_n] = 0; }
    env_free(inl_env[L]); an_inl -= 1; return;
  }
  if k == S_CONT { env_join(cont_env[an_loops - 1], env); set_dead(env); return; }
  if k == S_BLOCK { let mut c = nd[s].a; while c >= 0 { as_stmt(c, env); c = nd[c].next; } return; }
  if k == S_IF {
    er(nd[s].a, env);
    // the then branch works on a copy, the else branch on env itself; then env = join(else, then)
    let t = env_alloc(); env_copy(t, env);
    refine(t, nd[s].a, true); refine(env, nd[s].a, false);
    if an_annot && bv_sel[s] && !dead(env) { bv_alive[s] = true; }
    as_stmt(nd[s].b, t); if nd[s].c >= 0 { as_stmt(nd[s].c, env); }
    env_join(env, t);
    env_free(t); return;
  }
  if k == S_WHILE {
    let entry = env_alloc(); let head = env_alloc(); let bdy = env_alloc(); let nh = env_alloc();
    env_copy(entry, env); env_copy(head, env);
    if wcache[s] != 0 { env_join(head, wcache[s] - 1); }
    if an_loops >= MAX_LOOPS { fail("loops nested too deeply"); }
    let L = an_loops; an_loops += 1;
    brk_env[L] = env_alloc(); cont_env[L] = env_alloc();   // dead until joined into (a join into a dead env copies)
    // Only variables the loop assigns can differ between the head and the next iterate (the rest
    // only narrow inside the body), so the joins, widening and the convergence test visit those.
    let ml = am_list(s); let mln = AM_N;
    let mut it = 0;
    while true {
      set_dead(brk_env[L]); set_dead(cont_env[L]);
      env_copy(bdy, head); er(nd[s].a, bdy); refine(bdy, nd[s].a, true);
      as_stmt(nd[s].b, bdy);
      if ml < 0 {
        env_join(bdy, cont_env[L]);
        env_copy(nh, entry); env_join(nh, bdy);
        env_join(nh, head);
        if it >= 2 { env_widen(head, nh, it < 40); }
        if env_eq(nh, head) { break; }
        env_copy(head, nh);
      } else {
        // nh = head + bdy + continue states on the assigned variables (head already covers entry)
        AM_N = mln;   // inner loops reuse AM_N
        am_copy(nh, head, ml); am_join(nh, bdy, ml); am_join(nh, cont_env[L], ml);
        if it >= 2 { am_widen(head, nh, it < 40, ml); }
        if am_eq(nh, head, ml) { break; }
        am_copy(head, nh, ml);
      }
      if it > 200 { fail("internal: range analysis did not converge"); }
      it += 1;
    }
    it = 0;
    while it < 3 {
      set_dead(brk_env[L]); set_dead(cont_env[L]);
      env_copy(bdy, head); er(nd[s].a, bdy); refine(bdy, nd[s].a, true);
      as_stmt(nd[s].b, bdy); env_join(bdy, cont_env[L]);
      env_copy(nh, entry); env_join(nh, bdy);
      if env_eq(nh, head) { break; }
      env_copy(head, nh);
      it += 1;
    }
    if wcache[s] == 0 && wcache_bytes < WCACHE_MAX { wcache[s] = env_new_cache() + 1; wcache_bytes += (env_n + 1) * 32; wc_set[nwc_set] = s; nwc_set += 1; }
    if wcache[s] != 0 { env_copy(wcache[s] - 1, head); }
    if an_annot && has_mod(nd[s].b) { if wentry[s] == 0 { wentry[s] = env_new_keep() + 1; } env_copy(wentry[s] - 1, entry); wfn[s] = an_fn; }
    env_copy(env, head); refine(env, nd[s].a, false); env_join(env, brk_env[L]);
    an_loops -= 1; env_free(brk_env[L]); env_free(cont_env[L]);
    env_free(entry); env_free(head); env_free(bdy); env_free(nh);
    return;
  }
}
// assigned-variable lists of loops (LV indices), per loop node; -1: use whole environments
let am_at = alloc<i64>(1048576);   // node -> start + 1 in am_pool
let am_len = alloc<i64>(1048576);
let am_fn = alloc<i64>(1048576);
let am_pool = alloc<i32>(4194304);
let mut am_used: i64 = 0;
let mut AM_FULL: bool = false;
let am_seen = alloc<i64>(65536);
let mut AM_TAG: i64 = 0;
fn am_add(v: i64) {
  if v < 0 || am_seen[v] == AM_TAG { return; }
  am_seen[v] = AM_TAG;
  let i = lmap[v]; if i < 0 { AM_FULL = true; return; }
  if am_used >= 4194304 { AM_FULL = true; return; }
  am_pool[am_used] = i as i32; am_used += 1;
}
fn am_walk(s: i64) {
  if s < 0 || AM_FULL { return; }
  let k = nd[s].k;
  if k == S_LET || k == S_ASSIGN || k == S_IRET { am_add(nd[s].var); return; }
  if k == S_ARR || k == S_PAR || k == S_SAVE || k == S_WRITE { AM_FULL = true; return; }   // lengths and other effects: whole envs
  if k == S_BLOCK || k == S_INL { if k == S_INL { am_add(nd[s].var); } let mut c = nd[s].a; while c >= 0 { am_walk(c); c = nd[c].next; } return; }
  if k == S_IF { am_walk(nd[s].b); am_walk(nd[s].c); return; }
  if k == S_WHILE { am_walk(nd[s].b); return; }
}
fn am_list(s: i64) -> i64 {   // start in am_pool (length am_len[s]), or -1
  if am_at[s] != 0 && am_fn[s] == an_fn { if am_at[s] < 0 { return -1; } AM_N = am_len[s]; return am_at[s] - 1; }
  AM_TAG += 1; AM_FULL = false;
  let st = am_used;
  am_walk(nd[s].b);
  am_fn[s] = an_fn;
  if AM_FULL { am_used = st; am_at[s] = -1; return -1; }
  am_at[s] = st + 1; am_len[s] = am_used - st; AM_N = am_len[s]; return st;
}
fn am_copy(d: i64, s: i64, ml: i64) { let n = am_len_of(ml); let mut q = 0; while q < n { let v = am_pool[ml + q] as i64; env_lo[d + v] = env_lo[s + v]; env_hi[d + v] = env_hi[s + v]; env_lt[d + v] = env_lt[s + v]; env_bot[d + v] = env_bot[s + v]; q += 1; } env_lo[d + env_n] = env_lo[s + env_n]; }
fn am_join(d: i64, s: i64, ml: i64) {
  if dead(s) { return; }
  let n = am_len_of(ml); let mut q = 0;
  while q < n {
    let v = am_pool[ml + q] as i64;
    if env_bot[d + v] { env_lo[d + v] = env_lo[s + v]; env_hi[d + v] = env_hi[s + v]; env_bot[d + v] = env_bot[s + v]; }
    else if !env_bot[s + v] {
      if env_lo[s + v] < env_lo[d + v] { env_lo[d + v] = env_lo[s + v]; }
      if env_hi[s + v] > env_hi[d + v] { env_hi[d + v] = env_hi[s + v]; }
    }
    env_lt[d + v] = env_lt[d + v] & env_lt[s + v];
    q += 1;
  }
}
fn am_eq(a: i64, b: i64, ml: i64) -> bool {
  let n = am_len_of(ml); let mut q = 0;
  while q < n {
    let v = am_pool[ml + q] as i64;
    if env_lt[a + v] != env_lt[b + v] || env_bot[a + v] != env_bot[b + v] { return false; }
    if !env_bot[a + v] && (env_lo[a + v] != env_lo[b + v] || env_hi[a + v] != env_hi[b + v]) { return false; }
    q += 1;
  }
  return true;
}
fn am_widen(old: i64, nw: i64, use_thr: bool, ml: i64) {
  let n = am_len_of(ml); let mut q = 0;
  while q < n {
    let v = am_pool[ml + q] as i64;
    if !env_bot[old + v] && !env_bot[nw + v] {
      if env_lo[nw + v] < env_lo[old + v] {
        let mut t = INT64_MIN;
        if use_thr { let mut i = nthr - 1; while i >= 0 { if thr[i] <= env_lo[nw + v] { t = thr[i]; break; } i -= 1; } }
        env_lo[nw + v] = t;
      }
      if env_hi[nw + v] > env_hi[old + v] {
        let mut t = INT64_MAX;
        if use_thr { let mut i = 0; while i < nthr { if thr[i] >= env_hi[nw + v] { t = thr[i]; break; } i += 1; } }
        env_hi[nw + v] = t;
      }
    }
    q += 1;
  }
}
let mut AM_N: i64 = 0;   // length of the list am_list returned last
fn am_len_of(ml: i64) -> i64 { return AM_N; }
fn env_new_cache() -> i64 { return env_new(); }   // cache blocks live until wcache_free (pool reset)
fn fn_env(env: i64, f: i64) {
  let mut v = 0;
  while v < env_n { env_lo[env + v] = 0; env_hi[env + v] = 0; env_bot[env + v] = true; env_lt[env + v] = 0; v += 1; }
  env_lo[env + env_n] = 0;
  if f == mainfn { let i = env + LV(0); env_lo[i] = 1; env_hi[i] = 2147483647; env_bot[i] = false; }
  let mut i = 0;
  while i < fns[f].np {
    let pv = fpvar[f * 16 + i];
    if fpw[f * 16 + i] != 0 { let j = env + LV(vars[pv].lenv); env_lo[j] = 0; env_hi[j] = 140737488355328; env_bot[j] = false; }
    else { let j = env + LV(pv); env_lo[j] = INT64_MIN; env_hi[j] = INT64_MAX; env_bot[j] = false; }
    i += 1;
  }
}
fn analyze_fn(f: i64) {
  lmap_for(f); an_fn = f;
  er_refine = true;
  let env = env_new(); fn_env(env, f); as_stmt(fns[f].body, env); env_free(env);
  er_refine = false;
  wcache_free();
}
fn analyze() {
  let mut v = 0;
  while v < nv { sz_defs[v] = 0; szmask[v] = 0; v += 1; }
  v = 0; while v < nfn { if fns[v].used != 0 { sz_count(fns[v].body); } v += 1; }
  v = 0;
  while v < nv { arr_leader[v] = v; vars[v].aid = -1; v += 1; }
  let mut na = 0;
  v = 0;
  while v < nv {
    if vars[v].arr != 0 {
      let mut u = 0;
      while u < v { if vars[u].arr != 0 && vars[u].basev == vars[v].basev { arr_leader[v] = arr_leader[u]; break; } u += 1; }
      if na < 64 { vars[v].aid = na; na += 1; }
      if vars[v].lenv >= 0 { vars[vars[v].lenv].lenof = v + 1; }
    }
    v += 1;
  }
  nthr = 0; add_thr(0);
  let mut i = 0;
  while i < nn {
    if nd[i].k == N_BIN && is_cmp_op(nd[i].op) {
      if is_const(nd[i].a) { add_thr(nd[nd[i].a].v as i64); }
      if is_const(nd[i].b) { add_thr(nd[nd[i].b].v as i64); }
    }
    i += 1;
  }
  v = 0;
  while v < nv { if vars[v].arr != 0 && vars[v].lenv < 0 { add_thr(vars[v].alen); } v += 1; }
  v = 0;
  while v < nv { arr_lo[v] = 0; arr_hi[v] = 0; arr_bot[v] = true; v += 1; }
  v = 0;
  while v < nv {
    if vars[v].arr != 0 {
      let L = arr_leader[v];
      if vars[v].ro != 0 { arr_lo[L] = INT64_MIN; arr_hi[L] = INT64_MAX; arr_bot[L] = false; }
      else if vars[v].glob != 0 { type_rg(vars[v].et); arr_lo[L] = RLO; arr_hi[L] = RHI; arr_bot[L] = false; }
      else if L != v || vars[v].et != vars[L].et { arr_lo[L] = INT64_MIN; arr_hi[L] = INT64_MAX; arr_bot[L] = false; }
      else if arr_bot[L] { arr_lo[L] = 0; arr_hi[L] = 0; arr_bot[L] = false; }
    }
    v += 1;
  }
  let mut f = 0;
  while f < nfn {
    i = 0;
    while i < fns[f].np {
      if fpw[f * 16 + i] != 0 {
        type_rg(fpty[f * 16 + i]);
        let L = arr_leader[fpvar[f * 16 + i]];
        arr_lo[L] = RLO; arr_hi[L] = RHI; arr_bot[L] = false;
      }
      i += 1;
    }
    f += 1;
  }
  let mut e = 0;
  while e < nn {
    if nd[e].k == N_CALL && nd[e].var >= 0 {
      let mut j = 0;
      let mut x = nd[e].a;
      while x >= 0 {
        if nd[x].k == N_ARR && fpmut[nd[e].var * 16 + j] != 0 {
          let L = arr_leader[nd[x].var];
          type_rg(vars[nd[x].var].et);
          if arr_bot[L] { arr_lo[L] = RLO; arr_hi[L] = RHI; arr_bot[L] = false; }
          else { arr_lo[L] = mn(arr_lo[L], RLO); arr_hi[L] = mx(arr_hi[L], RHI); }
        }
        x = nd[x].next; j += 1;
      }
    }
    e += 1;
  }
  v = 0;
  while v < MAX_VARS { lmap[v] = -1; v += 1; }
  nlvars = 0; lmap_fn = -2;
  let mut round = 0;
  while true {
    an_changed = false;
    v = 0;
    while v < nv { arr_chg[v] = false; v += 1; }
    f = 0;
    while f < nfn { if fns[f].used != 0 { analyze_fn(f); } f += 1; }
    if !an_changed { break; }
    if round >= 8 {
      v = 0;
      while v < nv {
        if arr_chg[v] && vars[v].arr != 0 && arr_leader[v] == v {
          type_rg(vars[v].et);
          if arr_bot[v] { arr_lo[v] = RLO; arr_hi[v] = RHI; arr_bot[v] = false; }
          else { arr_lo[v] = mn(arr_lo[v], RLO); arr_hi[v] = mx(arr_hi[v], RHI); }
        }
        v += 1;
      }
    }
    if round > 32 { fail("internal: array range analysis did not converge"); }
    round += 1;
  }
  an_annot = true;
  f = 0;
  while f < nfn { if fns[f].used != 0 { analyze_fn(f); } f += 1; }
}
// ---------------------------------------------------------------- parser state
let mut depth: i64 = 0;
let mut loopdepth: i64 = 0;
let mut inpar: bool = false;
let mut par_outer_nv: i64 = 0;
let loopmark = alloc<i64>(257);
let loopfor = alloc<i64>(257);    // per loop depth: the `for` variable a `continue` steps first (-1: none)
let forvar = alloc<bool>(65536);  // a `for` loop variable (read-only in the body)
let mut use_arena: bool = false;
let vis = alloc<i64>(65536);
let mut nvis: i64 = 0;
let gvis = alloc<i64>(65536);
let mut ngvis: i64 = 0;
let mut in_prelude: bool = false;
let mut nfn_decl: i64 = 0;
let mut parsing: bool = false;

fn enter() { depth += 1; if depth > MAX_DEPTH { fail("nesting too deep"); } }
fn find_var(off: i64, n: i64) -> i64 {
  let mut j = nvis - 1;
  while j >= 0 { let v = vis[j]; if eqn(vars[v].noff, vars[v].nlen, off, n) { return v; } j -= 1; }
  j = 0;
  while j < ngvis { let v = gvis[j]; if eqn(vars[v].noff, vars[v].nlen, off, n) { return v; } j += 1; }
  return -1;
}
fn lookup(off: i64, n: i64) -> i64 { let v = find_var(off, n); if v < 0 { fail_name("unknown variable", off, n); } return v; }
fn peek_kind() -> i64 {
  let sp = pos; let ts = tstart; let sd = sdlen;
  let k0 = tk_kind; let o0 = tk_op; let b0 = tk_big; let v0 = tk_value; let f0 = tk_fval; let g0 = tk_fval32; let no = tk_noff; let nl = tk_nlen; let so = tk_soff; let sl = tk_slen;
  next();
  let k = tk_kind;
  pos = sp; tstart = ts; sdlen = sd;
  tk_kind = k0; tk_op = o0; tk_big = b0; tk_value = v0; tk_fval = f0; tk_fval32 = g0; tk_noff = no; tk_nlen = nl; tk_soff = so; tk_slen = sl;
  return k;
}
fn var_ref(v0: i64) -> i64 {
  let mut v = v0;
  while vars[v].alias != 0 { v = vars[v].alias - 1; }
  if vars[v].garr != 0 { let e = mk_load(vars[v].garr, mkconst(0)); nd[e].ty = vars[v].ty; return e; }
  if vars[v].arr != 0 { fail("array used as a scalar (index it, or use len())"); }
  if vars[v].isconst != 0 { let ce = mkconst_t(vars[v].cval, vars[v].ty); flit32[ce] = vflit32[v]; return ce; }
  vars[v].reads += 1;
  let e = mk(N_VAR); nd[e].var = v; nd[e].ty = vars[v].ty; return e;
}
fn mk_var(v: i64) -> i64 { vars[v].reads += 1; let e = mk(N_VAR); nd[e].var = v; nd[e].ty = vars[v].ty; return e; }

// ---------------------------------------------------------------- type rules
fn lit_fits(v: i64, t: i64) -> bool {
  if t == TY_I8 { return v >= -128 && v <= 127; } if t == TY_I16 { return v >= -32768 && v <= 32767; }
  if t == TY_I32 { return v >= -2147483648 && v <= 2147483647; } if t == TY_I64 { return true; }
  if t == TY_U8 { return v >= 0 && v <= 255; } if t == TY_U16 { return v >= 0 && v <= 65535; }
  if t == TY_U32 { return v >= 0 && v <= 4294967295; } if t == TY_U64 { return v >= 0; }
  return false;
}
fn widens(s: i64, t: i64) -> bool {
  if s == t { return true; }
  if ty_sint(s) { return ty_sint(t) && ty_width(t) >= ty_width(s); }
  if ty_uint(s) { return (ty_uint(t) && ty_width(t) >= ty_width(s)) || (ty_sint(t) && ty_width(t) > ty_width(s)); }
  return false;
}
fn conv(e: i64, t: i64) -> i64 {
  let s = nd[e].ty; errnode = e;
  if s == t { return e; }
  if s == TY_UNIT { fail("this function returns no value"); }
  if s == TY_ILIT {
    let v = nd[e].v as i64;
    if ty_int(t) { if !lit_fits(v, t) { emlen = 0; em_s("integer literal "); em_n(v); em_s(" out of range for "); em_ty(t); die(); } nd[e].ty = t; return e; }
    if ty_flt(t) {
      let mut d = 0.0;
      if t == TY_F32 { d = (v as f32) as f64; } else { d = v as f64; }
      if d >= 9223372036854775808.0 || d as i64 != v { emlen = 0; em_s("integer literal "); em_n(v); em_s(" not exactly representable as "); em_ty(t); die(); }
      if t == TY_F32 { nd[e].v = bits(d as f32) as u64; } else { nd[e].v = bits(d); }
      nd[e].ty = t; return e;
    }
  }
  if s == TY_FLIT && ty_flt(t) {
    if t == TY_F32 {
      if (flit32[e] & FLIT32_OK) != 0 { nd[e].v = flit32[e] & 4294967295; }
      else { nd[e].v = bits(f64_from_bits(nd[e].v) as f32) as u64; }
    }
    nd[e].ty = t; return e;
  }
  if ty_int(s) && ty_int(t) && widens(s, t) { nd[e].ty = t; errnode = -1; return e; }
  fail_ty2("type mismatch: expected ", t, ", found ", s); return -1;
}
fn deflt(e: i64) -> i64 {
  if nd[e].ty == TY_ILIT { return conv(e, TY_I64); }
  if nd[e].ty == TY_FLIT { return conv(e, TY_F64); }
  if nd[e].ty == TY_UNIT { fail("this function returns no value"); }
  return e;
}
fn need_bool(e: i64) -> i64 { errnode = e; if nd[e].ty != TY_BOOL { fail_ty("condition must be bool, found ", nd[e].ty); } return e; }
fn need_int(e0: i64) -> i64 { let e = deflt(e0); errnode = e; if !ty_int(nd[e].ty) { fail_ty("expected an integer, found ", nd[e].ty); } errnode = -1; return e; }
fn promote(t: i64) -> i64 { if t == TY_U64 { return TY_U64; } return TY_I64; }
let mut TB_A: i64 = 0;   // type_bin operands (updated in place)
let mut TB_B: i64 = 0;
fn type_bin(op0: i64) -> i64 {
  let mut op = op0;
  let ta = nd[TB_A].ty; let tb = nd[TB_B].ty; errnode = TB_A;
  if ta == TY_UNIT || tb == TY_UNIT { fail("this function returns no value"); }
  if op == O_LAND || op == O_LOR { need_bool(TB_A); need_bool(TB_B); return op; }
  let fa = ty_flt(ta) || ta == TY_FLIT;
  let fb = ty_flt(tb) || tb == TY_FLIT;
  if fa || fb {
    if (!fa && !ty_num(ta)) || (!fb && !ty_num(tb)) { fail_ty2("operator needs numbers, found ", ta, " and ", tb); }
    let mut t = TY_FLIT;
    if ty_flt(ta) { t = ta; } else if ty_flt(tb) { t = tb; }
    if t == TY_FLIT && ((ta != TY_ILIT && ta != TY_FLIT) || (tb != TY_ILIT && tb != TY_FLIT)) { fail_ty2("type mismatch: ", ta, " and ", tb); }
    if t == TY_FLIT {
      if ta == TY_ILIT { nd[TB_A].v = bits((nd[TB_A].v as i64) as f64); nd[TB_A].ty = TY_FLIT; }
      if tb == TY_ILIT { nd[TB_B].v = bits((nd[TB_B].v as i64) as f64); nd[TB_B].ty = TY_FLIT; }
    } else { TB_A = conv(TB_A, t); TB_B = conv(TB_B, t); }
    let mut base = -1;
    if op == O_ADD { base = O_FADD; } else if op == O_SUB { base = O_FSUB; } else if op == O_MUL { base = O_FMUL; }
    else if op == O_DIV { base = O_FDIV; } else if op == O_EQ { base = O_FEQ; } else if op == O_NE { base = O_FNE; }
    else if op == O_LT { base = O_FLT; } else if op == O_LE { base = O_FLE; } else if op == O_GT { base = O_FGT; }
    else if op == O_GE { base = O_FGE; } else { fail("operator not defined for floats"); }
    let mut r = base;
    if t == TY_F32 { r = base + (O_GADD - O_FADD); }
    if t == TY_FLIT { nd[TB_A].ty = TY_F64; nd[TB_B].ty = TY_F64; }
    return r;
  }
  if ta == TY_BOOL || tb == TY_BOOL {
    if ta != tb { fail_ty2("type mismatch: ", ta, " and ", tb); }
    if op != O_EQ && op != O_NE && op != O_AND && op != O_OR && op != O_XOR { fail("operator not defined for bool"); }
    return op;
  }
  if !ty_int(ta) || !ty_int(tb) { fail_ty2("operator needs numbers, found ", ta, " and ", tb); }
  if op == O_SHL || op == O_SHR || op == O_SAR {
    if ta != TY_ILIT { TB_A = conv(TB_A, promote(ta)); }
    else if tb != TY_ILIT { TB_A = conv(TB_A, TY_I64); }
    if tb == TY_ILIT && ta != TY_ILIT { TB_B = conv(TB_B, TY_I64); }
    if op == O_SAR && nd[TB_A].ty == TY_U64 { op = O_SHR; }
    return op;
  }
  let mut t = 0;
  if ta == TY_ILIT && tb == TY_ILIT { t = TY_ILIT; }
  else if ta == TY_ILIT { t = promote(tb); }
  else if tb == TY_ILIT { t = promote(ta); }
  else {
    let pa = promote(ta); let pb = promote(tb);
    if pa == pb { t = pa; }
    else if (pa == TY_U64 && ty_uint(tb)) || (pb == TY_U64 && ty_uint(ta)) { t = TY_U64; }
    else { emlen = 0; em_s("mixed signed and unsigned operands ("); em_ty(ta); em_s(", "); em_ty(tb); em_s("): convert one with `as`"); die(); }
  }
  if t != TY_ILIT { TB_A = conv(TB_A, t); TB_B = conv(TB_B, t); }
  if t == TY_U64 {
    if op == O_DIV { return O_DIVU; } if op == O_MOD { return O_MODU; } if op == O_LT { return O_LTU; }
    if op == O_LE { return O_LEU; } if op == O_GT { return O_GTU; } if op == O_GE { return O_GEU; }
  }
  return op;
}
fn is_lit_ty(t: i64) -> bool { return t == TY_FLIT || t == TY_ILIT; }
fn typed_bin(op: i64, a: i64, b: i64) -> i64 {
  let flit = is_lit_ty(nd[a].ty) && is_lit_ty(nd[b].ty) && (nd[a].ty == TY_FLIT || nd[b].ty == TY_FLIT);
  let sp = nd[a].src;
  TB_A = a; TB_B = b;
  let o = type_bin(op);
  let e = mk_bin(o, TB_A, TB_B);
  if flit && nd[e].ty == TY_F64 { nd[e].ty = TY_FLIT; }
  nd[e].src = sp; errnode = -1; return e;
}
fn typed_un(op: i64, a0: i64) -> i64 {
  let mut a = a0;
  let t = nd[a].ty; errnode = a;
  if t == TY_UNIT { fail("this function returns no value"); }
  if op == U_LNOT { need_bool(a); return mk_un(U_LNOT, a, TY_BOOL); }
  if op == U_NEG && (ty_flt(t) || t == TY_FLIT) {
    if t == TY_F32 { return mk_un(U_GNEG, a, t); }
    let r = mk_un(U_FNEG, a, t);
    if t == TY_FLIT && is_const(r) && (flit32[a] & FLIT32_OK) != 0 { flit32[r] = flit32[a] ^ 2147483648; }
    return r;
  }
  if !ty_int(t) { fail_ty("operator needs an integer, found ", t); }
  if t == TY_ILIT { return mk_un(op, a, TY_ILIT); }
  if op == U_NEG && t == TY_U64 { fail("cannot negate an unsigned value (use 0 - x)"); }
  a = conv(a, promote(t));
  return mk_un(op, a, promote(t));
}
fn narrow_op(t: i64) -> i64 { // int -> narrower int
  if t == TY_I8 { return U_SX8; } if t == TY_I16 { return U_SX16; } if t == TY_I32 { return U_SX32; }
  if t == TY_U8 { return U_ZX8; } if t == TY_U16 { return U_ZX16; } return U_ZX32;
}
fn sat_op(t: i64) -> i64 {
  if t == TY_I8 { return U_SATS8; } if t == TY_I16 { return U_SATS16; } if t == TY_I32 { return U_SATS32; }
  if t == TY_U8 { return U_SATU8; } if t == TY_U16 { return U_SATU16; } return U_SATU32;
}
fn typed_cast(e0: i64, t: i64) -> i64 {
  let mut e = e0;
  let mut s = nd[e].ty; errnode = e;
  if s == TY_UNIT { fail("this function returns no value"); }
  if t == TY_BOOL { fail("cannot cast to bool (compare with 0 instead)"); }
  if s == TY_ILIT { e = conv(e, TY_I64); s = TY_I64; }
  if s == TY_FLIT { e = conv(e, TY_F64); s = TY_F64; }
  if s == t { return e; }
  if s == TY_BOOL { if !ty_int(t) { fail("bool converts only to integer types"); } nd[e].ty = t; return e; }
  if ty_int(s) && ty_int(t) {
    if t == TY_I64 || t == TY_U64 || widens(s, t) { nd[e].ty = t; return e; }
    return mk_un(narrow_op(t), e, t);
  }
  if ty_int(s) && ty_flt(t) {
    let mut op = 0;
    if s == TY_U64 { if t == TY_F64 { op = U_U2D; } else { op = U_U2S; } }
    else { if t == TY_F64 { op = U_I2D; } else { op = U_I2S; } }
    return mk_un(op, e, t);
  }
  if ty_flt(s) && ty_flt(t) { if t == TY_F64 { return mk_un(U_S2D, e, t); } return mk_un(U_D2S, e, t); }
  if ty_flt(s) && ty_int(t) {
    if t == TY_U64 { if s == TY_F64 { return mk_un(U_D2U, e, t); } return mk_un(U_S2U, e, t); }
    let mut op = U_S2I; if s == TY_F64 { op = U_D2I; }
    let r = mk_un(op, e, TY_I64);
    if t == TY_I64 { return r; }
    return mk_un(sat_op(t), r, t);
  }
  fail_ty2("cannot cast ", s, " to ", t); return -1;
}
fn scalar_type(off: i64, n: i64) -> i64 {
  if eqs(off, n, "i8") { return TY_I8; } if eqs(off, n, "i16") { return TY_I16; }
  if eqs(off, n, "i32") { return TY_I32; } if eqs(off, n, "i64") { return TY_I64; }
  if eqs(off, n, "u8") { return TY_U8; } if eqs(off, n, "u16") { return TY_U16; }
  if eqs(off, n, "u32") { return TY_U32; } if eqs(off, n, "u64") { return TY_U64; }
  if eqs(off, n, "bool") { return TY_BOOL; } if eqs(off, n, "f32") { return TY_F32; }
  if eqs(off, n, "f64") { return TY_F64; }
  return 0;
}
fn parse_type_s(allow_struct: bool) -> i64 {
  if tk_kind != T_ID { fail("expected a type"); }
  let t = scalar_type(tk_noff, tk_nlen);
  if t != 0 { next(); return t; }
  let mut i = 0;
  while i < nst {
    if eqn(sts[i].noff, sts[i].nlen, tk_noff, tk_nlen) {
      if !allow_struct { fail("a struct can only be an array element type"); }
      next(); return TY_STRUCT0 + i;
    }
    i += 1;
  }
  fail_name("unknown type", tk_noff, tk_nlen); return -1;
}
fn parse_type() -> i64 { return parse_type_s(false); }
fn lookup_arr(off: i64, n: i64) -> i64 { let v = lookup(off, n); if vars[v].arr == 0 { fail("not an array"); } return v; }
fn mk_load(a: i64, idx: i64) -> i64 {
  vars[vars[a].basev].reads += 1; if vars[a].lenv >= 0 { vars[vars[a].lenv].reads += 1; }
  let e = mk(N_LOAD); nd[e].var = a; nd[e].a = idx; nd[e].chk = 1; nd[e].ty = vars[a].et; return e;
}
fn copy_node(r: i64, e: i64) {
  nd[r].k = nd[e].k; nd[r].op = nd[e].op; nd[r].a = nd[e].a; nd[r].b = nd[e].b; nd[r].c = nd[e].c; nd[r].next = nd[e].next;
  nd[r].var = nd[e].var; nd[r].pos = nd[e].pos; nd[r].chk = nd[e].chk; nd[r].nn = nd[e].nn; nd[r].ty = nd[e].ty;
  nd[r].v = nd[e].v; nd[r].dlo = nd[e].dlo; nd[r].dhi = nd[e].dhi; nd[r].src = nd[e].src; flit32[r] = flit32[e];
}
fn clone_expr(e: i64) -> i64 {
  if e < 0 { return -1; }
  let ck = nd[e].k; let ca = nd[e].a; let cb = nd[e].b; let cv = nd[e].var;
  let r = mk(ck); copy_node(r, e); nd[r].c = -1;
  if ck == N_VAR { vars[cv].reads += 1; }
  if ck == N_LOAD || ck == N_ARR { vars[vars[cv].basev].reads += 1; if vars[cv].lenv >= 0 { vars[vars[cv].lenv].reads += 1; } }
  nd[r].a = clone_expr(ca); nd[r].b = clone_expr(cb);
  if ck != N_CALL { nd[r].next = -1; }
  else {
    let mut prev = -1; nd[r].a = -1;
    let mut x = ca;
    while x >= 0 { let y = clone_expr(x); nd[y].next = -1; if prev < 0 { nd[r].a = y; } else { nd[prev].next = y; } prev = y; x = nd[x].next; }
  }
  return r;
}
fn find_fn(off: i64, n: i64) -> i64 {
  let mut i = 0;
  while i < nfn_decl { if eqn(fns[i].noff, fns[i].nlen, off, n) { return i; } i += 1; }
  return -1;
}
fn find_fn_lit(name: [u8]) -> i64 {
  let mut i = 0;
  while i < nfn_decl { if eqs(fns[i].noff, fns[i].nlen, name) { return i; } i += 1; }
  return -1;
}
fn str_array(v: i64, soff: i64, slen: i64) -> i64 {
  vars[v].arr = 1; vars[v].et = TY_U8; vars[v].ty = TY_NONE; vars[v].ro = 1; vars[v].alen = slen;
  let b = hidden(); vars[b].isconst = 1; vars[b].cval = soff as u64; vars[b].glob = 2; vars[b].owner = -1;
  vars[v].basev = b; return v;
}
fn parse_call(off: i64, n: i64) -> i64 { // current token is '('
  if starts2u(off, n) && !in_prelude { fail("names starting with __ are reserved"); }
  let f = find_fn(off, n);
  if f < 0 { fail_name("call to undefined function", off, n); }
  if f == mainfn { fail("main cannot be called"); }
  expect('(');
  let e = mk(N_CALL); nd[e].var = f; nd[e].ty = fns[f].rett;
  let mut prev = -1;
  let mut i = 0;
  while tk_kind != ')' {
    if i >= fns[f].np { fail("too many arguments"); }
    let mut ag = 0;
    let pi = f * 16 + i;
    if fpw[pi] != 0 && tk_kind == T_STR {
      if fpty[pi] != TY_U8 || fpmut[pi] != 0 { fail("a string literal is a read-only [u8]"); }
      let so = tk_soff; let sl = tk_slen; next();
      let a = str_array(hidden(), so, sl);
      vars[vars[a].basev].reads += 1;
      ag = mk(N_ARR); nd[ag].var = a; nd[ag].ty = TY_NONE;
    } else if fpw[pi] != 0 {
      if tk_kind != T_ID || find_var(tk_noff, tk_nlen) < 0 || vars[find_var(tk_noff, tk_nlen)].arr == 0 { fail("array parameter needs an array argument"); }
      let a = find_var(tk_noff, tk_nlen); next();
      if vars[a].et != fpty[pi] { fail_ty2("array element type mismatch: expected [", fpty[pi], "], found [", vars[a].et); }
      if fpmut[pi] != 0 && vars[a].ro != 0 { fail("read-only array passed to a mut parameter"); }
      vars[vars[a].basev].reads += 1; if vars[a].lenv >= 0 { vars[vars[a].lenv].reads += 1; }
      ag = mk(N_ARR); nd[ag].var = a; nd[ag].ty = TY_NONE;
    } else {
      if tk_kind == T_ID && find_var(tk_noff, tk_nlen) >= 0 && vars[find_var(tk_noff, tk_nlen)].arr != 0 {
        let pk = peek_kind();
        if pk == ',' || pk == ')' { fail("array passed where a scalar is expected"); }
      }
      ag = conv(parse_expr(), fpty[pi]);
    }
    nd[ag].next = -1;
    if prev < 0 { nd[e].a = ag; } else { nd[prev].next = ag; }
    prev = ag; i += 1;
    if tk_kind != ',' { break; }
    next();
  }
  expect(')');
  if i != fns[f].np { fail("too few arguments"); }
  return e;
}
fn parse_field(st: i64) -> i64 {
  let s = st - TY_STRUCT0;
  if tk_kind != '.' { fail("struct element: access a field (a[i].field)"); }
  next(); if tk_kind != T_ID { fail("expected a field name"); }
  let mut f = 0;
  while f < sts[s].nf {
    if eqn(sfnoff[s * 32 + f], sfnlen[s * 32 + f], tk_noff, tk_nlen) { next(); return f; }
    f += 1;
  }
  fail_name("no such field", tk_noff, tk_nlen); return -1;
}
fn mk_call1(name: [u8], ag: i64) -> i64 {
  let f = find_fn_lit(name); if f < 0 { fail("internal: missing prelude function"); }
  let e = mk(N_CALL); nd[e].var = f; nd[e].ty = fns[f].rett; nd[e].a = ag; nd[ag].next = -1; return e;
}
fn retag(e: i64, t: i64) -> i64 { nd[e].ty = t; return e; }
fn builtin_arg() -> i64 { expect('('); let e = parse_expr(); expect(')'); return e; }
fn atom() -> i64 {
  if tk_kind == T_NUM { let v = tk_value; let big = tk_big; next(); if big { return mkconst_t(v, TY_U64); } return mkconst_t(v, TY_ILIT); }
  if tk_kind == T_FNUM { let d = tk_fval; let d32 = tk_fval32; next(); let e = mkconst_t(d, TY_FLIT); flit32[e] = d32 | FLIT32_OK; return e; }
  if tk_kind == T_TRUE || tk_kind == T_FALSE { let v = (tk_kind == T_TRUE) as u64; next(); return mkconst_t(v, TY_BOOL); }
  if tk_kind == '(' { next(); let e = parse_expr(); expect(')'); return e; }
  if tk_kind == T_ID {
    let no = tk_noff; let nl = tk_nlen; let ids = tstart;
    next();
    if find_var(no, nl) < 0 && tk_kind != '(' { tstart = ids; fail_name("unknown variable", no, nl); }
    if tk_kind == '(' && find_var(no, nl) < 0 {
      if eqs(no, nl, "argc") { if curfn != mainfn { fail("argc() is only available in main"); } next(); expect(')'); return var_ref(0); }
      if eqs(no, nl, "ncpu") { next(); expect(')'); return mk(N_NCPU); }
      if eqs(no, nl, "len") {
        next(); if tk_kind != T_ID { fail("len() expects an array"); }
        let a = lookup_arr(tk_noff, tk_nlen); next(); expect(')');
        if vars[a].lenv < 0 { return mkconst_t(vars[a].alen as u64, TY_I64); }
        return var_ref(vars[a].lenv);
      }
      if eqs(no, nl, "bits") {
        let mut e = builtin_arg(); if nd[e].ty == TY_FLIT { e = conv(e, TY_F64); }
        if nd[e].ty == TY_F64 { return retag(e, TY_U64); }
        if nd[e].ty == TY_F32 { return retag(e, TY_U32); }
        fail("bits() expects a float");
      }
      if eqs(no, nl, "f64_from_bits") { return retag(conv(builtin_arg(), TY_U64), TY_F64); }
      if eqs(no, nl, "f32_from_bits") { return retag(conv(builtin_arg(), TY_U32), TY_F32); }
      if eqs(no, nl, "sqrt") {
        let mut e = builtin_arg(); if nd[e].ty == TY_FLIT { e = conv(e, TY_F64); }
        if nd[e].ty == TY_F64 { return mk_un(U_SQRTD, e, TY_F64); }
        if nd[e].ty == TY_F32 { return mk_un(U_SQRTS, e, TY_F32); }
        fail("sqrt() expects a float");
      }
      return parse_call(no, nl);
    }
    if tk_kind == '[' {
      let a = lookup_arr(no, nl); next(); let idx = need_int(parse_expr()); expect(']');
      let e = mk_load(a, idx);
      if is_struct(vars[a].et) { let f = parse_field(vars[a].et); nd[e].op = f + 1; nd[e].ty = sfty[(vars[a].et - TY_STRUCT0) * 32 + f]; }
      return e;
    }
    return var_ref(lookup(no, nl));
  }
  fail("expected expression"); return -1;
}
fn unary() -> i64 {
  enter();
  let mut r = 0;
  let st = tstart;
  if tk_kind == '-' { next(); r = typed_un(U_NEG, unary()); }
  else if tk_kind == '~' { next(); r = typed_un(U_NOT, unary()); }
  else if tk_kind == '!' { next(); r = typed_un(U_LNOT, unary()); }
  else if tk_kind == '+' { next(); r = unary(); if !ty_num(nd[r].ty) { fail("unary + needs a number"); } }
  else { r = atom(); }
  nd[r].src = st - source; errnode = -1;
  depth -= 1; return r;
}
fn cast_level() -> i64 {
  let mut r = unary();
  let sp = nd[r].src;
  while tk_kind == T_AS { next(); let t = parse_type(); r = typed_cast(r, t); nd[r].src = sp; errnode = -1; }
  return r;
}
let mut BL_OP: i64 = 0;
fn binlevel() -> i64 {
  let k = tk_kind;
  if k == T_LOR { BL_OP = O_LOR; return 1; } if k == T_LAND { BL_OP = O_LAND; return 2; }
  if k == T_EQ { BL_OP = O_EQ; return 3; } if k == T_NE { BL_OP = O_NE; return 3; }
  if k == '<' { BL_OP = O_LT; return 3; } if k == T_LE { BL_OP = O_LE; return 3; }
  if k == '>' { BL_OP = O_GT; return 3; } if k == T_GE { BL_OP = O_GE; return 3; }
  if k == '|' { BL_OP = O_OR; return 4; } if k == '^' { BL_OP = O_XOR; return 5; } if k == '&' { BL_OP = O_AND; return 6; }
  if k == T_SHL { BL_OP = O_SHL; return 7; } if k == T_SHR { BL_OP = O_SAR; return 7; } if k == T_SHRU { BL_OP = O_SHR; return 7; }
  if k == '+' { BL_OP = O_ADD; return 8; } if k == '-' { BL_OP = O_SUB; return 8; }
  if k == '*' { BL_OP = O_MUL; return 9; } if k == '/' { BL_OP = O_DIV; return 9; } if k == '%' { BL_OP = O_MOD; return 9; }
  return 0;
}
fn parse_bin(min: i64) -> i64 {
  let mut a = cast_level();
  while true {
    let l = binlevel();
    let op = BL_OP;
    if l == 0 || l < min { break; }
    next();
    let b = parse_bin(l + 1);
    a = typed_bin(op, a, b);
    if l == 3 && binlevel() == 3 { fail("comparison operators cannot be chained"); }
  }
  return a;
}
fn parse_expr() -> i64 { return parse_bin(1); }
let RESERVED = " argc argv len print putc write ewrite save exit alloc8 alloc16 alloc32 alloc64 shared8 shared16 shared32 shared64 ncpu alloc shared view bits f64_from_bits f32_from_bits sqrt file view16 view32 view64 i8 i16 i32 i64 u8 u16 u32 u64 bool f32 f64 fn main ";
fn in_wordlist(off: i64, n: i64, list: [u8]) -> bool { // list: words separated (and surrounded) by spaces
  let mut i = 0;
  while i < len(list) {
    if list[i] == 32 {
      let mut j = 0;
      while j < n && i + 1 + j < len(list) && list[i + 1 + j] == src[off + j] { j += 1; }
      if j == n && i + 1 + n < len(list) && list[i + 1 + n] == 32 { return true; }
    }
    i += 1;
  }
  return false;
}
fn clear_var(v: i64) {
  vars[v].noff = 0; vars[v].nlen = 0; vars[v].mutv = 0; vars[v].isconst = 0; vars[v].alias = 0; vars[v].hoist = 0;
  vars[v].reads = 0; vars[v].start = 0; vars[v].end = 0; vars[v].reg = -1; vars[v].slot = -1; vars[v].cval = 0;
  vars[v].weight = 0; vars[v].arr = 0; vars[v].ro = 0; vars[v].basev = 0; vars[v].lenv = -1; vars[v].shared = 0;
  vars[v].alen = 0; vars[v].lenof = 0; vars[v].aid = 0; vars[v].ty = TY_I64; vars[v].et = 0; vars[v].owner = 0;
  vars[v].glob = 0; vars[v].garr = 0; vars[v].xr = -1; forvar[v] = false; vflit32[v] = 0;
}
fn hidden() -> i64 {
  if nv >= MAX_VARS { fail("too many variables"); }
  clear_var(nv);
  if parsing { vars[nv].owner = curfn; } else { vars[nv].owner = -1; }
  nv += 1; return nv - 1;
}
fn declare(off: i64, n: i64, mut_: bool) -> i64 {
  errnode = -1; tstart = off;   // errors point at the name
  if in_wordlist(off, n, RESERVED) { fail_name("reserved name", off, n); }
  if starts2u(off, n) && !in_prelude { fail("names starting with __ are reserved"); }
  let mut j = 0;
  while j < nvis { if eqn(vars[vis[j]].noff, vars[vis[j]].nlen, off, n) { fail_name("variable already declared (shadowing not allowed):", off, n); } j += 1; }
  if nv >= MAX_VARS { fail("too many variables"); }
  clear_var(nv);
  vars[nv].noff = off; vars[nv].nlen = n; vars[nv].mutv = mut_ as i64; vars[nv].owner = curfn;
  vis[nvis] = nv; nvis += 1; nv += 1; return nv - 1;
}
let CTORS = " alloc shared view file argv alloc8 alloc16 alloc32 alloc64 shared8 shared16 shared32 shared64 view16 view32 view64 ";
fn legacy_et(b: i64) -> i64 { if b == 8 { return TY_U8; } if b == 16 { return TY_I16; } if b == 32 { return TY_I32; } return TY_I64; }
fn digits_at(off: i64, n: i64) -> i64 { let mut v = 0; let mut i = 0; while i < n { v = v * 10 + (src[off + i] - '0'); i += 1; } return v; }
let mut LB_MARK: i64 = -1;   // arena mark of the loop body parsed last
fn loop_body(fv: i64) -> i64 {
  loopdepth += 1; loopmark[loopdepth] = -1; loopfor[loopdepth] = fv;
  let b = parse_block();
  LB_MARK = loopmark[loopdepth]; loopdepth -= 1;
  return b;
}
fn mk_while(c: i64, b: i64) -> i64 {
  let s = mk(S_WHILE); nd[s].a = c; nd[s].b = b; nd[s].c = LB_MARK;
  if LB_MARK >= 0 { vars[LB_MARK].reads += 3; }
  return s;
}
fn for_step(v: i64) -> i64 { let s = mk(S_ASSIGN); nd[s].var = v; nd[s].a = typed_bin(O_ADD, var_ref(v), mkconst_t(1, TY_ILIT)); return s; }
fn parse_stmt() -> i64 {
  enter();
  let mut s = 0;
  let k = tk_kind;
  if k == T_LET || k == T_CONST {
    next();
    let mut mut_ = false;
    if tk_kind == T_MUT { if k == T_CONST { fail("a const cannot be mut"); } mut_ = true; next(); }
    if tk_kind != T_ID { fail("expected variable name"); }
    let no = tk_noff; let nl = tk_nlen; next();
    let mut ann = TY_NONE; let mut aarr = false;
    if tk_kind == ':' { next(); if tk_kind == '[' { next(); aarr = true; ann = parse_type_s(true); expect(']'); } else { ann = parse_type(); } }
    expect('=');
    if k == T_CONST && (aarr || tk_kind == T_STR || (tk_kind == T_ID && in_wordlist(tk_noff, tk_nlen, CTORS) && find_var(tk_noff, tk_nlen) < 0)) {
      fail("a const is a scalar (use let for arrays)");
    }
    if tk_kind == T_STR {
      if mut_ { fail("array bindings are immutable (their elements are not)"); }
      if ann != 0 && (!aarr || ann != TY_U8) { fail("a string literal is a [u8]"); }
      let so = tk_soff; let sl = tk_slen; next(); expect(';');
      let v = declare(no, nl, false);
      vars[v].arr = 1; vars[v].et = TY_U8; vars[v].ty = TY_NONE; vars[v].ro = 1; vars[v].alen = sl; vars[v].basev = hidden();
      vars[vars[v].basev].reads += 1;
      s = mk(S_ARR); nd[s].var = v; nd[s].op = A_STR; nd[s].v = so as u64; nd[s].chk = 1;
      depth -= 1; return s;
    }
    if tk_kind == T_ID && in_wordlist(tk_noff, tk_nlen, CTORS) && find_var(tk_noff, tk_nlen) < 0 {
      let co = tk_noff; let cl = tk_nlen; next();
      let mut kind = 0; let mut et = 0; let mut srcv = -1; let mut ag = -1; let mut shr = false;
      if eqs(co, cl, "alloc") || eqs(co, cl, "shared") || eqs(co, cl, "view") {
        expect('<'); et = parse_type_s(true); expect('>');
        shr = src[co] == 's';
        if src[co] == 'v' { kind = A_VIEW; } else { kind = A_ALLOC; }
      } else if eqs(co, cl, "file") { kind = A_FILE; et = TY_U8; }
      else if eqs(co, cl, "argv") { kind = A_ARG; et = TY_U8; }
      else if src[co] == 'a' { kind = A_ALLOC; et = legacy_et(digits_at(co + 5, cl - 5)); }
      else if src[co] == 's' { kind = A_ALLOC; shr = true; et = legacy_et(digits_at(co + 6, cl - 6)); }
      else { kind = A_VIEW; et = legacy_et(digits_at(co + 4, cl - 4)); }
      let w = ty_width(et);
      if kind == A_VIEW && et == TY_BOOL { fail("no bool views (a byte is not always a valid bool)"); }
      if kind == A_VIEW && is_struct(et) {
        let st = et - TY_STRUCT0;
        let mut fi = 0;
        while fi < sts[st].nf {
          if sfty[st * 32 + fi] == TY_BOOL { fail("no views of structs containing bool (a byte is not always a valid bool)"); }
          fi += 1;
        }
      }
      if ann != 0 && (!aarr || ann != et) { fail("array type annotation does not match the constructor"); }
      if inpar && kind != A_VIEW && kind != A_ARG { fail("no allocation or file mapping inside a par block"); }
      if mut_ { fail("array bindings are immutable (their elements are not)"); }
      let scoped = kind == A_ALLOC && (curfn != mainfn || loopdepth > 0);
      if kind == A_FILE && (loopdepth != 0 || curfn != mainfn) { fail("file() is only available at main's top level"); }
      if scoped && shr { fail("shared arrays are allocated at main's top level"); }
      if scoped {
        use_arena = true;
        if loopdepth != 0 && loopmark[loopdepth] < 0 { loopmark[loopdepth] = hidden(); }
        if curfn != mainfn && fns[curfn].mark < 0 { fns[curfn].mark = hidden(); }
      }
      expect('(');
      if kind == A_VIEW {
        if tk_kind != T_ID { fail("view expects an array"); }
        srcv = lookup_arr(tk_noff, tk_nlen);
        if vars[srcv].arr != 1 { fail("view source must be a byte array"); }
        next();
      } else { ag = conv(parse_expr(), TY_I64); }
      expect(')'); expect(';');
      let v = declare(no, nl, false);
      vars[v].arr = w; vars[v].et = et; vars[v].ty = TY_NONE; vars[v].shared = shr as i64;
      if kind == A_VIEW {
        vars[v].shared = vars[srcv].shared; vars[v].basev = vars[srcv].basev; vars[v].ro = vars[srcv].ro;
        if vars[srcv].lenv < 0 { vars[v].alen = vars[srcv].alen / w; }
        else { vars[v].lenv = hidden(); vars[vars[srcv].lenv].reads += 1; }
      } else {
        vars[v].basev = hidden(); vars[v].ro = (kind == A_FILE || kind == A_ARG) as i64;
        if kind == A_ARG {
          if curfn != mainfn { fail("ag() is only available in main"); }
          vars[0].reads += 1; vars[1].reads += 1; vars[v].lenv = hidden();
        } else if kind == A_FILE {
          if curfn != mainfn { fail("file() is only available in main"); }
          vars[0].reads += 1; vars[1].reads += 1; vars[v].lenv = hidden();
        } else if is_const(ag) {
          let n = nd[ag].v as i64;
          if n < 1 || n > 2147483647 { fail("array length must be 1..2^31-1"); }
          vars[v].alen = n;
        } else { vars[v].lenv = hidden(); }
      }
      vars[vars[v].basev].reads += 1;
      s = mk(S_ARR); nd[s].var = v; nd[s].a = ag; nd[s].op = kind; nd[s].c = srcv; nd[s].chk = w; nd[s].v = scoped as u64;
      depth -= 1; return s;
    }
    if aarr { fail("array type annotation needs an array constructor"); }
    let mut e = parse_expr(); expect(';');
    if ann != 0 { e = conv(e, ann); }
    else if mut_ { e = deflt(e); }
    if k == T_CONST && !is_const(e) { fail("a const value must be a compile-time constant"); }
    else if nd[e].ty == TY_UNIT { fail("this function returns no value"); }
    let v = declare(no, nl, mut_); vars[v].ty = nd[e].ty;
    if !mut_ && is_const(e) { vars[v].isconst = 1; vars[v].cval = nd[e].v; vflit32[v] = flit32[e]; s = mk(S_BLOCK); }
    else if !mut_ && nd[e].k == N_VAR && vars[nd[e].var].mutv == 0 && nd[e].ty == vars[nd[e].var].ty {
      vars[v].alias = nd[e].var + 1; vars[nd[e].var].reads -= 1; s = mk(S_BLOCK);
    } else { s = mk(S_LET); nd[s].var = v; nd[s].a = e; }
    depth -= 1; return s;
  }
  if k == T_IF {
    next();
    let c = need_bool(parse_expr());
    let t = parse_block();
    let mut el = -1;
    if tk_kind == T_ELSE { next(); if tk_kind == T_IF { el = parse_stmt(); } else { el = parse_block(); } }
    s = mk(S_IF); nd[s].a = c; nd[s].b = t; nd[s].c = el;
    depth -= 1; return s;
  }
  if k == T_WHILE {
    next();
    let c = need_bool(parse_expr());
    s = mk_while(c, loop_body(-1));
    depth -= 1; return s;
  }
  if k == T_LOOP {
    next();
    s = mk_while(mkconst_t(1, TY_BOOL), loop_body(-1));
    depth -= 1; return s;
  }
  if k == T_FOR {
    // for i in a..b { body }  =>  { let mut i = a; [let end = b;] while i < end { body; i += 1; } }
    // (`..=` compares with <=; `continue` in the body becomes `{ i += 1; continue; }`)
    next(); if tk_kind != T_ID { fail("expected loop variable"); }
    let no = tk_noff; let nl = tk_nlen; next(); expect(T_IN);
    let mut a = parse_expr();
    let incl = tk_kind == T_DOTDOTEQ;
    if tk_kind != T_DOTDOT && !incl { fail("expected `..` or `..=` in a for range"); }
    next();
    let mut b = parse_expr();
    let mut t = TY_I64; if nd[a].ty == TY_U64 || nd[b].ty == TY_U64 { t = TY_U64; }
    a = conv(a, t); b = conv(b, t);
    let mark = nvis;
    let iv = declare(no, nl, true); vars[iv].ty = t; forvar[iv] = true;
    let init = mk(S_LET); nd[init].var = iv; nd[init].a = a;
    // the bound is evaluated once: constants, immutable scalars and enclosing for variables
    // (read-only in this body) are used as they are
    let mut en = b;
    if !is_const(b) && !(nd[b].k == N_VAR && (vars[nd[b].var].mutv == 0 || forvar[nd[b].var])) {
      let ev = hidden(); vars[ev].ty = t;
      let hl = mk(S_LET); nd[hl].var = ev; nd[hl].a = b; nd[init].next = hl; en = mk_var(ev);
    }
    let mut op = O_LT; if incl { op = O_LE; }
    let c = typed_bin(op, mk_var(iv), en);
    let body = loop_body(iv);
    nvis = mark;
    let inc = for_step(iv);
    let mut last = nd[body].a;
    if last < 0 { nd[body].a = inc; } else { while nd[last].next >= 0 { last = nd[last].next; } nd[last].next = inc; }
    let w = mk_while(c, body);
    last = init; while nd[last].next >= 0 { last = nd[last].next; } nd[last].next = w;
    s = mk(S_BLOCK); nd[s].a = init;
    depth -= 1; return s;
  }
  if k == T_RETURN {
    if inpar { fail("return inside a par block"); }
    next();
    let mut e = 0;
    if fns[curfn].rett == TY_UNIT { if tk_kind != ';' { fail("this function returns no value: use `return;`"); } e = mkconst(0); }
    else { e = conv(parse_expr(), fns[curfn].rett); }
    expect(';'); s = mk(S_RET); nd[s].a = e;
    depth -= 1; return s;
  }
  if k == T_PAR {
    if curfn != mainfn { fail("par is only available in main"); }
    if inpar { fail("nested par blocks are not allowed"); }
    next(); if tk_kind != T_ID { fail("expected worker variable"); }
    let no = tk_noff; let nl = tk_nlen; next(); expect(T_IN);
    let a = conv(parse_expr(), TY_I64); expect(T_DOTDOT); let b = conv(parse_expr(), TY_I64);
    let pend = hidden(); vars[pend].reads += 2;
    let mark = nvis;
    let kv = declare(no, nl, false); vars[kv].reads += 2;
    let sv_loop = loopdepth; loopdepth = 0; inpar = true; par_outer_nv = kv;
    let bd = parse_block();
    inpar = false; loopdepth = sv_loop; nvis = mark;
    s = mk(S_PAR); nd[s].var = kv; nd[s].a = a; nd[s].b = b; nd[s].c = bd; nd[s].op = pend;
    depth -= 1; return s;
  }
  if k == T_BREAK || k == T_CONTINUE {
    let mut kk = S_CONT; if k == T_BREAK { kk = S_BRK; }
    if loopdepth == 0 { fail("break/continue outside loop"); }
    next(); expect(';'); s = mk(kk);
    if kk == S_CONT && loopfor[loopdepth] >= 0 {   // a for loop steps its variable before the next test
      let st = for_step(loopfor[loopdepth]); nd[st].next = s;
      s = mk(S_BLOCK); nd[s].a = st;
    }
    depth -= 1; return s;
  }
  if k == '{' { s = parse_block(); depth -= 1; return s; }
  if k == T_ID {
    let isvar = find_var(tk_noff, tk_nlen) >= 0;
    let no = tk_noff; let nl = tk_nlen;
    if !isvar && inpar && (eqs(no, nl, "print") || eqs(no, nl, "putc") || eqs(no, nl, "write") || eqs(no, nl, "ewrite")) {
      fail("no output inside a par block (write results to a shared array; print after it)");
    }
    if !isvar && eqs(no, nl, "print") {
      next(); expect('('); let e = deflt(parse_expr()); expect(')'); expect(';');
      let t = nd[e].ty;
      if ty_int(t) { s = mk(S_PRINT); nd[s].a = e; nd[s].op = (t == TY_U64) as i64; }
      else if t == TY_BOOL { s = mk(S_EXPR); nd[s].a = mk_call1("__print_bool", e); }
      else if ty_flt(t) {
        s = mk(S_EXPR);
        let mut ee = e; if t == TY_F32 { ee = typed_cast(e, TY_F64); }
        nd[s].a = mk_call1("__print_f64", ee);
      }
      else { fail("print() expects a number or bool"); }
      depth -= 1; return s;
    }
    if !isvar && eqs(no, nl, "putc") {
      next(); expect('('); let e = need_int(parse_expr()); expect(')'); expect(';');
      s = mk(S_PUTC); nd[s].a = e; depth -= 1; return s;
    }
    if !isvar && eqs(no, nl, "exit") {
      if inpar { fail("no exit inside a par block"); }
      next(); expect('('); let e = conv(parse_expr(), TY_I64); expect(')'); expect(';');
      s = mk(S_PUTC); nd[s].a = e; nd[s].op = 1; depth -= 1; return s;
    }
    if !isvar && eqs(no, nl, "save") {
      if curfn != mainfn { fail("save() is only available in main"); }
      if inpar { fail("no output inside a par block"); }
      next(); expect('('); let kk = conv(parse_expr(), TY_I64); expect(',');
      if tk_kind != T_ID { fail("save() expects a byte array"); }
      let a = lookup_arr(tk_noff, tk_nlen); if vars[a].arr != 1 || vars[a].et == TY_BOOL { fail("save() expects a byte array"); }
      next(); expect(',');
      let nb = conv(parse_expr(), TY_I64); expect(')'); expect(';');
      vars[vars[a].basev].reads += 1; if vars[a].lenv >= 0 { vars[vars[a].lenv].reads += 1; } vars[0].reads += 1; vars[1].reads += 1;
      s = mk(S_SAVE); nd[s].var = a; nd[s].a = kk; nd[s].b = nb; nd[s].chk = 1;
      depth -= 1; return s;
    }
    if !isvar && (eqs(no, nl, "write") || eqs(no, nl, "ewrite")) {
      next(); expect('(');
      s = mk(S_WRITE); nd[s].a = -1; nd[s].b = -1; nd[s].chk = 1; nd[s].op = (src[no] == 'e') as i64;
      if tk_kind == T_STR { nd[s].var = -1; nd[s].v = tk_soff as u64; nd[s].c = tk_slen; next(); }
      else {
        if tk_kind != T_ID { fail("write() expects a byte array"); }
        let a = lookup_arr(tk_noff, tk_nlen); if vars[a].arr != 1 || vars[a].et == TY_BOOL { fail("write() expects a byte array"); }
        next();
        vars[vars[a].basev].reads += 1; if vars[a].lenv >= 0 { vars[vars[a].lenv].reads += 1; }
        nd[s].var = a;
        if tk_kind == ',' { next(); nd[s].a = conv(parse_expr(), TY_I64); expect(','); nd[s].b = conv(parse_expr(), TY_I64); }
      }
      expect(')'); expect(';');
      depth -= 1; return s;
    }
    if !isvar && peek_kind() == '(' {
      next();
      let e = parse_call(no, nl); expect(';'); s = mk(S_EXPR); nd[s].a = e;
      depth -= 1; return s;
    }
    let mut v = lookup(no, nl); next();
    let mut gidx = -1;
    if vars[v].garr != 0 {
      if vars[v].mutv == 0 { fail("assignment to immutable variable"); }
      let t = vars[v].ty; v = vars[v].garr; gidx = mkconst(0); vars[v].et = t;
    }
    if vars[v].arr != 0 {
      if vars[v].ro != 0 { fail("store to read-only array"); }
      let mut et = vars[v].et;
      let mut fld = -1;
      let mut idx = 0;
      if gidx >= 0 { idx = gidx; }
      else { expect('['); idx = need_int(parse_expr()); expect(']'); }
      if is_struct(et) { fld = parse_field(et); et = sfty[(et - TY_STRUCT0) * 32 + fld]; }
      let mut op = -1;
      let mut val = 0;
      if tk_kind == '=' { next(); val = conv(parse_expr(), et); }
      else if tk_kind == T_OPEQ {
        op = tk_op; next();
        let r = parse_expr();
        if ty_int(et) && (op == O_ADD || op == O_SUB || op == O_AND || op == O_OR || op == O_XOR) {
          let probe = mkconst_t(0, et);
          TB_A = probe; TB_B = r; type_bin(op); val = TB_B;
        } else {
          expect(';');
          // The index runs after r. Constants and local scalars cannot change
          // through r, so use them directly; snapshot all other expressions.
          let direct = is_const(idx) || (nd[idx].k == N_VAR && vars[nd[idx].var].glob == 0);
          let mut ti = -1;
          let mut l2 = -1;
          if !direct { ti = hidden(); vars[ti].ty = nd[idx].ty; l2 = mk(S_LET); nd[l2].var = ti; nd[l2].a = idx; }
          let mut head = l2;
          let mut rv = 0;
          if is_const(r) { rv = r; }
          else {
            let tv = hidden(); let r2 = deflt(r); vars[tv].ty = nd[r2].ty;
            let l1 = mk(S_LET); nd[l1].var = tv; nd[l1].a = r2; nd[l1].next = l2; head = l1; rv = mk_var(tv);
          }
          let st = mk(S_STORE); nd[st].var = v; nd[st].op = -1; nd[st].chk = 1; nd[st].c = fld;
          let mut ld = 0;
          if direct { nd[st].a = idx; ld = mk_load(v, clone_expr(idx)); }
          else { nd[st].a = mk_var(ti); ld = mk_load(v, mk_var(ti)); }
          if fld >= 0 { nd[ld].op = fld + 1; nd[ld].ty = et; } else if gidx >= 0 { nd[ld].ty = et; }
          let mut val2 = typed_bin(op, ld, rv);
          if !ty_int(et) || !ty_int(nd[val2].ty) { val2 = conv(val2, et); }
          nd[st].b = val2;
          vars[vars[v].basev].reads += 1; if vars[v].lenv >= 0 { vars[vars[v].lenv].reads += 1; }
          if head < 0 { head = st; }
          else if l2 >= 0 { nd[l2].next = st; }
          else { nd[head].next = st; }
          s = mk(S_BLOCK); nd[s].a = head;
          depth -= 1; return s;
        }
      } else { fail("expected assignment"); }
      expect(';');
      vars[vars[v].basev].reads += 1; if vars[v].lenv >= 0 { vars[vars[v].lenv].reads += 1; }
      s = mk(S_STORE); nd[s].var = v; nd[s].a = idx; nd[s].b = val; nd[s].op = op; nd[s].chk = 1; nd[s].c = fld;
      depth -= 1; return s;
    }
    if vars[v].mutv == 0 { fail("assignment to immutable variable"); }
    if forvar[v] { fail("assignment to a for loop variable"); }
    if inpar && v < par_outer_nv { fail("a par block cannot assign variables declared outside it (use a shared array)"); }
    let t = vars[v].ty;
    let mut e = 0;
    if tk_kind == '=' { next(); e = conv(parse_expr(), t); }
    else if tk_kind == T_OPEQ {
      let op = tk_op; next();
      let r = parse_expr();
      e = typed_bin(op, var_ref(v), r);
      if ty_int(t) && ty_int(nd[e].ty) && nd[e].ty != t { e = typed_cast(e, t); }
      else { e = conv(e, t); }
    } else { fail("expected assignment"); }
    expect(';'); s = mk(S_ASSIGN); nd[s].var = v; nd[s].a = e;
    depth -= 1; return s;
  }
  fail("expected statement"); return -1;
}
fn parse_block() -> i64 {
  enter(); expect('{');
  let mark = nvis;
  let b = mk(S_BLOCK);
  let mut last = -1;
  while tk_kind != '}' {
    if tk_kind == T_EOF { fail("unterminated block"); }
    let s = parse_stmt();
    if last < 0 { nd[b].a = s; } else { nd[last].next = s; }
    last = s;
  }
  next(); nvis = mark; depth -= 1; return b;
}
fn parse_header(f: i64, decl: bool) {
  expect(T_FN);
  if tk_kind != T_ID { fail("expected function name"); }
  if starts2u(tk_noff, tk_nlen) && !in_prelude { fail("names starting with __ are reserved"); }
  fns[f].noff = tk_noff; fns[f].nlen = tk_nlen; next(); expect('(');
  fns[f].np = 0;
  while tk_kind != ')' {
    if fns[f].np >= MAX_PARAMS { fail("too many parameters"); }
    let mut mut_ = false; if tk_kind == T_MUT { mut_ = true; next(); }
    if tk_kind != T_ID { fail("expected parameter name"); }
    let no = tk_noff; let nl = tk_nlen; next(); expect(':');
    let mut w = 0; let mut amut = false; let mut t = 0;
    if tk_kind == T_MUT || tk_kind == '[' {
      if tk_kind == T_MUT { amut = true; next(); }
      expect('['); t = parse_type_s(true); expect(']'); w = ty_width(t);
      if mut_ { fail("array parameters are bindings; use `name: mut [T]` for writable elements"); }
    } else { t = parse_type(); }
    let pi = f * 16 + fns[f].np;
    if decl {
      let v = declare(no, nl, w == 0 && mut_);
      if w != 0 {
        vars[v].arr = w; vars[v].et = t; vars[v].ty = TY_NONE; vars[v].ro = (!amut) as i64;
        vars[v].basev = hidden(); vars[v].lenv = hidden();
      } else { vars[v].ty = t; }
      fpvar[pi] = v;
    }
    fpw[pi] = w; fpty[pi] = t; fpmut[pi] = amut as i64; fns[f].np += 1;
    if tk_kind != ',' { break; }
    next();
  }
  expect(')');
  if tk_kind == T_ARROW { next(); fns[f].rett = parse_type(); } else { fns[f].rett = TY_UNIT; }
}
fn breaks_out(s: i64, d: i64) -> bool {   // a break that leaves the loop whose body holds s
  if s < 0 { return false; }
  let k = nd[s].k;
  if k == S_BRK { return d == 0; }
  if k == S_BLOCK { let mut c = nd[s].a; while c >= 0 { if breaks_out(c, d) { return true; } c = nd[c].next; } return false; }
  if k == S_IF { return breaks_out(nd[s].b, d) || breaks_out(nd[s].c, d); }
  if k == S_WHILE { return breaks_out(nd[s].b, d + 1); }
  return false;
}
fn parse_function(f: i64) {
  curfn = f; nvis = 0; fns[f].mark = -1;
  parse_header(f, true);
  if f == mainfn && fns[f].np != 0 { fail("main takes no parameters"); }
  if f == mainfn && fns[f].rett != TY_I64 && fns[f].rett != TY_UNIT { fail("main returns i64 or nothing"); }
  fns[f].body = parse_block();
  if fns[f].mark >= 0 { vars[fns[f].mark].reads += 2; }
  let mut last = -1;
  let mut s = nd[fns[f].body].a;
  while s >= 0 { last = s; s = nd[s].next; }
  if last < 0 || nd[last].k != S_RET {
    // a final `loop` with no break never falls through: the return after it is unreachable
    let spin = last >= 0 && nd[last].k == S_WHILE && is_const(nd[last].a) && nd[nd[last].a].v != 0 && !breaks_out(nd[last].b, 0);
    if fns[f].rett != TY_UNIT && !spin { fail("a function must end with a return statement"); }
    let r = mk(S_RET); nd[r].a = mkconst(0);
    if fns[f].rett != TY_UNIT { nd[r].a = mkconst_t(0, fns[f].rett); }
    if last < 0 { nd[fns[f].body].a = r; } else { nd[last].next = r; }
  }
}

// ---------------------------------------------------------------- top-level items
let GLOB_MAX = 1073741824;
let mut glob_bytes: i64 = 0;
let mut ginit_head: i64 = -1;
let mut ginit_tail: i64 = -1;
fn parse_struct() {
  expect(T_STRUCT);
  if tk_kind != T_ID { fail("expected struct name"); }
  if nst >= MAX_STRUCTS { fail("too many structs"); }
  let mut i = 0;
  while i < nst { if eqn(sts[i].noff, sts[i].nlen, tk_noff, tk_nlen) { fail("duplicate struct"); } i += 1; }
  if scalar_type(tk_noff, tk_nlen) != 0 { fail("reserved name"); }
  let s = nst;
  sts[s].noff = tk_noff; sts[s].nlen = tk_nlen; sts[s].nf = 0; sts[s].size = 0;
  next(); expect('{');
  let mut off = 0;
  let mut al = 1;
  while tk_kind != '}' {
    if sts[s].nf >= MAX_FIELDS { fail("too many fields"); }
    if tk_kind != T_ID { fail("expected field name"); }
    let mut f = 0;
    while f < sts[s].nf { if eqn(sfnoff[s * 32 + f], sfnlen[s * 32 + f], tk_noff, tk_nlen) { fail("duplicate field"); } f += 1; }
    let fi = s * 32 + sts[s].nf;
    sfnoff[fi] = tk_noff; sfnlen[fi] = tk_nlen; next(); expect(':');
    let t = parse_type();
    let w = ty_width(t);
    off = (off + w - 1) / w * w; sfoff[fi] = off; sfty[fi] = t; sts[s].nf += 1; off += w; if w > al { al = w; }
    if tk_kind != ',' { break; }
    next();
  }
  expect('}');
  if sts[s].nf == 0 { fail("a struct needs at least one field"); }
  sts[s].size = (off + al - 1) / al * al; nst += 1;
}
fn new_global(off: i64, n: i64, mut_: bool) -> i64 {
  errnode = -1; tstart = off;
  if in_wordlist(off, n, RESERVED) { fail_name("reserved name", off, n); }
  if starts2u(off, n) && !in_prelude { fail("names starting with __ are reserved"); }
  let mut j = 0;
  while j < ngvis { if eqn(vars[gvis[j]].noff, vars[gvis[j]].nlen, off, n) { fail("duplicate global"); } j += 1; }
  if nv >= MAX_VARS { fail("too many variables"); }
  clear_var(nv);
  vars[nv].noff = off; vars[nv].nlen = n; vars[nv].mutv = mut_ as i64; vars[nv].owner = -1;
  gvis[ngvis] = nv; ngvis += 1; nv += 1; return nv - 1;
}
fn static_array(v: i64, et: i64, n: i64) -> i64 {
  let w = ty_width(et);
  vars[v].arr = w; vars[v].et = et; vars[v].ty = TY_NONE; vars[v].alen = n; vars[v].glob = 1;
  let at = (glob_bytes + 63) & ~63;
  if n < 1 || n > 2147483647 || at + n * w > GLOB_MAX { fail("global arrays exceed the static limit (1 GiB)"); }
  glob_bytes = at + n * w;
  let b = hidden(); vars[b].isconst = 1; vars[b].cval = at as u64; vars[b].owner = -1; vars[b].glob = 1;
  vars[v].basev = b; return v;
}
fn parse_global() {
  let isc = tk_kind == T_CONST;
  if !isc { expect(T_LET); } else { next(); }
  let mut mut_ = false; if tk_kind == T_MUT { if isc { fail("a const cannot be mut"); } mut_ = true; next(); }
  if tk_kind != T_ID { fail("expected variable name"); }
  let no = tk_noff; let nl = tk_nlen; next();
  let mut ann = TY_NONE; let mut aarr = false;
  if tk_kind == ':' { next(); if tk_kind == '[' { next(); aarr = true; ann = parse_type_s(true); expect(']'); } else { ann = parse_type(); } }
  expect('=');
  if isc && (aarr || tk_kind == T_STR || (tk_kind == T_ID && eqs(tk_noff, tk_nlen, "alloc"))) { fail("a const is a scalar (use let for arrays)"); }
  if tk_kind == T_ID && eqs(tk_noff, tk_nlen, "alloc") {
    next(); expect('<'); let et = parse_type_s(true); expect('>'); expect('(');
    let n = conv(parse_expr(), TY_I64); expect(')'); expect(';');
    if mut_ { fail("array bindings are immutable (their elements are not)"); }
    if ann != 0 && (!aarr || ann != et) { fail("array type annotation does not match the constructor"); }
    if !is_const(n) { fail("a global array needs a constant length"); }
    static_array(new_global(no, nl, false), et, nd[n].v as i64);
    return;
  }
  if tk_kind == T_STR {
    if mut_ { fail("array bindings are immutable (their elements are not)"); }
    if ann != 0 && (!aarr || ann != TY_U8) { fail("a string literal is a [u8]"); }
    let so = tk_soff; let sl = tk_slen; next(); expect(';');
    str_array(new_global(no, nl, false), so, sl);
    return;
  }
  if aarr { fail("array type annotation needs alloc<T>(n)"); }
  let mut e = parse_expr(); expect(';');
  if !is_const(e) { fail("a global initializer must be a constant"); }
  if ann != 0 { e = conv(e, ann); } else if mut_ { e = deflt(e); }
  let v = new_global(no, nl, mut_); vars[v].ty = nd[e].ty;
  if !mut_ { vars[v].isconst = 1; vars[v].cval = nd[e].v; vflit32[v] = flit32[e]; return; }
  let g = hidden(); vars[g].owner = -1; static_array(g, nd[e].ty, 1); vars[v].garr = g;
  if nd[e].v != 0 {
    let st = mk(S_STORE); nd[st].var = g; nd[st].a = mkconst(0); nd[st].b = e; nd[st].op = -1; nd[st].chk = 1;
    vars[vars[g].basev].reads += 1;
    if ginit_tail < 0 { ginit_head = st; } else { nd[ginit_tail].next = st; }
    ginit_tail = st;
  }
}
fn skip_item() {
  let mut d = 0;
  while true {
    if tk_kind == T_EOF { return; }
    if tk_kind == T_STR { sdlen -= tk_slen; }
    if tk_kind == '{' { d += 1; }
    if tk_kind == '}' { d -= 1; if d == 0 { next(); return; } }
    if tk_kind == ';' && d == 0 { next(); return; }
    next();
  }
}
fn skip_fn() { while tk_kind != '{' && tk_kind != T_EOF { next(); } skip_item(); }
fn prescan() {
  let sp = pos; let ts = tstart; let sd = sdlen;
  let k0 = tk_kind; let o0 = tk_op; let b0 = tk_big; let v0 = tk_value; let f0 = tk_fval; let g0 = tk_fval32; let no = tk_noff; let nl = tk_nlen; let so = tk_soff; let sl = tk_slen;
  let mut d = 0;
  while tk_kind != T_EOF {
    if d == 0 && tk_kind == T_FN {
      if nfn >= MAX_FUNCS { fail("too many functions"); }
      let f = nfn; nfn += 1;
      fns[f].noff = 0; fns[f].nlen = 0; fns[f].np = 0; fns[f].body = 0; fns[f].used = 0; fns[f].exit_list = -1;
      fns[f].addr = 0; fns[f].calls = -1; fns[f].rett = 0; fns[f].mark = 0;
      parse_header(f, false);
      let mut i = 0;
      while i < f { if eqn(fns[i].noff, fns[i].nlen, fns[f].noff, fns[f].nlen) { fail("duplicate function"); } i += 1; }
      if !in_prelude && eqs(fns[f].noff, fns[f].nlen, "main") { mainfn = f; }
      continue;
    }
    if d == 0 && (tk_kind == T_STRUCT || tk_kind == T_LET || tk_kind == T_CONST) { skip_item(); continue; }
    if tk_kind == '{' { d += 1; } else if tk_kind == '}' { d -= 1; }
    next();
  }
  pos = sp; tstart = ts; sdlen = sd;
  tk_kind = k0; tk_op = o0; tk_big = b0; tk_value = v0; tk_fval = f0; tk_fval32 = g0; tk_noff = no; tk_nlen = nl; tk_soff = so; tk_slen = sl;
}
let fout_state = alloc<i64>(4096);
fn expr_outputs(e: i64) -> bool {
  if e < 0 { return false; }
  if nd[e].k == N_CALL {
    if fn_outputs(nd[e].var) { return true; }
    let mut a = nd[e].a;
    while a >= 0 { if expr_outputs(a) { return true; } a = nd[a].next; }
    return false;
  }
  if nd[e].k > N_ARR && nd[e].k != N_NCPU { return stmt_outputs(e); }
  return expr_outputs(nd[e].a) || expr_outputs(nd[e].b);
}
fn stmt_outputs(s: i64) -> bool {
  if s < 0 { return false; }
  let k = nd[s].k;
  if k <= N_ARR || k == N_NCPU { return expr_outputs(s); }
  if k == S_PRINT || k == S_PUTC || k == S_WRITE || k == S_SAVE { return true; }
  if expr_outputs(nd[s].a) { return true; }
  if k == S_STORE && expr_outputs(nd[s].b) { return true; }
  if k == S_IF && (stmt_outputs(nd[s].b) || stmt_outputs(nd[s].c)) { return true; }
  if k == S_WHILE && stmt_outputs(nd[s].b) { return true; }
  if k == S_BLOCK { let mut c = nd[s].a; while c >= 0 { if stmt_outputs(c) { return true; } c = nd[c].next; } }
  return false;
}
fn fn_outputs(f: i64) -> bool {
  if fout_state[f] == 1 || fout_state[f] == 3 { return fout_state[f] == 3; }
  if fout_state[f] == 2 { return false; }
  fout_state[f] = 1;
  let r = stmt_outputs(fns[f].body);
  if r { fout_state[f] = 3; } else { fout_state[f] = 2; }
  return r;
}
fn check_par() {
  let mut i = 0;
  while i < nn {
    if nd[i].k == S_PAR && stmt_outputs(nd[i].c) { fail("a par block calls a function that may print (output only after the par block)"); }
    i += 1;
  }
}
let PRELUDE = "fn __pdig(x: u64) { if x >= 10 { __pdig(x / 10); } putc((x % 10) as i64 + 48); }\nfn __print_bool(b: bool) {\n  if b { putc(116); putc(114); putc(117); putc(101); }\n  else { putc(102); putc(97); putc(108); putc(115); putc(101); }\n  putc(10);\n}\nfn __pfrac6(t: u64) {\n  putc(46);\n  let mut p: u64 = 100000;\n  while p > 0 { putc((t / p % 10) as i64 + 48); p = p / 10; }\n}\nfn __pfix6(a: f64) {\n  let mut ip = a as u64;\n  let fr = a - ip as f64;\n  let s = fr * 1000000.0;\n  let mut t = s as u64;\n  let d = s - t as f64;\n  if d > 0.5 || (d == 0.5 && t % 2 == 1) { t += 1; }\n  if t == 1000000 { ip += 1; t = 0; }\n  __pdig(ip);\n  __pfrac6(t);\n}\nfn __print_f64(x: f64) {\n  if x != x { putc(78); putc(97); putc(78); putc(10); return; }\n  let neg = bits(x) >> 63 != 0;\n  if neg { putc(45); }\n  let mut a = x;\n  if neg { a = -x; }\n  if a == f64_from_bits(0x7FF0000000000000) { putc(105); putc(110); putc(102); putc(10); return; }\n  if a < 10000000000000000.0 { __pfix6(a); putc(10); return; }\n  if a < 18446744073709551616.0 { __pdig(a as u64); __pfrac6(0); putc(10); return; }\n  let mut e = 0;\n  while a >= 10.0 { a = a / 10.0; e += 1; }\n  __pfix6(a); putc(101); putc(43); __pdig(e as u64); putc(10);\n}\n";
let mut user_start: i64 = 0;
fn begin_src(k: i64) {
  if k == 0 { source = 0; in_prelude = true; parsing_src = 2; } else { source = user_start; in_prelude = false; parsing_src = 1; }
  pos = source;
}
fn parse() {
  nv = 1; clear_var(0); vars[0].owner = -1;
  clear_var(1); vars[1].owner = -1; nv = 2;
  parsing = true;
  mainfn = -2;
  let mut k = 0;
  while k < 2 {
    begin_src(k); curfn = -1; next();
    while tk_kind != T_EOF {
      if tk_kind == T_STRUCT { parse_struct(); }
      else if tk_kind == T_LET || tk_kind == T_CONST { parse_global(); }
      else if tk_kind == T_FN { skip_fn(); }
      else { fail("expected `fn`, `struct`, `let` or `const` at top level"); }
    }
    k += 1;
  }
  k = 0;
  while k < 2 { begin_src(k); next(); prescan(); k += 1; }
  if mainfn < 0 { fail("no main function"); }
  nfn_decl = nfn;
  let mut fi = 0;
  k = 0;
  while k < 2 {
    begin_src(k); next();
    while tk_kind != T_EOF {
      if tk_kind == T_FN { parse_function(fi); fi += 1; }
      else { skip_item(); }
    }
    k += 1;
  }
  in_prelude = false; parsing = false;
  check_par(); parsing_src = 0;
  body = fns[mainfn].body;
  if ginit_head >= 0 { nd[ginit_tail].next = nd[body].a; nd[body].a = ginit_head; }
}
// ---------------------------------------------------------------- loop-aware liveness
let loop_start = alloc<i64>(65536);
let loop_end = alloc<i64>(65536);
let mut nloops: i64 = 0;
let lstack = alloc<i64>(65536);
let mut nls: i64 = 0;
let mut pc: i64 = 0;
let pair_v = alloc<i64>(1048576);
let pair_l = alloc<i64>(1048576);
let mut npairs: i64 = 0;
fn loop_weight() -> i64 { let mut w = 1; let mut i = 0; while i < nls && i < 6 { w *= 8; i += 1; } return w; }
fn touch(v: i64) {
  if vars[v].reads == 0 { return; }
  if pc > vars[v].end { vars[v].end = pc; }
  vars[v].weight += loop_weight();
  let mut i = 0;
  while i < nls {
    if loop_start[lstack[i]] > vars[v].start {
      if npairs >= MAX_PAIRS { fail("liveness table full"); }
      pair_v[npairs] = v; pair_l[npairs] = lstack[i]; npairs += 1; break;
    }
    i += 1;
  }
}
// constants hoisted to loop L: a list per loop (hl_head[L] -> var -> hl_next), not a scan of all variables
let hl_head = alloc<i64>(1048576);
let hl_next = alloc<i64>(65536);
let hl_tail = alloc<i64>(1048576);
fn hoist_var(v: u64, L: i64, t: i64) -> i64 {
  let mut i = hl_head[L] - 1;
  while i >= 0 { if vars[i].hoist == L + 1 && vars[i].cval == v && vars[i].ty == t { return i; } i = hl_next[i] - 1; }
  if nv >= MAX_VARS { fail("too many variables"); }
  clear_var(nv); vars[nv].owner = 0; vars[nv].ty = t; vars[nv].lenv = 0;
  vars[nv].hoist = L + 1; vars[nv].cval = v; vars[nv].reads = 1; vars[nv].reg = -1; vars[nv].slot = -1; vars[nv].start = loop_start[L];
  hl_next[nv] = 0; if hl_head[L] == 0 { hl_head[L] = nv + 1; } else { hl_next[hl_tail[L] - 1] = nv + 1; } hl_tail[L] = nv + 1;
  nv += 1; return nv - 1;
}
let mut nchecks: i64 = 0;
let mut nelided: i64 = 0;
fn fits_s32(v: u64) -> bool { return (v as i64) >= -2147483648 && (v as i64) <= 2147483647; }
fn fits_s8(v: u64) -> bool { return (v as i64) >= -128 && (v as i64) <= 127; }
fn touch_arr(a: i64) { touch(vars[a].basev); if vars[a].lenv >= 0 { touch(vars[a].lenv); } }
fn walk_expr(e: i64) {
  if e < 0 { return; }
  let k = nd[e].k;
  if k == N_VAR { touch(nd[e].var); }
  else if k == N_ARR { touch_arr(nd[e].var); }
  else if k == N_CALL {
    let mut a = nd[e].a; while a >= 0 { walk_expr(a); a = nd[a].next; }
    if ncallpc < 1048576 { callpc[ncallpc] = pc; ncallpc += 1; }
  }
  else if k == N_LOAD {
    if nd[e].chk != 0 { touch_arr(nd[e].var); } else { touch(vars[nd[e].var].basev); }   // a proven access needs no length
    walk_expr(nd[e].a);
    nchecks += 1; if nd[e].chk == 0 { nelided += 1; }
  }
  else if k == N_CONST {
    let v = nd[e].v;
    let t = nd[e].ty;
    if nls != 0 && (t == TY_F64 || t == TY_F32 || t == TY_FLIT) && v != 0 {
      let mut ht = TY_F64; if t == TY_F32 { ht = TY_F32; }
      let h = hoist_var(v, lstack[0], ht); nd[e].c = h;
      vars[h].weight += loop_weight();
    }
    else if nls != 0 && !fits_s32(v) && (v & (v - 1)) != 0 {
      let h = hoist_var(v, lstack[0], 0); nd[e].c = h;
      vars[h].weight += loop_weight();
    }
  }
  else if k == N_UN { walk_expr(nd[e].a); }
  else if k == N_BIN {
    walk_expr(nd[e].a);
    let op = nd[e].op;
    if (op == O_DIV || op == O_MOD || op == O_DIVU || op == O_MODU) && is_const(nd[e].b) { return; }
    walk_expr(nd[e].b);
  }
}
fn walk_stmt(s: i64) {
  let k = nd[s].k;
  if k == S_LET {
    pc += 1; nd[s].pos = pc; walk_expr(nd[s].a);
    let v = nd[s].var;
    if vars[v].reads != 0 { vars[v].start = pc; vars[v].end = pc; if nd[nd[s].a].k == N_VAR { chint[v] = nd[nd[s].a].var; } }
  }
  else if k == S_ASSIGN || k == S_IRET {
    pc += 1; nd[s].pos = pc; walk_expr(nd[s].a);
    if k == S_IRET && vars[nd[s].var].start > pc {
      vars[nd[s].var].start = pc;
      if nd[nd[s].a].k == N_VAR { chint[nd[s].var] = nd[nd[s].a].var; }
    }
    touch(nd[s].var);
  }
  else if k == S_INL { // the inlined call's result variable is born at its first return (not live across the body's calls)
    let rv = nd[s].var;
    let live = rv >= 0 && vars[rv].reads != 0;
    if live { vars[rv].start = INT64_MAX; vars[rv].end = pc + 1; }
    let p0 = pc + 1;
    let mut c = nd[s].a; while c >= 0 { walk_stmt(c); c = nd[c].next; }
    if live && vars[rv].start > vars[rv].end { vars[rv].start = p0; }
  }
  else if k == S_PAR {
    pc += 1; nd[s].pos = pc; walk_expr(nd[s].a); walk_expr(nd[s].b);
    vars[nd[s].var].start = pc; vars[nd[s].var].end = pc; vars[nd[s].op].start = pc; vars[nd[s].op].end = pc;
    walk_stmt(nd[s].c);
    pc += 1; touch(nd[s].var); touch(nd[s].op);
  }
  else if k == S_IF { pc += 1; nd[s].pos = pc; walk_expr(nd[s].a); walk_stmt(nd[s].b); if nd[s].c >= 0 { walk_stmt(nd[s].c); } }
  else if k == S_WHILE {
    if nloops >= MAX_LOOPS { fail("too many loops"); }
    let m = nd[s].c;
    if m >= 0 { pc += 1; vars[m].start = pc; vars[m].end = pc; }
    let L = nloops; nloops += 1;
    pc += 1; nd[s].pos = pc; nd[s].var = L; loop_start[L] = pc; lstack[nls] = L; nls += 1;
    if m >= 0 { touch(m); }
    walk_expr(nd[s].a); walk_stmt(nd[s].b); loop_end[L] = pc; nls -= 1;
    if m >= 0 { pc += 1; touch(m); }
  }
  else if k == S_RET || k == S_PRINT || k == S_PUTC || k == S_EXPR { pc += 1; nd[s].pos = pc; walk_expr(nd[s].a); }
  else if k == S_WRITE { pc += 1; nd[s].pos = pc; if nd[s].var >= 0 { touch_arr(nd[s].var); } walk_expr(nd[s].a); walk_expr(nd[s].b); }
  else if k == S_SAVE { pc += 1; nd[s].pos = pc; touch_arr(nd[s].var); touch(0); touch(1); walk_expr(nd[s].a); walk_expr(nd[s].b); }
  else if k == S_BRK || k == S_CONT { pc += 1; nd[s].pos = pc; }
  else if k == S_STORE {
    pc += 1; nd[s].pos = pc; walk_expr(nd[s].a); walk_expr(nd[s].b);
    if nd[s].chk != 0 { touch_arr(nd[s].var); } else { touch(vars[nd[s].var].basev); }
    nchecks += 1; if nd[s].chk == 0 { nelided += 1; }
  }
  else if k == S_ARR {
    let a = nd[s].var;
    pc += 1; nd[s].pos = pc; walk_expr(nd[s].a);
    if nd[s].op == A_FILE || nd[s].op == A_ARG { touch(0); touch(1); }
    if nd[s].op == A_VIEW && vars[nd[s].c].lenv >= 0 { touch(vars[nd[s].c].lenv); }
    if nd[s].op != A_VIEW && vars[vars[a].basev].reads != 0 { vars[vars[a].basev].start = pc; vars[vars[a].basev].end = pc; }
    if vars[a].lenv >= 0 && vars[vars[a].lenv].reads != 0 { vars[vars[a].lenv].start = pc; vars[vars[a].lenv].end = pc; }
  }
  else if k == S_BLOCK { let mut c = nd[s].a; while c >= 0 { walk_stmt(c); c = nd[c].next; } }
}

// ---------------------------------------------------------------- inlining
fn has_call(e: i64) -> bool {
  if e < 0 { return false; }
  if nd[e].k == N_CALL { return true; }
  return has_call(nd[e].a) || has_call(nd[e].b);
}
fn inl_expr(f: i64) -> i64 {
  let b = fns[f].body;
  let s = nd[b].a;
  if s < 0 || nd[s].next >= 0 || nd[s].k != S_RET || has_call(nd[s].a) { return -1; }
  return nd[s].a;
}
fn subst(e: i64, f: i64, call: i64) -> i64 {
  if e < 0 { return -1; }
  let ck = nd[e].k; let cv = nd[e].var; let ca = nd[e].a; let cb = nd[e].b; let cop = nd[e].op; let cty = nd[e].ty;
  let mut i = 0;
  let mut x = nd[call].a;
  while x >= 0 {
    let pv = fpvar[f * 16 + i];
    if fpw[f * 16 + i] == 0 && ck == N_VAR && cv == pv { let r = clone_expr(x); nd[r].ty = cty; return r; }   // keeps a bits() retag
    if fpw[f * 16 + i] != 0 {
      let av = nd[x].var;
      if ck == N_VAR && cv == vars[pv].lenv {
        if vars[av].lenv < 0 { return mkconst(vars[av].alen as u64); }
        return mk_var(vars[av].lenv);
      }
      if ck == N_LOAD && cv == pv { let r = mk_load(av, subst(ca, f, call)); nd[r].op = cop; nd[r].ty = cty; return r; }
    }
    x = nd[x].next; i += 1;
  }
  let r = mk(ck); copy_node(r, e); nd[r].c = -1; nd[r].next = -1;
  if ck == N_VAR { vars[cv].reads += 1; }
  nd[r].a = subst(ca, f, call); nd[r].b = subst(cb, f, call);
  return r;
}
let mut ninlined: i64 = 0;
let imap = alloc<i64>(65536);
let imap_gen = alloc<i64>(65536);
let mut igen: i64 = 0;
fn map_var(v: i64) -> i64 { if imap_gen[v] == igen { return imap[v]; } return v; }
fn clone_e_inl(e: i64) -> i64 {
  if e < 0 { return -1; }
  let ck = nd[e].k; let cv = nd[e].var; let ca = nd[e].a; let cb = nd[e].b;
  if ck == N_VAR {
    if imap_gen[cv] == igen && imap[cv] < 0 {
      let av = 0 - imap[cv] - 1;
      if vars[av].lenv < 0 { return mkconst(vars[av].alen as u64); }
      return mk_var(vars[av].lenv);
    }
    if cv == SUBV { return mkconst_t(SUBC, nd[e].ty); }
    let r = mk_var(map_var(cv)); nd[r].ty = nd[e].ty; return r;   // keeps a bits() retag
  }
  if ck == N_LOAD { let op = nd[e].op; let ty = nd[e].ty; let r = mk_load(map_var(cv), clone_e_inl(ca)); nd[r].op = op; nd[r].ty = ty; return r; }
  if ck == N_ARR {
    let a = map_var(cv);
    vars[vars[a].basev].reads += 1; if vars[a].lenv >= 0 { vars[vars[a].lenv].reads += 1; }
    let r = mk(N_ARR); nd[r].var = a; return r;
  }
  let r = mk(ck); copy_node(r, e); nd[r].c = -1; nd[r].next = -1;
  if ck == N_CALL {
    let mut prev = -1; nd[r].a = -1;
    let mut x = ca;
    while x >= 0 { let y = clone_e_inl(x); nd[y].next = -1; if prev < 0 { nd[r].a = y; } else { nd[prev].next = y; } prev = y; x = nd[x].next; }
    return r;
  }
  nd[r].a = clone_e_inl(ca); nd[r].b = clone_e_inl(cb);
  return r;
}
fn clone_list_inl(first: i64, resv: i64) -> i64 {
  let mut head = -1; let mut prev = -1;
  let mut c = first;
  while c >= 0 { let y = clone_stmt_inl(c, resv); if prev < 0 { head = y; } else { nd[prev].next = y; } prev = y; c = nd[c].next; }
  return head;
}
fn clone_stmt_inl(s: i64, resv: i64) -> i64 {
  if s < 0 { return -1; }
  let ck = nd[s].k; let cv = nd[s].var; let ca = nd[s].a; let cb = nd[s].b; let cc = nd[s].c;
  let r = mk(ck); copy_node(r, s); nd[r].next = -1;
  if ck == S_LET {
    let nvv = hidden(); vars[nvv].mutv = vars[cv].mutv; vars[nvv].ty = vars[cv].ty;
    imap[cv] = nvv; imap_gen[cv] = igen;
    nd[r].a = clone_e_inl(ca); nd[r].var = nvv;
  }
  else if ck == S_ASSIGN { nd[r].var = map_var(cv); nd[r].a = clone_e_inl(ca); }
  else if ck == S_RET { if resv != -2 { nd[r].k = S_IRET; nd[r].var = resv; } nd[r].a = clone_e_inl(ca); }
  else if ck == S_IRET { nd[r].var = map_var(cv); nd[r].a = clone_e_inl(ca); }
  else if ck == S_IF { nd[r].a = clone_e_inl(ca); nd[r].b = clone_stmt_inl(cb, resv); nd[r].c = clone_stmt_inl(cc, resv); }
  else if ck == S_WHILE { nd[r].a = clone_e_inl(ca); nd[r].b = clone_stmt_inl(cb, resv); }
  else if ck == S_BLOCK || ck == S_INL {
    if ck == S_INL { let nvv = hidden(); vars[nvv].mutv = 1; vars[nvv].ty = vars[cv].ty; imap[cv] = nvv; imap_gen[cv] = igen; nd[r].var = nvv; }
    nd[r].a = clone_list_inl(ca, resv);
  }
  else if ck == S_STORE {
    let a = map_var(cv); nd[r].var = a; nd[r].a = clone_e_inl(ca); nd[r].b = clone_e_inl(cb);
    vars[vars[a].basev].reads += 1; if vars[a].lenv >= 0 { vars[vars[a].lenv].reads += 1; }
  }
  else if ck == S_PRINT || ck == S_PUTC || ck == S_EXPR { nd[r].a = clone_e_inl(ca); }
  else if ck == S_WRITE {
    if cv >= 0 { let a = map_var(cv); nd[r].var = a; vars[vars[a].basev].reads += 1; if vars[a].lenv >= 0 { vars[vars[a].lenv].reads += 1; } }
    nd[r].a = clone_e_inl(ca); nd[r].b = clone_e_inl(cb);
  }
  else if ck == S_BRK || ck == S_CONT { }
  else { fail("internal: cannot inline statement"); }
  return r;
}
fn stmt_size(s: i64) -> i64 {
  if s < 0 { return 0; }
  let mut n = 1;
  let k = nd[s].k;
  if k == S_BLOCK || k == S_INL { let mut c = nd[s].a; while c >= 0 { n += stmt_size(c); c = nd[c].next; } return n; }
  if k == S_IF { n += stmt_size(nd[s].b) + stmt_size(nd[s].c); }
  if k == S_WHILE { n += stmt_size(nd[s].b); }
  if k == S_ARR { n += 100000; }
  return n;
}
let reach_mark = alloc<bool>(4096);
fn expr_reach(e: i64, target: i64, dep: i64) -> bool {
  if e < 0 { return false; }
  if nd[e].k == N_CALL {
    let f = nd[e].var;
    if f == target { return true; }
    if !reach_mark[f] { reach_mark[f] = true; if calls_reach(fns[f].body, target, dep + 1) { return true; } }
    let mut a = nd[e].a;
    while a >= 0 { if expr_reach(a, target, dep) { return true; } a = nd[a].next; }
    return false;
  }
  if nd[e].k > N_ARR { return calls_reach(e, target, dep); }
  return expr_reach(nd[e].a, target, dep) || expr_reach(nd[e].b, target, dep);
}
fn calls_reach(s: i64, target: i64, dep: i64) -> bool {
  if s < 0 || dep > MAX_FUNCS { return false; }
  let k = nd[s].k;
  if k <= N_ARR { return expr_reach(s, target, dep); }
  if expr_reach(nd[s].a, target, dep) { return true; }
  if (k == S_STORE || k == S_WRITE || k == S_SAVE) && expr_reach(nd[s].b, target, dep) { return true; }
  if k == S_IF && (calls_reach(nd[s].b, target, dep) || calls_reach(nd[s].c, target, dep)) { return true; }
  if k == S_WHILE && calls_reach(nd[s].b, target, dep) { return true; }
  if k == S_BLOCK || k == S_INL { let mut c = nd[s].a; while c >= 0 { if calls_reach(c, target, dep) { return true; } c = nd[c].next; } }
  return false;
}
fn recursive(f: i64) -> bool {
  let mut i = 0;
  while i < MAX_FUNCS { reach_mark[i] = false; i += 1; }
  return calls_reach(fns[f].body, f, 0);
}
let INLINE_MAX_STMTS = 400;
let INLINE_NODE_BUDGET = 786432;
let INLINE_CALLER_BUDGET = 2000;
let mut inl_growth: i64 = 0;
let mut ninl_stmt: i64 = 0;
fn set_block(s: i64, a: i64, nx: i64) { // nd[s] = (Node){.k=S_BLOCK,.a=a,.b=-1,.c=-1,.next=nx,.var=-1}
  nd[s].k = S_BLOCK; nd[s].op = 0; nd[s].a = a; nd[s].b = -1; nd[s].c = -1; nd[s].next = nx; nd[s].var = -1;
  nd[s].pos = 0; nd[s].chk = 0; nd[s].nn = 0; nd[s].ty = 0; nd[s].v = 0; nd[s].dlo = 0; nd[s].dhi = 0;
}
// a function that always ends by exiting (error paths): never worth inlining
fn has_ret(s: i64) -> bool {
  if s < 0 { return false; }
  let k = nd[s].k;
  if k == S_RET || k == S_IRET { return true; }
  if k == S_IF { return has_ret(nd[s].b) || has_ret(nd[s].c); }
  if k == S_WHILE { return has_ret(nd[s].b); }
  if k == S_PAR { return has_ret(nd[s].c); }
  if k == S_BLOCK || k == S_INL { let mut c = nd[s].a; while c >= 0 { if has_ret(c) { return true; } c = nd[c].next; } }
  return false;
}
// s unconditionally exits before any return can be reached
fn noreturn_stmt(s: i64, depth: i64) -> bool {
  let k = nd[s].k;
  if k == S_PUTC && nd[s].op == 1 { return true; }
  if k == S_EXPR && nd[nd[s].a].k == N_CALL { return noreturn(nd[nd[s].a].var, depth + 1); }
  if k == S_BLOCK {
    let mut c = nd[s].a;
    while c >= 0 { if noreturn_stmt(c, depth) { return true; } if has_ret(c) { return false; } c = nd[c].next; }
  }
  return false;
}
fn noreturn(f: i64, depth: i64) -> bool { return depth <= 8 && fns[f].body >= 0 && noreturn_stmt(fns[f].body, depth); }
fn try_inline_stmt(s: i64) -> bool {
  let k = nd[s].k;
  let mut call = -1; let mut holder = -1; let mut inb = false;
  if k == S_STORE && nd[s].op < 0 && nd[s].b >= 0 && nd[nd[s].b].k == N_CALL { call = nd[s].b; inb = true; }
  if (k == S_PRINT || k == S_PUTC) && nd[s].a >= 0 && nd[nd[s].a].k == N_CALL { call = nd[s].a; }
  if call < 0 && (k == S_LET || k == S_ASSIGN || k == S_EXPR) && nd[s].a >= 0 {
    let xa = nd[s].a;
    if nd[xa].k == N_CALL { call = xa; }
    else if k != S_EXPR && nd[xa].k == N_BIN && nd[xa].op != O_LAND && nd[xa].op != O_LOR && nd[nd[xa].b].k == N_CALL &&
            (nd[nd[xa].a].k == N_VAR || nd[nd[xa].a].k == N_CONST) { call = nd[xa].b; holder = xa; }
  }
  if call < 0 { return false; }
  let f = nd[call].var;
  if starts2u(fns[f].noff, fns[f].nlen) || fn_nr[f] { return false; }
  let rec = frec[f];
  let mut src_body = fns[f].body;
  if rec { if forig[f] < 0 { return false; } src_body = forig[f]; }
  let csz = stmt_size(src_body);
  // tiny recursive bodies (tree builders and walkers) get one more level
  let mut rmax = MAX_REC_INLINE; let mut rbud = INLINE_REC_BUDGET;
  if csz <= INLINE_REC_TINY { rmax += 2; rbud = 16 * rbud; }
  if rec && rec_depth >= rmax { return false; }
  if csz > INLINE_MAX_STMTS || nn > INLINE_NODE_BUDGET { return false; }
  if rec && (csz > INLINE_REC_STMTS || rec_growth + csz > rbud) { return false; }
  if rec { rec_growth += csz; }
  if inl_growth + csz > INLINE_CALLER_BUDGET { return false; }
  LAST_REC = rec;
  inl_growth += csz;
  igen += 1;
  let resv = hidden(); vars[resv].mutv = 1; vars[resv].ty = fns[f].rett;
  let mut head = -1; let mut prev = -1; let mut i = 0;
  let mut a = nd[call].a;
  while a >= 0 {
    let pv = fpvar[f * 16 + i];
    if fpw[f * 16 + i] != 0 {
      let av = nd[a].var;
      imap[pv] = av; imap_gen[pv] = igen;
      imap[vars[pv].lenv] = 0 - (av + 1); imap_gen[vars[pv].lenv] = igen;
      imap[vars[pv].basev] = vars[av].basev; imap_gen[vars[pv].basev] = igen;
    } else {
      let nvv = hidden(); vars[nvv].mutv = vars[pv].mutv; vars[nvv].ty = vars[pv].ty;
      let l = mk(S_LET); nd[l].var = nvv; nd[l].a = a;
      imap[pv] = nvv; imap_gen[pv] = igen;
      if prev < 0 { head = l; } else { nd[prev].next = l; }
      prev = l;
    }
    a = nd[a].next; i += 1;
  }
  let bd = clone_list_inl(nd[src_body].a, resv);
  if prev < 0 { head = bd; } else { nd[prev].next = bd; }
  let inl = mk(S_INL); nd[inl].a = head; nd[inl].var = resv;
  let keep_next = nd[s].next;
  let orig = mk(nd[s].k); copy_node(orig, s); nd[orig].next = -1;
  nd[call].k = N_CONST; nd[call].v = 0; nd[call].a = -1;
  if nd[orig].k == S_EXPR { nd[inl].next = -1; set_block(s, inl, keep_next); }
  else {
    if holder >= 0 { nd[holder].b = mk_var(resv); } else if inb { nd[orig].b = mk_var(resv); } else { nd[orig].a = mk_var(resv); }
    nd[inl].next = orig; set_block(s, inl, keep_next);
  }
  ninl_stmt += 1;
  return true;
}
fn inline_stmts(s: i64) {
  if s < 0 { return; }
  let k = nd[s].k;
  if k == S_BLOCK || k == S_INL { let mut c = nd[s].a; while c >= 0 { inline_stmts(c); c = nd[c].next; } return; }
  if k == S_IF { inline_stmts(nd[s].b); inline_stmts(nd[s].c); return; }
  if k == S_WHILE { inline_stmts(nd[s].b); return; }
  if k == S_PAR { inline_stmts(nd[s].c); return; }
  if try_inline_stmt(s) {
    if LAST_REC { rec_depth += 1; inline_stmts(nd[s].a); rec_depth -= 1; } else { inline_stmts(nd[s].a); }
  }
}
// ---- bounded inlining of recursive functions, from a pristine copy of the body
let MAX_REC_INLINE = 3;
let INLINE_REC_STMTS = 16;
let INLINE_REC_BUDGET = 160;   // statements of recursive copies per caller
let INLINE_REC_TINY = 15;
let mut rec_growth: i64 = 0;
let forig = alloc<i64>(4096);
let mut rec_depth: i64 = 0;
let mut LAST_REC: bool = false;
let frec = alloc<bool>(4096);   // recursive (computed once, before inlining)
fn make_templates() {
  let mut f = 0;
  while f < nfn { frec[f] = fns[f].body >= 0 && recursive(f); f += 1; }
  f = 0;
  while f < nfn {
    forig[f] = -1;
    if f != mainfn && fns[f].body >= 0 && !starts2u(fns[f].noff, fns[f].nlen) && stmt_size(fns[f].body) <= INLINE_REC_STMTS && frec[f] {
      igen += 1;
      let b = mk(S_BLOCK); nd[b].a = clone_list_inl(nd[fns[f].body].a, -2); forig[f] = b;
    }
    f += 1;
  }
}
// ---- call lifting: calls inside expressions become `let t = f(..);` before the statement when
// everything evaluated before them is pure and cannot trap (so moving it after the call is invisible)
let mut LIFT_OK: bool = true;
let mut LIFT_H: i64 = -1;
let mut LIFT_T: i64 = -1;
fn pure_nt(e: i64) -> bool {
  if e < 0 { return true; }
  let k = nd[e].k;
  if k == N_CONST || k == N_VAR { return true; }
  if k == N_CALL || k == N_LOAD || k == N_ARR || k == N_NCPU { return false; }
  if k == N_UN { return pure_nt(nd[e].a); }
  let op = nd[e].op;
  if op == O_DIV || op == O_MOD || op == O_DIVU || op == O_MODU {
    let b = nd[e].b;
    if !is_const(b) || nd[b].v == 0 || ((op == O_DIV || op == O_MOD) && (nd[b].v as i64) == -1) { return false; }
  }
  return pure_nt(nd[e].a) && pure_nt(nd[e].b);
}
fn lift_e(e: i64) -> i64 {
  if e < 0 || !LIFT_OK { return e; }
  let k = nd[e].k;
  if k == N_CONST || k == N_VAR { return e; }
  if k == N_CALL {
    let mut a = nd[e].a; let mut prev = -1;
    while a >= 0 {
      let nx = nd[a].next;
      let r = lift_e(a);
      if r != a { nd[r].next = nx; if prev < 0 { nd[e].a = r; } else { nd[prev].next = r; } }
      prev = r; a = nx;
    }
    if !LIFT_OK || nd[e].ty == TY_UNIT { LIFT_OK = false; return e; }
    let t = hidden(); vars[t].ty = nd[e].ty;
    let l = mk(S_LET); nd[l].var = t; nd[l].a = e;
    if LIFT_T < 0 { LIFT_H = l; } else { nd[LIFT_T].next = l; }
    LIFT_T = l;
    let r = mk_var(t); nd[r].ty = nd[e].ty; return r;
  }
  if k == N_BIN && (nd[e].op == O_LAND || nd[e].op == O_LOR) {
    if has_call(e) || !pure_nt(e) { LIFT_OK = false; }
    return e;
  }
  if k == N_LOAD { nd[e].a = lift_e(nd[e].a); LIFT_OK = false; return e; }
  if k == N_UN { nd[e].a = lift_e(nd[e].a); return e; }
  if k == N_BIN {
    nd[e].a = lift_e(nd[e].a); nd[e].b = lift_e(nd[e].b);
    if !pure_nt_op(e) { LIFT_OK = false; }
    return e;
  }
  LIFT_OK = false; return e;
}
fn pure_nt_op(e: i64) -> bool {   // the node's own operation cannot trap
  let op = nd[e].op;
  if op == O_DIV || op == O_MOD || op == O_DIVU || op == O_MODU {
    let b = nd[e].b;
    return is_const(b) && nd[b].v != 0 && !((op == O_DIV || op == O_MOD) && (nd[b].v as i64) == -1);
  }
  return true;
}
fn lift_stmt(s: i64) {
  let k = nd[s].k;
  LIFT_OK = true; LIFT_H = -1; LIFT_T = -1;
  if k == S_LET || k == S_ASSIGN || k == S_RET || k == S_PRINT || k == S_PUTC || k == S_IF {
    let e = nd[s].a;
    if e < 0 || !has_call(e) { return; }
    if (k == S_LET || k == S_ASSIGN) && nd[e].k == N_CALL { return; }   // already a statement-level call
    nd[s].a = lift_e(e);
  } else if k == S_STORE {
    if nd[s].b < 0 || !has_call(nd[s].b) || has_call(nd[s].a) || nd[nd[s].b].k == N_CALL { return; }
    nd[s].b = lift_e(nd[s].b);
  } else { return; }
  if LIFT_H < 0 { return; }
  let keep_next = nd[s].next;
  let orig = mk(nd[s].k); copy_node(orig, s); nd[orig].next = -1;
  nd[LIFT_T].next = orig;
  set_block(s, LIFT_H, keep_next);
}
fn lift_calls(s: i64) {
  if s < 0 { return; }
  let k = nd[s].k;
  if k == S_BLOCK || k == S_INL { let mut c = nd[s].a; while c >= 0 { lift_calls(c); c = nd[c].next; } return; }
  if k == S_IF { lift_calls(nd[s].b); lift_calls(nd[s].c); lift_stmt(s); return; }
  if k == S_WHILE { lift_calls(nd[s].b); return; }
  if k == S_PAR { lift_calls(nd[s].c); return; }
  lift_stmt(s);
}
fn inline_calls() {
  let mut round = 0;
  while round < 8 {
    let mut changed = false;
    let n0 = nn;
    let mut e = 0;
    while e < n0 {
      if nd[e].k == N_CALL {
        let f = nd[e].var;
        let body_e = inl_expr(f);
        if body_e >= 0 {
          let mut ok = true;
          let mut x = nd[e].a;
          while x >= 0 { if nd[x].k != N_VAR && nd[x].k != N_CONST && nd[x].k != N_ARR { ok = false; } x = nd[x].next; }
          if ok {
            let r = subst(body_e, f, e);
            let keep_next = nd[e].next; copy_node(e, r); nd[e].next = keep_next;
            changed = true; ninlined += 1;
          }
        }
      }
      e += 1;
    }
    if !changed { break; }
    round += 1;
  }
}
// ---------------------------------------------------------------- constant propagation, folding, full unrolling
let acount = alloc<i64>(65536);
fn count_assigns() {
  let mut v = 0;
  while v < nv { acount[v] = 0; v += 1; }
  let mut i = 0;
  while i < nn {
    let k = nd[i].k;
    if (k == S_LET || k == S_ASSIGN || k == S_IRET) && nd[i].var >= 0 { acount[nd[i].var] += 1; }
    if k == S_PAR { acount[nd[i].var] += 2; acount[nd[i].op] += 2; }
    i += 1;
  }
}
// fold a node whose operands are constants (never folds an operation that may trap)
fn fold_node(e: i64) -> bool {
  let k = nd[e].k;
  if k == N_BIN {
    let a = nd[e].a; let b = nd[e].b;
    let op = nd[e].op;
    if (op == O_LAND || op == O_LOR) && is_const(a) {
      if (op == O_LAND) == (nd[a].v != 0) { if !is_const(b) { return false; } nd[e].v = (nd[b].v != 0) as u64; }
      else { nd[e].v = (op == O_LOR) as u64; }
      nd[e].k = N_CONST; nd[e].a = -1; nd[e].b = -1; nd[e].c = -1; return true;
    }
    if !is_const(a) || !is_const(b) { return false; }
    if op == O_DIV || op == O_MOD || op == O_DIVU || op == O_MODU {
      if nd[b].v == 0 { return false; }
      if (op == O_DIV || op == O_MOD) && (nd[b].v as i64) == -1 && (nd[a].v as i64) == INT64_MIN { return false; }
    }
    nd[e].v = eval_bin(op, nd[a].v, nd[b].v);
    nd[e].k = N_CONST; nd[e].a = -1; nd[e].b = -1; nd[e].c = -1; return true;
  }
  if k == N_UN {
    let a = nd[e].a;
    if !is_const(a) || nd[e].op == U_SQRTD || nd[e].op == U_SQRTS { return false; }
    nd[e].v = eval_un(nd[e].op, nd[a].v);
    nd[e].k = N_CONST; nd[e].a = -1; nd[e].c = -1; return true;
  }
  return false;
}
// immutable variables bound once to a constant become that constant; then fold
fn const_prop() -> bool {
  count_assigns();
  let mut changed = false;
  let mut i = 0;
  while i < nn {
    if nd[i].k == S_LET && is_const(nd[i].a) {
      let v = nd[i].var;
      if vars[v].mutv == 0 && acount[v] == 1 && vars[v].isconst == 0 && vars[v].arr == 0 && vars[v].garr == 0 && v > 1 {
        vars[v].isconst = 1; vars[v].cval = nd[nd[i].a].v; vars[v].reads = 0;
        set_block(i, -1, nd[i].next);
        changed = true;
      }
    }
    i += 1;
  }
  if !changed { return false; }
  i = 0;
  while i < nn {
    if nd[i].k == N_VAR && vars[nd[i].var].isconst != 0 && vars[nd[i].var].arr == 0 { nd[i].k = N_CONST; nd[i].v = vars[nd[i].var].cval; nd[i].var = -1; nd[i].c = -1; }
    i += 1;
  }
  let mut again = true;
  while again {
    again = false;
    i = nn - 1;
    while i >= 0 { if (nd[i].k == N_BIN || nd[i].k == N_UN) && fold_node(i) { again = true; } i -= 1; }
  }
  return true;
}
// while i < C { body; i += 1 } with i = c0 just before and a small trip count: one copy per value of i
let UNROLL_MAX_TRIP = 16;
let UNROLL_MAX_STMTS = 320;
let mut SUBV: i64 = -1;
let mut SUBC: u64 = 0;
fn has_jump0(s: i64, d: i64) -> bool {   // break/continue that leaves the loop being unrolled
  if s < 0 { return false; }
  let k = nd[s].k;
  if (k == S_BRK || k == S_CONT) && d == 0 { return true; }
  if k == S_BLOCK || k == S_INL { let mut c = nd[s].a; while c >= 0 { if has_jump0(c, d) { return true; } c = nd[c].next; } return false; }
  if k == S_IF { return has_jump0(nd[s].b, d) || has_jump0(nd[s].c, d); }
  if k == S_WHILE { return has_jump0(nd[s].b, d + 1); }
  if k == S_PAR || k == S_ARR || k == S_SAVE { return true; }
  return false;
}
fn cfold_ok(e: i64) -> bool {   // small constant +, -, * arithmetic
  if is_const(e) { let v = nd[e].v as i64; return v > -1000000000 && v < 1000000000; }
  if nd[e].k != N_BIN || nd[e].ty != TY_I64 || !(nd[e].op == O_ADD || nd[e].op == O_SUB || nd[e].op == O_MUL) { return false; }
  if !cfold_ok(nd[e].a) || !cfold_ok(nd[e].b) { return false; }
  let v = cfold(e); return v > -1000000000 && v < 1000000000;
}
fn cfold(e: i64) -> i64 {
  if is_const(e) { return nd[e].v as i64; }
  let a = cfold(nd[e].a); let b = cfold(nd[e].b);
  if nd[e].op == O_ADD { return a + b; } if nd[e].op == O_SUB { return a - b; } return a * b;
}
fn try_unroll(prev: i64, s: i64) -> bool {
  if nd[s].k != S_WHILE || nd[s].c >= 0 { return false; }
  let cnd = nd[s].a;
  if nd[cnd].k != N_BIN || (nd[cnd].op != O_LT && nd[cnd].op != O_LE) || nd[nd[cnd].a].k != N_VAR || !is_const(nd[cnd].b) { return false; }
  let iv = nd[nd[cnd].a].var;
  if vars[iv].ty != TY_I64 || vars[iv].xr >= 0 { return false; }
  if prev < 0 || (nd[prev].k != S_LET && nd[prev].k != S_ASSIGN) || nd[prev].var != iv || !cfold_ok(nd[prev].a) { return false; }
  let c0 = cfold(nd[prev].a);   // a constant, or constant arithmetic left by an outer unrolled loop (j = 0 + 1)
  let mut c1 = nd[nd[cnd].b].v as i64;
  if nd[cnd].op == O_LE { if c1 == INT64_MAX { return false; } c1 += 1; }
  let trip = c1 - c0;
  if c0 < -1000000000 || c1 > 1000000000 || trip > UNROLL_MAX_TRIP { return false; }
  if trip <= 0 {   // never runs: the condition is false on entry and has no side effects
    if has_call(cnd) { return false; }
    set_block(s, -1, nd[s].next); return true;
  }
  let body = nd[s].b;
  if nd[body].k != S_BLOCK || count_assign(s, iv) != 1 || has_jump0(body, 0) { return false; }
  let mut inc = -1;
  let mut c = nd[body].a;
  while c >= 0 { if nd[c].k == S_ASSIGN && is_inc1(c, iv) && nd[c].next < 0 { inc = c; } c = nd[c].next; }
  if inc < 0 { return false; }
  if stmt_size(body) * trip > UNROLL_MAX_STMTS { return false; }
  // build: copy(c0) .. copy(c1 - 1), then i = c1
  let mut head = -1; let mut tail = -1;
  let mut t = 0;
  while t < trip {
    igen += 1;
    SUBV = iv; SUBC = (c0 + t) as u64;
    c = nd[body].a;
    while c >= 0 && c != inc {
      let y = clone_stmt_inl(c, -2);
      if tail < 0 { head = y; } else { nd[tail].next = y; }
      tail = y; c = nd[c].next;
    }
    SUBV = -1;
    t += 1;
  }
  let fin = mk(S_ASSIGN); nd[fin].var = iv; nd[fin].a = mkconst_t(c1 as u64, TY_I64);
  if tail < 0 { head = fin; } else { nd[tail].next = fin; }
  let blk = mk(S_BLOCK); nd[blk].a = head;
  let keep_next = nd[s].next;
  set_block(s, head, keep_next);
  return true;
}
let mut nunrolled: i64 = 0;
fn unroll_stmts(s: i64) -> bool {
  if s < 0 { return false; }
  let k = nd[s].k;
  let mut ch = false;
  if k == S_BLOCK || k == S_INL {
    let mut prev = -1;
    let mut c = nd[s].a;
    while c >= 0 {
      if try_unroll(prev, c) { nunrolled += 1; ch = true; }
      else if unroll_stmts(c) { ch = true; }
      prev = c; c = nd[c].next;
    }
    return ch;
  }
  if k == S_IF { if unroll_stmts(nd[s].b) { ch = true; } if unroll_stmts(nd[s].c) { ch = true; } return ch; }
  if k == S_WHILE { return unroll_stmts(nd[s].b); }
  if k == S_PAR { return unroll_stmts(nd[s].c); }
  return false;
}
// ---- global scalars live in a register across loops that make no calls
let gsc = alloc<bool>(65536);      // static array holding a global scalar
let gpro = alloc<i64>(65536);      // static array -> promoted local (+1) while rewriting one loop
let gtouch = alloc<i64>(65536);    // touched in the loop being examined (tag)
let mut gtag: i64 = 0;
let gl_list = alloc<i64>(4096);
let mut ngl: i64 = 0;
let mut npromoted: i64 = 0;
fn gs_expr_ok(e: i64) -> bool {
  if e < 0 { return true; }
  let k = nd[e].k;
  if k == N_CALL || k == N_NCPU { return false; }
  if k == N_LOAD && gsc[nd[e].var] && gtouch[nd[e].var] != gtag { gtouch[nd[e].var] = gtag; if ngl < 4096 { gl_list[ngl] = nd[e].var; ngl += 1; } }
  if k == N_CONST || k == N_VAR || k == N_ARR { return true; }
  return gs_expr_ok(nd[e].a) && gs_expr_ok(nd[e].b);
}
fn gs_stmt_ok(s: i64) -> bool {
  if s < 0 { return true; }
  let k = nd[s].k;
  if k == S_RET || k == S_IRET || k == S_EXPR || k == S_PAR || k == S_SAVE || k == S_ARR { return false; }
  if k == S_STORE && gsc[nd[s].var] && gtouch[nd[s].var] != gtag { gtouch[nd[s].var] = gtag; if ngl < 4096 { gl_list[ngl] = nd[s].var; ngl += 1; } }
  if !gs_expr_ok(nd[s].a) { return false; }
  if (k == S_STORE || k == S_WRITE) && !gs_expr_ok(nd[s].b) { return false; }
  if k == S_IF { return gs_stmt_ok(nd[s].b) && gs_stmt_ok(nd[s].c); }
  if k == S_WHILE { return gs_stmt_ok(nd[s].b); }
  if k == S_BLOCK || k == S_INL { let mut c = nd[s].a; while c >= 0 { if !gs_stmt_ok(c) { return false; } c = nd[c].next; } }
  return true;
}
fn gs_rewrite_e(e: i64) {
  if e < 0 { return; }
  let k = nd[e].k;
  if k == N_LOAD && gpro[nd[e].var] > 0 && is_const(nd[e].a) {
    let t = gpro[nd[e].var] - 1;
    nd[e].k = N_VAR; nd[e].var = t; nd[e].a = -1; vars[t].reads += 1; return;
  }
  if k == N_CALL { let mut a = nd[e].a; while a >= 0 { gs_rewrite_e(a); a = nd[a].next; } return; }
  if k == N_CONST || k == N_VAR || k == N_ARR { return; }
  gs_rewrite_e(nd[e].a); gs_rewrite_e(nd[e].b);
}
fn gs_rewrite(s: i64) {
  if s < 0 { return; }
  let k = nd[s].k;
  gs_rewrite_e(nd[s].a);
  if k == S_STORE || k == S_WRITE { gs_rewrite_e(nd[s].b); }
  if k == S_STORE && gpro[nd[s].var] > 0 {
    let g = nd[s].var; let t = gpro[g] - 1; let et = vars[g].et;
    let mut e = nd[s].b;
    if nd[s].op >= 0 {
      let tv = mk_var(t);
      e = mk_bin(nd[s].op, tv, e); nd[e].ty = promote(et);
      if ty_width(et) < 8 && ty_int(et) { e = mk_un(narrow_op(et), e, et); }
    }
    nd[s].k = S_ASSIGN; nd[s].var = t; nd[s].a = e; nd[s].b = -1; nd[s].op = 0; nd[s].c = -1;
    return;
  }
  if k == S_IF { gs_rewrite(nd[s].b); gs_rewrite(nd[s].c); }
  if k == S_WHILE { gs_rewrite(nd[s].b); }
  if k == S_BLOCK || k == S_INL { let mut c = nd[s].a; while c >= 0 { gs_rewrite(c); c = nd[c].next; } }
}
fn gs_loop(s: i64) -> bool {
  gtag += 1; ngl = 0;
  if !gs_expr_ok(nd[s].a) || !gs_stmt_ok(nd[s].b) || ngl == 0 { return false; }
  // let t = g; while ..; g = t
  let w = mk(S_WHILE); copy_node(w, s); nd[w].next = -1;
  let mut head = -1; let mut tail = -1;
  let mut i = 0;
  while i < ngl {
    let g = gl_list[i];
    let t = hidden(); vars[t].ty = vars[g].et; vars[t].mutv = 1;
    gpro[g] = t + 1;
    let ld = mk_load(g, mkconst(0)); nd[ld].ty = vars[g].et;
    let l = mk(S_LET); nd[l].var = t; nd[l].a = ld;
    if tail < 0 { head = l; } else { nd[tail].next = l; }
    tail = l;
    i += 1;
  }
  gs_rewrite_e(nd[w].a); gs_rewrite(nd[w].b);
  nd[tail].next = w; tail = w;
  i = 0;
  while i < ngl {
    let g = gl_list[i]; let t = gpro[g] - 1;
    let st = mk(S_STORE); nd[st].var = g; nd[st].a = mkconst(0); nd[st].b = mk_var(t); nd[st].op = -1; nd[st].chk = 0; nd[st].c = -1;
    vars[vars[g].basev].reads += 1;
    nd[tail].next = st; tail = st;
    gpro[g] = 0;
    i += 1;
  }
  set_block(s, head, nd[s].next);
  npromoted += ngl;
  return true;
}
fn gs_stmts(s: i64) {
  if s < 0 { return; }
  let k = nd[s].k;
  if k == S_WHILE { if !gs_loop(s) { gs_stmts(nd[s].b); } return; }
  if k == S_BLOCK || k == S_INL { let mut c = nd[s].a; while c >= 0 { gs_stmts(c); c = nd[c].next; } return; }
  if k == S_IF { gs_stmts(nd[s].b); gs_stmts(nd[s].c); return; }
  if k == S_PAR { gs_stmts(nd[s].c); return; }
}
fn promote_globals() {
  let mut v = 0;
  while v < nv { if vars[v].garr != 0 { gsc[vars[v].garr] = true; } v += 1; }
  let mut f = 0;
  while f < nfn { if fns[f].used != 0 { gs_stmts(fns[f].body); } f += 1; }
}
fn simplify() {
  let mut round = 0;
  while round < 4 {
    const_prop();
    let mut ch = false;
    let mut f = 0;
    while f < nfn { if fns[f].used != 0 && unroll_stmts(fns[f].body) { ch = true; } f += 1; }
    if !ch { break; }
    round += 1;
  }
  const_prop();
  promote_globals();
}
fn mark_used_stmt(s: i64) {
  if s < 0 { return; }
  let k = nd[s].k;
  mark_used_expr(nd[s].a);
  if k == S_STORE || k == S_WRITE || k == S_SAVE { mark_used_expr(nd[s].b); }
  if k == S_IF { mark_used_stmt(nd[s].b); mark_used_stmt(nd[s].c); }
  if k == S_WHILE { mark_used_stmt(nd[s].b); }
  if k == S_PAR { mark_used_expr(nd[s].b); mark_used_stmt(nd[s].c); }
  if k == S_BLOCK || k == S_INL { let mut c = nd[s].a; while c >= 0 { mark_used_stmt(c); c = nd[c].next; } }
}
fn mark_used_expr(e: i64) {
  if e < 0 || e >= nn { return; }
  let k = nd[e].k;
  if k > N_ARR { return; }
  if k == N_CALL {
    let f = nd[e].var;
    if fns[f].used == 0 { fns[f].used = 1; mark_used_stmt(fns[f].body); }
    let mut a = nd[e].a;
    while a >= 0 { mark_used_expr(a); a = nd[a].next; }
    return;
  }
  mark_used_expr(nd[e].a); mark_used_expr(nd[e].b);
}
fn mark_used() {
  let mut f = 0;
  while f < nfn { fns[f].used = 0; f += 1; }
  fns[mainfn].used = 1; mark_used_stmt(fns[mainfn].body);
}

// ---------------------------------------------------------------- periodic-index strength reduction
fn count_assign(s: i64, v: i64) -> i64 {
  if s < 0 { return 0; }
  let k = nd[s].k;
  let mut c = 0;
  if (k == S_LET || k == S_ASSIGN || k == S_IRET) && nd[s].var == v { c += 1; }
  if k == S_BLOCK || k == S_INL { let mut ch = nd[s].a; while ch >= 0 { c += count_assign(ch, v); ch = nd[ch].next; } return c; }
  if k == S_IF { c += count_assign(nd[s].b, v) + count_assign(nd[s].c, v); }
  if k == S_WHILE { c += count_assign(nd[s].b, v); }
  if k == S_PAR { c += count_assign(nd[s].c, v); if nd[s].var == v { c += 1; } }
  return c;
}
fn invariant(e: i64, lp: i64) -> bool {
  if e < 0 { return true; }
  let k = nd[e].k;
  if k == N_LOAD || k == N_CALL || k == N_ARR { return false; }
  if k == N_VAR { return count_assign(lp, nd[e].var) == 0; }
  return invariant(nd[e].a, lp) && invariant(nd[e].b, lp);
}
fn is_inc1(s: i64, v: i64) -> bool {
  if nd[s].k != S_ASSIGN || nd[s].var != v { return false; }
  let e = nd[s].a;
  return nd[e].k == N_BIN && nd[e].op == O_ADD && nd[nd[e].a].k == N_VAR && nd[nd[e].a].var == v && is_const(nd[e].b) && nd[nd[e].b].v == 1;
}
let mut nsr: i64 = 0;
fn mk_assign(v: i64, e: i64) -> i64 { let s = mk(S_ASSIGN); nd[s].var = v; nd[s].a = e; return s; }
let mut SR_IH: i64 = -1;   // init statements chain (head/tail)
let mut SR_IT: i64 = -1;
fn sr_scan(e: i64, lp: i64, ivar: i64, incstmt: i64) {
  if e < 0 { return; }
  let k = nd[e].k;
  if k == N_BIN || k == N_UN || k == N_LOAD { sr_scan(nd[e].a, lp, ivar, incstmt); sr_scan(nd[e].b, lp, ivar, incstmt); }
  if k == N_CALL { let mut a = nd[e].a; while a >= 0 { sr_scan(a, lp, ivar, incstmt); a = nd[a].next; } }
  if nd[e].k != N_BIN || nd[e].op != O_MOD { return; }
  let d = nd[e].a;
  let mut E = -1;
  if nd[d].k == N_VAR && nd[d].var == ivar { }
  else if nd[d].k == N_BIN && nd[d].op == O_ADD && nd[nd[d].a].k == N_VAR && nd[nd[d].a].var == ivar { E = nd[d].b; }
  else { return; }
  let xb = nd[e].b;
  if !invariant(xb, lp) || (E >= 0 && !invariant(E, lp)) { return; }
  if has_trap(xb) || (E >= 0 && has_trap(E)) { return; }
  if wentry[lp] == 0 { return; }
  let en = wentry[lp] - 1;
  lmap_for(wfn[lp]);
  if dead(en) { return; }
  er(d, en);
  let dlo = RLO; let dbot = RBOT;
  er(xb, en);
  if dbot || dlo < 0 || RBOT || RLO < 1 { return; }
  let m = hidden(); vars[m].mutv = 1;
  let init = mk(S_LET); nd[init].var = m;
  let c1 = clone_expr(d);
  let c2 = clone_expr(xb);
  nd[init].a = mk_bin(O_MOD, c1, c2);
  nd[nd[init].a].nn = 1;
  if SR_IT < 0 { SR_IH = init; } else { nd[SR_IT].next = init; }
  SR_IT = init;
  let mv = mk_var(m);
  let one = mkconst(1);
  let inc = mk_assign(m, mk_bin(O_ADD, mv, one));
  let reset = mk_assign(m, mkconst(0));
  let blk = mk(S_BLOCK); nd[blk].a = reset;
  let iff = mk(S_IF);
  let mv2 = mk_var(m);
  let cp = clone_expr(xb);
  nd[iff].a = mk_bin(O_EQ, mv2, cp); nd[iff].b = blk;
  nd[inc].next = iff; nd[iff].next = nd[incstmt].next; nd[incstmt].next = inc;
  nd[e].k = N_VAR; nd[e].var = m; nd[e].a = -1; nd[e].b = -1; vars[m].reads += 1;
  nsr += 1;
}
fn sr_stmts(s: i64, lp: i64, ivar: i64, incstmt: i64) {
  if s < 0 { return; }
  let k = nd[s].k;
  if k == S_BLOCK || k == S_INL { let mut c = nd[s].a; while c >= 0 { sr_stmts(c, lp, ivar, incstmt); c = nd[c].next; } }
  else if k == S_IRET { sr_scan(nd[s].a, lp, ivar, incstmt); }
  else if k == S_PAR { sr_scan(nd[s].a, lp, ivar, incstmt); sr_scan(nd[s].b, lp, ivar, incstmt); sr_stmts(nd[s].c, lp, ivar, incstmt); }
  else if k == S_LET || k == S_ASSIGN || k == S_RET || k == S_PRINT || k == S_PUTC || k == S_EXPR { sr_scan(nd[s].a, lp, ivar, incstmt); }
  else if k == S_WRITE || k == S_STORE { sr_scan(nd[s].a, lp, ivar, incstmt); sr_scan(nd[s].b, lp, ivar, incstmt); }
  else if k == S_IF { sr_scan(nd[s].a, lp, ivar, incstmt); sr_stmts(nd[s].b, lp, ivar, incstmt); sr_stmts(nd[s].c, lp, ivar, incstmt); }
  else if k == S_WHILE { sr_scan(nd[s].a, lp, ivar, incstmt); sr_stmts(nd[s].b, lp, ivar, incstmt); }
}
fn strength_reduce() {
  let n0 = nn;
  let mut L = 0;
  while L < n0 {
    if nd[L].k == S_WHILE && wentry[L] != 0 {
      let body_blk = nd[L].b;
      SR_IH = -1; SR_IT = -1;
      let mut s = nd[body_blk].a;
      while s >= 0 {
        if nd[s].k == S_ASSIGN && is_inc1(s, nd[s].var) {
          let v = nd[s].var;
          if count_assign(L, v) == 1 {
            sr_scan(nd[L].a, L, v, s);
            sr_stmts(body_blk, L, v, s);
          }
        }
        s = nd[s].next;
      }
      if SR_IH >= 0 {
        let w = mk(S_WHILE); copy_node(w, L); nd[w].next = -1;
        wentry[w] = wentry[L]; wentry[L] = 0; wfn[w] = wfn[L];
        nd[SR_IT].next = w;
        let keep_next = nd[L].next;
        set_block(L, SR_IH, keep_next);
      }
    }
    L += 1;
  }
  let mut i = 0;
  while i < nn { wentry[i] = 0; i += 1; }
}

// ---------------------------------------------------------------- linear-scan allocation
let RAX = 0; let RCX = 1; let RDX = 2; let RBX = 3; let RSP = 4; let RBP = 5; let RSI = 6; let RDI = 7;
let allregs = alloc<i64>(12);
fn init_regs() {
  allregs[0] = 6; allregs[1] = 7; allregs[2] = 8; allregs[3] = 9; allregs[4] = 10; allregs[5] = 11;
  allregs[6] = 3; allregs[7] = 5; allregs[8] = 12; allregs[9] = 13; allregs[10] = 14; allregs[11] = 15;
}
let mut nslots: i64 = 0;
let mut spilled: i64 = 0;
let mut peak_active: i64 = 0;
fn cheaper(a: i64, b: i64) -> bool {
  let la = vars[a].end - vars[a].start + 1;
  let lb = vars[b].end - vars[b].start + 1;
  return vars[a].weight * lb < vars[b].weight * la;
}
let order = alloc<i64>(65536);
let order2 = alloc<i64>(65536);
let scount = alloc<i64>(4194306);
// stable counting sort of order[0..no) by vars[].start (starts are pcs in 0..pc+1)
fn sort_by_start(no: i64) {
  let mut mxs = 0;
  let mut i = 0;
  while i < no { let st = vars[order[i]].start; if st < 0 || st > 4194303 { insertion_sort(no); return; } if st > mxs { mxs = st; } i += 1; }
  i = 0;
  while i <= mxs + 1 { scount[i] = 0; i += 1; }
  i = 0;
  while i < no { scount[vars[order[i]].start + 1] += 1; i += 1; }
  i = 1;
  while i <= mxs + 1 { scount[i] += scount[i - 1]; i += 1; }
  i = 0;
  while i < no { let st = vars[order[i]].start; order2[scount[st]] = order[i]; scount[st] += 1; i += 1; }
  i = 0;
  while i < no { order[i] = order2[i]; i += 1; }
}
fn insertion_sort(no: i64) {
  let mut i = 1;
  while i < no {
    let x = order[i];
    let mut j = i;
    while j > 0 && vars[order[j - 1]].start > vars[x].start { order[j] = order[j - 1]; j -= 1; }
    order[j] = x;
    i += 1;
  }
}
// stack slots are numbered per function, so each function's frame holds only its own spills
let fslot = alloc<i64>(4096);
let fpc_lo = alloc<i64>(4096);
let fpc_hi = alloc<i64>(4096);
fn new_slot(v: i64) {
  let mut fo = mainfn;
  let mut f = 0;
  if vars[v].start > 0 { // a value lives in the function whose walk contains its birth
    while f < nfn { if fns[f].used != 0 && fpc_lo[f] < vars[v].start && vars[v].start <= fpc_hi[f] { fo = f; } f += 1; }
  }
  vars[v].slot = fslot[fo]; fslot[fo] += 1; nslots += 1; spilled += 1;
}
let active = alloc<i64>(11);
// float scalars are allocated to xmm8..xmm15 (xmm0/1 are scratch, xmm2..7 the expression stack)
let XREG0 = 8;
let NXREG = 8;
let xactive = alloc<i64>(8);
let mut xspilled: i64 = 0;
let mut xpeak: i64 = 0;
fn is_xvar(v: i64) -> bool {
  let t = vars[v].ty;
  return (t == TY_F64 || t == TY_F32) && vars[v].arr == 0 && vars[v].garr == 0 && vars[v].glob == 0 && v > 1;
}
let fn_nr = alloc<bool>(4096);   // function never returns (always exits)
// calling convention: rbx, rbp, r12..r15 are preserved by the callee (saved in its prologue when it
// writes them); rsi, rdi, r8..r11 are saved by the caller around a call when live
fn nop_fill(at0: i64, n0: i64) {   // multi-byte NOPs over code[at0 .. at0 + n0)
  let mut at = at0; let mut n = n0;
  while n > 0 {
    if n >= 7 { code[at] = 15; code[at + 1] = 31; code[at + 2] = 128; code[at + 3] = 0; code[at + 4] = 0; code[at + 5] = 0; code[at + 6] = 0; at += 7; n -= 7; }
    else if n >= 4 { code[at] = 15; code[at + 1] = 31; code[at + 2] = 64; code[at + 3] = 0; at += 4; n -= 4; }
    else if n == 3 { code[at] = 15; code[at + 1] = 31; code[at + 2] = 0; at += 3; n -= 3; }
    else if n == 2 { code[at] = 102; code[at + 1] = 144; at += 2; n -= 2; }
    else { code[at] = 144; at += 1; n -= 1; }
  }
}
fn callee_saved(r: i64) -> bool { return r == RBX || r == RBP || r >= 12; }
let lext = alloc<bool>(65536);   // interval stretched to a loop's end (live around its back edge)
let chint = alloc<i64>(65536);   // variable defined as a plain copy of this one (register coalescing hint)
let callpc = alloc<i64>(1048576);   // pcs of statements containing a real call (non-decreasing)
let mut ncallpc: i64 = 0;
fn crosses_call(v: i64) -> bool {
  let st = vars[v].start; let en = vars[v].end;
  let mut lo = 0; let mut hi = ncallpc;
  while lo < hi { let m = (lo + hi) / 2; if callpc[m] <= st { lo = m + 1; } else { hi = m; } }
  return lo < ncallpc && callpc[lo] <= en;
}
// ---- tail recursion modulo +: in f, `return A + f(B)` becomes `acc = acc + A; params = B; continue` inside
// `let mut acc = 0; while true { body }`, and every other `return R` becomes `return acc + R`.
// Exact for wrapping 64-bit integers: A is evaluated before B as before, and + is associative and commutative.
let mut tre_n: i64 = 0;
fn tre_tail(s: i64, f: i64) -> bool {
  let e = nd[s].a;
  if e < 0 { return false; }
  if nd[e].k == N_CALL { return nd[e].var == f; }
  return nd[e].k == N_BIN && nd[e].op == O_ADD && nd[e].ty == fns[f].rett && nd[nd[e].b].k == N_CALL && nd[nd[e].b].var == f;
}
// number of tail returns, or -1 when the function cannot be rewritten
fn tre_scan(s: i64, f: i64, inloop: bool) -> i64 {
  if s < 0 { return 0; }
  let k = nd[s].k;
  if k == S_PAR || k == S_INL || k == S_IRET { return -1; }
  if k == S_RET { if !tre_tail(s, f) { return 0; } if inloop { return -1; } return 1; }
  let mut a = 0; let mut b = 0;
  if k == S_BLOCK { let mut c = nd[s].a; while c >= 0 { let x = tre_scan(c, f, inloop); if x < 0 { return -1; } a += x; c = nd[c].next; } return a; }
  if k == S_IF { a = tre_scan(nd[s].b, f, inloop); b = tre_scan(nd[s].c, f, inloop); if a < 0 || b < 0 { return -1; } return a + b; }
  if k == S_WHILE { return tre_scan(nd[s].b, f, true); }
  return 0;
}
fn tre_rewrite(s: i64, f: i64, acc: i64, last: bool) {
  if s < 0 { return; }
  let k = nd[s].k;
  if k == S_BLOCK { let mut c = nd[s].a; while c >= 0 { tre_rewrite(c, f, acc, last && nd[c].next < 0); c = nd[c].next; } return; }
  if k == S_IF { tre_rewrite(nd[s].b, f, acc, last); tre_rewrite(nd[s].c, f, acc, last); return; }
  if k == S_WHILE { tre_rewrite(nd[s].b, f, acc, false); return; }
  if k != S_RET { return; }
  let rt = fns[f].rett;
  if !tre_tail(s, f) { let e = mk_bin(O_ADD, mk_var(acc), nd[s].a); nd[e].ty = rt; nd[s].a = e; return; }
  let e = nd[s].a;
  let mut call = e;
  let mut head = -1; let mut tail = -1;
  if nd[e].k != N_CALL {
    call = nd[e].b;
    let ad = mk_bin(O_ADD, mk_var(acc), nd[e].a); nd[ad].ty = rt;
    let st = mk(S_ASSIGN); nd[st].var = acc; nd[st].a = ad; head = st; tail = st;
  }
  // arguments left to right into temporaries (all but the last), then into the parameters
  let np = fns[f].np;
  let tv = alloc<i64>(16);
  let mut x = nd[call].a; let mut i = 0;
  while x >= 0 {
    let nx = nd[x].next; nd[x].next = -1;
    let pv = fpvar[f * 16 + i];
    let mut st = -1;
    if i == np - 1 { st = mk(S_ASSIGN); nd[st].var = pv; nd[st].a = x; tv[i] = -1; }
    else if nd[x].k == N_VAR && nd[x].var == pv { tv[i] = -1; }
    else { let t = hidden(); vars[t].ty = vars[pv].ty; vars[t].mutv = 1; st = mk(S_LET); nd[st].var = t; nd[st].a = x; tv[i] = t; }
    if st >= 0 { if head < 0 { head = st; } else { nd[tail].next = st; } tail = st; }
    x = nx; i += 1;
  }
  i = 0;
  while i < np - 1 {
    if tv[i] >= 0 {
      let st = mk(S_ASSIGN); nd[st].var = fpvar[f * 16 + i]; nd[st].a = mk_var(tv[i]);
      if head < 0 { head = st; } else { nd[tail].next = st; } tail = st;
    }
    i += 1;
  }
  if !last {
    let st = mk(S_CONT);
    if head < 0 { head = st; } else { nd[tail].next = st; } tail = st;
  }
  set_block(s, head, nd[s].next);
}
fn tre_fn(f: i64) {
  let b = fns[f].body;
  let rt = fns[f].rett;
  if b < 0 || (rt != TY_I64 && rt != TY_U64) || fns[f].mark >= 0 || fns[f].np < 1 || fns[f].np > 16 { return; }
  let mut i = 0;
  while i < fns[f].np { if fpw[f * 16 + i] != 0 { return; } i += 1; }
  if !terminates(b) || tre_scan(b, f, false) <= 0 { return; }
  i = 0;
  while i < fns[f].np { vars[fpvar[f * 16 + i]].mutv = 1; i += 1; }
  let acc = hidden(); vars[acc].ty = rt; vars[acc].mutv = 1; vars[acc].owner = f;
  let lb = mk(S_BLOCK); nd[lb].a = nd[b].a;
  tre_rewrite(lb, f, acc, true);
  let w = mk(S_WHILE); nd[w].a = mkconst_t(1, TY_BOOL); nd[w].b = lb;
  let la = mk(S_LET); nd[la].var = acc; nd[la].a = mkconst_t(0, rt); nd[la].next = w;
  nd[b].a = la;
  tre_n += 1;
}
// ---- carried stores: in `while i < E { ..; a[i] (op)= v; ..; i += 1 }` a load a[i - 1] reads what
// the previous iteration stored, so that value stays in a variable instead of going through memory
// (prefix sums, DP rows). The first a[i - 1] is loaded before the loop when the loop will run; the
// body may not print, call, divide by a variable or nest loops, so every possible trap is the same
// bounds-check SIGILL and loading it earlier is unobservable.
let mut CS_F: i64 = -1;
let mut CS_A: i64 = -1;
let mut CS_BAD: bool = false;
let mut CS_NLD: i64 = 0;
let mut CS_NST: i64 = 0;
let mut CS_ST: i64 = -1;
fn cs_prev(x: i64, iv: i64) -> bool {
  return nd[x].k == N_BIN && nd[x].op == O_SUB && nd[nd[x].a].k == N_VAR && nd[nd[x].a].var == iv && is_const(nd[x].b) && nd[nd[x].b].v == 1;
}
fn cs_scan_e(e: i64, iv: i64, rw: bool) {   // rw: rewrite a[i - 1] -> CS temporary
  if e < 0 { return; }
  let k = nd[e].k;
  if k == N_CALL || k == N_NCPU { CS_BAD = true; return; }
  if k == N_CONST || k == N_VAR || k == N_ARR { return; }
  if k == N_BIN && (nd[e].op == O_DIV || nd[e].op == O_MOD || nd[e].op == O_DIVU || nd[e].op == O_MODU) && !(is_const(nd[e].b) && nd[nd[e].b].v != 0 && (nd[nd[e].b].v as i64) != -1) { CS_BAD = true; }
  if k == N_LOAD && vars[nd[e].var].basev == vars[CS_A].basev {
    let x = nd[e].a;
    if nd[e].op > 0 || vars[nd[e].var].arr != vars[CS_A].arr { CS_BAD = true; return; }
    if nd[x].k == N_VAR && nd[x].var == iv { return; }
    if cs_prev(x, iv) { CS_NLD += 1; if rw { nd[e].k = N_VAR; nd[e].var = CS_T; nd[e].a = -1; vars[CS_T].reads += 1; } return; }
    CS_BAD = true; return;
  }
  cs_scan_e(nd[e].a, iv, rw); cs_scan_e(nd[e].b, iv, rw);
}
let mut CS_T: i64 = -1;
fn cs_scan_s(s: i64, iv: i64, rw: bool) {
  if s < 0 { return; }
  let k = nd[s].k;
  if k == S_BLOCK { let mut c = nd[s].a; while c >= 0 { cs_scan_s(c, iv, rw); c = nd[c].next; } return; }
  if k == S_LET || k == S_ASSIGN { cs_scan_e(nd[s].a, iv, rw); return; }
  if k == S_IF { cs_scan_e(nd[s].a, iv, rw); cs_scan_s(nd[s].b, iv, rw); cs_scan_s(nd[s].c, iv, rw); return; }
  if k == S_STORE {
    cs_scan_e(nd[s].a, iv, rw); cs_scan_e(nd[s].b, iv, rw);
    if vars[nd[s].var].basev == vars[CS_A].basev { CS_NST += 1; if s != CS_ST { CS_BAD = true; } }
    else if CS_F != mainfn { CS_BAD = true; }   // parameters may be the same array
    return;
  }
  CS_BAD = true;
}
fn cs_loop(w: i64) {
  let cnd = nd[w].a;
  if nd[cnd].k != N_BIN || (nd[cnd].op != O_LT && nd[cnd].op != O_LE) || nd[nd[cnd].a].k != N_VAR { return; }
  let iv = nd[nd[cnd].a].var;
  if vars[iv].ty != TY_I64 || count_assign(w, iv) != 1 || has_call(cnd) || nd[w].c >= 0 { return; }
  let body = nd[w].b;
  if nd[body].k != S_BLOCK { return; }
  // the increment is last; the store a[i] (op)= v is a top-level statement or ends a top-level block
  let mut prev = -1; let mut c = nd[body].a; let mut st = -1;
  while c >= 0 && nd[c].next >= 0 {
    let mut x = c;
    if nd[x].k == S_BLOCK { x = nd[x].a; while x >= 0 && nd[x].next >= 0 { x = nd[x].next; } }
    if x >= 0 && nd[x].k == S_STORE && nd[nd[x].a].k == N_VAR && nd[nd[x].a].var == iv && st < 0 { st = x; }
    prev = c; c = nd[c].next;
  }
  if c < 0 || !is_inc1(c, iv) || st < 0 || prev < 0 { return; }
  let a = nd[st].var;
  let et = vars[a].et;
  if nd[st].c >= 0 || vars[a].arr != 8 || !(et == TY_I64 || et == TY_U64 || et == TY_F64) { return; }
  if nd[st].op >= 0 && !is_alu_op(nd[st].op) { return; }
  CS_A = a; CS_ST = st; CS_BAD = false; CS_NLD = 0; CS_NST = 0;
  cs_scan_e(cnd, iv, false);
  let mut q = nd[body].a; while q >= 0 && q != c { cs_scan_s(q, iv, false); q = nd[q].next; }
  if CS_BAD || CS_NLD == 0 || CS_NST != 1 { return; }
  // rewrite
  let t = hidden(); vars[t].ty = et; vars[t].mutv = 1; vars[t].owner = CS_F; CS_T = t;
  let nvv = hidden(); vars[nvv].ty = et; vars[nvv].mutv = 1; vars[nvv].owner = CS_F;
  q = nd[body].a; while q >= 0 && q != c { cs_scan_s(q, iv, true); q = nd[q].next; }
  let mut val = nd[st].b;
  if nd[st].op >= 0 { val = mk_bin(nd[st].op, mk_load(a, mk_var(iv)), val); if nd[val].ty != et { nd[val].ty = et; } nd[st].op = -1; }
  let st2 = mk(S_STORE); copy_node(st2, st); nd[st2].next = -1; nd[st2].b = mk_var(nvv);
  let as1 = mk_assign(nvv, val); nd[as1].next = st2;
  set_block(st, as1, nd[st].next);
  let at = mk_assign(t, mk_var(nvv)); nd[at].next = c; nd[prev].next = at;
  // before the loop: let mut t = 0; let mut nv = 0; if cond { t = a[i - 1]; }
  let w2 = mk(S_WHILE); copy_node(w2, w); nd[w2].next = -1;
  let ld = mk_load(a, mk_bin(O_SUB, mk_var(iv), mkconst_t(1, TY_I64)));
  let tif = mk(S_IF); nd[tif].a = clone_expr(cnd); nd[tif].b = mk_assign(t, ld); nd[tif].c = -1; nd[tif].next = w2;
  let l2 = mk(S_LET); nd[l2].var = nvv; nd[l2].a = mkconst_t(0, et); nd[l2].next = tif;
  let l1 = mk(S_LET); nd[l1].var = t; nd[l1].a = mkconst_t(0, et); nd[l1].next = l2;
  set_block(w, l1, nd[w].next);
}
// ---- small matches: `let mut j = 0; while j < M && C(j) { j += 1; } if j == M { S }` with a constant
// M <= 8 and j unused elsewhere becomes `if C(0) && C(1) && .. && C(M - 1) { S }`: the same tests in the
// same short-circuit order (so the same traps), without the loop
fn sm_subst(e: i64, v: i64, k: i64) {   // in place: N_VAR v -> constant k
  if e < 0 { return; }
  let kk = nd[e].k;
  if kk == N_VAR { if nd[e].var == v { let ty = nd[e].ty; nd[e].k = N_CONST; nd[e].v = k as u64; nd[e].ty = ty; nd[e].var = -1; nd[e].c = -1; vars[v].reads -= 1; } return; }
  if kk == N_CONST || kk == N_ARR || kk == N_NCPU { return; }
  if kk == N_CALL { let mut a = nd[e].a; while a >= 0 { sm_subst(a, v, k); a = nd[a].next; } return; }
  sm_subst(nd[e].a, v, k); sm_subst(nd[e].b, v, k);
}
fn sm_try(l: i64) -> bool {   // l: the let; rewrites l, its next (while) and the if after it
  if nd[l].k != S_LET || !is_const(nd[l].a) || nd[nd[l].a].v != 0 { return false; }
  let j = nd[l].var;
  let w = nd[l].next; if w < 0 || nd[w].k != S_WHILE || nd[w].c >= 0 { return false; }
  let f = nd[w].next; if f < 0 || nd[f].k != S_IF || nd[f].c >= 0 { return false; }
  let cnd = nd[w].a;
  if nd[cnd].k != N_BIN || nd[cnd].op != O_LAND { return false; }
  let lim = nd[cnd].a; let C = nd[cnd].b;
  if nd[lim].k != N_BIN || nd[lim].op != O_LT || nd[nd[lim].a].k != N_VAR || nd[nd[lim].a].var != j || !is_const(nd[lim].b) { return false; }
  let M = nd[nd[lim].b].v as i64;
  if M < 1 || M > 8 || has_call(C) { return false; }
  let mut b = nd[w].b; if nd[b].k == S_BLOCK { b = nd[b].a; if b < 0 || nd[b].next >= 0 { return false; } }
  if !is_inc1(b, j) { return false; }
  let fc = nd[f].a;
  if nd[fc].k != N_BIN || nd[fc].op != O_EQ || nd[nd[fc].a].k != N_VAR || nd[nd[fc].a].var != j || !is_const(nd[fc].b) || (nd[nd[fc].b].v as i64) != M { return false; }
  // j is read only by the loop test, the increment and the final test
  if vars[j].reads != ex_reads(cnd, j) + 1 + 1 || st_reads(nd[f].b, j) != 0 { return false; }
  let mut conj = -1;
  let mut k = M - 1;
  while k >= 0 {
    let ck = clone_expr(C); sm_subst(ck, j, k);
    if conj < 0 { conj = ck; } else { let a2 = mk(N_BIN); nd[a2].op = O_LAND; nd[a2].a = ck; nd[a2].b = conj; nd[a2].ty = TY_BOOL; conj = a2; }
    k -= 1;
  }
  nd[f].a = conj;
  // drop the let and the loop: l becomes an empty block before the if
  set_block(l, -1, f);
  vars[j].reads = 0;
  return true;
}
fn sm_walk(s: i64) {
  if s < 0 { return; }
  let k = nd[s].k;
  if k == S_BLOCK || k == S_INL { let mut c = nd[s].a; while c >= 0 { sm_try(c); sm_walk(c); c = nd[c].next; } return; }
  if k == S_IF { sm_walk(nd[s].b); sm_walk(nd[s].c); return; }
  if k == S_WHILE { sm_walk(nd[s].b); return; }
}
// ---- one division for a / b and a % b: when a statement computes both on the same load-free,
// call-free operands and nothing else in it can trap, q = a / b is computed first and
// a % b becomes a - q * b (exact: |q * b| <= |a|; the only traps are this division's own)
let mut DM_DIV: i64 = -1;
fn dm_find(e: i64, op: i64) -> i64 {   // a node a op b (op DIV or DIVU) somewhere in e
  if e < 0 { return -1; }
  let k = nd[e].k;
  if k == N_CONST || k == N_VAR || k == N_ARR || k == N_LOAD || k == N_CALL || k == N_NCPU { return -1; }
  // Hoisting before the statement is unsafe for either operand of a short-circuit node.
  if k == N_BIN && (nd[e].op == O_LAND || nd[e].op == O_LOR) { return -1; }
  if k == N_BIN && nd[e].op == op && !is_const(nd[e].b) && ic_pure(nd[e].a) && ic_pure(nd[e].b) { return e; }
  let x = dm_find(nd[e].a, op); if x >= 0 { return x; }
  return dm_find(nd[e].b, op);
}
fn dm_other_trap(e: i64, d: i64, m: i64) -> bool {   // a trap anywhere but the division pair
  if e < 0 || e == d || e == m { return false; }
  let k = nd[e].k;
  if k == N_CONST || k == N_VAR || k == N_ARR { return false; }
  if k == N_CALL || k == N_LOAD { return true; }
  if k == N_BIN && (nd[e].op == O_DIV || nd[e].op == O_MOD || nd[e].op == O_DIVU || nd[e].op == O_MODU) && has_trap(e) { return true; }
  return dm_other_trap(nd[e].a, d, m) || dm_other_trap(nd[e].b, d, m);
}
fn dm_mod(e: i64, d: i64, mop: i64) -> i64 {   // the matching a % b node
  if e < 0 { return -1; }
  let k = nd[e].k;
  if k == N_CONST || k == N_VAR || k == N_ARR || k == N_LOAD || k == N_CALL || k == N_NCPU { return -1; }
  // Keep the matching remainder in the same unconditional region as its quotient.
  if k == N_BIN && (nd[e].op == O_LAND || nd[e].op == O_LOR) { return -1; }
  if k == N_BIN && nd[e].op == mop && expr_same(nd[e].a, nd[d].a) && expr_same(nd[e].b, nd[d].b) { return e; }
  let x = dm_mod(nd[e].a, d, mop); if x >= 0 { return x; }
  return dm_mod(nd[e].b, d, mop);
}
fn dm_stmt(s: i64) {
  let k = nd[s].k;
  if !(k == S_LET || k == S_ASSIGN || k == S_PRINT) { return; }
  let e = nd[s].a;
  let mut op = O_DIV; let mut d = dm_find(e, O_DIV);
  if d < 0 { op = O_DIVU; d = dm_find(e, O_DIVU); }
  if d < 0 { return; }
  let mut mop = O_MOD; if op == O_DIVU { mop = O_MODU; }
  let m = dm_mod(e, d, mop);
  if m < 0 || dm_other_trap(e, d, m) || !ty_int(nd[d].ty) { return; }
  let q = hidden(); vars[q].ty = nd[d].ty; vars[q].owner = CS_F;
  // q = a / b, before the statement (s itself becomes the block {let q; s'})
  let qd = mk(N_BIN); copy_node(qd, d); nd[qd].a = clone_expr(nd[d].a); nd[qd].b = clone_expr(nd[d].b);
  let s2 = mk(nd[s].k); copy_node(s2, s); nd[s2].next = -1;
  let lq = mk(S_LET); nd[lq].var = q; nd[lq].a = qd; nd[lq].next = s2;
  // a % b -> a - q * b; a / b -> q
  let pr = mk_bin(O_MUL, mk_var(q), clone_expr(nd[m].b)); nd[pr].ty = nd[m].ty;
  let df = mk_bin(O_SUB, clone_expr(nd[m].a), pr); nd[df].ty = nd[m].ty;
  copy_node(m, df);
  let qv = mk_var(q); nd[qv].ty = nd[d].ty; copy_node(d, qv);
  set_block(s, lq, nd[s].next);
}
fn dm_walk(s: i64) {
  if s < 0 { return; }
  let k = nd[s].k;
  if k == S_BLOCK || k == S_INL { let mut c = nd[s].a; while c >= 0 { let nx = nd[c].next; dm_walk(c); c = nx; } return; }
  if k == S_IF { dm_walk(nd[s].b); dm_walk(nd[s].c); return; }
  if k == S_WHILE { dm_walk(nd[s].b); return; }
  dm_stmt(s);
}
// ---- select stores: in a loop, `if C { a[k] = X; S1 } else { a[k] = Y; S2 }` (S1, S2 a few
// if-convertible assignments that leave k alone) becomes `let u = X; let t = Y; if C' { t = u; S1 }
// else { S2 } a[k] = t`, which if-conversion makes branch-free (merges). X and Y are pure or are
// loads C itself performs unconditionally; C may only trap by bounds checks, so every trap is the
// same SIGILL whichever load runs first, and C' reads u/t in place of those loads.
fn ss_cok(e: i64) -> bool {
  if e < 0 { return true; }
  let k = nd[e].k;
  if k == N_VAR || k == N_CONST { return true; }
  if !ty_int(nd[e].ty) { return false; }
  if k == N_LOAD { return ss_cok(nd[e].a); }
  if k == N_UN { return ss_cok(nd[e].a); }
  if k != N_BIN || nd[e].op == O_LAND || nd[e].op == O_LOR || nd[e].op == O_DIV || nd[e].op == O_MOD || nd[e].op == O_DIVU || nd[e].op == O_MODU { return false; }
  return ss_cok(nd[e].a) && ss_cok(nd[e].b);
}
fn ss_in(e: i64, x: i64) -> bool {
  if e < 0 { return false; }
  if expr_same(e, x) { return true; }
  let k = nd[e].k;
  if k == N_VAR || k == N_CONST { return false; }
  return ss_in(nd[e].a, x) || ss_in(nd[e].b, x);
}
fn ss_sub(e: i64, x: i64, v: i64) -> i64 {   // e with subtrees equal to x replaced by v
  if e < 0 { return e; }
  if expr_same(e, x) { return mk_var(v); }
  let k = nd[e].k;
  if k == N_VAR || k == N_CONST { return e; }
  nd[e].a = ss_sub(nd[e].a, x, v); nd[e].b = ss_sub(nd[e].b, x, v);
  return e;
}
fn ss_store(b: i64) -> i64 {   // the leading plain store of branch b, or -1
  if b < 0 || nd[b].k != S_BLOCK { return -1; }
  let st = nd[b].a;
  if st < 0 || nd[st].k != S_STORE || nd[st].op >= 0 || nd[st].c >= 0 || !ty_int(vars[nd[st].var].et) { return -1; }
  return st;
}
fn ss_keeps(s: i64, idx: i64) -> bool {   // statements s.. assign nothing idx reads
  let mut c = s;
  while c >= 0 {
    if nd[c].k == S_ASSIGN && ex_reads(idx, nd[c].var) != 0 { return false; }
    if nd[c].k == S_IF && !(ss_keeps(nd[c].b, idx) && ss_keeps(nd[c].c, idx)) { return false; }
    if nd[c].k == S_BLOCK && !ss_keeps(nd[c].a, idx) { return false; }
    c = nd[c].next;
  }
  return true;
}
fn ss_val(x: i64, c: i64) -> bool { return ic_pure(x) || (nd[x].k == N_LOAD && ss_in(c, x)); }
fn ss_try(s: i64) {
  if nd[s].k != S_IF || nd[s].c < 0 { return; }
  let c = nd[s].a;
  if nd[c].k != N_BIN || !is_cmp(nd[c].op) || !ss_cok(nd[c].a) || !ss_cok(nd[c].b) { return; }
  let s1 = ss_store(nd[s].b); let s2 = ss_store(nd[s].c);
  if s1 < 0 || s2 < 0 || nd[s1].var != nd[s2].var || !expr_same(nd[s1].a, nd[s2].a) || !ic_pure(nd[s1].a) { return; }
  let x = nd[s1].b; let y = nd[s2].b;
  if !ss_val(x, c) || !ss_val(y, c) || nd[x].ty != nd[y].ty { return; }
  let r1 = nd[s1].next; let r2 = nd[s2].next;
  IC_NEST = false;
  let n1 = ic_count_list(r1); let n2 = ic_count_list(r2);
  if n1 < 0 || n2 < 0 || n1 + n2 > 3 || !ss_keeps(r1, nd[s1].a) || !ss_keeps(r2, nd[s1].a) { return; }
  let u = hidden(); vars[u].ty = nd[x].ty; vars[u].owner = CS_F;
  let t = hidden(); vars[t].ty = nd[x].ty; vars[t].mutv = 1; vars[t].owner = CS_F;
  let lu = mk(S_LET); nd[lu].var = u; nd[lu].a = clone_expr(x);
  let lt = mk(S_LET); nd[lt].var = t; nd[lt].a = clone_expr(y); nd[lu].next = lt;
  let f = mk(S_IF); copy_node(f, s); nd[lt].next = f;
  nd[f].a = ss_sub(ss_sub(c, x, u), y, t);
  let au = mk_assign(t, mk_var(u)); nd[au].next = r1;
  let b1 = mk(S_BLOCK); set_block(b1, au, -1); nd[f].b = b1;
  let b2 = mk(S_BLOCK); set_block(b2, r2, -1); nd[f].c = b2;
  nd[s1].b = mk_var(t); nd[s1].next = -1; nd[f].next = s1;
  set_block(s, lu, nd[s].next);
}
fn ic_count_list(c0: i64) -> i64 {
  let mut t = 0; let mut c = c0;
  while c >= 0 { let x = ic_count(c, 0); if x < 0 { return -1; } t += x; c = nd[c].next; }
  return t;
}
fn ss_walk(s: i64, inl: bool) {
  if s < 0 { return; }
  let k = nd[s].k;
  if k == S_BLOCK || k == S_INL { let mut c = nd[s].a; while c >= 0 { let nx = nd[c].next; ss_walk(c, inl); c = nx; } return; }
  if k == S_IF { if inl { ss_try(s); } if nd[s].k == S_IF { ss_walk(nd[s].b, inl); ss_walk(nd[s].c, inl); } return; }
  if k == S_WHILE { ss_walk(nd[s].b, true); return; }
}
// ---- min/max chains: `if X1 < v { v = X1 } if X2 < v { v = X2 }` (pure X not reading v) gives
// v = min(v, X1, X2) in either order; the update whose X reads a variable set later in the loop
// body (a value carried from the previous iteration) goes last, off the critical path (DP cells)
fn mm_later(c: i64, x: i64) -> bool {   // x reads a variable assigned by a statement from c on
  let mut q = c;
  while q >= 0 { if (nd[q].k == S_ASSIGN || nd[q].k == S_LET) && ex_reads(x, nd[q].var) != 0 { return true; } q = nd[q].next; }
  return false;
}
fn mm_pair(s1: i64) {
  let s2 = nd[s1].next;
  if s2 < 0 { return; }
  let k1 = minmax_kind(s1); let v1 = MM_VAR; let x1 = MM_X;
  if k1 == 0 { return; }
  let k2 = minmax_kind(s2); let x2 = MM_X;
  if k2 != k1 || MM_VAR != v1 || !ty_int(vars[v1].ty) || !ic_pure(x1) || !ic_pure(x2) || refs(x1, v1) || refs(x2, v1) { return; }
  if !mm_later(nd[s2].next, x1) || mm_later(nd[s2].next, x2) { return; }
  let ta = nd[s1].a; let tb = nd[s1].b;
  nd[s1].a = nd[s2].a; nd[s1].b = nd[s2].b; nd[s2].a = ta; nd[s2].b = tb;
}
fn mm_walk(s: i64, inl: bool) {
  if s < 0 { return; }
  let k = nd[s].k;
  if k == S_BLOCK || k == S_INL { let mut c = nd[s].a; while c >= 0 { if inl { mm_pair(c); } mm_walk(c, inl); c = nd[c].next; } return; }
  if k == S_IF { mm_walk(nd[s].b, inl); mm_walk(nd[s].c, inl); return; }
  if k == S_WHILE { mm_walk(nd[s].b, true); return; }
}
// ---- invariant loads: in an innermost `while C { .. }` without calls, output, exits or division
// by a variable, a load A[k] that every iteration performs (a top-level statement, not under
// && / ||) with k loop-invariant and A never stored in the loop is read once before the loop
// when C holds; every trap left is the same bounds-check SIGILL, so reading it earlier is
// unobservable. Outside main an array parameter may share memory with a stored array: then
// `if base(A) == base(B) .. { original loop } else { hoisted loop }`.
let mut LH_BAD: bool = false;
let mut LH_A: i64 = -1;
let LH_ST = alloc<i64>(16);
let mut LH_NST: i64 = 0;
fn lh_e(e: i64) {
  if e < 0 { return; }
  let k = nd[e].k;
  if k == N_CALL || k == N_NCPU || k == N_ARR { LH_BAD = true; return; }
  if k == N_CONST || k == N_VAR { return; }
  if k == N_BIN && (nd[e].op == O_DIV || nd[e].op == O_MOD || nd[e].op == O_DIVU || nd[e].op == O_MODU) && !(is_const(nd[e].b) && nd[nd[e].b].v != 0 && (nd[nd[e].b].v as i64) != -1) { LH_BAD = true; }
  lh_e(nd[e].a); lh_e(nd[e].b);
}
fn lh_s(s: i64) {
  if s < 0 { return; }
  let k = nd[s].k;
  if k == S_BLOCK { let mut c = nd[s].a; while c >= 0 { lh_s(c); c = nd[c].next; } return; }
  if k == S_LET { if vars[nd[s].var].arr != 0 { LH_BAD = true; } lh_e(nd[s].a); return; }
  if k == S_ASSIGN { lh_e(nd[s].a); return; }
  if k == S_IF { lh_e(nd[s].a); lh_s(nd[s].b); lh_s(nd[s].c); return; }
  if k == S_STORE {
    lh_e(nd[s].a); lh_e(nd[s].b);
    let b = vars[nd[s].var].basev;
    let mut i = 0; while i < LH_NST && LH_ST[i] != nd[s].var { i += 1; }
    if i == LH_NST { if LH_NST >= 16 { LH_BAD = true; return; } LH_ST[LH_NST] = nd[s].var; LH_NST += 1; }
    if b < 0 { LH_BAD = true; }
    return;
  }
  LH_BAD = true;
}
fn lh_find(e: i64, w: i64) -> i64 {   // an unconditionally evaluated invariant load in e
  if e < 0 { return -1; }
  let k = nd[e].k;
  if k == N_CONST || k == N_VAR { return -1; }
  if k == N_LOAD {
    let a = nd[e].var;
    if nd[e].op <= 0 && vars[a].arr != 0 && !(vars[a].ro != 0 && vars[a].lenv < 0) && invariant(nd[e].a, w) && ic_pure(nd[e].a) {   // not string literals (constant data, byte-lane patterns)
      let mut ok = true; let mut i = 0;
      while i < LH_NST { if vars[LH_ST[i]].basev == vars[a].basev { ok = false; } i += 1; }
      if ok { return e; }
    }
    return lh_find(nd[e].a, w);
  }
  if k == N_BIN && (nd[e].op == O_LAND || nd[e].op == O_LOR) { return lh_find(nd[e].a, w); }
  let x = lh_find(nd[e].a, w); if x >= 0 { return x; }
  return lh_find(nd[e].b, w);
}
fn lh_sub(e: i64, x: i64, h: i64) {   // in place: loads equal to x -> h
  if e < 0 { return; }
  if nd[e].k == N_LOAD && expr_same(e, x) { nd[e].k = N_VAR; nd[e].var = h; nd[e].a = -1; nd[e].op = 0; vars[h].reads += 1; return; }
  if nd[e].k == N_CONST || nd[e].k == N_VAR { return; }
  lh_sub(nd[e].a, x, h); lh_sub(nd[e].b, x, h);
}
fn lh_sub_s(s: i64, x: i64, h: i64) {
  if s < 0 { return; }
  let k = nd[s].k;
  if k == S_BLOCK { let mut c = nd[s].a; while c >= 0 { lh_sub_s(c, x, h); c = nd[c].next; } return; }
  if k == S_IF { lh_sub(nd[s].a, x, h); lh_sub_s(nd[s].b, x, h); lh_sub_s(nd[s].c, x, h); return; }
  lh_sub(nd[s].a, x, h); if k == S_STORE { lh_sub(nd[s].b, x, h); }
}
fn lh_loop(w: i64) {
  let cnd = nd[w].a; let body = nd[w].b;
  if nd[w].c >= 0 || has_call(cnd) || body < 0 || nd[body].k != S_BLOCK { return; }
  LH_BAD = false; LH_NST = 0;
  lh_e(cnd); lh_s(body);
  if LH_BAD { return; }
  let mut L = -1; let mut c = nd[body].a;
  while c >= 0 && L < 0 {
    let k = nd[c].k;
    if k == S_LET || k == S_ASSIGN || k == S_IF { L = lh_find(nd[c].a, w); }
    if k == S_STORE { L = lh_find(nd[c].b, w); if L < 0 { L = lh_find(nd[c].a, w); } }
    c = nd[c].next;
  }
  if L < 0 { return; }
  let A = nd[L].var;
  // alias test: stored arrays that may be A (outside main: another base variable)
  let mut ab = -1;
  if CS_F != mainfn {
    let mut i = 0;
    while i < LH_NST {
      let B = LH_ST[i];
      if vars[vars[B].basev].glob != 2 && vars[vars[A].basev].glob != 2 {
        let ea = mk(N_ARR); nd[ea].var = A; vars[vars[A].basev].reads += 1; nd[ea].ty = TY_I64;
        let eb = mk(N_ARR); nd[eb].var = B; vars[vars[B].basev].reads += 1; nd[eb].ty = TY_I64;
        let q = mk_bin(O_EQ, ea, eb); nd[q].ty = TY_BOOL;
        if ab < 0 { ab = q; } else { let o = mk_bin(O_LOR, ab, q); nd[o].ty = TY_BOOL; ab = o; }
      }
      i += 1;
    }
  }
  let ld = clone_expr(L);
  let h = hidden(); vars[h].ty = nd[L].ty; vars[h].mutv = 1; vars[h].owner = CS_F;
  let w2 = mk(S_WHILE); copy_node(w2, w); nd[w2].next = -1;
  if ab >= 0 {   // w2 becomes a copy of the loop
    igen += 1;
    let nv0 = nv;
    let cl = clone_stmt_inl(w, -2);
    let mut v = nv0; while v < nv { vars[v].owner = CS_F; v += 1; }
    copy_node(w2, cl); nd[w2].next = -1;
  }
  lh_sub_s(nd[w2].b, L, h); lh_sub(nd[w2].a, L, h);
  // let mut h = 0; if C { h = A[k] }; while C' { .. }
  let tif = mk(S_IF); nd[tif].a = clone_expr(cnd); nd[tif].b = mk_assign(h, ld); nd[tif].c = -1; nd[tif].next = w2;
  let lt = mk(S_LET); nd[lt].var = h; nd[lt].a = mkconst_t(0, nd[L].ty); nd[lt].next = tif;
  if ab < 0 { set_block(w, lt, nd[w].next); return; }
  let w1 = mk(S_WHILE); copy_node(w1, w); nd[w1].next = -1;
  let hb = mk(S_BLOCK); set_block(hb, lt, -1);
  let sel = mk(S_IF); nd[sel].a = ab; nd[sel].b = w1; nd[sel].c = hb; nd[sel].pos = nd[w].pos;
  set_block(w, sel, nd[w].next);
}
fn lh_inner(s: i64) -> bool {   // s contains no loop
  if s < 0 { return true; }
  let k = nd[s].k;
  if k == S_WHILE || k == S_INL || k == S_PAR { return false; }
  if k == S_BLOCK { let mut c = nd[s].a; while c >= 0 { if !lh_inner(c) { return false; } c = nd[c].next; } return true; }
  if k == S_IF { return lh_inner(nd[s].b) && lh_inner(nd[s].c); }
  return true;
}
fn lh_walk(s: i64) {
  if s < 0 { return; }
  let k = nd[s].k;
  if k == S_BLOCK || k == S_INL { let mut c = nd[s].a; while c >= 0 { let nx = nd[c].next; lh_walk(c); c = nx; } return; }
  if k == S_IF { lh_walk(nd[s].b); lh_walk(nd[s].c); return; }
  if k == S_WHILE { if lh_inner(nd[s].b) { lh_loop(s); } else { lh_walk(nd[s].b); } return; }
}
// ---- bounds versioning: `while i < E { ..; i += 1 }` (i changed only by that last statement, E
// invariant) runs a copy without the bounds checks of its a[i + k] accesses when, before the loop,
// i + k >= 0 and E + k <= len(a) (E + k < len(a) for <=) hold for each of them: every such access
// sees i0 <= i < E (<= E), so it cannot fail. Otherwise the checked original runs and traps as before.
let vpre = alloc<bool>(1048576);   // access proven by a versioning guard
let BV_A = alloc<i64>(64);
let BV_K = alloc<i64>(64);
let mut BV_N: i64 = 0;
let mut BV_I: i64 = -1;
let mut BV_BAD: bool = false;
let mut BV_HARD: bool = false;
let mut BV_E: i64 = -1;
let mut BV_LE: bool = false;
// an index i + X + k: X up to two loop-invariant i64 variables (BV_LV), k a small constant
let mut BV_W: i64 = -1;
// induction variables: conjuncts v < E (v <= E) of the loop test; each grows only by one v += 1
let BV_IV = alloc<i64>(4);
let BV_IE = alloc<i64>(4);
let BV_ILE = alloc<bool>(4);
let BV_INC = alloc<bool>(4);   // walking the body: v's increment already passed
let mut BV_NIV: i64 = 0;
let mut BV_NIV0: i64 = 0;   // test variables come first; counters after
let mut BV_WHICH: i64 = 0;
let BV_AI = alloc<i64>(64);    // access -> its induction variable
let BV_LV = alloc<i64>(2);
let mut BV_NLV: i64 = 0;
let mut BV_NI: i64 = 0;
let mut BV_LK: i64 = 0;
let mut BV_LOK: bool = true;
fn bv_lin(x: i64, neg: bool) {
  if !BV_LOK { return; }
  let k = nd[x].k;
  if k == N_CONST { let c = nd[x].v as i64; if c <= -1048576 || c >= 1048576 { BV_LOK = false; return; } if neg { BV_LK -= c; } else { BV_LK += c; } return; }
  if k == N_VAR {
    let v = nd[x].var;
    if neg || vars[v].ty != TY_I64 { BV_LOK = false; return; }
    let mut q = 0; while q < BV_NIV && BV_IV[q] != v { q += 1; }
    if q < BV_NIV { if BV_NI > 0 && BV_WHICH != q { BV_LOK = false; return; } BV_NI += 1; BV_WHICH = q; return; }
    if count_assign(BV_W, v) != 0 || BV_NLV >= 2 { BV_LOK = false; return; }
    BV_LV[BV_NLV] = v; BV_NLV += 1; return;
  }
  if k == N_BIN && nd[x].ty == TY_I64 && nd[x].op == O_ADD { bv_lin(nd[x].a, neg); bv_lin(nd[x].b, neg); return; }
  if k == N_BIN && nd[x].ty == TY_I64 && nd[x].op == O_SUB { bv_lin(nd[x].a, neg); bv_lin(nd[x].b, !neg); return; }
  BV_LOK = false;
}
fn bv_off(x: i64) -> bool {   // x is i + X + k: sets BV_LV/BV_NLV (sorted) and BV_LK
  BV_NLV = 0; BV_NI = 0; BV_LK = 0; BV_LOK = true;
  bv_lin(x, false);
  if !BV_LOK || BV_NI != 1 || BV_LK <= -1048576 || BV_LK >= 1048576 { return false; }
  if BV_NLV == 2 && BV_LV[0] > BV_LV[1] { let t = BV_LV[0]; BV_LV[0] = BV_LV[1]; BV_LV[1] = t; }
  return true;
}
let BV_X1 = alloc<i64>(64);
let BV_X2 = alloc<i64>(64);
fn bv_acc(a: i64, x: i64, node: i64, mark: bool) {
  if !bv_off(x) { return; }
  let q = BV_WHICH;
  if BV_INC[q] { return; }   // after the increment in this iteration: the test no longer bounds it
  BV_E = BV_IE[q]; BV_LE = BV_ILE[q];
  let k = BV_LK;
  let mut x1 = -1; let mut x2 = -1;
  if BV_NLV > 0 { x1 = BV_LV[0]; } if BV_NLV > 1 { x2 = BV_LV[1]; }
  if mark { vpre[node] = true; return; }
  let mut i = 0;
  while i < BV_N && !(BV_A[i] == a && BV_K[i] == k && BV_X1[i] == x1 && BV_X2[i] == x2 && BV_AI[i] == q) { i += 1; }
  if i == BV_N { if BV_N >= 64 { BV_BAD = true; return; } BV_A[i] = a; BV_K[i] = k; BV_X1[i] = x1; BV_X2[i] = x2; BV_AI[i] = q; BV_N += 1; }
  let mut easy = false;   // the range analysis proves these itself: E is len(a) (or a copy of it), or a constant in range
  if q >= BV_NIV0 { BV_HARD = true; return; }   // counters are bounded by the trip count only
  if x1 < 0 && k >= 0 && is_const(BV_E) && vars[a].lenv < 0 { let mut last = nd[BV_E].v as i64; if !BV_LE { last -= 1; } easy = last + k < vars[a].alen; }
  if x1 < 0 && k == 0 && !BV_LE && nd[BV_E].k == N_VAR && vars[a].lenv >= 0 {
    let ev = nd[BV_E].var;
    easy = ev == vars[a].lenv || (vars[ev].lenof > 0 && vars[vars[ev].lenof - 1].lenv == vars[a].lenv);
  }
  if !easy { BV_HARD = true; }
}
fn bv_e(e: i64, mark: bool) {
  if e < 0 { return; }
  let k = nd[e].k;
  if k == N_CONST || k == N_VAR || k == N_ARR || k == N_NCPU { return; }
  if k == N_CALL { BV_BAD = true; return; }   // a call dominates the loop's cost; not worth a copy
  if k == N_LOAD { bv_e(nd[e].a, mark); bv_acc(nd[e].var, nd[e].a, e, mark); return; }
  bv_e(nd[e].a, mark); bv_e(nd[e].b, mark);
}
fn bv_s(s: i64, mark: bool) {
  if s < 0 { return; }
  let k = nd[s].k;
  if k == S_BLOCK || k == S_INL { let mut c = nd[s].a; while c >= 0 { bv_s(c, mark); c = nd[c].next; } return; }
  if k == S_ARR || k == S_PAR { BV_BAD = true; return; }
  if k == S_IF { bv_e(nd[s].a, mark); bv_s(nd[s].b, mark); bv_s(nd[s].c, mark); return; }
  if k == S_WHILE { bv_e(nd[s].a, mark); bv_s(nd[s].b, mark); return; }
  if k == S_STORE { bv_e(nd[s].a, mark); bv_e(nd[s].b, mark); bv_acc(nd[s].var, nd[s].a, s, mark); return; }
  if k == S_WRITE || k == S_SAVE { BV_BAD = true; return; }
  if k == S_ASSIGN { bv_e(nd[s].a, mark); let mut q = 0; while q < BV_NIV { if nd[s].var == BV_IV[q] { BV_INC[q] = true; } q += 1; } return; }
  bv_e(nd[s].a, mark); bv_e(nd[s].b, mark);
}
fn bv_len(a: i64) -> i64 {
  if vars[a].lenv >= 0 { return mk_var(vars[a].lenv); }
  return mkconst_t(vars[a].alen as u64, TY_I64);
}
fn bv_bound(e: i64) -> i64 {   // -2^40 <= e && e <= 2^40
  let a = mk_bin(O_GE, e, mkconst_t((0 - 1099511627776) as u64, TY_I64)); nd[a].ty = TY_BOOL;
  let b = mk_bin(O_LE, clone_expr(e), mkconst_t(1099511627776, TY_I64)); nd[b].ty = TY_BOOL;
  let o = mk_bin(O_LAND, a, b); nd[o].ty = TY_BOOL; return o;
}
fn bv_sum(e0: i64, x1: i64, x2: i64, k: i64) -> i64 {
  let mut e = e0;
  if x1 >= 0 { e = mk_bin(O_ADD, e, mk_var(x1)); nd[e].ty = TY_I64; }
  if x2 >= 0 { e = mk_bin(O_ADD, e, mk_var(x2)); nd[e].ty = TY_I64; }
  if k != 0 { e = mk_bin(O_ADD, e, mkconst_t(k as u64, TY_I64)); nd[e].ty = TY_I64; }
  return e;
}
fn bv_and(g: i64, c: i64) -> i64 { if g < 0 { return c; } let o = mk_bin(O_LAND, g, c); nd[o].ty = TY_BOOL; return o; }
fn bv_conj(c: i64, w: i64) {   // induction-variable conjuncts of the loop test
  if nd[c].k == N_BIN && nd[c].op == O_LAND { bv_conj(nd[c].a, w); bv_conj(nd[c].b, w); return; }
  if nd[c].k != N_BIN || (nd[c].op != O_LT && nd[c].op != O_LE) || nd[nd[c].a].k != N_VAR || BV_NIV >= 4 { return; }
  let v = nd[nd[c].a].var; let E = nd[c].b;
  if vars[v].ty != TY_I64 || nd[E].ty != TY_I64 || !invariant(E, w) || has_call(E) || has_trap(E) || count_assign(w, v) != 1 || !bv_has_inc(nd[w].b, v) { return; }
  let mut q = 0; while q < BV_NIV { if BV_IV[q] == v { return; } q += 1; }
  BV_IV[BV_NIV] = v; BV_IE[BV_NIV] = E; BV_ILE[BV_NIV] = nd[c].op == O_LE; BV_NIV += 1;
}
fn bv_progress(c0: i64) -> bool {   // every path through these statements increments a test variable
  let mut c = c0;
  while c >= 0 {
    let k = nd[c].k;
    if k == S_ASSIGN { let mut q = 0; while q < BV_NIV0 { if nd[c].var == BV_IV[q] { return true; } q += 1; } }
    if k == S_BLOCK && bv_progress(nd[c].a) { return true; }
    if k == S_IF && nd[c].c >= 0 && bv_progress1(nd[c].b) && bv_progress1(nd[c].c) { return true; }
    if k == S_BRK || k == S_CONT || k == S_RET || k == S_IRET { return false; }
    if k == S_IF && (bv_jumps(nd[c].b) || bv_jumps(nd[c].c)) { return false; }
    c = nd[c].next;
  }
  return false;
}
fn bv_progress1(s: i64) -> bool { if nd[s].k == S_BLOCK { return bv_progress(nd[s].a); } let sv = nd[s].next; nd[s].next = -1; let r = bv_progress(s); nd[s].next = sv; return r; }
fn bv_jumps(s: i64) -> bool { return s >= 0 && has_jump0(s, 0); }
fn bv_trip(lim: bool) -> i64 {   // sum over test variables of E - v (+ 1 for <=): an iteration bound
  let mut e = -1; let mut q = 0;
  while q < BV_NIV0 {
    let mut t = mk_bin(O_SUB, clone_expr(BV_IE[q]), mk_var(BV_IV[q])); nd[t].ty = TY_I64;
    if BV_ILE[q] { t = mk_bin(O_ADD, t, mkconst_t(1, TY_I64)); nd[t].ty = TY_I64; }
    if e < 0 { e = t; } else { e = mk_bin(O_ADD, e, t); nd[e].ty = TY_I64; }
    q += 1;
  }
  return e;
}
fn bv_has_inc(s: i64, v: i64) -> bool {   // the one assignment of v in s is v += 1
  if s < 0 { return false; }
  let k = nd[s].k;
  if k == S_ASSIGN { return nd[s].var == v && is_inc1(s, v); }
  if k == S_BLOCK || k == S_INL { let mut c = nd[s].a; while c >= 0 { if bv_has_inc(c, v) { return true; } c = nd[c].next; } return false; }
  if k == S_IF { return bv_has_inc(nd[s].b, v) || bv_has_inc(nd[s].c, v); }
  return false;
}
fn bv_loop(w: i64) {
  let cnd = nd[w].a; let body = nd[w].b;
  if nd[w].c >= 0 || body < 0 || nd[body].k != S_BLOCK || has_call(cnd) || stmt_size(body) > 80 { return; }
  BV_W = w; BV_NIV = 0;
  bv_conj(cnd, w);
  if BV_NIV == 0 { return; }
  // counters: a top-level v += 1 (v changed nowhere else) when every path of the body increments
  // a test variable: at most sum(E - v0) iterations run, so v < v0 + sum(E - v0)
  BV_NIV0 = BV_NIV;
  if bv_progress(nd[body].a) {
    let mut c = nd[body].a;
    while c >= 0 && BV_NIV < 4 {
      if nd[c].k == S_ASSIGN && is_inc1(c, nd[c].var) && vars[nd[c].var].ty == TY_I64 && count_assign(w, nd[c].var) == 1 {
        let v = nd[c].var; let mut q = 0; while q < BV_NIV && BV_IV[q] != v { q += 1; }
        if q == BV_NIV { BV_IV[BV_NIV] = v; BV_IE[BV_NIV] = -1; BV_ILE[BV_NIV] = false; BV_NIV += 1; }
      }
      c = nd[c].next;
    }
  }
  BV_N = 0; BV_BAD = false; BV_HARD = false;
  let mut q = 0; while q < BV_NIV { BV_INC[q] = false; q += 1; }
  bv_s(body, false);
  if BV_BAD || !BV_HARD || BV_N == 0 { return; }
  // guard: for each (a, X, k): i + X + k >= 0 && E + X + k <= len(a) (+ 1 for <=). With variable
  // offsets every term is first bounded to +-2^40 (&& evaluates them first), so no sum can wrap.
  let mut g = -1; let mut i = 0;
  q = 0;
  while q < BV_NIV {
    let iv = BV_IV[q]; let E = BV_IE[q];
    let mut kmin = 1048576; let mut anyx = false; let mut used = false;
    i = 0;
    while i < BV_N { if BV_AI[i] == q { used = true; if BV_X1[i] < 0 && BV_K[i] < kmin { kmin = BV_K[i]; } if BV_X1[i] >= 0 { anyx = true; } } i += 1; }
    if q >= BV_NIV0 && used {   // counter: its bound sums every test variable's E - v0
      g = bv_and(g, bv_bound(mk_var(iv)));
      let mut r = 0; while r < BV_NIV0 { g = bv_and(g, bv_bound(mk_var(BV_IV[r]))); g = bv_and(g, bv_bound(clone_expr(BV_IE[r]))); r += 1; }
    }
    if anyx {
      g = bv_and(g, bv_bound(mk_var(iv)));
      if E >= 0 { g = bv_and(g, bv_bound(clone_expr(E))); }
      i = 0;
      while i < BV_N {
        if BV_AI[i] == q && BV_X1[i] >= 0 { g = bv_and(g, bv_bound(mk_var(BV_X1[i]))); }
        if BV_AI[i] == q && BV_X2[i] >= 0 { g = bv_and(g, bv_bound(mk_var(BV_X2[i]))); }
        i += 1;
      }
    }
    // the smallest index i0 + kmin of the constant-offset accesses must be >= 0 (also for kmin >= 0)
    if kmin < 1048576 { let c = mk_bin(O_GE, mk_var(iv), mkconst_t((0 - kmin) as u64, TY_I64)); nd[c].ty = TY_BOOL; g = bv_and(g, c); }
    q += 1;
  }
  i = 0;
  while i < BV_N {
    let iv = BV_IV[BV_AI[i]]; let mut E = BV_IE[BV_AI[i]];
    if E < 0 { E = mk_bin(O_ADD, mk_var(iv), bv_trip(false)); nd[E].ty = TY_I64; }   // counter: v0 + trip
    let mut d = BV_K[i]; if BV_ILE[BV_AI[i]] { d += 1; }
    if BV_X1[i] < 0 {
      let mut r = bv_len(BV_A[i]);
      if d != 0 { r = mk_bin(O_SUB, r, mkconst_t(d as u64, TY_I64)); nd[r].ty = TY_I64; }
      let c = mk_bin(O_LE, clone_expr(E), r); nd[c].ty = TY_BOOL;
      g = bv_and(g, c);
    } else {
      let lo = bv_sum(mk_var(iv), BV_X1[i], BV_X2[i], BV_K[i]);
      let c1 = mk_bin(O_GE, lo, mkconst_t(0, TY_I64)); nd[c1].ty = TY_BOOL; g = bv_and(g, c1);
      let hi = bv_sum(clone_expr(E), BV_X1[i], BV_X2[i], d);
      let c2 = mk_bin(O_LE, hi, bv_len(BV_A[i])); nd[c2].ty = TY_BOOL; g = bv_and(g, c2);
    }
    i += 1;
  }
  // if g { w (unchecked accesses) } else { checked copy }
  igen += 1;
  let nv0 = nv;
  let cl = clone_stmt_inl(w, -2);
  let mut v = nv0; while v < nv { vars[v].owner = CS_F; v += 1; }
  v = 0;   // the copies of lets keep the facts known about the originals
  while v < nv0 {
    if imap_gen[v] == igen && imap[v] >= nv0 { let c = imap[v]; vars[c].isconst = vars[v].isconst; vars[c].cval = vars[v].cval; vars[c].lenof = vars[v].lenof; }
    v += 1;
  }
  q = 0; while q < BV_NIV { BV_INC[q] = false; q += 1; }
  bv_s(body, true);
  let w1 = mk(S_WHILE); copy_node(w1, w); nd[w1].next = -1;
  nd[cl].next = -1;
  let sel = mk(S_IF); nd[sel].a = g; nd[sel].b = w1; nd[sel].c = cl; nd[sel].pos = nd[w].pos;
  set_block(w, sel, nd[w].next);
  if BV_NV < 4096 { BV_SEL[BV_NV] = w; BV_NV += 1; bv_sel[sel] = true; }
}
// after the range analysis: a versioned loop whose checked copy needs no check keeps only that copy
let BV_SEL = alloc<i64>(4096);
let bv_sel = alloc<bool>(1048576);     // the if of a versioned loop
let bv_alive = alloc<bool>(1048576);   // the analysis reached its checked branch
let mut BV_NV: i64 = 0;
fn bv_chk_e(e: i64) -> bool {   // a load in e keeps a bounds check
  if e < 0 { return false; }
  let k = nd[e].k;
  if k == N_CONST || k == N_VAR || k == N_ARR || k == N_NCPU { return false; }
  if k == N_CALL { let mut a = nd[e].a; while a >= 0 { if bv_chk_e(a) { return true; } a = nd[a].next; } return false; }
  if k == N_LOAD && nd[e].chk != 0 { return true; }
  return bv_chk_e(nd[e].a) || bv_chk_e(nd[e].b);
}
fn bv_chk_s(s: i64) -> bool {
  if s < 0 { return false; }
  let k = nd[s].k;
  if k == S_BLOCK || k == S_INL { let mut c = nd[s].a; while c >= 0 { if bv_chk_s(c) { return true; } c = nd[c].next; } return false; }
  if k == S_IF { return bv_chk_e(nd[s].a) || bv_chk_s(nd[s].b) || bv_chk_s(nd[s].c); }
  if k == S_WHILE { return bv_chk_e(nd[s].a) || bv_chk_s(nd[s].b); }
  if k == S_STORE && nd[s].chk != 0 { return true; }
  return bv_chk_e(nd[s].a) || bv_chk_e(nd[s].b);
}
fn bv_prune() {
  let mut i = 0;
  while i < BV_NV {
    let b = BV_SEL[i]; let sel = nd[b].a;
    if nd[b].k == S_BLOCK && sel >= 0 && nd[sel].k == S_IF {
      if !bv_alive[sel] { nd[b].a = nd[sel].b; }   // the guard always holds
      else if !bv_chk_s(nd[sel].c) { nd[b].a = nd[sel].c; }   // the checked copy needs no check
    }
    i += 1;
  }
}
fn bv_walk(s: i64) {
  if s < 0 { return; }
  let k = nd[s].k;
  if k == S_BLOCK || k == S_INL { let mut c = nd[s].a; while c >= 0 { let nx = nd[c].next; bv_walk(c); c = nx; } return; }
  if k == S_IF { bv_walk(nd[s].b); bv_walk(nd[s].c); return; }
  if k == S_WHILE { if lh_inner(nd[s].b) { bv_loop(s); } else { bv_walk(nd[s].b); } return; }
}
// ---- `let v = g; g += c` (g a global scalar, a one-element static array): the update reads v
// instead of loading g again (nothing runs between the two)
fn gi_g0(e: i64) -> bool { return nd[e].k == N_LOAD && gsc[nd[e].var] && is_const(nd[e].a) && nd[nd[e].a].v == 0 && nd[e].op <= 0; }
fn gi_walk(s: i64) {
  if s < 0 { return; }
  let k = nd[s].k;
  if k == S_BLOCK || k == S_INL {
    let mut c = nd[s].a;
    while c >= 0 {
      let x0 = nd[c].next;
      let mut x = x0;
      if x >= 0 && nd[x].k == S_BLOCK && nd[x].a >= 0 && nd[nd[x].a].next < 0 { x = nd[x].a; }
      if x >= 0 && nd[c].k == S_LET && gi_g0(nd[c].a) && nd[x].k == S_STORE && nd[x].c < 0 && nd[x].var == nd[nd[c].a].var && is_const(nd[x].a) && nd[nd[x].a].v == 0 {
        let e = nd[x].b; let v = nd[c].var; let g = nd[x].var;
        if nd[x].op < 0 && nd[e].k == N_BIN && (nd[e].op == O_ADD || nd[e].op == O_SUB) && gi_g0(nd[e].a) && nd[nd[e].a].var == g && is_const(nd[e].b) && vars[v].ty == nd[nd[e].a].ty {
          let ld = nd[e].a; let ty = nd[ld].ty;
          nd[ld].k = N_VAR; nd[ld].var = v; nd[ld].a = -1; nd[ld].op = 0; nd[ld].ty = ty; vars[v].reads += 1;
        }
        else if (nd[x].op == O_ADD || nd[x].op == O_SUB) && is_const(e) && vars[v].ty == vars[g].et && ty_int(vars[g].et) {   // g[0] += c
          let b = mk_bin(nd[x].op, mk_var(v), e); nd[b].ty = vars[g].et;
          nd[x].b = b; nd[x].op = -1;
        }
      }
      gi_walk(c); c = x0;
    }
    return;
  }
  if k == S_IF { gi_walk(nd[s].b); gi_walk(nd[s].c); return; }
  if k == S_WHILE { gi_walk(nd[s].b); return; }
}
// ---- short search loops: `c = c0; while c < K && C(c) { c += 1 }` with constants c0 < K,
// K - c0 <= 16 and C free of calls becomes `if C(c0) { c = c0 + 1; if C(c0 + 1) { .. c = K } }`:
// the same tests in the same order (so the same traps), with constant indices and no back jump
fn su_try(p: i64, w: i64) -> bool {
  if nd[w].k != S_WHILE || nd[w].c >= 0 { return false; }
  if !((nd[p].k == S_LET || nd[p].k == S_ASSIGN) && is_const(nd[p].a)) { return false; }
  let c = nd[p].var; let c0 = nd[nd[p].a].v as i64;
  let cnd = nd[w].a;
  if nd[cnd].k != N_BIN || nd[cnd].op != O_LAND { return false; }
  let lim = nd[cnd].a; let C = nd[cnd].b;
  if nd[lim].k != N_BIN || nd[lim].op != O_LT || nd[nd[lim].a].k != N_VAR || nd[nd[lim].a].var != c || !cfold_ok(nd[lim].b) || vars[c].ty != TY_I64 { return false; }
  let K = cfold(nd[lim].b);
  if c0 < 0 || K <= c0 || K - c0 > 16 || has_call(C) || stmt_size(C) > 12 { return false; }
  let mut b = nd[w].b; if nd[b].k == S_BLOCK { b = nd[b].a; if b < 0 || nd[b].next >= 0 { return false; } }
  if !is_inc1(b, c) { return false; }
  // build from the innermost level out
  let mut inner = mk_assign(c, mkconst_t(K as u64, TY_I64));
  let mut k = K - 1;
  while k >= c0 {
    let ck = clone_expr(C); sm_subst(ck, c, k);
    let f = mk(S_IF); nd[f].a = ck; nd[f].c = -1;
    if k == K - 1 { nd[f].b = inner; }
    else { let as1 = mk_assign(c, mkconst_t((k + 1) as u64, TY_I64)); nd[as1].next = inner; let blk = mk(S_BLOCK); set_block(blk, as1, -1); nd[f].b = blk; }
    inner = f; k -= 1;
  }
  set_block(w, inner, nd[w].next);
  return true;
}
fn su_walk(s: i64) {
  if s < 0 { return; }
  let k = nd[s].k;
  if k == S_BLOCK || k == S_INL {
    let mut p = -1; let mut c = nd[s].a;
    while c >= 0 { let nx = nd[c].next; if !(p >= 0 && su_try(p, c)) { su_walk(c); } p = c; c = nx; }
    return;
  }
  if k == S_IF { su_walk(nd[s].b); su_walk(nd[s].c); return; }
  if k == S_WHILE { su_walk(nd[s].b); return; }
}
// ---- flags: `let mut v = 0; if C { v = 1 }` becomes `let v = C` (a 0/1 value from setcc)
fn bi_one(b: i64, v: i64) -> bool {
  let mut x = b; if nd[x].k == S_BLOCK { x = nd[x].a; if x < 0 || nd[x].next >= 0 { return false; } }
  return nd[x].k == S_ASSIGN && nd[x].var == v && is_const(nd[x].a) && nd[nd[x].a].v == 1;
}
fn bi_walk(s: i64) {
  if s < 0 { return; }
  let k = nd[s].k;
  if k == S_BLOCK || k == S_INL {
    let mut c = nd[s].a;
    while c >= 0 {
      let x = nd[c].next;
      if x >= 0 && nd[c].k == S_LET && is_const(nd[c].a) && nd[nd[c].a].v == 0 && ty_int(vars[nd[c].var].ty) && nd[x].k == S_IF && nd[x].c < 0 {
        let v = nd[c].var; let C = nd[x].a;
        if nd[C].ty == TY_BOOL && !has_call(C) && !refs(C, v) && bi_one(nd[x].b, v) {
          nd[C].ty = vars[v].ty; nd[c].a = C; set_block(x, -1, nd[x].next);
        }
      }
      bi_walk(c); c = x;
    }
    return;
  }
  if k == S_IF { bi_walk(nd[s].b); bi_walk(nd[s].c); return; }
  if k == S_WHILE { bi_walk(nd[s].b); return; }
}
// ---- rotations: `let t = E; a = b; b = t` (t read only there) becomes `let s = b; b = E; a = s`:
// E still sees the old a and b, and the copy of b moves off the E -> b dependency (Euclid's loop)
fn sw_walk(s: i64) {
  if s < 0 { return; }
  let k = nd[s].k;
  if k == S_BLOCK || k == S_INL {
    let mut c = nd[s].a;
    while c >= 0 {
      let x = nd[c].next;
      if x >= 0 && nd[x].next >= 0 && nd[c].k == S_LET && nd[x].k == S_ASSIGN && nd[nd[x].next].k == S_ASSIGN {
        let y = nd[x].next;
        let t = nd[c].var; let a = nd[x].var; let e1 = nd[x].a; let e2 = nd[y].a;
        if nd[e1].k == N_VAR && nd[e2].k == N_VAR && nd[e2].var == t && nd[y].var == nd[e1].var && a != nd[e1].var && a != t
           && vars[t].reads == 1 && vars[t].ty == vars[nd[y].var].ty && vars[a].ty == vars[nd[y].var].ty && ty_int(vars[a].ty) {
          let b = nd[y].var; let E = nd[c].a;
          let sv = hidden(); vars[sv].ty = vars[b].ty; vars[sv].owner = CS_F;
          nd[c].var = sv; nd[c].a = mk_var(b);
          nd[x].var = b; nd[x].a = E;
          nd[y].var = a; nd[y].a = mk_var(sv);
          vars[t].reads = 0; vars[b].reads -= 1;
        }
      }
      sw_walk(c); c = x;
    }
    return;
  }
  if k == S_IF { sw_walk(nd[s].b); sw_walk(nd[s].c); return; }
  if k == S_WHILE { sw_walk(nd[s].b); return; }
}
// ---- loop copies of invariant scalars: before an innermost loop, each scalar it reads but never
// assigns is copied into a variable used only inside the loop. The copy's live range is the loop,
// so the allocator keeps it in a register there and spills the long-lived original instead.
let LS_V = alloc<i64>(16);
let LS_C = alloc<i64>(16);
let mut LS_N: i64 = 0;
let ls_len = alloc<bool>(65536);   // array length variables (bounds proofs need the original)
fn ls_note(e: i64, w: i64) {
  if e < 0 { return; }
  let k = nd[e].k;
  if k == N_VAR {
    let v = nd[e].var;
    if LS_N < 16 && vars[v].glob == 0 && vars[v].arr == 0 && vars[v].isconst == 0 && !ls_len[v] && (ty_int(vars[v].ty) || vars[v].ty == TY_F64) && count_assign(w, v) == 0 {
      let mut i = 0; while i < LS_N && LS_V[i] != v { i += 1; }
      if i == LS_N { LS_V[i] = v; LS_N += 1; }
    }
    return;
  }
  if k == N_CONST || k == N_ARR || k == N_NCPU { return; }
  if k == N_CALL { let mut a = nd[e].a; while a >= 0 { ls_note(a, w); a = nd[a].next; } return; }
  ls_note(nd[e].a, w); ls_note(nd[e].b, w);
}
fn ls_note_s(s: i64, w: i64) {
  if s < 0 { return; }
  let k = nd[s].k;
  if k == S_BLOCK || k == S_INL { let mut c = nd[s].a; while c >= 0 { ls_note_s(c, w); c = nd[c].next; } return; }
  if k == S_IF { ls_note(nd[s].a, w); ls_note_s(nd[s].b, w); ls_note_s(nd[s].c, w); return; }
  if k == S_WHILE { ls_note(nd[s].a, w); ls_note_s(nd[s].b, w); return; }
  ls_note(nd[s].a, w); ls_note(nd[s].b, w);
}
fn ls_sub(e: i64) {
  if e < 0 { return; }
  let k = nd[e].k;
  if k == N_VAR { let mut i = 0; while i < LS_N { if nd[e].var == LS_V[i] { nd[e].var = LS_C[i]; vars[LS_V[i]].reads -= 1; vars[LS_C[i]].reads += 1; return; } i += 1; } return; }
  if k == N_CONST || k == N_ARR || k == N_NCPU { return; }
  if k == N_CALL { let mut a = nd[e].a; while a >= 0 { ls_sub(a); a = nd[a].next; } return; }
  ls_sub(nd[e].a); ls_sub(nd[e].b);
}
fn ls_sub_s(s: i64) {
  if s < 0 { return; }
  let k = nd[s].k;
  if k == S_BLOCK || k == S_INL { let mut c = nd[s].a; while c >= 0 { ls_sub_s(c); c = nd[c].next; } return; }
  if k == S_IF { ls_sub(nd[s].a); ls_sub_s(nd[s].b); ls_sub_s(nd[s].c); return; }
  if k == S_WHILE { ls_sub(nd[s].a); ls_sub_s(nd[s].b); return; }
  ls_sub(nd[s].a); ls_sub(nd[s].b);
}
fn ls_loop(w: i64) {
  LS_N = 0;
  ls_note(nd[w].a, w); ls_note_s(nd[w].b, w);
  if LS_N == 0 { return; }
  let mut head = -1; let mut prev = -1; let mut i = 0;
  while i < LS_N {
    let v = LS_V[i];
    let c = hidden(); vars[c].ty = vars[v].ty; vars[c].owner = CS_F; LS_C[i] = c;
    let l = mk(S_LET); nd[l].var = c; nd[l].a = mk_var(v);
    if prev < 0 { head = l; } else { nd[prev].next = l; }
    prev = l; i += 1;
  }
  ls_sub(nd[w].a); ls_sub_s(nd[w].b);
  let w2 = mk(S_WHILE); copy_node(w2, w); nd[w2].next = -1; nd[prev].next = w2;
  set_block(w, head, nd[w].next);
}
fn ls_walk(s: i64) {
  if s < 0 { return; }
  let k = nd[s].k;
  if k == S_BLOCK || k == S_INL { let mut c = nd[s].a; while c >= 0 { let nx = nd[c].next; ls_walk(c); c = nx; } return; }
  if k == S_IF { ls_walk(nd[s].b); ls_walk(nd[s].c); return; }
  if k == S_WHILE { if lh_inner(nd[s].b) { ls_loop(s); } else { ls_walk(nd[s].b); } return; }
}
fn ls_mark_lens() { let mut v = 0; while v < nv { ls_len[v] = false; v += 1; } v = 0; while v < nv { if vars[v].arr != 0 && vars[v].lenv >= 0 { ls_len[vars[v].lenv] = true; } v += 1; } }
fn cs_walk(s: i64) {
  if s < 0 { return; }
  let k = nd[s].k;
  if k == S_BLOCK || k == S_INL { let mut c = nd[s].a; while c >= 0 { let nx = nd[c].next; cs_walk(c); c = nx; } return; }
  if k == S_IF { cs_walk(nd[s].b); cs_walk(nd[s].c); return; }
  if k == S_WHILE { cs_walk(nd[s].b); cs_loop(s); return; }
}
fn allocate() {
  let mut g = 0;
  while g < nfn { if !starts2u(fns[g].noff, fns[g].nlen) { tre_fn(g); } g += 1; }
  g = 0;
  while g < nfn { fn_nr[g] = noreturn(g, 0); g += 1; }
  inline_calls();
  g = 0;
  while g < nfn { if !starts2u(fns[g].noff, fns[g].nlen) { lift_calls(fns[g].body); } g += 1; }
  make_templates();
  if nfn > 1 { inl_growth = 0; rec_growth = 0; inline_stmts(fns[mainfn].body); }
  let mut f = 0;
  while f < nfn { if f != mainfn { inl_growth = 0; rec_growth = 0; inline_stmts(fns[f].body); } f += 1; }
  inline_calls();
  mark_used();
  simplify();
  f = 0;
  while f < nfn { if fns[f].used != 0 { CS_F = f; gi_walk(fns[f].body); bi_walk(fns[f].body); sw_walk(fns[f].body); sm_walk(fns[f].body); su_walk(fns[f].body); ss_walk(fns[f].body, false); cs_walk(fns[f].body); lh_walk(fns[f].body); bv_walk(fns[f].body); mm_walk(fns[f].body, false); dm_walk(fns[f].body); } f += 1; }
  let mut v = 0;
  while v < nv { if vars[v].owner >= 0 && fns[vars[v].owner].used == 0 { vars[v].reads = 0; } v += 1; }
  analyze();
  bv_prune();
  strength_reduce();
  v = 0;
  while v < nv { chint[v] = -1; v += 1; }
  f = 0;
  while f < nfn {
    if fns[f].used != 0 {
      fpc_lo[f] = pc;
      pc += 1;
      let mut i = 0;
      while i < fns[f].np {
        let pv = fpvar[f * 16 + i];
        let mut id0 = pv; let mut id1 = -1;
        if fpw[f * 16 + i] != 0 { id0 = vars[pv].basev; id1 = vars[pv].lenv; }
        if id0 >= 0 && vars[id0].reads != 0 { vars[id0].start = pc; vars[id0].end = pc; }
        if id1 >= 0 && vars[id1].reads != 0 { vars[id1].start = pc; vars[id1].end = pc; }
        i += 1;
      }
      let fm = fns[f].mark;
      if fm >= 0 { vars[fm].start = pc; vars[fm].end = pc; }
      // argc/argv are born when main starts, not at pc 0 (they would block registers in every function walked before main)
      if f == mainfn { if vars[0].reads != 0 { vars[0].start = pc; vars[0].end = pc; } if vars[1].reads != 0 { vars[1].start = pc; vars[1].end = pc; } }
      walk_stmt(fns[f].body);
      if fm >= 0 { pc += 1; touch(fm); }
      fpc_hi[f] = pc;
    }
    f += 1;
  }
  let mut i = 0;
  while i < npairs { if loop_end[pair_l[i]] > vars[pair_v[i]].end { vars[pair_v[i]].end = loop_end[pair_l[i]]; } i += 1; }
  v = 0;
  while v < nv { if vars[v].hoist != 0 { vars[v].end = loop_end[vars[v].hoist - 1]; } v += 1; }
  // an interval that ends at a loop's end is live across the back edge, not dead after its last statement
  v = 0;
  while v < nv { lext[v] = vars[v].hoist != 0; v += 1; }
  i = 0;
  while i < npairs { if loop_end[pair_l[i]] == vars[pair_v[i]].end { lext[pair_v[i]] = true; } i += 1; }
  let mut no = 0;
  let mut na = 0;
  v = 0;
  while v < nv { if vars[v].reads != 0 && vars[v].isconst == 0 { order[no] = v; no += 1; } v += 1; }
  sort_by_start(no);
  let freer = alloc<i64>(12);
  let mut nf = 12;
  i = 0;
  while i < 12 { freer[i] = allregs[i]; i += 1; }
  let xfree = alloc<i64>(8);
  let mut nxf = NXREG;
  let mut nxa = 0;
  i = 0;
  while i < NXREG { xfree[i] = XREG0 + NXREG - 1 - i; i += 1; }
  i = 0;
  while i < no {
    let vv = order[i];
    let mut j = 0;
    if is_xvar(vv) {
      while j < nxa {
        if vars[xactive[j]].end < vars[vv].start { xfree[nxf] = vars[xactive[j]].xr; nxf += 1; nxa -= 1; xactive[j] = xactive[nxa]; }
        else { j += 1; }
      }
      if nxa < NXREG { nxf -= 1; vars[vv].xr = xfree[nxf]; xactive[nxa] = vv; nxa += 1; }
      else {
        let mut vi = -1;
        j = 0;
        while j < nxa { if vi < 0 || cheaper(xactive[j], xactive[vi]) { vi = j; } j += 1; }
        if cheaper(vv, xactive[vi]) { if vars[vv].hoist == 0 { new_slot(vv); xspilled += 1; } }
        else {
          let old = xactive[vi];
          vars[vv].xr = vars[old].xr; vars[old].xr = -1;
          if vars[old].hoist == 0 { new_slot(old); xspilled += 1; }
          xactive[vi] = vv;
        }
      }
      if nxa > xpeak { xpeak = nxa; }
      i += 1;
      continue;
    }
    while j < na {
      if vars[active[j]].end < vars[vv].start { freer[nf] = vars[active[j]].reg; nf += 1; na -= 1; active[j] = active[na]; }
      else { j += 1; }
    }
    // `let v = h` where h dies right there: v takes over h's register and the copy disappears
    let h = chint[vv];
    let mut hj = -1;
    if h >= 0 && !is_xvar(h) && vars[h].reg >= 0 && vars[h].end == vars[vv].start && !lext[h] && (callee_saved(vars[h].reg) || !crosses_call(vv)) {
      j = 0;
      while j < na { if active[j] == h { hj = j; } j += 1; }
    }
    if hj >= 0 { vars[vv].reg = vars[h].reg; active[hj] = vv; }
    else if na < MAX_ACTIVE {
      // values live across a call prefer callee-saved registers, others caller-saved ones
      let want = crosses_call(vv);
      let mut pick = nf - 1;
      let mut q = nf - 1;
      while q >= 0 { if callee_saved(freer[q]) == want { pick = q; break; } q -= 1; }
      let tr = freer[pick]; freer[pick] = freer[nf - 1]; freer[nf - 1] = tr;
      nf -= 1; vars[vv].reg = freer[nf]; active[na] = vv; na += 1;
    }
    else {
      let mut vi = -1;
      j = 0;
      while j < na { if vi < 0 || cheaper(active[j], active[vi]) { vi = j; } j += 1; }
      if cheaper(vv, active[vi]) { if vars[vv].hoist == 0 { new_slot(vv); } }
      else {
        let old = active[vi];
        vars[vv].reg = vars[old].reg; vars[old].reg = -1;
        if vars[old].hoist == 0 { new_slot(old); }
        active[vi] = vv;
      }
    }
    if na > peak_active { peak_active = na; }
    i += 1;
  }
}
let busy = alloc<i64>(4194304);
let xbusy = alloc<i64>(4194304);   // xmm registers held by float variables, per pc
let busyd = alloc<i32>(4194305);   // per-register difference array, reused
let livem = alloc<i64>(4194304);   // general registers whose variable is still needed after the statement at this pc
let lived = alloc<i32>(4194305);
let mut busy_n: i64 = 0;
let mut busy_built: bool = false;
// register index: 0..11 general (allregs order), 12.. xmm8..xmm15
fn busy_reg_of(v: i64, i: i64) -> bool {
  if i >= 12 { return vars[v].xr == XREG0 + i - 12; }
  return vars[v].reg == allregs[i];
}
fn build_busy() {
  busy_n = pc + 2;
  if busy_n > 4194304 { fail("program too large"); }
  let mut i = 0;
  while i < 12 + NXREG {
    let mut p = 0;
    while p < busy_n { busyd[p] = 0; lived[p] = 0; p += 1; }
    let mut any = false;
    let mut v = 0;
    while v < nv {
      if vars[v].start <= vars[v].end && busy_reg_of(v, i) {
        let mut a = vars[v].start; if a < 0 { a = 0; }
        let mut b = vars[v].end + 1; if b > busy_n - 1 { b = busy_n - 1; }
        busyd[a] += 1; busyd[b] -= 1; any = true;
        if !lext[v] { b -= 1; }
        if a < b { lived[a] += 1; lived[b] -= 1; }
      }
      v += 1;
    }
    if any {
      let mut c = 0; let mut cl = 0;
      p = 0;
      while p < busy_n {
        c += busyd[p] as i64; cl += lived[p] as i64;
        if c > 0 { if i < 12 { busy[p] = busy[p] | (1 << i); } else { xbusy[p] = xbusy[p] | (1 << (i - 12)); } }
        if cl > 0 && i < 12 { livem[p] = livem[p] | (1 << i); }
        p += 1;
      }
    }
    i += 1;
  }
  busy_built = true;
}
let TMPS = alloc<i64>(12);   // temps_at result
fn temps_at(p: i64) -> i64 {
  let mut n = 0;
  if !busy_built { build_busy(); }
  let mut m = 0;
  if p >= 0 && p < busy_n { m = busy[p]; }
  let mut i = 0;
  while i < 12 { if ((m >> i) & 1) == 0 { TMPS[n] = allregs[i]; n += 1; } i += 1; }
  if n < 2 { fail("internal: fewer than two temporary registers"); }
  return n;
}
// ---------------------------------------------------------------- x86-64 encoder
let code = alloc<u8>(16777216);
let mut clen: i64 = 0;
fn nop_n(n0: i64) {   // n bytes of NOP instructions (multi-byte forms)
  let mut n = n0;
  while n > 0 {
    let k = n; 
    if k >= 9 { emh("660f1f840000000000"); n -= 9; }
    else if k == 8 { emh("0f1f840000000000"); n -= 8; }
    else if k == 7 { emh("0f1f8000000000"); n -= 7; }
    else if k == 6 { emh("660f1f440000"); n -= 6; }
    else if k == 5 { emh("0f1f440000"); n -= 5; }
    else if k == 4 { emh("0f1f4000"); n -= 4; }
    else if k == 3 { emh("0f1f00"); n -= 3; }
    else if k == 2 { emh("6690"); n -= 2; }
    else { byte(144); n -= 1; }
  }
}
fn byte(x: i64) { if clen >= MAX_BYTES { fail("generated code limit reached"); } code[clen] = x as u8; clen += 1; }
fn u32_(x: i64) { byte(x & 255); byte((x >> 8) & 255); byte((x >> 16) & 255); byte((x >> 24) & 255); }
fn u64_(x: u64) { let mut i: u64 = 0; while i < 8 { byte(((x >> (8 * i)) & 255) as i64); i += 1; } }
fn patch32(at: i64, v: i64) { code[at] = v as u8; code[at + 1] = (v >> 8) as u8; code[at + 2] = (v >> 16) as u8; code[at + 3] = (v >> 24) as u8; }
fn rel32(at: i64, target: i64) {
  let d = target - (at + 4);
  if d < -2147483648 || d > 2147483647 { fail("branch too far"); }
  patch32(at, d);
}
fn hexv(c: i64) -> i64 { if c >= 'a' { return c - 'a' + 10; } return c - '0'; }
fn emh(h: [u8]) { // emit bytes written as hex digits
  let mut i = 0;
  while i + 1 < len(h) { byte(hexv(h[i] as i64) * 16 + hexv(h[i + 1] as i64)); i += 2; }
}
let K_REG = 0; let K_MEM = 1; let K_IMM = 2; let K_XMM = 3; let K_XMMS = 4;   // XMM: f64 / f32 variable in an xmm register
fn is_xk(k: i64) -> bool { return k == K_XMM || k == K_XMMS; }
let mut OK: i64 = 0;     // operand "return value": kind, register/slot, immediate
let mut ORR: i64 = 0;
let mut OI: u64 = 0;
let mut sp_adj: i64 = 0;
fn enc(w: i64, force_rex: bool, nop: i64, o1: i64, o2: i64, regf: i64, rk: i64, rr: i64) {
  if rk > K_MEM { fail("internal: bad operand kind"); }
  let mut b = RSP; if rk == K_REG { b = rr; }
  let mut rex = 64;
  if w != 0 { rex = rex | 8; } if (regf & 8) != 0 { rex = rex | 4; } if (b & 8) != 0 { rex = rex | 1; }
  if rex != 64 || force_rex { byte(rex); }
  byte(o1); if nop == 2 { byte(o2); }
  if rk == K_REG { byte(192 | ((regf & 7) << 3) | (rr & 7)); return; }
  let d = rr * 8 + sp_adj;
  if d == 0 { byte(4 | ((regf & 7) << 3)); byte(36); }
  else if d < 128 { byte(68 | ((regf & 7) << 3)); byte(36); byte(d); }
  else { byte(132 | ((regf & 7) << 3)); byte(36); u32_(d); }
}
fn encr(w: i64, force_rex: bool, nop: i64, o1: i64, o2: i64, regf: i64, r: i64) { enc(w, force_rex, nop, o1, o2, regf, K_REG, r); }
fn mov_rr(d: i64, s: i64) { if d != s { encr(1, false, 1, 137, 0, s, d); } }
fn mov_ri(d: i64, v: u64) {
  if v == 0 { encr(0, false, 1, 49, 0, d, d); return; }
  if v <= 4294967295 { if (d & 8) != 0 { byte(65); } byte(184 | (d & 7)); u32_(v as i64); return; }
  if fits_s32(v) { encr(1, false, 1, 199, 0, 0, d); u32_(v as i64); return; }
  let mut rx = 72; if (d & 8) != 0 { rx = 73; }
  byte(rx); byte(184 | (d & 7)); u64_(v);
}
fn load(d: i64, sk: i64, sr: i64, si: u64) {
  if is_xk(sk) { sse(102, (sk == K_XMM) as i64, 126, sr, K_REG, d); return; }   // movq/movd gpr <- xmm
  if sk == K_REG { mov_rr(d, sr); }
  else if sk == K_MEM { enc(1, false, 1, 139, 0, d, K_MEM, sr); }
  else { mov_ri(d, si); }
}
fn store(dk: i64, dr: i64, s: i64) {
  if is_xk(dk) { sse(102, (dk == K_XMM) as i64, 110, dr, K_REG, s); return; }   // movq/movd xmm <- gpr
  if dk == K_REG { mov_rr(dr, s); } else { enc(1, false, 1, 137, 0, s, dk, dr); }
}
let A_ADD = 0; let A_OR = 1; let A_AND = 4; let A_SUB = 5; let A_XOR = 6; let A_CMP = 7;
fn alu(dig: i64, dk: i64, dr: i64, sk0: i64, sr0: i64, si: u64) {
  let mut sk = sk0; let mut sr = sr0;
  if dig == 7 && sk == K_IMM && si == 0 && dk == K_REG { encr(1, false, 1, 133, 0, dr, dr); return; }
  if sk == K_IMM {
    if !fits_s32(si) { let mut sc = RAX; if dk == K_REG && dr == RAX { sc = RDX; } mov_ri(sc, si); sk = K_REG; sr = sc; }
    else if fits_s8(si) { enc(1, false, 1, 131, 0, dig, dk, dr); byte((si & 255) as i64); return; }
    else { enc(1, false, 1, 129, 0, dig, dk, dr); u32_(si as i64); return; }
  }
  if sk == K_REG { enc(1, false, 1, dig * 8 + 1, 0, sr, dk, dr); }
  else { if dk != K_REG { fail("internal: mem-mem alu"); } enc(1, false, 1, dig * 8 + 3, 0, dr, sk, sr); }
}
fn alur(dig: i64, d: i64, s: i64) { alu(dig, K_REG, d, K_REG, s, 0); }
fn alui(dig: i64, d: i64, v: u64) { alu(dig, K_REG, d, K_IMM, 0, v); }
fn imul_r(d: i64, sk0: i64, sr0: i64, si: u64) {
  let mut sk = sk0; let mut sr = sr0;
  if sk == K_IMM {
    if fits_s8(si) { encr(1, false, 1, 107, 0, d, d); byte((si & 255) as i64); return; }
    if fits_s32(si) { encr(1, false, 1, 105, 0, d, d); u32_(si as i64); return; }
    let mut sc = RAX; if d == RAX { sc = RDX; }
    mov_ri(sc, si); sk = K_REG; sr = sc;
  }
  enc(1, false, 2, 15, 175, d, sk, sr);
}
fn shift_ri(dig: i64, d: i64, k0: i64) {
  let k = k0 & 63;
  if k == 0 { return; }
  if k == 1 { encr(1, false, 1, 209, 0, dig, d); } else { encr(1, false, 1, 193, 0, dig, d); byte(k); }
}
fn lea(d: i64, base: i64, index: i64, disp: i64) {
  let mut md = 2;
  if disp == 0 && (base & 7) != 5 { md = 0; } else if fits_s8(disp as u64) { md = 1; }
  let mut rx = 72;
  if (d & 8) != 0 { rx = rx | 4; } if index >= 0 && (index & 8) != 0 { rx = rx | 2; } if (base & 8) != 0 { rx = rx | 1; }
  byte(rx); byte(141);
  if index < 0 && (base & 7) != 4 { byte((md << 6) | ((d & 7) << 3) | (base & 7)); }
  else {
    byte((md << 6) | ((d & 7) << 3) | 4);
    let mut ix = index; if index < 0 { ix = 4; }
    byte(((ix & 7) << 3) | (base & 7));
  }
  if md == 1 { byte(disp & 255); } else if md == 2 { u32_(disp); }
}
// r * (1 + 2^scale), modulo 2^64: lea r, [r + r * 2^scale]
fn lea_mul_small(r: i64, scale: i64) {
  let mut rex = 72;
  if (r & 8) != 0 { rex = 79; }   // REX.W | REX.R | REX.X | REX.B
  byte(rex); byte(141);
  let mut md = 0;
  if (r & 7) == 5 { md = 1; }   // rbp / r13 as base need mod 01 with a zero displacement
  byte((md << 6) | ((r & 7) << 3) | 4);
  byte((scale << 6) | ((r & 7) << 3) | (r & 7));
  if md == 1 { byte(0); }
}
let mut mdisp: i64 = 0;
fn memop(w: i64, p66: bool, force_rex: bool, nop: i64, o1: i64, o2: i64, regf: i64, base: i64, index: i64, scale: i64) {
  if p66 { byte(102); }
  let mut rex = 64;
  if w != 0 { rex = rex | 8; } if (regf & 8) != 0 { rex = rex | 4; } if index >= 0 && (index & 8) != 0 { rex = rex | 2; } if base >= 0 && (base & 8) != 0 { rex = rex | 1; }
  if rex != 64 || force_rex { byte(rex); }
  byte(o1); if nop == 2 { byte(o2); }
  let d = mdisp; mdisp = 0;
  if base < 0 {   // no base register: [index * 2^scale + disp32] or [disp32]
    let mut ix = 4; if index >= 0 { ix = index & 7; }
    byte(4 | ((regf & 7) << 3)); byte((scale << 6) | (ix << 3) | 5); u32_(d); return;
  }
  let mut md = 2;
  if d == 0 && (base & 7) != 5 { md = 0; } else if fits_s8(d as u64) { md = 1; }
  byte((md << 6) | ((regf & 7) << 3) | 4);
  let mut ix = index & 7; if index < 0 { ix = 4; }
  byte((scale << 6) | (ix << 3) | (base & 7));
  if md == 1 { byte(d & 255); } else if md == 2 { u32_(d); }
}
fn lg(w: i64) -> i64 { let mut k = 0; while (1 << k) < w { k += 1; } return k; }
fn load_elem(t: i64, d: i64, base: i64, idx: i64, sc: i64) {
  if t == TY_U8 || t == TY_BOOL { memop(0, false, false, 2, 15, 182, d, base, idx, sc); }
  else if t == TY_I8 { memop(1, false, false, 2, 15, 190, d, base, idx, sc); }
  else if t == TY_U16 { memop(0, false, false, 2, 15, 183, d, base, idx, sc); }
  else if t == TY_I16 { memop(1, false, false, 2, 15, 191, d, base, idx, sc); }
  else if t == TY_U32 || t == TY_F32 { memop(0, false, false, 1, 139, 0, d, base, idx, sc); }
  else if t == TY_I32 { memop(1, false, false, 1, 99, 0, d, base, idx, sc); }
  else { memop(1, false, false, 1, 139, 0, d, base, idx, sc); }
}
fn store_elem(w: i64, dig: i64, v: i64, base: i64, idx: i64, sc: i64) {
  let mut op = 0;
  if dig < 0 { if w == 1 { op = 136; } else { op = 137; } }
  else { if w == 1 { op = dig * 8; } else { op = dig * 8 + 1; } }
  let mut ww = 0; if w == 8 { ww = 1; }
  memop(ww, w == 2, w == 1, 1, op, 0, v, base, idx, sc);
}
// mem (op)= immediate; dig < 0: plain store
fn store_elem_imm(w: i64, dig: i64, v: u64) {
  let mut ww = 0; if w == 8 { ww = 1; }
  if dig < 0 {
    if w == 1 { memop(0, false, false, 1, 198, 0, 0, EA_B, EA_RI, EA_SC); byte((v & 255) as i64); return; }
    memop(ww, w == 2, false, 1, 199, 0, 0, EA_B, EA_RI, EA_SC);
    if w == 2 { byte((v & 255) as i64); byte(((v >> 8) & 255) as i64); } else { u32_((v & 4294967295) as i64); }
    return;
  }
  if w == 1 { memop(0, false, false, 1, 128, 0, dig, EA_B, EA_RI, EA_SC); byte((v & 255) as i64); return; }
  if w == 2 { memop(0, true, false, 1, 129, 0, dig, EA_B, EA_RI, EA_SC); byte((v & 255) as i64); byte(((v >> 8) & 255) as i64); return; }
  if fits_s8(v) && (w == 8 || fits_s8((v as u32) as i32 as i64 as u64)) {
    memop(ww, false, false, 1, 131, 0, dig, EA_B, EA_RI, EA_SC); byte((v & 255) as i64); return;
  }
  memop(ww, false, false, 1, 129, 0, dig, EA_B, EA_RI, EA_SC); u32_((v & 4294967295) as i64);
}
fn unop(dig: i64, dk: i64, dr: i64) { enc(1, false, 1, 247, 0, dig, dk, dr); }
fn cqo() { emh("4899"); }
// rax / rcx -> rax, rdx. When both fit in 32 unsigned bits (so a signed operand is non-negative),
// the 32-bit divide gives the same quotient and remainder several times faster; a zero divisor
// still raises #DE (SIGFPE) on either path, and i64::MIN / -1 takes the 64-bit idiv.
fn div32_fast(signed: bool) { div32_by(signed, RCX); }
// the 64-bit divide is an out-of-line stub (emitted with the runtime) that jumps back: the 32-bit
// fast path falls through without a taken branch
let DS_AT = alloc<i64>(65536);
let DS_RET = alloc<i64>(65536);
let DS_SG = alloc<bool>(65536);
let DS_D = alloc<i64>(65536);
let mut NDS: i64 = 0;
fn div32_by(signed: bool, d: i64) {   // rax / d (d not rax, rdx)
  emh("4889c2"); alur(A_OR, RDX, d); emh("48c1ea20");   // rdx = (rax | d) >> 32
  if NDS < 65536 {
    let slow = jcc(CC_NE);
    encr(0, false, 1, 247, 0, 6, d);               // div d32 (edx = 0)
    DS_AT[NDS] = slow; DS_RET[NDS] = clen; DS_SG[NDS] = signed; DS_D[NDS] = d; NDS += 1;
    return;
  }
  let slow = j8(117);                              // jnz
  encr(0, false, 1, 247, 0, 6, d);                 // div d32 (edx = 0)
  let done = j8(235);
  p8(slow, clen);
  if signed { cqo(); encr(1, false, 1, 247, 0, 7, d); } else { emh("31d2"); encr(1, false, 1, 247, 0, 6, d); }   // idiv / div d
  p8(done, clen);
}
fn emit_div_stubs() {
  let mut i = 0;
  while i < NDS {
    rel32(DS_AT[i], clen);
    let d = DS_D[i];
    if DS_SG[i] { cqo(); encr(1, false, 1, 247, 0, 7, d); } else { emh("31d2"); encr(1, false, 1, 247, 0, 6, d); }
    rel32(jmp(), DS_RET[i]);
    i += 1;
  }
  NDS = 0;
}
fn setcc_zx(cc: i64, r: i64) { encr(0, true, 2, 15, 144 | cc, 0, r); encr(1, false, 2, 15, 182, r, r); }
fn test_rr(r: i64) { encr(1, false, 1, 133, 0, r, r); }
fn jcc(cc: i64) -> i64 { let s0 = clen; byte(15); byte(128 | cc); u32_(0); jrec(s0); return clen - 4; }
fn jmp() -> i64 { let s0 = clen; byte(233); u32_(0); jrec(s0); return clen - 4; }
let CC_B = 2; let CC_AE = 3; let CC_BE = 6; let CC_A = 7; let CC_S = 8; let CC_P = 10; let CC_NP = 11;
let CC_E = 4; let CC_NE = 5; let CC_L = 12; let CC_GE = 13; let CC_LE = 14; let CC_G = 15;
fn cc_of(op: i64) -> i64 {
  if op == O_EQ { return CC_E; } if op == O_NE { return CC_NE; } if op == O_LT { return CC_L; }
  if op == O_LE { return CC_LE; } if op == O_GT { return CC_G; }
  if op == O_LTU { return CC_B; } if op == O_LEU { return CC_BE; } if op == O_GTU { return CC_A; } if op == O_GEU { return CC_AE; }
  return CC_GE;
}
// patch lists of rel32 fields awaiting a target (lists are threaded by value)
let pl_at = alloc<i64>(1048576);
let pl_next = alloc<i64>(1048576);
let mut npl: i64 = 0;
fn pl_add(list: i64, at: i64) -> i64 {
  if npl >= MAX_PATCH { fail("too many branches"); }
  pl_at[npl] = at; pl_next[npl] = list; npl += 1; return npl - 1;
}
fn pl_patch(list0: i64, target: i64) { let mut l = list0; while l >= 0 { if pl_at[l] >= 0 { rel32(pl_at[l], target); } l = pl_next[l]; } }   // pl_at -1: rewound
fn pl_cat(a: i64, b: i64) -> i64 { let mut r = a; let mut l = b; while l >= 0 { if pl_at[l] >= 0 { r = pl_add(r, pl_at[l]); } l = pl_next[l]; } return r; }

// ---------------------------------------------------------------- signed division by constant
let mut MG_M: i64 = 0;
let mut MG_S: i64 = 0;
fn magic(d: i64) {
  let two63: u64 = 9223372036854775808;
  let mut ad = d as u64; if d < 0 { ad = 0 - (d as u64); }
  let t = two63 + ((d as u64) >> 63);
  let anc = t - 1 - t % ad;
  let mut p = 63;
  let mut q1 = two63 / anc;
  let mut r1 = two63 - q1 * anc;
  let mut q2 = two63 / ad;
  let mut r2 = two63 - q2 * ad;
  let mut delta: u64 = 0;
  while true {
    p += 1;
    q1 = q1 * 2; r1 = r1 * 2; if r1 >= anc { q1 += 1; r1 -= anc; }
    q2 = q2 * 2; r2 = r2 * 2; if r2 >= ad { q2 += 1; r2 -= ad; }
    delta = ad - r2;
    if !(q1 < delta || (q1 == delta && r1 == 0)) { break; }
  }
  let mut m = q2 + 1; if d < 0 { m = 0 - m; }
  MG_M = m as i64; MG_S = p - 64;
}
fn divconst(r: i64, dv: u64, mod_: bool, nn_: bool) {
  let d = dv as i64;
  if d == 0 { mov_ri(RCX, 0); mov_rr(RAX, r); cqo(); unop(7, K_REG, RCX); return; }   // constant-propagated zero: trap at run time
  if d == 1 { if mod_ { mov_ri(r, 0); } return; }
  if d == -1 || d == INT64_MIN {
    mov_ri(RCX, dv); mov_rr(RAX, r); cqo(); unop(7, K_REG, RCX);
    if mod_ { mov_rr(r, RDX); } else { mov_rr(r, RAX); }
    return;
  }
  let mut ad = dv; if d < 0 { ad = 0 - dv; }
  if nn_ && d > 0 && (ad & (ad - 1)) == 0 {
    let mut k: u64 = 0; while ((1 as u64) << k) != ad { k += 1; }
    if mod_ { alui(A_AND, r, ad - 1); } else { shift_ri(7, r, k as i64); }
    return;
  }
  if (ad & (ad - 1)) == 0 {
    let mut k: u64 = 0; while ((1 as u64) << k) != ad { k += 1; }
    mov_rr(RAX, r); shift_ri(7, RAX, 63); shift_ri(5, RAX, 64 - k as i64); alur(A_ADD, RAX, r);
    if mod_ { alui(A_AND, RAX, 0 - ad); alur(A_SUB, r, RAX); }
    else { shift_ri(7, RAX, k as i64); if d < 0 { unop(3, K_REG, RAX); } mov_rr(r, RAX); }
    return;
  }
  magic(d);
  let M = MG_M; let s = MG_S;
  mov_ri(RAX, M as u64); unop(5, K_REG, r);
  if d > 0 && M < 0 { alur(A_ADD, RDX, r); }
  if d < 0 && M > 0 { alur(A_SUB, RDX, r); }
  shift_ri(7, RDX, s);
  if d > 0 { if !nn_ { mov_rr(RAX, r); shift_ri(7, RAX, 63); alur(A_SUB, RDX, RAX); } }
  else { mov_rr(RAX, RDX); shift_ri(5, RAX, 63); alur(A_ADD, RDX, RAX); }
  if !mod_ { mov_rr(r, RDX); return; }
  imul_r(RDX, K_IMM, 0, dv); alur(A_SUB, r, RDX);
}

// ---------------------------------------------------------------- expression codegen
let mut tbase: i64 = 0;
let mut tdepth: i64 = 0;
let mut tmax: i64 = 0;
fn tslot_push() -> i64 { let s = tbase + tdepth; tdepth += 1; if tdepth > tmax { tmax = tdepth; } return s; }
fn loc(v: i64) {
  if vars[v].xr >= 0 { if vars[v].ty == TY_F32 { OK = K_XMMS; } else { OK = K_XMM; } ORR = vars[v].xr; OI = 0; return; }
  if vars[v].reg < 0 && (vars[v].slot < 0 || vars[v].slot >= fslot[curfn]) { emlen = 0; em_s("internal: variable outside its frame: "); em_src(vars[v].noff, vars[v].nlen); em_c(32); em_n(v); em_c(32); em_n(vars[v].start); em_c(32); em_n(vars[v].end); em_s(" glob="); em_n(vars[v].glob); em_s(" owner="); em_n(vars[v].owner); em_s(" curfn="); em_src(fns[curfn].noff, fns[curfn].nlen); die(); }
  if vars[v].reg >= 0 { OK = K_REG; ORR = vars[v].reg; } else { OK = K_MEM; ORR = vars[v].slot; } OI = 0; }
fn simple(e: i64) -> bool { return nd[e].k == N_CONST || nd[e].k == N_VAR; }
fn hoisted(e: i64) -> i64 {
  if nd[e].k == N_CONST && nd[e].c >= 0 && vars[nd[e].c].reg >= 0 { return vars[nd[e].c].reg; }
  return -1;
}
fn hoisted_x(e: i64) -> i64 {
  if nd[e].k == N_CONST && nd[e].c >= 0 && vars[nd[e].c].xr >= 0 { return vars[nd[e].c].xr; }
  return -1;
}
fn movx(d: i64, s: i64) { if d != s { sse(0, 0, 40, d, K_REG, s); } }   // movaps
fn opnd(e: i64) {
  if nd[e].k == N_CONST {
    let h = hoisted(e);
    if h >= 0 { OK = K_REG; ORR = h; OI = 0; } else { OK = K_IMM; ORR = 0; OI = nd[e].v; }
    return;
  }
  loc(nd[e].var);
  // an xmm-resident float read as an integer (bits(x)): its bit pattern goes through rcx
  if is_xk(OK) && !ty_flt(nd[e].ty) { load(RCX, OK, ORR, OI); OK = K_REG; ORR = RCX; OI = 0; }
}
fn xvar_node(e: i64) -> bool { return nd[e].k == N_VAR && vars[nd[e].var].xr >= 0; }
fn is_cmp(op: i64) -> bool { return op >= O_EQ && op <= O_GEU; }
fn commutes(op: i64) -> bool { return op == O_ADD || op == O_MUL || op == O_AND || op == O_OR || op == O_XOR || op == O_EQ || op == O_NE; }
fn swap_cmp(op: i64) -> i64 {
  if op == O_LT { return O_GT; } if op == O_GT { return O_LT; } if op == O_LE { return O_GE; } if op == O_GE { return O_LE; }
  if op == O_LTU { return O_GTU; } if op == O_GTU { return O_LTU; } if op == O_LEU { return O_GEU; } if op == O_GEU { return O_LEU; }
  if op == O_FLT { return O_FGT; } if op == O_FGT { return O_FLT; } if op == O_FLE { return O_FGE; } if op == O_FGE { return O_FLE; }
  if op == O_GLT { return O_GGT; } if op == O_GGT { return O_GLT; } if op == O_GLE { return O_GGE; } if op == O_GGE { return O_GLE; }
  return op;
}
fn need(e: i64) -> i64 {
  let k = nd[e].k;
  if k == N_UN || k == N_LOAD { return need(nd[e].a); }
  if k != N_BIN { return 1; }
  let na = need(nd[e].a);
  if nd[e].op == O_LAND || nd[e].op == O_LOR { let nb = need(nd[e].b); if na > nb { return na; } return nb; }
  if simple(nd[e].b) { return na; }
  let nb = need(nd[e].b);
  if na == nb { return na + 1; } if na > nb { return na; } return nb;
}
fn refs(e: i64, v: i64) -> bool {
  if e < 0 { return false; }
  if nd[e].k == N_VAR { return nd[e].var == v; }
  if nd[e].k == N_CALL { let mut a = nd[e].a; while a >= 0 { if refs(a, v) { return true; } a = nd[a].next; } return false; }
  return refs(nd[e].a, v) || refs(nd[e].b, v);
}
fn has_trap(e: i64) -> bool {
  if e < 0 || nd[e].k == N_CONST || nd[e].k == N_VAR || nd[e].k == N_ARR { return false; }
  if nd[e].k == N_CALL { return true; }
  let b = nd[e].b;
  if nd[e].k == N_LOAD && nd[e].chk != 0 { return true; }
  if nd[e].k == N_BIN && (nd[e].op == O_DIV || nd[e].op == O_MOD) && (!is_const(b) || (nd[b].v as i64) == -1 || nd[b].v == 0) { return true; }
  if nd[e].k == N_BIN && (nd[e].op == O_DIVU || nd[e].op == O_MODU) && (!is_const(b) || nd[b].v == 0) { return true; }
  return has_trap(nd[e].a) || has_trap(nd[e].b);
}
let mut div_nn: bool = false;
// ---- SSE2 scalar float
fn sse(pfx: i64, w: i64, op: i64, regf: i64, rk: i64, rr: i64) { if pfx != 0 { byte(pfx); } enc(w, false, 2, 15, op, regf, rk, rr); }
fn fload(x: i64, sk0: i64, sr0: i64, si: u64, dbl: bool) {
  let mut sk = sk0; let mut sr = sr0;
  if is_xk(sk) { movx(x, sr); return; }
  if sk == K_IMM { mov_ri(RAX, si); sk = K_REG; sr = RAX; }
  if sk == K_REG { sse(102, dbl as i64, 110, x, sk, sr); }
  else { sse(243, 0, 126, x, sk, sr); }
}
fn fstore(r: i64, x: i64, dbl: bool) { sse(102, dbl as i64, 126, x, K_REG, r); }
fn ucpfx(dbl: bool) -> i64 { if dbl { return 102; } return 0; }
fn fcmp_xmm(r: i64, sk: i64, sr: i64, si: u64, dbl: bool, swap: bool) {
  fload(0, K_REG, r, 0, dbl);
  if sk == K_MEM && !swap { sse(ucpfx(dbl), 0, 46, 0, sk, sr); return; }
  if is_xk(sk) && !swap { sse(ucpfx(dbl), 0, 46, 0, K_REG, sr); return; }
  fload(1, sk, sr, si, dbl);
  if swap { sse(ucpfx(dbl), 0, 46, 1, K_REG, 0); } else { sse(ucpfx(dbl), 0, 46, 0, K_REG, 1); }
}
fn foc(b: i64) -> i64 { if b == O_FADD { return 88; } if b == O_FSUB { return 92; } if b == O_FMUL { return 89; } return 94; }
fn apply_f(op: i64, r: i64, sk: i64, sr: i64, si: u64) {
  let dbl = fop_dbl(op);
  let b = fop_base(op);
  let mut pfx = 243; if dbl { pfx = 242; }
  if b <= O_FDIV {
    fload(0, K_REG, r, 0, dbl);
    if sk == K_MEM { sse(pfx, 0, foc(b), 0, sk, sr); }
    else if is_xk(sk) { sse(pfx, 0, foc(b), 0, K_REG, sr); }
    else { fload(1, sk, sr, si, dbl); sse(pfx, 0, foc(b), 0, K_REG, 1); }
    fstore(r, 0, dbl); return;
  }
  let swap = b == O_FLT || b == O_FLE;
  fcmp_xmm(r, sk, sr, si, dbl, swap);
  if b == O_FGT || b == O_FLT { setcc_zx(CC_A, r); }
  else if b == O_FGE || b == O_FLE { setcc_zx(CC_AE, r); }
  else if b == O_FEQ { setcc_zx(CC_E, r); emh("0f9bc00fb6c0"); alur(A_AND, r, RAX); }
  else { setcc_zx(CC_NE, r); emh("0f9ac00fb6c0"); alur(A_OR, r, RAX); }
}
let mut u2d_calls: i64 = -1;
let mut u2s_calls: i64 = -1;
let mut d2u_calls: i64 = -1;
let mut s2u_calls: i64 = -1;
fn call_to(list: i64) -> i64 { byte(232); let l = pl_add(list, clen); u32_(0); return l; }
fn f2i(r: i64, dbl: bool) {
  fload(0, K_REG, r, 0, dbl);
  let mut p = 243; if dbl { p = 242; }
  sse(p, 1, 44, r, K_REG, 0);
  alui(A_CMP, r, 1); let ok = j8(113);
  sse(ucpfx(dbl), 0, 46, 0, K_REG, 0); let nan = j8(122);
  fstore(RAX, 0, dbl); if dbl { test_rr(RAX); } else { emh("85c0"); } let neg = j8(120);
  unop(2, K_REG, r); let d2 = j8(235);
  p8(nan, clen); encr(0, false, 1, 49, 0, r, r);
  p8(ok, clen); p8(neg, clen); p8(d2, clen);
}
fn is_narrow(op: i64) -> bool { return op >= U_SX8 && op <= U_SATU32; }
fn ext_width(op: i64) -> i64 {
  if op == U_SX8 || op == U_ZX8 { return 1; } if op == U_SX16 || op == U_ZX16 { return 2; } if op == U_SX32 || op == U_ZX32 { return 4; }
  return 0;
}
fn sat_lo(k: i64) -> i64 { if k == 0 { return -128; } if k == 1 { return -32768; } if k == 2 { return -2147483648; } return 0; }
fn sat_hi(k: i64) -> i64 { if k == 0 { return 127; } if k == 1 { return 32767; } if k == 2 { return 2147483647; } if k == 3 { return 255; } if k == 4 { return 65535; } return 4294967295; }
fn apply_un(op: i64, r: i64) {
  if op == U_NEG { unop(3, K_REG, r); }
  else if op == U_NOT { unop(2, K_REG, r); }
  else if op == U_LNOT { alui(A_XOR, r, 1); }
  else if op == U_SX8 { encr(1, false, 2, 15, 190, r, r); }
  else if op == U_SX16 { encr(1, false, 2, 15, 191, r, r); }
  else if op == U_SX32 { encr(1, false, 1, 99, 0, r, r); }
  else if op == U_ZX8 { encr(0, true, 2, 15, 182, r, r); }
  else if op == U_ZX16 { encr(0, false, 2, 15, 183, r, r); }
  else if op == U_ZX32 { encr(0, false, 1, 137, 0, r, r); }
  else if op >= U_SATS8 && op <= U_SATU32 {
    let k = op - U_SATS8;
    mov_ri(RAX, sat_lo(k) as u64); alur(A_CMP, r, RAX); encr(1, false, 2, 15, 76, r, RAX);
    mov_ri(RAX, sat_hi(k) as u64); alur(A_CMP, r, RAX); encr(1, false, 2, 15, 79, r, RAX);
  }
  else if op == U_FNEG { encr(1, false, 2, 15, 186, 7, r); byte(63); }
  else if op == U_GNEG { encr(0, false, 1, 129, 0, 6, r); u32_(2147483648); }
  else if op == U_I2D || op == U_I2S {
    emh("660fefc0");
    let mut p = 243; if op == U_I2D { p = 242; }
    sse(p, 1, 42, 0, K_REG, r); fstore(r, 0, op == U_I2D);
  }
  else if op == U_D2S { fload(0, K_REG, r, 0, true); emh("f20f5ac0"); fstore(r, 0, false); }
  else if op == U_S2D { fload(0, K_REG, r, 0, false); emh("f30f5ac0"); fstore(r, 0, true); }
  else if op == U_SQRTD { fload(0, K_REG, r, 0, true); emh("f20f51c0"); fstore(r, 0, true); }
  else if op == U_SQRTS { fload(0, K_REG, r, 0, false); emh("f30f51c0"); fstore(r, 0, false); }
  else if op == U_D2I { f2i(r, true); }
  else if op == U_S2I { f2i(r, false); }
  else if op == U_U2D { mov_rr(RAX, r); u2d_calls = call_to(u2d_calls); mov_rr(r, RAX); }
  else if op == U_U2S { mov_rr(RAX, r); u2s_calls = call_to(u2s_calls); mov_rr(r, RAX); }
  else if op == U_D2U { mov_rr(RAX, r); d2u_calls = call_to(d2u_calls); mov_rr(r, RAX); }
  else if op == U_S2U { mov_rr(RAX, r); s2u_calls = call_to(s2u_calls); mov_rr(r, RAX); }
  else { fail("internal: bad unary operator"); }
}
fn apply(op: i64, r: i64, sk0: i64, sr0: i64, si: u64) {
  let mut sk = sk0; let mut sr = sr0;
  let nn_ = div_nn; div_nn = false;
  if is_fop(op) { apply_f(op, r, sk, sr, si); return; }
  if op == O_DIVU || op == O_MODU {
    if sk == K_IMM && si != 0 && (si & (si - 1)) == 0 {
      let mut k: u64 = 0; while ((1 as u64) << k) != si { k += 1; }
      if op == O_MODU { alui(A_AND, r, si - 1); } else { shift_ri(5, r, k as i64); }
      return;
    }
    if sk == K_IMM && si != 0 && (si & 1) == 0 {
      // For d=2m, floor(n/d) = floor((n >> 1)/m); n >> 1 fits signed i64.
      mov_rr(RCX, r); shift_ri(5, RCX, 1); divconst(RCX, si >> 1, false, true);
      if op == O_DIVU { mov_rr(r, RCX); }
      else { imul_r(RCX, K_IMM, 0, si); alur(A_SUB, r, RCX); }
      return;
    }
    if sk == K_IMM && si != 0 {
      if (si as i64) < 0 {
        // For d >= 2^63, the unsigned quotient is only zero or one.
        mov_ri(RAX, si);
        if op == O_DIVU { alur(A_CMP, r, RAX); setcc_zx(CC_AE, RAX); mov_rr(r, RAX); }
        else { mov_rr(RCX, r); alur(A_SUB, RCX, RAX); alur(A_CMP, r, RAX); cmov_rr(CC_AE, r, RCX); }
        return;
      }
      // ceil(2^64/d) gives the exact high product or one too much for odd d.
      let M = 18446744073709551615 / si + 1;
      mov_ri(RAX, M); unop(4, K_REG, r);  // unsigned high product is in RDX
      mov_rr(RCX, RDX); imul_r(RCX, K_IMM, 0, si); alur(A_SUB, r, RCX);
      if op == O_DIVU {
        alui(A_CMP, r, si); setcc_zx(CC_AE, RAX); alur(A_SUB, RDX, RAX); mov_rr(r, RDX);
      } else {
        mov_rr(RCX, r); alui(A_ADD, RCX, si); alui(A_CMP, r, si); cmov_rr(CC_AE, r, RCX);
      }
      return;
    }
    if sk == K_IMM { mov_ri(RCX, si); } else { load(RCX, sk, sr, si); }
    mov_rr(RAX, r); div32_fast(false);
    if op == O_DIVU { mov_rr(r, RAX); } else { mov_rr(r, RDX); }
    return;
  }
  if op == O_ADD { alu(A_ADD, K_REG, r, sk, sr, si); return; }
  if op == O_SUB { alu(A_SUB, K_REG, r, sk, sr, si); return; }
  if op == O_AND { alu(A_AND, K_REG, r, sk, sr, si); return; }
  if op == O_OR { alu(A_OR, K_REG, r, sk, sr, si); return; }
  if op == O_XOR { alu(A_XOR, K_REG, r, sk, sr, si); return; }
  if op == O_MUL {
    if sk == K_IMM {
      let v = si;
      if v == 0 { mov_ri(r, 0); return; }
      if v == 1 { return; }
      if (v as i64) == -1 { unop(3, K_REG, r); return; }
      if (v & (v - 1)) == 0 { let mut k: u64 = 0; while ((1 as u64) << k) != v { k += 1; } shift_ri(4, r, k as i64); return; }
      if v == 3 { lea_mul_small(r, 1); return; }
      if v == 5 { lea_mul_small(r, 2); return; }
      if v == 9 { lea_mul_small(r, 3); return; }
    }
    imul_r(r, sk, sr, si); return;
  }
  if op == O_SHL || op == O_SHR || op == O_SAR {
    let mut dig = 7; if op == O_SHL { dig = 4; } else if op == O_SHR { dig = 5; }
    if sk == K_IMM { shift_ri(dig, r, (si & 63) as i64); }
    else { load(RCX, sk, sr, si); encr(1, false, 1, 211, 0, dig, r); }
    return;
  }
  if op == O_DIV || op == O_MOD {
    if sk == K_IMM { divconst(r, si, op == O_MOD, nn_); return; }
    load(RCX, sk, sr, si); mov_rr(RAX, r); div32_fast(true);
    if op == O_DIV { mov_rr(r, RAX); } else { mov_rr(r, RDX); }
    return;
  }
  if !is_cmp(op) { fail("internal: bad operator"); }
  alu(A_CMP, K_REG, r, sk, sr, si); setcc_zx(cc_of(op), r);
}
fn j8(op: i64) -> i64 { let s0 = clen; byte(op); byte(0); jrec(s0); return clen - 1; }
// branches emitted while a loop is laid out (start, end), to choose its head padding
let JR_S = alloc<i64>(65536);
let JR_E = alloc<i64>(65536);
let mut NJR: i64 = 0;
let mut JREC: bool = false;
fn jrec(s0: i64) { if JREC && NJR < 65536 { JR_S[NJR] = s0; JR_E[NJR] = clen; NJR += 1; } }
fn jr_bad(d: i64, from: i64, cst: i64, cen: i64) -> i64 {   // weighted line-crossing branches with d more bytes
  let mut b = 0; let mut i = 0;
  while i < NJR {
    if JR_S[i] >= from {
      let a = JR_S[i] - 4 + d; let e = JR_E[i] + d;   // with a fused cmp/test of up to 4 bytes
      if (a / 32) != ((e - 1) / 32) || (e % 32) == 0 { b += 1; }
    }
    i += 1;
  }
  let a = cst + d; let e = cen + d;
  if (a / 32) != ((e - 1) / 32) || (e % 32) == 0 { b += 4; }   // the back edge (cmp + jcc) counts more
  return b;
}
fn p8(at: i64, target: i64) {
  let d = target - (at + 1);
  if d < -128 || d > 127 { fail("internal: short branch"); }
  code[at] = (d & 255) as u8;
}
let mut trap_list: i64 = -1;
let mut print_calls: i64 = -1;
let mut heap_calls: i64 = -1;
let mut printu_calls: i64 = -1;
let mut putc_calls: i64 = -1;
let mut write_calls: i64 = -1;
let mut ewrite_calls: i64 = -1;
let mut ncpu_calls: i64 = -1;
let mut use_out: bool = false;
let mut use_bss: bool = false;
let mut flush_calls: i64 = -1;
let ss_at = alloc<i64>(65536);
let ss_off = alloc<i64>(65536);
let mut nss: i64 = 0;
fn str_site(at: i64, off: i64) { if nss >= 65536 { fail("too many string uses"); } ss_at[nss] = at; ss_off[nss] = off; nss += 1; }
fn bounds(a: i64, r: i64, chk: i64) {
  if chk == 0 { return; }
  if vars[a].lenv < 0 { alu(A_CMP, K_REG, r, K_IMM, 0, vars[a].alen as u64); }
  else { loc(vars[a].lenv); alu(A_CMP, K_REG, r, OK, ORR, OI); }
  trap_list = pl_add(trap_list, jcc(CC_AE));
}
// fixed addresses: the image is mapped at 0x400000; static data (BSS) starts at 256 MiB
let BSS = 268435456;
let OUT_LEN = 268435456;
let SIG_ACT = 268435464;
let PAR_STATUS = 268435504;
let PAR_FAIL = 268435512;
let OUT_BUF = 268435520;
let OUT_CAP = 65536;
let ARENA_TOP = 268501056;
let ARENA_END = 268501064;
let HEAP_TOP = 268501080;   // bump heap for alloc<T>(n): next free byte, end of the mapped chunk
let HEAP_END = 268501088;
let GLOB_BASE = 268501120;
let BSS_FIXED = 65664;
fn base_opnd(a: i64) {
  let b = vars[a].basev;
  if vars[b].isconst != 0 { OK = K_IMM; ORR = 0; OI = (GLOB_BASE as u64) + vars[b].cval; return; }
  loc(b);
}
fn load_base(r: i64, a: i64) {
  let b = vars[a].basev;
  if vars[b].glob == 2 { if (r & 8) != 0 { byte(65); } byte(184 | (r & 7)); str_site(clen, vars[b].cval as i64); u32_(0); return; }
  base_opnd(a); load(r, OK, ORR, OI);
}
fn abs_op(op: i64, r: i64, addr: i64) { let mut rx = 72; if (r & 8) != 0 { rx = 76; } byte(rx); byte(op); byte(4 | ((r & 7) << 3)); byte(37); u32_(addr); }
fn base_reg(a: i64) -> i64 {
  if vars[vars[a].basev].glob == 2 { load_base(RAX, a); return RAX; }
  base_opnd(a);
  if OK == K_REG { return ORR; }
  load(RAX, OK, ORR, OI); return RAX;
}
// expression temporaries: register lists live in RGS; a list is (index, count)
let RGS = alloc<i64>(1048576);
let mut rgs_top: i64 = 0;
let mut IR_DISP: i64 = 0;
fn index_reg(idx: i64, chk: i64, w: i64, rg: i64, n: i64) -> i64 {
  IR_DISP = 0;
  if chk == 0 && is_const(idx) && (nd[idx].v as i64) > -1048576 && (nd[idx].v as i64) < 1048576 && w <= 1024 { IR_DISP = (nd[idx].v as i64) * w; return -1; }   // no index register
  if nd[idx].k == N_VAR && vars[nd[idx].var].reg >= 0 { return vars[nd[idx].var].reg; }
  if chk == 0 && nd[idx].k == N_BIN && (nd[idx].op == O_ADD || nd[idx].op == O_SUB) && nd[nd[idx].a].k == N_VAR && vars[nd[nd[idx].a].var].reg >= 0 && is_const(nd[idx].b) {
    let mut c = nd[nd[idx].b].v as i64; if nd[idx].op == O_SUB { c = 0 - c; }
    if c > -1048576 && c < 1048576 && w <= 1024 { IR_DISP = c * w; return vars[nd[nd[idx].a].var].reg; }
  }
  gen(idx, rg, n); IR_DISP = 0; return RGS[rg];
}
let mut EA_B: i64 = 0;
let mut EA_RI: i64 = 0;
let mut EA_SC: i64 = 0;
fn elem_addr(a: i64, idx: i64, chk: i64, foff: i64, rg: i64, n: i64) {
  let w = vars[a].arr;
  let bv = vars[a].basev;
  let static_base = vars[bv].isconst != 0 && vars[bv].glob == 1;
  // static array, constant index, no check: one absolute address
  if static_base && chk == 0 && is_const(idx) && fits_s32(nd[idx].v) {
    let ad = GLOB_BASE + (vars[bv].cval as i64) + (nd[idx].v as i64) * w + foff;
    if ad >= 0 && ad < 2147483647 { EA_B = -1; EA_RI = -1; EA_SC = 0; mdisp = ad; return; }
  }
  let mut ri = index_reg(idx, chk, w, rg, n);
  let d = IR_DISP;
  bounds(a, ri, chk);
  let mut sc = 0;
  if w == 1 || w == 2 || w == 4 || w == 8 || ri < 0 { if ri >= 0 { sc = lg(w); } }
  else {
    if w < 128 { encr(1, false, 1, 107, 0, RDX, ri); byte(w); } else { encr(1, false, 1, 105, 0, RDX, ri); u32_(w); }
    ri = RDX; sc = 0;
  }
  if static_base && GLOB_BASE + (vars[bv].cval as i64) + d + foff < 2147483647 && d + foff > -1048576 {
    EA_B = -1; EA_RI = ri; EA_SC = sc; mdisp = GLOB_BASE + (vars[bv].cval as i64) + d + foff; return;
  }
  EA_B = base_reg(a); EA_RI = ri; EA_SC = sc; mdisp = d + foff;
}
fn fld_off(a: i64, f: i64) -> i64 { if f > 0 { return sfoff[(vars[a].et - TY_STRUCT0) * 32 + f - 1]; } return 0; }
fn fld_ty(a: i64, f: i64) -> i64 { if f > 0 { return sfty[(vars[a].et - TY_STRUCT0) * 32 + f - 1]; } return vars[a].et; }
fn store_out(disp: i64, r: i64) { let sv = sp_adj; sp_adj = 0; enc(1, false, 1, 137, 0, r, K_MEM, disp / 8); sp_adj = sv; }
let FRAME_FIX = alloc<i64>(64);
let mut nframefix: i64 = 0;
fn push_r(r: i64) { if (r & 8) != 0 { byte(65); } byte(80 | (r & 7)); }
fn pop_r(r: i64) { if (r & 8) != 0 { byte(65); } byte(88 | (r & 7)); }
// functions with at most two scalar parameters take them in rcx, rdx
fn regconv(f: i64) -> bool {
  if fns[f].np > 2 { return false; }
  let mut i = 0;
  while i < fns[f].np { if fpw[f * 16 + i] != 0 { return false; } i += 1; }
  return true;
}
let mut cur_stmt: i64 = -1;  // statement whose call sites may skip saving registers that die there
fn rbit(v: i64) -> i64 {
  if v < 0 || vars[v].reg < 0 { return 0; }
  let mut i = 0;
  while i < 12 { if allregs[i] == vars[v].reg { return 1 << i; } i += 1; }
  return 0;
}
fn arr_bits(a: i64) -> i64 { let mut m = rbit(vars[a].basev); if vars[a].lenv >= 0 { m = m | rbit(vars[a].lenv); } return m; }
// registers of variables read by e outside the subtree `skip`
fn refs_bits(e: i64, skip: i64) -> i64 {
  if e < 0 || e == skip { return 0; }
  let k = nd[e].k;
  if k == N_VAR { return rbit(nd[e].var); }
  if k == N_CONST { if nd[e].c >= 0 { return rbit(nd[e].c); } return 0; }
  if k == N_ARR { return arr_bits(nd[e].var); }
  if k == N_CALL { let mut m = 0; let mut a = nd[e].a; while a >= 0 { m = m | refs_bits(a, skip); a = nd[a].next; } return m; }
  let mut m = 0;
  if k == N_LOAD { m = arr_bits(nd[e].var); }
  return m | refs_bits(nd[e].a, skip) | refs_bits(nd[e].b, skip);
}
// caller-saved registers whose variables are dead once call e (in statement cur_stmt) returns
fn dead_at_call(e: i64) -> i64 {
  let s = cur_stmt;
  if s < 0 || cur_pos != nd[s].pos || cur_pos < 0 || cur_pos >= busy_n { return 0; }
  let mut m = busy[cur_pos] & ~livem[cur_pos];
  if m == 0 { return 0; }
  let k = nd[s].k;
  let mut r = refs_bits(nd[s].a, e);
  if k == S_LET || k == S_ASSIGN || k == S_IRET { r = r | rbit(nd[s].var); }
  if k == S_STORE { r = r | refs_bits(nd[s].b, e) | arr_bits(nd[s].var); }
  return m & ~r;
}
fn gen_simple_to(e: i64, r: i64) {   // a constant or integer variable into register r
  if nd[e].k == N_CONST { if hoisted(e) >= 0 { mov_rr(r, hoisted(e)); } else { mov_ri(r, nd[e].v); } return; }
  loc(nd[e].var); load(r, OK, ORR, OI);
}
fn gen_call(e: i64, rg: i64, n: i64) {
  let f = nd[e].var;
  let rc = regconv(f);
  let mut words = 0;
  let mut direct = true;
  let mut nscal = 0;
  let mut a = nd[e].a;
  while a >= 0 { if nd[a].k == N_ARR { words += 2; } else { words += 1; if has_call(a) { direct = false; } } a = nd[a].next; }
  let slot = alloc<i64>(16);
  let mut k = 0;
  if !direct {
    a = nd[e].a;
    while a >= 0 {
      if nd[a].k != N_ARR { gen(a, rg, n); slot[k] = tslot_push(); store(K_MEM, slot[k], RGS[rg]); k += 1; nscal += 1; }
      a = nd[a].next;
    }
  }
  let svr = alloc<i64>(12);
  let mut ns = 0;
  let dm = dead_at_call(e);
  let mut i = 0;
  while i < 12 {
    let r = allregs[i];
    let mut fr = callee_saved(r) || ((dm >> i) & 1) != 0;
    let mut j = 0;
    while j < n { if RGS[rg + j] == r { fr = true; } j += 1; }
    if !fr { svr[ns] = r; ns += 1; }
    i += 1;
  }
  i = 0;
  while i < ns { push_r(svr[i]); i += 1; }
  let mut xm = 0;
  if cur_pos >= 0 && cur_pos < busy_n { xm = xbusy[cur_pos]; }
  let mut nx = 0;
  i = 0;
  while i < NXREG { if ((xm >> i) & 1) != 0 { sse(102, 1, 126, XREG0 + i, K_REG, RAX); push_r(RAX); nx += 1; } i += 1; }
  let mut A = 8 * words;
  if rc { A = 0; }
  if A != 0 { if A <= 127 { emh("4883ec"); byte(A); } else { emh("4881ec"); u32_(A); } }
  sp_adj = 8 * (ns + nx) + A;
  let mut w = 0;
  k = 0;
  a = nd[e].a;
  if rc {
    // arguments into temporaries first (evaluating one may use rcx/rdx), then into rcx, rdx
    let mut j = 0;
    let np = fns[f].np;
    if direct && np == 2 && n < 2 {   // one free temporary: park the first argument in a frame slot
      gen(a, rg, n); let ts = tslot_push(); store(K_MEM, ts, RGS[rg]);
      gen(nd[a].next, rg, n); mov_rr(RDX, RGS[rg]); load(RCX, K_MEM, ts, 0); tdepth -= 1;
      a = -1;
    }
    if !direct {
      while a >= 0 { if j == 0 { load(RCX, K_MEM, slot[k], 0); } else { load(RDX, K_MEM, slot[k], 0); } k += 1; j += 1; a = nd[a].next; }
    }
    // plain variables and constants go straight into rcx / rdx (loading them clobbers nothing)
    let mut allsimple = direct && a >= 0;
    let mut q = a; while q >= 0 { if !simple(q) || xvar_node(q) { allsimple = false; } q = nd[q].next; }
    if allsimple {
      while a >= 0 { let d = RCX; if j == 1 { gen_simple_to(a, RDX); } else { gen_simple_to(a, d); } j += 1; a = nd[a].next; }
      j = 0;
    }
    while a >= 0 { gen(a, rg + j, n - j); j += 1; a = nd[a].next; }
    if direct && j >= 1 { mov_rr(RCX, RGS[rg]); }
    if direct && j >= 2 { mov_rr(RDX, RGS[rg + 1]); }
  }
  while a >= 0 {
    if nd[a].k == N_ARR {
      let av = nd[a].var;
      load_base(RAX, av); store_out(8 * w, RAX);
      if vars[av].lenv < 0 { mov_ri(RAX, vars[av].alen as u64); } else { loc(vars[av].lenv); load(RAX, OK, ORR, OI); }
      store_out(8 * w + 8, RAX); w += 2;
    } else {
      if direct { gen(a, rg, n); store_out(8 * w, RGS[rg]); }
      else { load(RAX, K_MEM, slot[k], 0); k += 1; store_out(8 * w, RAX); }
      w += 1;
    }
    a = nd[a].next;
  }
  sp_adj = 0;
  byte(232); fns[f].calls = pl_add(fns[f].calls, clen); u32_(0);
  if A != 0 { if A <= 127 { emh("4883c4"); byte(A); } else { emh("4881c4"); u32_(A); } }
  i = NXREG - 1;
  while i >= 0 { if ((xm >> i) & 1) != 0 { pop_r(RCX); sse(102, 1, 110, XREG0 + i, K_REG, RCX); } i -= 1; }
  i = ns - 1;
  while i >= 0 { pop_r(svr[i]); i -= 1; }
  mov_rr(RGS[rg], RAX);
  tdepth -= nscal;
}
// ---- float expression trees in an XMM stack (xmm2..xmm15)
fn fprec(e: i64) -> bool {
  let k = nd[e].k;
  let op = nd[e].op;
  if k == N_BIN && is_fop(op) { return fop_dbl(op); }
  if k == N_UN {
    if op == U_D2S || op == U_GNEG || op == U_SQRTS || op == U_I2S { return false; }
    if op == U_S2D || op == U_FNEG || op == U_SQRTD || op == U_I2D { return true; }
  }
  return nd[e].ty != TY_F32;
}
fn ftree(e: i64) -> bool {
  let k = nd[e].k;
  let op = nd[e].op;
  if k == N_BIN { return is_fop(op) && !is_fcmp(op); }
  if k == N_UN { return op == U_FNEG || op == U_GNEG || op == U_S2D || op == U_D2S || op == U_SQRTD || op == U_SQRTS || op == U_I2D || op == U_I2S; }
  return false;
}
let mut xtop: i64 = 2;
fn gen_x(e: i64, x: i64, rg: i64, n: i64) { let sv = xtop; xtop = x + 1; gen(e, rg, n); xtop = sv; }
fn xmov_in(x: i64, sk0: i64, sr0: i64, si: u64) {
  let mut sk = sk0; let mut sr = sr0;
  if is_xk(sk) { movx(x, sr); return; }
  if sk == K_IMM {
    if si == 0 { byte(102); encr(0, false, 2, 15, 239, x, x); return; }
    mov_ri(RAX, si); sk = K_REG; sr = RAX;
  }
  if sk == K_REG { sse(102, 1, 110, x, sk, sr); } else { sse(243, 0, 126, x, sk, sr); }
}
// a float element load usable as the memory operand of an SSE op of this precision
fn fmem_ok(b: i64, dbl: bool) -> bool {
  if nd[b].k != N_LOAD { return false; }
  let ft = fld_ty(nd[b].var, nd[b].op);
  return (ft == TY_F64 && dbl) || (ft == TY_F32 && !dbl);
}
fn fop_mem(pfx: i64, o: i64, x: i64, b: i64, rg: i64, n: i64) {
  let sv = xtop; if x + 1 > xtop { xtop = x + 1; }
  elem_addr(nd[b].var, nd[b].a, nd[b].chk, fld_off(nd[b].var, nd[b].op), rg, n);
  xtop = sv;
  byte(pfx); memop(0, false, false, 2, 15, o, x, EA_B, EA_RI, EA_SC);
}
fn genf(e: i64, x: i64, rg: i64, n: i64) {
  let dbl = fprec(e);
  let mut pfx = 243; if dbl { pfx = 242; }
  let k = nd[e].k;
  if k == N_CONST {
    let hx = hoisted_x(e);
    if hx >= 0 { movx(x, hx); return; }
    let h = hoisted(e);
    if h >= 0 { xmov_in(x, K_REG, h, 0); } else { xmov_in(x, K_IMM, 0, nd[e].v); }
    return;
  }
  if k == N_VAR { loc(nd[e].var); xmov_in(x, OK, ORR, OI); return; }
  if k == N_LOAD {
    let ft = fld_ty(nd[e].var, nd[e].op);
    if ty_flt(ft) {
      let sv = xtop; xtop = x + 1;
      elem_addr(nd[e].var, nd[e].a, nd[e].chk, fld_off(nd[e].var, nd[e].op), rg, n);
      xtop = sv;
      if ft == TY_F64 { byte(242); } else { byte(243); }
      memop(0, false, false, 2, 15, 16, x, EA_B, EA_RI, EA_SC);
      return;
    }
  }
  if k == N_BIN && is_fop(nd[e].op) && !is_fcmp(nd[e].op) {
    let o = foc(fop_base(nd[e].op));
    genf(nd[e].a, x, rg, n);
    let b = nd[e].b;
    if nd[b].k == N_VAR && vars[nd[b].var].reg < 0 {
      loc(nd[b].var);
      if is_xk(OK) { sse(pfx, 0, o, x, K_REG, ORR); } else { sse(pfx, 0, o, x, OK, ORR); }
      return;
    }
    if hoisted_x(b) >= 0 { sse(pfx, 0, o, x, K_REG, hoisted_x(b)); return; }
    if fmem_ok(b, dbl) { fop_mem(pfx, o, x, b, rg, n); return; }
    if x < XSTACK_TOP { genf(b, x + 1, rg, n); sse(pfx, 0, o, x, K_REG, x + 1); return; }
    gen_x(b, x, rg, n); xmov_in(1, K_REG, RGS[rg], 0); sse(pfx, 0, o, x, K_REG, 1); return;
  }
  if k == N_UN {
    let op = nd[e].op;
    if op == U_FNEG || op == U_GNEG {
      genf(nd[e].a, x, rg, n);
      if op == U_FNEG { mov_ri(RAX, 9223372036854775808); } else { mov_ri(RAX, 2147483648); }
      xmov_in(1, K_REG, RAX, 0);
      if op == U_FNEG { byte(102); }
      encr(0, false, 2, 15, 87, x, 1); return;
    }
    if op == U_S2D { genf(nd[e].a, x, rg, n); sse(243, 0, 90, x, K_REG, x); return; }
    if op == U_D2S { genf(nd[e].a, x, rg, n); sse(242, 0, 90, x, K_REG, x); return; }
    if op == U_SQRTD { genf(nd[e].a, x, rg, n); sse(242, 0, 81, x, K_REG, x); return; }
    if op == U_SQRTS { genf(nd[e].a, x, rg, n); sse(243, 0, 81, x, K_REG, x); return; }
    if op == U_I2D || op == U_I2S {
      gen_x(nd[e].a, x - 1, rg, n); byte(102); encr(0, false, 2, 15, 239, x, x);
      let mut p = 243; if op == U_I2D { p = 242; }
      sse(p, 1, 42, x, K_REG, RGS[rg]); return;
    }
  }
  gen_x(e, x - 1, rg, n); xmov_in(x, K_REG, RGS[rg], 0);
}
let XSTACK_TOP = 7;   // expression stack xmm2..xmm7
fn xroom(e: i64) -> bool { return ftree(e) && !has_call(e) && xtop <= XSTACK_TOP - 2; }
fn genf_root(e: i64, r: i64, rg: i64, n: i64) { let x = xtop; genf(e, x, rg, n); fstore(r, x, fprec(e)); }
let mut clobm: i64 = 0;   // callee-saved registers written while generating the current function
fn gen(e: i64, rg: i64, n: i64) {
  let r0 = RGS[rg];
  clobm = clobm | (1 << r0);
  if xroom(e) { genf_root(e, r0, rg, n); return; }
  let k = nd[e].k;
  if k == N_CONST { if hoisted(e) >= 0 { mov_rr(r0, hoisted(e)); } else { mov_ri(r0, nd[e].v); } return; }
  if k == N_VAR { loc(nd[e].var); load(r0, OK, ORR, OI); return; }
  if k == N_CALL { gen_call(e, rg, n); return; }
  if k == N_ARR { let b = base_reg(nd[e].var); mov_rr(r0, b); return; }   // base address (alias tests)
  if k == N_NCPU { byte(232); ncpu_calls = pl_add(ncpu_calls, clen); u32_(0); mov_rr(r0, RAX); return; }
  if k == N_LOAD {
    elem_addr(nd[e].var, nd[e].a, nd[e].chk, fld_off(nd[e].var, nd[e].op), rg, n);
    load_elem(fld_ty(nd[e].var, nd[e].op), r0, EA_B, EA_RI, EA_SC);
    return;
  }
  if k == N_UN { gen(nd[e].a, rg, n); if !(nd[e].nn != 0 && is_narrow(nd[e].op)) { apply_un(nd[e].op, r0); } return; }
  let op = nd[e].op; let mut a = nd[e].a; let mut b = nd[e].b;
  // constant-first commutative integer op: put the constant on the right (immediate / lea forms)
  if commutes(op) && nd[a].k == N_CONST && nd[b].k != N_CONST && hoisted(a) < 0 { let t = a; a = b; b = t; }
  // a / b, a % b on plain variables: operands straight into rax / rcx (no copy through r0)
  if div_simple(e) {
    opnd(b);
    let mut d = RCX;
    if OK == K_REG && ORR != RAX && ORR != RDX { d = ORR; } else { load(RCX, OK, ORR, OI); }   // a register divisor is used in place
    gen_simple_to(a, RAX);
    div32_by(op == O_DIV || op == O_MOD, d);
    if op == O_DIV || op == O_DIVU { mov_rr(r0, RAX); } else { mov_rr(r0, RDX); }
    return;
  }
  // (x << c) | (x >> (64 - c)) on 64-bit x: one rotate
  // Complementary logical shifts partition all 64 bits; OR, XOR, and wrapping
  // ADD therefore have the same result, with ADD producing no carries.
  if (op == O_OR || op == O_XOR || op == O_ADD) && (nd[e].ty == TY_U64 || nd[e].ty == TY_I64) && nd[a].k == N_BIN && nd[b].k == N_BIN {
    let mut l = a; let mut r = b;
    if nd[l].op == O_SHR && nd[r].op == O_SHL { l = b; r = a; }
    if nd[l].op == O_SHL && nd[r].op == O_SHR && is_const(nd[l].b) && is_const(nd[r].b) && expr_same(nd[l].a, nd[r].a) && ic_pure(nd[l].a)
       && (nd[nd[l].a].ty == TY_U64 || nd[nd[l].a].ty == TY_I64) {
      let c1 = nd[nd[l].b].v as i64; let c2 = nd[nd[r].b].v as i64;
      if c1 > 0 && c2 > 0 && c1 + c2 == 64 { gen(nd[l].a, rg, n); shift_ri(0, r0, c1); return; }
    }
  }
  if op == O_LAND || op == O_LOR {
    let mut f = -1; let mut en = -1;
    f = cond_jump(e, false, f, rg, n);
    mov_ri(r0, 1); en = pl_add(en, jmp()); pl_patch(f, clen); mov_ri(r0, 0); pl_patch(en, clen);
    return;
  }
  if nd[a].k == N_VAR && nd[b].k == N_CONST && !xvar_node(a) {
    let kv = nd[b].v;
    loc(nd[a].var);
    let lk = OK; let lr = ORR;
    if op == O_MUL && fits_s32(kv) && kv > 1 && (kv & (kv - 1)) != 0 && (kv as i64) != -1 {
      if lk == K_REG && (kv == 3 || kv == 5 || kv == 9) {   // r * (1 + 2^s): one lea
        mov_rr(r0, lr);
        let mut sh = 1; if kv == 5 { sh = 2; } if kv == 9 { sh = 3; }
        lea_mul_small(r0, sh); return;
      }
      if fits_s8(kv) { enc(1, false, 1, 107, 0, r0, lk, lr); byte((kv & 255) as i64); }
      else { enc(1, false, 1, 105, 0, r0, lk, lr); u32_(kv as i64); }
      return;
    }
    if (op == O_ADD || op == O_SUB) && lk == K_REG && fits_s32(kv) && (op == O_ADD || (kv as i64) != -2147483648) && kv != 0 {
      if op == O_ADD { lea(r0, lr, -1, kv as i64); } else { lea(r0, lr, -1, 0 - (kv as i64)); }
      return;
    }
  }
  if op == O_ADD && nd[a].k == N_VAR && nd[b].k == N_VAR && vars[nd[a].var].reg >= 0 && vars[nd[b].var].reg >= 0 {
    lea(r0, vars[nd[a].var].reg, vars[nd[b].var].reg, 0); return;
  }
  if simple(b) { gen(a, rg, n); div_nn = nd[e].nn != 0; opnd(b); apply(op, r0, OK, ORR, OI); return; }
  let lr = has_call(a) || has_call(b);
  if n >= 2 {
    if lr || need(a) >= need(b) { gen(a, rg, n); gen(b, rg + 1, n - 1); apply(op, r0, K_REG, RGS[rg + 1], 0); return; }
    gen(b, rg, n); gen(a, rg + 1, n - 1);
    if commutes(op) { apply(op, r0, K_REG, RGS[rg + 1], 0); }
    else if is_cmp(op) { apply(swap_cmp(op), r0, K_REG, RGS[rg + 1], 0); }
    else { apply(op, RGS[rg + 1], K_REG, r0, 0); mov_rr(r0, RGS[rg + 1]); }
    return;
  }
  if lr {
    gen(a, rg, 1); let sa = tslot_push(); store(K_MEM, sa, r0); gen(b, rg, 1); let sb = tslot_push(); store(K_MEM, sb, r0);
    load(r0, K_MEM, sa, 0); apply(op, r0, K_MEM, sb, 0); tdepth -= 2; return;
  }
  gen(b, rg, 1); let s = tslot_push(); store(K_MEM, s, r0); gen(a, rg, 1); apply(op, r0, K_MEM, s, 0); tdepth -= 1;
}
fn cond_jump(e: i64, sense: bool, list0: i64, rg: i64, n: i64) -> i64 {
  let mut list = list0;
  let k = nd[e].k;
  if k == N_CONST { if (nd[e].v != 0) == sense { list = pl_add(list, jmp()); } return list; }
  if k == N_UN && nd[e].op == U_LNOT { return cond_jump(nd[e].a, !sense, list, rg, n); }
  let op = nd[e].op;
  if k == N_BIN && op == O_LAND {
    if sense { let mut f = -1; f = cond_jump(nd[e].a, false, f, rg, n); list = cond_jump(nd[e].b, true, list, rg, n); pl_patch(f, clen); }
    else { list = cond_jump(nd[e].a, false, list, rg, n); list = cond_jump(nd[e].b, false, list, rg, n); }
    return list;
  }
  if k == N_BIN && op == O_LOR {
    if sense { list = cond_jump(nd[e].a, true, list, rg, n); list = cond_jump(nd[e].b, true, list, rg, n); }
    else { let mut t = -1; t = cond_jump(nd[e].a, true, t, rg, n); list = cond_jump(nd[e].b, false, list, rg, n); pl_patch(t, clen); }
    return list;
  }
  if k == N_BIN && is_fcmp(op) && !has_call(e) && xtop <= XSTACK_TOP - 1 {
    let bs = fop_base(op); let dbl = fop_dbl(op); let sw = bs == O_FLT || bs == O_FLE; let mut xa = xtop; let mut xb = xtop + 1;
    // operands in xmm variables are compared in place (ucomis* only reads them)
    if xvar_node(nd[e].a) { xa = vars[nd[nd[e].a].var].xr; } else { genf(nd[e].a, xa, rg, n); }
    if xvar_node(nd[e].b) { xb = vars[nd[nd[e].b].var].xr; } else { genf(nd[e].b, xb, rg, n); }
    if sw { sse(ucpfx(dbl), 0, 46, xb, K_REG, xa); } else { sse(ucpfx(dbl), 0, 46, xa, K_REG, xb); }
    if bs == O_FEQ || bs == O_FNE {
      let eq = (bs == O_FEQ) == sense;
      if eq { let sk = j8(122); list = pl_add(list, jcc(CC_E)); p8(sk, clen); }
      else { list = pl_add(list, jcc(CC_P)); list = pl_add(list, jcc(CC_NE)); }
      return list;
    }
    let mut cc = CC_AE; if bs == O_FGT || bs == O_FLT { cc = CC_A; }
    if sense { list = pl_add(list, jcc(cc)); } else { list = pl_add(list, jcc(cc ^ 1)); }
    return list;
  }
  if k == N_BIN && is_fcmp(op) && fop_base(op) != O_FEQ && fop_base(op) != O_FNE {
    let a = nd[e].a; let b = nd[e].b; let bs = fop_base(op); let dbl = fop_dbl(op); let ra = RGS[rg];
    let mut obk = 0; let mut obr = 0; let mut obi: u64 = 0;
    let mut park = 0;
    if simple(b) { gen(a, rg, n); opnd(b); obk = OK; obr = ORR; obi = OI; }
    else if n >= 2 { gen(a, rg, n); gen(b, rg + 1, n - 1); obk = K_REG; obr = RGS[rg + 1]; }
    else {
      gen(a, rg, 1); let sa = tslot_push(); store(K_MEM, sa, ra); gen(b, rg, 1); let sb = tslot_push(); store(K_MEM, sb, ra);
      load(ra, K_MEM, sa, 0); obk = K_MEM; obr = sb; park = 2;
    }
    fcmp_xmm(ra, obk, obr, obi, dbl, bs == O_FLT || bs == O_FLE);
    tdepth -= park;
    let mut cc = CC_AE; if bs == O_FGT || bs == O_FLT { cc = CC_A; }
    if sense { list = pl_add(list, jcc(cc)); } else { list = pl_add(list, jcc(cc ^ 1)); }
    return list;
  }
  if k == N_BIN && is_cmp(op) {
    let a = nd[e].a; let b = nd[e].b; let cc = cc_of(op);
    let mut lk = K_IMM; let mut lr = 0; let mut li: u64 = 0;
    let av = nd[a].k == N_VAR && !xvar_node(a);
    if av { loc(nd[a].var); lk = OK; lr = ORR; li = OI; }
    let mut bk = 0; let mut bbr = 0; let mut bi: u64 = 0;
    if simple(b) { opnd(b); bk = OK; bbr = ORR; bi = OI; }
    if av && simple(b) && (lk == K_REG || bk != K_MEM) { alu(A_CMP, lk, lr, bk, bbr, bi); }
    else if av && lk == K_REG { gen(b, rg, n); alu(A_CMP, lk, lr, K_REG, RGS[rg], 0); }
    else if simple(b) { gen(a, rg, n); opnd(b); alu(A_CMP, K_REG, RGS[rg], OK, ORR, OI); }
    else if n >= 2 && (need(a) >= need(b) || has_call(a) || has_call(b)) { gen(a, rg, n); gen(b, rg + 1, n - 1); alur(A_CMP, RGS[rg], RGS[rg + 1]); }
    else if n >= 2 { gen(b, rg, n); gen(a, rg + 1, n - 1); alur(A_CMP, RGS[rg + 1], RGS[rg]); }
    else if has_call(a) || has_call(b) {
      gen(a, rg, 1); let sa = tslot_push(); store(K_MEM, sa, RGS[rg]); gen(b, rg, 1); let sb = tslot_push(); store(K_MEM, sb, RGS[rg]);
      load(RGS[rg], K_MEM, sa, 0); alu(A_CMP, K_REG, RGS[rg], K_MEM, sb, 0); tdepth -= 2;
    }
    else { gen(b, rg, 1); let s = tslot_push(); store(K_MEM, s, RGS[rg]); gen(a, rg, 1); alu(A_CMP, K_REG, RGS[rg], K_MEM, s, 0); tdepth -= 1; }
    if sense { list = pl_add(list, jcc(cc)); } else { list = pl_add(list, jcc(cc ^ 1)); }
    return list;
  }
  if k == N_VAR && vars[nd[e].var].reg >= 0 { test_rr(vars[nd[e].var].reg); }
  else { gen(e, rg, n); test_rr(RGS[rg]); }
  if sense { list = pl_add(list, jcc(CC_NE)); } else { list = pl_add(list, jcc(CC_E)); }
  return list;
}

// ---------------------------------------------------------------- AVX-512 encoder (EVEX / VEX for mask registers)
// Memory operand for vector instructions (set before calling evx with rmk = 1):
//   VM_KIND 0: [VM_B + VM_I * 2^VM_S + VM_D] (VM_I < 0: no index), 1: [rip + constant pool offset VM_D], 2: [absolute VM_D]
let mut VM_KIND: i64 = 0;
let mut VM_B: i64 = 0;
let mut VM_I: i64 = -1;
let mut VM_S: i64 = 0;
let mut VM_D: i64 = 0;
let mut VM_TAIL: i64 = 0;          // bytes that follow the displacement (imm8): RIP-relative fixups need it
let cp_at = alloc<i64>(262144);    // constant-pool references: disp32 position, pool offset, tail bytes
let cp_off = alloc<i64>(262144);
let cp_tail = alloc<i64>(262144);
let mut ncp: i64 = 0;
let cpool = alloc<u8>(1048576);
let mut cplen: i64 = 0;
fn vm_mem(b: i64, i: i64, sc: i64, d: i64) { VM_KIND = 0; VM_B = b; VM_I = i; VM_S = sc; VM_D = d; }
fn vm_pool(off: i64) { VM_KIND = 1; VM_D = off; }
fn vm_abs(a: i64) { VM_KIND = 2; VM_D = a; }
// EVEX: map mm (1 0F, 2 0F38, 3 0F3A), pp (0, 1 66, 2 F3, 3 F2), W, ll (0 128, 1 256, 2 512)
fn evx(mm: i64, pp: i64, w: i64, ll: i64, op: i64, reg: i64, vv: i64, rmk: i64, rm: i64, aaa: i64, z: bool, bc: bool) {
  let mut xb = 0; let mut bb = 0;
  if rmk == 0 { bb = (rm >> 3) & 1; xb = (rm >> 4) & 1; }
  else if VM_KIND == 0 { bb = (VM_B >> 3) & 1; if VM_I >= 0 { xb = (VM_I >> 3) & 1; } }
  byte(98);
  byte(((1 - ((reg >> 3) & 1)) << 7) | ((1 - xb) << 6) | ((1 - bb) << 5) | ((1 - ((reg >> 4) & 1)) << 4) | mm);
  byte((w << 7) | (((~vv) & 15) << 3) | 4 | pp);
  byte(((z as i64) << 7) | (ll << 5) | ((bc as i64) << 4) | ((1 - ((vv >> 4) & 1)) << 3) | aaa);
  byte(op);
  if rmk == 0 { byte(192 | ((reg & 7) << 3) | (rm & 7)); return; }
  if VM_KIND == 1 {
    byte(5 | ((reg & 7) << 3));
    cp_at[ncp] = clen; cp_off[ncp] = VM_D; cp_tail[ncp] = VM_TAIL; ncp += 1; if ncp >= 262144 { fail("too many vector constants"); }
    u32_(0); return;
  }
  if VM_KIND == 2 { byte(4 | ((reg & 7) << 3)); byte(37); u32_(VM_D); return; }
  byte(132 | ((reg & 7) << 3));
  let mut ix = 4; if VM_I >= 0 { ix = VM_I & 7; }
  byte((VM_S << 6) | (ix << 3) | (VM_B & 7));
  u32_(VM_D);
}
// VEX (3-byte) for mask-register instructions
fn vex3(mm: i64, pp: i64, w: i64, l: i64, op: i64, reg: i64, vv: i64, rm: i64) {
  byte(196);
  byte(((1 - ((reg >> 3) & 1)) << 7) | 64 | ((1 - ((rm >> 3) & 1)) << 5) | mm);
  byte((w << 7) | (((~vv) & 15) << 3) | (l << 2) | pp);
  byte(op); byte(192 | ((reg & 7) << 3) | (rm & 7));
}
fn kmov_kr(k: i64, r: i64) { vex3(1, 0, 0, 0, 146, k, 0, r); }        // kmovw k, r32
fn kmov_rk(r: i64, k: i64) { vex3(1, 0, 0, 0, 147, r, 0, k); }        // kmovw r32, k
fn kand(d: i64, a: i64, b: i64) { vex3(1, 0, 0, 1, 65, d, a, b); }    // kandw
fn kandn(d: i64, a: i64, b: i64) { vex3(1, 0, 0, 1, 66, d, a, b); }   // kandnw: ~a & b
fn kor(d: i64, a: i64, b: i64) { vex3(1, 0, 0, 1, 69, d, a, b); }     // korw
fn kortest(a: i64, b: i64) { vex3(1, 0, 0, 0, 152, a, 0, b); }        // kortestw: ZF = (a|b) == 0
fn kmovk(d: i64, a: i64) { vex3(1, 0, 0, 0, 144, d, 0, a); }          // kmovw k, k
// constant pool (emitted after the code, read RIP-relative); 8-byte aligned entries
fn cp_find(v: u64) -> i64 {
  let mut i = 0;
  while i + 8 <= cplen {
    let mut x: u64 = 0; let mut j = 7;
    while j >= 0 { x = (x << 8) | (cpool[i + j] as u64); j -= 1; }
    if x == v { return i; }
    i += 8;
  }
  return -1;
}
fn cp_u64(v: u64) -> i64 {
  let f = cp_find(v); if f >= 0 { return f; }
  let at = cplen; let mut j: u64 = 0;
  while j < 8 { cpool[cplen] = ((v >> (8 * j)) & 255) as u8; cplen += 1; j += 1; }
  return at;
}
fn cp_iota(base: i64) -> i64 {   // 8 lanes base, base+1, ...
  while (cplen & 63) != 0 { cpool[cplen] = 0; cplen += 1; }
  let at = cplen; let mut k = 0;
  while k < 8 { let v = (base + k) as u64; let mut j: u64 = 0; while j < 8 { cpool[cplen] = ((v >> (8 * j)) & 255) as u8; cplen += 1; j += 1; } k += 1; }
  return at;
}
// ---------------------------------------------------------------- SIMD: lane-parallel loops
// A loop `while i < E { PRE; POST }` (i += 1 once, in POST) runs PRE for L consecutive
// values of i at once in zmm16..zmm31: varying values sit in vector lanes, uniform ones stay
// scalar, varying branches and inner loops run under k-masks. Every lane performs exactly the
// scalar operations (IEEE-exact, wrapping integers), so results are bit-identical. POST then
// runs as ordinary scalar code once per lane, in order, reading PRE's results lane by lane.
// PRE has no side effects and no lane-dependent traps, so the reordering is unobservable.
let MAX_PLANS = 4096;
let vplan = alloc<i64>(1048576);     // while node -> plan + 1
let mut nplans: i64 = 0;
let mut simd_off: bool = false;
let vp_loop = alloc<i64>(4096);
let vp_iv = alloc<i64>(4096);
let vp_npre = alloc<i64>(4096);
let vp_u = alloc<i64>(4096);
let vp_nv = alloc<i64>(4096);        // varying variables with registers
let vp_tmp = alloc<i64>(4096);       // stream plans: deepest vector temporary
let vp_need0 = alloc<i64>(4096);     // extracted variables: vp_need[vp_need0 .. vp_need0 + vp_nneed)
let vp_nneed = alloc<i64>(4096);
let vp_scr = alloc<i64>(4096);       // scratch offset in the vector area
let vp_tag = alloc<i64>(4096);
let vp_need = alloc<i64>(65536);
let mut nvneed: i64 = 0;
let mut vec_bytes: i64 = 64;         // vector scratch area (after the globals); 0..7: lane counter
let vmark = alloc<i64>(65536);       // == tag: varying in the plan being built/emitted
let vdecl = alloc<i64>(65536);       // == tag: declared inside PRE
let vprw = alloc<i64>(65536);        // == tag: assigned in PRE
let vprr = alloc<i64>(65536);        // == tag: read in PRE
let vpow = alloc<i64>(65536);        // == tag: assigned in POST
let vpor = alloc<i64>(65536);        // == tag: read in POST
let vald = alloc<i64>(65536);        // == tag: array (leader) loaded in PRE
let vast = alloc<i64>(65536);        // == tag: array (leader) stored in POST
let VREG = alloc<i64>(65536);        // varying variable -> first zmm of its group
let vred = alloc<i64>(65536);        // == tag: reduction variable (stream loops)
let vldx = alloc<i64>(65536);        // == tag: array (leader) loaded at an index other than i or i + c (c > 0)
let vldp = alloc<i64>(65536);        // == tag: loaded at i + c, c > 0; vldp_at: last statement doing so
let vldp_at = alloc<i64>(65536);
let vst_at = alloc<i64>(65536);      // first statement storing the leader
let mut VK_SNO: i64 = 0;             // statement number (stream checks, in execution order)
// element widths per leader: lane j of a[i] is the same memory as lane j of b[i] only when a and b
// have the same width (a view<u64> of bytes shares the leader of the bytes)
let vlw = alloc<i64>(65536);
let vlw_w = alloc<i64>(65536);
let vlwx = alloc<i64>(65536);        // == tag: leader accessed with two element widths
fn vnote_w(a: i64) {
  let L = arr_leader[a]; let w = vars[a].arr;
  if vlw[L] != vtag { vlw[L] = vtag; vlw_w[L] = w; } else if vlw_w[L] != w { vlwx[L] = vtag; }
}
// bounds guards of the plan being checked: a[i + c] with an unproven check runs vectorized only
// while i + c .. i + c + L - 1 is inside a (tested per block; otherwise the scalar loop takes over)
let vg_arr = alloc<i64>(64);
let vg_off = alloc<i64>(64);
let vg_offe = alloc<i64>(64);        // offset expression (U in a[i + U]) or -1
let mut VK_NG: i64 = 0;
let mut vtag: i64 = 0;
let mut VK_OK: bool = true;          // legality accumulator
let mut VK_LOOPS: i64 = 0;           // loops inside PRE
let mut VK_DEPTH: i64 = 0;           // deepest mask level needed
let mut VK_TMP: i64 = 0;             // deepest vector temporary needed
fn is_v(v: i64) -> bool { return vmark[v] == vtag; }
// element types a vector lane (64 bits) can load or store: 8-byte f64/i64/u64, narrower integers
fn velem_ok(w: i64, t: i64) -> bool {
  if w == 8 { return f64_type(t) || t == TY_I64 || t == TY_U64; }
  return (w == 1 || w == 2 || w == 4) && ty_int(t) && t != TY_BOOL && t != TY_ILIT && ty_width(t) == w;
}
fn vtrunc_op(w: i64) -> i64 { if w == 1 { return 50; } if w == 2 { return 52; } return 53; }   // vpmovqb/qw/qd (F3 0F38)
fn vext_op(t: i64) -> i64 {   // vpmov{z,s}x{b,w,d}q (0F38)
  if t == TY_U8 { return 50; } if t == TY_I8 { return 34; } if t == TY_U16 { return 52; } if t == TY_I16 { return 36; }
  if t == TY_U32 { return 53; } return 37;
}
// load L lanes of array a starting at index register ri into group d (mask level lvl)
fn vload(a: i64, t: i64, b: i64, ri: i64, d: i64, lvl: i64) {
  let w = vars[a].arr;
  let mut h = 0;
  while h < VU {
    vm_mem(b, ri, lg(w), 8 * w * h);
    if w == 8 { evx(1, 2, 1, 2, 111, d + h, 0, 1, 0, kreg(lvl, h), false, false); }   // vmovdqu64
    else { evx(2, 1, 0, 2, vext_op(t), d + h, 0, 1, 0, kreg(lvl, h), false, false); }
    h += 1;
  }
}
fn add_guard(a: i64, c: i64) -> bool {
  if c < -1048576 || c > 1048576 { return false; }
  let mut i = 0;
  while i < VK_NG { if vg_arr[i] == a && vg_off[i] == c && vg_offe[i] < 0 { return true; } i += 1; }
  if VK_NG >= 64 { return false; }
  vg_arr[VK_NG] = a; vg_off[VK_NG] = c; vg_offe[VK_NG] = -1; VK_NG += 1;
  return true;
}
fn add_guard_e(a: i64, u: i64) -> bool {
  let mut i = 0;
  while i < VK_NG { if vg_arr[i] == a && vg_offe[i] >= 0 && expr_same(vg_offe[i], u) { return true; } i += 1; }
  if VK_NG >= 64 { return false; }
  vg_arr[VK_NG] = a; vg_off[VK_NG] = 0; vg_offe[VK_NG] = u; VK_NG += 1;
  return true;
}
fn refs_v(e: i64) -> bool {
  if e < 0 { return false; }
  let k = nd[e].k;
  if k == N_VAR { return is_v(nd[e].var); }
  if k == N_CONST || k == N_ARR || k == N_NCPU { return false; }
  if k == N_CALL { let mut a = nd[e].a; while a >= 0 { if refs_v(a) { return true; } a = nd[a].next; } return false; }
  return refs_v(nd[e].a) || refs_v(nd[e].b);
}
// varying set: the induction variable, anything computed from a varying value or under varying control
fn vclass(s: i64, ctl: bool) -> bool {
  if s < 0 { return false; }
  let k = nd[s].k;
  let mut ch = false;
  if k == S_LET || k == S_ASSIGN || k == S_IRET {
    if (ctl || refs_v(nd[s].a)) && !is_v(nd[s].var) { vmark[nd[s].var] = vtag; ch = true; }
    return ch;
  }
  if k == S_BLOCK || k == S_INL { let mut c = nd[s].a; while c >= 0 { if vclass(c, ctl) { ch = true; } c = nd[c].next; } return ch; }
  if k == S_IF { let c2 = ctl || refs_v(nd[s].a); if vclass(nd[s].b, c2) { ch = true; } if vclass(nd[s].c, c2) { ch = true; } return ch; }
  if k == S_WHILE { return vclass(nd[s].b, ctl || refs_v(nd[s].a)); }
  return false;
}
fn vrec_reads(e: i64, post: bool) {
  if e < 0 { return; }
  let k = nd[e].k;
  if k == N_VAR { if post { vpor[nd[e].var] = vtag; } else { vprr[nd[e].var] = vtag; } return; }
  if k == N_LOAD {
    if !post { vald[arr_leader[nd[e].var]] = vtag; }
    vrec_reads(nd[e].a, post); return;
  }
  if k == N_CALL { let mut a = nd[e].a; while a >= 0 { vrec_reads(a, post); a = nd[a].next; } return; }
  if k == N_CONST || k == N_ARR || k == N_NCPU { return; }
  vrec_reads(nd[e].a, post); vrec_reads(nd[e].b, post);
}
fn is_pow2(v: u64) -> bool { return v != 0 && (v & (v - 1)) == 0; }
fn f64_type(t: i64) -> bool { return t == TY_F64; }
fn int8_type(t: i64) -> bool { return ty_int(t) && t != TY_ILIT; }
// can e be evaluated with all lanes active (no side effects, no lane-dependent trap)? t: temps in use
fn vexpr_ok(e: i64, t: i64, iv: i64) -> bool {
  if t + 1 > VK_TMP { VK_TMP = t + 1; }
  let k = nd[e].k;
  if k == N_CALL || k == N_NCPU || k == N_ARR { return false; }
  if !refs_v(e) {   // uniform: scalar code, then broadcast
    if has_call(e) { return false; }
    return f64_type(nd[e].ty) || int8_type(nd[e].ty) || k == N_CONST;
  }
  if k == N_VAR { let t2 = vars[nd[e].var].ty; return f64_type(t2) || int8_type(t2); }
  if k == N_LOAD {   // varying: contiguous a[i + c], check proven or guarded (constant c); narrow ints widen
    if nd[e].op > 0 || !velem_ok(vars[nd[e].var].arr, vars[nd[e].var].et) { return false; }
    if vars[nd[e].var].arr < 8 && !int8_type(nd[e].ty) { return false; }   // (a widening cast may retype the load)
    let x = nd[e].a;
    if nd[x].k == N_VAR && nd[x].var == iv { return nd[e].chk == 0 || add_guard(nd[e].var, 0); }
    let u = iv_u(x, iv);
    if u >= 0 { return nd[e].chk == 0 || add_guard_e(nd[e].var, u); }
    if nd[x].k == N_BIN && (nd[x].op == O_ADD || nd[x].op == O_SUB) && nd[nd[x].a].k == N_VAR && nd[nd[x].a].var == iv && !refs_v(nd[x].b) && !has_call(nd[x].b) {
      if nd[e].chk == 0 { return true; }
      if !is_const(nd[x].b) { return false; }
      let mut c = nd[nd[x].b].v as i64; if nd[x].op == O_SUB { c = 0 - c; }
      return add_guard(nd[e].var, c);
    }
    return false;
  }
  if k == N_UN {
    let op = nd[e].op;
    let a = nd[e].a;
    if !vexpr_ok(a, t, iv) { return false; }
    if op == U_NEG || op == U_NOT { return int8_type(nd[e].ty); }
    if op == U_I2D { return int8_type(nd[a].ty) && nd[a].ty != TY_U64; }
    if op == U_FNEG || op == U_SQRTD { return true; }
    if op >= U_SX8 && op <= U_ZX32 { return true; }
    return false;
  }
  if k == N_BIN {
    let op = nd[e].op;
    let a = nd[e].a; let b = nd[e].b;
    if is_cmp_op(op) || is_fcmp(op) || op == O_LAND || op == O_LOR { return false; }   // booleans only as conditions
    if op == O_FADD || op == O_FSUB || op == O_FMUL || op == O_FDIV {
      return vexpr_ok(a, t, iv) && vexpr_ok(b, t + 1, iv);
    }
    if is_fop(op) { return false; }   // f32
    if op == O_ADD || op == O_SUB || op == O_MUL || op == O_AND || op == O_OR || op == O_XOR {
      return vexpr_ok(a, t, iv) && vexpr_ok(b, t + 1, iv);
    }
    if op == O_SHL || op == O_SHR || op == O_SAR { return is_const(b) && vexpr_ok(a, t, iv); }
    if op == O_DIV || op == O_MOD || op == O_DIVU || op == O_MODU {
      if !is_const(b) || !is_pow2(nd[b].v) { return false; }
      if (op == O_DIV || op == O_MOD) && (nd[b].v as i64) <= 0 { return false; }
      return vexpr_ok(a, t, iv);
    }
    return false;
  }
  return false;
}
// a condition evaluated into mask level dst under mask level pm (OR-like nodes use fresh levels)
fn vcond_ok(e: i64, dst: i64, pm: i64, neg: bool, iv: i64) -> bool {
  if dst + 1 > VK_DEPTH { VK_DEPTH = dst + 1; }
  let k = nd[e].k;
  if !refs_v(e) { return !has_call(e); }
  if k == N_UN && nd[e].op == U_LNOT { return vcond_ok(nd[e].a, dst, pm, !neg, iv); }
  if k != N_BIN { return false; }
  let op = nd[e].op;
  if (op == O_LAND && !neg) || (op == O_LOR && neg) { return vcond_ok(nd[e].a, dst, pm, neg, iv) && vcond_ok(nd[e].b, dst, dst, neg, iv); }
  if op == O_LAND || op == O_LOR {
    let t = mx(dst, pm) + 1;
    return vcond_ok(nd[e].a, t, pm, neg, iv) && vcond_ok(nd[e].b, t + 1, pm, neg, iv);
  }
  if is_cmp_op(op) { return vexpr_ok(nd[e].a, 0, iv) && vexpr_ok(nd[e].b, 1, iv) && int8_type(nd[nd[e].a].ty); }
  if op >= O_FEQ && op <= O_FGE { return vexpr_ok(nd[e].a, 0, iv) && vexpr_ok(nd[e].b, 1, iv); }
  return false;
}
// PRE statement check. lvl: current mask level (-1: all lanes, uniform control); ld: loops entered
fn vpre_ok(s: i64, lvl: i64, ld: i64, iv: i64) -> bool {
  if s < 0 { return true; }
  let k = nd[s].k;
  if k == S_LET || k == S_ASSIGN || k == S_IRET {
    let v = nd[s].var;
    if k == S_LET { vdecl[v] = vtag; }
    if vdecl[v] != vtag { return false; }   // PRE writes only variables it declares
    vprw[v] = vtag; vrec_reads(nd[s].a, false);
    if has_call(nd[s].a) || (lvl >= 0 && has_trap(nd[s].a)) { return false; }
    if vars[v].reads == 0 { return !has_trap(nd[s].a); }
    if is_v(v) {
      let t = vars[v].ty;
      if !(f64_type(t) || int8_type(t)) { return false; }
      return vexpr_ok(nd[s].a, 0, iv);
    }
    if lvl >= 0 { return false; }
    return !has_call(nd[s].a);
  }
  if k == S_BLOCK { let mut c = nd[s].a; while c >= 0 { if !vpre_ok(c, lvl, ld, iv) { return false; } c = nd[c].next; } return true; }
  if k == S_INL {
    vdecl[nd[s].var] = vtag;
    let mut c = nd[s].a;
    while c >= 0 {
      if nd[c].k == S_IRET && nd[c].next >= 0 && lvl >= 0 { return false; }   // early return under a mask
      if !vpre_ok(c, lvl, ld, iv) { return false; }
      c = nd[c].next;
    }
    return true;
  }
  if k == S_IF {
    vrec_reads(nd[s].a, false);
    if lvl >= 0 && has_trap(nd[s].a) { return false; }
    if lvl < 0 && !refs_v(nd[s].a) {
      if has_call(nd[s].a) { return false; }
      return vpre_ok(nd[s].b, -1, ld, iv) && vpre_ok(nd[s].c, -1, ld, iv);
    }
    let nl = lvl + 1;
    if !vcond_ok(nd[s].a, nl, lvl, false, iv) || !vcond_ok(nd[s].a, nl, nl, false, iv) { return false; }
    return vpre_ok(nd[s].b, nl, ld, iv) && vpre_ok(nd[s].c, nl, ld, iv);
  }
  if k == S_WHILE {
    if nd[s].c >= 0 { return false; }
    VK_LOOPS += 1;
    vrec_reads(nd[s].a, false);
    if lvl < 0 && !refs_v(nd[s].a) {
      if has_call(nd[s].a) { return false; }
      return vpre_ok(nd[s].b, -1, ld + 1, iv);
    }
    if has_trap(nd[s].a) { return false; }   // re-evaluated under the loop's own mask
    let nl = lvl + 1;
    if !vcond_ok(nd[s].a, nl, lvl, false, iv) || !vcond_ok(nd[s].a, nl, nl, false, iv) { return false; }
    return vpre_ok(nd[s].b, nl, ld + 1, iv);
  }
  if k == S_BRK || k == S_CONT { return lvl < 0 && ld > 0; }
  return false;
}
// POST: scalar per lane; no calls, returns, par, or jumps out of the vectorized loop
fn vpost_ok(s: i64, ld: i64) -> bool {
  if s < 0 { return true; }
  let k = nd[s].k;
  if k == S_RET || k == S_PAR || k == S_ARR || k == S_SAVE { return false; }
  if (k == S_BRK || k == S_CONT) && ld == 0 { return false; }
  if k == S_LET || k == S_ASSIGN || k == S_IRET { vpow[nd[s].var] = vtag; }
  if k == S_STORE { vast[arr_leader[nd[s].var]] = vtag; }
  if k == S_EXPR || has_call(nd[s].a) || ((k == S_STORE || k == S_WRITE) && has_call(nd[s].b)) { return false; }
  if k <= N_ARR { return false; }
  vrec_reads(nd[s].a, true);
  if k == S_STORE || k == S_WRITE { vrec_reads(nd[s].b, true); }
  if k == S_STORE || k == S_WRITE { if nd[s].var >= 0 { vpor[vars[nd[s].var].basev] = vtag; } }
  if k == S_IF { return vpost_ok(nd[s].b, ld) && vpost_ok(nd[s].c, ld); }
  if k == S_WHILE { if nd[s].c >= 0 { return false; } return vpost_ok(nd[s].b, ld + 1); }
  if k == S_BLOCK || k == S_INL { let mut c = nd[s].a; while c >= 0 { if !vpost_ok(c, ld) { return false; } c = nd[c].next; } }
  return true;
}
let vp_v0 = alloc<i64>(4096);         // varying variables of plan p: vp_vlist[vp_v0 .. vp_v0 + vp_nv)
let vp_vlist = alloc<i64>(65536);
let vp_vreg = alloc<i64>(65536);
let mut nvlist: i64 = 0;
fn pre_classify(body: i64, k: i64, iv: i64) {
  vtag += 1;
  vmark[iv] = vtag;
  let mut changed = true;
  while changed {
    changed = false;
    let mut c = nd[body].a; let mut i = 0;
    while c >= 0 && i < k { if vclass(c, false) { changed = true; } c = nd[c].next; i += 1; }
  }
}
fn pre_check(body: i64, k: i64, iv: i64) -> bool {
  VK_LOOPS = 0; VK_DEPTH = 0; VK_TMP = 0; VK_NG = 0;
  let mut c = nd[body].a; let mut i = 0;
  while c >= 0 && i < k { if !vpre_ok(c, -1, 0, iv) { return false; } c = nd[c].next; i += 1; }
  return true;
}
// loop bound E: a constant, a variable v or v +/- constant (v: not i, not in an xmm register)
fn bound_var(en: i64, iv: i64) -> i64 {
  let mut x = en;
  if nd[x].k == N_BIN && (nd[x].op == O_ADD || nd[x].op == O_SUB) && is_const(nd[x].b) { x = nd[x].a; }
  if nd[x].k == N_VAR && nd[x].var != iv && vars[nd[x].var].xr < 0 && ty_int(vars[nd[x].var].ty) { return nd[x].var; }
  return -1;
}
// E into rcx, wrapping exactly as the scalar condition computes it (may use rax)
fn bound_rcx(en: i64) {
  if is_const(en) { mov_ri(RCX, nd[en].v); return; }
  if nd[en].k == N_VAR { loc(nd[en].var); load(RCX, OK, ORR, OI); return; }
  loc(nd[nd[en].a].var); load(RCX, OK, ORR, OI);
  let mut d = A_ADD; if nd[en].op == O_SUB { d = A_SUB; }
  alui(d, RCX, nd[nd[en].b].v);
}
fn plan_loop(s: i64) {
  if simd_off || nplans >= MAX_PLANS || nd[s].c >= 0 { return; }
  let cnd = nd[s].a;
  if nd[cnd].k != N_BIN || (nd[cnd].op != O_LT && nd[cnd].op != O_LE) { return; }
  let mut ivn = nd[cnd].a; let en = nd[cnd].b;
  PLAN_CADD = 0;
  if nd[ivn].k == N_BIN && nd[ivn].op == O_ADD && is_const(nd[ivn].b) && (nd[nd[ivn].b].v as i64) > 0 && (nd[nd[ivn].b].v as i64) < 1048576 {   // i + c < E
    PLAN_CADD = nd[nd[ivn].b].v as i64; ivn = nd[ivn].a;
  }
  if nd[ivn].k != N_VAR { return; }
  let iv = nd[ivn].var;
  if vars[iv].ty != TY_I64 || vars[iv].xr >= 0 { return; }
  if !(is_const(en) || bound_var(en, iv) >= 0) { return; }
  if count_assign(s, iv) != 1 { return; }
  if bound_var(en, iv) >= 0 && count_assign(nd[s].b, bound_var(en, iv)) != 0 { return; }
  let body = nd[s].b;
  if nd[body].k != S_BLOCK { return; }
  IVU_BODY = body;
  let mut inc = -1;
  let mut nbefore = 0;
  let mut c = nd[body].a;
  while c >= 0 { if nd[c].k == S_ASSIGN && is_inc1(c, iv) { inc = c; break; } nbefore += 1; c = nd[c].next; }
  if inc < 0 { return; }
  // PRE: the longest prefix of statements (before the increment) that can run lane-parallel
  let mut npre = 0;
  while npre < nbefore {
    pre_classify(body, npre + 1, iv);
    if !pre_check(body, npre + 1, iv) { break; }
    npre += 1;
  }
  if npre > 0 { pre_classify(body, npre, iv); }
  if npre == 0 || !pre_check(body, npre, iv) || VK_LOOPS == 0 { plan_stream(s, body, inc, iv, nbefore); return; }
  let t0 = vtag;
  c = nd[body].a;
  let mut i = 0;
  while i < npre { c = nd[c].next; i += 1; }
  while c >= 0 { if !vpost_ok(c, 0) { return; } c = nd[c].next; }
  // cross checks
  let mut vv = 0;
  let mut nvar = 0;
  while vv < nv {
    if vprw[vv] == t0 && vdecl[vv] != t0 { return; }                       // PRE writes only its own variables
    if vprr[vv] == t0 && vdecl[vv] != t0 && vv != iv && vpow[vv] == t0 { return; }   // loop-carried input
    if vpow[vv] == t0 && vv != iv && (vprr[vv] == t0 || vprw[vv] == t0) { return; }
    if vald[vv] == t0 && vast[vv] == t0 { return; }                        // POST stores what PRE loads
    if is_v(vv) && vv != iv && vdecl[vv] != t0 { return; }
    if is_v(vv) { let t = vars[vv].ty; if !(f64_type(t) || int8_type(t)) { return; } nvar += 1; }
    vv += 1;
  }
  // registers: groups of U zmm registers among zmm16..zmm31; masks k1..k6 (k7 = all lanes)
  let mut u = 2;
  if (nvar + VK_TMP + 1) * 2 > 16 || VK_DEPTH * 2 > 6 { u = 1; }
  if (nvar + VK_TMP + 1) * u > 16 || VK_DEPTH * u > 6 { return; }
  if nvlist + nvar > 65536 || nvneed + nvar > 65536 { return; }
  if !plan_extra(false, t0) { return; }
  let p = nplans; nplans += 1;
  vplan[s] = p + 1; vp_cadd[p] = PLAN_CADD;
  vp_loop[p] = s; vp_iv[p] = iv; vp_npre[p] = npre; vp_u[p] = u; vp_nv[p] = nvar;
  vp_need0[p] = nvneed; vp_v0[p] = nvlist;
  let mut g = 0;
  vv = 0;
  while vv < nv {
    if is_v(vv) {
      vp_vlist[nvlist] = vv; vp_vreg[nvlist] = 16 + g * u; nvlist += 1; g += 1;
      if vpor[vv] == t0 && vv != iv { vp_need[nvneed] = vv; nvneed += 1; }
    }
    vv += 1;
  }
  vp_nneed[p] = nvneed - vp_need0[p];
  vp_scr[p] = vec_bytes;
  vec_bytes += vp_nneed[p] * 64 * u;
}
// per plan: bounds guards, array pairs that must not share memory (checked at run time outside
// main, where distinct arrays can be the same argument), stream loops and their reductions
let vp_g0 = alloc<i64>(4096);
let vp_ng = alloc<i64>(4096);
let vgl_arr = alloc<i64>(65536);
let vgl_off = alloc<i64>(65536);
let vgl_offe = alloc<i64>(65536);
let mut nvgl: i64 = 0;
let vp_a0 = alloc<i64>(4096);
let vp_na = alloc<i64>(4096);
let val_s = alloc<i64>(65536);
let val_l = alloc<i64>(65536);
let mut nval: i64 = 0;
let vp_stream = alloc<bool>(4096);
let vp_r0 = alloc<i64>(4096);
let vp_nr = alloc<i64>(4096);
let vrl_var = alloc<i64>(65536);
let vrl_op = alloc<i64>(65536);
let vredop = alloc<i64>(65536);
let mut nvrl: i64 = 0;
let vst_tmp = alloc<i64>(64);
let vld_tmp = alloc<i64>(64);
// fill plan nplans's guards and alias pairs from the current tags (t0); false: too many
fn plan_extra(stream: bool, t0: i64) -> bool {
  let p = nplans;
  if nvgl + VK_NG > 65536 { return false; }
  vp_g0[p] = nvgl; vp_ng[p] = VK_NG;
  let mut i = 0;
  while i < VK_NG { vgl_arr[nvgl + i] = vg_arr[i]; vgl_off[nvgl + i] = vg_off[i]; vgl_offe[nvgl + i] = vg_offe[i]; i += 1; }
  // stored leaders x leaders loaded where a different memory layout could see another lane's store
  let mut ns = 0; let mut nl = 0;
  let mut v = 0;
  while v < nv {
    if vars[v].arr != 0 && arr_leader[v] == v {
      if vast[v] == t0 { if ns >= 64 { return false; } vst_tmp[ns] = v; ns += 1; }
      if (stream && vlw[v] == t0) || (!stream && vald[v] == t0) { if nl >= 64 { return false; } vld_tmp[nl] = v; nl += 1; }
    }
    v += 1;
  }
  if nval + ns * nl > 65536 { return false; }
  vp_a0[p] = nval; vp_na[p] = 0;
  i = 0;
  while i < ns {
    let mut j = 0;
    while j < nl {
      let S = vst_tmp[i]; let L = vld_tmp[j];
      // stream loops: lane j of S[i] and L[i] is the same memory only for equal widths, both at index i
      let need = S != L && (!stream || vldx[L] == t0 || vldp[L] == t0 || vlw_w[L] != vlw_w[S] || vlwx[L] == t0);
      if need { if vp_na[p] >= 16 { return false; } val_s[nval] = S; val_l[nval] = L; nval += 1; vp_na[p] += 1; }
      j += 1;
    }
    i += 1;
  }
  nvgl += VK_NG;
  vp_stream[p] = stream; vp_r0[p] = nvrl; vp_nr[p] = 0;
  return true;
}
fn ex_reads(e: i64, v: i64) -> i64 {
  if e < 0 { return 0; }
  let k = nd[e].k;
  if k == N_VAR { return (nd[e].var == v) as i64; }
  if k == N_CONST || k == N_ARR || k == N_NCPU { return 0; }
  if k == N_CALL { let mut cnt = 0; let mut a = nd[e].a; while a >= 0 { cnt += ex_reads(a, v); a = nd[a].next; } return cnt; }
  return ex_reads(nd[e].a, v) + ex_reads(nd[e].b, v);
}
fn st_reads(s: i64, v: i64) -> i64 {
  if s < 0 { return 0; }
  let k = nd[s].k;
  if k == S_BLOCK || k == S_INL { let mut cnt = 0; let mut c = nd[s].a; while c >= 0 { cnt += st_reads(c, v); c = nd[c].next; } return cnt; }
  if k == S_IF { return ex_reads(nd[s].a, v) + st_reads(nd[s].b, v) + st_reads(nd[s].c, v); }
  if k == S_WHILE { return ex_reads(nd[s].a, v) + st_reads(nd[s].b, v); }
  if k == S_STORE || k == S_WRITE || k == S_SAVE { return ex_reads(nd[s].a, v) + ex_reads(nd[s].b, v); }
  return ex_reads(nd[s].a, v);
}
// loads not at index i (stream loops): their arrays must not be stored in the loop
fn vscan_loads(e: i64, iv: i64) {
  if e < 0 { return; }
  let k = nd[e].k;
  if k == N_LOAD {
    let x = nd[e].a; let L = arr_leader[nd[e].var];
    vnote_w(nd[e].var);
    if vstit[L] == vtag && !(nd[vsti[L]].k == N_VAR && nd[vsti[L]].var == iv) {   // stored at i + U: only that index is lane-local
      if nd[e].op > 0 || !expr_same(x, vsti[L]) { vldx[L] = vtag; }
      vscan_loads(x, iv); return;
    }
    if nd[e].op > 0 { vldx[L] = vtag; }
    else if nd[x].k == N_VAR && nd[x].var == iv { }
    else if nd[x].k == N_BIN && nd[x].op == O_ADD && nd[nd[x].a].k == N_VAR && nd[nd[x].a].var == iv && is_const(nd[x].b) && (nd[nd[x].b].v as i64) > 0 {
      if vldp[L] != vtag || vldp_at[L] < VK_SNO { vldp_at[L] = VK_SNO; }
      vldp[L] = vtag;
    }
    else { vldx[L] = vtag; }
    vscan_loads(x, iv); return;
  }
  if k == N_CONST || k == N_VAR || k == N_ARR || k == N_NCPU { return; }
  if k == N_CALL { let mut a = nd[e].a; while a >= 0 { vscan_loads(a, iv); a = nd[a].next; } return; }
  vscan_loads(nd[e].a, iv); vscan_loads(nd[e].b, iv);
}
// the index each stored array is stored at (one per leader in a stream loop)
let vsti = alloc<i64>(65536);
let vstit = alloc<i64>(65536);
let vstib = alloc<i64>(65536);
fn st_prescan(s: i64) {
  if s < 0 { return; }
  let k = nd[s].k;
  if k == S_BLOCK { let mut c = nd[s].a; while c >= 0 { st_prescan(c); c = nd[c].next; } return; }
  if k == S_IF { st_prescan(nd[s].b); st_prescan(nd[s].c); return; }
  if k == S_STORE {
    let L = arr_leader[nd[s].var];
    if vstit[L] != vtag { vstit[L] = vtag; vsti[L] = nd[s].a; } else if !expr_same(vsti[L], nd[s].a) { vstib[L] = vtag; }
  }
}
// hidden immutable copies `let t = i` (compound stores a[i] op= e index a[t]): read i instead
fn ivcopy_e(e: i64, t: i64, iv: i64) {
  if e < 0 { return; }
  let k = nd[e].k;
  if k == N_VAR { if nd[e].var == t { nd[e].var = iv; vars[t].reads -= 1; vars[iv].reads += 1; } return; }
  if k == N_CONST || k == N_ARR || k == N_NCPU { return; }
  if k == N_CALL { let mut a = nd[e].a; while a >= 0 { ivcopy_e(a, t, iv); a = nd[a].next; } return; }
  ivcopy_e(nd[e].a, t, iv); ivcopy_e(nd[e].b, t, iv);
}
fn ivcopy_s(s: i64, t: i64, iv: i64) {
  if s < 0 { return; }
  let k = nd[s].k;
  if k == S_BLOCK || k == S_INL { let mut c = nd[s].a; while c >= 0 { ivcopy_s(c, t, iv); c = nd[c].next; } return; }
  if k == S_IF { ivcopy_e(nd[s].a, t, iv); ivcopy_s(nd[s].b, t, iv); ivcopy_s(nd[s].c, t, iv); return; }
  if k == S_WHILE { ivcopy_e(nd[s].a, t, iv); ivcopy_s(nd[s].b, t, iv); return; }
  if k == S_STORE || k == S_WRITE || k == S_SAVE { ivcopy_e(nd[s].a, t, iv); ivcopy_e(nd[s].b, t, iv); return; }
  if k == S_LET && nd[s].var == t { return; }
  ivcopy_e(nd[s].a, t, iv);
}
fn inv_u(e: i64, body: i64, iv: i64) -> bool {
  if e < 0 { return true; }
  let k = nd[e].k;
  if k == N_LOAD || k == N_CALL || k == N_NCPU { return false; }
  if k == N_VAR { return nd[e].var != iv && count_assign(body, nd[e].var) == 0 && vars[nd[e].var].xr < 0 && ty_int(vars[nd[e].var].ty); }
  if k == N_CONST || k == N_ARR { return k == N_CONST; }
  if has_trap(e) { return false; }
  return inv_u(nd[e].a, body, iv) && inv_u(nd[e].b, body, iv);
}
let mut IVU_BODY: i64 = -1;          // loop body for iv_u checks (stream planning)
fn iv_u(x: i64, iv: i64) -> i64 {    // x = iv + U or U + iv: U, else -1
  if nd[x].k != N_BIN || nd[x].op != O_ADD || IVU_BODY < 0 { return -1; }
  if nd[nd[x].a].k == N_VAR && nd[nd[x].a].var == iv && inv_u(nd[x].b, IVU_BODY, iv) && !is_const(nd[x].b) { return nd[x].b; }
  if nd[nd[x].b].k == N_VAR && nd[nd[x].b].var == iv && inv_u(nd[x].a, IVU_BODY, iv) && !is_const(nd[x].a) { return nd[x].a; }
  return -1;
}
fn ivcopy_x(e: i64, t: i64, x: i64) {   // N_VAR t -> a copy of x
  if e < 0 { return; }
  let k = nd[e].k;
  if k == N_VAR { if nd[e].var == t { let cl = clone_expr(x); copy_node(e, cl); vars[t].reads -= 1; } return; }
  if k == N_CONST || k == N_ARR || k == N_NCPU { return; }
  if k == N_CALL { let mut a = nd[e].a; while a >= 0 { ivcopy_x(a, t, x); a = nd[a].next; } return; }
  ivcopy_x(nd[e].a, t, x); ivcopy_x(nd[e].b, t, x);
}
fn ivcopy_sx(s: i64, t: i64, x: i64) {
  if s < 0 { return; }
  let k = nd[s].k;
  if k == S_BLOCK || k == S_INL { let mut c = nd[s].a; while c >= 0 { ivcopy_sx(c, t, x); c = nd[c].next; } return; }
  if k == S_IF { ivcopy_x(nd[s].a, t, x); ivcopy_sx(nd[s].b, t, x); ivcopy_sx(nd[s].c, t, x); return; }
  if k == S_STORE || k == S_WRITE || k == S_SAVE { ivcopy_x(nd[s].a, t, x); ivcopy_x(nd[s].b, t, x); return; }
  if k == S_LET && nd[s].var == t { return; }
  if k == S_WHILE { return; }
  ivcopy_x(nd[s].a, t, x);
}
fn ivcopies(body: i64, s: i64, iv: i64) {
  if s < 0 { return; }
  let k = nd[s].k;
  if k == S_BLOCK { let mut c = nd[s].a; while c >= 0 { ivcopies(body, c, iv); c = nd[c].next; } return; }
  if k == S_LET && nd[nd[s].a].k == N_VAR && nd[nd[s].a].var == iv && vars[nd[s].var].ty == TY_I64 && count_assign(body, nd[s].var) == 1 { ivcopy_s(body, nd[s].var, iv); }
  else if k == S_LET && vars[nd[s].var].ty == TY_I64 && count_assign(body, nd[s].var) == 1 && iv_u(nd[s].a, iv) >= 0 { ivcopy_sx(body, nd[s].var, nd[s].a); }
}
// a statement of a stream loop: lane-parallel lets, vector stores a[i] = e / a[i] op= e (8-byte
// elements), integer reductions s op= e (op: + - & | ^; wrapping, so any grouping gives the same sum)
fn sst_ok(s: i64, iv: i64, lvl: i64) -> bool {
  let k = nd[s].k;
  if k == S_BLOCK { let mut c = nd[s].a; while c >= 0 { if !sst_ok(c, iv, lvl) { return false; } c = nd[c].next; } return true; }
  if k == S_IF {
    if lvl < 0 && minmax_ok(s, iv) { return true; }
    let cnd = nd[s].a;
    if has_call(cnd) { return false; }
    VK_SNO += 1;
    vscan_loads(cnd, iv);
    if !refs_v(cnd) {   // uniform: an ordinary branch around lane-parallel code (loop-invariant, so no lane order issue)
      if lvl >= 0 || has_trap(cnd) { return false; }
      return sst_ok(nd[s].b, iv, -1) && (nd[s].c < 0 || sst_ok(nd[s].c, iv, -1));
    }
    if !vdead_ok(cnd) { return false; }
    let nl = lvl + 1;
    if !vcond_ok(cnd, nl, lvl, false, iv) || !vcond_ok(cnd, nl, nl, false, iv) { return false; }
    return sst_ok(nd[s].b, iv, nl) && (nd[s].c < 0 || sst_ok(nd[s].c, iv, nl));
  }
  if k == S_STORE {
    let a = nd[s].var;
    let et = vars[a].et;
    if nd[s].c >= 0 || !velem_ok(vars[a].arr, et) || vars[a].ro != 0 || has_call(nd[s].b) { return false; }
    let x = nd[s].a;
    let at_i = nd[x].k == N_VAR && nd[x].var == iv;
    if !at_i && iv_u(x, iv) < 0 { return false; }
    if vstib[arr_leader[a]] == vtag { return false; }
    if nd[s].op >= 0 && !(et != TY_F64 && is_alu_op(nd[s].op)) { return false; }
    if nd[s].chk != 0 { if at_i { if !add_guard(a, 0) { return false; } } else if !add_guard_e(a, iv_u(x, iv)) { return false; } }
    VK_SNO += 1;
    vnote_w(a);
    if vast[arr_leader[a]] != vtag { vst_at[arr_leader[a]] = VK_SNO; }
    vast[arr_leader[a]] = vtag;
    vscan_loads(nd[s].b, iv);
    if lvl >= 0 && !vdead_ok(nd[s].b) { return false; }   // under a mask: no uniform traps
    if !vexpr_ok(nd[s].b, 1, iv) { return false; }
    if VK_TMP < 2 { VK_TMP = 2; }
    return true;
  }
  if k == S_ASSIGN && vdecl[nd[s].var] != vtag {
    let v = nd[s].var; let e = nd[s].a;
    if (vars[v].ty != TY_I64 && vars[v].ty != TY_U64) || vars[v].xr >= 0 || v == iv || vars[v].glob != 0 { return false; }
    if nd[e].k != N_BIN || !is_alu_op(nd[e].op) || nd[nd[e].a].k != N_VAR || nd[nd[e].a].var != v { return false; }
    if vred[v] == vtag || refs(nd[e].b, v) || has_call(nd[e].b) { return false; }
    vred[v] = vtag; vredop[v] = nd[e].op; vmark[v] = vtag;   // the accumulator is a lane vector
    VK_SNO += 1;
    vscan_loads(nd[e].b, iv);
    if lvl >= 0 && !vdead_ok(nd[e].b) { return false; }
    return vexpr_ok(nd[e].b, 1, iv);
  }
  if k == S_LET || k == S_ASSIGN {
    VK_SNO += 1;
    vscan_loads(nd[s].a, iv);
    // an unused varying value: its only possible traps are loads, which the guards cover
    if k == S_LET && vars[nd[s].var].reads == 0 && refs_v(nd[s].a) && !has_call(nd[s].a) && vdead_ok(nd[s].a) { vdecl[nd[s].var] = vtag; vprw[nd[s].var] = vtag; return vexpr_ok(nd[s].a, 0, iv); }
    if lvl >= 0 {   // under a mask: varying values merge into their lanes; nothing may trap
      let v = nd[s].var;
      if k == S_LET { vdecl[v] = vtag; }
      if vdecl[v] != vtag || has_call(nd[s].a) || !vdead_ok(nd[s].a) { return false; }
      vprw[v] = vtag;
      if !is_v(v) { return false; }
      let t = vars[v].ty; if !(f64_type(t) || int8_type(t)) { return false; }
      return vexpr_ok(nd[s].a, 0, iv);
    }
    return vpre_ok(s, -1, 0, iv);
  }
  return false;
}
// max/min reductions: `if X > m { m = X; }` (also >=, <, <=, either side, unsigned forms)
let RED_MAXS = 901; let RED_MAXU = 902; let RED_MINS = 903; let RED_MINU = 904;
fn expr_same(a: i64, b: i64) -> bool {
  if nd[a].k != nd[b].k || nd[a].op != nd[b].op || nd[a].var != nd[b].var || nd[a].ty != nd[b].ty { return false; }
  let k = nd[a].k;
  if k == N_CONST { return nd[a].v == nd[b].v; }
  if k == N_VAR { return true; }
  if k == N_LOAD { return expr_same(nd[a].a, nd[b].a); }
  if k == N_UN { return expr_same(nd[a].a, nd[b].a); }
  if k == N_BIN { return expr_same(nd[a].a, nd[b].a) && expr_same(nd[a].b, nd[b].b); }
  return false;
}
let mut MM_VAR: i64 = -1;
let mut MM_X: i64 = -1;
fn minmax_kind(s: i64) -> i64 {   // RED_* or 0; sets MM_VAR, MM_X
  if nd[s].k != S_IF || nd[s].c >= 0 { return 0; }
  let mut b = nd[s].b;
  if nd[b].k == S_BLOCK { b = nd[b].a; if b < 0 || nd[b].next >= 0 { return 0; } }
  if nd[b].k != S_ASSIGN { return 0; }
  let m = nd[b].var; let x = nd[b].a; let c = nd[s].a;
  if nd[c].k != N_BIN || has_call(x) { return 0; }
  let op = nd[c].op;
  let mut gt = false;
  if op == O_GT || op == O_GE || op == O_GTU || op == O_GEU { gt = true; }
  else if !(op == O_LT || op == O_LE || op == O_LTU || op == O_LEU) { return 0; }
  let uns = op == O_GTU || op == O_GEU || op == O_LTU || op == O_LEU;
  let ca = nd[c].a; let cb = nd[c].b;
  let mut mx_ = false;
  if nd[cb].k == N_VAR && nd[cb].var == m && expr_same(ca, x) { mx_ = gt; }        // X > m: max
  else if nd[ca].k == N_VAR && nd[ca].var == m && expr_same(cb, x) { mx_ = !gt; }  // m < X: max
  else { return 0; }
  MM_VAR = m; MM_X = x;
  if mx_ { if uns { return RED_MAXU; } return RED_MAXS; }
  if uns { return RED_MINU; } return RED_MINS;
}
fn minmax_ok(s: i64, iv: i64) -> bool {
  let kind = minmax_kind(s);
  if kind == 0 { return false; }
  let v = MM_VAR; let x = MM_X;
  if (vars[v].ty != TY_I64 && vars[v].ty != TY_U64) || vars[v].xr >= 0 || v == iv || vars[v].glob != 0 || vdecl[v] == vtag || vred[v] == vtag { return false; }
  if refs(x, v) || !refs_v(x) || !vdead_ok(x) { return false; }
  if (kind == RED_MAXU || kind == RED_MINU) != (vars[v].ty == TY_U64) { return false; }
  vred[v] = vtag; vredop[v] = kind; vmark[v] = vtag;
  VK_SNO += 1;
  vscan_loads(nd[s].a, iv);
  return vexpr_ok(x, 1, iv);
}
// an unused varying value can be skipped: uniform parts cannot trap, varying loads are guarded
fn vdead_ok(e: i64) -> bool {
  if !refs_v(e) { return !has_trap(e); }
  let k = nd[e].k;
  if k == N_VAR || k == N_LOAD { return true; }
  if k == N_UN { return vdead_ok(nd[e].a); }
  if k == N_BIN { return vdead_ok(nd[e].a) && vdead_ok(nd[e].b); }
  return false;
}
// loops without inner loops: every statement before the final i += 1 runs on L lanes at once
fn plan_stream(s: i64, body: i64, inc: i64, iv: i64, nb: i64) {
  if nd[inc].next >= 0 || nb == 0 { return; }
  let mut c = nd[body].a; let mut i = 0;
  while i < nb { ivcopies(body, c, iv); c = nd[c].next; i += 1; }
  if bplan(s, body, iv, nb) { return; }
  pre_classify(body, nb, iv);
  VK_LOOPS = 0; VK_DEPTH = 0; VK_TMP = 0; VK_NG = 0; VK_SNO = 0;
  let t0 = vtag;
  c = nd[body].a; i = 0;
  while i < nb { st_prescan(c); c = nd[c].next; i += 1; }
  c = nd[body].a; i = 0;
  while i < nb { if !sst_ok(c, iv, -1) { return; } c = nd[c].next; i += 1; }
  if VK_LOOPS != 0 { return; }
  let mut nvar = 0; let mut nst = 0; let mut nred = 0;
  let mut vv = 0;
  while vv < nv {
    if vprw[vv] == t0 && vdecl[vv] != t0 { return; }
    if vast[vv] == t0 { nst += 1; if vldx[vv] == t0 || vlwx[vv] == t0 || (vldp[vv] == t0 && vldp_at[vv] > vst_at[vv]) { return; } }
    if vred[vv] == t0 { if count_assign(body, vv) != 1 || st_reads(body, vv) != 1 { return; } nred += 1; }
    if is_v(vv) && vv != iv && vdecl[vv] != t0 && vred[vv] != t0 { return; }
    if is_v(vv) && (vars[vv].reads != 0 || vv == iv) { let t = vars[vv].ty; if !(f64_type(t) || int8_type(t)) { return; } nvar += 1; }
    vv += 1;
  }
  if nst + nred == 0 { return; }
  let mut u = 2;
  if (nvar + VK_TMP + 1) * 2 > 16 || VK_DEPTH * 2 > 6 { u = 1; }
  if (nvar + VK_TMP + 1) * u > 16 || VK_DEPTH * u > 6 { return; }
  if nvlist + nvar > 65536 || nvrl + nred > 65536 { return; }
  // an array of constant length shorter than one block: the vector loop could never run
  let mut sv = 0;
  while sv < nv {
    if vars[sv].arr != 0 && (vast[sv] == t0 || vlw[sv] == t0) {
      let lv = vars[sv].lenv;
      if lv < 0 && vars[sv].alen < 8 * u { return; }
      if lv >= 0 && vars[lv].isconst != 0 && (vars[lv].cval as i64) < 8 * u { return; }
    }
    sv += 1;
  }
  if !plan_extra(true, t0) { return; }
  let p = nplans; nplans += 1;
  vplan[s] = p + 1; vp_cadd[p] = PLAN_CADD;
  vp_loop[p] = s; vp_iv[p] = iv; vp_npre[p] = nb; vp_u[p] = u; vp_nv[p] = nvar; vp_tmp[p] = VK_TMP;
  vp_need0[p] = nvneed; vp_nneed[p] = 0; vp_v0[p] = nvlist; vp_scr[p] = vec_bytes;
  let mut g = 0;
  vv = 0;
  while vv < nv {
    if is_v(vv) && (vars[vv].reads != 0 || vv == iv) { vp_vlist[nvlist] = vv; vp_vreg[nvlist] = 16 + g * u; nvlist += 1; g += 1; }
    if vred[vv] == t0 { vrl_var[nvrl] = vv; vrl_op[nvrl] = vredop[vv]; nvrl += 1; vp_nr[p] += 1; }
    vv += 1;
  }
}
// ---- byte lanes: loops over u8/i8 arrays only run 64 iterations per zmm register
// Values are tracked as bytes. A value is "exact" when the 64-bit value the program computes fits
// the byte (class 1: unsigned 0..255, 2: signed -128..127, 3: both, 0: only its low byte is known).
// Comparisons need exact operands of one signedness; stores and wrapping + - & | ^ need only low bytes.
let vp_byte = alloc<bool>(4096);
let vp_cadd = alloc<i64>(4096);       // loop test i + c < E: c
let mut PLAN_CADD: i64 = 0;
let vp_brec = alloc<i64>(4096);       // byte plans: the recurrence flag or -1
let bclass = alloc<i64>(65536);      // byte let temporaries: class
let vbyte = alloc<i64>(65536);       // == tag: byte let temporary
let vcnt = alloc<i64>(65536);        // == tag: count reduction (s += k / s -= k with constant k)
fn bx(e: i64, iv: i64) -> i64 {      // class, or -1 when e is not a byte-lane value
  let k = nd[e].k;
  if k == N_CONST {
    let v = nd[e].v as i64;
    if v >= 0 && v <= 127 { return 3; } if v >= 128 && v <= 255 { return 1; } if v >= -128 && v < 0 { return 2; }
    return 0;
  }
  if k == N_LOAD {
    if nd[e].op > 0 || vars[nd[e].var].arr != 1 { return -1; }
    let x = nd[e].a;
    if !refs_v(x) && !has_call(x) && nd[e].chk == 0 && !has_trap(x) {   // the same byte for every lane
      let et0 = vars[nd[e].var].et;
      if et0 == TY_U8 { return 1; } if et0 == TY_I8 { return 2; } return -1;
    }
    if !(nd[x].k == N_VAR && nd[x].var == iv) && !(nd[x].k == N_BIN && nd[x].op == O_ADD && nd[nd[x].a].k == N_VAR && nd[nd[x].a].var == iv && is_const(nd[x].b)) { return -1; }
    if nd[e].chk != 0 { let mut c = 0; if nd[x].k == N_BIN { c = nd[nd[x].b].v as i64; } if !add_guard(nd[e].var, c) { return -1; } }
    let et = vars[nd[e].var].et;
    if et == TY_U8 { return 1; } if et == TY_I8 { return 2; } return -1;
  }
  if k == N_VAR { if vbyte[nd[e].var] == vtag { return bclass[nd[e].var]; } return -1; }
  if k == N_UN {
    let a = bx(nd[e].a, iv); if a < 0 { return -1; }
    let op = nd[e].op;
    if op == U_ZX8 { return 1; } if op == U_SX8 { return 2; }
    if op >= U_SX8 && op <= U_ZX32 { if a == 0 { return 0; } if op == U_ZX16 || op == U_ZX32 { if a == 2 { return 0; } } return a; }
    if op == U_NOT || op == U_NEG { return 0; }
    return -1;
  }
  if k == N_BIN {
    let op = nd[e].op;
    if !(op == O_ADD || op == O_SUB || op == O_AND || op == O_OR || op == O_XOR) { return -1; }
    let a = bx(nd[e].a, iv); let b = bx(nd[e].b, iv);
    if a < 0 || b < 0 { return -1; }
    if op == O_ADD || op == O_SUB { return 0; }
    if (a == 1 || a == 3) && (b == 1 || b == 3) { if a == 3 && b == 3 { return 3; } return 1; }
    if (a == 2 || a == 3) && (b == 2 || b == 3) { if a == 3 && b == 3 { return 3; } return 2; }
    return 0;
  }
  return -1;
}
fn bxc(e: i64) -> i64 {   // class of an accepted byte-lane value (codegen; no checks)
  let k = nd[e].k;
  if k == N_CONST { let v = nd[e].v as i64; if v >= 0 && v <= 127 { return 3; } if v >= 128 && v <= 255 { return 1; } if v >= -128 && v < 0 { return 2; } return 0; }
  if k == N_LOAD { if vars[nd[e].var].et == TY_U8 { return 1; } return 2; }
  if k == N_VAR { return bclass[nd[e].var]; }
  if k == N_UN {
    let a = bxc(nd[e].a); let op = nd[e].op;
    if op == U_ZX8 { return 1; } if op == U_SX8 { return 2; }
    if op >= U_SX8 && op <= U_ZX32 { if a == 0 { return 0; } if op == U_ZX16 || op == U_ZX32 { if a == 2 { return 0; } } return a; }
    return 0;
  }
  let op = nd[e].op; let a = bxc(nd[e].a); let b = bxc(nd[e].b);
  if op == O_ADD || op == O_SUB { return 0; }
  if (a == 1 || a == 3) && (b == 1 || b == 3) { if a == 3 && b == 3 { return 3; } return 1; }
  if (a == 2 || a == 3) && (b == 2 || b == 3) { if a == 3 && b == 3 { return 3; } return 2; }
  return 0;
}
// first-order recurrence (byte lanes): a 0/1 state flag BREC declared outside the loop, assigned
// constants on every path, read only as `b == k` / `b != k` before it is assigned. Its value
// before iteration i is its value after i - 1: the after-mask shifted up one lane.
let mut BREC: i64 = -1;
fn brec_cmp(e: i64) -> bool {
  if BREC < 0 || nd[e].k != N_BIN { return false; }
  return (nd[nd[e].a].k == N_VAR && nd[nd[e].a].var == BREC && is_const(nd[e].b)) || (nd[nd[e].b].k == N_VAR && nd[nd[e].b].var == BREC && is_const(nd[e].a));
}
fn brec_assigns(s: i64) -> bool {   // does subtree s assign BREC?
  if s < 0 { return false; }
  let k = nd[s].k;
  if k == S_ASSIGN { return nd[s].var == BREC; }
  if k == S_BLOCK { let mut c = nd[s].a; while c >= 0 { if brec_assigns(c) { return true; } c = nd[c].next; } return false; }
  if k == S_IF { return brec_assigns(nd[s].b) || brec_assigns(nd[s].c); }
  return false;
}
// state after s on every path: 0 unassigned, 1 assigned, 2 mixed, -1 invalid (read after assignment,
// or a condition that steers an assignment reads the flag)
fn brec_flow(s: i64, st: i64) -> i64 {
  if s < 0 { return st; }
  let k = nd[s].k;
  if k == S_BLOCK { let mut a = st; let mut c = nd[s].a; while c >= 0 { a = brec_flow(c, a); if a < 0 { return -1; } c = nd[c].next; } return a; }
  if k == S_ASSIGN && nd[s].var == BREC { return 1; }
  if k == S_IF {
    let rd = refs(nd[s].a, BREC);
    if rd && (st != 0 || brec_assigns(s)) { return -1; }
    let a = brec_flow(nd[s].b, st); let b = brec_flow(nd[s].c, st);
    if a < 0 || b < 0 { return -1; }
    if a == b { return a; } return 2;
  }
  let mut rd = refs(nd[s].a, BREC);
  if k == S_STORE { rd = rd || refs(nd[s].b, BREC); }
  if rd { return -1; }   // only conditions may read it
  return st;
}
// pass 1 runs before the body's stores: what it evaluates must not load an array the loop stores
fn ld_stored(e: i64, t0: i64) -> bool {
  if e < 0 { return false; }
  let k = nd[e].k;
  if k == N_LOAD { if vast[arr_leader[nd[e].var]] == t0 { return true; } return ld_stored(nd[e].a, t0); }
  if k == N_CONST || k == N_VAR || k == N_ARR || k == N_NCPU { return false; }
  if k == N_CALL { return true; }
  return ld_stored(nd[e].a, t0) || ld_stored(nd[e].b, t0);
}
fn brec_pure(s: i64, t0: i64, top: bool) -> bool {
  if s < 0 { return true; }
  let k = nd[s].k;
  if k == S_BLOCK { let mut c = nd[s].a; while c >= 0 { if !brec_pure(c, t0, top) { return false; } c = nd[c].next; } return true; }
  if k == S_LET && top { return !ld_stored(nd[s].a, t0); }
  if k == S_IF && brec_assigns(s) { return !ld_stored(nd[s].a, t0) && brec_pure(nd[s].b, t0, false) && brec_pure(nd[s].c, t0, false); }
  return true;
}
fn brec_find(s: i64, iv: i64) {   // candidate: an outer i64 assigned 0 / 1 in the body
  if s < 0 { return; }
  let k = nd[s].k;
  if k == S_BLOCK { let mut c = nd[s].a; while c >= 0 { brec_find(c, iv); c = nd[c].next; } return; }
  if k == S_IF { brec_find(nd[s].b, iv); brec_find(nd[s].c, iv); return; }
  if k == S_ASSIGN && BREC < 0 && is_const(nd[s].a) && (nd[nd[s].a].v == 0 || nd[nd[s].a].v == 1) {
    let v = nd[s].var;
    if vars[v].ty == TY_I64 && vars[v].xr < 0 && vars[v].glob == 0 && v != iv { BREC = v; }
  }
}
let mut BC_NEG: bool = false;
fn bcond_ok(e: i64, dst: i64, pm: i64, iv: i64) -> bool {
  if dst + 1 > VK_DEPTH { VK_DEPTH = dst + 1; }
  if !refs_v(e) { return false; }
  let k = nd[e].k;
  if k == N_UN && nd[e].op == U_LNOT { BC_NEG = !BC_NEG; let r = bcond_ok(nd[e].a, dst, pm, iv); BC_NEG = !BC_NEG; return r; }
  if k != N_BIN { return false; }
  let op = nd[e].op;
  // mask levels exactly as bcond uses them
  if (op == O_LAND && !BC_NEG) || (op == O_LOR && BC_NEG) { return bcond_ok(nd[e].a, dst, pm, iv) && bcond_ok(nd[e].b, dst, dst, iv); }
  if op == O_LAND || op == O_LOR { let t = mx(dst, pm) + 1; return bcond_ok(nd[e].a, t, pm, iv) && bcond_ok(nd[e].b, t + 1, pm, iv); }
  if !(op == O_EQ || op == O_NE || op == O_LT || op == O_LE || op == O_GT || op == O_GE) { return false; }
  if brec_cmp(e) { return op == O_EQ || op == O_NE; }
  let a = bx(nd[e].a, iv); let b = bx(nd[e].b, iv);
  return (a == 1 || a == 3) && (b == 1 || b == 3) || (a == 2 || a == 3) && (b == 2 || b == 3);
}
fn bst_ok(s: i64, iv: i64, lvl: i64) -> bool {
  let k = nd[s].k;
  if k == S_BLOCK { let mut c = nd[s].a; while c >= 0 { if !bst_ok(c, iv, lvl) { return false; } c = nd[c].next; } return true; }
  if k == S_IF {
    let cnd = nd[s].a;
    VK_SNO += 1; vscan_loads(cnd, iv);
    let nl = lvl + 1;
    if !bcond_ok(cnd, nl, lvl, iv) { return false; }
    return bst_ok(nd[s].b, iv, nl) && (nd[s].c < 0 || bst_ok(nd[s].c, iv, nl));
  }
  if k == S_STORE {
    let a = nd[s].var;
    if nd[s].c >= 0 || vars[a].arr != 1 || vars[a].ro != 0 || (vars[a].et != TY_U8 && vars[a].et != TY_I8) { return false; }
    let x = nd[s].a;
    if nd[x].k != N_VAR || nd[x].var != iv { return false; }
    if nd[s].op >= 0 && !is_alu_op(nd[s].op) { return false; }
    if nd[s].chk != 0 && !add_guard(a, 0) { return false; }
    VK_SNO += 1;
    vnote_w(a);
    if vast[arr_leader[a]] != vtag { vst_at[arr_leader[a]] = VK_SNO; }
    vast[arr_leader[a]] = vtag;
    vscan_loads(nd[s].b, iv);
    return bx(nd[s].b, iv) >= 0;
  }
  if k == S_ASSIGN && nd[s].var == BREC {   // state flag: b = 0 / 1 (checked in brec_ok)
    VK_SNO += 1;
    return is_const(nd[s].a) && (nd[s].a >= 0) && (nd[nd[s].a].v == 0 || nd[nd[s].a].v == 1);
  }
  if k == S_ASSIGN && vbyte[nd[s].var] != vtag {   // s += k (count) or s += byte (sum), s -= ...
    let v = nd[s].var; let e = nd[s].a;
    if (vars[v].ty != TY_I64 && vars[v].ty != TY_U64) || vars[v].xr >= 0 || v == iv || vars[v].glob != 0 { return false; }
    if nd[e].k != N_BIN || (nd[e].op != O_ADD && nd[e].op != O_SUB) || nd[nd[e].a].k != N_VAR || nd[nd[e].a].var != v { return false; }
    if vred[v] == vtag || vcnt[v] == vtag || refs(nd[e].b, v) { return false; }
    VK_SNO += 1; vscan_loads(nd[e].b, iv);
    let b = nd[e].b;
    if is_const(b) { vcnt[v] = vtag; return true; }
    let c = bx(b, iv);
    if c != 1 && c != 3 { return false; }
    vred[v] = vtag; vredop[v] = nd[e].op; vmark[v] = vtag;
    return true;
  }
  if k == S_LET {
    let v = nd[s].var;
    VK_SNO += 1; vscan_loads(nd[s].a, iv);
    let c = bx(nd[s].a, iv);
    if c < 0 || !ty_int(vars[v].ty) { return false; }
    vbyte[v] = vtag; bclass[v] = c; vdecl[v] = vtag;
    return true;
  }
  return false;
}
fn bplan(s: i64, body: i64, iv: i64, nb: i64) -> bool {
  pre_classify(body, nb, iv);
  VK_LOOPS = 0; VK_DEPTH = 0; VK_TMP = 0; VK_NG = 0; VK_SNO = 0;
  let t0 = vtag;
  BREC = -1;
  let mut c = nd[body].a; let mut i = 0;
  while i < nb { brec_find(c, iv); c = nd[c].next; i += 1; }
  if BREC >= 0 {   // the whole body must assign it on every path, reads first
    let mut st = 0; c = nd[body].a; i = 0;
    while i < nb { st = brec_flow(c, st); if st < 0 { break; } c = nd[c].next; i += 1; }
    if st != 1 || count_assign(body, BREC) == 0 { BREC = -1; }
  }
  let brec = BREC;
  c = nd[body].a; i = 0;
  while i < nb { if !bst_ok(c, iv, -1) { BREC = -1; return false; } c = nd[c].next; i += 1; }
  BREC = -1;
  let mut nvar = 0; let mut nst = 0; let mut nred = 0;
  let mut vv = 0;
  while vv < nv {
    if vast[vv] == t0 { nst += 1; if vldx[vv] == t0 || vlwx[vv] == t0 || (vldp[vv] == t0 && vldp_at[vv] > vst_at[vv]) { return false; } }
    if vred[vv] == t0 || vcnt[vv] == t0 { if count_assign(body, vv) != 1 || st_reads(body, vv) != 1 { return false; } nred += 1; }
    if vbyte[vv] == t0 && vars[vv].reads != 0 { nvar += 1; }
    if vred[vv] == t0 { nvar += 1; }
    vv += 1;
  }
  if nst + nred == 0 || nvar + 4 > 16 || VK_DEPTH > 4 { return false; }
  if brec >= 0 {
    BREC = brec;
    c = nd[body].a; i = 0;
    while i < nb { if !brec_pure(c, t0, true) { BREC = -1; return false; } c = nd[c].next; i += 1; }
    BREC = -1;
  }
  if nvlist + nvar > 65536 || nvrl + nred > 65536 { return false; }
  if !plan_extra(true, t0) { return false; }
  let p = nplans; nplans += 1;
  vplan[s] = p + 1; vp_cadd[p] = PLAN_CADD; vp_byte[p] = true; vp_brec[p] = brec;
  vp_loop[p] = s; vp_iv[p] = iv; vp_npre[p] = nb; vp_u[p] = 1; vp_nv[p] = nvar;
  vp_need0[p] = nvneed; vp_nneed[p] = 0; vp_v0[p] = nvlist; vp_scr[p] = vec_bytes;
  let mut g = 0;
  vv = 0;
  while vv < nv {
    if (vbyte[vv] == t0 && vars[vv].reads != 0) || vred[vv] == t0 { vp_vlist[nvlist] = vv; vp_vreg[nvlist] = 16 + g; nvlist += 1; g += 1; }
    if vred[vv] == t0 { vrl_var[nvrl] = vv; vrl_op[nvrl] = vredop[vv]; nvrl += 1; vp_nr[p] += 1; }
    vv += 1;
  }
  return true;
}
// byte-lane code generation (VU = 1, masks are 64 bits wide)
fn kand64(d: i64, a: i64, b: i64) { vex3(1, 0, 1, 1, 65, d, a, b); }
fn kandn64(d: i64, a: i64, b: i64) { vex3(1, 0, 1, 1, 66, d, a, b); }
fn kor64(d: i64, a: i64, b: i64) { vex3(1, 0, 1, 1, 69, d, a, b); }
fn ktest64(a: i64) { vex3(1, 0, 1, 0, 152, a, 0, a); }     // kortestq a, a
fn bbcast(d: i64, c: u64) { VM_TAIL = 0; vm_pool(cp_u64(c)); evx(2, 1, 0, 2, 120, d, 0, 1, 0, 0, false, false); }   // vpbroadcastb
fn bval(e: i64, d: i64, t: i64) {    // byte value of e into zmm d (all lanes), temporaries vr(t)..
  let k = nd[e].k;
  if k == N_CONST { bbcast(d, nd[e].v & 255); return; }
  if k == N_VAR { let r = VREG[nd[e].var]; if r != d { evx(1, 1, 1, 2, 111, d, 0, 0, r, 0, false, false); } return; }
  if k == N_LOAD {
    let a = nd[e].var;
    if !refs(nd[e].a, vp_iv[VP]) && !refs_v(nd[e].a) { gen(e, VRG, VN); evx(2, 1, 0, 2, 122, d, 0, 0, RGS[VRG], 0, false, false); return; }   // vpbroadcastb from r32
    gen(nd[e].a, VRG, VN); let ri = RGS[VRG];
    let b = base_reg(a);
    vm_mem(b, ri, 0, 0); evx(1, 2, 1, 2, 111, d, 0, 1, 0, 0, false, false);   // vmovdqu64
    return;
  }
  if k == N_UN {
    let op = nd[e].op;
    bval(nd[e].a, d, t);
    if op == U_NOT { evx(3, 1, 1, 2, 37, d, d, 0, d, 0, false, false); byte(51); return; }   // vpternlogq ~
    if op == U_NEG { let z = vr(t); evx(1, 1, 1, 2, 239, z, z, 0, z, 0, false, false); evx(1, 1, 0, 2, 248, d, z, 0, d, 0, false, false); }   // 0 - x
    return;   // narrowing / widening casts: the low byte is unchanged
  }
  let op = nd[e].op;
  bval(nd[e].a, d, t);
  let b = nd[e].b;
  let mut r = 0;
  if nd[b].k == N_VAR && vbyte[nd[b].var] == vtag && vars[nd[b].var].reads != 0 { r = VREG[nd[b].var]; }
  else { r = vr(t); bval(b, r, t + 1); }
  if op == O_ADD { evx(1, 1, 0, 2, 252, d, d, 0, r, 0, false, false); }        // vpaddb
  else if op == O_SUB { evx(1, 1, 0, 2, 248, d, d, 0, r, 0, false, false); }   // vpsubb
  else { evx(1, 1, 1, 2, viop(op), d, d, 0, r, 0, false, false); }
}
fn bcmp_pred(op: i64) -> i64 { if op == O_EQ { return 0; } if op == O_LT { return 1; } if op == O_LE { return 2; } if op == O_NE { return 4; } if op == O_GE { return 5; } return 6; }
fn bcond(e: i64, dst: i64, pm: i64, neg: bool) {
  let k = nd[e].k;
  if k == N_UN { bcond(nd[e].a, dst, pm, !neg); return; }
  let op = nd[e].op;
  if (op == O_LAND && !neg) || (op == O_LOR && neg) { bcond(nd[e].a, dst, pm, neg); bcond(nd[e].b, dst, dst, neg); return; }
  if op == O_LAND || op == O_LOR {
    let t = mx(dst, pm) + 1;
    bcond(nd[e].a, t, pm, neg); bcond(nd[e].b, t + 1, pm, neg);
    kor64(kreg(dst, 0), kreg(t, 0), kreg(t + 1, 0));
    return;
  }
  if brec_cmp(e) {   // the state flag before this lane: k6
    let mut K = nd[e].b; if !is_const(K) { K = nd[e].a; }
    let kv = nd[K].v;
    let mut eq = op == O_EQ; if neg { eq = !eq; }
    let d = kreg(dst, 0); let pmk = kpar(pm, 0);
    if kv == 1 { if eq { kand64(d, 6, pmk); } else { kandn64(d, 6, pmk); } }
    else if kv == 0 { if eq { kandn64(d, 6, pmk); } else { kand64(d, 6, pmk); } }
    else { if eq { kandn64(d, pmk, pmk); } else { kand64(d, pmk, pmk); } }
    return;
  }
  let ca = bxc(nd[e].a); let cb = bxc(nd[e].b);
  let uns = (ca == 1 || ca == 3) && (cb == 1 || cb == 3);
  let A = vr(0); let B = vr(1);
  bval(nd[e].a, A, 2); bval(nd[e].b, B, 2);
  let mut pred = bcmp_pred(op); if neg { pred = pred ^ 4; }
  let mut opc = 63; if uns { opc = 62; }
  evx(3, 1, 0, 2, opc, kreg(dst, 0), A, 0, B, kpar(pm, 0), false, false); byte(pred);   // vpcmp[u]b
}
// pass 1: k5 = lanes whose flag is 1 after the iteration (only the ifs that steer assignments)
fn brec_pass(p: i64, s: i64, lvl: i64) {
  if s < 0 { return; }
  let k = nd[s].k;
  if k == S_BLOCK { let mut c = nd[s].a; while c >= 0 { brec_pass(p, c, lvl); c = nd[c].next; } return; }
  if k == S_LET && lvl < 0 { bgen(p, s, lvl); return; }   // byte temporaries the conditions read
  if k == S_ASSIGN && nd[s].var == BREC {
    if nd[nd[s].a].v == 1 { kor64(5, 5, kpar(lvl, 0)); } else { kandn64(5, kpar(lvl, 0), 5); }
    return;
  }
  if k == S_IF && brec_assigns(s) {
    let sv_rg = rgs_top; let sv_pos = cur_pos;
    vtemps(s); rgs_top += 12; cur_pos = nd[s].pos;
    let nl = lvl + 1;
    bcond(nd[s].a, nl, lvl, false);
    rgs_top = sv_rg; cur_pos = sv_pos;
    brec_pass(p, nd[s].b, nl);
    if nd[s].c >= 0 { kandn64(kreg(nl, 0), kreg(nl, 0), kpar(lvl, 0)); brec_pass(p, nd[s].c, nl); }
  }
}
fn bgen(p: i64, s: i64, lvl: i64) {
  let k = nd[s].k;
  if k == S_BLOCK { let mut c = nd[s].a; while c >= 0 { bgen(p, c, lvl); c = nd[c].next; } return; }
  let sv_rg = rgs_top; let sv_pos = cur_pos;
  vtemps(s); rgs_top += 12; cur_pos = nd[s].pos;
  if k == S_IF {
    let nl = lvl + 1;
    bcond(nd[s].a, nl, lvl, false);
    rgs_top = sv_rg; cur_pos = sv_pos;
    ktest64(kreg(nl, 0)); let sk = jcc(CC_E);
    bgen(p, nd[s].b, nl);
    rel32(sk, clen);
    if nd[s].c >= 0 {
      kandn64(kreg(nl, 0), kreg(nl, 0), kpar(lvl, 0));
      ktest64(kreg(nl, 0)); let sk2 = jcc(CC_E);
      bgen(p, nd[s].c, nl);
      rel32(sk2, clen);
    }
    return;
  }
  if k == S_STORE {
    let a = nd[s].var;
    let D = vr(0);
    bval(nd[s].b, D, 2);
    gen(nd[s].a, VRG, VN); let ri = RGS[VRG];
    let b = base_reg(a);
    if nd[s].op >= 0 {
      vm_mem(b, ri, 0, 0); evx(1, 2, 1, 2, 111, vr(1), 0, 1, 0, 0, false, false);
      let op = nd[s].op;
      if op == O_ADD { evx(1, 1, 0, 2, 252, D, vr(1), 0, D, 0, false, false); }
      else if op == O_SUB { evx(1, 1, 0, 2, 248, D, vr(1), 0, D, 0, false, false); }
      else { evx(1, 1, 1, 2, viop(op), D, vr(1), 0, D, 0, false, false); }
    }
    vm_mem(b, ri, 0, 0);
    if lvl < 0 { evx(1, 2, 1, 2, 127, D, 0, 1, 0, 0, false, false); }           // vmovdqu64
    else { evx(1, 3, 0, 2, 127, D, 0, 1, 0, kreg(lvl, 0), false, false); }      // vmovdqu8 {k}
    rgs_top = sv_rg; cur_pos = sv_pos;
    return;
  }
  if k == S_ASSIGN && nd[s].var == BREC { rgs_top = sv_rg; cur_pos = sv_pos; return; }   // done in brec_pass
  if k == S_ASSIGN && vbyte[nd[s].var] != vtag {
    let v = nd[s].var; let e = nd[s].a; let b = nd[e].b;
    let mut dig = A_ADD; if nd[e].op == O_SUB { dig = A_SUB; }
    if is_const(b) {   // count: active lanes x k
      if lvl < 0 { mov_ri(RAX, 64 * nd[b].v); }
      else { vex3(1, 3, 1, 0, 147, RAX, 0, kreg(lvl, 0)); emh("f3480fb8c0"); if nd[b].v != 1 { imul_r(RAX, K_IMM, 0, nd[b].v); } }   // kmovq, popcnt
      loc(v); alu(dig, OK, ORR, K_REG, RAX, 0);
    } else {           // sum of bytes: vpsadbw against zero, into the 64-bit accumulator lanes
      let T = vr(0); let Z = vr(1);
      bval(b, T, 2);
      if lvl >= 0 { evx(1, 3, 0, 2, 111, T, 0, 0, T, kreg(lvl, 0), true, false); }   // vmovdqu8 T{k}{z}
      evx(1, 1, 1, 2, 239, Z, Z, 0, Z, 0, false, false);
      evx(1, 1, 0, 2, 246, T, T, 0, Z, 0, false, false);                         // vpsadbw
      evx(1, 1, 1, 2, 212, VREG[v], VREG[v], 0, T, 0, false, false);             // vpaddq
    }
    rgs_top = sv_rg; cur_pos = sv_pos;
    return;
  }
  if k == S_LET {
    let v = nd[s].var;
    if vars[v].reads != 0 {
      if lvl < 0 { bval(nd[s].a, VREG[v], 0); }
      else { let T = vr(0); bval(nd[s].a, T, 1); evx(1, 3, 0, 2, 111, VREG[v], 0, 0, T, kreg(lvl, 0), false, false); }   // merge into active lanes
    }
    rgs_top = sv_rg; cur_pos = sv_pos;
    return;
  }
  fail("internal: statement in a byte-lane loop");
}
// make plan p's varying set current (marks and registers)
fn plan_enter(p: i64) {
  vtag += 1;
  let mut i = 0;
  while i < vp_nv[p] { let v = vp_vlist[vp_v0[p] + i]; vmark[v] = vtag; VREG[v] = vp_vreg[vp_v0[p] + i]; if vp_byte[p] && !red_of(p, v) { vbyte[v] = vtag; } i += 1; }
}
fn plan_all() {
  let mut s = 0;
  while s < nn { if nd[s].k == S_WHILE { plan_loop(s); } s += 1; }
}
// ---- vector code generation (current plan: VP, U zmm registers per value)
let mut VP: i64 = 0;
let mut VU: i64 = 1;
let mut VRG: i64 = 0;       // scalar temporaries of the statement being generated
let mut VN: i64 = 0;
let HAS_AVX = 268435496;      // BSS byte: AVX-512F+DQ+BW+VL usable (set at start)
fn vec_base() -> i64 { return GLOB_BASE + ((glob_bytes + 63) & ~63); }
fn vr(t: i64) -> i64 { return 16 + (vp_nv[VP] + t) * VU; }
fn kreg(lvl: i64, h: i64) -> i64 { if lvl < 0 { return 0; } return 1 + lvl * VU + h; }
fn kpar(lvl: i64, h: i64) -> i64 { if lvl < 0 { return 7; } return 1 + lvl * VU + h; }
// operand: kind 0 register group, 1 constant-pool broadcast
let mut VOK: i64 = 0;
let mut VOR: i64 = 0;
// dst{mask} = a OP b over every half. b: register group or broadcast constant
fn vop3(mm: i64, pp: i64, opc: i64, d: i64, a: i64, bk: i64, b: i64, lvl: i64) {
  let mut h = 0;
  while h < VU {
    if bk == 0 { evx(mm, pp, 1, 2, opc, d + h, a + h, 0, b + h, kreg(lvl, h), false, false); }
    else { VM_TAIL = 0; vm_pool(b); evx(mm, pp, 1, 2, opc, d + h, a + h, 1, 0, kreg(lvl, h), false, true); }
    h += 1;
  }
}
fn vshift(dig: i64, opc: i64, d: i64, a: i64, k: i64, lvl: i64) {   // vpsllq/vpsrlq (73 /6, /2), vpsraq (72 /4)
  let mut h = 0;
  while h < VU { evx(1, 1, 1, 2, opc, dig, d + h, 0, a + h, kreg(lvl, h), false, false); byte(k & 63); h += 1; }
}
fn vmov(d: i64, a: i64, lvl: i64) {   // vmovdqa64 d{k}, a
  if d == a && lvl < 0 { return; }
  let mut h = 0;
  while h < VU { evx(1, 1, 1, 2, 111, d + h, 0, 0, a + h, kreg(lvl, h), false, false); h += 1; }
}
fn vbc_pool(d: i64, off: i64, lvl: i64) {   // vpbroadcastq d{k}, [pool]
  let mut h = 0;
  while h < VU { VM_TAIL = 0; vm_pool(off); evx(2, 1, 1, 2, 89, d + h, 0, 1, 0, kreg(lvl, h), false, false); h += 1; }
}
fn vbc_gpr(d: i64, r: i64, lvl: i64) {      // vpbroadcastq d{k}, r64
  let mut h = 0;
  while h < VU { evx(2, 1, 1, 2, 124, d + h, 0, 0, r, kreg(lvl, h), false, false); h += 1; }
}
// broadcast a uniform scalar expression
fn vbcast(e: i64, d: i64, lvl: i64) {
  let k = nd[e].k;
  if k == N_VAR && hv_tag[nd[e].var] == HV_TAG { vmov(d, hv_reg[nd[e].var], lvl); return; }
  if k == N_CONST { vbc_pool(d, cp_u64(nd[e].v), lvl); return; }
  if k == N_VAR {
    loc(nd[e].var);
    if OK == K_REG { vbc_gpr(d, ORR, lvl); return; }
    if OK == K_XMM { let mut h = 0; while h < VU { evx(2, 1, 1, 2, 25, d + h, 0, 0, ORR, kreg(lvl, h), false, false); h += 1; } return; }
    if OK == K_MEM { let mut h = 0; while h < VU { vm_mem(RSP, -1, 0, ORR * 8 + sp_adj); evx(2, 1, 1, 2, 89, d + h, 0, 1, 0, kreg(lvl, h), false, false); h += 1; } return; }
  }
  gen(e, VRG, VN); vbc_gpr(d, RGS[VRG], lvl);
}
fn fp_nan(v: u64) -> bool { return (v & 9218868437227405312) == 9218868437227405312 && (v & 4503599627370495) != 0; }
// operand for e: a register group (computed into vr(t) if needed) or a pool constant
fn vopnd(e: i64, t: i64) {
  if nd[e].k == N_CONST { VOK = 1; VOR = cp_u64(nd[e].v); return; }
  if nd[e].k == N_VAR && is_v(nd[e].var) { VOK = 0; VOR = VREG[nd[e].var]; return; }
  if nd[e].k == N_VAR && hv_tag[nd[e].var] == HV_TAG { VOK = 0; VOR = hv_reg[nd[e].var]; return; }
  vgen_into(e, vr(t), -1, t); VOK = 0; VOR = vr(t);
}
fn vfop(op: i64) -> i64 { if op == O_FADD { return 88; } if op == O_FSUB { return 92; } if op == O_FMUL { return 89; } return 94; }
fn viop(op: i64) -> i64 { if op == O_ADD { return 212; } if op == O_SUB { return 251; } if op == O_AND { return 219; } if op == O_OR { return 235; } return 239; }
// e into register group d under mask level lvl (merge: inactive lanes keep d), temporaries from t
fn vgen_into(e: i64, d: i64, lvl: i64, t: i64) {
  let k = nd[e].k;
  if !refs_v(e) { vbcast(e, d, lvl); return; }
  if k == N_VAR { vmov(d, VREG[nd[e].var], lvl); return; }
  if k == N_LOAD {
    let a = nd[e].var;
    gen(nd[e].a, VRG, VN);
    let ri = RGS[VRG];
    let b = base_reg(a);
    vload(a, vars[a].et, b, ri, d, lvl);
    return;
  }
  if k == N_UN {
    let op = nd[e].op;
    vopnd(nd[e].a, t);
    let ak = VOK; let mut ar = VOR;
    if ak == 1 { vbc_pool(vr(t), ar, -1); ar = vr(t); }
    if op == U_FNEG { vop3(1, 1, 239, d, ar, 1, cp_u64(9223372036854775808), lvl); return; }
    if op == U_NOT { vop3(1, 1, 239, d, ar, 1, cp_u64(18446744073709551615), lvl); return; }
    if op == U_NEG { let z = vr(t + 1); vop3(1, 1, 239, z, z, 0, z, -1); vop3(1, 1, 251, d, z, 0, ar, lvl); return; }
    if op == U_SQRTD { let mut h = 0; while h < VU { evx(1, 1, 1, 2, 81, d + h, 0, 0, ar + h, kreg(lvl, h), false, false); h += 1; } return; }
    if op == U_I2D { let mut h = 0; while h < VU { evx(1, 2, 1, 2, 230, d + h, 0, 0, ar + h, kreg(lvl, h), false, false); h += 1; } return; }
    if op == U_ZX8 { vop3(1, 1, 219, d, ar, 1, cp_u64(255), lvl); return; }
    if op == U_ZX16 { vop3(1, 1, 219, d, ar, 1, cp_u64(65535), lvl); return; }
    if op == U_ZX32 { vop3(1, 1, 219, d, ar, 1, cp_u64(4294967295), lvl); return; }
    let mut sh = 32; if op == U_SX8 { sh = 56; } else if op == U_SX16 { sh = 48; }
    let tt = vr(t + 1);
    vshift(6, 115, tt, ar, sh, -1); vshift(4, 114, d, tt, sh, lvl); return;
  }
  let op = nd[e].op;
  let a = nd[e].a; let b = nd[e].b;
  if op == O_SHL || op == O_SHR || op == O_SAR {
    vopnd(a, t); let mut ar = VOR; if VOK == 1 { vbc_pool(vr(t), ar, -1); ar = vr(t); }
    let c = (nd[b].v & 63) as i64;
    if op == O_SHL { vshift(6, 115, d, ar, c, lvl); } else if op == O_SHR { vshift(2, 115, d, ar, c, lvl); } else { vshift(4, 114, d, ar, c, lvl); }
    return;
  }
  if op == O_DIV || op == O_MOD || op == O_DIVU || op == O_MODU {
    vopnd(a, t); let mut ar = VOR; if VOK == 1 { vbc_pool(vr(t), ar, -1); ar = vr(t); }
    let dv = nd[b].v;
    let mut kk = 0; while ((1 as u64) << (kk as u64)) != dv { kk += 1; }
    if op == O_DIVU || (op == O_DIV && nd[e].nn != 0) {
      if op == O_DIVU { vshift(2, 115, d, ar, kk, lvl); } else { vshift(4, 114, d, ar, kk, lvl); }
      return;
    }
    if op == O_MODU || nd[e].nn != 0 { vop3(1, 1, 219, d, ar, 1, cp_u64(dv - 1), lvl); return; }
    let tt = vr(t + 1);
    vshift(4, 114, tt, ar, 63, -1);
    if kk > 0 { vshift(2, 115, tt, tt, 64 - kk, -1); } else { vop3(1, 1, 239, tt, tt, 0, tt, -1); }
    vop3(1, 1, 212, tt, ar, 0, tt, -1);                    // x + bias
    if op == O_DIV { vshift(4, 114, d, tt, kk, lvl); return; }
    vop3(1, 1, 219, tt, tt, 1, cp_u64(0 - dv), -1);        // & -2^k
    vop3(1, 1, 251, d, ar, 0, tt, lvl);                    // x - that
    return;
  }
  vopnd(a, t);
  let mut ak = VOK; let mut ar = VOR;
  vopnd(b, t + 1);
  let mut bk = VOK; let mut br = VOR;
  let fp = op == O_FADD || op == O_FSUB || op == O_FMUL || op == O_FDIV;
  let comm = op == O_FADD || op == O_FMUL || op == O_ADD || op == O_MUL || op == O_AND || op == O_OR || op == O_XOR;
  if ak == 1 {
    if comm && bk == 0 && !(fp && fp_nan(nd[a].v)) { let tk = ak; let tr2 = ar; ak = bk; ar = br; bk = tk; br = tr2; }
    else { vbc_pool(vr(t), ar, -1); ak = 0; ar = vr(t); }
  }
  if fp { vop3(1, 1, vfop(op), d, ar, bk, br, lvl); return; }
  if op == O_MUL { vop3(2, 1, 64, d, ar, bk, br, lvl); return; }
  vop3(1, 1, viop(op), d, ar, bk, br, lvl);
}
// condition -> mask level lvl, restricted to mask level pm (-1: all lanes)
fn vcmp_pred(op: i64) -> i64 {
  if op == O_EQ || op == O_FEQ { return 0; } if op == O_LT || op == O_LTU || op == O_FLT { return 1; }
  if op == O_LE || op == O_LEU || op == O_FLE { return 2; } if op == O_NE || op == O_FNE { return 4; }
  if op == O_FGT { return 14; } if op == O_FGE { return 13; }
  if op == O_GE || op == O_GEU { return 5; } return 6;
}
fn vcond(e: i64, dst: i64, pm: i64, neg: bool) {
  let k = nd[e].k;
  if !refs_v(e) {
    gen(e, VRG, VN); let r = RGS[VRG];
    if neg { alui(A_XOR, r, 1); }
    unop(3, K_REG, r);
    kmov_kr(0, r);
    let mut h = 0;
    while h < VU { kand(kreg(dst, h), 0, kpar(pm, h)); h += 1; }
    return;
  }
  if k == N_UN { vcond(nd[e].a, dst, pm, !neg); return; }
  let op = nd[e].op;
  if (op == O_LAND && !neg) || (op == O_LOR && neg) { vcond(nd[e].a, dst, pm, neg); vcond(nd[e].b, dst, dst, neg); return; }
  if op == O_LAND || op == O_LOR {
    let t = mx(dst, pm) + 1;
    vcond(nd[e].a, t, pm, neg); vcond(nd[e].b, t + 1, pm, neg);
    let mut h = 0; while h < VU { kor(kreg(dst, h), kreg(t, h), kreg(t + 1, h)); h += 1; }
    return;
  }
  let a = nd[e].a; let b = nd[e].b;
  vopnd(a, 0); let mut ak = VOK; let mut ar = VOR;
  vopnd(b, 1); let mut bk = VOK; let mut br = VOR;
  let mut o = op;
  if ak == 1 {
    if bk == 0 { let tk = ak; let tr2 = ar; ak = bk; ar = br; bk = tk; br = tr2; o = swap_cmp(op); }
    else { vbc_pool(vr(0), ar, -1); ak = 0; ar = vr(0); }
  }
  let fl = op >= O_FEQ && op <= O_FGE;
  let uns = op == O_LTU || op == O_LEU || op == O_GTU || op == O_GEU;
  let mut pred = vcmp_pred(o);
  if neg { pred = pred ^ 4; }
  let mut h = 0;
  while h < VU {
    VM_TAIL = 1;
    if bk == 1 { vm_pool(br); }
    let rr = if_sel(bk == 0, br + h, 0);
    if fl { evx(1, 1, 1, 2, 194, kreg(dst, h), ar + h, bk, rr, kreg(pm, h), false, bk == 1); }
    else if uns { evx(3, 1, 1, 2, 30, kreg(dst, h), ar + h, bk, rr, kreg(pm, h), false, bk == 1); }
    else { evx(3, 1, 1, 2, 31, kreg(dst, h), ar + h, bk, rr, kreg(pm, h), false, bk == 1); }
    byte(pred);
    VM_TAIL = 0;
    h += 1;
  }
}
fn if_sel(c: bool, a: i64, b: i64) -> i64 { if c { return a; } return b; }
fn vtemps(s: i64) {
  VRG = rgs_top; VN = temps_at(nd[s].pos);
  let mut i = 0;
  while i < VN { RGS[VRG + i] = TMPS[i]; i += 1; }
}
fn vstmt(s: i64, lvl: i64) {
  if s < 0 { return; }
  let k = nd[s].k;
  let sv_rg = rgs_top; let sv_pos = cur_pos; let sv_st = cur_stmt;
  if k != S_BLOCK && k != S_INL && k != S_BRK && k != S_CONT { vtemps(s); rgs_top += 12; cur_pos = nd[s].pos; cur_stmt = -1; }
  vstmt_body(s, lvl);
  rgs_top = sv_rg; cur_pos = sv_pos; cur_stmt = sv_st;
}
fn vstmt_body(s: i64, lvl: i64) {
  let k = nd[s].k;
  if k == S_LET || k == S_ASSIGN || k == S_IRET {
    let v = nd[s].var;
    if vars[v].reads != 0 {
      if is_v(v) { vgen_into(nd[s].a, VREG[v], lvl, 0); }
      else { assign(v, nd[s].a, VRG, VN); }
    } else if has_trap(nd[s].a) { gen(nd[s].a, VRG, VN); }
    if k == S_IRET && nd[s].next >= 0 { inl_list[ninlctx - 1] = pl_add(inl_list[ninlctx - 1], jmp()); }
    return;
  }
  if k == S_BLOCK { let mut c = nd[s].a; while c >= 0 { vstmt(c, lvl); c = nd[c].next; } return; }
  if k == S_INL {
    let L = ninlctx; ninlctx += 1; inl_list[L] = -1;
    let mut c = nd[s].a;
    while c >= 0 { vstmt(c, lvl); c = nd[c].next; }
    pl_patch(inl_list[L], clen); ninlctx -= 1;
    return;
  }
  if k == S_BRK { brk_list[nloopctx - 1] = pl_add(brk_list[nloopctx - 1], jmp()); return; }
  if k == S_CONT { cont_list[nloopctx - 1] = pl_add(cont_list[nloopctx - 1], jmp()); return; }
  if k == S_IF {
    if lvl < 0 && !refs_v(nd[s].a) {
      if is_const(nd[s].a) { if nd[nd[s].a].v != 0 { vstmt(nd[s].b, -1); } else { vstmt(nd[s].c, -1); } return; }
      let mut f = -1; let mut en = -1;
      f = cond_jump(nd[s].a, false, f, VRG, VN); vstmt(nd[s].b, -1);
      if nd[s].c >= 0 { if !terminates(nd[s].b) { en = pl_add(en, jmp()); } pl_patch(f, clen); vstmt(nd[s].c, -1); pl_patch(en, clen); }
      else { pl_patch(f, clen); }
      return;
    }
    let nl = lvl + 1;
    vcond(nd[s].a, nl, lvl, false);
    let mut h = 0;
    kortest(kreg(nl, 0), kreg(nl, VU - 1));
    let sk = jcc(CC_E);
    vstmt(nd[s].b, nl);
    rel32(sk, clen);
    if nd[s].c >= 0 {
      h = 0; while h < VU { kandn(kreg(nl, h), kreg(nl, h), kpar(lvl, h)); h += 1; }
      kortest(kreg(nl, 0), kreg(nl, VU - 1));
      let sk2 = jcc(CC_E);
      vstmt(nd[s].c, nl);
      rel32(sk2, clen);
    }
    return;
  }
  if k == S_WHILE {
    if lvl < 0 && !refs_v(nd[s].a) {
      if is_const(nd[s].a) && nd[nd[s].a].v == 0 { return; }
      let mut entry = -1; let mut back = -1;
      if !is_const(nd[s].a) { entry = pl_add(entry, jmp()); let mut al = 16; if lh_inner(nd[s].b) { al = 32; } while (clen % al) != 0 { byte(144); } }
      let top = clen;
      let L = nloopctx; nloopctx += 1; brk_list[L] = -1; cont_list[L] = -1;
      vstmt(nd[s].b, -1);
      let c1 = nd[s].a;
      if nd[c1].k == N_BIN && is_cmp(nd[c1].op) && ty_int(nd[nd[c1].a].ty) && simple(nd[c1].a) && simple(nd[c1].b) { let room = 32 - (clen % 32); if room < 14 { nop_n(room); } }
      pl_patch(cont_list[L], clen); pl_patch(entry, clen);
      vtemps(s);
      back = cond_jump(nd[s].a, true, back, VRG, VN); pl_patch(back, top);
      pl_patch(brk_list[L], clen); nloopctx -= 1;
      return;
    }
    let nl = lvl + 1;
    vcond(nd[s].a, nl, lvl, false);
    kortest(kreg(nl, 0), kreg(nl, VU - 1));
    let ex = jcc(CC_E);
    let top = clen;
    vstmt(nd[s].b, nl);
    vtemps(s);
    vcond(nd[s].a, nl, nl, false);
    kortest(kreg(nl, 0), kreg(nl, VU - 1));
    rel32(jcc(CC_NE), top);
    rel32(ex, clen);
    return;
  }
  fail("internal: statement in a vector region");
}
// run-time conditions for plan p's vector loop, tested once before it (inputs do not change in the loop)
fn alen_cmp(a: i64) {
  if vars[a].lenv < 0 { alu(A_CMP, K_REG, RAX, K_IMM, 0, vars[a].alen as u64); }
  else { loc(vars[a].lenv); alu(A_CMP, K_REG, RAX, OK, ORR, OI); }
}
fn vguards(p: i64, iv: i64, cnd: i64, en: i64, ts0: i64) -> i64 {
  let mut ts = ts0;
  // outside main, two array parameters (or a parameter and a global) can be one array: different bases
  if curfn != mainfn {
    let mut i = 0;
    while i < vp_na[p] {
      let b1 = base_reg(val_s[vp_a0[p] + i]); if b1 != RCX { mov_rr(RCX, b1); }
      let b2 = base_reg(val_l[vp_a0[p] + i]);
      alu(A_CMP, K_REG, RCX, K_REG, b2, 0); ts = pl_add(ts, jcc(CC_E));
      i += 1;
    }
  }
  // unproven a[i + c]: every index a block can touch, i0 + c .. last + c, lies inside a
  // (last = E - 1 for <, E for <=; i only grows by 1 per iteration)
  let mut g = 0;
  while g < vp_ng[p] {
    let a = vgl_arr[vp_g0[p] + g]; let c = vgl_off[vp_g0[p] + g]; let u = vgl_offe[vp_g0[p] + g];
    if u >= 0 {   // a[i + U]: 0 <= U + i0 and U + last < len (U is loop-invariant)
      gen(u, VRG, VN); let ru = RGS[VRG];
      mov_rr(RAX, ru); loc(iv); alu(A_ADD, K_REG, RAX, OK, ORR, OI); ts = pl_add(ts, jcc(0));
      alen_cmp(a); ts = pl_add(ts, jcc(CC_AE));
      bound_rcx(en);
      if vp_cadd[p] != 0 { alui(A_SUB, RCX, vp_cadd[p] as u64); ts = pl_add(ts, jcc(0)); }
      mov_rr(RAX, ru); alu(A_ADD, K_REG, RAX, K_REG, RCX, 0); ts = pl_add(ts, jcc(0));
      if nd[cnd].op == O_LT { alui(A_SUB, RAX, 1); ts = pl_add(ts, jcc(0)); }
      alen_cmp(a); ts = pl_add(ts, jcc(CC_GE));
      g += 1;
      continue;
    }
    loc(iv); load(RAX, OK, ORR, OI);
    if c != 0 { alui(A_ADD, RAX, c as u64); ts = pl_add(ts, jcc(0)); }
    alen_cmp(a); ts = pl_add(ts, jcc(CC_AE));
    bound_rcx(en); mov_rr(RAX, RCX);
    let mut adj = c - vp_cadd[p]; if nd[cnd].op == O_LT { adj = c - 1; }
    if adj != 0 { alui(A_ADD, RAX, adj as u64); ts = pl_add(ts, jcc(0)); }
    alen_cmp(a); ts = pl_add(ts, jcc(CC_GE));
    g += 1;
  }
  return ts;
}
// stream loops: accumulators start at the identity (all ones for &, else 0)
fn vred_init(p: i64) {
  let mut r = 0;
  while r < vp_nr[p] {
    let R = VREG[vrl_var[vp_r0[p] + r]];
    let mut h = 0;
    while h < VU {
      let op = vrl_op[vp_r0[p] + r];
      if op >= RED_MAXS {   // identity: the opposite extreme
        let mut id: u64 = 9223372036854775808;
        if op == RED_MAXU { id = 0; } else if op == RED_MINS { id = 9223372036854775807; } else if op == RED_MINU { id = 18446744073709551615; }
        VM_TAIL = 0; vm_pool(cp_u64(id)); evx(2, 1, 1, 2, 89, R + h, 0, 1, 0, 0, false, false);   // vpbroadcastq
      }
      else if op == O_AND { evx(3, 1, 1, 2, 37, R + h, R + h, 0, R + h, 0, false, false); byte(255); }   // vpternlogq: ones
      else { evx(1, 1, 1, 2, 239, R + h, R + h, 0, R + h, 0, false, false); }                                        // vpxorq: zero
      h += 1;
    }
    r += 1;
  }
}
fn vred_opc(op: i64) -> i64 {   // s -= e: subtract the sum; max/min: vpmax/vpmin (0F38)
  if op == RED_MAXS { return 61; } if op == RED_MAXU { return 63; } if op == RED_MINS { return 57; } if op == RED_MINU { return 59; }
  if op == O_SUB { return viop(O_ADD); } return viop(op);
}
fn vred_mm(op: i64) -> i64 { if op >= RED_MAXS { return 2; } return 1; }
// fold the lanes and combine with the scalar: s = s op (lane0 op lane1 op ..)
fn vred_fini(p: i64) {
  let mut r = 0;
  while r < vp_nr[p] {
    let v = vrl_var[vp_r0[p] + r]; let op = vrl_op[vp_r0[p] + r];
    let R = VREG[v]; let T = vr(0); let o = vred_opc(op); let mm = vred_mm(op);
    if VU == 2 { evx(mm, 1, 1, 2, o, R, R, 0, R + 1, 0, false, false); }
    evx(3, 1, 1, 2, 59, R, 0, 0, T, 0, false, false); byte(1);   // vextracti64x4 ymmT, zmmR, 1
    evx(mm, 1, 1, 1, o, R, R, 0, T, 0, false, false);
    evx(3, 1, 1, 1, 57, R, 0, 0, T, 0, false, false); byte(1);   // vextracti64x2 xmmT, ymmR, 1
    evx(mm, 1, 1, 0, o, R, R, 0, T, 0, false, false);
    evx(1, 1, 0, 0, 112, T, 0, 0, R, 0, false, false); byte(78); // vpshufd xmmT, xmmR, 0x4e
    evx(mm, 1, 1, 0, o, R, R, 0, T, 0, false, false);
    if op >= RED_MAXS {   // combine with the scalar in the vector unit: lane 0 = max/min(m, folded)
      loc(v); load(RCX, OK, ORR, OI);
      evx(1, 1, 1, 0, 110, T, 0, 0, RCX, 0, false, false);       // vmovq xmmT, rcx
      evx(mm, 1, 1, 0, o, R, R, 0, T, 0, false, false);
      evx(1, 1, 1, 0, 126, R, 0, 0, RAX, 0, false, false);       // vmovq rax, xmmR
      loc(v); store(OK, ORR, RAX);
    } else {
      evx(1, 1, 1, 0, 126, R, 0, 0, RAX, 0, false, false);       // vmovq rax, xmmR
      loc(v); load(RCX, OK, ORR, OI); alu(alu_dig(op), K_REG, RCX, K_REG, RAX, 0); loc(v); store(OK, ORR, RCX);
    }
    r += 1;
  }
}
fn red_of(p: i64, v: i64) -> bool {
  let mut r = 0;
  while r < vp_nr[p] { if vrl_var[vp_r0[p] + r] == v { return true; } r += 1; }
  return false;
}
fn sgen(p: i64, s: i64, lvl: i64) {
  let k = nd[s].k;
  if k == S_BLOCK { let mut c = nd[s].a; while c >= 0 { sgen(p, c, lvl); c = nd[c].next; } return; }
  if k == S_IF && lvl < 0 && minmax_kind(s) != 0 && red_of(p, MM_VAR) {
    let r = MM_VAR; let x = MM_X; let op = minmax_kind(s);
    let sv_rg = rgs_top; let sv_pos = cur_pos;
    vtemps(s); rgs_top += 12; cur_pos = nd[s].pos;
    vopnd(x, 0);
    let mut h = 0;
    while h < VU {
      if VOK == 1 { VM_TAIL = 0; vm_pool(VOR); evx(2, 1, 1, 2, vred_opc(op), VREG[r] + h, VREG[r] + h, 1, 0, 0, false, true); }
      else { evx(2, 1, 1, 2, vred_opc(op), VREG[r] + h, VREG[r] + h, 0, VOR + h, 0, false, false); }
      h += 1;
    }
    rgs_top = sv_rg; cur_pos = sv_pos;
    return;
  }
  if k == S_IF {
    let sv_rg = rgs_top; let sv_pos = cur_pos;
    vtemps(s); rgs_top += 12; cur_pos = nd[s].pos;
    let cnd = nd[s].a;
    if !refs_v(cnd) {
      let mut f = -1; let mut en = -1;
      f = cond_jump(cnd, false, f, VRG, VN);
      rgs_top = sv_rg; cur_pos = sv_pos;
      sgen(p, nd[s].b, lvl);
      if nd[s].c >= 0 { en = pl_add(en, jmp()); pl_patch(f, clen); sgen(p, nd[s].c, lvl); pl_patch(en, clen); }
      else { pl_patch(f, clen); }
      return;
    }
    let nl = lvl + 1;
    vcond(cnd, nl, lvl, false);
    rgs_top = sv_rg; cur_pos = sv_pos;
    kortest(kreg(nl, 0), kreg(nl, VU - 1));
    let sk = jcc(CC_E);
    sgen(p, nd[s].b, nl);
    rel32(sk, clen);
    if nd[s].c >= 0 {
      let mut h = 0; while h < VU { kandn(kreg(nl, h), kreg(nl, h), kpar(lvl, h)); h += 1; }
      kortest(kreg(nl, 0), kreg(nl, VU - 1));
      let sk2 = jcc(CC_E);
      sgen(p, nd[s].c, nl);
      rel32(sk2, clen);
    }
    return;
  }
  if k == S_STORE || (k == S_ASSIGN && red_of(p, nd[s].var)) {
    let sv_rg = rgs_top; let sv_pos = cur_pos;
    vtemps(s); rgs_top += 12; cur_pos = nd[s].pos;
    if k == S_STORE { vstore(s, lvl); }
    else {
      let r = nd[s].var; let e = nd[s].a;
      vopnd(nd[e].b, 0);
      vop3(1, 1, vred_opc(nd[e].op), VREG[r], VREG[r], VOK, VOR, lvl);
    }
    rgs_top = sv_rg; cur_pos = sv_pos;
    return;
  }
  if k == S_LET && vars[nd[s].var].reads == 0 && refs_v(nd[s].a) { return; }   // guarded, nothing to compute
  vstmt(s, lvl);
}
// a[i..i+L) = value (a[i] op= value: load, op, store), 8-byte elements
fn vstore(s: i64, lvl: i64) {
  let a = nd[s].var; let mut val = nd[s].b;
  let w = vars[a].arr;
  while nd[val].k == N_UN && ext_width(nd[val].op) >= w { val = nd[val].a; }   // the store truncates anyway
  let mut src = 0;
  if nd[val].k == N_VAR && is_v(nd[val].var) { src = VREG[nd[val].var]; }
  else { vgen_into(val, vr(0), -1, 1); src = vr(0); }
  let x = nd[s].a;
  let mut ri = 0;
  if nd[x].k == N_VAR && vars[nd[x].var].reg >= 0 { ri = vars[nd[x].var].reg; } else { gen(x, VRG, VN); ri = RGS[VRG]; }
  let b = base_reg(a);
  let mut h = 0;
  if nd[s].op >= 0 { vload(a, vars[a].et, b, ri, vr(1), -1); vop3(1, 1, viop(nd[s].op), vr(0), vr(1), 0, src, -1); src = vr(0); }
  while h < VU {
    vm_mem(b, ri, lg(w), 8 * w * h);
    if w == 8 { evx(1, 2, 1, 2, 127, src + h, 0, 1, 0, kreg(lvl, h), false, false); }               // vmovdqu64 store {k}
    else { evx(2, 2, 0, 2, vtrunc_op(w), src + h, 0, 1, 0, kreg(lvl, h), false, false); }   // vpmovq{b,w,d}: truncate {k}
    h += 1;
  }
}
// mov r64 / movsd xmm  <- [lane * 8 + abs] (lane index in rax)
fn lane_load(dst: i64, x: bool, abs: i64) {
  if x { byte(242); if (dst & 8) != 0 { byte(68); } byte(15); byte(16); }
  else { if (dst & 8) != 0 { byte(76); } else { byte(72); } byte(139); }
  byte(4 | ((dst & 7) << 3)); byte(197); u32_(abs);
}
// the vectorized form of loop s (plan p), placed before the ordinary scalar loop; returns the
// patch list of jumps to the scalar loop
// stream loops: loop-invariant scalar variables read by vector expressions are broadcast once,
// before the loop, into the zmm groups the plan leaves free
let hv_tag = alloc<i64>(65536);
let hv_reg = alloc<i64>(65536);
let mut HV_TAG: i64 = 0;
let mut HV_NEXT: i64 = 0;
fn ivv_e(e: i64, iv: i64) -> bool {   // e reads iv outside array indices
  if e < 0 { return false; }
  let k = nd[e].k;
  if k == N_VAR { return nd[e].var == iv; }
  if k == N_CONST || k == N_ARR || k == N_NCPU { return false; }
  if k == N_LOAD { return false; }
  if k == N_CALL { return true; }
  return ivv_e(nd[e].a, iv) || ivv_e(nd[e].b, iv);
}
fn ivv_s(c0: i64, iv: i64, n: i64) -> bool {
  let mut c = c0; let mut i = 0;
  while c >= 0 && i < n { if ivv_st(c, iv) { return true; } c = nd[c].next; i += 1; }
  return false;
}
fn ivv_st(s: i64, iv: i64) -> bool {
  if s < 0 { return false; }
  let k = nd[s].k;
  if k == S_BLOCK || k == S_INL { let mut c = nd[s].a; while c >= 0 { if ivv_st(c, iv) { return true; } c = nd[c].next; } return false; }
  if k == S_IF { return ivv_e(nd[s].a, iv) || ivv_st(nd[s].b, iv) || ivv_st(nd[s].c, iv); }
  if k == S_STORE { return ivv_e(nd[s].b, iv); }
  if k == S_WHILE { return true; }
  if (k == S_LET || k == S_ASSIGN) && vars[nd[s].var].reads == 0 && !has_trap(nd[s].a) { return false; }   // dead: not generated
  return ivv_e(nd[s].a, iv) || ivv_e(nd[s].b, iv);
}
fn hv_e(e: i64, s: i64) {   // invariant variables in vector expressions of e
  if e < 0 { return; }
  let k = nd[e].k;
  if k == N_CONST || k == N_ARR || k == N_NCPU || k == N_CALL { return; }
  if k == N_LOAD { return; }   // its index is scalar code
  if k == N_VAR {
    let v = nd[e].var;
    if !is_v(v) && hv_tag[v] != HV_TAG && vars[v].arr == 0 && count_assign(s, v) == 0 && HV_NEXT + VU <= 32 {
      hv_tag[v] = HV_TAG; hv_reg[v] = HV_NEXT; HV_NEXT += VU;
      vbcast_raw(e, hv_reg[v]);
    }
    return;
  }
  hv_e(nd[e].a, s); hv_e(nd[e].b, s);
}
fn hv_st(c: i64, s: i64) {
  if c < 0 { return; }
  let k = nd[c].k;
  if k == S_BLOCK || k == S_INL { let mut q = nd[c].a; while q >= 0 { hv_st(q, s); q = nd[q].next; } return; }
  if k == S_IF { hv_e(nd[c].a, s); hv_st(nd[c].b, s); hv_st(nd[c].c, s); return; }
  if k == S_STORE { hv_e(nd[c].b, s); return; }
  if k == S_LET || k == S_ASSIGN { if vars[nd[c].var].reads != 0 { hv_e(nd[c].a, s); } return; }
}
fn hv_plan(p: i64, s: i64) {
  HV_NEXT = 16 + (vp_nv[p] + vp_tmp[p] + 1) * VU;
  let body = nd[s].b; let mut c = nd[body].a; let mut i = 0;
  while c >= 0 && i < vp_npre[p] { hv_st(c, s); c = nd[c].next; i += 1; }
}
fn vbcast_raw(e: i64, d: i64) { let sv = HV_TAG; HV_TAG = -1; vbcast(e, d, -1); HV_TAG = sv; }
fn gen_vloop(s: i64, p: i64) -> i64 {
  VP = p; VU = vp_u[p];
  plan_enter(p);
  let mut L = 8 * VU;
  let byt = vp_byte[p];
  if byt { L = 64; }
  let iv = vp_iv[p];
  let mut to_scalar = -1;
  emh("803c25"); u32_(HAS_AVX); byte(0); to_scalar = pl_add(to_scalar, jcc(CC_E));
  let cnd = nd[s].a; let en = nd[cnd].b;
  vtemps(s);
  to_scalar = vguards(p, iv, cnd, en, to_scalar);
  let st = vp_stream[p];
  if byt && vp_brec[p] >= 0 { loc(vp_brec[p]); load(RAX, OK, ORR, OI); alui(A_CMP, RAX, 1); to_scalar = pl_add(to_scalar, jcc(CC_A)); }
  if st { vred_init(p); }
  HV_TAG += 1;
  if st && !byt { hv_plan(p, s); vex3(1, 0, 0, 1, 70, 7, 7, 7); }   // kxnorw k7: k7 only ever holds all ones
  let mut ex = -1;   // exits after the first block (stream loops: through the reduction epilogue)
  let vtop = clen;
  // all L lanes run: i + L - 1 (no overflow) < E  (or <= E)
  let mut er = RCX;
  if nd[en].k == N_VAR { loc(nd[en].var); if OK == K_REG { er = ORR; } }
  if er == RCX { bound_rcx(en); }
  loc(iv); load(RAX, OK, ORR, OI);
  alui(A_ADD, RAX, (L - 1 + vp_cadd[p]) as u64); ex = pl_add(ex, jcc(0));
  alu(A_CMP, K_REG, RAX, K_REG, er, 0);
  if nd[cnd].op == O_LT { ex = pl_add(ex, jcc(CC_GE)); } else { ex = pl_add(ex, jcc(CC_G)); }
  if byt {
    vex3(1, 0, 1, 1, 70, 7, 7, 7);   // kxnorq k7, k7, k7
    let body = nd[s].b; let mut c = nd[body].a; let mut i = 0;
    BREC = vp_brec[p];
    if BREC >= 0 {
      vex3(1, 0, 1, 1, 71, 5, 5, 5);   // kxorq k5: after-mask
      while i < vp_npre[p] { brec_pass(p, c, -1); c = nd[c].next; i += 1; }
      vex3(3, 1, 1, 0, 51, 6, 0, 5); byte(1);           // kshiftlq k6, k5, 1
      loc(BREC); load(RAX, OK, ORR, OI);
      vex3(1, 3, 1, 0, 146, 0, 0, RAX);                 // kmovq k0, rax (carry in: 0 / 1)
      kor64(6, 6, 0);
      vex3(1, 3, 1, 0, 147, RAX, 0, 5); shift_ri(5, RAX, 63);   // flag after the block: lane 63
      loc(BREC); store(OK, ORR, RAX);
      c = nd[body].a; i = 0;
    }
    while i < vp_npre[p] { bgen(p, c, -1); c = nd[c].next; i += 1; }
    BREC = -1;
    loc(iv); alu(A_ADD, OK, ORR, K_IMM, 0, L as u64);
    rel32(jmp(), vtop);
    pl_patch(ex, clen);
    vred_fini(p);
    return to_scalar;
  }
  if !st { vex3(1, 0, 0, 1, 70, 7, 7, 7); }   // kxnorw k7, k7, k7 (stream plans: before the loop)
  let body = nd[s].b;
  // lanes of the induction variable: i + (0, 1, ..), when a vector expression reads i itself
  // (indices are computed in scalar registers)
  let mut h = 0;
  if !st || ivv_s(nd[body].a, iv, vp_npre[p]) {
    loc(iv); load(RAX, OK, ORR, OI);
    let R = VREG[iv];
    while h < VU {
      evx(2, 1, 1, 2, 124, R + h, 0, 0, RAX, 0, false, false);
      VM_TAIL = 0; vm_pool(cp_iota(8 * h)); evx(1, 1, 1, 2, 212, R + h, R + h, 1, 0, 0, false, false);
      h += 1;
    }
  }
  let mut c = nd[body].a;
  let mut i = 0;
  if st {
    while i < vp_npre[p] { sgen(p, c, -1); c = nd[c].next; i += 1; }
    loc(iv); alu(A_ADD, OK, ORR, K_IMM, 0, L as u64);
    rel32(jmp(), vtop);
    pl_patch(ex, clen);
    vred_fini(p);
    return to_scalar;
  }
  to_scalar = pl_cat(to_scalar, ex);
  while i < vp_npre[p] { vstmt(c, -1); c = nd[c].next; i += 1; }
  let post0 = c;
  // PRE results needed by POST go to the scratch area, lane by lane
  let scr = vec_base() + vp_scr[p];
  i = 0;
  while i < vp_nneed[p] {
    let v = vp_need[vp_need0[p] + i];
    h = 0;
    while h < VU { vm_abs(scr + i * 64 * VU + 64 * h); evx(1, 2, 1, 2, 127, VREG[v] + h, 0, 1, 0, 0, false, false); h += 1; }   // vmovdqu64 [..], zmm
    i += 1;
  }
  let lane = vec_base();
  emh("48c70425"); u32_(lane); u32_(0);
  let ltop = clen;
  if vp_nneed[p] > 0 {
    abs_op(139, RAX, lane);
    i = 0;
    while i < vp_nneed[p] {
      let v = vp_need[vp_need0[p] + i];
      let a = scr + i * 64 * VU;
      loc(v);
      if OK == K_REG { lane_load(ORR, false, a); }
      else if OK == K_XMM { lane_load(ORR, true, a); }
      else { lane_load(RCX, false, a); store(OK, ORR, RCX); }
      i += 1;
    }
  }
  c = post0;
  while c >= 0 { gen_stmt(c, false); c = nd[c].next; }
  abs_op(139, RAX, lane); alui(A_ADD, RAX, 1); abs_op(137, RAX, lane); alui(A_CMP, RAX, L as u64);
  rel32(jcc(CC_L), ltop);
  rel32(jmp(), vtop);
  return to_scalar;
}
// ---------------------------------------------------------------- statement codegen
let brk_list = alloc<i64>(65536);
let cont_list = alloc<i64>(65536);
let mut nloopctx: i64 = 0;
fn is_alu_op(op: i64) -> bool { return op == O_ADD || op == O_SUB || op == O_AND || op == O_OR || op == O_XOR; }
fn spine(e: i64, v: i64) -> bool {
  let k = nd[e].k;
  if k == N_VAR { return nd[e].var == v; }
  if k == N_UN { return spine(nd[e].a, v); }
  if k != N_BIN || nd[e].op == O_LAND || nd[e].op == O_LOR { return false; }
  if !spine(nd[e].a, v) && commutes(nd[e].op) && spine(nd[e].b, v) && !refs(nd[e].a, v) { let t = nd[e].a; nd[e].a = nd[e].b; nd[e].b = t; }
  return spine(nd[e].a, v) && !refs(nd[e].b, v);
}
fn gen_inplace(e: i64, r: i64, rg: i64, n: i64) {
  if nd[e].k == N_VAR { return; }
  gen_inplace(nd[e].a, r, rg, n);
  if nd[e].k == N_UN { if !(nd[e].nn != 0 && is_narrow(nd[e].op)) { apply_un(nd[e].op, r); } return; }
  if simple(nd[e].b) { div_nn = nd[e].nn != 0; opnd(nd[e].b); apply(nd[e].op, r, OK, ORR, OI); }
  else { gen(nd[e].b, rg, n); apply(nd[e].op, r, K_REG, RGS[rg], 0); }
}
fn alu_dig(op: i64) -> i64 {
  if op == O_ADD { return A_ADD; } if op == O_SUB { return A_SUB; } if op == O_AND { return A_AND; } if op == O_OR { return A_OR; }
  return A_XOR;
}
// e can be computed directly in v's register: along the left spine no right operand reads v
fn spine_x(e: i64, v: i64) -> bool {
  let k = nd[e].k;
  if k == N_BIN && is_fop(nd[e].op) && !is_fcmp(nd[e].op) { return spine_x(nd[e].a, v) && !refs(nd[e].b, v); }
  if k == N_UN && xunary_inplace(nd[e].op) { return spine_x(nd[e].a, v); }
  return true;
}
fn xunary_inplace(op: i64) -> bool { return op == U_FNEG || op == U_GNEG || op == U_S2D || op == U_D2S || op == U_SQRTD || op == U_SQRTS; }
// float tree into xmm register t (a variable's register, not part of the stack)
fn genf_to(e: i64, t: i64, rg: i64, n: i64) {
  let k = nd[e].k;
  let mut pfx = 243; if fprec(e) { pfx = 242; }
  if k == N_VAR && vars[nd[e].var].xr >= 0 { movx(t, vars[nd[e].var].xr); return; }
  if k == N_BIN && is_fop(nd[e].op) && !is_fcmp(nd[e].op) {
    let o = foc(fop_base(nd[e].op));
    genf_to(nd[e].a, t, rg, n);
    let b = nd[e].b;
    if nd[b].k == N_VAR && vars[nd[b].var].reg < 0 {
      loc(nd[b].var);
      if is_xk(OK) { sse(pfx, 0, o, t, K_REG, ORR); } else { sse(pfx, 0, o, t, OK, ORR); }
      return;
    }
    if hoisted_x(b) >= 0 { sse(pfx, 0, o, t, K_REG, hoisted_x(b)); return; }
    if fmem_ok(b, fprec(e)) { fop_mem(pfx, o, t, b, rg, n); return; }
    let x = xtop; genf(b, x, rg, n); sse(pfx, 0, o, t, K_REG, x); return;
  }
  if k == N_UN && xunary_inplace(nd[e].op) {
    let op = nd[e].op;
    genf_to(nd[e].a, t, rg, n);
    if op == U_FNEG || op == U_GNEG {
      if op == U_FNEG { mov_ri(RAX, 9223372036854775808); } else { mov_ri(RAX, 2147483648); }
      xmov_in(1, K_REG, RAX, 0);
      if op == U_FNEG { byte(102); }
      encr(0, false, 2, 15, 87, t, 1); return;
    }
    if op == U_S2D { sse(243, 0, 90, t, K_REG, t); return; }
    if op == U_D2S { sse(242, 0, 90, t, K_REG, t); return; }
    if op == U_SQRTD { sse(242, 0, 81, t, K_REG, t); return; }
    sse(243, 0, 81, t, K_REG, t); return;
  }
  if k == N_CONST || k == N_VAR || (k == N_LOAD && ty_flt(fld_ty(nd[e].var, nd[e].op))) { genf(e, t, rg, n); return; }
  let x = xtop; genf(e, x, rg, n); movx(t, x);
}
// x = e for a float variable held in an xmm register
fn assign_x(xr: i64, dbl: bool, v: i64, e: i64, rg: i64, n: i64) {
  let k = nd[e].k;
  if k == N_CONST {
    let hx = hoisted_x(e);
    if hx >= 0 { movx(xr, hx); }
    else if nd[e].v == 0 { byte(102); encr(0, false, 2, 15, 239, xr, xr); }
    else { mov_ri(RAX, nd[e].v); sse(102, 1, 110, xr, K_REG, RAX); }
    return;
  }
  if k == N_VAR { loc(nd[e].var); xmov_in(xr, OK, ORR, OI); return; }
  if xroom(e) {
    if spine_x(e, v) { genf_to(e, xr, rg, n); return; }
    let x = xtop; genf(e, x, rg, n); movx(xr, x); return;
  }
  gen(e, rg, n); sse(102, dbl as i64, 110, xr, K_REG, RGS[rg]);
}
fn assign(v: i64, e: i64, rg: i64, n: i64) {
  loc(v);
  let Lk = OK; let Lr = ORR;
  if is_xk(Lk) { assign_x(Lr, Lk == K_XMM, v, e, rg, n); return; }
  if xroom(e) {
    if Lk == K_REG { genf_root(e, Lr, rg, n); }
    else if Lk == K_MEM && vars[v].ty == TY_F64 && fprec(e) { let x = xtop; genf(e, x, rg, n); sse(242, 0, 17, x, K_MEM, Lr); }   // movsd [slot], x
    else { genf_root(e, RAX, rg, n); store(Lk, Lr, RAX); }
    return;
  }
  let k = nd[e].k;
  if Lk == K_REG && k != N_VAR && spine(e, v) { gen_inplace(e, Lr, rg, n); return; }
  let op = nd[e].op;
  if k == N_BIN && (is_alu_op(op) || op == O_MUL || op == O_SHL || op == O_SHR || op == O_SAR) {
    let mut a = nd[e].a; let mut b = nd[e].b;
    if commutes(op) && !(nd[a].k == N_VAR && nd[a].var == v) && nd[b].k == N_VAR && nd[b].var == v { let t = a; a = b; b = t; }
    // b is computed (into a temporary) before v changes, so b may read v
    if nd[a].k == N_VAR && nd[a].var == v && (!refs(b, v) || !has_call(b)) {
      if Lk == K_REG {
        if simple(b) { opnd(b); apply(op, Lr, OK, ORR, OI); } else { gen(b, rg, n); apply(op, Lr, K_REG, RGS[rg], 0); }
        return;
      }
      if is_alu_op(op) {
        let mut sk = 0; let mut sr = 0; let mut si: u64 = 0;
        if simple(b) { opnd(b); sk = OK; sr = ORR; si = OI; if sk == K_MEM { load(RGS[rg], sk, sr, si); sk = K_REG; sr = RGS[rg]; si = 0; } }
        else { gen(b, rg, n); sk = K_REG; sr = RGS[rg]; }
        alu(alu_dig(op), Lk, Lr, sk, sr, si);
        return;
      }
    }
  }
  if k == N_CONST {
    let cv = nd[e].v;
    if Lk == K_REG { mov_ri(Lr, cv); }
    else if fits_s32(cv) { enc(1, false, 1, 199, 0, 0, Lk, Lr); u32_(cv as i64); }
    else { mov_ri(RAX, cv); store(Lk, Lr, RAX); }
    return;
  }
  if k == N_VAR {
    loc(nd[e].var);
    let sk = OK; let sr = ORR;
    if Lk == K_REG { load(Lr, sk, sr, 0); } else if sk == K_REG { store(Lk, Lr, sr); } else { load(RAX, sk, sr, 0); store(Lk, Lr, RAX); }
    return;
  }
  if Lk == K_REG && (!refs(e, v) || ld_idx_only(e, v) || div_simple(e)) {
    let r2 = rgs_top; rgs_top += n + 1;
    RGS[r2] = Lr;
    let mut i = 0;
    while i < n { RGS[r2 + 1 + i] = RGS[rg + i]; i += 1; }
    gen(e, r2, n + 1);
    rgs_top -= n + 1;
    return;
  }
  gen(e, rg, n); store(Lk, Lr, RGS[rg]);
}
// e is (conversions of) a load a[v]: v is read only as the index register, before the load
// writes the destination, so the result can go straight into v's register (t = rgt[t])
// a / b or a % b on plain integer variables: gen reads both into rax / the divisor first
fn div_simple(e: i64) -> bool {
  if nd[e].k != N_BIN { return false; }
  let op = nd[e].op; let a = nd[e].a; let b = nd[e].b;
  return (op == O_DIV || op == O_MOD || op == O_DIVU || op == O_MODU) && simple(a) && simple(b) && !is_const(b) && !xvar_node(a) && !xvar_node(b) && ty_int(nd[e].ty);
}
fn ld_idx_only(e: i64, v: i64) -> bool {
  let mut x = e;
  while nd[x].k == N_UN && (nd[x].op >= U_SX8 && nd[x].op <= U_ZX32) { x = nd[x].a; }
  return nd[x].k == N_LOAD && nd[nd[x].a].k == N_VAR && nd[nd[x].a].var == v && !ty_flt(nd[x].ty);
}
fn sys_save() { emh("56574150415141524153"); }
fn sys_restore() { emh("415b415a415941585f5e"); }
fn trap_if(cc: i64) { trap_list = pl_add(trap_list, jcc(cc)); }
fn gen_arr(s: i64, rg: i64, n: i64) {
  let a = nd[s].var;
  let w = vars[a].arr;
  let op = nd[s].op;
  if op == A_STR {
    if vars[vars[a].basev].reads != 0 {
      loc(vars[a].basev);
      let bk = OK; let bb = ORR;
      let mut r = RAX; if bk == K_REG { r = bb; }
      if (r & 8) != 0 { byte(65); }
      byte(184 | (r & 7)); str_site(clen, nd[s].v as i64); u32_(0);
      if bk != K_REG { store(bk, bb, RAX); }
    }
    return;
  }
  if op == A_VIEW {
    if vars[a].lenv >= 0 && vars[vars[a].lenv].reads != 0 {
      loc(vars[nd[s].c].lenv); load(RAX, OK, ORR, OI);
      if (w & (w - 1)) == 0 { shift_ri(5, RAX, lg(w)); } else { mov_ri(RCX, w as u64); emh("31d2"); unop(6, K_REG, RCX); }
      loc(vars[a].lenv); store(OK, ORR, RAX);
    }
    return;
  }
  if op == A_ALLOC {
    let mut rs = -1;
    if vars[a].lenv >= 0 {
      gen(nd[s].a, rg, n); rs = RGS[rg];
      mov_rr(RAX, rs); lea(RCX, RAX, -1, -1); alui(A_CMP, RCX, 2147483646); trap_if(7);
    } else { mov_ri(RAX, vars[a].alen as u64); }
    if (w & (w - 1)) == 0 { shift_ri(4, RAX, lg(w)); } else { imul_r(RAX, K_IMM, 0, w as u64); }
    if nd[s].v != 0 {
      alui(A_ADD, RAX, 15); alui(A_AND, RAX, 18446744073709551600);
      abs_op(139, RCX, ARENA_TOP);
      alui(A_ADD, RCX, 63); alui(A_AND, RCX, 18446744073709551552);
      lea(RDX, RCX, RAX, 0);
      abs_op(59, RDX, ARENA_END); trap_if(7);
      abs_op(137, RDX, ARENA_TOP);
      emh("574889cf4889ca4889c131c0f3aa5f4889d0");
      if vars[vars[a].basev].reads != 0 { loc(vars[a].basev); store(OK, ORR, RAX); }
      if vars[a].lenv >= 0 && vars[vars[a].lenv].reads != 0 { loc(vars[a].lenv); store(OK, ORR, rs); }
      return;
    }
    if vars[a].shared == 0 {
      // bump allocation from a lazily faulted reservation (fresh pages are zero); the stub maps
      // a new chunk when it runs out. One syscall per gigabyte instead of one per array.
      alui(A_ADD, RAX, 63); alui(A_AND, RAX, 18446744073709551552);
      abs_op(139, RCX, HEAP_TOP);
      lea(RDX, RCX, RAX, 0);
      abs_op(59, RDX, HEAP_END);
      let fast = jcc(CC_BE);
      heap_calls = call_to(heap_calls);
      let done = jmp();
      rel32(fast, clen);
      abs_op(137, RDX, HEAP_TOP); mov_rr(RAX, RCX);
      rel32(done, clen);
      if vars[vars[a].basev].reads != 0 { loc(vars[a].basev); store(OK, ORR, RAX); }
      if vars[a].lenv >= 0 && vars[vars[a].lenv].reads != 0 { loc(vars[a].lenv); store(OK, ORR, rs); }
      return;
    }
    sys_save();
    emh("4889c6"); emh("31ff"); emh("ba03000000");
    if vars[a].shared != 0 { emh("41ba21000000"); } else { emh("41ba22000000"); }
    emh("49c7c0ffffffff"); emh("4531c9"); emh("b8090000000f05");
    sys_restore();
    emh("483d00f0ffff"); trap_if(7);
    if vars[vars[a].basev].reads != 0 { loc(vars[a].basev); store(OK, ORR, RAX); }
    if vars[a].lenv >= 0 && vars[vars[a].lenv].reads != 0 { loc(vars[a].lenv); store(OK, ORR, rs); }
    return;
  }
  gen(nd[s].a, rg, n);
  let rk = RGS[rg];
  loc(0); alu(A_CMP, K_REG, rk, OK, ORR, OI); trap_if(CC_AE);
  loc(1); load(RAX, OK, ORR, OI); mov_rr(RCX, rk); memop(1, false, false, 1, 139, 0, RAX, RAX, RCX, 3);
  if op == A_ARG { // strlen: rax = argv[k], rcx = length
    emh("31c9"); let top = clen; emh("803c0800"); let z = j8(116); emh("48ffc1"); p8(j8(235), top); p8(z, clen);
    if vars[vars[a].basev].reads != 0 { loc(vars[a].basev); store(OK, ORR, RAX); }
    if vars[vars[a].lenv].reads != 0 { loc(vars[a].lenv); store(OK, ORR, RCX); }
    return;
  }
  sys_save();
  emh("4889c731f6b8020000000f05");
  test_rr(RAX); trap_if(CC_S);
  emh("4989c0");
  emh("4889c731f6ba02000000b8080000000f05");
  test_rr(RAX); trap_if(CC_S);
  emh("4889c6");
  emh("31c0"); test_rr(RSI); let jz = jcc(CC_E);
  emh("31ffba0100000041ba020000004531c9b8090000000f05");
  emh("483d00f0ffff"); trap_if(7);
  rel32(jz, clen);
  emh("4989c14c89c7b8030000000f05");
  emh("4c89c84889f1");
  sys_restore();
  if vars[vars[a].basev].reads != 0 { loc(vars[a].basev); store(OK, ORR, RAX); }
  if vars[vars[a].lenv].reads != 0 { loc(vars[a].lenv); store(OK, ORR, RCX); }
}
let inl_list = alloc<i64>(65536);
let mut ninlctx: i64 = 0;
fn terminates(s: i64) -> bool {
  if s < 0 { return false; }
  let k = nd[s].k;
  if k == S_RET || k == S_BRK || k == S_CONT || k == S_IRET { return true; }
  if k == S_BLOCK { let mut last = -1; let mut c = nd[s].a; while c >= 0 { last = c; c = nd[c].next; } return terminates(last); }
  if k == S_IF { return nd[s].c >= 0 && terminates(nd[s].b) && terminates(nd[s].c); }
  return false;
}
let mut cur_pos: i64 = -1;   // pc of the statement being generated (call sites save what is live there)
fn gen_stmt(s: i64, is_final: bool) {
  let k = nd[s].k;
  let rg = rgs_top;
  rgs_top += 12;
  let mut n = 0;
  let sv_pos = cur_pos; let sv_st = cur_stmt;
  if k != S_BLOCK && k != S_BRK && k != S_CONT && k != S_INL {
    n = temps_at(nd[s].pos);
    let mut i = 0;
    while i < n { RGS[rg + i] = TMPS[i]; i += 1; }
    cur_pos = nd[s].pos;
    cur_stmt = -1;
    if k == S_LET || k == S_ASSIGN || k == S_IRET || k == S_RET || k == S_EXPR || k == S_STORE || k == S_IF || k == S_PRINT || k == S_PUTC { cur_stmt = s; }
  }
  gen_stmt_body(s, is_final, rg, n);
  cur_pos = sv_pos; cur_stmt = sv_st;
  rgs_top -= 12;
}
// ---- if-conversion: inside loops, `if C { x = e; .. } else { y = f; .. }` with a few integer
// assignments whose right sides cannot trap or touch memory becomes branch-free cmov selects
// (unpredictable branches on text and DP data cost more than computing both sides)
fn ic_pure(e: i64) -> bool {
  if e < 0 { return true; }
  let k = nd[e].k;
  if k == N_LOAD || k == N_CALL || k == N_NCPU { return false; }
  if !(ty_int(nd[e].ty) || nd[e].ty == TY_BOOL) { return false; }
  if k == N_VAR { return vars[nd[e].var].xr < 0 && vars[nd[e].var].glob == 0; }
  if k == N_CONST || k == N_ARR { return true; }
  if has_trap(e) { return false; }
  if k == N_UN && !(nd[e].op == U_NEG || nd[e].op == U_NOT || nd[e].op == U_LNOT || (nd[e].op >= U_SX8 && nd[e].op <= U_ZX32)) { return false; }
  return ic_pure(nd[e].a) && ic_pure(nd[e].b);
}
fn ic_count(s: i64, d: i64) -> i64 {   // assignments in a branch, -1 when not convertible (d: nesting)
  if s < 0 { return 0; }
  let k = nd[s].k;
  if k == S_BLOCK { let mut t = 0; let mut c = nd[s].a; while c >= 0 { let x = ic_count(c, d); if x < 0 { return -1; } t += x; c = nd[c].next; } return t; }
  if k == S_IF && d == 0 && nd[s].c < 0 && ic_cond_ok(nd[s].a) && ic_pure(nd[s].a) { let x = ic_count(nd[s].b, 1); if x < 0 { return -1; } IC_NEST = true; return x + 1; }
  if k != S_ASSIGN { return -1; }
  let v = nd[s].var;
  if !ty_int(vars[v].ty) || vars[v].xr >= 0 || vars[v].glob != 0 || vars[v].reads == 0 { return -1; }
  if !ic_pure(nd[s].a) { return -1; }
  return 1;
}
fn ic_cond_ok(e: i64) -> bool {   // evaluated without branches: && / || need side-effect-free, load-free right sides
  if nd[e].ty != TY_BOOL || has_call(e) { return false; }
  if nd[e].k == N_BIN && (nd[e].op == O_LAND || nd[e].op == O_LOR) { return ic_cond_ok(nd[e].a) && ic_pure(nd[e].b) && ic_cond_ok(nd[e].b); }
  if nd[e].k == N_UN && nd[e].op == U_LNOT { return ic_cond_ok(nd[e].a); }
  return nd[e].k == N_BIN && is_cmp(nd[e].op) && ty_int(nd[nd[e].a].ty);
}
let mut IC_NEST: bool = false;
fn ifconv_ok(s: i64, n: i64) -> bool {
  if !ic_cond_ok(nd[s].a) { return false; }
  IC_NEST = false;
  let a = ic_count(nd[s].b, 0); let b = ic_count(nd[s].c, 0);
  return a >= 0 && b >= 0 && a + b >= 1 && a + b <= 4;
}
// condition -> 0/1 in RGS[rg]
fn ic_bool(e: i64, rg: i64, n: i64) {
  let k = nd[e].k;
  if k == N_BIN && (nd[e].op == O_LAND || nd[e].op == O_LOR) {
    let mut d = A_AND; if nd[e].op == O_LOR { d = A_OR; }
    if n >= 2 {
      ic_bool(nd[e].a, rg, n); ic_bool(nd[e].b, rg + 1, n - 1);
      alur(d, RGS[rg], RGS[rg + 1]); return;
    }
    let sl = tslot_push();
    ic_bool(nd[e].a, rg, n); store(K_MEM, sl, RGS[rg]);
    ic_bool(nd[e].b, rg, n);
    alu(d, K_REG, RGS[rg], K_MEM, sl, 0);
    tdepth -= 1; return;
  }
  if k == N_UN { ic_bool(nd[e].a, rg, n); alui(A_XOR, RGS[rg], 1); return; }
  gen(e, rg, n);
}
fn cmov_rr(cc: i64, d: i64, sr: i64) { encr(1, false, 2, 15, 64 | cc, d, sr); }
// statements of a branch under predicate (temp slot sl != 0) == want
fn ic_gen(s: i64, sl: i64, rg: i64, n: i64, want: bool) {
  if s < 0 { return; }
  let k = nd[s].k;
  if k == S_BLOCK { let mut c = nd[s].a; while c >= 0 { ic_gen(c, sl, rg, n, want); c = nd[c].next; } return; }
  if k == S_IF {   // nested condition: p = (pred == want) and C
    ic_bool(nd[s].a, rg, n);
    let r = RGS[rg];
    if want { alu(A_AND, K_REG, r, K_MEM, sl, 0); } else { load(RAX, K_MEM, sl, 0); alui(A_XOR, RAX, 1); alur(A_AND, r, RAX); }
    let s2 = tslot_push(); store(K_MEM, s2, r);
    ic_gen(nd[s].b, s2, rg, n, true);
    tdepth -= 1;
    return;
  }
  let v = nd[s].var;
  gen(nd[s].a, rg, n);
  let t = RGS[rg];
  alu(A_CMP, K_MEM, sl, K_IMM, 0, 0);
  let mut cc = CC_NE; if !want { cc = CC_E; }
  loc(v);
  if OK == K_REG { cmov_rr(cc, ORR, t); }
  else { enc(1, false, 2, 15, 64 | (cc ^ 1), t, OK, ORR); loc(v); store(OK, ORR, t); }   // t = cond ? t : v; v = t
}
// one assignment under one comparison: value, cmp, cmov (no predicate materialized)
fn ic_single(s: i64) -> i64 {   // the assignment statement, or -1
  let c = nd[s].a;
  if nd[c].k != N_BIN || !is_cmp(nd[c].op) || nd[s].c >= 0 { return -1; }
  let mut b = nd[s].b;
  if nd[b].k == S_BLOCK { b = nd[b].a; if b < 0 || nd[b].next >= 0 { return -1; } }
  if nd[b].k != S_ASSIGN { return -1; }
  return b;
}
// flat branches under one comparison: every value first, then the compare, then the cmovs
// (mov and store keep the flags); needs no assignment to read a variable its branch set earlier
fn ic_list(b: i64) -> i64 { if nd[b].k == S_BLOCK { return nd[b].a; } return b; }
fn ic_indep(b: i64) -> bool {
  let mut c = ic_list(b);
  while c >= 0 {
    if nd[c].k != S_ASSIGN { return false; }
    let mut q = ic_list(b);
    while q != c { if nd[q].var == nd[c].var || ex_reads(nd[c].a, nd[q].var) != 0 { return false; } q = nd[q].next; }
    c = nd[c].next;
  }
  return true;
}
fn ic_nlist(b: i64) -> i64 { if b < 0 { return 0; } let mut t = 0; let mut c = ic_list(b); while c >= 0 { t += 1; c = nd[c].next; } return t; }
let IC_SRC = alloc<i64>(16);   // per assignment: source register, or -1 for v += 1 (added from setcc)
fn ic_reg_src(e: i64) -> bool { return nd[e].k == N_VAR && vars[nd[e].var].reg >= 0; }
fn ic_vals(b: i64, i0: i64, rg: i64, n: i64, j0: i64) -> i64 {   // sources into IC_SRC[i0..]; returns regs used
  if b < 0 { return j0; }
  let mut i = i0; let mut j = j0; let mut c = ic_list(b);
  while c >= 0 {
    let e = nd[c].a;
    if is_inc1(c, nd[c].var) { IC_SRC[i] = -1; }
    else if ic_reg_src(e) { IC_SRC[i] = vars[nd[e].var].reg; }
    else { gen(e, rg + j, n - j); IC_SRC[i] = RGS[rg + j]; j += 1; }
    i += 1; c = nd[c].next;
  }
  return j;
}
fn ic_need(b: i64) -> i64 {
  if b < 0 { return 0; }
  let mut m = 0; let mut c = ic_list(b);
  while c >= 0 { if !is_inc1(c, nd[c].var) && !ic_reg_src(nd[c].a) { m += 1; } c = nd[c].next; }
  return m;
}
fn ic_cmovs(b: i64, i0: i64, cc: i64) -> i64 {
  if b < 0 { return i0; }
  let mut i = i0; let mut c = ic_list(b);
  while c >= 0 {
    let t = IC_SRC[i]; let v = nd[c].var;
    if t >= 0 {
      loc(v);
      if OK == K_REG { if ORR != t { cmov_rr(cc, ORR, t); } }
      else { mov_rr(RAX, t); enc(1, false, 2, 15, 64 | (cc ^ 1), RAX, OK, ORR); loc(v); store(OK, ORR, RAX); }
    }
    i += 1; c = nd[c].next;
  }
  return i;
}
fn ic_incs(b: i64, i0: i64, r: i64) -> i64 {   // v += r for the v += 1 assignments (r = predicate 0/1)
  if b < 0 { return i0; }
  let mut i = i0; let mut c = ic_list(b);
  while c >= 0 { if IC_SRC[i] < 0 { loc(nd[c].var); alu(A_ADD, OK, ORR, K_REG, r, 0); } i += 1; c = nd[c].next; }
  return i;
}
fn ic_multi(s: i64, rg: i64, n: i64) -> bool {
  let c = nd[s].a;
  if IC_NEST || nd[c].k != N_BIN || !is_cmp(nd[c].op) { return false; }
  let k1 = ic_nlist(nd[s].b); let k = k1 + ic_nlist(nd[s].c);
  if k > 16 || !ic_indep(nd[s].b) || (nd[s].c >= 0 && !ic_indep(nd[s].c)) { return false; }
  let m = ic_need(nd[s].b) + ic_need(nd[s].c);   // registers the values need
  let mut ia = m; let ib = m; if !simple(nd[c].b) { ia += 1; }   // b's register, then a's
  let mut need = ia; if !simple(nd[c].a) { need += 1; }
  if n < need + 1 { return false; }
  let j = ic_vals(nd[s].b, 0, rg, n, 0);
  ic_vals(nd[s].c, k1, rg, n, j);
  let mut rb = -1;   // b before a: generating b may use rax
  if !simple(nd[c].b) { gen(nd[c].b, rg + ib, n - ib); rb = RGS[rg + ib]; }
  let mut ra = RAX;
  if simple(nd[c].a) { opnd(nd[c].a); if OK == K_REG { ra = ORR; } else { load(RAX, OK, ORR, OI); } }   // a register variable is compared in place
  else { gen(nd[c].a, rg + ia, n - ia); ra = RGS[rg + ia]; }
  let mut ninc1 = 0; let mut ninc2 = 0; let mut q = 0;
  while q < k { if IC_SRC[q] < 0 { if q < k1 { ninc1 += 1; } else { ninc2 += 1; } } q += 1; }
  // v += 1 under the predicate: rcx / rdx (never temporaries) are zeroed before the compare and
  // receive setcc / its negation, so each increment is one add after the flags
  if ninc1 > 0 { emh("31c9"); }   // xor ecx, ecx
  if ninc2 > 0 { emh("31d2"); }   // xor edx, edx
  if rb < 0 { opnd(nd[c].b); alu(A_CMP, K_REG, ra, OK, ORR, OI); }
  else { alu(A_CMP, K_REG, ra, K_REG, rb, 0); }
  let cc = cc_of(nd[c].op);
  ic_cmovs(nd[s].c, ic_cmovs(nd[s].b, 0, cc), cc ^ 1);
  if ninc1 > 0 { encr(0, false, 2, 15, 144 | cc, 0, RCX); }         // setcc cl
  if ninc2 > 0 { encr(0, false, 2, 15, 144 | (cc ^ 1), 0, RDX); }   // set!cc dl
  if ninc1 > 0 { ic_incs(nd[s].b, 0, RCX); }
  if ninc2 > 0 { ic_incs(nd[s].c, k1, RDX); }
  return true;
}
fn ifconv(s: i64, rg: i64, n: i64) {
  let one = ic_single(s);
  let c0 = nd[s].a;
  if one >= 0 && (n >= 3 || (simple(nd[c0].a) && simple(nd[c0].b))) {
    let c = nd[s].a;
    gen(nd[one].a, rg, n);
    let t = RGS[rg];
    let sa = !simple(nd[c].a) && expr_same(nd[c].a, nd[one].a);   // `if e < v { v = e }`: e once
    let sb = !simple(nd[c].b) && expr_same(nd[c].b, nd[one].a);
    let mut rb = -1;   // b before a: generating b may use rax
    let mut ia = 1;   // a's register comes after b's: generating a must not clobber b
    if sb { rb = t; } else if !simple(nd[c].b) { gen(nd[c].b, rg + 1, n - 1); rb = RGS[rg + 1]; ia = 2; }
    let mut ra = RAX;
    if sa { ra = t; }
    else if simple(nd[c].a) { opnd(nd[c].a); if OK == K_REG { ra = ORR; } else { load(RAX, OK, ORR, OI); } }
    else { gen(nd[c].a, rg + ia, n - ia); ra = RGS[rg + ia]; }
    if rb < 0 { opnd(nd[c].b); alu(A_CMP, K_REG, ra, OK, ORR, OI); }
    else { alu(A_CMP, K_REG, ra, K_REG, rb, 0); }
    let cc = cc_of(nd[c].op);
    loc(nd[one].var);
    if OK == K_REG { cmov_rr(cc, ORR, t); }
    else { enc(1, false, 2, 15, 64 | (cc ^ 1), t, OK, ORR); loc(nd[one].var); store(OK, ORR, t); }
    return;
  }
  if ic_multi(s, rg, n) { return; }
  ic_bool(nd[s].a, rg, n);
  let sl = tslot_push(); store(K_MEM, sl, RGS[rg]);
  ic_gen(nd[s].b, sl, rg, n, true);
  ic_gen(nd[s].c, sl, rg, n, false);
  tdepth -= 1;
}
// ---- copy loops: `while i < E { [let j = i + X;] .. A[i + Xd] = B[i + Xs]; .. i += 1 }` over static
// arrays (distinct between statements, same element width) becomes one `rep movs` per statement when
// every copied range is in bounds; otherwise the checked loop runs (and traps where it did).
// A forward element-by-element copy is exactly what rep movs does, overlap included.
let CP_A = alloc<i64>(16);
let CP_B = alloc<i64>(16);
let CP_DX = alloc<i64>(16);   // offset expression of the destination index (-1: none)
let CP_SX = alloc<i64>(16);
let CP_LV = alloc<i64>(16);   // let variables -> their offset expressions
let CP_LX = alloc<i64>(16);
let CP_LU = alloc<i64>(16);   // uses of each let variable
let mut CP_NL: i64 = 0;
let mut CP_N: i64 = 0;
let mut CP_IV: i64 = -1;
let mut CP_DONE: i64 = -1;
let mut CP_X: i64 = -1;
fn cpl_off(x: i64) -> bool {   // x is iv + X (X simple, not iv), X + iv or iv: CP_X = X (-1 for none)
  if nd[x].k == N_VAR && nd[x].var == CP_IV { CP_X = -1; return true; }
  if nd[x].k == N_VAR { let mut q = 0; while q < CP_NL { if CP_LV[q] == nd[x].var { CP_X = CP_LX[q]; CP_LU[q] += 1; return true; } q += 1; } return false; }
  if nd[x].k != N_BIN || nd[x].op != O_ADD || nd[x].ty != TY_I64 { return false; }
  let a = nd[x].a; let b = nd[x].b;
  if nd[a].k == N_VAR && nd[a].var == CP_IV && simple(b) && !(nd[b].k == N_VAR && nd[b].var == CP_IV) { CP_X = b; return true; }
  if nd[b].k == N_VAR && nd[b].var == CP_IV && simple(a) && !(nd[a].k == N_VAR && nd[a].var == CP_IV) { CP_X = a; return true; }
  return false;
}
fn cpl_static(a: i64) -> bool { return vars[a].arr != 0 && vars[a].arr <= 8 && (vars[a].arr & (vars[a].arr - 1)) == 0 && vars[a].lenv < 0 && vars[vars[a].basev].isconst != 0 && vars[a].alen > 0; }
fn cpl_match(w: i64) -> bool {
  let cnd = nd[w].a; let body = nd[w].b;
  if nd[w].c >= 0 || nd[cnd].k != N_BIN || (nd[cnd].op != O_LT && nd[cnd].op != O_LE) || nd[nd[cnd].a].k != N_VAR || !simple(nd[cnd].b) { return false; }
  CP_IV = nd[nd[cnd].a].var;
  if vars[CP_IV].ty != TY_I64 || nd[nd[cnd].b].ty != TY_I64 || (nd[nd[cnd].b].k == N_VAR && nd[nd[cnd].b].var == CP_IV) { return false; }
  if body < 0 || nd[body].k != S_BLOCK { return false; }
  CP_N = 0; CP_NL = 0;
  let mut c = nd[body].a; let mut last = -1;
  while c >= 0 {
    let k = nd[c].k;
    if nd[c].next < 0 { last = c; break; }
    if k == S_LET && CP_N == 0 {
      if CP_NL >= 16 || !cpl_off(nd[c].a) { return false; }
      if nd[nd[c].a].k == N_VAR && nd[nd[c].a].var != CP_IV { return false; }   // a copy of another let
      CP_LV[CP_NL] = nd[c].var; CP_LX[CP_NL] = CP_X; CP_LU[CP_NL] = 0; CP_NL += 1;
    } else if k == S_STORE {
      let v = nd[c].b;
      if CP_N >= 16 || nd[c].op >= 0 || nd[c].c >= 0 || nd[v].k != N_LOAD || nd[v].op > 0 { return false; }
      let A = nd[c].var; let B = nd[v].var;
      if !cpl_static(A) || !cpl_static(B) || vars[A].arr != vars[B].arr { return false; }
      if !cpl_off(nd[c].a) { return false; } CP_DX[CP_N] = CP_X;
      if !cpl_off(nd[v].a) { return false; } CP_SX[CP_N] = CP_X;
      CP_A[CP_N] = A; CP_B[CP_N] = B; CP_N += 1;
    } else { return false; }
    c = nd[c].next;
  }
  if last < 0 || CP_N == 0 || !is_inc1(last, CP_IV) || count_assign(w, CP_IV) != 1 { return false; }
  // the lets are only these indices
  let mut q = 0; while q < CP_NL { if vars[CP_LV[q]].reads != CP_LU[q] { return false; } q += 1; }
  // statements touch pairwise distinct arrays (a statement may copy within one array)
  let mut i = 0;
  while i < CP_N {
    let mut j = 0;
    while j < CP_N {
      if i != j {
        let ai = vars[CP_A[i]].basev; let bi = vars[CP_B[i]].basev; let aj = vars[CP_A[j]].basev; let bj = vars[CP_B[j]].basev;
        if ai == aj || ai == bj || bi == aj { return false; }
      }
      j += 1;
    }
    i += 1;
  }
  // offsets are not assigned by the loop (only the increment and the lets run in it)
  return true;
}
fn cpl_index(x: i64) {   // rax = iv + X
  loc(CP_IV); load(RAX, OK, ORR, OI);
  if x >= 0 { opnd(x); alu(A_ADD, K_REG, RAX, OK, ORR, OI); }
}
fn cpl_range(a: i64, x: i64, sn: i64, fb: i64) -> i64 {   // address of a[iv + X] into rax; fb: fallback list
  let mut f = fb;
  cpl_index(x);
  mov_ri(RDX, vars[a].alen as u64);
  alu(A_CMP, K_REG, RAX, K_REG, RDX, 0); f = pl_add(f, jcc(CC_AE));        // 0 <= lo < len (unsigned)
  alur(A_SUB, RDX, RAX); load(RCX, K_MEM, sn, 0);
  alu(A_CMP, K_REG, RCX, K_REG, RDX, 0); f = pl_add(f, jcc(CC_A));         // n <= len - lo
  shift_ri(4, RAX, lg(vars[a].arr));
  base_opnd(a); alu(A_ADD, K_REG, RAX, OK, ORR, OI);
  return f;
}
fn cpl_gen(w: i64) -> i64 {   // emits the fast copy; returns the fallback patch list (the checked loop follows)
  let cnd = nd[w].a; let le = nd[cnd].op == O_LE; let E = nd[cnd].b;
  let mut fb = -1; let mut done = -1;
  loc(CP_IV); load(RAX, OK, ORR, OI);
  opnd(E); load(RCX, OK, ORR, OI);
  alu(A_CMP, K_REG, RAX, K_REG, RCX, 0);
  if le { done = pl_add(done, jcc(CC_G)); } else { done = pl_add(done, jcc(CC_GE)); }   // the loop does not run
  alur(A_SUB, RCX, RAX);
  if le { alui(A_ADD, RCX, 1); fb = pl_add(fb, jcc(CC_E)); }   // 2^64 iterations: leave it to the loop
  let sn = tslot_push(); store(K_MEM, sn, RCX);
  tslot_push(); tslot_push(); let ssi = tslot_push(); let sdi = tslot_push();
  let mut i = 0;
  let base = tdepth;
  while i < CP_N { tslot_push(); tslot_push(); i += 1; }
  i = 0;
  while i < CP_N {
    fb = cpl_range(CP_A[i], CP_DX[i], sn, fb); store(K_MEM, tbase + base + 2 * i, RAX);
    fb = cpl_range(CP_B[i], CP_SX[i], sn, fb); store(K_MEM, tbase + base + 2 * i + 1, RAX);
    i += 1;
  }
  store(K_MEM, ssi, RSI); store(K_MEM, sdi, RDI);
  i = 0;
  while i < CP_N {
    load(RDI, K_MEM, tbase + base + 2 * i, 0); load(RSI, K_MEM, tbase + base + 2 * i + 1, 0); load(RCX, K_MEM, sn, 0);
    let wd = vars[CP_A[i]].arr;
    if wd == 8 { emh("f348a5"); } else if wd == 4 { emh("f3a5"); } else if wd == 2 { emh("66f3a5"); } else { emh("f3a4"); }
    i += 1;
  }
  load(RSI, K_MEM, ssi, 0); load(RDI, K_MEM, sdi, 0);
  // iv = E (+ 1)
  opnd(E); load(RAX, OK, ORR, OI); if le { alui(A_ADD, RAX, 1); }
  loc(CP_IV); store(OK, ORR, RAX);
  tdepth -= 5 + 2 * CP_N;
  done = pl_add(done, jmp());
  CP_DONE = done;
  return fb;
}
fn gen_stmt_body(s: i64, is_final: bool, rg: i64, n: i64) {
  let k = nd[s].k;
  if k == S_LET || k == S_ASSIGN {
    if vars[nd[s].var].reads == 0 { if has_trap(nd[s].a) { gen(nd[s].a, rg, n); } return; }
    assign(nd[s].var, nd[s].a, rg, n); return;
  }
  if k == S_IF {
    if is_const(nd[s].a) { if nd[nd[s].a].v != 0 { gen_stmt(nd[s].b, false); } else if nd[s].c >= 0 { gen_stmt(nd[s].c, false); } return; }
    if nloopctx > 0 && n >= 2 && ifconv_ok(s, n) { ifconv(s, rg, n); return; }
    let mut f = -1; let mut en = -1;
    f = cond_jump(nd[s].a, false, f, rg, n); gen_stmt(nd[s].b, false);
    if nd[s].c >= 0 { if !terminates(nd[s].b) { en = pl_add(en, jmp()); } pl_patch(f, clen); gen_stmt(nd[s].c, false); pl_patch(en, clen); }
    else { pl_patch(f, clen); }
    return;
  }
  if k == S_WHILE {
    if is_const(nd[s].a) && nd[nd[s].a].v == 0 { return; }
    let mut entry = -1; let mut back = -1;
    let mut v = -1;
    if nd[s].var >= 0 { v = hl_head[nd[s].var] - 1; }
    while v >= 0 {
      if vars[v].hoist == nd[s].var + 1 {
        if vars[v].reg >= 0 { mov_ri(vars[v].reg, vars[v].cval); }
        else if vars[v].xr >= 0 { mov_ri(RAX, vars[v].cval); sse(102, 1, 110, vars[v].xr, K_REG, RAX); }
      }
      v = hl_next[v] - 1;
    }
    let m = nd[s].c;
    if m >= 0 { abs_op(139, RAX, ARENA_TOP); loc(m); store(OK, ORR, RAX); }
    // An innermost loop with a simple test is generated, measured and, when its back edge (cmp + jcc)
    // would cross or end on a 32-byte line, rewound and generated again behind more (never
    // executed) head padding: the JCC erratum makes such branches several times slower.
    let mut cp_done = -1;
    if vplan[s] == 0 && cpl_match(s) { let fb = cpl_gen(s); cp_done = CP_DONE; pl_patch(fb, clen); }
    let cnd0 = nd[s].a;
    let simple_t = cp_done < 0 && nd[cnd0].k == N_BIN && is_cmp(nd[cnd0].op) && ty_int(nd[nd[cnd0].a].ty) && simple(nd[cnd0].a) && simple(nd[cnd0].b) && !is_const(cnd0);
    let inner = lh_inner(nd[s].b);
    let c0 = clen; let npl0 = npl; let nds0 = NDS; let ncp0 = ncp; let nss0 = nss; let td0 = tdepth;
    let mut pad = -1;   // -1: first attempt (align the head), else forced head padding
    let mut pj = 0;     // position after the entry jump
    let mut attempt = 0;
    while true {
      entry = -1; back = -1;
      if inner && simple_t && attempt == 0 { JREC = true; NJR = 0; }
      if vplan[s] != 0 { let ts = gen_vloop(s, vplan[s] - 1); pl_patch(ts, clen); }
      if !is_const(nd[s].a) {
        entry = pl_add(entry, jmp());
        pj = clen;
        if pad < 0 { let mut al = 16; if inner { al = 32; } while (clen % al) != 0 { byte(144); } }
        else { let mut q = 0; while q < pad { byte(144); q += 1; } }
      }
      let top = clen;
      let L = nloopctx; nloopctx += 1; brk_list[L] = -1; cont_list[L] = -1;
      if m >= 0 { loc(m); load(RAX, OK, ORR, OI); abs_op(137, RAX, ARENA_TOP); }
      gen_stmt(nd[s].b, false);
      if !(inner && simple_t) || attempt > 0 {
        // other loops: a simple test that would cross a line starts the next one (one NOP per iteration)
        if simple_t && !(inner && attempt > 0) { let room = 32 - (clen % 32); if room < 14 { nop_n(room); } }
      }
      let cst = clen;
      pl_patch(cont_list[L], clen); pl_patch(entry, clen);
      back = cond_jump(nd[s].a, true, back, rg, n); pl_patch(back, top);
      let cen = clen;
      pl_patch(brk_list[L], clen); nloopctx -= 1;
      if m >= 0 { loc(m); load(RAX, OK, ORR, OI); abs_op(137, RAX, ARENA_TOP); }
      if !(inner && simple_t) || attempt > 0 || is_const(nd[s].a) { JREC = false; pl_patch(cp_done, clen); return; }
      JREC = false;
      // the head padding d (0..31 more bytes) with the fewest line-crossing branches after the head
      let b0 = jr_bad(0, pj, cst, cen);
      if b0 == 0 { pl_patch(cp_done, clen); return; }
      let base_pad = top - pj;   // head padding of this attempt
      let mut d = 1; let mut best = -1; let mut bb = b0;
      while d < 32 { let x = jr_bad(d, pj, cst, cen); if x < bb { bb = x; best = d; } d += 1; }
      if best < 0 { pl_patch(cp_done, clen); return; }
      // rewind and generate again with base_pad + best bytes of head padding
      clen = c0; let mut q = npl0; while q < npl { pl_at[q] = -1; q += 1; }
      NDS = nds0; ncp = ncp0; nss = nss0; tdepth = td0;
      pad = base_pad + best; attempt = 1;
    }
    return;
  }
  if k == S_RET {
    let a = nd[s].a;
    if nd[a].k == N_CONST || nd[a].k == N_VAR { opnd(a); load(RAX, OK, ORR, OI); }
    else { gen(a, rg, n); mov_rr(RAX, RGS[rg]); }
    if !is_final { fns[curfn].exit_list = pl_add(fns[curfn].exit_list, jmp()); }
    return;
  }
  if k == S_EXPR { gen(nd[s].a, rg, n); return; }
  if k == S_WRITE {
    let av = nd[s].var;
    if nd[s].op == 1 && use_out { flush_calls = call_to(flush_calls); } // keep stdout/stderr ordered
    if av < 0 { byte(184); str_site(clen, nd[s].v as i64); u32_(0); byte(185); u32_(nd[s].c); }
    else if nd[s].a < 0 {
      load_base(RAX, av);
      if vars[av].lenv < 0 { mov_ri(RCX, vars[av].alen as u64); } else { loc(vars[av].lenv); load(RCX, OK, ORR, OI); }
    } else {
      gen(nd[s].a, rg, n); gen(nd[s].b, rg + 1, n - 1);
      let ro = RGS[rg]; let rn = RGS[rg + 1];
      let mut Lk = K_IMM; let mut Lr = 0; let mut Li = vars[av].alen as u64;
      if vars[av].lenv >= 0 { loc(vars[av].lenv); Lk = OK; Lr = ORR; Li = OI; }
      alu(A_CMP, K_REG, ro, Lk, Lr, Li); trap_list = pl_add(trap_list, jcc(7));
      if Lk == K_IMM { mov_ri(RAX, Li); } else { load(RAX, Lk, Lr, Li); }
      alur(A_SUB, RAX, ro); alur(A_CMP, rn, RAX); trap_list = pl_add(trap_list, jcc(7));
      load_base(RAX, av); alur(A_ADD, RAX, ro); mov_rr(RCX, rn);
    }
    if nd[s].op == 1 { ewrite_calls = call_to(ewrite_calls); return; }
    byte(232); write_calls = pl_add(write_calls, clen); u32_(0);
    return;
  }
  if k == S_STORE {
    let fs = nd[s].c >= 0;
    let av = nd[s].var;
    let mut w = vars[av].arr;
    if fs { w = ty_width(sfty[(vars[av].et - TY_STRUCT0) * 32 + nd[s].c]); }
    let mut val = nd[s].b;
    let mut ir = rg; let mut inn = n;
    while nd[val].k == N_UN && ext_width(nd[val].op) >= w { val = nd[val].a; }
    let mut fo = 0; if fs { fo = sfoff[(vars[av].et - TY_STRUCT0) * 32 + nd[s].c]; }
    let mut et = vars[av].et; if fs { et = sfty[(vars[av].et - TY_STRUCT0) * 32 + nd[s].c]; }
    // float element: the value goes straight from an xmm register to memory
    if nd[s].op < 0 && ty_flt(et) && (xvar_node(val) || xroom(val)) {
      let mut xv = 0;
      let sv = xtop;
      if xvar_node(val) { xv = vars[nd[val].var].xr; }
      else { xv = xtop; genf(val, xv, rg, n); xtop = xv + 1; }
      elem_addr(av, nd[s].a, nd[s].chk, fo, rg, n);
      xtop = sv;
      if et == TY_F64 { byte(242); } else { byte(243); }
      memop(0, false, false, 2, 15, 17, xv, EA_B, EA_RI, EA_SC);
      return;
    }
    if is_const(val) && hoisted(val) < 0 && (w != 8 || fits_s32(nd[val].v)) {
      elem_addr(av, nd[s].a, nd[s].chk, fo, rg, n);
      let mut dig = -1; if nd[s].op >= 0 { dig = alu_dig(nd[s].op); }
      store_elem_imm(w, dig, nd[val].v);
      return;
    }
    let mut rv = 0;
    if nd[val].k == N_VAR && vars[nd[val].var].reg >= 0 { rv = vars[nd[val].var].reg; }
    else { gen(val, rg, n); rv = RGS[rg]; ir = rg + 1; inn = n - 1; }
    elem_addr(av, nd[s].a, nd[s].chk, fo, ir, inn);
    let mut dig = -1; if nd[s].op >= 0 { dig = alu_dig(nd[s].op); }
    store_elem(w, dig, rv, EA_B, EA_RI, EA_SC);
    return;
  }
  if k == S_PRINT || k == S_PUTC {
    let a = nd[s].a;
    if simple(a) { opnd(a); load(RAX, OK, ORR, OI); } else { gen(a, rg, n); mov_rr(RAX, RGS[rg]); }
    if k == S_PUTC && nd[s].op == 1 {
      byte(80); if use_out { flush_calls = call_to(flush_calls); } emh("5fb8e70000000f05");
      return;
    }
    byte(232);
    if k == S_PUTC { putc_calls = pl_add(putc_calls, clen); }
    else if nd[s].op != 0 { printu_calls = pl_add(printu_calls, clen); }
    else { print_calls = pl_add(print_calls, clen); }
    u32_(0);
    return;
  }
  if k == S_ARR { gen_arr(s, rg, n); return; }
  if k == S_SAVE {
    let av = nd[s].var;
    gen(nd[s].a, rg, n); gen(nd[s].b, rg + 1, n - 1);
    let rk = RGS[rg]; let rn = RGS[rg + 1];
    loc(0); alu(A_CMP, K_REG, rk, OK, ORR, OI); trap_if(CC_AE);
    if vars[av].lenv < 0 { alu(A_CMP, K_REG, rn, K_IMM, 0, vars[av].alen as u64); } else { loc(vars[av].lenv); alu(A_CMP, K_REG, rn, OK, ORR, OI); }
    trap_if(7);
    load_base(RAX, av); mov_rr(RDX, RAX);
    loc(1); load(RAX, OK, ORR, OI); mov_rr(RCX, rk); memop(1, false, false, 1, 139, 0, RAX, RAX, RCX, 3);
    mov_rr(RCX, rn);
    sys_save();
    emh("4989d24989c9");
    emh("4889c7be41020000baed010000b8020000000f05");
    test_rr(RAX); trap_if(CC_S);
    emh("4989c0");
    let top = clen; emh("4d85c9"); let done = j8(116);
    emh("4c89c74c89d64c89cab8010000000f05");
    test_rr(RAX); trap_if(CC_LE);
    emh("4901c24929c1"); p8(j8(235), top);
    p8(done, clen);
    emh("4c89c7b8030000000f05");
    sys_restore();
    return;
  }
  if k == S_BRK { brk_list[nloopctx - 1] = pl_add(brk_list[nloopctx - 1], jmp()); return; }
  if k == S_IRET { if vars[nd[s].var].reads != 0 { assign(nd[s].var, nd[s].a, rg, n); } else if has_trap(nd[s].a) { gen(nd[s].a, rg, n); } inl_list[ninlctx - 1] = pl_add(inl_list[ninlctx - 1], jmp()); return; }
  if k == S_PAR {
    loc(nd[s].var); let Kk = OK; let Kr = ORR;
    loc(nd[s].op); let Ek = OK; let Er = ORR;
    assign(nd[s].var, nd[s].a, rg, n); assign(nd[s].op, nd[s].b, rg, n);
    load(RAX, Ek, Er, 0); alu(A_SUB, K_REG, RAX, Kk, Kr, 0); alui(A_CMP, RAX, 256); trap_list = pl_add(trap_list, jcc(CC_G));
    let top = clen;
    load(RAX, Kk, Kr, 0); alu(A_CMP, K_REG, RAX, Ek, Er, 0); let done = jcc(CC_GE);
    sys_save(); emh("b8390000000f05"); sys_restore();
    test_rr(RAX); trap_list = pl_add(trap_list, jcc(CC_S)); let child = jcc(CC_E);
    alu(A_ADD, Kk, Kr, K_IMM, 0, 1); rel32(jmp(), top);
    rel32(child, clen);
    if use_out { emh("48c70425"); u32_(OUT_LEN); u32_(0); }
    gen_stmt(nd[s].c, false);
    emh("31ffb8e70000000f05");
    rel32(done, clen);
    let wl = clen;
    sys_save();
    emh("48c7c7ffffffffbe"); u32_(PAR_STATUS);
    emh("31d24531d2b83d0000000f05");
    sys_restore();
    test_rr(RAX); let fin = jcc(CC_S);
    emh("8b0425"); u32_(PAR_STATUS); emh("85c0");
    let okw = j8(116); emh("c60425"); u32_(PAR_FAIL); byte(1); p8(okw, clen);
    rel32(jmp(), wl);
    rel32(fin, clen);
    emh("803c25"); u32_(PAR_FAIL); byte(0); trap_list = pl_add(trap_list, jcc(CC_NE));
    return;
  }
  if k == S_INL {
    let L = ninlctx; ninlctx += 1; inl_list[L] = -1;
    let mut c = nd[s].a;
    while c >= 0 { gen_stmt(c, false); c = nd[c].next; }
    // a jump to the end emitted as the very last instruction falls through instead
    let hl = inl_list[L];
    if hl >= 0 && pl_at[hl] == clen - 4 && code[clen - 5] == 233 { clen -= 5; inl_list[L] = pl_next[hl]; }
    pl_patch(inl_list[L], clen); ninlctx -= 1;
    return;
  }
  if k == S_CONT { cont_list[nloopctx - 1] = pl_add(cont_list[nloopctx - 1], jmp()); return; }
  if k == S_BLOCK {
    let mut c = nd[s].a;
    while c >= 0 { gen_stmt(c, is_final && nd[c].next < 0); c = nd[c].next; }
    return;
  }
}
fn print_signed_and_exit() {
  emh("4883ec30"); emh("488d74242f"); emh("c6060a"); emh("b901000000"); emh("4531c9"); emh("4885c0");
  emh("0f89"); let jns = clen; u32_(0);
  emh("41b901000000"); emh("48f7d8");
  rel32(jns, clen);
  emh("48c7c30a000000");
  let lp = clen;
  emh("31d2"); emh("48f7f3"); emh("80c230"); emh("48ffce"); emh("8816"); emh("48ffc1"); emh("4885c0");
  emh("0f85"); let jne = clen; u32_(0); rel32(jne, lp);
  emh("4585c9");
  emh("0f84"); let je = clen; u32_(0);
  emh("48ffce"); emh("c6062d"); emh("48ffc1");
  rel32(je, clen);
  emh("4889ca"); emh("b801000000"); emh("bf01000000"); emh("0f05");
  emh("31ff"); emh("b83c000000"); emh("0f05");
}
let mut handler_imm_at: i64 = 0;
let mut restorer_imm_at: i64 = 0;
let mut handler_off: i64 = 0;
fn emit_ncpu() {
  if ncpu_calls < 0 { return; }
  pl_patch(ncpu_calls, clen);
  emh("565741534150"); emh("4881ec80000000");
  emh("31ffbe800000004889e2b8cc0000000f05");
  emh("4531c04885c0"); let le = j8(126);
  emh("4889c148c1e9034889e6");
  let lq = clen; emh("4885c9"); let zq = j8(116);
  emh("488b16");
  let lb = clen; emh("4885d2"); let nq = j8(116);
  emh("488d7aff4821fa49ffc0"); p8(j8(235), lb);
  p8(nq, clen); emh("4883c60848ffc9"); p8(j8(235), lq);
  p8(zq, clen); p8(le, clen);
  emh("4c89c04885c07505b801000000");
  emh("4881c480000000415841" ); emh("5b5f5ec3");
}
fn emit_convert() {
  if u2d_calls >= 0 || u2s_calls >= 0 {
    let mut k = 0;
    while k < 2 {
      let mut list = u2d_calls; if k == 1 { list = u2s_calls; }
      if list >= 0 {
        let mut p = 242; if k == 1 { p = 243; }
        pl_patch(list, clen);
        emh("4885c0"); let big = j8(120);
        emh("660fefc0"); byte(p); emh("480f2ac0");
        fstore(RAX, 0, k == 0); byte(195);
        p8(big, clen);
        emh("4889c148d1e983e0014809c1");
        emh("660fefc0"); byte(p); emh("480f2ac1"); byte(p); emh("0f58c0");
        fstore(RAX, 0, k == 0); byte(195);
      }
      k += 1;
    }
  }
  if d2u_calls >= 0 || s2u_calls >= 0 {
    let mut jb = 0;
    if s2u_calls >= 0 { pl_patch(s2u_calls, clen); emh("660f6ec0f30f5ac0"); jb = j8(235); }
    if d2u_calls >= 0 { pl_patch(d2u_calls, clen); }
    emh("66480f6ec0");
    if s2u_calls >= 0 { p8(jb, clen); }
    emh("660f2ec0"); let z1 = j8(122);
    emh("660fefc9660f2ec1"); let z2 = j8(118);
    mov_ri(RAX, 4895412794951729152); emh("66480f6ec8660f2ec1"); let mxj = j8(115);
    mov_ri(RAX, 4890909195324358656); emh("66480f6ec8660f2ec1"); let hi = j8(115);
    emh("f2480f2cc0c3");
    p8(hi, clen); emh("f20f5cc1f2480f2cc0480fbaf83fc3");
    p8(mxj, clen); emh("48c7c0ffffffffc3");
    p8(z1, clen); p8(z2, clen); emh("31c0c3");
  }
}
fn emit_print(list: i64, uns: bool) {
  pl_patch(list, clen);
  emh("5356574151");
  emh("4883ec30488d74242fc6060a");
  emh("bf010000004531c9");
  let mut a = 0;
  if !uns { emh("4885c0"); a = j8(121); emh("41b90100000048f7d8"); p8(a, clen); }
  emh("48c7c30a000000");
  let lp = clen;
  emh("31d248f7f380c23048ffce881648ffc74885c0");
  p8(j8(117), lp);
  emh("4585c9"); a = j8(116); emh("48ffcec6062d48ffc7"); p8(a, clen);
  let em = clen;
  emh("0fb606"); putc_calls = call_to(putc_calls); emh("48ffc648ffcf"); p8(j8(117), em);
  emh("4883c43041595f5e5bc3");
}
fn emit_runtime() {
  if heap_calls >= 0 {   // rax = bytes (multiple of 64) -> rax = zeroed memory; preserves all but rcx, rdx
    pl_patch(heap_calls, clen);
    emh("56574150415141524153");               // push rsi, rdi, r8 - r11
    emh("50");                                 // push rax (size)
    emh("4889c6");                             // mov rsi, rax
    emh("b800000040"); emh("4839c6");          // mov eax, 1 GiB; cmp rsi, rax
    let big = j8(115);                         // jae: size >= chunk
    emh("4889c6");                             // mov rsi, rax (chunk)
    p8(big, clen);
    emh("56");                                 // push rsi (length)
    emh("31ff"); emh("ba03000000");            // addr 0, PROT_READ | PROT_WRITE
    emh("41ba22400000");                       // MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE
    emh("49c7c0ffffffff4531c9b8090000000f05"); // fd -1, offset 0, mmap
    emh("483d00f0ffff"); trap_if(7);
    emh("5e5a");                               // pop rsi (length), pop rdx (size)
    emh("488d0c10");                           // lea rcx, [rax + rdx]
    abs_op(137, RCX, HEAP_TOP);
    emh("4801c6");                             // add rsi, rax
    abs_op(137, RSI, HEAP_END);
    emh("415b415a415941585f5e");               // pop r11 - r8, rdi, rsi
    emh("c3");
  }
  emit_div_stubs();
  emit_ncpu();
  emit_convert();
  if ewrite_calls >= 0 { // rax = bytes, rcx = length: unbuffered write(2, ...)
    pl_patch(ewrite_calls, clen);
    emh("565741534889c64889ca");
    let top = clen; emh("4885d2"); let z = j8(116);
    emh("bf02000000b8010000000f054885c0"); let ee = j8(126);
    emh("4801c64829c2"); p8(j8(235), top); p8(z, clen); p8(ee, clen);
    emh("415b5f5ec3");
  }
  if !use_out { if trap_list >= 0 { pl_patch(trap_list, clen); emh("0f0b"); } return; }
  if print_calls >= 0 { emit_print(print_calls, false); }
  if printu_calls >= 0 { emit_print(printu_calls, true); }
  if write_calls >= 0 {   // rax = bytes, rcx = length: bulk copy into the output buffer, flushing when full
    pl_patch(write_calls, clen);
    emh("5657415048" ); emh("89c64989c8");
    let top = clen; emh("4d85c0"); let done = j8(116);
    emh("488b1425"); u32_(OUT_LEN);
    byte(185); u32_(OUT_CAP); emh("4829d1");
    emh("4939c8490f42c8");          // rcx = min(space, remaining)
    emh("4929c8");
    emh("488dba"); u32_(OUT_BUF);   // rdi = OUT_BUF + len
    emh("4801ca48891425"); u32_(OUT_LEN);
    let ql = clen; emh("4883f908"); let qb = j8(114);
    emh("488b064889074883c6084883c7084883e908"); p8(j8(235), ql);
    p8(qb, clen);
    let bl = clen; emh("4885c9"); let bz = j8(116);
    emh("8a06880748ffc648ffc748ffc9"); p8(j8(235), bl);
    p8(bz, clen);
    emh("48813c25"); u32_(OUT_LEN); u32_(OUT_CAP); rel32(jcc(CC_B), top);
    flush_calls = call_to(flush_calls); rel32(jmp(), top);
    p8(done, clen);
    emh("41585f5ec3");
  }
  pl_patch(putc_calls, clen);
  emh("488b0c25"); u32_(OUT_LEN);
  emh("8881"); u32_(OUT_BUF);
  emh("48ffc148890c25"); u32_(OUT_LEN);
  emh("4881f9"); u32_(OUT_CAP);
  let a = j8(114); flush_calls = call_to(flush_calls); p8(a, clen);
  byte(195);
  let flush_at = clen;
  emh("56574153488b1425"); u32_(OUT_LEN);
  byte(190); u32_(OUT_BUF);
  let top = clen; emh("4885d2"); let z = j8(116);
  emh("bf01000000b8010000000f054885c0"); let ee = j8(126);
  emh("4801c64829c2"); p8(j8(235), top); p8(z, clen); p8(ee, clen);
  emh("48c70425"); u32_(OUT_LEN); u32_(0);
  emh("415b5f5ec3");
  handler_off = clen;
  flush_calls = call_to(flush_calls); emh("bf88000000b8e70000000f05");
  if trap_list >= 0 { pl_patch(trap_list, clen); flush_calls = call_to(flush_calls); emh("0f0b"); }
  pl_patch(flush_calls, flush_at);
}
let fsites = alloc<i64>(8192);
fn generate() {
  allocate();
  plan_all();
  let mut i = 0;
  while i < nn { if nd[i].k == S_PRINT || (nd[i].k == S_PUTC && nd[i].op != 1) || (nd[i].k == S_WRITE && nd[i].op == 0) { use_out = true; } i += 1; }
  use_bss = use_out || use_arena || glob_bytes > 0;
  i = 0;
  while i < nn { if nd[i].k == S_PAR { use_bss = true; } i += 1; }
  if nplans > 0 {
    use_bss = true;
    // AVX-512 F, DQ, BW and VL usable? (cpuid.1:ecx.OSXSAVE, xgetbv: opmask/zmm state, cpuid.7:ebx bits 16, 17, 30, 31)
    emh("53"); emh("b80100000031c90fa2"); emh("0fbae11b"); let n1 = j8(115);
    emh("31c90f01d0"); emh("25e6000000"); emh("3de6000000"); let n2 = j8(117);
    emh("b80700000031c90fa2"); emh("81e3000003c0"); emh("81fb000003c0"); let n3 = j8(117);
    emh("c60425"); u32_(HAS_AVX); byte(1);
    p8(n1, clen); p8(n2, clen); p8(n3, clen);
    emh("5b");
  }
  if use_arena {
    emh("31ff48be"); u64_(17179869184);
    emh("ba0300000041ba2240000049c7c0ffffffff4531c9b8090000000f05");
    emh("483d00f0ffff"); trap_if(7);
    abs_op(137, RAX, ARENA_TOP); alur(A_ADD, RAX, RSI); abs_op(137, RAX, ARENA_END);
  }
  if use_out {
    emh("48c70425"); u32_(SIG_ACT); handler_imm_at = clen; u32_(0);
    emh("48c70425"); u32_(SIG_ACT + 8); u32_(67108864);
    emh("48c70425"); u32_(SIG_ACT + 16); restorer_imm_at = clen; u32_(0);
    emh("bf08000000be"); u32_(SIG_ACT);
    emh("31d241ba08000000b80d0000000f05");
  }
  let argc_used = vars[0].reads > 0;
  let argv_used = vars[1].reads > 0;
  if argc_used { let mut r = RAX; if vars[0].reg >= 0 { r = vars[0].reg; } load(r, K_MEM, 0, 0); }
  if argv_used { let mut r = RDX; if vars[1].reg >= 0 { r = vars[1].reg; } lea(r, RSP, -1, 8); }
  let frame_at = clen; emh("4881ec"); u32_(0);
  if argc_used && vars[0].reg < 0 { loc(0); store(OK, ORR, RAX); }
  if argv_used && vars[1].reg < 0 { loc(1); store(OK, ORR, RDX); }
  tbase = fslot[mainfn]; tdepth = 0; tmax = 0;
  curfn = mainfn;
  gen_stmt(body, true);
  let frame = ((fslot[mainfn] + tmax) * 8 + 15) & ~15;
  pl_patch(fns[mainfn].exit_list, clen);
  let unit_main = fns[mainfn].rett == TY_UNIT;
  if use_out {
    if !unit_main { print_calls = call_to(print_calls); }
    flush_calls = call_to(flush_calls);
    emh("31ffb83c0000000f05");
  } else if !unit_main { print_signed_and_exit(); }
  else { emh("31ffb83c0000000f05"); }
  let mut nfuncs = 0;
  let mut f = 0;
  while f < nfn {
    if f != mainfn && fns[f].used != 0 {
      nfuncs += 1; curfn = f; fns[f].addr = clen;
      let rc = regconv(f);
      clobm = 0;
      let pro = clen; emh("90909090909090909090");   // room for push rbx, rbp, r12..r15
      let site = clen; emh("4881ec"); u32_(0);
      tbase = fslot[f]; tdepth = 0; tmax = 0;
      if rc {
        i = 0;
        while i < fns[f].np {
          let pv = fpvar[f * 16 + i];
          if vars[pv].reads != 0 { loc(pv); let mut src = RCX; if i == 1 { src = RDX; } store(OK, ORR, src); }
          i += 1;
        }
      }
      // stack arguments sit above the frame: [rsp + frame + 8 + 8w] (frame patched below)
      let mut w = 0;
      i = 0;
      if rc { i = fns[f].np; }
      while i < fns[f].np {
        let pv = fpvar[f * 16 + i];
        let mut id0 = pv; let mut id1 = -1; let mut cnt = 1;
        if fpw[f * 16 + i] != 0 { id0 = vars[pv].basev; id1 = vars[pv].lenv; cnt = 2; }
        let mut kk = 0;
        while kk < cnt {
          let mut id = id0; if kk == 1 { id = id1; }
          if vars[id].reads != 0 {
            loc(id);
            let Lk = OK; let Lr = ORR;
            let mut r = RCX; if Lk == K_REG { r = Lr; }
            let disp = 8 + 8 * w;
            let mut rx = 72; if (r & 8) != 0 { rx = 76; }
            byte(rx); byte(139);
            byte(132 | ((r & 7) << 3)); byte(36); FRAME_FIX[nframefix] = clen; nframefix += 1; u32_(disp);
            if Lk != K_REG { store(Lk, Lr, RCX); }
          }
          kk += 1; w += 1;
        }
        i += 1;
      }
      if fns[f].mark >= 0 { abs_op(139, RCX, ARENA_TOP); loc(fns[f].mark); store(OK, ORR, RCX); }
      gen_stmt(fns[f].body, true);
      pl_patch(fns[f].exit_list, clen);
      if fns[f].mark >= 0 { loc(fns[f].mark); load(RCX, OK, ORR, OI); abs_op(137, RCX, ARENA_TOP); }
      let ff = ((fslot[f] + tmax) * 8 + 15) & ~15;
      // callee-saved registers this function writes: its variables' registers and expression temporaries
      let mut v = 0;
      while v < nv { if vars[v].reg >= 0 && vars[v].start > fpc_lo[f] && vars[v].start <= fpc_hi[f] { clobm = clobm | (1 << vars[v].reg); } v += 1; }
      let mut np = 0;
      let mut pp = pro;
      let mut q = 0;
      while q < 12 {
        let r = allregs[q];
        if callee_saved(r) && ((clobm >> r) & 1) != 0 { if (r & 8) != 0 { code[pp] = 65; pp += 1; } code[pp] = (80 | (r & 7)) as u8; pp += 1; np += 1; }
        q += 1;
      }
      nop_fill(pp, pro + 10 - pp);
      if ff == 0 { code[site] = 15; code[site + 1] = 31; code[site + 2] = 128; patch32(site + 3, 0); }   // 7-byte nop
      else { patch32(site + 3, ff); emh("4881c4"); u32_(ff); }
      q = 11;
      while q >= 0 { let r = allregs[q]; if callee_saved(r) && ((clobm >> r) & 1) != 0 { pop_r(r); } q -= 1; }
      // stack-argument loads come after the frame and the saved registers: rebase their displacements
      q = 0;
      while q < nframefix { let at = FRAME_FIX[q]; patch32(at, (code[at] as i64) + ((code[at + 1] as i64) << 8) + ff + 8 * np); q += 1; }
      nframefix = 0;
      byte(195);
    }
    f += 1;
  }
  f = 0;
  while f < nfn { if fns[f].used != 0 && f != mainfn { pl_patch(fns[f].calls, fns[f].addr); } f += 1; }
  emit_runtime();
  let mut shift = 0;
  // drop main's empty frame unless functions exist or a prologue branch (arena trap) crosses it
  if frame != 0 || nfuncs != 0 || use_arena { patch32(frame_at + 3, frame); }
  else {   // a 7-byte NOP in its place: removing it would shift (and misalign) every loop after it
    code[frame_at] = 15 as u8; code[frame_at + 1] = 31 as u8; code[frame_at + 2] = 128 as u8;
    code[frame_at + 3] = 0 as u8; code[frame_at + 4] = 0 as u8; code[frame_at + 5] = 0 as u8; code[frame_at + 6] = 0 as u8;
  }
  if handler_off > frame_at { handler_off -= shift; }
  i = 0;
  while i < nss { if ss_at[i] > frame_at { ss_at[i] -= shift; } i += 1; }
  if cplen > 0 {
    while (clen & 63) != 0 { byte(204); }
    let pool_at = clen;
    i = 0;
    while i < cplen { byte(cpool[i] as i64); i += 1; }
    i = 0;
    while i < ncp {
      let mut at = cp_at[i]; if at > frame_at { at -= shift; }
      patch32(at, pool_at + cp_off[i] - (at + 4 + cp_tail[i]));
      i += 1;
    }
  }
  let data_at = clen;
  i = 0;
  while i < sdlen { byte(sdata[i] as i64); i += 1; }
  i = 0;
  while i < nss { patch32(ss_at[i], 4194304 + 256 + data_at + ss_off[i]); i += 1; }
  if use_out { patch32(handler_imm_at, 4194304 + 256 + handler_off); patch32(restorer_imm_at, 4194304 + 256 + handler_off); }
}

// ---------------------------------------------------------------- ELF64 writer
let outb = alloc<u8>(16777472);
fn at16(n: i64, v: i64) { outb[n] = v as u8; outb[n + 1] = (v >> 8) as u8; }
fn at32(n: i64, v: i64) { at16(n, v & 65535); at16(n + 2, (v >> 16) & 65535); }
fn at64(n: i64, v: i64) { at32(n, v & 4294967295); at32(n + 4, (v >> 32) & 4294967295); }
fn build_elf() -> i64 {
  let offset = 256;
  let total = offset + clen;
  if 4194304 + total > BSS { fail("program too large (code and data exceed 252 MiB)"); }
  let mut i = 0;
  while i < offset { outb[i] = 0; i += 1; }
  outb[0] = 127; outb[1] = 'E'; outb[2] = 'L'; outb[3] = 'F'; outb[4] = 2; outb[5] = 1; outb[6] = 1;
  at16(16, 2); at16(18, 62); at32(20, 1);
  at64(24, 4194304 + offset); at64(32, 64);
  at16(52, 64); at16(54, 56);
  if use_bss { at16(56, 3); } else { at16(56, 2); }
  let mut ph = 64;
  at32(ph, 1); at32(ph + 4, 5);
  at64(ph + 8, 0); at64(ph + 16, 4194304); at64(ph + 24, 4194304);
  at64(ph + 32, total); at64(ph + 40, total); at64(ph + 48, 4096);
  ph = 120; at32(ph, 1685382481); at32(ph + 4, 6); at64(ph + 48, 16);
  if use_bss {
    ph = 176; at32(ph, 1); at32(ph + 4, 6); at64(ph + 8, 0); at64(ph + 16, BSS); at64(ph + 24, BSS);
    let mut vb = 0; if nplans > 0 { vb = ((glob_bytes + 63) & ~63) - glob_bytes + vec_bytes; }
    at64(ph + 32, 0); at64(ph + 40, BSS_FIXED + glob_bytes + vb); at64(ph + 48, 4096);
  }
  i = 0;
  while i < clen { outb[offset + i] = code[i]; i += 1; }
  return total;
}
let mut want_map: bool = false;
// --map: function start addresses on stderr (for profiling)
fn write_map() {
  let hx = "0123456789abcdef";
  let line = alloc<u8>(128);
  let mut f = 0;
  while f < nfn {
    if fns[f].used != 0 && f != mainfn {
      let a = 4194304 + 256 + fns[f].addr;
      let mut n = 0;
      let mut sh = 28;
      while sh >= 0 { line[n] = hx[(a >> sh) & 15]; n += 1; sh -= 4; }
      line[n] = 32; n += 1;
      let mut i = 0;
      while i < fns[f].nlen && n < 120 { line[n] = src[fns[f].noff + i]; n += 1; i += 1; }
      line[n] = 10; n += 1;
      ewrite(line, 0, n);
    }
    f += 1;
  }
}
fn report(total: i64, out: [u8]) {
  write("skite: wrote "); write(out); write(" ("); putnum(total); write(" bytes, "); putnum(clen); write(" machine-code bytes, ");
  putnum(nv - 2); write(" vars, "); putnum(spilled); write(" spills, "); putnum(peak_active); write(" peak registers, "); putnum(xpeak); write(" xmm, ");
  putnum(nelided); putc('/'); putnum(nchecks); write(" bounds checks elided, "); putnum(nsr); write(" modulo reduced, "); putnum(nplans); write(" loops vectorized ("); let mut ns_ = 0; let mut q_ = 0; while q_ < nplans { if vp_stream[q_] { ns_ += 1; } q_ += 1; } putnum(ns_); write(" element-wise, "); ns_ = 0; q_ = 0; while q_ < nplans { if vp_byte[q_] { ns_ += 1; } q_ += 1; } putnum(ns_); write(" byte-lane), ");
  putnum(ninlined + ninl_stmt); write(" calls inlined, "); putnum(nunrolled); write(" loops unrolled)\n");
}
fn main() {
  if argc() != 3 && argc() != 4 { ewrite("usage: skite input.ck output-executable [--scalar]\n"); exit(2); }
  if argc() == 4 {
    let o = argv(3);
    if len(o) == 8 && o[2] == 's' && o[3] == 'c' { simd_off = true; }
    else if len(o) == 5 && o[2] == 'm' && o[3] == 'a' { want_map = true; }
    else { ewrite("skite: unknown option (--scalar, --map)\n"); exit(2); }
  }
  let input = file(1);
  let nm = argv(1);
  srcname_len = len(nm); if srcname_len > 4000 { srcname_len = 4000; }
  let mut j = 0;
  while j < srcname_len { srcname[j] = nm[j]; j += 1; }
  if len(input) > 1048576 { ewrite("skite: error: invalid source file size\n"); exit(1); }
  let mut i = 0;
  while i < len(PRELUDE) { src[i] = PRELUDE[i]; i += 1; }
  prelude_len = len(PRELUDE);
  src[prelude_len] = 0;
  user_start = prelude_len + 1;
  i = 0;
  while i < len(input) {
    if input[i] == 0 { ewrite("skite: error: source contains NUL byte\n"); exit(1); }
    src[user_start + i] = input[i]; i += 1;
  }
  src[user_start + len(input)] = 0;
  src_len = user_start + len(input);
  init_regs();
  parse();
  generate();
  let total = build_elf();
  if want_map { write_map(); }
  save(2, outb, total);
  let outp = argv(2);
  report(total, outp);
}
