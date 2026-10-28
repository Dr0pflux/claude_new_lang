#!/usr/bin/env bash
# G1/G3 gate: random structured programs vs an independent reference interpreter.
# usage: tests/run_cf_fuzz.sh [CASES] [SEED] [PRESSURE=0|1] [MEM=0|1] [FUNC=0|1] [PAR=0|1]
set -euo pipefail
cd "$(dirname "$0")/.."
N=${1:-300}; SEED=${2:-1}; PRESSURE=${3:-0}; MEM=${4:-0}; FUNC=${5:-0}; PAR=${6:-0}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cc -std=c11 -O2 -Wall -Wextra -Werror tests/cf_fuzz.c -o "$T/gen"
"$T/gen" "$T" "$N" "$SEED" "$PRESSURE" "$MEM" "$FUNC" "$PAR"
pass=0; traps=0; loops=0; spills=0
for src in "$T"/c*.cock; do
  b=${src%.cock}
  if ! "${LING:-./ling}" "$src" "$T/p" > "$T/log" 2>&1; then echo "COMPILE FAIL $src"; cat "$T/log" "$src"; exit 1; fi
  grep -q while "$src" && loops=$((loops+1))
  grep -qE ' [1-9][0-9]* spills' "$T/log" && spills=$((spills+1))
  args=()
  for a in 1 2 3; do
    rc=$( ( "$T/p" "${args[@]}" > "$T/got" 2>/dev/null ); echo $? ) 2>/dev/null
    want=$(cat "$b.a$a.rc")
    if [[ $want == TRAP ]]; then
      if [[ $rc -ne 136 && $rc -ne 132 ]]; then echo "EXPECTED TRAP $src argc=$a rc=$rc"; cat "$src"; exit 1; fi
      traps=$((traps+1))
    elif [[ $rc -ne 0 ]]; then echo "UNEXPECTED rc=$rc $src argc=$a"; cat "$src"; exit 1; fi
    if ! cmp -s "$T/got" "$b.a$a.out"; then echo "OUTPUT MISMATCH $src argc=$a"; diff <(head -c 2000 "$T/got") <(head -c 2000 "$b.a$a.out") | head; cat "$src"; exit 1; fi
    pass=$((pass+1)); args+=(a)
  done
done
echo "PASS $pass runs ($traps expected traps) over $N programs ($loops with loops, $spills spilling)"
