#!/usr/bin/env python3
"""The LLVM backend (tools/skite-llvm) must print exactly what the native backend prints
for every Benchmarks Game program and every kernel."""
import os, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKITE = os.path.join(ROOT, "skite")
LLVM = os.path.join(ROOT, "tools", "skite-llvm")
GAME = [("nbody", ["20000"]), ("spectralnorm", ["300"]), ("mandelbrot", ["400"]),
        ("fannkuchredux", ["8"]), ("fasta", ["50000"]), ("binarytrees", ["12"])]

def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, timeout=300, **kw)

def main():
    progs = [(os.path.join(ROOT, "bench", "game", n + ".ck"), a) for n, a in GAME]
    kd = os.path.join(ROOT, "bench", "kernels")
    progs += [(os.path.join(kd, f), []) for f in sorted(os.listdir(kd)) if f.endswith(".ck")]
    with tempfile.TemporaryDirectory(prefix="skite-llvm-game-") as td:
        for src, args in progs:
            nat, ll = os.path.join(td, "native"), os.path.join(td, "llvm")
            for cmd in ([SKITE, src, nat], [LLVM, src, ll]):
                p = run(cmd)
                if p.returncode != 0:
                    sys.exit(f"FAIL: build {' '.join(cmd)}\n{p.stderr.decode()}")
            a, b = run([nat] + args), run([ll] + args)
            if (a.returncode, a.stdout) != (b.returncode, b.stdout):
                sys.exit(f"FAIL: {os.path.basename(src)} {args}: native rc={a.returncode} llvm rc={b.returncode}, outputs differ")
    print(f"PASS: {len(progs)} Game and kernel programs print identical output with --llvm")

main()
