#!/usr/bin/env bash
# Validates constant-divisor lowering (magic multiply, power-of-2, idiv fallback).
# env: SKITE=compiler (default ./skite), JOBS=parallel workers (default: CPU count)
set -euo pipefail
SELF=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
cd "$(dirname "$0")/.."
. tests/par.sh
SKITE=${SKITE:-./skite}; export SKITE

# worker: compile one divisor program, run it, compare with the C oracle's answer
one() {
  par_skip "$1" && return 0
  local src=$1 base want rc=0 got
  base=${src##*/}; base=${base%.ck}
  local p=$W/$base.p log=$W/$base.log fail=$W/$base.fail
  if ! "$SKITE" "$src" "$p" > "$log" 2>&1; then { echo "COMPILE FAIL $src"; cat "$log" "$src"; } > "$fail"; par_failed "$base"; fi
  want=$(cat "${src%.ck}.exp"); got=$("$p" 2>/dev/null) || rc=$?
  if [[ $want == TRAP ]]; then
    [[ $rc -eq 136 ]] || { echo "EXPECTED TRAP $src rc=$rc" > "$fail"; par_failed "$base"; }
  elif [[ $rc -ne 0 || $got != "$want" ]]; then
    { echo "MISMATCH $src want=$want got=$got rc=$rc"; cat "$src"; } > "$fail"; par_failed "$base"
  fi
  rm -f "$p" "$log"
  echo 1 > "$W/$base.stat"
}
if [[ ${1:-} == --one ]]; then one "$2"; exit 0; fi

par_setup
cc -std=c11 -O2 -Wall -Wextra -Werror tests/divconst_gen.c -o "$T/gen"
"$T/gen" "$T"
shopt -s nullglob; srcs=("$T"/d*.ck)
par_main "$SELF" "${srcs[@]}"
echo "PASS: $(par_sum) divisor programs match the C oracle"
