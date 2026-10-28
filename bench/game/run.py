#!/usr/bin/env python3
"""Benchmarks Game suite: skite vs gcc, clang and rustc on the same algorithms.

Each program exists as NAME.ck, NAME.c and NAME.rs. A run is rejected
unless every binary prints byte-identical output. Runs are interleaved and
the median wall time is reported.

usage: bench/game/run.py [RUNS] [NAME...]
"""
import hashlib, os, shutil, statistics, subprocess, sys, tempfile, time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SKITE = os.path.join(ROOT, "skite")
# name -> argument (standard Benchmarks Game sizes where they run in ~1 s)
SIZES = [("nbody", "50000000"), ("spectralnorm", "5500"), ("mandelbrot", "16000"),
         ("fannkuchredux", "12"), ("fasta", "25000000"), ("binarytrees", "21")]
QUICK = {"nbody": "5000000", "spectralnorm": "3000", "mandelbrot": "4000",
         "fannkuchredux": "11", "fasta": "2500000", "binarytrees": "19"}
COMPILE_TIMEOUT = 120
EXEC_TIMEOUT = 300

def sh(cmd):
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                   timeout=COMPILE_TIMEOUT)

def execute(exe, arg, stdout=subprocess.PIPE):
    return subprocess.run([exe, arg], stdout=stdout, stderr=subprocess.PIPE,
                          check=True, timeout=EXEC_TIMEOUT)

def build(name, tmp):
    src = os.path.join(HERE, name)
    exe = os.path.join(tmp, name)
    sh([SKITE, src + ".ck", exe + ".skite"])
    out = {"skite": exe + ".skite"}
    compilers = {
        "gcc": ["gcc", "-O3", "-march=native", src + ".c", "-o", exe + ".gcc", "-lm"],
        "clang": ["clang", "-O3", "-march=native", src + ".c", "-o", exe + ".clang", "-lm"],
        "rust": ["rustc", "-C", "opt-level=3", "-C", "target-cpu=native", "-C", "codegen-units=1",
                 "-C", "panic=abort", src + ".rs", "-o", exe + ".rust"],
    }
    for name, cmd in compilers.items():
        try:
            sh(cmd)
            out[name] = exe + "." + name
        except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
            print(f"  ({name} unavailable or build failed; skipped: {exc})", file=sys.stderr)
    return out

def main():
    args = sys.argv[1:]
    quick = "--quick" in args
    args = [a for a in args if a != "--quick"]
    runs = 5
    if args:
        try:
            runs = int(args[0])
        except ValueError:
            pass
        else:
            args = args[1:]
            if runs <= 0:
                sys.exit("RUNS must be a positive integer")
    only = set(args)
    unknown = only - {name for name, _ in SIZES}
    if unknown:
        sys.exit(f"unknown benchmark name(s): {', '.join(sorted(unknown))}")
    cpu = open("/proc/cpuinfo").read().split("model name")[1].split(":")[1].splitlines()[0].strip()
    print(f"cpu: {cpu}, {os.cpu_count()} cpus; median of {runs} interleaved runs, wall ms")
    for c in (["gcc", "--version"], ["clang", "--version"], ["rustc", "--version"]):
        try:
            p = subprocess.run(c, capture_output=True, text=True, check=True, timeout=10)
            version = p.stdout.splitlines()
            print("  " + (version[0] if version else f"{c[0]}: unavailable"))
        except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired):
            print(f"  {c[0]}: unavailable")
    print(f"{'benchmark':14s} {'arg':>9s} {'skite':>8s} {'gcc':>8s} {'clang':>8s} {'rust':>8s}  skite vs best")
    tmp = tempfile.mkdtemp()
    try:
        for name, arg in SIZES:
            if only and name not in only: continue
            if quick: arg = QUICK[name]
            exes = build(name, tmp)
            ref = None
            for v, e in exes.items():
                try:
                    h = hashlib.md5(execute(e, arg).stdout).hexdigest()
                except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
                    sys.exit(f"EXECUTION FAILED {name} {v}: {exc}")
                if ref is None: ref = h
                elif h != ref: sys.exit(f"OUTPUT MISMATCH {name} {v}")
            t = {v: [] for v in exes}
            for _ in range(runs):
                for v, e in exes.items():
                    s = time.perf_counter()
                    try:
                        execute(e, arg, stdout=subprocess.DEVNULL)
                    except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
                        sys.exit(f"TIMED EXECUTION FAILED {name} {v}: {exc}")
                    t[v].append((time.perf_counter() - s) * 1000)
            med = {v: statistics.median(x) for v, x in t.items()}
            cells = " ".join(f"{med[v]:8.0f}" if v in med else f"{'-':>8s}"
                              for v in ("skite", "gcc", "clang", "rust"))
            competitors = [(m, v) for v, m in med.items() if v != "skite"]
            if competitors:
                best = min(competitors)
                r = med["skite"] / best[0]
                verdict = f"{1/r:.2f}x faster than {best[1]}" if r < 1 else f"{r:.2f}x SLOWER than {best[1]}"
            else:
                verdict = "no comparator available"
            print(f"{name:14s} {arg:>9s} {cells}  {verdict}", flush=True)
    finally:
        shutil.rmtree(tmp)

if __name__ == "__main__":
    main()
