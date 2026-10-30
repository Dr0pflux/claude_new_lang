# Skite

Skite is a self-hosted native language and compiler for Linux x86-64, built for
text processing, numerical kernels and classical cryptanalysis. Cipher solvers
are user programs; compiler optimizations apply to general language constructs.

The compiler, `skite.ck`, emits x86-64 machine code and ELF executables directly.
The normal compiler build needs no C compiler, assembler, external linker, LLVM,
VM or libc. A prebuilt Skite seed starts the build; self-hosting is checked by
reproducing the compiler byte for byte. The original C bootstrap is retained
only for auditing.

## Native code and runtime work (branch `claude/native-runtime-20261030`)

Machine-code and runtime changes, verified by self-hosting fixed point, `tests/run.sh`
and differential fuzzing (no benchmark claims):

- **Loop layout:** loop heads are padded (never executed) and innermost loops are laid out so
  their branches do not cross 32-byte lines (the JCC erratum made such loops up to ~1.9x slower);
  main's empty frame is replaced by a NOP instead of being cut out, which shifted every loop.
- **Bounds checks:** `alloc(n)` with an immutable `n` makes `i < n` prove `i < len(a)`; proven
  accesses no longer keep the array length live in a register.
- **Allocation runtime:** `alloc<T>(n)` bumps a pointer in a lazily faulted 1 GiB reservation
  (one `mmap` per chunk instead of one syscall and six register saves per array).
- **Copy loops:** `A[i + d] = B[i + s]` loops over static arrays become `rep movs` when every copied
  range is in bounds (the checked loop runs otherwise, so traps are unchanged).
- **Compiler speed:** the range analysis keeps its environments as separate field arrays, copies
  once per `if`, iterates loops only over assigned variables, and resets its loop cache
  incrementally; hoisted loop constants are kept in per-loop lists. Self-compile 5.9 s → 1.7 s.
- **Also:** `x * 3/5/9` as `lea`, 8-bit stack adjustments (owner's local experiment), loop-local
  copies of read-only scalars, stream loops without dead iota or per-block broadcasts.

**Matrix types (owner's local fork, merged here):** `alloc<T>(rows, cols)` (constant or runtime
shape, each dimension evaluated once; invalid or overflowing shapes exit), `m[r, c]`,
`m[r, c, stride]` flat sugar, `rows(m)`/`cols(m)`, and `matrix[T]` / `mut matrix[T]` parameters
that carry the shape as hidden arguments. Each coordinate is checked on its own, so `m[0, cols]`
traps even when the flat offset is in bounds. Checks are dropped only for constant or
`for i in 0..rows(m)` / `0..cols(m)` coordinates. A pure one-expression predicate called on an
array load (`if p(a[i])`) is now inlined, using one temporary for the load. Covered by
`tests/matrix_test.py` (19 cases, run by `tests/run.sh`).

**Seed refreshed ([issue #25](https://github.com/Dr0pflux/skite.ck/issues/25)):** the old seed put BSS at
`0x600000`, so any compiler image over 2 MiB overlapped it and crashed. `bootstrap/skite-seed` is now
this branch's fixed point (SHA-256 `b8c88884…9b44d`), produced by the chain old seed
(`cedfd47a…`) → integration `42d02c9` source → its fixed point → this `skite.ck` → fixed point.
`make` now works from a clean tree and reproduces the seed byte for byte.

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
  values, constant division (including unsigned immediate constants) and paired
  division/remainder when both are evaluated.
  Complementary logical shifts of the same pure 64-bit value can use one rotate
  when combined with OR, XOR or wrapping ADD.
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

Recent focused measurements, with exact hashes, raw samples and limitations in each record:

| Change | Measured result | Evidence |
| --- | --- | --- |
| Unsigned odd constant division/remainder | Dependent `% 29`: 317.53 to 205.64 ms; compiler +1,280 bytes | [Record](bench/unsigned_odd/README.md) |
| Unsigned even constant division/remainder | Dependent `% 26`: 333.18 to 231.25 ms; compiler 2,304 bytes smaller | [Record](bench/unsigned_even/README.md) |
| Complementary-shift ADD to rotate | 96.72 to 62.97 ms; kernel 10 bytes smaller | [Record](bench/rotate_add/README.md) |
| Guarded terminal bounds proof | Prefix code 636 to 624 bytes; compiler +384 bytes; no reliable runtime win | [Record](bench/length_facts/terminal.md) |

The three arithmetic diagnostics use 11 interleaved runs. Their six Game binaries are
unchanged; these are focused improvements, not general C/Rust or Game speed
claims. The `% 26` diagnostic still trails its GCC control (197.40 ms); `% 29` locally
measures below its GCC control (245.89 ms). Clang and
Rust were unavailable for these local measurements.

## Validation and status

`make test` checks the self-hosting fixed point, regressions and independent
control-flow, typed, vector and stream oracles. It includes 52,818 unsigned-divisor and 9,096 rotate-add oracle outputs, plus 75 deterministic
fuzz-harness fault checks and 1,442 runtime-length output/trap cases under normal
and scalar compilation. Failures retain sources, inputs and diagnostics under
`SKITE_ARTIFACT_DIR`; subprocess deadlines and process-group cleanup are enforced.
CI additionally runs the historical control-flow failure seed and divisor oracle.

PR #26 passed both CI runs and independent available-agent review. Genuine Claude
cross-review is queued for Saturday, October 31; it is not claimed as completed.
The [shared ledger](https://github.com/Dr0pflux/skite.ck/issues/3) records exact
reviewed/tested commits and newer state.

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
