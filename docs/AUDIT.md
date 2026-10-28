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
- Paired quotient/remainder commoning stops at short-circuit `&&` and `||` nodes,
  keeping division traps inside the branch where the source evaluates them.
  `tests/divmod_pair.py` covers skipped and evaluated branches, cross-branch matches,
  signed overflow, and unconditional signed/unsigned pairs.
- PR #10 removes redundant initialization before full analysis-state copies.
  Independent review, clean bootstrap, byte-identical self-hosting fixed point,
  regressions and fuzz smoke tests passed on its exact head. Additional control-flow
  and constant-divisor oracles passed in [CI](https://github.com/Dr0pflux/skite.ck/actions/runs/40690963952).
  All six Game executables and the unchanged compiler source compiled byte-identically
  with the baseline and optimized compilers. See [BENCHMARKS.md](BENCHMARKS.md).

Claude's genuine ledger cross-audit found no defects in merged PRs #1/#2/#4/#5/#6/#8.
Codex independently reviewed `e872829` and `027a8d9`. PR #10 received independent
Luna and parent Codex review; Claude subsequently cross-audited PRs #10–#13
with no defects found (ledger comment6475114698). PR #15 also received a genuine
Claude review; exact verdicts and conditions are recorded in its PR and the ledger.

The subsequent analysis-copy index reuse has the same copy/access order and
passed independent static review and generated-binary equivalence checks for all
six Game programs and the unchanged compiler source. Its measured benefit is a
3,316-byte smaller compiler executable; compile-time samples show no reliable
speed gain. Exact integration/CI status is recorded in the ledger.

General compound-assignment index-snapshot elision has independent parser review,
fixed expected-output/status probes for evaluation/trap order, and 50 additional
integer differential cases (13 expected traps, no mismatch). All six Game outputs
match. Measured benefit is smaller nbody code, with a 24-byte compiler-size cost;
no runtime-speed claim is made. Exact-head build/CI evidence is kept in the ledger.

## Float-literal rounding (issue #14)

Issue #14 has a reproducer where a decimal literal used directly as `f32` rounds to
the lower binary32 value after an intermediate binary64 rounding, while its exact
decimal value lies above the binary32 midpoint. The parser now
rounds direct `f32`-context literals once from decimal to binary32. Literals defaulting
to `f64`, including explicit `literal as f32` narrowing, retain their staged behavior.
The implementation adds about 8.5 MiB of virtual metadata mappings; RSS impact is unknown,
and it is not a performance optimization. `tests/f32_literals.py` checks 20 cases against exact Fraction rounding of the emitted
decimal text, including midpoint parity, subnormal/normal and overflow boundaries,
constant aliases, signed zero and explicit narrowing controls. The old compiler fails
the above-midpoint case. Exact-head build, review and CI evidence is recorded in the ledger.

## Open findings

1. [Issue #9](https://github.com/Dr0pflux/skite.ck/issues/9) is resolved: Claude
   reproduced the mixed-width alias hazard natively, rejected same-leader mixed widths
   and added runtime parameter guards. Codex/Luna scoped review and integrated CI
   passed afterward; the issue records exact evidence and the post-integration review
   ordering. Broader newer vectorizer changes still need independent audits; views
   do not grant general noalias assumptions.
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
