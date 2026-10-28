# Current limitations

Updated against integration `c4837cf` on 2026-10-28. Planned goals are tracked in
[issue #7](https://github.com/Dr0pflux/skite.ck/issues/7); they are not all implemented.

1. **Targets and portability.** Executables target Linux x86-64. There is no
   completed AArch64 backend or verified ARM NEON output. The build uses the
   prebuilt Skite seed; the archived C compiler is an audit path, not a dependency.
2. **Program composition.** Modules/imports, cross-file interfaces, dynamic strings,
   and returning or storing arrays are not established features. See the current
   [language reference](LANGUAGE.md) for supported constructs.
3. **Performance evidence.** Regular Game workloads use matched algorithms and
   checked outputs. Results depend on CPU features, sizes and flags; see
   [BENCHMARKS.md](BENCHMARKS.md). The verified Ryzen measurements still trail the
   best C/Rust comparator. No claim of winning every metric is justified.
4. **Vectorization and aliasing.** AVX-512 vectorization and scalar dispatch exist,
   but not every loop is vectorizable. The stream/reduction extension remains WIP.
   [Issue #9](https://github.com/Dr0pflux/skite.ck/issues/9) tracks mixed-width view
   dependence checks; parameter aliases also require care. Views/sharing are not
   an enforced non-aliasing memory model. Scalar fallback tests do not prove SIMD
   correctness. Default floating semantics do not permit FMA contraction or
   reassociation merely for speed.
5. **Parallelism.** `par` uses processes. A lower-overhead shared-memory thread
   runtime, atomics and verified multicore scaling against C/Rust remain goals.
   Process launch/join overhead matters for small tasks.
6. **Memory layout.** Owned buffers are at least 64-byte aligned: static-array offsets
   are rounded to 64 bytes, main-level mappings are page-aligned, and scoped arena
   allocations round their base to 64 bytes. Borrowed data is not universally aligned, natural struct layout
   remains observable, and a verified structure-of-arrays facility is still a goal.
   Scope release constrains array lifetime/escape behavior.
7. **Register allocation and analysis.** Per-function frames, XMM float variables,
   limited copy coalescing, mutable-variable range analysis and dominating bounds
   reuse exist. They do not eliminate all spills or checks. Interval analysis and
   selected length facts cannot express every relation between indices/arrays.
   Spill-slot reuse and more precise liveness remain opportunities.
8. **Calls and recursion.** Inlining and selected scalar integer tail-recursion
   transformations reduce overhead; other recursive calls still require frames
   and live-register preservation. Stack exhaustion remains possible.
9. **Executable/runtime interface.** Fixed-address ELF output lacks a general
   external linking/debugging ecosystem. Runtime traps are not rich source-level
   diagnostics. This is not a drop-in system ABI/library toolchain.
10. **Compile-time evaluation and tuning.** Folding, unrolling, range analysis and
    constant-division lowering exist. Deterministic resource-bounded arbitrary
    compile-time evaluation, target profiles and measured host microtuning remain
    separate goals; no privileged OS driver is required by the current compiler.
11. **Tests are bounded.** Fuzzers/oracles have per-input limits and retained failure
    artifacts, but finite tests do not establish correctness for all programs.
    AVX-512 and ARM claims need appropriate execution hardware.
12. **Type ergonomics.** Narrow integer arithmetic promotes to i64; explicit casts
    are needed to store results back into narrow slots. Float formatting is not
    a general shortest-round-trip library; consult [LANGUAGE.md](LANGUAGE.md).
