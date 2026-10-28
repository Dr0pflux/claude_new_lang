#!/usr/bin/env bash
# usage: tests/run_dag_fuzz.sh [CASES] [SEED]
set -euo pipefail
cd "$(dirname "$0")/.."; N=${1:-300}; SEED=${2:-1}; D=tests
T=$(mktemp -d)
source tests/fuzz_helpers.sh
cc -O2 -o "$T/gen" -std=c11 -Wall -Wextra -Werror "$D/dag_fuzz.c"; "$T/gen" "$T" "$N" "$SEED"
pass=0; spills=0
for src in "$T"/f*.ck; do
  if ! fuzz_compile; then exit 1; fi
  grep -qE ' [1-9][0-9]* spills' "$T/log" && spills=$((spills+1))
  mapfile -t exp < "${src%.ck}.exp"
  args=()
  for x in 0 1 2 3; do
    rc=0; fuzz_run "${args[@]}" > "$T/got" || rc=$?
    got=$(cat "$T/got")
    if [[ $rc -ne 0 ]]; then echo "UNEXPECTED rc=$rc $src"; cat "$src"; exit 1; fi
    if [[ "$got" != "${exp[$x]}" ]]; then echo "MISMATCH $src argc=$((x+1)) want=${exp[$x]} got=$got"; cat "$src"; exit 1; fi
    pass=$((pass+1)); args+=(a)
  done
done
echo "PASS $pass comparisons, $spills/$N programs spilled"
