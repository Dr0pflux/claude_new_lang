"""Shared subprocess policy for the differential oracle fuzzers."""
import os
import math
import signal
import subprocess


class HarnessFailure(RuntimeError):
    pass


def _timeout(name, default):
    raw = os.environ.get(name, str(default))
    try:
        value = float(raw)
    except ValueError as exc:
        raise HarnessFailure(f"{name} must be a positive number, got {raw!r}") from exc
    if not math.isfinite(value) or value <= 0:
        raise HarnessFailure(f"{name} must be finite and positive, got {raw!r}")
    return value


def _allowed_runtime_status(code):
    return code == 0 or code in (-signal.SIGILL, -signal.SIGFPE,
                                 128 + signal.SIGILL, 128 + signal.SIGFPE)


def _run_bounded(argv, timeout, stage):
    """Run a command in its own process group, killing descendants on timeout."""
    try:
        process = subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   start_new_session=True)
    except OSError as exc:
        raise HarnessFailure(f"cannot start {stage} {argv[0]!r}: {exc}") from exc
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired as exc:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        stdout, stderr = process.communicate()
        raise HarnessFailure(f"{stage} timed out after {timeout:g}s: {argv[0]}") from exc
    return subprocess.CompletedProcess(argv, process.returncode, stdout, stderr)


def compile_and_run(compiler, source, output):
    compile_timeout = _timeout("SKITE_ORACLE_COMPILE_TIMEOUT", 10)
    run_timeout = _timeout("SKITE_ORACLE_RUN_TIMEOUT", 2)
    try:
        os.unlink(output)
    except FileNotFoundError:
        pass
    except OSError as exc:
        raise HarnessFailure(f"cannot clear stale output {output}: {exc}") from exc
    result = _run_bounded([compiler, source, output], compile_timeout, "compile")
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).decode(errors="replace")[:400]
        raise HarnessFailure(f"compile failed ({result.returncode}) with {compiler}: {detail}")
    if not os.path.isfile(output):
        raise HarnessFailure(f"compiler succeeded but did not create output: {output}")
    try:
        with open(output, "rb") as f:
            binary = f.read()
    except OSError as exc:
        raise HarnessFailure(f"cannot read compiled output {output}: {exc}") from exc
    result = _run_bounded([output], run_timeout, "program")
    if not _allowed_runtime_status(result.returncode):
        detail = (result.stderr or result.stdout).decode(errors="replace")[:400]
        raise HarnessFailure(f"program failed with status {result.returncode}: {output}: {detail}")
    return (result.returncode, result.stdout), binary


def run_pair(new_compiler, old_compiler, source, new_output, old_output):
    new_result, new_binary = compile_and_run(new_compiler, source, new_output)
    old_result, old_binary = compile_and_run(old_compiler, source, old_output)
    return new_result, old_result, new_binary != old_binary
