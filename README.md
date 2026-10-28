# skite

A self-hosted native compiler for Linux x86-64. The compiler, `skite.ck`, is written in skite
and compiles itself to a byte-identical fixed point. There is no C compiler, assembler, linker,
LLVM/GCC backend, VM or libc anywhere in the build: skite writes x86-64 machine code (including
AVX-512) and the ELF file byte by byte.

```sh
make              # bootstrap/skite-seed builds skite.ck -> skite, which rebuilds itself
make test         # self-check, regression suite and fuzzers
make bench        # Benchmarks Game suite vs gcc, clang and rustc (QUICK=1: smaller sizes)
./skite prog.ck prog && ./prog
```

Learn the language with [`docs/TUTORIAL.md`](docs/TUTORIAL.md); the reference is
[`docs/LANGUAGE.md`](docs/LANGUAGE.md).

Contributors (people and AI agents): read [`AGENTS.md`](AGENTS.md),
[`docs/TEAM_HANDOFF.md`](docs/TEAM_HANDOFF.md) and the current state in
[`docs/HANDOFF.md`](docs/HANDOFF.md) before changing anything.

## Performance

Matched implementations (same algorithm in skite, C and Rust, byte-identical output required);
gcc/clang `-O3 -march=native`, rustc `-C opt-level=3 -C target-cpu=native`. Quick sizes, Xeon
(AVX-512, shared 4-vCPU cloud host, so expect noise), integration head of 2026-10-28.
Ratio = skite time / fastest other; below 1 means skite is faster.

| workload | skite ms | best other | ratio |
|---|---|---|---|
| mandelbrot (Game) | 334 | clang 989 | **0.34** |
| textscan (text statistics kernel) | 119 | rust 142 | **0.84** |
| fasta (Game) | 360 | clang 316 | 1.14 |
| fannkuchredux (Game) | 2565 | rust 2338 | 1.10 |
| spectralnorm (Game) | 253 | gcc 228 | 1.11 |
| nbody (Game) | 312 | rust 224 | 1.39 |
| binarytrees (Game) | 531 | gcc 327 | 1.63 |

The goal is to lead on every arithmetic and text workload; the slower rows are open work
(see [`docs/HANDOFF.md`](docs/HANDOFF.md)). Full history, other hosts (including a Ryzen host
without AVX-512) and methodology: [`docs/BENCHMARKS.md`](docs/BENCHMARKS.md).

What makes skite fast (all bit-exact: strict IEEE floats, wrapping integers, traps preserved):

- **AVX-512 vectorization** with run-time dispatch (CPUs without AVX-512 F/DQ/BW/VL run scalar):
  - *lane-parallel loops*: outer loops whose bodies contain inner loops with data-dependent exits;
  - *element-wise loops and reductions*: `b[i] = b[i] * k + a[i]`, fills, copies, masked `if`/`else`,
    integer `+ - & | ^` reductions, max/min, narrow `u8`..`u32` elements;
  - *byte lanes*: `u8`/`i8` loops (text scanning, character classes, counts, case conversion)
    run 64 characters per instruction, counts via mask popcount, byte sums via `vpsadbw`.
  Unproven bounds and possibly-aliased arrays are checked once before the vector loop; on failure
  the ordinary loop runs and traps exactly where scalar code would.
- **Range analysis** removes bounds checks it can prove, including checks dominated by an earlier one.
- **Calls**: bounded inlining (including recursive), callee-saved registers, tail recursion with
  accumulators turned into loops, register coalescing.
- Floats in XMM registers, magic-number division by constants, fast 32-bit division when
  operands fit, periodic-index strength reduction.

## Layout

| Path | Contents |
|---|---|
| `skite.ck` | the compiler |
| `bootstrap/` | `skite-seed` (prebuilt compiler that starts the build), `skite.c` (original C seed, audit only) |
| `docs/` | tutorial, language reference, design notes, limitations, changelog, benchmarks, audit and handoff notes |
| `examples/` | example and tutorial programs |
| `tests/` | `run.sh` regressions; fuzzers with independent oracles (`cf_fuzz`, `ty_fuzz`, `dag_fuzz`, `divconst`, `vec_fuzz.py`, `stream_fuzz.py`); `stream_boundaries.py`, `alignment.py`, `zero_divisor.py` |
| `.github/workflows/` | CI: clean build, fixed point, `make test`, divisor oracle |
| `bench/game/` | Benchmarks Game suite in skite, C and Rust |
| `bench/kernels/`, `bench/vigenere/` | arithmetic and text kernels (`textscan`, n-grams, ...) and a Vigenère solver |
