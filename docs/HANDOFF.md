# Claude handoff: state, open work, next steps

Read this with [TEAM_HANDOFF.md](TEAM_HANDOFF.md) (protocol) and the ledger issue
(https://github.com/Dr0pflux/skite.ck/issues/3, live state). Updated 2026-10-28 11:55 UTC.

## Integration branch

`claude/optimize-benchmark-gcc-clang-dyjp4k` at `eb6b2a7`: PRs #1, #2, #4, #5, #6, #8 plus the
`for` / `loop` / `const` / `0b` / `0o` front-end sugar (merge `4d2e3fc`). Gate run on `eb6b2a7`:
build from `bootstrap/skite-seed`, stage B == stage C (fixed point), `make test` (18 s on an idle
4-vCPU host), `bench/game/run.py 1 --quick` with all outputs identical to C.

`for`, `loop` and `const` are reserved words now: never use them as identifiers in `skite.ck`.

### Verify before and after any change

```bash
./bootstrap/skite-seed skite.ck /tmp/A && /tmp/A skite.ck /tmp/B && /tmp/B skite.ck /tmp/C && cmp /tmp/B /tmp/C
```

```bash
make clean && make test
```

```bash
python3 bench/game/run.py 1 --quick
```

Run fuzzers against a frozen copy (`cp skite /tmp/frozen; SKITE=/tmp/frozen ./tests/run_cf_fuzz.sh ...`)
so a rebuild never races a running test.

### Quick-size results at `eb6b2a7` (Xeon 2.1 GHz, AVX-512, idle, median of 3, ms)

| benchmark | skite | gcc | clang | rust | skite vs best |
|---|---|---|---|---|---|
| nbody 5000000 | 404 | 289 | 297 | 268 | 1.51x slower (rust) |
| spectralnorm 3000 | 274 | 266 | 551 | 549 | 1.03x slower (gcc) |
| mandelbrot 4000 | 318 | 1200 | 1200 | 1256 | 3.78x faster |
| fannkuchredux 11 | 2943 | 2833 | 3232 | 2812 | 1.05x slower (rust) |
| fasta 2500000 | 380 | 403 | 389 | 408 | 1.02x faster |
| binarytrees 19 | 971 | 383 | 820 | 968 | 2.53x slower (gcc) |

Timings on a loaded host are meaningless; compare ratios from one run on an idle machine.

## Cross-audit of outside PRs (Claude, against the merged diffs)

- #1 `lg()` for struct widths >= 16: correct (old code returned 3 for 16/32/64-byte elements).
- #2 reject `view<S>` when `S` has a `bool` field: correct, a needed soundness fix.
- #4 handoff docs: no code.
- #5 bounded fuzzing (`tests/fuzz_helpers.sh`, per-input timeouts, artifacts): correct.
- #6 Game runner rejects failed/timed-out runs and bad selections: correct.
- #8 scoped arena buffers aligned to 64: correct (`rcx = (ARENA_TOP + 63) & -64`, zeroing and
  `ARENA_TOP` update use the aligned base; at most 63 extra bytes per scoped allocation).

## Known problems (not fixed on the integration branch)

1. **Vectorizer aliasing through parameters.** Leaders (`arr_leader`) group arrays that share a
   base variable, so two parameters of a non-inlined function are "different" even when called
   as `f(x, x)`. A PRE load `a[i - 1]` plus a POST store `b[i]` would then read stale lanes.
   Not yet reachable in practice (needs proven bounds in a non-inlined function); becomes
   reachable once bounds guards land. Codex has a reject-based prototype (ledger 08:18);
   `wip/claude-vector-stream` instead compares base pointers at run time outside `main`.
2. **No element-wise / reduction vectorization.** `plan_loop` only vectorizes loops whose PRE
   contains an inner loop (`VK_LOOPS > 0`); plain `b[i] = b[i] * k + a[i]`, fills, copies and
   integer reductions (`s += a[i]`) stay scalar (gcc is about 2x faster on such loops).
3. binarytrees repeats the bounds check of `rgt[t]` after the recursive call
   (`wip/claude-calls-binarytrees` has a fix).

## WIP branches (pushed; none of them gated, all need review + the gate above)

| branch | base | what | state / next step |
|---|---|---|---|
| `wip/claude-vector-stream` | 4d2e3fc | bounds guards for unproven `a[i+c]` loads, runtime alias guards, stream loops (element-wise stores + integer reductions) | planner written; **codegen missing** (`gen_vloop` must handle `vp_stream`: alias guards before the loop, hoisted bounds guards, reduction init / horizontal reduce, vector stores, `i += L`). Do not build for use until done. |
| `wip/claude-calls-binarytrees` | 154cccc | dominating bounds check reuse (`lft[t]` proof covers `rgt[t]`), call overhead | first increment passed selfcheck, run.sh, cf fuzz (func mode); finish gate, measure |
| `wip/claude-nbody-slp` | 154cccc | packed codegen for the unrolled nbody step (field cells in registers, xyz in 3-lane ymm, scalar sqrt/div in order) | design only + 30 lines; target ~200 ms |
| `wip/claude-scalar-int-fannkuch` | 154cccc | scalar integer codegen for fannkuch/fasta | unfinished, unknown quality |
| `wip/claude-memory-idioms` | 979317a | addressing modes, displacement folding, fill/copy idioms | unfinished |
| `wip/claude-tail-calls` | 979317a | self tail calls to jumps, leaf frames; `tests/tc_fuzz.py` | unfinished |
| `wip/claude-compile-speed` | 979317a | range analysis (`as_stmt`, 83% of compile time) env copy/join | unfinished |
| `wip/claude-vector-codegen` | 154cccc | AVX-512 codegen quality; `proto/markstein.py` checks an FMA reciprocal-refinement idea for spectralnorm | experimental; any reciprocal trick needs a proof of correct rounding for every input |
| `wip/claude-more-benchmarks` | 154cccc | adds revcomp, knucleotide, nsieve, pidigits (skite/C/Rust) + run.py | committed by its agent; needs a merge with the new run.py |
| `wip/claude-fast-tests` | 979317a | parallel test runner (`tests/par.sh`, `tests/quick.sh`) | conflicts with #5 fuzz scripts; rebase |
| `wip/claude-encoder-audit` | 979317a | objdump cross-check of emitted code (`tests/enc_*`) | unfinished |
| `wip/claude-float-diff-fuzz` | 979317a | float differential fuzzer vs C (`tests/flt_diff.py`), parser touches | unfinished; review the parser changes |
| `wip/claude-int-diff-fuzz` | 979317a | integer differential fuzzer vs C (`tests/int_diff_gen.py`) | generator only |
| `wip/claude-simplify-audit` | 979317a | const-prop/unroll fuzzer (`tests/simp_fuzz.py`) | generator only |
| `wip/claude-robustness-fuzz` | 979317a | malformed-input fuzzer (`tests/robust_fuzz.py`) | unfinished |
| `wip/claude-inliner-audit` | 979317a | call/inliner fuzzer (`tests/call_fuzz.py`) | unfinished |

## Lessons

- Twenty concurrent agents exhausted a 5-hour quota in about 40 minutes and made every timing
  useless. Run at most a few agents; timings only on an idle machine.
- Build every candidate from the seed and check B == C; never test with a compiler built by an
  unverified compiler. Never let a fuzzer run `./skite` while it is being rebuilt.
- An earlier "dead after call" save elision miscompiled because it ignored array base/length
  variables still live after the call; liveness must include `basev`/`lenv`.

## Priorities

1. Finish `wip/claude-vector-stream` codegen + tests (vector vs `--scalar`, alias, guards, n = 0..20).
2. binarytrees (2.5x): check reuse, call/return overhead, recursion unrolling.
3. nbody (1.5x): `wip/claude-nbody-slp`.
4. fannkuchredux, spectralnorm (within 5%).
