#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
SKITE=${SKITE:-./skite}; [ -x "$SKITE" ] || make -s skite
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
check() {
  local src="$1" expected="$2";shift 2
  "$SKITE" "$src" "$T/prog" > "$T/build.log"
  local actual
  actual=$($T/prog "$@")
  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL: $src args=[$*]: got [$actual] expected [$expected]" >&2
    exit 1
  fi
  readelf -h "$T/prog" | grep -q 'Advanced Micro Devices X86-64'
  readelf -l "$T/prog" | grep -q 'GNU_STACK'
  if readelf -l "$T/prog" | grep -E 'GNU_STACK .*RWE' >/dev/null; then
    echo 'FAIL: stack unexpectedly executable' >&2;exit 1
  fi
  echo "PASS: $src args=[$*] => $actual"
}
check examples/arith.ck 56
check examples/negative.ck -3509
check examples/argc.ck 46
check examples/argc.ck 4 arg1 arg2
check examples/operations.ck 7
check examples/operations.ck 26 arg1 arg2 arg3
check examples/minimum.ck -9223372036854775808
cat > "$T/overflow.ck" <<'SRC'
fn main() -> i64 { return 9223372036854775807 + 1; }
SRC
check "$T/overflow.ck" -9223372036854775808
cat > "$T/mod.ck" <<'SRC'
fn main() -> i64 { return -(argc() * 11) % 5; }
SRC
check "$T/mod.ck" -1
check "$T/mod.ck" -3 a b
cat > "$T/bad.ck" <<'SRC'
fn main() -> i64 { return 42 / 0; }
SRC
if "$SKITE" "$T/bad.ck" "$T/prog" 2> "$T/error"; then
  echo 'FAIL: divide-by-zero unexpectedly accepted' >&2;exit 1
fi
grep -q 'division by zero' "$T/error"
echo 'PASS: constant divide-by-zero rejected'
# Opus review D1: hostile nesting must be a diagnostic, not a compiler SIGSEGV.
for unit in '(' '-'; do
  { printf 'fn main() -> i64 { return '; for _ in $(seq 100000); do printf '%s' "$unit"; done
    printf '1'; [[ $unit == '(' ]] && for _ in $(seq 100000); do printf ')'; done; printf '; }\n'; } > "$T/deep.ck"
  rc=0; "$SKITE" "$T/deep.ck" "$T/prog" 2> "$T/error" || rc=$?
  if [[ $rc -ne 1 ]] || ! grep -q 'nesting too deep' "$T/error"; then
    echo "FAIL: deep '$unit' nesting rc=$rc (expected diagnostic)" >&2; exit 1; fi
done
echo 'PASS: deep nesting rejected with diagnostic'
# Opus review D7: bytes after an embedded NUL must not be silently ignored.
printf 'fn main() -> i64 { return 7; }\0 trailing' > "$T/nul.ck"
if "$SKITE" "$T/nul.ck" "$T/prog" 2> "$T/error"; then echo 'FAIL: NUL-truncated source accepted' >&2; exit 1; fi
grep -q 'NUL byte' "$T/error"
echo 'PASS: embedded NUL rejected'
# Immediate-encoding boundaries (imm8 / imm32 / zero-ext imm32 / imm64), both operand sides.
cat > "$T/imm.ck" <<'SRC'
fn main() -> i64 {
  let n = argc();
  let a = n + 127 + (n - 128) + (n * 128) + (-129 * n);
  let b = (n + 2147483647) - (n - 2147483648) + (n * 4294967295) + (4294967296 - n);
  let c = (n * (-2147483647 - 1)) + (n - (-2147483647 - 2)) + (9223372036854775807 * n);
  return a + b + c;
}
SRC
check "$T/imm.ck" -9223372023969873922
check "$T/imm.ck" -9223372019674906628 x y
# v0.3: lea/imul3 forms with every pool register as base (rbp/r13 need disp, r12 needs SIB)
{
  echo 'fn main() -> i64 {'; echo '  let n = argc();'
  for i in $(seq 0 8); do echo "  let mut a$i = n * $((i+3)) + $i;"; done
  echo '  let mut t = 0;'
  for r in 0 1 2; do
    echo "  let mut j$r = 0;"; echo "  while j$r < 3 {"
    for i in $(seq 0 8); do echo "    t += a$i + $((i*7+r)); t += a$i + a$(( (i+r+1)%9 )); t -= a$i - 300; a$i = a$i * 5 + 1;"; done
    echo "    j$r += 1;"; echo '  }'
  done
  echo '  return t;'; echo '}'
} > "$T/lea.ck"
lea_expect() { local n=$1 t=0 r i j k; local -a a
  for i in $(seq 0 8); do a[$i]=$(( n*(i+3)+i )); done
  for r in 0 1 2; do for j in 0 1 2; do for i in $(seq 0 8); do
    k=$(( (i+r+1)%9 )); t=$(( t + a[i] + i*7+r )); t=$(( t + a[i] + a[k] )); t=$(( t - (a[i]-300) )); a[$i]=$(( a[i]*5+1 ))
  done; done; done; echo $t; }
check "$T/lea.ck" "$(lea_expect 1)"
check "$T/lea.ck" "$(lea_expect 3)" x y
# ---- v0.4: memory, files, output, bounds safety ----
cat > "$T/mem.ck" <<'SRC'
fn main() -> i64 {
  let f = file(1);
  let cnt = alloc32(26);
  let mut i = 0;
  while i < len(f) {
    let c = f[i];
    if c >= 65 && c <= 90 { cnt[c - 65] += 1; }
    i += 1;
  }
  let mut j = 0;
  while j < 26 { if cnt[j] > 0 { putc(j + 65); putc(61); print(cnt[j]); } j += 1; }
  let w = view16(f);
  let b = alloc64(argc() + 2);
  b[argc() + 1] = -5;
  print(b[argc() + 1] * len(w));
  return len(f);
}
SRC
printf 'ABBA CAB' > "$T/in.txt"
"$SKITE" "$T/mem.ck" "$T/mem" > /dev/null
got=$("$T/mem" "$T/in.txt" | tr '\n' ' ')
[[ "$got" == "A=3 B=3 C=1 -20 8 " ]] || { echo "FAIL: mem.ck got [$got]" >&2; exit 1; }
echo 'PASS: arrays/file/view/print/putc'
rc=$( ( "$T/mem" /nonexistent >/dev/null 2>&1 ); echo $? ) 2>/dev/null
[[ $rc -eq 132 ]] || { echo "FAIL: missing file rc=$rc" >&2; exit 1; }
rc=$( ( "$T/mem" >/dev/null 2>&1 ); echo $? ) 2>/dev/null
[[ $rc -eq 132 ]] || { echo "FAIL: argv out of range rc=$rc" >&2; exit 1; }
echo 'PASS: file errors trap'
cat > "$T/oob.ck" <<'SRC'
fn main() -> i64 { let a = alloc8(4); print(7); a[argc() + 3] = 1; return 0; }
SRC
"$SKITE" "$T/oob.ck" "$T/oob" > /dev/null
rc=0; got=$( ( "$T/oob" ) 2>/dev/null ) || rc=$?
[[ $rc -eq 132 && "$got" == "7" ]] || { echo "FAIL: bounds trap rc=$rc out=[$got]" >&2; exit 1; }
echo 'PASS: out-of-bounds store traps after flushing output'
cat > "$T/fpe.ck" <<'SRC'
fn main() -> i64 { print(9); return 1 / (argc() - 1); }
SRC
"$SKITE" "$T/fpe.ck" "$T/fpe" > /dev/null
rc=0; got=$( ( "$T/fpe" ) 2>/dev/null ) || rc=$?
[[ $rc -eq 136 && "$got" == "9" ]] || { echo "FAIL: div trap rc=$rc out=[$got]" >&2; exit 1; }
echo 'PASS: division trap flushes output (SIGFPE handler)'
# R marks RHS evaluation and I marks index evaluation. The runtime's
# installed SIGFPE handler exits 136; SIGILL's shell status is 132.

cat > "$T/opeq_rhs_divzero.ck" <<'SRC'
let arr = alloc<f64>(2);
let mut zero: i64 = 0;
fn rhs() -> f64 { putc(82); return (1 / zero) as f64; }
fn index() -> i64 { putc(73); return 99; }
fn main() { arr[index()] += rhs(); }
SRC
"$SKITE" "$T/opeq_rhs_divzero.ck" "$T/prog" > /dev/null
rc=0; got=$("$T/prog" 2>/dev/null) || rc=$?
[[ $rc -eq 136 && "$got" == "R" ]] || { echo "FAIL: RHS divzero/order rc=$rc out=[$got]" >&2; exit 1; }

cat > "$T/opeq_oob.ck" <<'SRC'
let arr = alloc<f64>(2);
fn rhs() -> f64 { putc(82); return 3.0; }
fn index() -> i64 { putc(73); return 99; }
fn main() { arr[index()] += rhs(); }
SRC
"$SKITE" "$T/opeq_oob.ck" "$T/prog" > /dev/null
rc=0; got=$("$T/prog" 2>/dev/null) || rc=$?
[[ $rc -eq 132 && "$got" == "RI" ]] || { echo "FAIL: OOB/index order rc=$rc out=[$got]" >&2; exit 1; }

cat > "$T/opeq_index_divzero.ck" <<'SRC'
let arr = alloc<f64>(2);
let mut zero: i64 = 0;
fn rhs() -> f64 { putc(82); return 1.0; }
fn index() -> i64 { putc(73); return 1 / zero; }
fn main() { arr[index()] /= rhs(); }
SRC
"$SKITE" "$T/opeq_index_divzero.ck" "$T/prog" > /dev/null
rc=0; got=$("$T/prog" 2>/dev/null) || rc=$?
[[ $rc -eq 136 && "$got" == "RI" ]] || { echo "FAIL: index divzero/order rc=$rc out=[$got]" >&2; exit 1; }

# A direct constant index (the optimized branch) must also leave RHS traps first:
cat > "$T/opeq_direct_rhs_divzero.ck" <<'SRC'
let arr = alloc<f64>(2);
let mut zero: i64 = 0;
fn rhs() -> f64 { putc(82); return (1 / zero) as f64; }
fn main() { arr[99] += rhs(); }
SRC
"$SKITE" "$T/opeq_direct_rhs_divzero.ck" "$T/prog" > /dev/null
rc=0; got=$("$T/prog" 2>/dev/null) || rc=$?
[[ $rc -eq 136 && "$got" == "R" ]] || { echo "FAIL: direct-index RHS trap rc=$rc out=[$got]" >&2; exit 1; }

echo 'PASS: compound assignment RHS/index evaluation and trap order'
for bad in 'let mut a = alloc8(4);' 'let a = alloc8(0);' 'let a = file(1); a[0] = 1;' 'let a = alloc8(4); let x = a;' 'let mut i = 0; while i < 2 { let a = file(1); i += 1; }'; do
  printf 'fn main() -> i64 { %s return 0; }' "$bad" > "$T/bad.ck"
  if "$SKITE" "$T/bad.ck" "$T/prog" 2>/dev/null; then echo "FAIL: accepted [$bad]" >&2; exit 1; fi
done
echo 'PASS: unsafe array forms rejected'
# Vigenere solver: skite output must equal the C reference implementation's
if [[ -f bench/vigenere/data/quad.bin ]]; then
  "$SKITE" bench/vigenere/vig.ck "$T/vig" > "$T/vig.log"
  grep -q '67/67 bounds checks elided' "$T/vig.log" || { echo "FAIL: vig bounds-check proof regressed" >&2; cat "$T/vig.log" >&2; exit 1; }
  cc -O2 bench/vigenere/vig.c -o "$T/vigc"
  cmp -s <("$T/vig" bench/vigenere/data/quad.bin bench/vigenere/data/cipher.txt) <("$T/vigc" bench/vigenere/data/quad.bin bench/vigenere/data/cipher.txt) \
    || { echo "FAIL: vig.ck output differs from vig.c" >&2; exit 1; }
  echo 'PASS: Vigenere solver matches C reference (all bounds checks proven)'
fi
# Regression (fuzz seed 1 #772): strength reduction must not hoist a trapping
# offset in front of a loop that never runs.
cat > "$T/srtrap.ck" <<'SRC'
fn main() -> i64 {
  let z = argc() - argc();
  let mut i = 0;
  let mut t = 0;
  while i < 8 && z > 0 { i += 1; t += (i + (z % z)) % 26; }
  return t + 5;
}
SRC
check "$T/srtrap.ck" 5
# Regression (fuzz, v0.5): a[i] op= e must evaluate i exactly once (calls in i have effects)
cat > "$T/opeq.ck" <<'SRC'
fn tick(x: i64) -> i64 { putc(66); return x; }
fn main() -> i64 { let a = alloc64(4); a[1] = 3; a[tick(1)] <<= 2; a[tick(1)] *= 5; putc(10); return a[1]; }
SRC
"$SKITE" "$T/opeq.ck" "$T/opeq" > /dev/null
got=$("$T/opeq" | tr '\n' ' ')
[[ "$got" == "BB 60 " ]] || { echo "FAIL: compound store evaluated its index twice: [$got]" >&2; exit 1; }
echo 'PASS: compound array store evaluates the index once'
# ---- v0.6: par blocks / shared arrays / ncpu() ----
cat > "$T/par.ck" <<'SRC'
fn work(k: i64, n: i64) -> i64 { let mut s = 0; let mut i = 0; while i < n { s += (i * i + k) % 1000003; i += 1; } return s; }
fn main() -> i64 {
  let res = shared64(8);
  let scratch = alloc64(1);
  scratch[0] = 99;
  par k in 0..8 { scratch[0] = k; res[k] = work(k, 200000); }
  let mut t = 0; let mut k = 0;
  while k < 8 { t += res[k]; k += 1; }
  print(scratch[0]);
  if ncpu() < 1 { return -1; }
  return t;
}
SRC
"$SKITE" "$T/par.ck" "$T/par" > /dev/null
got=$("$T/par" | tr '\n' ' ')
want=$(cat > "$T/par.c" <<'SRC'
#include <stdio.h>
#include <stdint.h>
int main(){int64_t t=0;for(int k=0;k<8;k++){int64_t s=0;for(int64_t i=0;i<200000;i++)s+=(i*i+k)%1000003;t+=s;}printf("99 %lld ",(long long)t);}
SRC
cc -O2 "$T/par.c" -o "$T/parc" && "$T/parc")
[[ "$got" == "$want" ]] || { echo "FAIL: par results [$got] want [$want]" >&2; exit 1; }
echo 'PASS: par workers + shared results + private snapshots'
cat > "$T/parf.ck" <<'SRC'
fn main() -> i64 { let r = shared64(4); print(1); par k in 0..4 { r[k] = 100 / (2 - k); } print(2); return 0; }
SRC
"$SKITE" "$T/parf.ck" "$T/parf" > /dev/null
rc=$( ( "$T/parf" > "$T/parf.out" 2>/dev/null ); echo $? ) 2>/dev/null
[[ $rc -eq 132 && "$(cat "$T/parf.out")" == "1" ]] || { echo "FAIL: failing worker rc=$rc" >&2; exit 1; }
echo 'PASS: a failing worker makes the parent trap after the join (output before par kept)'
for bad in 'let mut x = 0; par k in 0..2 { x = k; }' 'par k in 0..2 { print(k); }' 'par k in 0..2 { par j in 0..2 { } }' 'par k in 0..2 { let a = alloc8(4); }' 'par k in 0..2 { return 1; }'; do
  printf 'fn main() -> i64 { %s return 0; }' "$bad" > "$T/bad.ck"
  if "$SKITE" "$T/bad.ck" "$T/prog" 2>/dev/null; then echo "FAIL: accepted [$bad]" >&2; exit 1; fi
done
printf 'fn say(x: i64) -> i64 { print(x); return x; }\nfn main() -> i64 { let r = shared64(2); par k in 0..2 { r[k] = say(k); } return 0; }' > "$T/bad.ck"
if "$SKITE" "$T/bad.ck" "$T/prog" 2>/dev/null; then echo "FAIL: accepted printing call in par" >&2; exit 1; fi
echo 'PASS: unsafe par forms rejected'
if [[ -f bench/vigenere/data/quad.bin ]]; then
  "$SKITE" bench/vigenere/vigp.ck "$T/vigp" > /dev/null
  cmp -s <("$T/vigp" bench/vigenere/data/quad.bin bench/vigenere/data/cipher.txt) <("$T/vigc" bench/vigenere/data/quad.bin bench/vigenere/data/cipher.txt) \
    || { echo "FAIL: parallel Vigenere differs from the C reference" >&2; exit 1; }
  echo 'PASS: parallel Vigenere solver matches C reference'
fi
"$SKITE" tests/types/types.ck "$T/types" > /dev/null
"$T/types" | cmp -s - tests/types/types.expected || { echo "FAIL: typed regression" >&2; "$T/types" | diff - tests/types/types.expected >&2; exit 1; }
echo 'PASS: v0.7 types (widths, unsigned, f32/f64, casts, bool, unit functions)'
"$SKITE" tests/types/xmm.ck "$T/xmm" > /dev/null
"$T/xmm" | cmp -s - tests/types/xmm.expected || { echo "FAIL: XMM expression stack" >&2; exit 1; }
echo 'PASS: float trees deeper than the XMM stack, nested in integer subexpressions'
while IFS= read -r bad; do
  printf 'fn u() { }\nfn main() -> i64 { %s return 0; }' "$bad" > "$T/bad.ck"
  if "$SKITE" "$T/bad.ck" "$T/prog" 2>/dev/null; then echo "FAIL: accepted ill-typed [$bad]" >&2; exit 1; fi
done <<'BAD'
let x: u8 = 300;
let a: i64 = 1; let b: u64 = 2; let c = a + b;
if 1 { }
let x: i64 = 1.5;
let mut f = 1.0; let g: f32 = f;
let x: u8 = 5; let y: u8 = x + 1;
let b = true + 1;
let u: u64 = 1; let v = -u;
let x = 3 as bool;
let a = alloc<u8>(4); a[0] = 256;
let x = u();
let f: f32 = 1.0; let d: f64 = 2.0; let s = f + d;
let x: i64 = 2; let y = x % 2.0;
let x: i32 = 16777217; let f: f32 = 16777217;
let __x = 1;
let a = alloc<f64>(2); let i = a[1.0];
while 1 < 2 && 3 { }
BAD
echo 'PASS: ill-typed programs rejected'
# Reinterpreting bytes as a bool field violates the canonical 0/1 invariant.
# Include a mixed layout so rejection does not depend on element width.
for fields in 'ok: bool' 'value: u64, ok: bool'; do
  cat > "$T/bad.ck" <<SRC
struct Flag { $fields }
fn main() {
  let bytes = alloc<u8>(argc() + 32);
  bytes[0] = 2;
  let flags = view<Flag>(bytes);
  if flags[0].ok { print(1); }
}
SRC
  if "$SKITE" "$T/bad.ck" "$T/prog" 2> "$T/error"; then
    echo 'FAIL: accepted byte view of bool-containing struct' >&2; exit 1
  fi
  grep -q 'no views of structs containing bool' "$T/error"
done
echo 'PASS: views cannot create invalid bool fields'
for t in structs heap structsz valias valias_width carry selstore; do
  "$SKITE" tests/data/$t.ck "$T/$t" > /dev/null
  "$T/$t" "$T/$t.saved" | cmp -s - tests/data/$t.expected || { echo "FAIL: $t" >&2; exit 1; }
done
[[ "$(cat "$T/heap.saved")" == "hi" ]] || { echo "FAIL: save()" >&2; exit 1; }
echo 'PASS: structs, globals, scoped heap, save(), 16/32/64-byte struct alloc and view'
"$SKITE" tests/features/features.ck "$T/features" > /dev/null
"$T/features" | cmp -s - tests/features/features.expected || { echo "FAIL: for/loop/const/literals" >&2; "$T/features" | diff - tests/features/features.expected >&2; exit 1; }
"$SKITE" tests/features/for_form.ck "$T/for_form" > /dev/null
"$SKITE" tests/features/while_form.ck "$T/while_form" > /dev/null
cmp -s "$T/for_form" "$T/while_form" || { echo "FAIL: for loops must compile to the same machine code as their while form" >&2; exit 1; }
check tests/features/compound_index.ck "$(cat tests/features/compound_index.expected)" dummy
"$SKITE" tests/features/tail_acc.ck "$T/tail_acc" > /dev/null
"$T/tail_acc" | cmp -s - tests/features/tail_acc.expected || { echo "FAIL: tail recursion modulo +" >&2; "$T/tail_acc" | diff - tests/features/tail_acc.expected >&2; exit 1; }
while IFS='|' read -r msg bad; do
  printf '%s\n' "$bad" > "$T/bad.ck"
  if "$SKITE" "$T/bad.ck" "$T/prog" 2> "$T/error" > /dev/null; then echo "FAIL: accepted [$bad]" >&2; exit 1; fi
  grep -qF "$msg" "$T/error" || { echo "FAIL: [$bad]: expected [$msg], got: $(cat "$T/error")" >&2; exit 1; }
done <<'BAD'
for loop variable|fn main() { for i in 0..3 { i = 5; } }
for loop variable|fn main() { for i in 0..3 { i += 1; } }
compile-time constant|fn main() { const x = argc(); }
cannot be mut|fn main() { const mut x = 1; }
cannot be mut|const mut X = 1; fn main() { }
scalar|const S = "hi"; fn main() { }
scalar|fn main() { const a = alloc<u8>(4); }
malformed number|fn main() { let a = 0b102; }
malformed number|fn main() { let a = 0b; }
malformed number|fn main() { let a = 0o8; }
exceeds u64|fn main() { let a = 0b1_0000000000000000000000000000000000000000000000000000000000000000; }
exceeds u64|fn main() { let a = 0o2000000000000000000000; }
type mismatch|fn main() { for i in 0.0..3.0 { } }
type mismatch|fn main() { let a: u64 = 1; let b: i64 = 2; for i in a..b { } }
unknown variable|fn main() { for i in 0..3 { } print(i); }
expected `..`|fn main() { for i in 0, 3 { } }
expected variable name|fn main() { let loop = 1; }
must end with a return|fn f() -> i64 { loop { break; } } fn main() { }
must end with a return|fn f(n: i64) -> i64 { loop { if n > 1 { break; } } } fn main() { }
break/continue outside loop|fn main() { for i in 0..2 { } break; }
BAD
echo 'PASS: for/loop/const, 0b/0o literals (for compiles to the same machine code as while)'
# stores through a view<u64> of bytes read by a later lane (issue #9): vector == scalar
"$SKITE" tests/stream_mixed_width.ck "$T/mw" > /dev/null && "$SKITE" tests/stream_mixed_width.ck "$T/mws" --scalar > /dev/null
"$T/mw" | cmp -s - <("$T/mws") || { echo 'FAIL: mixed-width view store/load' >&2; exit 1; }
echo 'PASS: element-wise vector loops through views of different widths'
# carried a[i - 1]: with no arguments the first iteration reads a[-1] and must trap after the same output
if "$T/carry" > "$T/carry.out" 2>/dev/null; then echo 'FAIL: carry trap' >&2; exit 1; fi
cmp -s tests/data/carry.trap "$T/carry.out" || { echo 'FAIL: carry trap output' >&2; exit 1; }
echo 'PASS: loop-carried stores keep traps and outputs'
# a / b + a % b computed once: same values, MIN / -1 still traps with SIGFPE (exit 136)
"$SKITE" tests/data/divmod_pair.ck "$T/dmp" > /dev/null
rc=0; "$T/dmp" > "$T/dmp.out" || rc=$?
[[ $rc -eq 136 && "$(cat "$T/dmp.out")" == "-3094914550737416739" ]] || { echo "FAIL: divmod pair (rc=$rc)" >&2; exit 1; }
echo 'PASS: paired division and remainder'
echo 'All tests passed'
