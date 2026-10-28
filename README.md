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

## Performance

Benchmarks Game programs, the same algorithm in skite, C and Rust, byte-identical output
required (`bench/game/`). gcc/clang `-O3 -march=native`, rustc `-C opt-level=3 -C target-cpu=native`.
Results and methodology: [`docs/BENCHMARKS.md`](docs/BENCHMARKS.md).

What makes skite fast:

- **Bit-exact auto-vectorization.** Loops whose bodies start with pure computation (including
  inner loops with data-dependent exits) run 8 or 16 iterations at once in AVX-512 registers
  under k-masks; the rest of the body runs per lane in order. Results are bit-identical to scalar
  execution (no reassociation, no FMA contraction). CPUs without AVX-512 take the scalar path.
- **Proven-safe indexing:** every array access is bounds-checked unless range analysis proves it.
- **Zero-cost helpers:** non-recursive functions are inlined; bounds proofs flow through them.
- Floats in XMM registers, periodic-index strength reduction, magic-number division.

## Layout

| Path | Contents |
|---|---|
| `skite.ck` | the compiler |
| `bootstrap/` | `skite-seed` (prebuilt compiler that starts the build), `skite.c` (original C seed, audit only) |
| `docs/` | tutorial, language reference, design notes, limitations, changelog, benchmarks |
| `examples/` | example and tutorial programs |
| `tests/` | `run.sh` regressions; fuzzers with independent oracles (`cf_fuzz`, `ty_fuzz`, `dag_fuzz`, `divconst`, `vec_fuzz.py`) |
| `bench/game/` | Benchmarks Game suite in skite, C and Rust |
| `bench/kernels/`, `bench/vigenere/` | computational-linguistics kernels and a Vigenère solver |
