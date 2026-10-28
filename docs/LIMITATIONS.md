# Current limitations (v0.9)

1. **Self-hosted, with caveats.**
   - The compiler is `skite.cock`. The build starts from the prebuilt `bootstrap/skite-seed`; `bootstrap/skite.c` is only an audit trail.
   - Test generators (`tests/*_fuzz.c`) and C/Rust baselines in `bench/` are still C; they are tooling, not part of the compile path.
   - The self-built compiler compiles itself in ~2 s (the gcc-built C seed took ~1.6 s for the same source). Compile-speed work is still to come.
   - Missing for larger programs: modules, returning or storing arrays, dynamic strings.
2. **Speed evidence:** two arithmetic kernels plus one real solver, on one shared VM. Runs to do on bare metal:
   - perf counters
   - memory-bound kernels (needs G3)
   - a best-of-ecosystem comparison
3. **Allocator.**
   - Linear scan, but a spilled variable stays in memory for its whole life (no interval splitting).
   - No spill-slot reuse; no copy coalescing.
   - Liveness is lexical with loop extension, which is conservative.
   - `temps_at` is O(vars) per statement, so compile time is O(n²) worst case.
4. **Instruction selection.**
   - No branch relaxation: every jump is rel32.
   - No `cmov`.
   - Magic constants are not hoisted.
   - No `lea` scale forms (×3/5/9).
   - A dying variable's register is not reused for the expression that consumes it (one extra `mov` at some returns).
5. **No range analysis on mutable variables.** For example, a loop counter `i ≥ 0` is not proven, so `i % 7` keeps its sign fix-up.
6. **Fixed-address ET_EXEC.** One R+X `PT_LOAD` that maps the headers (review D6). No PIE, relocations, sections, or debug info.
7. **Runtime ABI.**
   - Linux entry → print-and-exit only.
   - Traps surface as SIGFPE with no diagnostic.
   - RBX/RBP/R12–R15 are clobbered freely (fine with no calls; must be fixed in G2).
8. **Oracles are bounded.**
   - The fuzzer's loops are counter-bounded (`while c < N && cond`), so arbitrary loop exits are tested only through `break`, `continue` and `return`.
   - There is no exhaustive proof of the magic-division constants; the method is the published one, validated over about 65M cases.
9. **No SIMD yet.** Parallelism is process-based (`par`).
   - Fork cost is ~0.1 ms per worker, fine for batch work but not for tiny tasks.
   - Shared-memory threads with atomics are not available.
10. **Range analysis is intervals, not relations.** Beyond `< len(a)` facts it can't prove things like `i + 3 < n` from `i <= n - 4` unless the intervals work out. The fallback is a check (safe), never an unchecked access.
11. **Stack slots are not reused** between a function's non-overlapping spilled variables (frames are per function since v0.9).
12. **Calls are caller-saved.** A hot *non-inlined* call (recursion) pushes and pops the live registers. Inlining removes this cost for non-recursive helpers.
13. **Floats live in general registers.**
    - Float expression trees run in an XMM stack, but float *variables* still sit in GPRs.
    - So a loop-carried float (`s += …`) pays a `movq` round trip each iteration.
    - Spectral-norm (n=3000) is ~1.8× slower than scalar gcc -O3 and ~3.9× slower than vectorizing gcc -O3. XMM register allocation and SIMD are Phase 3 (SSA backend).
    - Float printing is fixed 6 decimals, not shortest round-trip; values ≥ 2⁶⁴ print in approximate scientific notation. There is no `log`/`exp` yet (Phase 4 library).
14. **Uniform frame size across functions** (the maximum over all of them), which wastes stack in deep recursion. Stack overflow hits the guard page as SIGSEGV.
15. **Type ergonomics:** narrow integer arithmetic promotes to i64, so `n - 1` with `n: u32` needs `as u32` to go back into a `u32` slot. This is deliberate (no silent 8/16/32-bit wraparound), but verbose for code that computes in narrow types.
16. **Bounds checks on parameter arrays.** `v[j]` with `j < n` (where `n` is a separate parameter, not `len(v)`) keeps its check. Write loops against `len(v)` to get proofs (spectral-norm: 3/16 elided).
