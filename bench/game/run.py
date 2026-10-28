#!/usr/bin/env python3
"""Benchmarks Game suite: skite vs gcc, clang and rustc on the same algorithms.

Each program exists as NAME.ck, NAME.c and NAME.rs. A run is rejected
unless every binary prints byte-identical output. Runs are interleaved and
the median wall time is reported.

usage: bench/game/run.py [RUNS] [--quick] [NAME...]

revcomp and knucleotide read a FASTA file: their size is the argument of the fasta
benchmark, and the harness generates the file once (with the gcc-built fasta) in the
temporary directory and passes its path to the programs.
"""
import hashlib, os, shutil, statistics, subprocess, sys, tempfile, time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SKITE = os.path.join(ROOT, "skite")
# name -> argument (standard Benchmarks Game sizes where they run in ~1 s)
SIZES = [("nbody", "50000000"), ("spectralnorm", "5500"), ("mandelbrot", "16000"),
         ("fannkuchredux", "12"), ("fasta", "25000000"), ("binarytrees", "21"),
         ("revcomp", "25000000"), ("knucleotide", "5000000"), ("nsieve", "12"), ("pidigits", "4000")]
QUICK = {"nbody": "5000000", "spectralnorm": "3000", "mandelbrot": "4000",
         "fannkuchredux": "11", "fasta": "2500000", "binarytrees": "19",
         "revcomp": "2500000", "knucleotide": "2500000", "nsieve": "10", "pidigits": "2000"}
FASTA_INPUT = {"revcomp", "knucleotide"}   # argument = size N of a generated FASTA file

def sh(cmd):
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)

def fasta_file(n, tmp):
    """Path of the output of `fasta n`, generated once per size."""
    path = os.path.join(tmp, f"fasta-{n}.txt")
    if not os.path.exists(path):
        gen = os.path.join(tmp, "fasta.gen")
        if not os.path.exists(gen):
            sh(["gcc", "-O3", "-march=native", os.path.join(HERE, "fasta.c"), "-o", gen])
        with open(path, "wb") as f:
            subprocess.run([gen, n], check=True, stdout=f)
    return path

def digest(cmd):
    h = hashlib.md5()
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE)
    for chunk in iter(lambda: p.stdout.read(1 << 20), b""):
        h.update(chunk)
    if p.wait() != 0:
        sys.exit(f"{cmd[0]} exited with status {p.returncode}")
    return h.hexdigest()

def build(name, tmp):
    src = os.path.join(HERE, name)
    exe = os.path.join(tmp, name)
    sh([SKITE, src + ".ck", exe + ".skite"])
    sh(["gcc", "-O3", "-march=native", src + ".c", "-o", exe + ".gcc", "-lm"])
    sh(["clang", "-O3", "-march=native", src + ".c", "-o", exe + ".clang", "-lm"])
    sh(["rustc", "-C", "opt-level=3", "-C", "target-cpu=native", "-C", "codegen-units=1",
        "-C", "panic=abort", src + ".rs", "-o", exe + ".rust"])
    return {v: exe + "." + v for v in ("skite", "gcc", "clang", "rust")}

def main():
    args = sys.argv[1:]
    quick = "--quick" in args
    args = [a for a in args if a != "--quick"]
    runs = int(args[0]) if args and args[0].isdigit() else 5
    only = set(a for a in args if not a.isdigit())
    cpu = open("/proc/cpuinfo").read().split("model name")[1].split(":")[1].splitlines()[0].strip()
    print(f"cpu: {cpu}, {os.cpu_count()} cpus; median of {runs} interleaved runs, wall ms")
    for c in (["gcc", "--version"], ["clang", "--version"], ["rustc", "--version"]):
        print("  " + subprocess.run(c, capture_output=True, text=True).stdout.splitlines()[0])
    print(f"{'benchmark':14s} {'arg':>9s} {'skite':>8s} {'gcc':>8s} {'clang':>8s} {'rust':>8s}  skite vs best")
    tmp = tempfile.mkdtemp()
    try:
        for name, arg in SIZES:
            if only and name not in only: continue
            if quick: arg = QUICK[name]
            exes = build(name, tmp)
            run_arg = fasta_file(arg, tmp) if name in FASTA_INPUT else arg
            ref = None
            for v, e in exes.items():
                h = digest([e, run_arg])
                if ref is None: ref = h
                elif h != ref: sys.exit(f"OUTPUT MISMATCH {name} {v}")
            t = {v: [] for v in exes}
            for _ in range(runs):
                for v, e in exes.items():
                    s = time.perf_counter()
                    subprocess.run([e, run_arg], stdout=subprocess.DEVNULL)
                    t[v].append((time.perf_counter() - s) * 1000)
            med = {v: statistics.median(x) for v, x in t.items()}
            best = min((m, v) for v, m in med.items() if v != "skite")
            r = med["skite"] / best[0]
            verdict = f"{1/r:.2f}x faster than {best[1]}" if r < 1 else f"{r:.2f}x SLOWER than {best[1]}"
            print(f"{name:14s} {arg:>9s} " + " ".join(f"{med[v]:8.0f}" for v in exes) + f"  {verdict}", flush=True)
    finally:
        shutil.rmtree(tmp)

main()
