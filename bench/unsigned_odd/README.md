# Unsigned odd-constant division and remainder

Before: `a71c907b52f3416087471c987a75b82536c146f6`.
Code: `5801e6369ac0f94c5cd69437023ea89c0aaa1ee6`, tree
`84a1dd5c45863e40b255f18143b8fcdfbdb767c5`, equivalent to local tested `75755c1`.
Exact source/compiler/kernel hashes, CPU flags, affinity, arguments and samples:
[results.json](results.json).

For odd1<d<2^63, M=ceil(2^64/d). Unsigned mulhi(n,M) estimates floor(n/d)
exactly or one too high: its real-valued error is nonnegative and below one.
Compute tentative r=n-q*d modulo2^64. A correct estimate gives r<d; an
overestimate gives r=2^64-t with1<=t<d, hence r>d because d<2^63.
Subtract one from q or add d to r exactly when the unsigned comparison detects
this case. For d>=2^63, quotient is simply n>=d and remainder conditionally
subtracts d. Previous zero, even/power-of-two, signed and runtime-divisor paths
remain unchanged. The emitter uses reserved RAX/RCX/RDX scratch registers.

| Metric | Before | After | GCC control |
| --- | ---: | ---: | ---: |
| Median ms | 317.532 | 205.636 | 245.889 |
| First/third quartile ms | 303.915 / 325.184 | 194.560 / 222.339 | 238.118 / 249.936 |
| Kernel machine-code bytes | 400 | 399 | See ELF record |
| Compiler ELF bytes | 1,793,792 | 1,795,072 | N/A |

Eleven randomized interleaved runs pinned on AMD EPYC9V74. The matched C/Skite
loop is a50million-iteration dependent modulo29 recurrence. Median runtime
falls35.2%; compiler grows1,280B. GCC uses `-O3 -march=native -ffp-contract=off`;
outputs agree for argc1,2,4. This local diagnostic measures below the GCC
control; Clang/Rust are unavailable, and no general superiority claim follows.
All six Game executables are byte-identical before/after; no Game gain measured.

```sh
python3 bench/unsigned_odd/run.py --before /path/to/before --after /path/to/after \
  --before-source /path/to/before.ck \
  --before-sha a71c907b52f3416087471c987a75b82536c146f6 \
  --after-sha 5801e6369ac0f94c5cd69437023ea89c0aaa1ee6 \
  --output /tmp/unsigned-odd-results.json
```

The expanded `tests/unsigned_even.py` now checks52,818 outputs over190divisors,
normal/scalar: small odd constants, high-bit/max divisors, multiple boundaries,
deterministic random inputs, in-place/nested expressions and effectful dividends.
The historical filename is retained for compatibility. Existing C divisor oracle
passes137programs/1,089divisors; candidate fixed point passes. Local clean tests
pass earlier gates then fail the mandatory runtime supervisor because ptrace is
denied on this host. CI must pass that gate and all remaining checks. Independent
exact-head review and genuine ClaudeSaturday cross-review are separate statuses.
