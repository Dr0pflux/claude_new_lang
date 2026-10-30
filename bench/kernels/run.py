#!/usr/bin/env python3
"""skite vs gcc/clang/rustc on the domain kernels: two arithmetic kernels
(bench/kernels) and the Vigenere solver, serial and par (bench/vigenere).

Every program implements the same algorithm; a run is rejected unless all
binaries print byte-identical output. Runs are interleaved (skite, gcc, clang,
rust, skite, ...) and the median wall time is reported.

usage: bench/kernels/run.py [RUNS] [NAME...]
"""
import os, subprocess, sys, tempfile, time, statistics, hashlib, shutil

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SKITE = os.path.join(ROOT, "skite")
SKITE_LLVM = os.path.join(ROOT, "tools", "skite-llvm")
B = os.path.join(ROOT, "bench")
V = os.path.join(B, "vigenere")
D = os.path.join(V, "data")

def big_cipher(tmp):
    # 4,000 texts: the 400 held-out regression texts repeated 10 times
    p = os.path.join(tmp, "cipher4000.txt")
    with open(os.path.join(D, "cipher.txt"), "rb") as f: s = f.read()
    with open(p, "wb") as f: f.write(s * 10)
    return p

def benches(tmp):
    quad = os.path.join(D, "quad.bin"); c4k = big_cipher(tmp)
    return [
        ("ngram29",    os.path.join(B, "kernels", "ngram29"),    [], "c"),
        ("vigenere29", os.path.join(B, "kernels", "vigenere29"), [], "c"),
        ("textscan",   os.path.join(B, "kernels", "textscan"),   [], "c"),
        ("sieve", os.path.join(B, "kernels", "sieve"), [], "c"),
        ("collatz", os.path.join(B, "kernels", "collatz"), [], "c"),
        ("gcdsum", os.path.join(B, "kernels", "gcdsum"), [], "c"),
        ("hashmix", os.path.join(B, "kernels", "hashmix"), [], "c"),
        ("prefixsum", os.path.join(B, "kernels", "prefixsum"), [], "c"),
        ("matmul", os.path.join(B, "kernels", "matmul"), [], "c"),
        ("polyeval", os.path.join(B, "kernels", "polyeval"), [], "c"),
        ("intsort", os.path.join(B, "kernels", "intsort"), [], "c"),
        ("divmod", os.path.join(B, "kernels", "divmod"), [], "c"),
        ("nqueens", os.path.join(B, "kernels", "nqueens"), [], "c"),
        ("histogram", os.path.join(B, "kernels", "histogram"), [], "c"),
        ("wordcount", os.path.join(B, "kernels", "wordcount"), [], "c"),
        ("strsearch", os.path.join(B, "kernels", "strsearch"), [], "c"),
        ("ngramhash", os.path.join(B, "kernels", "ngramhash"), [], "c"),
        ("editdist", os.path.join(B, "kernels", "editdist"), [], "c"),
        ("caseconv", os.path.join(B, "kernels", "caseconv"), [], "c"),
        ("vig-solver", os.path.join(V, "vig"),  [quad, c4k], "c"),
        ("vig-par",    os.path.join(V, "vigp"), [quad, c4k], "omp"),
    ]

def build(name, base, kind, tmp):
    out = {}
    def run(cmd):
        subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    exe = os.path.join(tmp, name)
    run([SKITE, base + ".ck", exe + ".skite"]); out["skite"] = exe + ".skite"
    if shutil.which("clang"):   # the LLVM backend (tools/skite-llvm)
        try:
            run([SKITE_LLVM, base + ".ck", exe + ".skite-llvm"]); out["skite-llvm"] = exe + ".skite-llvm"
        except subprocess.CalledProcessError:
            print(f"  (skite-llvm build of {name} failed; skipped)", file=sys.stderr)
    extra = {"c": [], "cm": ["-lm"], "omp": ["-fopenmp"]}[kind]
    for cc in ("gcc", "clang"):
        try:
            run([cc, "-O3", "-march=native", "-ffp-contract=off", base + ".c", "-o", exe + "." + cc] + extra)
            out[cc] = exe + "." + cc
        except subprocess.CalledProcessError:
            print(f"  ({cc} build of {name} failed; skipped)", file=sys.stderr)
    if os.path.exists(base + ".rs"):
        run(["rustc", "-C", "opt-level=3", "-C", "target-cpu=native", "-C", "codegen-units=1",
             "-C", "panic=abort", base + ".rs", "-o", exe + ".rust"])
        out["rust"] = exe + ".rust"
    return out

def main():
    runs = int(sys.argv[1]) if len(sys.argv) > 1 else 7
    only = set(sys.argv[2:])
    print(f"cpu: {open('/proc/cpuinfo').read().split('model name')[1].split(':')[1].splitlines()[0].strip()}, {os.cpu_count()} cpus")
    for c in (["gcc", "--version"], ["clang", "--version"], ["rustc", "--version"]):
        print(subprocess.run(c, capture_output=True, text=True).stdout.splitlines()[0])
    tmp = tempfile.mkdtemp()
    try:
        rows = []
        for name, base, args, kind in benches(tmp):
            if only and name not in only: continue
            exes = build(name, base, kind, tmp)
            ref = None
            for v, e in exes.items():
                h = hashlib.md5(subprocess.run([e] + args, capture_output=True).stdout).hexdigest()
                if ref is None: ref = h
                elif h != ref: sys.exit(f"OUTPUT MISMATCH {name} {v}")
            t = {v: [] for v in exes}
            for _ in range(runs):
                for v, e in exes.items():
                    s = time.perf_counter()
                    subprocess.run([e] + args, stdout=subprocess.DEVNULL)
                    t[v].append((time.perf_counter() - s) * 1000)
            med = {v: statistics.median(x) for v, x in t.items()}
            best = min((m, v) for v, m in med.items() if not v.startswith("skite"))
            cells = "  ".join(f"{v} {med[v]:7.1f}" for v in exes)
            ratio = f"skite/best-other = {med['skite']/best[0]:.3f} ({best[1]})"
            if "skite-llvm" in med: ratio += f"  skite-llvm/best-other = {med['skite-llvm']/best[0]:.3f}"
            print(f"{name:11s} {cells}   {ratio}", flush=True)
            rows.append((name, med))
    finally:
        shutil.rmtree(tmp)

main()
