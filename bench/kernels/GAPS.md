# Kernel gap table: skite vs gcc/clang/rustc

Median of 3 interleaved runs (`python3 bench/kernels/run.py 3 ...`), Intel Xeon @ 2.10GHz (4 cpus, shared machine, so absolute
times are noisy), gcc 13.3 / clang 18.1 (`-O3 -march=native -ffp-contract=off`), rustc 1.97 (`opt-level=3 target-cpu=native`).
Ratio = skite / fastest other compiler (above 1 = skite slower). All four binaries print byte-identical output for every kernel.
Problem sizes carry `argc()` so the trip counts are runtime values in all three languages.

| kernel | skite ms | gcc ms | clang ms | rust ms | skite/best-other | best other |
|---|---:|---:|---:|---:|---:|---|
| prefixsum | 1005.3 | 196.8 | 195.3 | 215.9 | 5.147 | clang |
| wordcount | 338.7 | 280.9 | 72.2 | 262.6 | 4.689 | clang |
| matmul | 657.8 | 195.8 | 252.1 | 240.4 | 3.360 | gcc |
| editdist | 404.3 | 171.5 | 303.2 | 345.0 | 2.358 | gcc |
| divmod | 391.7 | 192.7 | 195.0 | 198.5 | 2.033 | gcc |
| strsearch | 309.7 | 198.3 | 173.1 | 263.9 | 1.789 | clang |
| intsort | 287.7 | 262.5 | 184.7 | 272.2 | 1.558 | clang |
| gcdsum | 271.3 | 270.3 | 217.0 | 215.3 | 1.260 | rust |
| ngramhash | 302.0 | 264.8 | 281.9 | 364.0 | 1.141 | gcc |
| hashmix | 255.2 | 242.8 | 244.2 | 226.6 | 1.126 | rust |
| histogram | 203.1 | 201.4 | 189.0 | 189.9 | 1.074 | clang |
| polyeval | 349.3 | 340.5 | 378.9 | 333.1 | 1.049 | rust |
| nqueens | 302.0 | 307.7 | 307.9 | 314.0 | 0.981 | gcc |
| sieve | 308.3 | 334.4 | 321.8 | 350.0 | 0.958 | clang |
| caseconv | 96.1 | 186.0 | 131.5 | 122.9 | 0.782 | rust |
| collatz | 195.1 | 336.8 | 272.3 | 271.9 | 0.717 | rust |

## Likely causes for the five worst (from the skite statistics line)

1. **prefixsum (5.1x)**: `0/5 bounds checks elided, 0 loops vectorized, 0 unrolled`. The array length is a runtime value, so
   `a[i] += a[i-1]` keeps a bounds check on both the load of `a[i-1]` and the load/store of `a[i]` inside a 1-cycle-latency
   loop-carried chain; gcc/clang/rust drop the checks (or hoist them) and unroll. Needs a length fact `i < len(a)` from the
   `for i in 1..n` bound when `n == len(a)` is known, plus unrolling of loop-carried recurrences.
2. **wordcount (4.7x vs clang)**: `1/2 bounds checks elided, 0 loops vectorized`. clang (72 ms vs about 260-280 for gcc/rust)
   turns the branchy word-boundary state machine into branchless / vectorized code; skite emits a compare-and-branch per byte
   with a data-dependent `inw` flag, and the `t[i]` check is not proven because `n` is runtime. gcc and rust are only about 1.1x
   faster than skite, so the gap is mostly clang's if-conversion plus SIMD.
3. **matmul (3.4x)**: `0/8 bounds checks elided, 2 xmm, 0 loops vectorized`. The i-k-j inner loop
   `c[i*n+j] += aik*b[k*n+j]` is a textbook SIMD candidate, but the flat index `i*n+j` with runtime `n` defeats the interval
   analysis (checks stay) and the f64 loop is not vectorized (only 2 xmm registers used, scalar `mulsd/addsd`); the others use
   AVX2 vector mul/add. Vectorizing f64 element-wise loops with affine multi-dimensional indices would close most of it.
4. **editdist (2.4x)**: `8 spills, 9/11 bounds checks elided, 2 loops vectorized` (the vectorized ones are the `row[j]=j` init
   and nothing in the DP). The DP inner loop has a loop-carried `diag`/`row[j-1]` dependency with three data-dependent `if`
   minimums; gcc turns them into `cmov` and keeps `up/diag/row[j-1]` in registers, while skite spills (8 spills at 10 peak
   registers) and branches, hurting on random data. Better register pressure handling and if-to-cmov for min patterns.
5. **divmod (2.0x)**: `0 modulo reduced`, 0 bounds checks. `x / k` and `x % k` with the same runtime operands are emitted as two
   `idiv`s, whereas gcc/clang/rust compute both from one `idiv` (quotient in rax, remainder in rdx). Fusing a div/mod pair with
   identical operands should roughly halve the time.

Other notes: gcdsum (1.26x) and intsort (1.56x) are also behind (the former is `idiv`-latency bound with the Euclid loop, the
latter loses to clang's branchless merge); skite is ahead on collatz, caseconv, sieve and nqueens.
