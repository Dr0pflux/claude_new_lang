# skite language reference — implemented in v0.9

Everything here is implemented and tested. Planned features live in `DESIGN.md` (domain roadmap).

## Program

```text
fn main() {
    let text = file(1);                  // argv[1], mapped read-only: [u8]
    let freq = alloc<u32>(26);           // zero-initialized
    for i in 0..len(text) {
        let c = text[i];                 // c: u8
        if c >= 65 && c <= 90 { freq[c - 65] += 1; }
    }
    for k in 0..26 { putc(k + 65); putc(32); print(freq[k]); }
}
```

A program is a set of top-level items in any order: functions, `struct` declarations and global `let`s / `const`s. New users should start with `TUTORIAL.md`.

A program's entry point is `main`. `main` takes no parameters and returns `i64` or nothing. If it returns `i64`, the value is printed in decimal on the last line. The process exits with status 0.

## Types

| Type | Values | Register form |
|---|---|---|
| `i8 i16 i32 i64` | two's complement | sign-extended to 64 bits |
| `u8 u16 u32 u64` | unsigned | zero-extended to 64 bits |
| `bool` | `true` `false` | 0 / 1 |
| `f32 f64` | IEEE 754 binary32 / binary64 | bit pattern (f32 zero-extended) |

Because every value is kept in its canonical 64-bit form, widening is free (no instruction).

### Literals

- **Integers:** `123`, `1_000_000`, `0xff`, `0b1010`, `0o755` (`_` separators in any base; `0X`/`0B`/`0O` too), up to u64 max. Above the i64 max, a literal is `u64`.
- **Floats:** `1.5`, `2e10`, `3.0e-7`. `1..n` stays an integer range.
- **Bool:** `true`, `false`.
- **Untyped until context fixes the type.** A literal adapts to the type it meets and must fit, or it is a compile error (`let x: u8 = 300;`). An integer literal used as a float must be exactly representable. On their own, literals default to `i64` / `f64`.
- **Untyped constants:** `let k = 26;` (immutable, literal initializer) stays untyped, so `k` adapts wherever it is used.

### Implicit conversions

Only lossless integer widenings happen implicitly: `i8→i16→i32→i64`, `u8→u16→u32→u64`, and `uN → iM` for M > N. There is no implicit int↔float, int↔bool, signed→unsigned or f32↔f64 conversion.

### Operators

- **Integer arithmetic runs in 64 bits.**
  - Operands of narrower types promote to `i64`, or to `u64` when the other operand is `u64`. So `u8 + u8` is an `i64` and can't silently wrap at 8 bits.
  - Mixing `u64` with a signed type is a compile error (convert one with `as`).
  - The result is `i64` or `u64`. `/ % < <= > >=` and `>>` follow the signedness: `u64` divides and compares unsigned, and its `>>` is logical. `>>>` is always logical.
  - Shifts: the result has the (promoted) left type; the count may be any integer type, taken mod 64.
- **Floats:** `+ - * /`, comparisons and unary `-`, on two operands of the same float type. A float literal adapts to `f32`.
- **bool:** `! && || == != & | ^`. `if`/`while` conditions must be `bool` (write `x != 0`).
- **Comparisons** yield `bool`; `&&` and `||` short-circuit.

### Casts: `e as T`

`as` binds tighter than binary operators and looser than prefix ones: `-x as u8` is `(-x) as u8`.

| From → to | Meaning |
|---|---|
| int → int | two's-complement truncation / reinterpretation (`200u8 as i8 = -56`, `-1 as u64 = u64::MAX`) |
| bool → int | 0 / 1 |
| int → float | round to nearest |
| float → int | truncate toward zero, **saturating**; NaN → 0 (`300.7 as u8 = 255`) |
| f32 ↔ f64 | widen exactly / round to nearest |
| anything → bool | not allowed (compare instead) |

### Built-ins

- `bits(f)`: the IEEE bit pattern (`f64 → u64`, `f32 → u32`), free.
- `f64_from_bits(u)`, `f32_from_bits(u)`: the reverse, free.
- `sqrt(f)`: correctly rounded (`sqrtsd` / `sqrtss`).

## Structs and globals

```text
struct Tok { kind: u8, len: u16, start: i32, val: f64 }   // natural alignment; here 16 bytes

let MAX = 65536;                      // global constant (untyped, no storage)
let toks = alloc<Tok>(MAX);           // global array: static, zeroed, any element type
let mut ntok: i64 = 0;                // global scalar
let LIMIT: u16 = 300;                 // typed global constant
const FLAGS = 0b0110;                 // `const`: same as an immutable scalar `let`, value must be constant

fn push(k: u8) { toks[ntok].kind = k; ntok += 1; }
```

- **Structs** are record types used as array elements: `alloc<S>(n)`, `[S]` / `mut [S]` parameters, `view<S>(bytes)`.
  - Fields are any scalar type, read and written as `a[i].f` (including `a[i].f op= e`).
  - Fields are laid out in declaration order with natural alignment.
  - Strides that aren't powers of two are fine.
  - There are no whole-struct values yet (copy field by field).
- **Globals:** top-level `let` / `const` is visible in every function.
  - An initializer must be a constant, and a global array needs a constant length (up to 1 GiB total).
  - Global arrays and scalars are static memory; nonzero initial values are stored at program start.
  - In a `par` block, each worker has its own copy, as with all non-shared memory.
  - Range analysis assumes any function may write a global, so loads from globals have their type's range.

## Functions

```text
fn q4(q: [i16], p: [u8], s: i64) -> i64 {          // [T]: read-only array (by reference)
    return q[((p[s] * 26 + p[s + 1]) * 26 + p[s + 2]) * 26 + p[s + 3]];
}
fn fill(a: mut [f64], v: f64) {                    // mut [T]: writable; no return type: unit
    for i in 0..len(a) { a[i] = v; }
}
fn fib(n: i64) -> u64 { if n < 2 { return n as u64; } return fib(n - 1) + fib(n - 2); }
fn byte_at(t: [u8], i: i64) -> u8 { return (t[i] - 32) as u8; }   // u8 - 32 is i64: narrow it back
```

- **Parameters** have any scalar type (`mut x: T` is a mutable local copy) or an array type `[T]` / `mut [T]`. At most 16 parameters. Arguments convert implicitly, as above.
- **Return type:** a function returns `-> T`, or nothing (unit). A unit function may use `return;` and needn't end with it. A unit call is a statement only. A function with a result must end with `return e;`, or with a `loop` that no `break` leaves.
- **Arrays** are passed by reference, as base and length. The element type must match exactly. A read-only array can't be passed to a `mut` parameter.
- **Calls** work anywhere in expressions or as statements. Recursion is supported. Functions may be defined in any order; signatures are collected before bodies are checked.
- **Inside functions:** `argc()`, `file()` and `alloc` are available in `main` only. Functions get arrays through parameters, so a function can never leak memory.
- **Evaluation order:** when calls are involved, operands and arguments are evaluated strictly left to right. A store `a[i] = e` (and `a[i] op= e`) evaluates `e` first, then `i`, each exactly once.
- **Zero-cost abstraction:** non-recursive functions are inlined (expression helpers at simple-argument calls; whole bodies at `let x = f(..)`, `x = f(..)`, `x op= f(..)` and `f(..);`). Range analysis then sees the caller's real arrays.
- **Runtime library:** `print` of floats and bools is implemented by functions written in skite itself. They are compiled with every program but emitted only if used. Names starting with `__` are reserved.

## Parallelism: `par`

```text
let res = shared<i64>(n);         // results come back through shared arrays
par w in 0..ncpu() {              // ncpu() workers, w = 0..ncpu()-1
    let mut t = w;
    while t < n { res[t] = solve(t); t += ncpu(); }
}
// after the block, every worker has finished; print here
```

- **Workers:** `par k in a..b { body }` runs `b − a` workers (at most 256, otherwise a trap), each a forked process with `k: i64` set to `a..b−1`. The block ends when every worker has finished.
- **Memory:** each worker sees a **private snapshot** of all memory. Only `shared<T>(n)` arrays are visible to the parent afterward.
- **Determinism:** inside a `par` body there is no output, `return`, nested `par`, allocation or file mapping. `break`/`continue` are allowed only in loops inside the body. The body can't assign variables declared outside it, and can't call a function that may print. All of this is checked at compile time.
- **Failure:** if any worker traps, the parent waits for all of them, flushes its output and traps (exit status 132).
- **Races:** two workers writing the *same* shared element race (no memory unsafety, but an unspecified winner).
- **`ncpu()`** is the CPU count of the affinity mask. **`par` is `main`-only.**

## Arrays, strings and output

Owned `alloc<T>` and `shared<T>` buffer bases are aligned to at least 64 bytes, including scoped arena allocations. Struct fields keep their natural layout; this guarantee does not extend to borrowed `argv`, file, string literal, or reinterpreted `view` data. Scoped allocation padding can increase memory use.

| Form | Notes |
|---|---|
| `let a = alloc<T>(n);` | zero-initialized array of any scalar or struct `T`; `n` ∈ 1..2³¹−1 (constant: compile-time check; runtime: trap). At `main`'s top level: lives for the whole program. **Anywhere else** (functions, loops): taken from the scoped heap (below) |
| `let a = shared<T>(n);` | the same, visible across `par` workers |
| `save(k, a, n);` | writes the first `n` bytes of `[u8]` `a` to the file named by `argv[k]` (created or truncated, mode 0755); traps if `k ≥ argc`, `n > len(a)` or the write fails; `main` only |
| `let f = file(k);` | maps `argv[k]` read-only as `[u8]`; traps if `k ≥ argc` or open/map fails; an empty file has length 0 |
| `let s = argv(k);` | the text of command-line argument `k` as a read-only `[u8]` (no copy); traps if `k ≥ argc`; `main` only |
| `let w = view<T>(bytes);` | reinterprets a `[u8]` as `[T]` (length = bytes ÷ width, any `T` except `bool` or a struct containing a `bool` field); shares memory; read-only if the source is |
| `alloc8/16/32/64`, `shared8..64`, `view16/32/64` | v0.6 spellings for `u8 i16 i32 i64` |
| `let a: [T] = …;` | optional annotation, checked |
| `let s = "text\n";` | read-only `[u8]` in the program image; escapes `\n \t \r \0 \\ \" \xHH` |

- **Scoped heap:** `alloc` outside `main`'s top level bumps a 16 GiB reserved arena (pages committed on touch). It traps when exhausted.
  - Arrays are zeroed.
  - All arrays allocated during one iteration of the innermost loop are released before the next iteration and when the loop ends.
  - A function's arrays are released when it returns.
  - O(1) allocation and release, no `free`, no GC. It is safe because arrays can't be returned, stored or reassigned, so none can outlive its scope.
- **Loads** give the element type.
- **`a[i] = e`** needs `e` convertible to the element type (a narrowing needs `as`).
- **Compound stores** `a[i] op= e` compute in the promoted type and wrap to the element type.
- **Index:** any integer type.
- **`len(a)`** is `i64`.
- **`write(a)` / `write(a, off, n)` / `write("lit")`:** output bytes. A slice traps unless `0 ≤ off ≤ len` and `0 ≤ n ≤ len − off`.
- **`ewrite(…)`:** same forms as `write`, but to stderr, unbuffered (pending stdout is flushed first, so the two stay in order).
- **`print(e)`:** integers in decimal (`u64` unsigned), `bool` as `true`/`false`, floats in fixed point with 6 decimals (`NaN`, `inf`, `-inf`; values ≥ 2⁶⁴ in approximate scientific notation). Each `print` ends with a newline.
- **`putc(e)`:** one byte (low 8 bits). Output is buffered.

## Statements

| Form | Notes |
|---|---|
| `let x = e;` / `let x: T = e;` | immutable; constants propagate; `let x = y` (both immutable, same type) is an alias |
| `let mut x = e;` / `let mut x: T = e;` | mutable; an untyped literal defaults to `i64`/`f64` |
| `const X = e;` / `const X: T = e;` | an immutable scalar `let` whose value must fold to a compile-time constant (also at top level) |
| `x = e;` | `e` must convert implicitly to `x`'s type |
| `x op= e;` | `op` ∈ `+ - * / % & \| ^ << >> >>>`; computed in the promoted type, then **wrapped** to `x`'s type |
| `if` / `else if` / `else`, `while`, `break`, `continue`, `return`, `{ }` | conditions are `bool` |
| `for i in a..b { }` / `for i in a..=b { }` | counted loop, see below |
| `loop { }` | runs until `break` or `return` (same as `while true`) |

### Loops: `for` and `loop` are zero-cost

`for i in a..b { body }` is exactly the counter loop you would write by hand:

```text
{ let mut i = a; let end = b; while i < end { body; i += 1; } }
```

- `a..b` excludes `b`; `a..=b` includes it (the test is `i <= end`, so `b` must be below the type's maximum). An empty or reversed range runs zero times.
- `a` and `b` are evaluated once, before the first iteration (`end` is skipped when `b` is a constant, an immutable variable or an enclosing `for` variable). Changing a variable used in `b` inside the body doesn't change the trip count.
- `i` is an `i64` (a `u64` if either bound is `u64`; narrower integer bounds widen). It is scoped to the body, where it is read-only: assigning it is a compile error.
- `continue` steps `i` before the next test; `break` leaves the loop.
- Because the loop is the same tree as the `while` form, unrolling, vectorization, bounds-check proofs and strength reduction apply unchanged: `tests/features/for_form.ck` and `while_form.ck` compile to byte-identical executables.

Array bindings are immutable, though their elements are not. Shadowing is not allowed. Reserved names (plus keywords `par in as true false for loop const`): built-ins, constructors, type names, `fn`, `main`, and anything starting with `__`.

## Precedence, loosest → tightest

`||` · `&&` · `== != < <= > >=` (non-associative) · `|` · `^` · `&` · `<< >> >>>` · `+ -` · `* / %` · `as` · unary `- ~ ! +` · `a[i]`, calls, built-ins

## Semantics (normative)

- **Integer arithmetic:** `+ - * <<` wrap modulo 2⁶⁴. `/` truncates toward zero; `%` takes the sign of the dividend (unsigned for `u64`).
- **Division trap:** an integer divisor of 0, or `INT64_MIN / -1` (and `%`), raises SIGFPE (exit status 136). A literal zero divisor is a compile error. A division that might trap is never removed as dead code. Float division never traps.
- **Floats:** IEEE 754 round-to-nearest; no fused or reassociated operations. The compiler folds constants with the same arithmetic.
- **Bounds:** every `a[i]` is checked against `0 ≤ i < len(a)` (unsigned compare). A violation executes `ud2`, raising SIGILL (exit status 132). A check is removed only when range analysis **proves** the index in bounds. File and mapping failures trap the same way.
- **Output** is buffered (64 KiB) and flushed at exit, before a bounds trap, and by the SIGFPE handler.

## How bounds checks get proven

A flow-sensitive interval analysis tracks every scalar through assignments, `if`/`while` conditions (both branches), and loops (fixpoint, widening with guard thresholds, then narrowing). It also tracks:
- **Length facts:** a scalar is known to be `< len(a)` after `i < len(a)`.
- **Array contents:** the join of every value stored into an array.
- **Types:**
  - a load is within its element type's range;
  - a narrowing cast is within its target range (and costs nothing when its input is proven to fit);
  - unsigned compares refine when both sides are proven non-negative;
  - `x % c` on `u64` is in `0..c−1`.

A check is removed when the index range lies within `[0, len−1]` for a constant length, when a length fact applies, or when the index's maximum is below a validated minimum length (`if len(q) < N { return …; }`). In `bench/vigenere/vig.ck`, 67 of 67 checks are proven.

## Optimizations intended to preserve results

- **Division:** magic-number division and modulo by signed constants; shifts and masks for unsigned powers of two.
- **Periodic-index strength reduction:** `(i + E) % p` → a wrapping counter (with `p ≥ 1` and `i + E ≥ 0` proven).
- **Free casts:**
  - `as` to a width at least the element width is dropped right before a store;
  - narrowing casts proven in range are dropped;
  - widening is always free.
- **Float trees:** float expression trees are evaluated in an XMM register stack (xmm2–xmm15). Values move in from leaves once and out at the root once, and loads go straight to XMM. Eligible local f32/f64 variables are allocated to XMM registers; globals and spills may still require memory/register transfers.
- **Codegen:** loop-invariant constants in registers, in-place `x = f(x, …)`, `lea` and 3-operand `imul`, folded address offsets.
- **Dead functions:** variables of functions that were fully inlined (or never called) take no registers or frame slots.

These transformations must preserve language semantics. Known dependence-analysis
risks and hardware validation gaps are tracked in [AUDIT.md](AUDIT.md) and
[issue #9](https://github.com/Dr0pflux/skite.ck/issues/9); listed optimizations are
not an exhaustive correctness proof for all programs.

## Diagnostics

Compile errors go to stderr as `file:line:col: error: message`, followed by the source line and a caret, with exit status 1. Type errors point at the start of the offending expression; declaration errors at the name.

## Configured compiler limits

- Nesting depth 256.
- 1,048,576 AST nodes, 65,536 variables; optimizer-created nodes/variables also use these budgets.
- 1 MiB of user source; 16 MiB of generated machine code.
- 4,096 functions, 16 parameters per function, 64 struct types and 32 fields per struct.
- Identifiers up to 63 bytes.
- NUL bytes in source are rejected.
