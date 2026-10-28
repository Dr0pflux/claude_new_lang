#!/usr/bin/env python3
"""Regression for register-budget exhaustion in if-converted logical trees."""
import argparse
import pathlib
import subprocess
import tempfile


def nested_or(values, tail="a == 99"):
    expr = tail
    for value in values:
        expr = f"(a == {value} || {expr})"
    return expr


def nested_and(values, tail="a == 99"):
    expr = tail
    for value in values:
        expr = f"(a == {value} && {expr})"
    return expr


def program(cond):
    return f"""fn main() {{
  let a = argc();
  let mut i = 0;
  let mut x = 0;
  let mut y = 0;
  while i < 2 {{
    if {cond} {{ x += 1; y += 2; }} else {{ x += 3; y += 4; }}
    i += 1;
  }}
  print(x); print(y);
}}
"""


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--compiler", default="./skite")
    args = parser.parse_args()
    compiler = str(pathlib.Path(args.compiler).resolve())
    and_not = "a != 99"
    for value in range(4, 24):
        and_not = f"(a != {value} && {and_not})"
    cases = [
        (and_not, 3, b"6\n8\n"),
        (and_not, 0, b"2\n4\n"),
        ("a == 4 || a == 99", 3, b"2\n4\n"),
        (nested_or(range(4, 24)), 3, b"2\n4\n"),
        (nested_and(range(4, 24)), 3, b"6\n8\n"),
        (f"!({nested_or(range(4, 24))})", 3, b"6\n8\n"),
        (f"(a == 4 && {nested_or(range(5, 24))}) || a == 4", 3, b"2\n4\n"),
        (nested_or(range(4, 24)), 0, b"6\n8\n"),
        (nested_or(range(4, 24)), 7, b"2\n4\n"),
    ]
    with tempfile.TemporaryDirectory(prefix="skite-ifconv-") as tmp:
        root = pathlib.Path(tmp)
        for index, (cond, nargs, expected) in enumerate(cases):
            source = root / f"case-{index}.ck"
            binary = root / f"case-{index}"
            source.write_text(program(cond))
            subprocess.run([compiler, str(source), str(binary)], check=True,
                           timeout=10, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            run = subprocess.run([str(binary), *(["x"] * nargs)], timeout=2,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            if run.returncode != 0 or run.stdout != expected:
                raise SystemExit(
                    f"case {index}: args={nargs}, status={run.returncode}, "
                    f"stdout={run.stdout!r}, expected={expected!r}, stderr={run.stderr!r}"
                )
    print(f"ifconv_depth: {len(cases)} cases passed")


if __name__ == "__main__":
    main()
