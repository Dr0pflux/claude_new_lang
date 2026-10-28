# Project handoff: verified state and pending work

Read this with [TEAM_HANDOFF.md](TEAM_HANDOFF.md) (protocol) and the ledger issue
(https://github.com/Dr0pflux/skite.ck/issues/3, live state). Updated 2026-10-28 after PR #10. Fetch the ledger and remote branches before acting.

## Integration branch

`claude/optimize-benchmark-gcc-clang-dyjp4k` at
`c4837cf83e284b588b30daaaa2d66824fffc4e8f` (PR #10). Its source tree matches reviewed,
tested head `5e86b4b06154452e3d517de4dabf828bffe96a6c`. Integrated work includes
PRs #1/#2/#4/#5/#6/#8, front-end sugar, `e872829` call/bounds reuse, `027a8d9`
integer tail-recursion/copy coalescing, and PR #10 analysis-copy initialization.

Exact PR #10 head: clean seed bootstrap, byte-identical self-hosting fixed point,
full `make test`, independent Luna/parent review and
[CI](https://github.com/Dr0pflux/skite.ck/actions/runs/40690963952) passed.
The merge tree was checked against the tested head. All six Game programs and
the unchanged compiler source compile byte-identically with baseline `027a8d9`
and the optimized compiler. Self-source compile median fell 2.520167 → 2.221176 s
on Ryzen 7 5700U (three paired runs after warmup); this is compile-time evidence,
not a generated-program runtime gain. See [BENCHMARKS.md](BENCHMARKS.md).

`for`, `loop` and `const` are reserved words now: never use them as identifiers in `skite.ck`.

### Validate compiler changes

```bash
./bootstrap/skite-seed skite.ck /tmp/A && /tmp/A skite.ck /tmp/B && /tmp/B skite.ck /tmp/C && cmp /tmp/B /tmp/C
```

```bash
make clean && make test
```

```bash
python3 bench/game/run.py 1 --quick
```

For documentation-only changes, check content/links and require CI; avoid redundant
local compiler rebuilds when source is unchanged.

Run fuzzers against a frozen copy (`cp skite /tmp/frozen; SKITE=/tmp/frozen ./tests/run_cf_fuzz.sh ...`)
so a rebuild never races a running test.

### Performance snapshots

Use [BENCHMARKS.md](BENCHMARKS.md) as the canonical measurement record. It separates
the verified `027a8d9` Ryzen quick-size results from historical Xeon measurements
and identifies the recording/measurement provenance. The older Xeon table formerly
in this handoff was a different snapshot; recover it from Git history if needed,
not by mixing its timings with the canonical tables. The Ryzen host lacks AVX-512.

## Cross-audit of outside PRs (Claude, against the merged diffs)

- #1 `lg()` for struct widths >= 16: correct (old code returned 3 for 16/32/64-byte elements).
- #2 reject `view<S>` when `S` has a `bool` field: correct, a needed soundness fix.
- #4 handoff docs: no code.
- #5 bounded fuzzing (`tests/fuzz_helpers.sh`, per-input timeouts, artifacts): correct.
- #6 Game runner rejects failed/timed-out runs and bad selections: correct.
- #8 scoped arena buffers aligned to 64: correct (`rcx = (ARENA_TOP + 63) & -64`, zeroing and
  `ARENA_TOP` update use the aligned base; at most 63 extra bytes per scoped allocation).

## Pending correctness and review

1. **Vectorizer aliasing.** Parameter leaders can differ even for `f(x, x)`.
   WIP `wip/claude-vector-stream` adds runtime base guards, but mixed-width
   overlapping views need further dependence checks even for exact `a[i]`
   accesses. [Issue #9](https://github.com/Dr0pflux/skite.ck/issues/9) contains
   a reproducer and native AVX-512 acceptance criteria. No native mismatch or fix
   has been verified on the Codex Ryzen host; scalar dispatch is insufficient.
2. **Stream/reduction extension remains WIP.** `eed833b` has codegen and reaches
   a fixed point. The test-only `codex/stream-cross-audit-tests` branch (`39137d5`)
   supplies 120 reduction/tail/wrapping oracle cases and a mixed-width fixture.
   Local scalar dispatch passes the reduction cases; native vector coverage is pending.
3. **Provider review.** Claude genuinely cross-audited merged PRs #1/#2/#4/#5/#6/#8.
   Codex reviewed `e872829` and `027a8d9`. Claude review of PR #10 is pending;
   one normal CLI request returned a cap resetting at 11:40 a.m. America/Chicago
   on 2026-10-28. Read the ledger for newer retry metadata, and retry only after capacity returns
   and the latest provider-reported retry time has passed. Do not label pending review approved.
   Separate Claude cloud sessions coordinate through the ledger, not the local CLI.

The binarytrees dominating-check reuse and recursion work are already integrated;
do not recreate them from old WIP descriptions. Owner goals beyond the implemented
features remain open in [issue #7](https://github.com/Dr0pflux/skite.ck/issues/7).

## Branch inventory (historical WIP; fetch exact heads before reuse)

| branch | base | what | state / next step |
|---|---|---|---|
| `wip/claude-vector-stream` | 4d2e3fc | bounds guards for unproven `a[i+c]` loads, runtime alias guards, stream loops (element-wise stores + integer reductions) | `eed833b`: codegen/fixed point exist; issue #9 and native tail/reduction validation remain blockers. Claude owns implementation; Codex supplies review/tests. |
| `wip/claude-calls-binarytrees` | 154cccc | dominating bounds check reuse (`lft[t]` proof covers `rgt[t]`), call overhead | Call/bounds reuse integrated at `e872829`; subsequent recursion/coalescing at `027a8d9` passed Codex review, full suite and CI. Do not duplicate. |
| `wip/claude-nbody-slp` | 154cccc | packed codegen for the unrolled nbody step (field cells in registers, xyz in 3-lane ymm, scalar sqrt/div in order) | `f45d219`: inspected unique diff adds AST diagnostics only; no SLP optimization. Excluded from performance integration. |
| `wip/claude-scalar-int-fannkuch` | 154cccc | static array placement and reversal specialization | Inspected unique diff is not a general scalar-int optimization; not selected for integration. |
| `wip/claude-memory-idioms` | 979317a | addressing modes, displacement folding, fill/copy idioms | unfinished |
| `wip/claude-tail-calls` | 979317a | self tail calls to jumps, leaf frames; `tests/tc_fuzz.py` | unfinished |
| `wip/claude-compile-speed` | 979317a | range-analysis prototypes | Only narrow immediate-copy initialization optimization ported/merged as PR #10. Hoist-index prototype rejected for no measured gain; other caching changes remain unreviewed. |
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

1. Resolve stream issue #9 and execute exact-head vector alias/tail/reduction
   checks on AVX-512 hardware. Preserve default floating/trap semantics.
2. Complete genuine Claude cross-audit of PR #10 after capacity returns.
3. Improve compiler bottlenecks in matched regular Game workloads. Latest Ryzen
   ratios versus best comparator: nbody 2.02x, binarytrees 1.86x, fannkuchredux
   1.26x, fasta 1.10x, mandelbrot 1.04x, spectralnorm 1.01x slower. These are
   quick-size measurements, not universal rankings; see [BENCHMARKS.md](BENCHMARKS.md).
4. Pursue the owner roadmap with measurable acceptance evidence: multicore,
   safe SIMD/lookup optimization, modules, exact AVX-512/NEON modular math,
   enforced owned-memory non-aliasing, SoA, bounded precomputation and host tuning.

Luna/low is the main scoped implementation worker; at most three non-overlapping
workers run concurrently, with extra tasks/checkpoints queued durably. Reject
changes without correctness evidence or a measured benefit. Update README and
relevant Markdown when implementation, measured results or open risks change.
