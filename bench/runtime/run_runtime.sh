#!/usr/bin/env bash
# Runtime benchmark: same algorithm, same semantics, outputs must match.
# usage: bench/runtime/run_runtime.sh [RUNS]   (needs clang, gcc, rustc)
set -euo pipefail
cd "$(dirname "$0")"; RUNS=${1:-7}; B=$(mktemp -d); trap 'rm -rf "$B"' EXIT
L=../../ling0; [[ -x $L ]] || (cd ../.. && make ling0 >/dev/null)
echo "cpu: $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | xargs)"
echo "clang: $(clang --version | head -1)"; echo "gcc: $(gcc --version | head -1)"; echo "rustc: $(rustc --version)"
for k in *.cock; do k=${k%.cock}
  $L $k.cock $B/$k.ling0 >/dev/null
  clang -O3 -march=native $k.c -o $B/$k.clang
  gcc -O3 -march=native $k.c -o $B/$k.gcc
  rustc -C opt-level=3 -C target-cpu=native $k.rs -o $B/$k.rust
  ref=$($B/$k.clang)
  for v in ling0 clang gcc rust; do [[ $($B/$k.$v) == "$ref" ]] || { echo "OUTPUT MISMATCH $k $v"; exit 1; }; done
  declare -A T=()
  for ((r=0;r<RUNS;r++)); do for v in ling0 clang gcc rust; do
    s=$(date +%s%N); $B/$k.$v >/dev/null; e=$(date +%s%N); T[$v]+="$(( (e-s)/1000000 )) "
  done; done
  for v in ling0 clang gcc rust; do
    sorted=$(tr ' ' '\n' <<<"${T[$v]}" | grep . | sort -n | xargs)
    med=$(awk '{print $((NF+1)/2)}' <<<"$sorted" 2>/dev/null || true)
    med=$(echo $sorted | awk '{a[NR]=$0} {n=split($0,x," "); print x[int((n+1)/2)]}')
    min=$(echo $sorted | awk '{print $1}')
    printf "%-12s %-6s median %5s ms  min %5s ms  runs: %s\n" "$k" "$v" "$med" "$min" "$sorted"
  done
  unset T
done
