#!/usr/bin/env bash
# Fast correctness gate (`make quick`): the fixed-point selfcheck, the regression
# suite and a small batch of every fuzzer, all running concurrently. About 15-20 s
# on 4 idle CPUs, against several minutes for `make test` plus the other fuzzers.
# Each fuzzer already parallelizes over JOBS workers (default: CPU count).
# usage: tests/quick.sh        env: SKITE=compiler (default ./skite), JOBS=workers per fuzzer
set -uo pipefail
cd "$(dirname "$0")/.."
SKITE=${SKITE:-./skite}; export SKITE
[ -x ./skite ] || make -s skite
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

now_ms() { local t=${EPOCHREALTIME:-$SECONDS.000000}; echo $(( ${t/./} / 1000 )); }
names=()
# job NAME CMD... : run CMD in the background, log to $T/NAME.log, report when it finishes
job() {
  local name=$1; shift; names+=("$name")
  (
    s=$(now_ms); rc=0
    "$@" > "$T/$name.log" 2>&1 || rc=$?
    ms=$(( $(now_ms) - s )); echo $rc > "$T/$name.rc"
    if [ $rc -eq 0 ]; then verdict=ok; detail=$(tail -n 1 "$T/$name.log" | cut -c1-90)
    else verdict=FAIL; detail="(exit $rc, log below)"; fi
    printf '  %-4s %-14s %5d.%ds  %s\n' $verdict "$name" $((ms/1000)) $((ms%1000/100)) "$detail"
  ) &
}

selfcheck() { ./skite skite.ck "$T/skite.check" && cmp skite "$T/skite.check" && echo "selfcheck: fixed point"; }

start=$(now_ms)
echo "quick: running checks concurrently ($(nproc) CPUs, JOBS=${JOBS:-nproc} workers per fuzzer)"
job selfcheck   selfcheck
job run.sh      tests/run.sh
# args: CASES SEED PRESSURE MEM FUNC PAR
job cf-plain    tests/run_cf_fuzz.sh 120 2 0 0 0 0
job cf-all      tests/run_cf_fuzz.sh 120 3 1 1 1 1
job cf-mem-func tests/run_cf_fuzz.sh 80 4 0 1 1 0
job ty-fuzz     tests/run_ty_fuzz.sh 250 2
job dag-fuzz    tests/run_dag_fuzz.sh 120 2
job vec-fuzz    python3 tests/vec_fuzz.py 150 2
job divconst    tests/run_divconst.sh
wait

failed=()
for n in "${names[@]}"; do [ "$(cat "$T/$n.rc")" -eq 0 ] || failed+=("$n"); done
secs=$(( ($(now_ms) - start) / 1000 ))
if [ ${#failed[@]} -eq 0 ]; then
  echo "quick: all ${#names[@]} checks passed in ${secs}s"
else
  for n in "${failed[@]}"; do echo; echo "=== FAILED: $n"; cat "$T/$n.log"; done
  echo; echo "quick: ${#failed[@]} of ${#names[@]} checks FAILED (${failed[*]}) after ${secs}s"
  exit 1
fi
