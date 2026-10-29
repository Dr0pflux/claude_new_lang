# Complementary-shift addition diagnostic

Code commit: `130a914da42aec54d63c81026b8ffce9037f082f`, tree
`1d21be07ff6890ff3b46de674cb9bae22628e0fa` (identical to local tested `05b4197`).
The exact base commit, compiler/source/executable hashes, CPU flags, affinity,
arguments and raw timing samples are in [results.json](results.json).

The existing rotate recognizer already handled OR/XOR. It now also handles
wrapping ADD of complementary logical shifts of the identical pure 64-bit
operand. Both shift counts must be positive constants summing to64. The two
halves occupy disjoint bits, so addition has no carries and equals OR exactly.
Arithmetic right shifts, differing operands, impure expressions and narrowing
operations do not gain new permissions. No floating-point behavior changes.

| Metric | Before | After | GCC control |
| --- | ---: | ---: | ---: |
| Median ms | 96.722 | 62.973 | 66.379 |
| First/third quartile ms | 95.128 / 98.731 | 61.765 / 63.999 | 65.755 / 71.129 |
| Kernel machine-code bytes | 368 | 358 | See ELF in JSON |
| Compiler ELF bytes | 1,796,096 | 1,796,096 | N/A |

Eleven randomized interleaved runs on AMD EPYC9V74, pinned to the first allowed
CPU. The matched loop executes100million iterations of wrapping rotate-add/XOR.
Median before/after time falls34.9%; code shrinks10bytes. Checksums agree with GCC
for argc1,2,4. GCC uses `-O3 -march=native -ffp-contract=off`. Clang and Rust
were unavailable; no best-compiler or universal performance claim follows.
All six existing Game executables are byte-identical before/after, so this
change establishes no Game speed gain.

```sh
python3 bench/rotate_add/run.py --before /path/to/before --after /path/to/after \
  --before-source /path/to/before.ck --before-sha BASE_COMMIT \
  --after-sha 130a914da42aec54d63c81026b8ffce9037f082f \
  --output /tmp/rotate-add-results.json
```

`tests/rotate_add.py` checks9,096 outputs against independent bit arithmetic,
all63complementary counts, signed/unsigned inputs, reversed operands, compound
pure operands,0/64/noncomplementary counts, arithmetic right shift, calls with
side effects, differing operands and explicit narrowing. Five ADD/OR pairs
must compile byte-identically. The existing rotate differential fuzzer also
passes100programs/seed44, with15generated binaries changed and no mismatches.
The self-hosted candidate reproduces itself byte for byte.

Local clean tests pass through stream boundaries but fail at the mandatory
runtime-length supervisor because this host denies ptrace. CI must pass that
supervisor and the full length suite before integration. Genuine Claude review
is queued for Saturday October31; available-agent exact-head review is separate.
