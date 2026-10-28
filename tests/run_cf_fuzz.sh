#!/usr/bin/env bash
# G1/G3 gate: random structured programs vs an independent reference interpreter.
# usage: tests/run_cf_fuzz.sh [CASES] [SEED] [PRESSURE=0|1] [MEM=0|1] [FUNC=0|1] [PAR=0|1]
# env:   SKITE=compiler (default ./skite), JOBS=parallel workers (default: CPU count)
set -euo pipefail
SELF=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
cd "$(dirname "$0")/.."
. tests/par.sh
SKITE=${SKITE:-./skite}; export SKITE

# worker: compile one generated program and check its three runs (argc 1, 2, 3)
one() {
  par_skip "$1" && return 0
  local src=$1 base b a rc want
  b=${src%.ck}; base=${b##*/}
  local p=$W/$base.p log=$W/$base.log got=$W/$base.got fail=$W/$base.fail
  if ! "$SKITE" "$src" "$p" > "$log" 2>&1; then { echo "COMPILE FAIL $src"; cat "$log" "$src"; } > "$fail"; par_failed "$base"; fi
  local loops=0 spills=0 traps=0 pass=0 args=()
  grep -q while "$src" && loops=1
  grep -qE ' [1-9][0-9]* spills' "$log" && spills=1
  for a in 1 2 3; do
    rc=$( ( "$p" "${args[@]}" > "$got" 2>/dev/null ); echo $? ) 2>/dev/null
    want=$(cat "$b.a$a.rc")
    if [[ $want == TRAP ]]; then
      if [[ $rc -ne 136 && $rc -ne 132 ]]; then { echo "EXPECTED TRAP $src argc=$a rc=$rc"; cat "$src"; } > "$fail"; par_failed "$base"; fi
      traps=$((traps+1))
    elif [[ $rc -ne 0 ]]; then { echo "UNEXPECTED rc=$rc $src argc=$a"; cat "$src"; } > "$fail"; par_failed "$base"; fi
    if ! cmp -s "$got" "$b.a$a.out"; then
      { echo "OUTPUT MISMATCH $src argc=$a"; diff <(head -c 2000 "$got") <(head -c 2000 "$b.a$a.out") | head || true; cat "$src"; } > "$fail"; par_failed "$base"
    fi
    pass=$((pass+1)); args+=(a)
  done
  rm -f "$p" "$log" "$got"
  echo "$pass $traps $loops $spills" > "$W/$base.stat"
}
if [[ ${1:-} == --one ]]; then one "$2"; exit 0; fi

N=${1:-300}; SEED=${2:-1}; PRESSURE=${3:-0}; MEM=${4:-0}; FUNC=${5:-0}; PAR=${6:-0}
par_setup
cc -std=c11 -O2 -Wall -Wextra -Werror tests/cf_fuzz.c -o "$T/gen"
"$T/gen" "$T" "$N" "$SEED" "$PRESSURE" "$MEM" "$FUNC" "$PAR"
shopt -s nullglob; srcs=("$T"/c*.ck)
par_main "$SELF" "${srcs[@]}"
read -r pass traps loops spills <<< "$(par_sum)"
echo "PASS $pass runs ($traps expected traps) over $N programs ($loops with loops, $spills spilling)"
