# Shared bounded execution and optional failure artifacts for shell fuzzers.
# Source after changing to the repository root and creating T.
fuzz_compile() {
  local rc=0
  timeout --kill-after=1s "${SKITE_COMPILE_TIMEOUT:-10}s" "${SKITE:-./skite}" "$src" "$T/p" > "$T/log" 2>&1 || rc=$?
  FUZZ_COMPILE_STATUS=$rc
  if [[ $rc -ne 0 ]]; then
    echo "COMPILE FAIL rc=$rc $src (timeout status: 124 or 137)"
    cat "$T/log" "$src"
    return "$rc"
  fi
}

fuzz_run() {
  local rc=0
  { timeout --kill-after=1s "${SKITE_RUN_TIMEOUT:-10}s" "$T/p" "$@" || rc=$?; } 2> "$T/stderr"
  FUZZ_RUN_STATUS=$rc
  return "$rc"
}

fuzz_cleanup() {
  local rc=$1 saved item
  if [[ $rc -ne 0 && -n ${SKITE_ARTIFACT_DIR:-} && -n ${src:-} ]]; then
    if mkdir -p -- "$SKITE_ARTIFACT_DIR" && saved=$(mktemp -d "$SKITE_ARTIFACT_DIR/$(basename "$0" .sh).XXXXXX"); then
      for item in "${src%.ck}".* "$T/log" "$T/got" "$T/stderr" "$T/p"; do
        if [[ -f $item ]]; then cp -- "$item" "$saved/" || true; fi
      done
      printf 'harness=%s\nsource=%s\nexit=%s\nseed=%s\nargs=%s\ncompile_timeout=%s\nrun_timeout=%s\ncompiler=%s\ncompile_status=%s\nrun_status=%s\n' \
        "$0" "$src" "$rc" "${SEED:-}" "${args[*]:-}" "${SKITE_COMPILE_TIMEOUT:-10}" "${SKITE_RUN_TIMEOUT:-10}" "${SKITE:-./skite}" "${FUZZ_COMPILE_STATUS:-}" "${FUZZ_RUN_STATUS:-}" > "$saved/context.txt"
      echo "Failure artifacts: $saved" >&2
    else
      echo "Could not preserve failure artifacts in $SKITE_ARTIFACT_DIR" >&2
    fi
  fi
  rm -rf -- "$T"
}
trap 'fuzz_cleanup "$?"' EXIT
# GNU timeout treats zero as unlimited; reject it and malformed durations up front.
if ! python3 - "${SKITE_COMPILE_TIMEOUT:-10}" "${SKITE_RUN_TIMEOUT:-10}" <<'PY'
import math
import re
import sys

for name, value in zip(("SKITE_COMPILE_TIMEOUT", "SKITE_RUN_TIMEOUT"), sys.argv[1:]):
    if (not re.fullmatch(r"(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)", value)
            or not math.isfinite(float(value)) or float(value) <= 0):
        print(f"{name} must be a positive finite decimal number of seconds", file=sys.stderr)
        sys.exit(1)
PY
then
  exit 2
fi
