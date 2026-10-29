# Guarded terminal length proof, 2026-10-29

Before: `0faaec8b74b77b5621756d382a1795064bb037e6`.
After code: `12367b40cec90dfe5777ca1859fbcb6b97f7d33c`.
The public code tree `0a7c6bd8e1b9732ff167237be6282f8c99e0f453`
matches local tested commit `8eb0692`; only commit metadata differs.

The compiler recognizes `a[len(a)-k]` for positive constant `k`, provided
the exact array length has a proven lower bound at least `k` and the index
is nonnegative. The subtraction cannot wrap. Other array lengths and views
do not supply this identity. This is a general range proof, with no cipher
recognition or benchmark changes.

| Existing kernel | Before | After |
| --- | --- | --- |
| Prefix checks elided | 5/6 | 6/6 |
| Prefix machine-code bytes | 636 | 624 |
| Prefix median ms | 217.263 | 221.270 |
| Window machine-code bytes | 559 | 559 |
| Window median ms | 67.886 | 67.238 |
| Self-hosted compiler bytes | 1,795,712 | 1,796,096 |

Eleven randomized interleaved runs pinned to the first allowed CPU on the
declared host. Timing distributions overlap; there is no runtime speedup claim.
The removed prefix check runs at final output, outside its hot loop. Window
executables are byte-identical. GCC `-O3 -march=native -ffp-contract=off`
outputs match for argc1,2,4; its prefix/window medians are216.543/64.314ms.
Clang and Rust are unavailable, so this is not a best-compiler comparison.
Exact CPU/features, raw samples, arguments, source/compiler/executable hashes,
quartiles and tool versions are in [terminal-results.json](terminal-results.json).

Reproduce using frozen compilers built from the corresponding source commits:

```sh
python3 bench/length_facts/run.py --before /path/to/before --after /path/to/after \
  --before-source /path/to/before.ck \
  --before-sha 0faaec8b74b77b5621756d382a1795064bb037e6 \
  --after-sha 12367b40cec90dfe5777ca1859fbcb6b97f7d33c \
  --runs 11 --output /tmp/terminal-results.json
```

Both frozen compiler chains reproduce themselves byte for byte. The baseline
fails the new `terminal_one` full-proof assertion (0/1); candidate proves it.
The expanded suite contains1442 normal/scalar output/trap cases, adding
guarded terminal loads/stores/parameters and empty, insufficient-guard,
distinct-array, shorter-view, mutable-copy, narrowing and huge-offset controls.
Independent review also exercised70dynamic arrays and parameter passing.

Local `make clean && make test` passes the clean build, fixed point, existing
regressions, fuzz-harness checks, control-flow/typed/vector/stream fuzzing and
120stream boundaries, then fails at the ptrace supervisor: this host denies
`PTRACE_TRACEME`. The supervisor and expanded runtime-length suite are not
skipped or counted as passing. Successful CI is an integration gate. Genuine
Claude cross-review is pending the reported weekly reset; independent
available-agent exact-head review is required separately.

CI on the initial candidate caught an invalid store fixture against a read-only file view. Independent follow-up review also caught zero-length allocation before the guard. The corrected store case allocates owned storage of the same runtime length inside the nonempty guard. All36 program shapes now pass both normal/scalar compilation and expected proof-counter gates locally (72 compilations); A separate local runner verified all520 positive output/proof cases without ptrace; the full supervised runtime/trap suite still requires CI. Compiler source and timing evidence are unchanged.
