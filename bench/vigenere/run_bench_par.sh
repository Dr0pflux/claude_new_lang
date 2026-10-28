#!/usr/bin/env bash
# Parallel Vigenere benchmark: ling0 par vs gcc OpenMP vs Rust std::thread (same algorithm,
# same static stride over ciphertexts, identical output required). Serial ling0/gcc for scaling.
# usage: bench/vigenere/run_bench_par.sh QUAD CIPHER [RUNS]
set -euo pipefail
cd "$(dirname "$0")"; Q=$1; C=$2; RUNS=${3:-11}; B=$(mktemp -d); trap 'rm -rf "$B"' EXIT
../../ling0 vigp.l0 $B/ling0_par >/dev/null; ../../ling0 vig.l0 $B/ling0_serial >/dev/null
gcc -O3 -march=native -fopenmp vigp.c -o $B/gcc_omp; gcc -O3 -march=native vig.c -o $B/gcc_serial
rustc -C opt-level=3 -C target-cpu=native vigp.rs -o $B/rust_threads
V="ling0_par gcc_omp rust_threads ling0_serial gcc_serial"
ref=$($B/gcc_serial $Q $C | md5sum)
for v in $V; do [[ $($B/$v $Q $C | md5sum) == "$ref" ]] || { echo "OUTPUT MISMATCH $v"; exit 1; }; done
echo "cpus: $(nproc)"
declare -A T
for ((r=0;r<RUNS;r++)); do for v in $V; do
  s=$(date +%s%N); $B/$v $Q $C >/dev/null; e=$(date +%s%N); T[$v]+="$(( (e-s)/1000000 )) "; done; done
for v in $V; do
  sorted=$(tr ' ' '\n' <<<"${T[$v]}" | grep . | sort -n | xargs)
  printf "%-13s median %5s ms  min %5s ms\n" $v "$(echo $sorted | awk '{print $(int((NF+1)/2))}')" "$(echo $sorted | awk '{print $1}')"
done
