# Benchmarks

## Method

- Programs: `bench/game/*.{cock,c,rs}` implement the same algorithm, line for line, in skite, C
  and Rust; a run is rejected unless all four binaries print byte-identical output.
- Compilers: gcc 13.3 and clang 18.1 with `-O3 -march=native`; rustc 1.97 with
  `-C opt-level=3 -C target-cpu=native -C codegen-units=1 -C panic=abort`.
- Timing: `bench/game/run.py` interleaves the four binaries and reports the median wall time.
- Machine: Intel Xeon (Cascade Lake, AVX-512, one 512-bit FMA unit) @ 2.8 GHz, 4 vCPUs, shared VM;
  expect a few percent of noise.
- gcc and clang contract `a*b+c` into FMA by default; skite never does (strict IEEE semantics).

## Results (in progress)

`python3 bench/game/run.py 3 --quick`, milliseconds:

| benchmark | arg | skite | gcc | clang | rust | skite vs best |
|---|---:|---:|---:|---:|---:|---|
| mandelbrot | 4000 | **373** | 1512 | 1469 | 1540 | **3.9x faster** |
| spectralnorm | 3000 | 273 | **245** | 457 | 612 | 1.11x slower |
| nbody | 5000000 | 642 | 327 | 315 | **283** | 2.3x slower |
| fannkuchredux | 11 | 3092 | 2663 | 2974 | **2571** | 1.2x slower |
| fasta | 2500000 | 504 | 399 | 345 | **339** | 1.5x slower |
| binarytrees | 19 | 924 | **351** | 633 | 666 | 2.6x slower |
