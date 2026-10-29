# Skite

Skite is a self-hosted native language and compiler for Linux x86-64, built for
text processing, numerical kernels and classical cryptanalysis. Cipher solvers
are user programs; compiler optimizations apply to general language constructs.

The compiler, `skite.ck`, emits x86-64 machine code and ELF executables directly.
The normal compiler build needs no C compiler, assembler, external linker, LLVM,
VM or libc. A prebuilt Skite seed starts the build; self-hosting is checked by
reproducing the compiler byte for byte. The original C bootstrap is retained
only for auditing.

## Build and learn

```sh
make                        # build the self-hosted compiler
./skite prog.ck prog         # compile a program
./prog
make test                   # fixed point, regressions and oracle fuzzing
make bench QUICK=1          # matched Benchmarks Game, smaller preset
```

Tests require Python 3 and a C compiler for independent oracles. Benchmark
comparisons use whichever of GCC, Clang and Rust are installed and report
missing tools. Linux runtime-length trap tests require working `ptrace` child
supervision and fail if it is unavailable.

Start with the [tutorial](docs/TUTORIAL.md) and [language reference](docs/LANGUAGE.md).
See [examples](examples/) for programs and [design notes](docs/DESIGN.md) for the compiler.

## Implemented capabilities

- **Native types and storage:** fixed-width signed/unsigned integers, `f32`/`f64`,
  booleans, structs, arrays, views and scoped allocation. File mappings are read-only;
  views preserve the source's write permissions.
- **Bounds proofs:** range analysis, dominating checks, runtime-length predecessor
  facts and guarded exact-length indices. `a[i-k]` can be proven for constant
  `0 <= k <= i < len(a)`; `a[len(a)-k]` for positive constant `k` when the length
  lower bound proves `len(a) >= k`. Unsafe accesses retain their checks.
- **Loop optimization:** bounds-checked loop versioning, constant-bound unrolling,
  periodic-index strength reduction and carried-store reuse for prefix sums.
- **AVX-512 vectorization:** lane-parallel and element-wise loops, masked stores,
  integer reductions, max/min and narrow integer elements. Byte-lane plans cover
  character classes, counts, folding and supported word-boundary/search patterns.
  Runtime dispatch uses scalar fallback without the required AVX-512 F/DQ/BW/VL
  features. Bounds and alias guards retain the original scalar path when needed.
- **Scalar code generation:** register allocation/coalescing, bounded recursive
  inlining, tail-recursion accumulation, integer if-conversion, XMM floating-point
  values, constant division and paired division/remainder when both are evaluated.
- **Parallel execution:** process-based `par` with partitioned results. Shared-memory
  threads and a low-overhead scheduler remain future work.

Default semantics preserve integer wrapping, observable traps and floating-point
operation order. Optimizations do not silently reassociate floats or contract FMA.
Direct contextual `f32` literals round to binary32; an explicit `literal as f32`
keeps the documented staged conversion.

## Performance and evidence

Performance leadership is the goal, not an established universal result. Compare
matched algorithms with byte-identical output, declared compiler flags, exact
commits and repeated timings on the same hardware. Runtime, compile time, memory,
startup and binary size are separate metrics.

[Benchmark records](docs/BENCHMARKS.md) contain dated host/compiler snapshots,
including the historical Xeon tables previously shown here. They are not current
measurements of every integration head. The primary comparison suite is
[`bench/game`](bench/game/); [`bench/kernels`](bench/kernels/) provides focused diagnostics.

The latest bounds-proof change, [PR #26](https://github.com/Dr0pflux/skite.ck/pull/26),
removes the final check in the existing prefix kernel: 5/6 to 6/6 checks proven,
636 to 624 machine-code bytes. The compiler grows by 384 bytes. Eleven-run timing
distributions overlap, so no runtime speedup is claimed. Exact hashes, hardware,
raw samples and GCC output controls are in [the evidence record](bench/length_facts/terminal.md).
Clang and Rust were unavailable for that measurement.

## Validation and status

`make test` checks the self-hosting fixed point, regressions and independent
control-flow, typed, vector and stream oracles. It includes 75 deterministic
fuzz-harness fault checks and 1,442 runtime-length output/trap cases under normal
and scalar compilation. Failures retain sources, inputs and diagnostics under
`SKITE_ARTIFACT_DIR`; subprocess deadlines and process-group cleanup are enforced.
CI additionally runs the historical control-flow failure seed and divisor oracle.

PR #26 passed both CI runs and independent available-agent review. Genuine Claude
cross-review is queued for Saturday, October 31; it is not claimed as completed.
The [shared ledger](https://github.com/Dr0pflux/skite.ck/issues/3) records exact
reviewed/tested commits and newer state.

Known open correctness work includes the old bootstrap seed's image-size overlap
[issue #25](https://github.com/Dr0pflux/skite.ck/issues/25). The current integration
build passes; refreshing the seed is a separately owned task.

Modules/separate compilation, shared-memory threads, stronger ownership/alias
semantics, first-class SoA, broader compile-time evaluation, AVX2 lowering and an
ARM64 backend remain roadmap work. See [project goals](https://github.com/Dr0pflux/skite.ck/issues/7)
and the [classical-cryptanalysis roadmap](docs/CLASSICAL_ROADMAP.md).

## Repository and contribution guide

| Path | Contents |
| --- | --- |
| `skite.ck` | Self-hosted compiler and native backend |
| `bootstrap/` | Prebuilt seed and archived C bootstrap |
| `docs/` | Tutorial, reference, design, audits, measurements and handoffs |
| `examples/` | Example and tutorial programs |
| `tests/` | Regressions, fuzzers and independent oracles |
| `bench/` | Matched Game workloads, diagnostic kernels and example solvers |
| `.github/workflows/` | Build, fixed-point and regression CI |

Before editing, read [AGENTS.md](AGENTS.md), the [team workflow](docs/TEAM_HANDOFF.md),
[handoff notes](docs/HANDOFF.md) and the latest ledger comments. Keep the README
and relevant documentation aligned with merged behavior, measured results and
pending reviews as changes land.
