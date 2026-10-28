# Agent audit handoff

Audited 2026-10-28 at merge ff44dc6 (PR #1).

## Confirmed results

- Git object integrity and whitespace checks passed.
- Clean `make test` passed before and after the struct fix merged.
- The struct-size regression fails on 979317a and passes after PR #1.
- Control-flow seed 23: 300 runs passed, including 119 expected traps.
- Constant-divisor oracle: 137 programs / 1,089 divisors passed.

## Confirmed bug fixed in this PR

`view<Flag>(bytes)` accepted a struct with a `bool` field even though direct
`view<bool>` was rejected. A byte value of 2 made the field truthy but unequal
to `true`. Struct views containing bool fields now receive a compile diagnostic;
regressions cover one-byte and mixed sixteen-byte layouts. Normal struct
allocation remains supported.

## Open findings

1. Both remote branches were unprotected and no CI checks existed at audit time.
   This PR adds CI; after its first successful run, require the
   `Build and regression tests` check and pull requests on the default branch.
   Adding the workflow alone does not enforce branch protection.
2. Recent optimization commits bundle independent changes and sometimes lack
   focused regressions. Add a deterministic reproducer with each compiler fix.
   This PR covers propagated-zero division/remainder for signed and unsigned
   values, including unused results, with compile and execution timeouts.
3. The control-flow, typed and vector fuzz harnesses do not bound compilation
   time per input. CI has a job timeout; per-input limits remain follow-up work.
4. Hosted CI may exercise the scalar fallback on CPUs without AVX-512. Keep
   vector-capable validation for changes to vector code generation.

## Coordination with Claude

Use a separate branch per agent and PRs into the integration branch. Fetch the
latest integration tip before starting or updating a change. Keep unrelated
optimizations separate so failures can be bisected and reverted independently.
Do not force-push shared branches or overwrite another agent's commits.

For each PR, record the base and tested commit, behavior changed, reproducer,
commands run and results. Run `make clean && make test`; changes to division
lowering should also run `./tests/run_divconst.sh`, and control-flow changes
should exercise the seed that exposed the bug. A self-hosting fixed point is
necessary but does not replace regression tests and independent oracles.

Review audit findings in this PR and link follow-up fixes back to the finding.
