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

Performance depends on the machine and compiler versions. The historical Xeon results and the
current Ryzen results are separate snapshots in [`docs/BENCHMARKS.md`](docs/BENCHMARKS.md).
On the Ryzen 7 5700U quick-size run, Skite was 2.02x slower than the fastest reference on nbody,
1.01x on spectralnorm, 1.04x on mandelbrot, 1.26x on fannkuchredux, 1.10x on fasta, and 1.86x
on binarytrees. These are matched implementations with byte-identical output, not rankings against
every implementation. The 3.9x mandelbrot lead in the older Xeon snapshot is specific to that host.

Merged PR #10 reduced compiler self-compilation median time on the same Ryzen from 2.520167 s to
2.221176 s (11.9% lower across three paired runs after warmup). It did not improve generated
program runtime; binaries for the six Game programs remained byte-identical. See the measurement
method and compiler versions in [`docs/BENCHMARKS.md`](docs/BENCHMARKS.md).

What makes skite fast:

- **Vectorization:** eligible loops can use AVX-512; CPUs without AVX-512 take the scalar path.
  Tested programs match their scalar/reference outputs. A global bit-exact guarantee for all
  programs has not been established; [issue #9](https://github.com/Dr0pflux/skite.ck/issues/9)
  tracks an alias-proof gap in the experimental stream-vectorization work.
- **Proven-safe indexing:** array accesses are bounds-checked unless range analysis proves them safe.
- **Bounded inlining:** small helpers can be inlined within size budgets; bounds proofs flow through them.
- Floats in XMM registers, periodic-index strength reduction, and magic-number division.

## Layout

| Path | Contents |
|---|---|
| `skite.ck` | the compiler |
| `bootstrap/` | `skite-seed` (prebuilt compiler that starts the build), `skite.c` (original C seed, audit only) |
| `docs/` | tutorial, language reference, design notes, limitations, changelog, benchmarks, audit and handoff notes |
| `examples/` | example and tutorial programs |
| `tests/` | `run.sh` regressions; fuzzers with independent oracles (`cf_fuzz`, `ty_fuzz`, `dag_fuzz`, `divconst`, `vec_fuzz.py`); `alignment.py`, `zero_divisor.py` |
| `.github/workflows/` | CI: clean build, fixed point, `make test`, divisor oracle |
| `bench/game/` | Benchmarks Game suite in skite, C and Rust |
| `bench/kernels/`, `bench/vigenere/` | computational-linguistics kernels and a Vigenère solver |
