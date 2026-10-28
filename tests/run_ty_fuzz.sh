#!/usr/bin/env bash
# Phase 1 (types) gate: random typed programs vs an independent interpreter.
# usage: tests/run_ty_fuzz.sh [CASES] [SEED]
# env:   SKITE=compiler (default ./skite), JOBS=parallel workers (default: CPU count)
set -euo pipefail
SELF=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
cd "$(dirname "$0")/.."
. tests/par.sh
SKITE=${SKITE:-./skite}; export SKITE

# worker: compile one generated program, run it, compare with the interpreter's output
one() {
  par_skip "$1" && return 0
  local src=$1 base b rc
  b=${src%.ck}; base=${b##*/}
  local p=$W/$base.p log=$W/$base.log got=$W/$base.got fail=$W/$base.fail
  if ! "$SKITE" "$src" "$p" > "$log" 2>&1; then { echo "COMPILE FAIL $src"; cat "$log" "$src"; } > "$fail"; par_failed "$base"; fi
  rc=$( ( "$p" > "$got" 2>/dev/null ); echo $? ) 2>/dev/null
  if [[ $rc -ne 0 ]]; then { echo "UNEXPECTED rc=$rc $src"; cat "$src"; } > "$fail"; par_failed "$base"; fi
  if ! cmp -s "$got" "$b.out"; then { echo "OUTPUT MISMATCH $src"; diff "$got" "$b.out" | head || true; cat "$src"; } > "$fail"; par_failed "$base"; fi
  rm -f "$p" "$log" "$got"
  echo 1 > "$W/$base.stat"
}
if [[ ${1:-} == --one ]]; then one "$2"; exit 0; fi

N=${1:-300}; SEED=${2:-1}
par_setup
cc -std=c11 -O2 -Wall -Wextra -Werror -fno-math-errno tests/ty_fuzz.c -o "$T/gen"
"$T/gen" "$T" "$N" "$SEED"
shopt -s nullglob; srcs=("$T"/t*.ck)
par_main "$SELF" "${srcs[@]}"
echo "PASS $(par_sum) typed programs"
