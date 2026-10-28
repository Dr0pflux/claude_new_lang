# Differential fuzzers for the AST optimization passes

Each script generates random programs aimed at one pass, compiles them with the compiler under
test and with an independent oracle compiler, and compares exit status and output (including
traps). The default oracle is the bootstrap seed, which predates all of these passes.

```bash
python3 tests/oracle_fuzz/bvfuzz2.py ./skite bootstrap/skite-seed 300 1
```

Arguments: compiler, oracle, number of programs, seed. Mismatching programs are kept in the
temporary directory printed on failure.

| script | pass |
|---|---|
| `bvfuzz.py` | bounds versioning, one induction variable, constant and variable offsets |
| `bvfuzz2.py` | bounds versioning over `i < n && j < m` and counters |
| `selfuzz.py` | select stores and multi-assignment if-conversion |
| `lhfuzz.py` | invariant-load hoisting with aliased array arguments |
| `rotfuzz.py` | rotate idiom and in-place updates |

Programs use `while` loops only, because the seed predates `for`. The seed is an old compiler;
investigate every mismatch against the source semantics before blaming either side.
