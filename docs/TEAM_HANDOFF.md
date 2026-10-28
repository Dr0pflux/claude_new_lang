# Team handoff and reset recovery

Shared ledger: https://github.com/Dr0pflux/skite.ck/issues/3
Integration branch: `claude/optimize-benchmark-gcc-clang-dyjp4k`.
The ledger and its latest comments are live state; this document is the protocol.

## Resume

1. Read the latest ledger comments and open PRs, then fetch the integration
   branch and task branch. Inspect uncommitted work before switching anything.
2. Continue the highest-priority unfinished task. Reuse its branch and PR;
   do not duplicate work already underway or completed since the checkpoint.
3. Post an explicit ownership/takeover comment before editing. A comment is not
   an atomic lock: the single coordinator must resolve competing claims before
   authorizing overlapping work. Time elapsed alone does not prove abandonment.
4. Parallelize reproduction, oracle tests, profiling and review. One implementer
   owns overlapping `skite.ck` edits. Default to one implementer plus at most two
   bounded reviewers; all subagents report results to the coordinator for saving.

## Checkpoint before stopping

Record task ID and state (active, quota-paused, blocked, review, complete),
provider and role, branch, base/head SHA, files edited, completed work, tests
actually run and their results, blockers, next exact command, and any
provider-reported reset/retry time with timezone. Push partial work on the task
branch when possible. Never push broken partial work to the integration branch.
Persist a local checkpoint if remote publication fails; sync it before takeover.

Usage resets restore capacity, not shared memory. The next team reconstructs
state from the ledger and Git history. Stop a capped provider, record its retry
time, and leave the work available for an explicit handoff. Do not poll a capped
provider before its known reset or retry it in a tight loop. Each resumed
provider may continue the other team's work after checking for newer changes.

## Automated coordinator

A recurring wakeup in the owner's Codex chat checks every thirty minutes,
including :10 and :40 past the hour. It runs only when the app, computer and
account capacity permit. It uses the latest ledger, checks Codex usage, and may
invoke the installed Claude CLI for one bounded task when Claude is available.
A new CLI session uses the shared checkpoint; resuming an unrelated private
cloud session is not assumed. Record provider failures once and preserve work.
Already-running Claude sessions must fetch this protocol or receive the ledger
link. This repository file does not itself install a scheduler on their hosts.

## Validate and integrate

Follow docs/AUDIT.md. Every change needs a reproducer or relevant oracle check.
Run `make clean && make test`; run the constant-divisor oracle for division
changes. Record the exact tested SHA and any hardware coverage gap. Review
changes independently, require passing CI, and merge only the tested head.
Performance changes require matching outputs, before/after SHAs, CPU features,
arguments, repeated timings and medians. Preserve traps and floating semantics.

Stay quiet on unchanged quota waits. Notify the owner for merged improvements,
new failures, or an action only they can take. Update the ledger on real state
changes rather than posting duplicate status comments.
