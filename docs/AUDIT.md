# Compiler audit and validation status

Updated 2026-10-28. Verified integration: `c4837cf83e284b588b30daaaa2d66824fffc4e8f`
(PR #10); its tree matches tested head `5e86b4b06154452e3d517de4dabf828bffe96a6c`.
The [team ledger](https://github.com/Dr0pflux/skite.ck/issues/3) records newer work.

## Integrated fixes and evidence

- PR #1 fixes allocation/view strides for struct widths of 16 bytes and above.
- PR #2 rejects views of structs containing bool fields, preventing invalid bool
  representations; it also adds propagated-zero division/remainder regressions and CI.
- PR #5 bounds fuzz compilation/execution, retains failure artifacts and fixes
  false passes. Injected-hang tests cover the harnesses.
- PR #6 makes the Game runner reject failed/timed-out executions and invalid
  selections; optional compiler availability is reported explicitly.
- PR #8 aligns owned scoped buffers to 64 bytes. Allocation regressions and a
  local debugger probe verified alignment; borrowed buffers keep their original alignment.
- `e872829` reuses dominating bounds checks and avoids saving registers that die
  at calls. `027a8d9` adds integer tail-recursion accumulation and copy coalescing.
  Clean suites and targeted call/order/wrapping regressions passed.
- PR #10 removes redundant initialization before full analysis-state copies.
  Independent review, clean bootstrap, byte-identical self-hosting fixed point,
  regressions and fuzz smoke tests passed on its exact head. Additional control-flow
  and constant-divisor oracles passed in [CI](https://github.com/Dr0pflux/skite.ck/actions/runs/40690963952).
  All six Game executables and the unchanged compiler source compiled byte-identically
  with the baseline and optimized compilers. See [BENCHMARKS.md](BENCHMARKS.md).

Claude's genuine ledger cross-audit found no defects in merged PRs #1/#2/#4/#5/#6/#8.
Codex independently reviewed `e872829` and `027a8d9`. PR #10 received independent
Luna and parent Codex review; Claude review remains pending after its CLI-reported
2026-10-28 11:40 a.m. America/Chicago reset. Do not describe pending review as approval.

## Open findings

1. [Issue #9](https://github.com/Dr0pflux/skite.ck/issues/9) tracks mixed-width
   overlapping views accepted by the WIP stream vectorizer. Native AVX-512
   differential execution and a verified fix remain pending. Parameter aliasing
   is also an outstanding dependence-analysis concern; do not assume noalias for views.
2. The Codex Ryzen host has AVX2 but lacks AVX-512 and ARM. A vector plan plus
   passing scalar fallback does not validate vector execution. Claude reported
   native AVX-512 coverage on its Xeon; identify the exact head/cases covered.
3. CI exists, but workflow presence alone does not enforce branch protection.
   Current protection requirements have not been independently verified.
4. Independent oracles and fixed points are bounded evidence, not an exhaustive
   proof of optimizer correctness. Keep reproductions with fixes and performance
   changes small enough to review independently.

## Before integration

Follow [TEAM_HANDOFF.md](TEAM_HANDOFF.md). Freeze compiler binaries during tests;
run a clean build, fixed point and relevant regressions, require successful CI,
and merge only the reviewed head after checking newer remote changes. Division
changes additionally require `tests/run_divconst.sh`. Record actual tests, SHA,
hardware limits and provider verdicts. Update the README, relevant reference docs
and changelog when behavior, supported features or verified performance changes.
