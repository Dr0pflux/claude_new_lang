#!/usr/bin/env bash
# Vigenere solver benchmark: identical algorithm/output in ling0, C (gcc, clang), Rust.
# usage: bench/vigenere/run_bench.sh QUAD CIPHER [RUNS]
set -euo pipefail
cd "$(dirname "$0")"; Q=$1; C=$2; RUNS=${3:-9}; B=$(mktemp -d); trap 'rm -rf "$B"' EXIT
../../ling0 vig.cock $B/ling0 >/dev/null
gcc -O3 -march=native vig.c -o $B/gcc; clang -O3 -march=native vig.c -o $B/clang
rustc -C opt-level=3 -C target-cpu=native vig.rs -o $B/rust
ref=$($B/gcc $Q $C | md5sum)
for v in ling0 clang rust; do [[ $($B/$v $Q $C | md5sum) == "$ref" ]] || { echo "OUTPUT MISMATCH $v"; exit 1; }; done
declare -A T
for ((r=0;r<RUNS;r++)); do for v in ling0 gcc clang rust; do
  s=$(date +%s%N); $B/$v $Q $C >/dev/null; e=$(date +%s%N); T[$v]+="$(( (e-s)/1000000 )) "; done; done
for v in ling0 gcc clang rust; do
  sorted=$(tr ' ' '\n' <<<"${T[$v]}" | grep . | sort -n | xargs)
  printf "%-6s median %5s ms  min %5s ms  [%s]\n" $v "$(echo $sorted | awk '{print $(int((NF+1)/2))}')" "$(echo $sorted | awk '{print $1}')" "$sorted"
done
