# Runtime-length predecessor proof

This is a focused compiler proof/code-size experiment, not a claim of beating the best C/Rust implementation.

## Tested source

- Before commit: `690f3b570cd048f816e1c42c091285899376caef`.
- After code commit: `57310f01562f81b54b57a2c619cfface71fee5e1`.
- Source SHA-256 before: `706f861843cc569f07b5c624da567df6deb5c3adb43f215701cfceef163728d0`.
- Source SHA-256 after: `5d2e9b97606f12d3ddcdf0bdbb264aaf8551746aefa84f9736691e5db3dca7e7`.
- Both compilers were independently bootstrapped seed -> A -> B -> C, with B == C. The clean after build is byte-identical to the frozen compiler used here.

## Result

| Workload | Before | After | Interpretation |
| --- | ---: | ---: | --- |
| Adjacent-window accumulator | 2/3 checks proven; 571 code bytes | 3/3 proven; 559 bytes | One hot-loop check removed, 12-byte code reduction |
| Prefix sums | 5/6 proven; 636 code bytes | 5/6 proven; 636 bytes | Byte-identical negative control; existing carried-store optimization already handles its inner loop |
| Self-hosted compiler ELF | 1,564,234 bytes | 1,564,746 bytes | Compiler grows by 512 bytes |

Normal compilation was used. The window kernel has a loop-carried XOR/add accumulator, so both versions emit zero vector plans; no vectorizer was disabled to obtain the code-size result. The new regression suite separately tests normal and `--scalar` compilation.

Measured on Intel Xeon Platinum 8573C, Linux x86-64, pinned to allowed logical CPU 0, shared host. Eleven randomized interleaved runs; quartiles and raw observations are in results.json. The full CPU feature list, affinity, executable/source hashes, compiler versions, arguments and checked outputs are recorded there.

| Workload | Before median | After median | GCC control |
| --- | ---: | ---: | ---: |
| Window | 116.359 ms | 115.272 ms | 114.720 ms |
| Prefix sums | 214.941 ms | 216.740 ms | 217.793 ms |

**No reliable runtime improvement is established.** The window interquartile ranges overlap (before 114.341..117.621 ms, after 114.461..116.712 ms); the prefix binaries are identical despite their timing difference. The positive evidence is bounds-proof coverage and native code size. There is no all-workload or best-compiler speed claim.

The GCC control uses `-O3 -march=native -ffp-contract=off`. Clang and rustc were unavailable locally, so a three-compiler performance verdict remains pending. Outputs are byte-identical before/after/GCC for argc 1, 2 and 4, and the implementations use matched wrapping integer algorithms. No floating arithmetic is transformed.

## Reproduce

Build frozen compilers from the before and after sources, verify each fixed point, then:

```sh
python3 bench/length_facts/run.py \
  --before /path/to/before --after /path/to/after \
  --before-source /path/to/before.ck \
  --before-sha 690f3b570cd048f816e1c42c091285899376caef \
  --after-sha 57310f01562f81b54b57a2c619cfface71fee5e1 \
  --runs 11 --output /tmp/length-results.json
SKITE=/path/to/after python3 tests/length_facts.py
```

The focused test fails on the before compiler because `for i in 1..len(a)` leaves the predecessor check unproven (0/1). After the patch, all positive accesses are proven. The 842 execution cases include empty inputs, offset boundaries, narrowing across endpoints, unsigned/huge offsets, mutable indices, distinct arrays, shorter same-memory views and RHS-before-invalid-store trap order.
