#!/usr/bin/env python3
"""Deterministic subprocess-policy tests for each oracle fuzz harness."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

HERE = Path(__file__).resolve().parent
HARNESS_NAMES = ("bvfuzz.py", "bvfuzz2.py", "lhfuzz.py", "rotfuzz.py", "selfuzz.py")


def fake_compiler(path, mode, side):
    if mode == "compile-error":
        body = "import sys; print('synthetic compile failure', file=sys.stderr); sys.exit(7)"
    elif mode == "missing-output":
        body = "pass"
    elif mode == "compile-timeout":
        body = "import time; time.sleep(5)"
    elif mode == "compile-fork-timeout":
        body = "import os,subprocess,sys,time; p=subprocess.Popen([sys.executable,'-c','import time;time.sleep(30)']); open(os.environ['ORACLE_CHILD_PID'],'w').write(str(p.pid)); time.sleep(30)"
    else:
        if mode == "runtime-timeout":
            program = "#!/usr/bin/env python3\nimport time; time.sleep(5)\n"
        elif mode == "runtime-fork-timeout":
            program = "#!/usr/bin/env python3\nimport os,subprocess,sys,time; p=subprocess.Popen([sys.executable,'-c','import time;time.sleep(30)']); open(os.environ['ORACLE_CHILD_PID'],'w').write(str(p.pid)); time.sleep(30)\n"
        elif mode == "runtime-failure":
            program = "#!/usr/bin/env python3\nimport sys; sys.exit(42)\n"
        elif mode == "matching-trap":
            program = "#!/usr/bin/env python3\nimport os,signal; os.kill(os.getpid(), signal.SIGFPE)\n"
        else:
            output = "NEW\n" if mode == "mismatch" and side == "new" else "SAME\n"
            program = f"#!/usr/bin/env python3\nprint({output!r}, end='')\n"
        body = f"from pathlib import Path; p=Path(sys.argv[2]); p.write_text({program!r}); p.chmod(0o755)"
    path.write_text("#!/usr/bin/env python3\nimport sys\n" + body + "\n")
    path.chmod(0o755)


def child_stopped(pid):
    """A vanished or zombie child is stopped; a live process is not."""
    for _ in range(30):
        try:
            stat = Path(f"/proc/{pid}/stat").read_text()
            state = stat[stat.rfind(")") + 2]
            if state == "Z":
                return True
        except FileNotFoundError:
            return True
        time.sleep(0.05)
    return False


def run_case(harness, mode, compile_timeout="0.75", run_timeout="0.75"):
    with tempfile.TemporaryDirectory(prefix="oracle-harness-test-") as td:
        td = Path(td)
        new = td / "new compiler"
        old = td / "old compiler"
        fake_compiler(new, mode, "new")
        fake_compiler(old, mode, "old")
        pid_file = td / "child.pid"
        env = os.environ.copy()
        env["SKITE_ORACLE_COMPILE_TIMEOUT"] = compile_timeout
        env["SKITE_ORACLE_RUN_TIMEOUT"] = run_timeout
        env["ORACLE_CHILD_PID"] = str(pid_file)
        result = subprocess.run([sys.executable, str(HERE / harness), str(new), str(old), "1", "31415"],
                                capture_output=True, text=True, env=env, timeout=5)
        pid = int(pid_file.read_text()) if pid_file.exists() else None
        return result, pid


def main():
    expected = {
        "pass": 0,
        "matching-trap": 0,
        "mismatch": 1,
        "compile-error": 2,
        "missing-output": 2,
        "compile-timeout": 2,
        "runtime-timeout": 2,
        "runtime-failure": 2,
        "compile-fork-timeout": 2,
        "runtime-fork-timeout": 2,
    }
    checks = 0
    for harness in HARNESS_NAMES:
        for mode, status in expected.items():
            result, child_pid = run_case(harness, mode)
            checks += 1
            if result.returncode != status:
                raise AssertionError(f"{harness} {mode}: expected {status}, got {result.returncode};\n{result.stdout}{result.stderr}")
            if mode == "mismatch" and "MISMATCH" not in result.stderr:
                raise AssertionError(f"{harness}: mismatch lacked diagnostic/artifact path: {result.stderr}")
            if mode not in ("pass", "matching-trap", "mismatch") and "artifacts=" not in result.stderr:
                raise AssertionError(f"{harness} {mode}: failure omitted retained artifact path: {result.stderr}")
            if mode in ("compile-fork-timeout", "runtime-fork-timeout"):
                if child_pid is None or not child_stopped(child_pid):
                    raise AssertionError(f"{harness} {mode}: descendant {child_pid} survived timeout")
        for invalid in ("nan", "inf", "-inf", "0", "-1"):
            result, _ = run_case(harness, "pass", compile_timeout=invalid)
            checks += 1
            if result.returncode != 2 or "finite and positive" not in result.stderr:
                raise AssertionError(f"{harness}: accepted invalid timeout {invalid}: {result.returncode}; {result.stderr}")
    print(f"ok: {checks} deterministic harness cases")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
