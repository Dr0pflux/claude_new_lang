# Unsigned even-constant division and remainder

Before: `8a10353fd674bb45ae380563963c971614205620`.
Code: `83051cb16d39549ab0615098481124f00b0a170f`, tree
`c65120b17e30569a5253f807fa208c0e20d7ee94`, equivalent to local tested `6643ad1`.
Exact source/compiler/kernel hashes, hardware flags, raw samples and arguments:
[results.json](results.json).

For any unsigned64 numerator n and positive even divisor d=2m,
`floor(n/d) = floor((n>>>1)/m)`. The shifted numerator is at most INT64_MAX;
the positive halved divisor also fits signed64. Reuse the existing signed
constant-division helper with its nonnegative premise. For remainder, retain
the original numerator and compute n-q*d. Since q*d<=n, the mathematical result
fits u64. Existing power-of-two lowering stays first; zero, odd, variable and
signed divisor paths retain their previous semantics.

| Metric | Before | After | GCC control |
| --- | ---: | ---: | ---: |
| Median ms | 333.176 | 231.250 | 197.396 |
| First/third quartile ms | 318.644 / 383.044 | 220.061 / 257.647 | 195.054 / 227.279 |
| Kernel machine-code bytes | 400 | 394 | See ELF record |
| Compiler ELF bytes | 1,796,096 | 1,793,792 | N/A |

Eleven randomized interleaved runs pinned to the first allowed CPU on AMD EPYC
9V74. The matched C/Skite diagnostic is a50million-iteration dependent unsigned
modulo26 recurrence. Median runtime falls30.6%, and the compiler shrinks2,304B.
GCC remains faster; this is not a general best-compiler claim. Outputs match
GCC `-O3 -march=native -ffp-contract=off` for argc1,2,4. Clang/Rust unavailable.
All six existing Game binaries are byte-identical before/after, so no Game gain
is established. An exploratory xorshift-plus-modulo loop was less sensitive to
the division latency; the recorded diagnostic explicitly measures a dependent
recurrence, not general cryptanalysis throughput.

```sh
python3 bench/unsigned_even/run.py --before /path/to/before --after /path/to/after \
  --before-source /path/to/before.ck \
  --before-sha 8a10353fd674bb45ae380563963c971614205620 \
  --after-sha 83051cb16d39549ab0615098481124f00b0a170f \
  --output /tmp/unsigned-even-results.json
```

`tests/unsigned_even.py` passes23,614 independent quotient/remainder outputs,
84 divisors, normal/scalar, including high-bit and maximum-even divisors,
boundary/multiple neighbors, deterministic random values, in-place/nested
operations and effectful dividends. Existing C oracle:137programs/1,089divisors
pass. Candidate self-hosting fixed point passes. The local clean full suite
passes earlier gates then fails at the mandatory supervisor because this host
denies ptrace; successful CI remains required. Independent exact-head review
and genuine Claude Saturday cross-review are separate gates/statuses.
