#!/usr/bin/env bash
# Phase 1 (types) gate: random typed programs vs an independent interpreter.
# usage: tests/run_ty_fuzz.sh [CASES] [SEED]
set -euo pipefail
cd "$(dirname "$0")/.."
N=${1:-300}; SEED=${2:-1}
T=$(mktemp -d)
source tests/fuzz_helpers.sh
cc -std=c11 -O2 -Wall -Wextra -Werror -fno-math-errno tests/ty_fuzz.c -o "$T/gen"
"$T/gen" "$T" "$N" "$SEED"
pass=0
for src in "$T"/t*.ck; do
  b=${src%.ck}
  if ! fuzz_compile; then exit 1; fi
  rc=0; fuzz_run > "$T/got" || rc=$?
  if [[ $rc -ne 0 ]]; then echo "UNEXPECTED rc=$rc $src"; cat "$src"; exit 1; fi
  if ! cmp -s "$T/got" "$b.out"; then echo "OUTPUT MISMATCH $src"; diff "$T/got" "$b.out" | head; cat "$src"; exit 1; fi
  pass=$((pass+1))
done
echo "PASS $pass typed programs"
