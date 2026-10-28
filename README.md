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
(AVX-512, shared 4-vCPU cloud host, so expect ±10% noise), 2026-10-28.
Ratio = skite time / fastest other; below 1 means skite is faster.

Benchmarks Game (`bench/game`):

| workload | skite ms | best other | ratio |
|---|---|---|---|
| mandelbrot | 334 | clang 955 | **0.35** |
| spectralnorm | 256 | gcc 261 | **0.98** |
| fannkuchredux | 2821 | clang 2557 | 1.10 |
| binarytrees | 454 | gcc 296 | 1.53 |
| fasta | 391 | rust 332 | 1.18 |
| nbody | 253 | rust 210 | 1.20 |

Arithmetic and text kernels (`bench/kernels`, `run.py 3`):

| kernel | ratio | kernel | ratio | kernel | ratio |
|---|---|---|---|---|---|
| strsearch | **0.26** | sieve | **0.99** | histogram | 1.01 |
| textscan | **0.40** | divmod | 1.00 | matmul | 1.24 |
| wordcount | **0.64** | polyeval | 1.03 | prefixsum | 1.28 |
| collatz | **0.70** | nqueens | 1.08 | ngramhash | 1.11 |
| caseconv | **0.82** | hashmix | **0.97** | intsort | 1.18 |
| | | gcdsum | 1.18 | editdist | 1.45 |

The compiler fixes rare decimal-to-`f32` double rounding (issue #14)
when a literal is used directly in an `f32` context. Default-`f64` literals and
explicit `literal as f32` narrowing keep their staged conversion. Exact-rounding regressions cover midpoint
and normal/subnormal boundaries; see [`docs/AUDIT.md`](docs/AUDIT.md).


The goal is to lead on every arithmetic and text workload; the slower rows are open work
(see [`docs/HANDOFF.md`](docs/HANDOFF.md)). Full history, other hosts (including a Ryzen host
without AVX-512) and methodology: [`docs/BENCHMARKS.md`](docs/BENCHMARKS.md).

What makes skite fast (all bit-exact: strict IEEE floats, wrapping integers, traps preserved):

- **AVX-512 vectorization** with run-time dispatch (CPUs without AVX-512 F/DQ/BW/VL run scalar):
  - *lane-parallel loops*: outer loops whose bodies contain inner loops with data-dependent exits;
  - *element-wise loops and reductions*: `b[i] = b[i] * k + a[i]`, fills, copies, masked `if`/`else`,
    integer `+ - & | ^` reductions, max/min, narrow `u8`..`u32` elements, 2-D indexing `a[i * n + j]`;
  - *byte lanes*: `u8`/`i8` loops (text scanning, character classes, counts, case conversion,
    word-boundary state machines) run 64 characters per instruction: counts via mask popcount,
    byte sums via `vpsadbw`, a 0/1 state flag carried between characters by shifting its mask,
    and short pattern searches (`while j < m && t[i + j] == p[j]`) turned into byte comparisons.
  Unproven bounds and possibly-aliased arrays are checked once before the vector loop; on failure
  the ordinary loop runs and traps exactly where scalar code would.
- **Range analysis** removes bounds checks it can prove, including checks dominated by an earlier one.
  Runtime-length facts also prove `a[i-k]` for constant `0 <= k <= i < len(a)`,
  including value-preserving integer casts; unsafe offsets and lost facts retain checks.
- **Calls**: bounded inlining (including recursive), callee-saved registers, tail recursion with
  accumulators turned into loops, register coalescing.
- **If-conversion**: small integer `if`/`else` bodies in loops become branch-free `cmov` selects;
  `if C { a[k] = X; .. } else { a[k] = Y; .. }` (merges) becomes one store of a selected value,
  and `v += 1` under the predicate adds the `setcc` result.
  deep logical conditions spill safely when the temporary-register budget runs out.
- **Loop-carried stores**: `a[i] += a[i - 1]` (prefix sums, DP rows) keeps the previous value in a register.
- Floats in XMM registers, magic-number division by constants, fast 32-bit division when
  operands fit, paired `/` and `%` when both are unconditionally evaluated, and
  periodic-index strength reduction. Paired division does not cross short-circuit `&&` or `||`;
  a skipped division keeps its original trap behavior.

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
