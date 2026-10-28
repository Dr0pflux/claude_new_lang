#!/usr/bin/env python3
"""Constant propagation must preserve division traps, including unused results."""
import os
from pathlib import Path
import signal
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
compiler = Path(os.environ.get("SKITE", str(root / "skite"))).resolve()
with tempfile.TemporaryDirectory() as directory:
    tmp = Path(directory)
    for kind in ("i64", "u64"):
        for op in ("/", "%"):
            for unused in (False, True):
                expression = f"numerator {op} zero"
                statement = f"let unused = {expression};" if unused else f"print({expression});"
                source = tmp / "zero.ck"
                binary = tmp / "zero"
                source.write_text(
                    f"fn get_zero() -> {kind} {{ return 0; }} fn main() {{ print(9); "
                    f"let numerator: {kind} = 42; let zero: {kind} = get_zero(); "
                    f"{statement} print(10); }}\n"
                )
                case = f"{kind} {op} unused={unused}"
                try:
                    build = subprocess.run([str(compiler), str(source), str(binary)],
                                           capture_output=True, timeout=10)
                    if build.returncode:
                        raise SystemExit(f"FAIL {case}: compile failed: {build.stderr!r}")
                    result = subprocess.run([str(binary)], capture_output=True, timeout=5)
                except subprocess.TimeoutExpired as error:
                    raise SystemExit(f"FAIL {case}: timed out") from error
                if result.returncode not in (-signal.SIGFPE, 128 + signal.SIGFPE) or result.stdout != b"9\n":
                    raise SystemExit(f"FAIL {case}: rc={result.returncode}, output={result.stdout!r}")
print("PASS: 8 propagated-zero division/remainder cases preserve traps and output")
