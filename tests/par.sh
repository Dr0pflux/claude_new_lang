# Shared plumbing for the parallel fuzz runners. Source it; do not execute it.
#
# A runner has a serial part (build the generator, generate the programs) and a
# per-program worker. The worker is a function of the runner itself, which the
# runner re-invokes as `SELF --one SRC`; par_main fans those invocations out
# over JOBS processes with xargs -P (JOBS defaults to the number of CPUs).
#
# Worker protocol, with W=$T/w and BASE the program's file name without .ck:
#   start    `par_skip SRC && return 0` (skips programs after a known failure)
#   success  write one line of counters to $W/BASE.stat (par_main sums them)
#   failure  write the complete failure report to $W/BASE.fail, then call
#            `par_failed BASE`
# par_main prints the report of the first failing program in program order and
# exits 1. Programs run in order and only programs after a recorded failure are
# skipped, so that is the failure a serial run would have stopped at.

JOBS=${JOBS:-$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}

# main: scratch directory (removed on exit) and the worker directory
par_setup() { T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; W=$T/w; mkdir "$W"; export T W; }

# worker: true when a program that sorts before SRC has already failed
par_skip() {
  [[ -s $T/FAILED ]] || return 1
  local b=${1##*/}; b=${b%.ck}
  [[ $(sort "$T/FAILED" | head -n 1) < $b ]]
}
# worker: record that BASE failed (its .fail file is already written) and finish
par_failed() { echo "$1" >> "$T/FAILED"; exit 0; }

# main: par_main SELF SRC... runs `SELF --one SRC` for every SRC, JOBS at a time
par_main() {
  local self=$1 rc=0 s b n=0; shift
  (( $# > 0 )) || return 0
  printf '%s\0' "$@" | xargs -0 -n 1 -P "$JOBS" "$self" --one || rc=$?
  for s in "$@"; do
    b=${s##*/}; b=${b%.ck}
    if [[ -e $W/$b.fail ]]; then cat "$W/$b.fail"; exit 1; fi
  done
  # no reported failure: every worker must have exited 0 and finished its program
  for s in "$@"; do b=${s##*/}; [[ -e $W/${b%.ck}.stat ]] && n=$((n+1)); done
  if (( rc != 0 || n != $# )); then
    echo "INTERNAL ERROR: parallel workers did not all finish (xargs status $rc, $n of $# programs done)"
    exit 1
  fi
}

# main: sum of the .stat columns, as one line "c1 c2 ..."
par_sum() {
  cat "$W"/*.stat 2>/dev/null |
    awk '{ for (i = 1; i <= NF; i++) s[i] += $i; if (NF > n) n = NF }
         END { for (i = 1; i <= n; i++) printf "%s%d", (i > 1 ? " " : ""), s[i]; print "" }'
}
