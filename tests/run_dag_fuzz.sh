#!/usr/bin/env bash
# usage: tests/run_dag_fuzz.sh [CASES] [SEED]
set -euo pipefail
cd "$(dirname "$0")/.."; L=./ling0; N=${1:-300}; SEED=${2:-1}; D=tests
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cc -O2 -o "$T/gen" -std=c11 -Wall -Wextra -Werror "$D/dag_fuzz.c"; "$T/gen" "$T" "$N" "$SEED"
pass=0; spills=0
for src in "$T"/f*.cock; do
  "$L" "$src" "$T/p" > "$T/log" 2>&1 || { echo "COMPILE FAIL $src"; cat "$T/log"; cat "$src"; exit 1; }
  grep -qE ' [1-9][0-9]* spills' "$T/log" && spills=$((spills+1))
  mapfile -t exp < "${src%.cock}.exp"
  args=()
  for x in 0 1 2 3; do
    got=$("$T/p" "${args[@]}" 2>&1) || true
    if [[ "$got" != "${exp[$x]}" ]]; then echo "MISMATCH $src argc=$((x+1)) want=${exp[$x]} got=$got"; cat "$src"; exit 1; fi
    pass=$((pass+1)); args+=(a)
  done
done
echo "PASS $pass comparisons, $spills/$N programs spilled"
