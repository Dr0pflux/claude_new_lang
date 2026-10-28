# ling: a native compiler written in its own language (v0.9)

**Status:** experimental Linux x86-64 compiler. **Self-hosted:** the compiler is `ling.cock`, written in ling0, and it compiles itself to a byte-identical fixed point.

- No C compiler, assembler, linker, LLVM/GCC backend, VM or libc anywhere in the build. ling writes x86-64 machine code and the ELF64 file byte by byte.
- `bootstrap/ling-seed` is a prebuilt ling executable used to start the build. `bootstrap/ling0.c` is the original C seed, kept only so the chain can be audited (`make seed-from-c`).

## Build and use

```
make            # bootstrap/ling-seed builds ling.cock -> ling, which rebuilds itself
make selfcheck  # ling must reproduce itself byte for byte
make test       # regression suite + small fuzz runs
./ling prog.cock prog && ./prog
```

Learn the language with `TUTORIAL.md`; the reference is `LANGUAGE.md`.

## New in v0.9: self-hosting

- The whole compiler (lexer, type checker, range analysis, inliner, strength reduction, register allocator, x86-64 encoder, ELF writer) is ported to ling0: about 4,300 lines in `ling.cock`. Its output was verified byte-identical to the C seed on every example, test and benchmark before the C seed was retired.
- New built-ins the compiler needed: `argv(k)` (an argument's text as `[u8]`) and `ewrite(…)` (unbuffered stderr).
- Fixes found while porting: inlined-call result variables were live from program start (spills on the compiler 1,316 → 789); every function shared one global-sized stack frame (now per-function frames); an unread inlined result could be stored below the stack pointer; error-path functions (always `exit`) are no longer inlined and are treated as non-returning by range analysis.
- See `V0.9_NOTES.md`.

## New in v0.7: Phase 1, the type system

- **Types:** `i8 i16 i32 i64 u8 u16 u32 u64 bool f32 f64`.
  - Values are kept in a canonical 64-bit register form, so widening costs nothing.
  - Literals are untyped until context fixes them (and must fit).
  - Integer arithmetic promotes to 64 bits, so there is no silent narrow wraparound.
  - `u64` uses unsigned division, comparisons and shifts.
  - Mixed signed/`u64` operands are a compile error.
- **Casts `as`:** integer casts wrap; float→int casts saturate (NaN → 0), as in Rust.
- **Floats (SSE2):** f32/f64 arithmetic and comparisons with exact IEEE semantics (NaN-correct branches), `sqrt`, and `bits`/`from_bits`. Float expression trees are evaluated in an XMM register stack.
- **Typed arrays:** `alloc<T>`, `shared<T>`, `view<T>` for every scalar type (`view<f32>(file(1))` reads a binary model). Typed functions take and return any scalar type; unit functions return nothing.
- **Runtime library written in ling0:** float and bool printing are ordinary ling0 functions, emitted only when used.
- **Phase 1 gate:**
  - a new typed differential fuzzer (`tests/ty_fuzz.c`, with its own interpreter of the type rules) over every type, cast, promotion, unsigned/float op, typed array and typed function;
  - ill-typed programs rejected;
  - all earlier suites ported to strict typing.
- **Speed:**
  - Vigenère solver: identical instruction count to v0.6 (still faster than gcc -O3).
  - Unused-function variables no longer take frame slots (spills 85 → 30 on the solver).
  - Floats: honest numbers in `V0.7_NOTES.md`.
- See `V0.7_NOTES.md`.

## New in v0.6

- **`par k in a..b { … }`:** deterministic, race-free parallelism. Workers are forked processes with private snapshots, and results come back through `shared8/16/32/64` arrays.
- **`ncpu()`** reports the CPUs in the affinity mask.
- **Compile-time rules:** no output, outer-variable assignment, or printing calls inside a `par` body.
- **Parallel Vigenère solver** (`bench/vigenere/vigp.cock`), same algorithm and identical output, 2 CPUs, median of 15 runs:

| | ling0 `par` | gcc -O3 OpenMP | Rust `std::thread` |
|---|---:|---:|---:|
| 4,000 texts | **~455 ms** | ~625 ms | ~975 ms |

  ling0 is ~27% faster than gcc OpenMP and ~2.1× faster than Rust threads. The VM was slower during this run, so compare ratios, not absolute times with v0.5. clang is not shown because this machine has no libomp.
- Statement inlining also covers `a[i] = f(..)` and `print(f(..))`.
- See `V0.6_NOTES.md`.

## New in v0.5

- **Functions:** `fn` with scalar and array parameters (`[T]` read-only, `mut [T]` writable, by reference), recursion, calls anywhere, and defined left-to-right evaluation order.
- **Zero-cost abstraction:** non-recursive functions are inlined (expression helpers and whole statement bodies), and bounds proofs flow through them.
  - The Vigenère solver, now written with 5 helpers, keeps 67/67 checks proven.
  - It runs in **474 ms vs gcc -O3 551 ms**, clang 573 ms and Rust 780 ms (median of 15, 4,000 texts).
- **Text:** string literals, plus `write(a)`, `write(a, off, n)` and `write("..")`.
- **New examples:** `examples/hello.cock` and `examples/wordfreq.cock` (letter profile + index of coincidence of any file).
- See `V0.5_NOTES.md`.

## New in v0.4

- **Memory:** `alloc8/16/32/64`, zero-copy `file(k)` mapping, `view16/32/64`, `a[i]` loads and stores, `len(a)`.
- **Output:** buffered `print`/`putc`; output is never lost on a trap.
- **Safety and speed together:** every index is bounds-checked unless flow-sensitive range analysis proves it in range. The Vigenère solver has 67/67 checks proven, so it runs with no checks executed.
- **Periodic-index strength reduction:** `i % period` in loops becomes a wrapping counter (no division). This is the defining pattern of periodic ciphers, and gcc and clang don't do it.
- **First real computational-linguistics workload.** A complete Vigenère solver (IoC period detection, unigram initialization, quadgram delta-scored coordinate ascent), run on 4,000 held-out Gutenberg texts with byte-identical output in all four implementations:

| | ling0 | gcc -O3 -march=native | clang -O3 -march=native | rustc -O3 native |
|---|---:|---:|---:|---:|
| Vigenère, 4,000 texts (median of 21) | **487 ms** | 545 ms | 573 ms | 764 ms |

That is ~11% faster than gcc, ~15% faster than clang and ~36% faster than Rust, while being memory-safe. Accuracy: 92.6% of keys decrypt correctly. Hardware: a shared 2-vCPU VM (±5–10% noise). This is one workload, not a general claim.

See `V0.4_NOTES.md` for details, bugs found and fixed, and evidence; `LANGUAGE.md` has the full reference.

## Run (x86-64 Linux)

```sh
make            # builds ./ling0 with -Wall -Wextra -Wpedantic -Werror
./ling0 examples/argc.cock ./program && ./program a b
make test       # regressions + C oracles + control-flow fuzz + div-by-const
make fuzz       # 16,000-program control-flow campaign
make runtime    # ling0 vs clang/gcc/rustc (needs all three)
make vigenere CORPUS=/path/to/gutenberg   # Vigenère solver benchmark
```

## Evidence (tested in this environment)

**Environment:** Intel Xeon @ 2.10 GHz, 2 vCPU VM, Linux 6.18, gcc 13.3, clang 18.1, rustc 1.97.

**Tests:**
- `make test` passes: the original v0.2 regressions plus new ones.
- `tests/run_cf_fuzz.sh`: random structured programs checked against an **independent tree interpreter**. The generator mirrors the compiler's folding rules, so it never emits a program the compiler is required to reject.
  - The expected value is the result, or `TRAP` (exit status 136 required).
  - "Pressure" mode keeps 12–40 mutable variables live across every loop.
  - Final build: `make fuzz` gave 48,000/48,000 runs (16,000 programs, 6,391 checked traps) with 0 failures.
- `tests/run_divconst.sh`: 1,089 divisors (all |d| ≤ 300, 2^k and 2^k±1, boundaries, 200 random), each against 11 boundary dividends plus 20,000 runtime dividends in 3 sign classes (about 65M checks), matching C.
- ASan+UBSan build of the compiler is clean over the fuzz suites.
- 3,000 byte- and token-mutated sources produced 0 crashes, only clean diagnostics.

**Runtime.** Same algorithm and semantics; outputs verified identical; median of 11 interleaved runs (`bench/runtime/`):

| kernel | ling0 | gcc -O3 -march=native | clang -O3 -march=native | rustc -O3 native |
|---|---:|---:|---:|---:|
| `ngram29` rolling 29-ary 5-gram index | 1090 ms | 1088 ms | 1164 ms | 1154 ms |
| `vigenere29` periodic-key mod-29 transform | 671 ms | 600 ms | 922 ms | 910 ms |

- **Scope:** arithmetic-only kernels; there is no memory access yet, so no real model-table lookups.
- **Result:**
  - ngram29: ling0 is at parity with gcc and about 6% faster than clang and Rust.
  - vigenere29: ling0 is about 27% faster than clang and Rust, but **gcc is about 11% faster than ling0**. A likely cause is that gcc proves `i ≥ 0` for the loop counter and drops the sign fix-up on `i % 7` (limitation #5) [hypothesis].
- **Noise:** this is a shared VM with spreads of ±5–10%.
- These two kernels don't support any general claim about speed versus C or Rust.

## Not yet

- Functions and calls
- Memory, pointers and slices
- I/O beyond print-and-exit
- Relocatable objects and a linker
- SIMD

See `KNOWN_LIMITATIONS.md` and `SELF_HOSTING.md` (next gate: G2).

## Map

| Path | Contents |
|---|---|
| `ling0.c` | the compiler (v0.3) |
| `bootstrap/ling0_s0.c`, `bootstrap/ling0_s1.c` | v0.1 and v0.2.1 snapshots |
| `LANGUAGE.md` | implemented language |
| `LANGUAGE_SPEC.md` | linguistics design proposal |
| `tests/` | `differential.c`, `dag_fuzz.c` (straight-line), `cf_fuzz.c` (control flow + interpreter), `divconst_gen.c` |
| `bench/code_size.sh`, `bench/runtime/` | benchmarks |
| `OPUS_REVIEW.md`, `V0.3_NOTES.md` | review and change notes for integration |
