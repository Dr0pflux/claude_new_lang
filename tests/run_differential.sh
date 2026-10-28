#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
CC=${CC:-cc}
"$CC" -std=c11 -O2 -Wall -Wextra -Wpedantic -Werror ling0.c -o ling0
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
"$CC" -std=c11 -O2 -Wall -Wextra -Wpedantic -Werror tests/differential.c -o "$T/gen"
"$T/gen" "$T" "${1:-120}"
passed=0;spilling=0;total_code=0
for src in "$T"/case_*.cock;do
  read -r e1 e3 e5 e7 < "${src%.cock}.expected"
  ./ling0 "$src" "$T/prog" > "$T/build.log"
  if grep -E ' [1-9][0-9]* spills' "$T/build.log" >/dev/null;then spilling=$((spilling+1));fi
  for spec in '1' '3 a b' '5 a b c d' '7 a b c d e f';do
    read -r n rest <<< "$spec"
    case "$n" in 1)want=$e1;;3)want=$e3;;5)want=$e5;;7)want=$e7;;esac
    # Word splitting is deliberate: each extra argument increments argc.
    # shellcheck disable=SC2086
    got=$("$T/prog" $rest)
    if [[ "$got" != "$want" ]];then
      echo "FAIL: $src argc=$n expected=$want got=$got" >&2
      cat "$src" >&2
      exit 1
    fi
    passed=$((passed+1))
  done
done
if [[ "$spilling" -eq 0 ]];then echo 'FAIL: no test exercised spilling' >&2;exit 1;fi
echo "PASS: $passed independent C-oracle comparisons, across $spilling spilling programs"
