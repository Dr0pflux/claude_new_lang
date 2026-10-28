#!/usr/bin/env bash
# usage: tests/run_dag_fuzz.sh [CASES] [SEED]
# env:   SKITE=compiler (default ./skite), JOBS=parallel workers (default: CPU count)
set -euo pipefail
SELF=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
cd "$(dirname "$0")/.."
. tests/par.sh
SKITE=${SKITE:-./skite}; export SKITE

# worker: compile one generated program and compare its output for argc 1..4
one() {
  par_skip "$1" && return 0
  local src=$1 base x got spill=0 pass=0 args=() exp
  base=${src##*/}; base=${base%.ck}
  local p=$W/$base.p log=$W/$base.log fail=$W/$base.fail
  if ! "$SKITE" "$src" "$p" > "$log" 2>&1; then { echo "COMPILE FAIL $src"; cat "$log"; cat "$src"; } > "$fail"; par_failed "$base"; fi
  grep -qE ' [1-9][0-9]* spills' "$log" && spill=1
  mapfile -t exp < "${src%.ck}.exp"
  for x in 0 1 2 3; do
    got=$("$p" "${args[@]}" 2>&1) || true
    if [[ "$got" != "${exp[$x]}" ]]; then { echo "MISMATCH $src argc=$((x+1)) want=${exp[$x]} got=$got"; cat "$src"; } > "$fail"; par_failed "$base"; fi
    pass=$((pass+1)); args+=(a)
  done
  rm -f "$p" "$log"
  echo "$pass $spill" > "$W/$base.stat"
}
if [[ ${1:-} == --one ]]; then one "$2"; exit 0; fi

N=${1:-300}; SEED=${2:-1}; D=tests
par_setup
cc -O2 -o "$T/gen" -std=c11 -Wall -Wextra -Werror "$D/dag_fuzz.c"; "$T/gen" "$T" "$N" "$SEED"
shopt -s nullglob; srcs=("$T"/f*.ck)
par_main "$SELF" "${srcs[@]}"
read -r pass spills <<< "$(par_sum)"
echo "PASS $pass comparisons, $spills/$N programs spilled"
