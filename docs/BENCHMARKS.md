# Benchmarks

These tables describe different machines and compiler snapshots. Compare ratios within each table;
do not compare milliseconds across the two hosts. The programs are the repository's matched
Benchmarks Game implementations, not a claim about every external implementation.

## Current Ryzen quick-size snapshot

Source/compiler head: `027a8d9797ec9dbee1b7041fe6138b9eb6b7e36e` (`skite.ck` SHA-256
`08b568142df8bd878c7bdbbc66d8ea63832cc3d2b95b5cf5ac5433f2e9fe393a`). The table uses three
interleaved repetitions per language; the runner rejects results unless all outputs match.

- Machine: AMD Ryzen 7 5700U with Radeon Graphics, Linux x86-64, 16 CPUs; AVX2 available,
  AVX-512 unavailable. No CPU affinity was set.
- Single-process workloads; this table does not measure multicore scaling.
- Skite: native defaults.
- C: GCC 16.2.0 and Clang 21.1.8, both `-O3 -march=native`.
- Rust: rustc 1.93.1, `-C opt-level=3 -C target-cpu=native -C codegen-units=1 -C panic=abort`.
- Command: `python3 bench/game/run.py 3 --quick`; times are median milliseconds.

| Benchmark | Argument | Skite | GCC | Clang | Rust | Skite vs fastest |
|---|---:|---:|---:|---:|---:|---|
| nbody | 5000000 | 393 | 284 | **194** | 202 | 2.02x slower |
| spectralnorm | 3000 | 421 | 418 | **418** | 420 | 1.01x slower |
| mandelbrot | 4000 | 908 | **869** | 882 | 932 | 1.04x slower |
| fannkuchredux | 11 | 2167 | 1877 | 2242 | **1727** | 1.26x slower |
| fasta | 2500000 | 254 | **232** | 262 | 262 | 1.10x slower |
| binarytrees | 19 | 390 | **210** | 444 | 490 | 1.86x slower |

All six outputs matched byte for byte. These results include tail-recursion and code-generation
changes through `027a8d9`; PR #10's subsequent environment-copy change affects compiler build time,
not these generated program runtimes.

## Historical Xeon snapshot

This table is preserved from the benchmark documentation recorded at commit
[`29e59588cab205a4ef6c828f0b7c7cbcf2ddb428`](https://github.com/Dr0pflux/skite.ck/commit/29e59588cab205a4ef6c828f0b7c7cbcf2ddb428).
This is the commit recording the table, not a verified identification of the exact
compiler used for those historical timings. The numbers and toolchains below are
as originally reported and have not been rerun by Codex. Host: Intel Xeon Cascade
Lake at 2.8 GHz, AVX-512 with one 512-bit FMA unit, 4-vCPU shared VM. Expect several percent of
noise. The originally reported toolchain versions were GCC 13.3, Clang 18.1, and rustc 1.97, with
`-O3 -march=native` for C and `-C opt-level=3 -C target-cpu=native -C codegen-units=1 -C panic=abort`
for Rust. The command was `python3 bench/game/run.py 3 --quick`; times are median milliseconds.

| Benchmark | Argument | Skite | GCC | Clang | Rust | Skite vs fastest |
|---|---:|---:|---:|---:|---:|---|
| mandelbrot | 4000 | **373** | 1512 | 1469 | 1540 | **3.9x faster** |
| spectralnorm | 3000 | 273 | **245** | 457 | 612 | 1.11x slower |
| nbody | 5000000 | 642 | 327 | 315 | **283** | 2.3x slower |
| fannkuchredux | 11 | 3092 | 2663 | 2974 | **2571** | 1.2x slower |
| fasta | 2500000 | 504 | 399 | 345 | **339** | 1.5x slower |
| binarytrees | 19 | 924 | **351** | 633 | 666 | 2.6x slower |

The historical mandelbrot result is specific to this Xeon snapshot and its compiler versions; it is
not the current Ryzen result.

## Compiler compile-time change (PR #10)

On the Ryzen 7 5700U, one warmup and three paired self-compilation runs, alternating baseline and
candidate order, reduced median compile time from 2.520167 s at `027a8d9` to 2.221176 s at
`5e86b4b` (11.9%). The compiler executable was 1,836 bytes smaller. All six Game outputs, the
compiler-source output, and a nested integer/float constant probe were byte-identical. This is a
compiler build-time improvement, not a generated-program runtime improvement.

## Compiler size: analysis-copy index reuse

Naming the existing source/destination indices once per `env_copy` iteration lets
bounds-check refinement reuse their checks across the four fields. Copy order,
indices and trap semantics are unchanged. The compiler executable shrinks from
1,214,532 bytes at integration `08737b4` to 1,211,216 bytes (3,316 bytes, about 0.27%).
Candidate compiler source SHA-256:
`7e93d1c9d5855138ad9d1263373271dde1b788094d32bfde8032b5d1b9c32391`.

On the same Ryzen 7 5700U (AVX2, no AVX-512), native defaults, no affinity,
one warmup and five alternating paired compilations of the unchanged compiler
source gave these elapsed seconds:

- Baseline: 2.253320, 2.247334, 2.250139, 2.192374, 2.174151; median 2.247334.
- Candidate: 2.308262, 2.248720, 2.255666, 2.167758, 2.167910; median 2.248720.

The 0.06% median increase is noise, not evidence of a speed gain. Fannkuch source
compilation medians were 11.181 versus 10.730 ms, also too small/noisy to support
a reliable speed claim. Both compilers emitted byte-identical binaries for all
six Game sources and the unchanged compiler source. This is a compiler-size
improvement; no generated-program runtime or binary-size gain is claimed.

## Nbody executable size: compound-index snapshots

General compound array/field assignments can retain constant or stable local
indices directly instead of creating a hidden index binding. Effectful/global
indices still use a snapshot; RHS-first evaluation and trap order are preserved.
This changes the compiler parser, not the benchmark algorithm or floating operations.

Baseline compiler: `f09ec806427591b2e218315ac8ba2f3a6814a23d`; candidate compiler
source SHA-256 `338aa881b876be10fad1358557206660863b9b7ce5205a88184de8519b233a9f`.
Unchanged `bench/game/nbody.ck` SHA-256:
`25788fb904106f3f2bb707016c1066e6e65976e7f7de11a1a1d0a0f06e687f9e`.
The nbody ELF shrinks from 10,705 to 8,855 bytes (1,850 bytes, 17.3%); the compiler
itself grows from 1,211,216 to 1,211,240 bytes (+24). Other five Game executable
sizes are unchanged. Outputs match byte for byte for all six quick-size workloads.

Ryzen 7 5700U, Linux x86-64, AVX2/no AVX-512, native Skite defaults, no affinity;
nbody argument 5,000,000, one warmup each, five pairs in alternating order:

- Baseline seconds: 0.391563, 0.394524, 0.395704, 0.394669, 0.393073; median 0.394524.
- Candidate seconds: 0.393318, 0.393052, 0.395602, 0.392831, 0.393711; median 0.393318.

The 0.31% runtime difference is within noise; no speedup is claimed. Both output
hashes are `a209785651d3f855b56ffcac6bce1eda49dff67124f34418aedd4ddb91c384c8`.
Fixed-oracle regressions cover global/effectful/direct indices, RHS mutation,
integer division traps before bounds checks, and f32/u8 struct-field updates.

## Correctness scope

Measured outputs match for the listed programs. This does not establish a universal bit-exact
guarantee for every program. [Issue #9](https://github.com/Dr0pflux/skite.ck/issues/9) tracks a
remaining alias-proof gap in experimental stream-vectorization work; native AVX-512 validation is
still needed for that work. Skite does not contract floating-point multiply-add into FMA.
