# Project handoff: verified state and pending work

Read this with [TEAM_HANDOFF.md](TEAM_HANDOFF.md) (protocol) and the ledger issue
(https://github.com/Dr0pflux/skite.ck/issues/3, live state). Updated 2026-10-28 at `bbec29f`. Fetch the ledger and remote branches before acting.

## Current integration state (Claude, 2026-10-28)

Integration branch `claude/optimize-benchmark-gcc-clang-dyjp4k` at `bbec29f`. Codex
`codex/length-offset-facts` (below) was reviewed by Claude (correct) and integrated at `d10df4a`.
Claude commits since `7b6f7bb` await Codex cross-review, the bounds-versioning pass first:

| commit | change | evidence |
|---|---|---|
| `7b6f7bb`, `1b76773` | select stores + one-compare multi-cmov; fix compare-register overlap; refine() no longer re-annotates loads (pre-existing bounds-check loss) | `selstore.ck`, `refine_trap.ck`, oracle fuzz |
| `1b76773`, `690f3b5` | invariant-load hoisting (versioned on base equality outside main), min/max chain order | `lhoist*.ck` |
| `405dcf2` | tiny recursive bodies: 8x inline copy budget | binarytrees 524 → 454 ms |
| `40183fc`, `3a479db` | bounds-check elimination by loop versioning (`bv_*`, `vpre`, `bv_prune`); `3a479db` fixes a missing lower guard for i0 < 0 | `bversion*.ck`, `bvfuzz` |
| `eca63bf` | `rol` idiom, in-place `v = v op e(v)` | hashmix 0.97x gcc |
| `d909c71` | unroll inner loops whose start is constant arithmetic | nbody 308 → 253 ms |
| `fc587fb`..`0032372` | global counter update, `t = a[t]` into place, call args, recursive inline budget | binarytrees 1.62x → 1.26x |
| `c0cbc2d`, `eeb56a8`, `bb30279` | movsd spills; constant-bound search loops → nested ifs; in-place compares; `v = C` flags | fasta −25% instructions, editdist −3% |
| `bbec29f` | division: register divisor, direct result, out-of-line 64-bit stub; Euclid rotation | gcdsum 240 → 231 ms, `div_paths.ck` |

WIP, not integrated: `wip/claude-row-promotion` (row promotion, 10 xmm variable registers;
correct, no measured nbody gain); `wip/claude-slp-pairs` (SSE2 pairing of sqrt/div lets; correct,
slower from reorder spills). Ideas measured and dropped: matmul invariant broadcast
hoisting, straight-line store forwarding, fannkuch flip peeling (no gain on this host).

## Current local candidate: runtime-length predecessors (2026-10-28)

Branch `codex/length-offset-facts`, integration base
`690f3b570cd048f816e1c42c091285899376caef`; compiler change is code commit
`57310f01562f81b54b57a2c619cfface71fee5e1`, source SHA-256
`5d2e9b97606f12d3ddcdf0bdbb264aaf8551746aefa84f9736691e5db3dca7e7`.
It proves `a[i-k]` only with the existing array-specific length fact and
`0 <= k <= i`, and preserves identity casts. Clean build, self-hosting fixed point,
full tests and 842 focused output/trap cases passed locally. The before compiler
fails the new predecessor-proof assertion.

Measured benefit is a 12-byte window-kernel reduction and one removed bounds
check, not a reliable runtime win. The compiler grows 512 bytes; the prefix
control is byte-identical. Exact source/compiler hashes, CPU/features, GCC control,
11-run samples and missing Clang/Rust coverage are recorded in
[the measurement record](../bench/length_facts/README.md). Integration and genuine
cross-provider review remain pending; do not infer merge approval from local tests.

The current owner priorities are in [CLASSICAL_ROADMAP.md](CLASSICAL_ROADMAP.md).
The integration baseline is already self-hosted and implements masked stream
loops, max/min and byte lanes. Historical sections below describe earlier
checkpoints; use the live ledger and current README for newer feature/review state.

## Historical integration checkpoint

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

1. **Stream vectorization integrated at `979586f`** (element-wise loops, integer reductions,
   narrow element types, bounds guards, run-time alias guards). Issue #9 (mixed-width views) was
   reproduced natively on AVX-512 and fixed: same-leader mixed widths are rejected, and
   different-width parameter pairs get base-pointer guards. Regressions: `tests/stream_mixed_width.ck`,
   `tests/data/valias.ck`, `tests/data/valias_width.ck`, `tests/stream_boundaries.py`,
   `tests/stream_fuzz.py` (views + mixed-type parameters; catches the pre-fix bug). Pending:
   Codex review of `979586f` and CI; then close #9.
2. Not yet vectorized in stream loops: `if` inside the body (masked stores/reductions), max/min
   reductions, f32, loads with negative offsets of stored arrays (true dependences, by design).
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
| `wip/claude-vector-stream` | 4d2e3fc | stream loops, guards | integrated at `979586f` (fast-forward); next: masked `if` and max/min reductions. Claude owns vectorizer edits. |
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

1. Codex review of `979586f` (issue #9 fix); masked stream loops and max/min reductions.
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
