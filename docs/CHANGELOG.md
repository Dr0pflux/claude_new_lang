# Changelog

### Unreleased (2026-10-28)

- **Vectorization (Claude):** element-wise loops and integer reductions (stores `a[i] = e`,
  `a[i] op= e`, `s op= e`, narrow element types), masked `if`/`else`, max/min reductions, and
  byte lanes for `u8`/`i8` loops (64 per instruction; counts by mask popcount, sums by `vpsadbw`).
  Bounds and parameter-alias guards fall back to the scalar loop; #9 (mixed-width views) fixed.
  Runtime check now requires AVX-512 BW and VL. Tests: `stream_fuzz.py`, `stream_boundaries.py`,
  `valias*.ck`, `stream_mixed_width.ck`. New kernel `bench/kernels/textscan`.
- **Division:** run-time divisors use a 32-bit `div` when both operands fit in 32 unsigned bits.
- **If-conversion:** small integer `if`/`else` bodies in loops become `cmov` selects; branches that
  store to the same element become one store of a selected value, with all values computed before
  one compare and `+= 1` taken from `setcc` (intsort merge 1.51x → 1.18x clang).
- **Invariant loads:** an innermost loop's unconditional `a[k]` with invariant `k` and `a` not stored in
  the loop is read once before it (only when the loop runs); outside `main` the loop is versioned
  on `base(a) != base(stored)` (editdist 244 → 212 ms). Consecutive `min`/`max` updates are reordered
  so the one reading the previous iteration's value comes last.
- **Bounds-check fix:** a load inside a comparison could lose its check when the branch
  refinement re-evaluated it under the assumption that the check had already passed (pre-existing;
  `tests/data/refine_trap.ck`). The if-conversion operand reorder in `7b6f7bb` also reused a
  register for both compare operands when both were non-trivial (miscompile on `84ff0e4`; fixed).
- **Loop-carried stores:** `a[i - 1]` after a store `a[i]` reads a register (prefixsum 994 → 204 ms).
- **String matching:** small search loops become conjunctions vectorized in byte lanes (strsearch 334 → 43 ms, clang 172).
- **Paired division:** `a / b` and `a % b` share one divide when both are unconditionally evaluated (divmod 390 → 201 ms). The transformation stops at short-circuit `&&`/`||`, so skipped branches cannot introduce division traps.
- **2-D vector indexing:** loads/stores at `i + U` (loop-invariant `U`) vectorize (matmul 654 → 264 ms).
- **Byte-lane recurrences:** a 0/1 state flag (word boundaries) is carried between lanes by mask
  shifts; wordcount kernel 249 → 45 ms (clang 72). 16 new kernels in `bench/kernels` (GAPS.md).
- **Calls/recursion (Claude agent):** dominating bounds-check reuse, dead-at-call save elision,
  tail recursion modulo `+`, register coalescing, deeper inlining of tiny recursive bodies
  (binarytrees 945 → ~600 ms on Xeon).
- **Float-literal correctness:** direct decimal literals in an `f32` context
  round once from the decimal value to binary32, avoiding rare double-rounding
  cases. Literals that default to `f64`, and explicit narrowing such as `literal as f32`, keep
  the existing staged conversion. Twenty exact rational-oracle regression cases cover boundary rounding, aliases,
  signed zero and explicit narrowing. The implementation uses about 8.5 MiB of additional virtual
  metadata mappings; resident-memory impact has not been measured, and no speed gain is claimed.

- **Generated code size:** omit hidden compound-index snapshots for constants and
  stable local scalars, while preserving RHS-first evaluation and snapshots for
  effectful/global indices. Standard nbody ELF shrinks by 1,850 bytes (17.3%);
  compiler grows by 24 bytes. Runtime differences were noise; all six Game outputs
  match. Added fixed-output and trap-order regressions; see [BENCHMARKS.md](BENCHMARKS.md).

- **Compiler size:** reuse analysis-copy indices across field accesses, reducing the
  compiler executable by 3,316 bytes (1,214,532 to 1,211,216). Generated Game and
  unchanged compiler-source binaries remain byte-identical. Five paired timings
  showed no reliable compile-time gain; see [BENCHMARKS.md](BENCHMARKS.md).

- **Correctness and tooling fixes:** reject invalid `view<S>` element layouts (PR #2), bound fuzz
  runs and preserve artifacts on failure (PR #5), reject failed or unknown benchmark runs (PR #6),
  and align scoped buffers to 64 bytes (PR #8).
- **Calls and recursion:** avoid saving caller registers that are dead after a call and reuse
  already-passed bounds checks (`e872829`); add bounded tail-recursion modulo addition, copy
  coalescing, and one additional inline level for tiny recursive functions (`027a8d9`).
- **Compiler build time:** PR #10 skips redundant zeroing before full range-analysis environment
  copies. On a Ryzen 7 5700U, median self-compilation fell from 2.520167 s to 2.221176 s (11.9%)
  across three paired runs after warmup. The compiler executable is 1,836 bytes smaller; generated
  binaries for the six Game programs remain byte-identical. This change affects compile time, not
  program runtime. See [`BENCHMARKS.md`](BENCHMARKS.md) for host, flags, versions, and measurements.
- Performance comparisons are hardware-specific; the historical Xeon and current Ryzen tables are
  reported separately. No global bit-exact guarantee is claimed for all programs. Issue #9 records
  an unresolved alias-proof gap in experimental stream-vectorization work.


Entries below are historical release snapshots. Their measurements, limitations
and future-work lists describe those versions; see [LIMITATIONS.md](LIMITATIONS.md)
and [HANDOFF.md](HANDOFF.md) for current status.

### v0.9

### What changed

- `skite.ck` (~4,300 lines) is the compiler: lexer, correctly-rounded float parsing, parser and type checker, range analysis, inliner, strength reduction, linear-scan register allocation, x86-64 encoder, runtime emission and ELF writer.
- Port method: a line-by-line port of the C seed, keeping node and variable creation order. The result was compared byte for byte against the C seed on all examples, tutorials, tests and benchmarks (identical) before the C seed was retired.
- Bootstrap: `bootstrap/skite-seed` (prebuilt) → `skite` → `skite` again. `make selfcheck` checks the fixed point (stage 2 == stage 3).
- No C is needed to build. `bootstrap/skite.c` stays as an audit trail.

### New built-ins

- `argv(k)`: argument `k` as a read-only `[u8]` (no copy).
- `ewrite(…)`: stderr, unbuffered, flushes stdout first.

### Bugs found and fixed during the port

- **Inlined result variables were live from program start.** Their birth was never recorded, so the allocator held a register or slot for them over all earlier code. Fixed: spills on the compiler went from 1,316 to 789.
- **One global frame size for every function.** Each call reserved stack for every spill in the program, which made deep recursion overflow. Frames are now per function. Codegen also now checks that every stack access stays inside the current frame.
- **Store below the stack pointer.** An unread inlined result was assigned to slot −1 (`[rsp-8]`). It is skipped now, and codegen rejects unallocated variables.
- **Empty-frame removal** could break a prologue trap branch when the scoped heap is in use. It is now skipped in that case.
- **Error paths:** a function that always exits (e.g. `fail`) is never inlined, and range analysis treats a call to it as the end of the path. Bounds proofs still hold after `if bad { fail(..) }`, and no code is bloated with error handling. On the compiler itself, compile time went from 18 s (with error helpers inlined everywhere) to 2 s.
- **Diagnostics:** errors go to stderr with `file:line:col`, the source line and a caret. Type errors name both types. Declaration errors point at the name.

### Numbers

| | value |
|---|---|
| compiler source | `skite.ck`, ~4,300 lines |
| compiler binary | ~1.0 MB machine code |
| self-compile time | ~2 s (C seed built by gcc -O2: ~1.6 s) |
| Vigenère solver | 568.9M instructions, unchanged from v0.8 |

### v0.8

Legend: **[T]** = tested here.

### Added [T]

- **Readable errors:** `file:line:col: error: message`, with the source line and a caret. Type errors point at the start of the offending expression; unknown names are quoted.
- **`TUTORIAL.md`**, with 10 runnable programs in `examples/tutorial/` (hello, types, control flow, functions, files, structs/globals, heap, floats, `par`, `save`).
- **`struct`:**
  - record types used as array elements: `alloc<S>(n)`, `[S]` parameters, `view<S>`, `a[i].f` loads, stores and compound stores;
  - natural alignment; any stride (non-power-of-two strides are scaled with `imul`).
- **Globals:**
  - top-level `let`: constants (no storage), static arrays (bss, zeroed, fixed address), and mutable scalars (static memory, initialized at start);
  - top-level items in any order (two-pass front end).
- **Scoped heap:** `alloc` anywhere.
  - Outside `main`'s top level it bumps a reserved arena.
  - Release happens at the end of each innermost-loop iteration and at function return.
  - O(1) alloc and free, no `free()`, no GC, no leaks, and no dangling pointers, because arrays can't escape their scope.
  - Test: 200,000 × 1 MiB allocations in a loop run in constant memory.
- **`save(k, a, n)`** writes bytes to the file named by `argv[k]` (mode 0755): the output path a self-hosted compiler needs.
- **Small additions:** character literals `'a'`, `'\n'`; `exit(code)`.

### Testing (kept minimal at the owner's request)

- `make test` = regressions + 100 control-flow programs + 100 typed programs.
- New regressions: `tests/data/structs.ck`, `tests/data/heap.ck` (including `save`).
- The heavy battery remains available as `make fuzz`, but isn't part of the normal loop.

### Next

Self-hosting: rewrite the compiler in skite, verify it byte-for-byte against the C seed, reach the fixed point (stage 2 = stage 3), then retire the C.

### v0.7

Legend: **[T]** = tested here; **[H]** = hypothesis.

### Headline [T]

skite now has a static type system: `i8 i16 i32 i64 u8 u16 u32 u64 bool f32 f64`, explicit casts, typed arrays and typed (or unit) functions. Every earlier program and test was ported to strict typing.
- The Vigenère solver keeps 67/67 checks proven.
- It executes the **identical instruction count as v0.6** (416.7M Ir on 300 texts, cachegrind), with fewer spills. It is still ahead of gcc -O3 (median 412 vs 443 ms on this VM).

### Design decisions (all in `LANGUAGE.md`)

| Decision | Why (safer / faster) |
|---|---|
| **Canonical register form:** signed narrow sign-extended, unsigned zero-extended, bool 0/1, floats as bits | Widening is free; a narrow value is a valid i64; loads already produce it |
| **Integer arithmetic promotes to 64 bits** (narrow → i64; next to u64 → u64) | No silent 8/16/32-bit wraparound, and no re-canonicalization instruction after each op (x86-64 64-bit ALU ops cost the same) |
| **u64 mixed with signed = compile error** | Removes the C signed/unsigned comparison bug class |
| **Untyped literals** that must fit their context; untyped `let k = 26;` constants | `let x: u8 = 300;` is an error; constants stay ergonomic |
| **Only lossless implicit widening;** everything else is `as` | Every truncation is visible in the source |
| **float → int saturates, NaN → 0** (Rust semantics) | No UB, no hardware "integer indefinite" leaking |
| **Typed opcodes** (`DIVU`, `LTU`, `FADD`/`GADD`, `SX8`, `SAT8`…) chosen by the parser | Every later pass sees exact semantics in the opcode; no type lookups in the optimizer or codegen |
| **Signatures collected before bodies** (prescan) | Calls are typed while parsing; any definition order still works |
| **Runtime library in skite** (float/bool printing) | First standard-library code written in the language; emitted only if used |

### Compiler changes

- **Front end:**
  - lexer: hex, `_` separators, float literals, u64-range literals;
  - `as` (Rust precedence), `true`/`false`, `alloc<T>`/`shared<T>`/`view<T>`;
  - unit functions (implicit `return;`), `main` returning `i64` or nothing;
  - type checker with literal adaptation;
  - constant folding per type (host IEEE for floats; `sqrt` is not folded, so the seed needs no libm).
- **Range analysis:**
  - element-type load ranges;
  - narrowing casts bounded by their target (and marked free when the input fits);
  - unsigned compares refine when both sides are ≥ 0;
  - `u64 % c` ∈ [0, c−1].
- **Codegen:**
  - typed loads (`movsx`/`movzx`/`mov r32` per element type);
  - unsigned `div`, `jb/jbe/ja/jae`, logical `>>`;
  - saturating `cvttsd2si` fix-up (6 instructions inline);
  - `u64↔float` through small runtime routines;
  - NaN-correct float branches (`ucomisd` + `ja/jae`; `==`/`!=` test PF).
- **XMM expression stack:** float trees are evaluated in xmm2–xmm15, with direct `movsd`/`movss` loads from arrays, memory operands for spilled variables, and nested trees placed above live stack entries.
- **Free casts:** `as` to a width ≥ the element width is dropped before a store, so `p[i] = (… % 26) as u8` costs nothing.
- **Dead-function variables** (fully inlined or never called) no longer get registers or frame slots: solver spills 85 → 30, frame smaller.

### Bugs found and fixed this cycle [T]

All three were found by the new typed fuzzer before release:

1. **Narrowing-cast range after implicit widening.** `(v16 as u32) + u64expr` retagged the cast node to `u64`, so the analysis read a FULL target range, "proved" the cast a no-op and dropped the zero-extension. Fix: the target range comes from the opcode.
2. **XMM stack reuse.** A float tree nested inside an integer subexpression of another float tree (`((v*v) as i32) as f64`) restarted at xmm2 and clobbered the live outer value. Fix: a stack top tracked across nested evaluation, plus a regression test (`tests/types/xmm.ck`, deeper than the 14-register stack).
3. **f32 root precision after `bits()`.** `bits()` retags the node type, so `bits((x / y) as f32)` stored 64 bits with upper garbage. Fix: root precision comes from the opcode.

### Evidence [T]

- **`make test`:** every earlier regression and the Vigenère differentials (serial and `par`), plus:
  - `tests/types/types.ck` (every type, cast and printing rule) and `tests/types/xmm.ck`;
  - 17 ill-typed programs rejected.
- **Typed fuzzer `tests/ty_fuzz.c`:**
  - Random programs over all 11 types: casts between every pair, promotions, u64 ops, f32/f64 arithmetic/compare/neg/sqrt, `bits`/`from_bits`, typed arrays with compound stores, typed helper functions with implicit argument widening, unit functions, untyped literals in every position, `print` of every type.
  - It is checked against an independent C interpreter of the type rules, written from the spec.
  - Pre-release: 10,000+ programs over 21 seeds, 0 failures after the 3 fixes above.
- **Release battery (`make fuzz`):** stopped early at the owner's request: 15 of 80 batches (45000 executions), 0 failures.
- **Sanitizers:** ASan+UBSan compiler build clean on 400 typed + 400 control-flow programs; 6,000 mutated sources (typed syntax tokens included), 0 crashes.

### Float performance, honestly [T]

Spectral-norm (Benchmarks Game, n = 3000, same algorithm, identical output):

| | time |
|---|---:|
| gcc -O3 -march=native (vectorized) | ~180 ms |
| gcc -O3 -fno-tree-vectorize (scalar) | ~385 ms |
| **skite v0.7** | ~700 ms |
| skite before the XMM stack | ~760 ms |

The inner loop is now tight (one `movq` in, one out). What remains:
1. The loop-carried float variable goes through a GPR (+~4 cycles on the critical chain).
2. There is no SIMD.
3. Parameter-length bounds checks are kept.

All three are Phase 3 work: XMM register allocation, vectorization and relational ranges in the SSA backend. Integer code (the Vigenère solver) remains ahead of gcc.

### Next: Phase 2, data

Structs, slices, safe ownership and a heap allocator. Then Phase 3, the SSA backend: XMM allocation, SIMD, GVN/LICM. Floats must beat gcc there.

### v0.6

Legend: **[T]** = tested here; **[H]** = hypothesis.

### Headline [T]

The parallel Vigenère solver uses the same algorithm as the C and Rust versions, the same static stride over ciphertexts and byte-identical output. On 2 CPUs, median of 15 runs, repeated twice:

| | run 1 | run 2 |
|---|---:|---:|
| skite `par` | 444 ms | 466 ms |
| gcc -O3 -fopenmp | 617 ms | 634 ms |
| Rust std::thread | 944 ms | 1009 ms |

skite is ~27% faster than gcc OpenMP and ~2.1× faster than Rust threads.

Serial runs in the same session: skite 712/786 ms, gcc 1004/1091 ms. The VM was slower than in v0.5, so compare ratios. Parallel scaling is ~1.6× on 2 vCPUs for both skite and gcc. clang is not shown because libomp isn't installed here.

### Language

- **`par k in a..b { body }`:** process-level workers, each with a private snapshot. `shared8/16/32/64(n)` uses MAP_SHARED|MAP_ANONYMOUS. `ncpu()` comes from sched_getaffinity.
- **Compile-time rules inside `par`:**
  - no output (`print`, `putc`, `write`)
  - no `return`; no `break`/`continue` at body level
  - no nested `par`; no allocation or `file()`
  - no assignment to outer variables
  - no call to a function that may print (transitive analysis, `fn_outputs`)

  `par` is `main`-only.
- **Runtime:** at most 256 workers, otherwise a trap. A failed worker makes the parent trap (132) after reaping every worker. A worker drops its inherited unflushed output buffer, so nothing is printed twice.

### Design choices (owner may overrule)

- **Processes, not threads.** Determinism and memory safety come for free (copy-on-write snapshots), and there is no shared mutable state except explicit shared arrays.
- **Cost:** fork+reap is ~0.1 ms per worker. Fine for batch computational linguistics (per-text or per-candidate work in milliseconds); not for microtasks.
- **Same-slot writes to shared arrays** by two workers race (no memory unsafety, just an unspecified winner). This is documented. A future checker could prove disjointness from index ranges (`res[k]`-style), using the existing range analysis [H].

### Compiler

- **S_PAR codegen:**
  - `fork` (registers saved around the syscall), child path → body → `exit_group(0)`
  - parent loop → `wait4(-1)` until ECHILD, OR-ing nonzero statuses into a bss flag.
- **Range analysis:** the body is analyzed once with `k ∈ [a.lo, b.hi−1]` (provable `res[k]` stores). Scalars are unchanged after the block; array contents are joined.
- **Statement inlining** now also handles `a[i] = f(..)` (the value is evaluated before the index anyway) and `print/putc(f(..))`. That put all hot-path checks back to proven in the parallel solver.

### Evidence [T]

- **`make test`:** `par` correctness against C, failure propagation, five unsafe forms plus a printing-call rejection, and a parallel-Vigenère differential.
- **`make fuzz`:** 9 modes × 8 seeds × 1,000 programs × 3 argc values. **Final build: 224,100 runs, 75,019 checked traps, 0 failures.**
  - New PAR modes put `par` blocks (1–4 workers) in main: random worker code, private-array writes, and a provably in-range disjoint slice written to a shared array.
  - The interpreter models snapshots exactly; any worker trap means the program traps.
- **Sanitizers:** ASan+UBSan compiler clean on 600 par+func programs; 3,000 mutants gave 0 crashes.

### Next

1. **AVX2 candidate batching** (26 shifts at once in `column_score`) [H: largest single-thread lever].
2. **Provable-disjointness checker** for shared stores, which would make `par` fully deterministic by construction.
3. **f64 and unsigned types; file output; structs.**
4. **AZDecrypt matched-algorithm port** to run on the owner's machine.

### v0.5

Legend: **[T]** = tested here; **[H]** = hypothesis.

### Headline [T]

Functions are in, and they are zero-cost:
- The Vigenère solver is rewritten with five helper functions (`find_period`, `initial_key`, `column_score`, `full_score`, `q4`).
- It still proves all 67/67 bounds checks.
- It produces byte-identical output to the C reference.
- It runs at **474 ms median vs gcc -O3 551 ms** (−14%), clang 573 ms and Rust 780 ms. That is a median of 15 runs on 4,000 held-out texts on the same 2-vCPU VM.

### Language additions (see `LANGUAGE.md`)

- **`fn` definitions:**
  - scalar parameters (`x: i64`, `mut x: i64`)
  - array parameters by reference (`a: [T]` read-only, `a: mut [T]` writable)
  - recursion, calls in expressions and as statements, any definition order.
- **String literals** (`let s = "..";` stored read-only in the image, escapes) and `write(a)`, `write(a, off, n)`, `write("lit")`.
- **Defined evaluation order** with calls: strictly left to right. Stores evaluate the value, then the index, each exactly once.
- **Safety rule:** `allocN`, `file` and `argc` are `main`-only. Functions receive arrays through parameters, so they can't leak memory.

### Compiler design

| Part | Choice |
|---|---|
| Call convention | Internal and caller-saved. The caller pushes every allocatable register that isn't a free temporary at the call site (exactly the live values) and passes arguments in an outgoing area above the return address (arrays as base and length). The callee takes `mov rax,rsp` → `[rax+8+8k]`, and its frame is `sub rsp,F` … `add rsp,F; ret`. Return value in RAX. |
| Register allocation | Still one global linear scan. Each function's positions are disjoint, so functions share registers without interference. Spill slots and frame size are uniform. |
| Analysis | Flow-sensitive ranges per function (parameters FULL, array-parameter lengths [0, 2⁴⁷]). Arrays passed to `mut` parameters get type-range contents in the caller. Calls return FULL and are never invariant or dead. |
| Expression inlining | `fn f(..) { return e; }` with no calls is substituted at calls whose arguments are all simple. Iterated to a fixpoint. |
| Statement inlining | A non-recursive callee (≤ 400 statements, no view/string declarations) is cloned with fresh variables into an `S_INL` block at `let/assign/op-assign/expression-statement` calls. `return` becomes `S_IRET` (assign + jump to block end), which analysis, liveness, strength reduction and codegen all understand. Arguments are bound left to right first. Orphaned call nodes are neutralized so they leave no stale facts behind. |
| Output | String data is appended after the code in the RX segment; absolute addresses are patched after the final layout. `write_sub` copies through the buffered putc. |
| Debugging | `LING0_NO=sr,inline,elide,hoist` disables individual optimizations, for bisecting. |

### Bugs found and fixed this cycle [T]

1. **Double evaluation in compound stores** (present since v0.4, found by the new function fuzzer).
   - `a[i] <<= e` (non-ALU `op=`) was desugared to `a[i] = a[i] << e`, which evaluated `i` twice. That is invisible without side effects and wrong with calls in `i`.
   - Fix: `{ let #v = e; let #i = i; a[#i] = a[#i] op #v; }`.
   - Regression test: `opeq.ck`.
2. **Operand order with calls:** the Sethi-Ullman ordering could evaluate the right operand first. It is now strictly left to right whenever either side contains a call, including the 1-register spill path and conditions.
3. **Stale analysis facts after inlining:** an orphaned call node still marked arrays as passed-to-mut, which lost the `p ∈ [0,25]` proof.

### Evidence [T]

- **`make test`:** all earlier regressions plus functions, strings, `write` and the compound-store regression. The Vigenère differential uses the function-based solver and asserts 67/67 proven.
- **`make fuzz`:** 7 modes × 8 seeds × 1,000 programs × 3 argc values. **Final build: 174,300 runs, 53,206 checked traps, 0 failures.**
  - The new function modes generate 1–3 helpers with depth-guarded recursion, calls between helpers, array parameters (read-only and mut) and nested calls in arguments.
  - Calls appear in expressions and as statement-inlinable forms.
  - The interpreter models real call frames. A step budget regenerates any program that would run too long.
- **Sanitizers:** ASan+UBSan build of the compiler clean on 900 function programs; 4,000 mutated sources (with the new syntax) gave 0 crashes.

### Next proposals

1. **AVX2 candidate batching** for `column_score`: all 26 shifts at once. The largest remaining speed lever [H].
2. **Threads** (`spawn`/`join` over independent ciphertexts) [H: near-linear].
3. **Callee-saved convention for hot non-inlined calls** (save only the registers used), so recursive code pays less.
4. **AZDecrypt matched-algorithm port** (n-gram sizes 5–8, simulated annealing), to run on the owner's machine.

### v0.4

Legend: **[T]** = tested here; **[H]** = hypothesis.

### Headline [T]

On a real computational-linguistics workload (a complete Vigenère solver), the identical algorithm and byte-identical output give:
- skite **~11% faster than gcc -O3** (487 vs 545 ms median of 21 runs), ~15% faster than clang -O3 and ~36% faster than Rust.
- Every array access in the solver is proven safe at compile time (67/67).

Numbers are in `bench/vigenere/README.md`.

### Language additions (see `LANGUAGE.md`)

- **Arrays:** `alloc8/16/32/64(n)` (mmap, zeroed); `file(k)` (mmap argv[k] read-only, zero-copy); `view16/32/64(a)` (reinterpret, shares memory).
- **Element access:** `a[i]`, `a[i] = e`, `a[i] op= e`; `len(a)`.
- **Output:** `print(e)` and `putc(e)` with a buffered stdout runtime.

### Safety design decisions (owner may overrule)

1. **Every index is bounds-checked** unless the compiler proves it in range. A violation is `ud2` → SIGILL (132).
2. **No allocation inside loops** (prevents leaks until there is an allocator); array bindings are immutable.
3. **Output is never lost on a trap.**
   - Bounds trap: flush, then `ud2`.
   - Division trap: a SIGFPE handler flushes, then `exit_group(136)`.
4. **A new ELF RW segment** (bss at 0x600000, no X) holds the output buffer, preserving W^X.
   - This partially addresses review D6. The header-mapping RX segment is unchanged.

### Compiler changes

| Area | Change |
|---|---|
| Range analysis | Flow-sensitive abstract interpretation over the AST: branch refinement, loop fixpoint (widening with guard thresholds → ±∞ fallback → 3 narrowing steps), per-loop cache across outer iterations, `< len(a)` facts, per-alias-class array content ranges. Compile time: 5 ms for the solver. |
| Bounds checks | `cmp idx,len; jae trap` (unsigned also catches negatives); removed only when proven. |
| Periodic-index strength reduction | `(i + E) % p` → shadow counter (conditions in `LANGUAGE.md`). |
| Addressing | SIB loads/stores at every width; register index used directly; `x+c` folded into the displacement when proven. |
| Registers | up to 10 of 12 for variables (≥2 temps guaranteed); `cmp r,0` → `test`; compare against a register-resident var without a copy. |
| Runtime | buffered print/putc/flush subroutines, SIGFPE handler (`SA_RESTORER` is required on x86-64), argv access. |

### Bugs found by the new tests and fixed in this cycle [T]

- **Miscompile (fuzz seed 1, #772):** strength reduction hoisted the initializer `(i + (z % z)) % 26` in front of a loop that never executed. That introduced a division trap absent from the original program.
  - Fix: hoisted parts must be trap-free.
  - Regression test: `srtrap.ck` in `test.sh`.
- **Compiler heap overflow** (found by ASan): loop-entry environments were indexed with a variable count that strength reduction had increased.
  - Fix: environments are sized by `env_n`, fixed at analysis start.
- **Unlinked runtime calls:** calls to `flush` emitted after its body were never patched.
- **SIGFPE handler crash:** `SA_RESTORER` was missing.
- **Analysis non-convergence and precision:** non-monotone loop heads and over-eager widening. Fixed with monotone ascent, guard thresholds and narrowing.

### Evidence [T]

- `make test`:
  - every v0.1–v0.3 regression, plus new memory/file/trap/flush tests
  - unsafe-form rejection
  - Vigenère skite = C differential, with a "67/67 proven" assertion
- `make fuzz` on the final build: 99,600 runs, 25,597 checked traps, 0 failures. It covers 32,000 programs × 3 argc values (plus `make test`'s fuzz runs), across modes plain, pressure (12–40 live variables), memory (arrays of every width, constant and runtime lengths, loads, stores, `op=`, `print`, `putc`) and pressure+memory. Memory mode also stresses:
  - guarded and `len()`-bounded accesses
  - deliberate off-by-one (`<=`) guards
  - negative starts
  - `ctr % d` / `(ctr+e) % d` periodic patterns.

  Every run compares exact stdout and trap behavior with the reference interpreter.
- ASan+UBSan build of the compiler is clean on the fuzz corpora and the solver; 3,000 mutated sources gave 0 crashes.

### Proposed next steps

1. **SIMD (AVX2) for candidate scoring.** Score all 26 shifts of a key position at once:
   - `vpgatherdd`, or table transposition so each candidate is one vector lane
   - expected: the largest remaining lever on the delta-scoring loop [H].
2. **Functions (G2)** with inlining, so solvers don't need copy-pasted loops.
3. **Threads.** Ciphertexts are independent, so the batch is embarrassingly parallel [H: near-linear scaling].
4. **A matched AZDecrypt algorithm port** (higher-order n-grams, simulated annealing) and a run on the owner's machine, for an honest head-to-head.

### v0.3

Legend: **[T]** = tested here; **[H]** = hypothesis.

### Decisions taken (owner may overrule)

1. **D2 trap rule = option A** [T].
   - Rule:
     - A literal or propagated-constant zero divisor is a compile error.
     - A possibly-trapping division is never eliminated as dead code.
     - At runtime, INT64_MIN / -1 and INT64_MIN % -1 trap (SIGFPE).
   - Rationale: deterministic and safe, and it permits magic division for every other constant.
2. **Shift counts are taken mod 64**, matching x86, so shifts have no undefined behavior. `>>` is arithmetic; `>>>` is logical.
3. **Booleans are i64 0/1.** `!x` means `x == 0`; `~x` is bitwise not.
4. **No shadowing; immutable by default.** Assigning to an immutable is a compile error.
5. **`main` must end with `return`.** This is a syntactic rule, so no flow analysis is needed.

### Architecture changes in `skite.c`

| Area | v0.2.1 | v0.3 |
|---|---|---|
| IR | straight-line SSA value list | AST with folding at construction (the MIR/SSA-CFG stage is still planned) |
| Liveness | next-use within one block | lexical intervals; a variable declared outside a loop and referenced inside is extended over the whole loop |
| Regalloc | 7-register pool + next-use eviction | linear scan over 12 registers (≤9 for variables); spill cost = loop-weighted uses ÷ interval length |
| Temporaries | RAX/RCX only | whatever registers no live variable holds at that statement; Sethi-Ullman ordering; stack slots on overflow |
| Branches | none | compare-and-branch with patch lists; rotated loops; short-circuit via cond-jump |
| Division by constant | `idiv` | magic multiply-high / shift; dividend-sign fix-up; skipped when the dividend is proven non-negative |
| Frame | `push rbp`, rbp-relative | rsp-relative, 16-byte aligned, omitted when empty |

Scratch registers: RAX, RCX, RDX (`idiv`, shift count, wide multiply). RSP is the frame. No callee-saved registers are preserved, which is acceptable until G2 adds calls.

### Correctness argument for the allocator

Variables are declared with an initializer and are lexically scoped, so the only values that flow around a back edge are variables declared outside the loop. Extending those over the entire loop span makes the lexical interval a superset of true liveness at every program point, including:
- `break` and `continue`
- the rotated loop's condition, which is emitted after the body
- `if`/`else` arms

Temporaries at a statement are exactly the registers held by no variable whose interval covers that statement. Hoisted constants are pseudo-variables spanning their outermost loop.

**Tested [T]:**
- `run_cf_fuzz.sh` pressure mode keeps 12–40 mutable variables live across every loop.
- The `lea.ck` regression covers every pool register as a base.

### Evidence, final build [T]

- **Unit regressions:** `make test` passes.
- **Control-flow fuzz:** `make fuzz` gave 16,000 programs / 48,000 runs (seeds 1–8 × plain + pressure), 6,391 checked traps, 0 failures.
- **Division by constant:** 137 programs covering 1,089 divisors and about 65M checked divisions.
- **Straight-line oracles:** `run_differential.sh` and `run_dag_fuzz.sh` pass.
- **Hostile input:** sanitized build clean; 3,000 mutated sources gave 0 crashes.
- **Runtime:** see the README table.

### Proposed next steps

1. **G2: functions and the System V ABI.**
   - Callee-saved registers, calls, recursion, an rsp alignment assert in tests.
   - The allocator needs call-clobber intervals.
   - Size: about 1–2 weeks of work.
2. **G3: memory.**
   - u8/i32/u64 loads and stores, slices with bounds checks, `mmap`/`read`/`write`.
   - Unlocks real n-gram tables. This is where the domain advantage has to be shown: with memory-level parallelism across candidates [H].
3. **Branch relaxation (rel8) and `cmov`; range analysis for loop counters.**
   - Drops the `i % 7` sign fix-up in `vigenere29`, where gcc currently leads by about 11% [H: likely closes most of the gap].

### Open disagreements to adjudicate

- **AST codegen versus a MIR/SSA stage.** v0.3 deliberately codegens from the AST, which keeps it small and auditable. SSA/GVN/LICM need a real CFG IR before G5.
  - Proposed objective test: introduce MIR only when an optimization that is measured on the runtime benchmarks requires it.
