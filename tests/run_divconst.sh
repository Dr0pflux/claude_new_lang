#!/usr/bin/env bash
# Validates constant-divisor lowering (magic multiply, power-of-2, idiv fallback).
set -euo pipefail
cd "$(dirname "$0")/.."
T=$(mktemp -d)
source tests/fuzz_helpers.sh
cc -std=c11 -O2 -Wall -Wextra -Werror tests/divconst_gen.c -o "$T/gen"
"$T/gen" "$T"
pass=0
for src in "$T"/d*.ck; do
  if ! fuzz_compile; then exit 1; fi
  want=$(cat "${src%.ck}.exp"); rc=0; fuzz_run > "$T/got" || rc=$?
  got=$(cat "$T/got")
  if [[ $want == TRAP ]]; then [[ $rc -eq 136 ]] || { echo "EXPECTED TRAP $src rc=$rc"; exit 1; }
  elif [[ $rc -ne 0 || $got != "$want" ]]; then echo "MISMATCH $src want=$want got=$got rc=$rc"; cat "$src"; exit 1; fi
  pass=$((pass+1))
done
echo "PASS: $pass divisor programs match the C oracle"
