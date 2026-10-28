"""Regression tests for benchmark-runner failure handling."""
import contextlib
import importlib.util
import io
import pathlib
import subprocess
import tempfile
import unittest
from unittest import mock


RUNNER_PATH = pathlib.Path(__file__).with_name("run.py")
SPEC = importlib.util.spec_from_file_location("game_benchmark_runner", RUNNER_PATH)
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)


class RunnerReliabilityTests(unittest.TestCase):
    def test_missing_optional_compilers_are_skipped(self):
        calls = []

        def fake_run(cmd, **kwargs):
            calls.append(cmd[0])
            if cmd[0] == runner.SKITE:
                return subprocess.CompletedProcess(cmd, 0)
            raise FileNotFoundError(cmd[0])

        with tempfile.TemporaryDirectory() as tmp, mock.patch.object(runner.subprocess, "run", fake_run):
            with contextlib.redirect_stderr(io.StringIO()):
                exes = runner.build("nbody", tmp)

        self.assertEqual(set(exes), {"skite"})
        self.assertEqual(calls, [runner.SKITE, "gcc", "clang", "rustc"])

    def test_nonzero_executable_fails_output_and_timing_runs(self):
        with tempfile.TemporaryDirectory() as tmp:
            executable = pathlib.Path(tmp) / "fails"
            executable.write_text("#!/bin/sh\nexit 19\n")
            executable.chmod(0o755)
            for stdout in (subprocess.PIPE, subprocess.DEVNULL):
                with self.subTest(stdout=stdout), self.assertRaises(subprocess.CalledProcessError) as raised:
                    runner.execute(str(executable), "1", stdout=stdout)
                self.assertEqual(raised.exception.returncode, 19)

    def test_nonpositive_run_counts_fail(self):
        for count in ("0", "-2"):
            with self.subTest(count=count), mock.patch.object(runner.sys, "argv", [str(RUNNER_PATH), count]):
                with self.assertRaisesRegex(SystemExit, "positive integer"):
                    runner.main()

    def test_unknown_benchmark_filter_fails(self):
        with mock.patch.object(runner.sys, "argv", [str(RUNNER_PATH), "not-a-benchmark"]):
            with self.assertRaisesRegex(SystemExit, "unknown benchmark"):
                runner.main()

    def test_empty_version_output_is_reported_as_unavailable(self):
        def empty_version(cmd, **kwargs):
            return subprocess.CompletedProcess(cmd, 0, stdout="", stderr="")

        output = io.StringIO()
        with mock.patch.object(runner.sys, "argv", [str(RUNNER_PATH), "nbody"]), \
             mock.patch.object(runner.subprocess, "run", empty_version), \
             mock.patch.object(runner, "build", return_value={}), \
             mock.patch.object(runner, "open", mock.mock_open(read_data="model name : test cpu\n"), create=True), \
             contextlib.redirect_stdout(output):
            runner.main()

        for compiler in ("gcc", "clang", "rustc"):
            self.assertIn(f"{compiler}: unavailable", output.getvalue())
        self.assertIn("no comparator available", output.getvalue())


if __name__ == "__main__":
    unittest.main()
