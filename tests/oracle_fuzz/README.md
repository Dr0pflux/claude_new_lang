# Oracle differential fuzzers

Each script accepts `NEW_COMPILER OLD_COMPILER N SEED` and generates deterministic programs from `SEED`. A successful run exits 0 only when all generated programs agree. Any output/status mismatch exits 1; compiler, timeout, missing-output, or unexpected runtime failures exit 2. The generated source and temporary artifact directory are printed on failures and retained for inspection.

Compile and execution subprocess trees are bounded by default to 10 and 2 seconds; a timeout kills the whole process group, including descendants. Set `SKITE_ORACLE_COMPILE_TIMEOUT` or `SKITE_ORACLE_RUN_TIMEOUT` to finite positive seconds to adjust those limits. Matching program exits caused by SIGILL or SIGFPE are treated as valid outcomes and compared between compilers; other nonzero runtime exits are harness errors.

Run the deterministic policy tests with:

```sh
python3 tests/oracle_fuzz/test_harnesses.py
```

The tests inject fake compilers to cover agreement, mismatch, compile failure, missing output, compile timeout, execution timeout, descendant cleanup after compile and runtime timeouts, invalid timeout values, unexpected runtime failure, and matching SIGFPE status for every harness.
