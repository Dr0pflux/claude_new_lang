#!/usr/bin/env python3
"""Inject a hanging compiler to verify fuzz timeouts and retained reproducers."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
HARNESSES = [
    ["bash", "tests/run_cf_fuzz.sh", "1", "1"],
    ["bash", "tests/run_ty_fuzz.sh", "1", "1"],
    ["bash", "tests/run_dag_fuzz.sh", "1", "1"],
    ["bash", "tests/run_divconst.sh"],
    [sys.executable, "tests/vec_fuzz.py", "1", "1"],
]
with tempfile.TemporaryDirectory() as directory:
    tmp = Path(directory)
    compiler = tmp / "hanging-compiler"
    compiler.write_text("#!/bin/sh\nprintf 'partial compiler output\\n'\nexec sleep 5\n")
    compiler.chmod(0o755)
    for index, command in enumerate(HARNESSES):
        artifacts = tmp / f"artifacts-{index}"
        env = dict(os.environ, SKITE=str(compiler), SKITE_COMPILE_TIMEOUT="0.1",
                   SKITE_RUN_TIMEOUT="0.1", SKITE_ARTIFACT_DIR=str(artifacts))
        try:
            result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True,
                                    text=True, timeout=10)
        except subprocess.TimeoutExpired as error:
            raise SystemExit(f"FAIL: harness did not bound compilation: {command}") from error
        if result.returncode == 0:
            raise SystemExit(f"FAIL: hanging compiler passed: {command}")
        saved = list(artifacts.iterdir()) if artifacts.exists() else []
        if len(saved) != 1 or not list(saved[0].glob("*.ck")):
            raise SystemExit(f"FAIL: source reproducer missing: {command}: {result.stdout} {result.stderr}")
        if index == 4:
            metadata = json.loads((saved[0] / "metadata.json").read_text())
            if not metadata["commands"]["compile-vector"].get("timed_out"):
                raise SystemExit("FAIL: vector timeout not recorded")
            log = (saved[0] / "compile-vector.stdout").read_text()
        else:
            context = (saved[0] / "context.txt").read_text()
            if "compile_status=124" not in context and "compile_status=137" not in context:
                raise SystemExit(f"FAIL: timeout status missing: {context}")
            log = (saved[0] / "log").read_text()
        if "partial compiler output" not in log:
            raise SystemExit(f"FAIL: partial compiler log missing: {command}")
print("PASS: all five fuzz harnesses bound compiler hangs and retain failure evidence")
