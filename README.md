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
(AVX-512, shared 4-vCPU cloud host, so expect ±10% noise), 2026-10-28, head `3a479db` (binarytrees `c0cbc2d`);
Game medians of 3 runs, kernels of 5.
Ratio = skite time / fastest other; below 1 means skite is faster.

Benchmarks Game (`bench/game`):

| workload | skite ms | best other | ratio |
|---|---|---|---|
| mandelbrot | 330 | gcc 942 | **0.35** |
| fasta | 321 | rust 310 | 1.04 |
| spectralnorm | 253 | gcc 240 | 1.06 |
| fannkuchredux | 2592 | rust 2316 | 1.12 |
| nbody | 268 | rust 205 | 1.30 |
| binarytrees | 422 | gcc 335 | 1.26 |

Arithmetic and text kernels (`bench/kernels`, `run.py 3`):

| kernel | ratio | kernel | ratio | kernel | ratio |
|---|---|---|---|---|---|
| strsearch | **0.26** | hashmix | **0.97** | ngramhash | 1.11 |
| textscan | **0.40** | polyeval | **0.98** | gcdsum | 1.14 |
| wordcount | **0.64** | sieve | **0.99** | intsort | 1.17 |
| collatz | **0.70** | divmod | 1.01 | matmul | 1.24 |
| caseconv | **0.82** | histogram | 1.01 | editdist | 1.34 |
| | | prefixsum | 1.08 | nqueens | 1.08 |

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
- **Bounds versioning** guards optimized loop copies with index-range checks; a potentially trapping
  bound expression stays in the original short-circuit loop test.
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

The runtime-length regression suite disables core dumps for expected traps and
retains failing source, input, executable, and command diagnostics under
`SKITE_ARTIFACT_DIR` (or `/tmp/skite-length-facts-artifacts`). Its timeouts and
842 output/trap oracles remain unchanged.
