#!/usr/bin/env python3
"""Keep trapping short-circuit bounds expressions inside the original loop test."""
import argparse
import pathlib
import subprocess
import tempfile


CASES = [
    # The false first conjunct must skip 42 / z when z is zero.
    ("skip_zero_divisor", """fn main(){
      let a=alloc<i64>(4); let n=argc()-1; let z=argc()-1;
      let mut i=argc(); let mut j=0; let mut s=0;
      while i<n && j<42/z { s+=a[j+1]; i+=1; j+=1; }
      print(s);
    }""", 0, b"0\n"),
    # Signed MIN / -1 traps only if the RHS conjunct is evaluated.
    ("skip_signed_overflow", """fn main(){
      let a=alloc<i64>(4); let n=argc()-1; let d=1-2*argc();
      let mut i=argc(); let mut j=0; let mut s=0;
      while i<n && j<(-9223372036854775807-1)/d { s+=a[j+1]; i+=1; j+=1; }
      print(s);
    }""", 0, b"0\n"),
    ("evaluate_zero_divisor", """fn main(){
      let a=alloc<i64>(4); let n=argc()+1; let z=argc()-1;
      let mut i=argc(); let mut j=0; let mut s=0; print(7);
      while i<n && j<42/z { s+=a[j+1]; i+=1; j+=1; }
      print(s);
    }""", 136, b"7\n"),
    ("evaluate_signed_overflow", """fn main(){
      let a=alloc<i64>(4); let n=argc()+1; let d=1-2*argc();
      let mut i=argc(); let mut j=0; let mut s=0; print(8);
      while i<n && j<(-9223372036854775807-1)/d { s+=a[j+1]; i+=1; j+=1; }
      print(s);
    }""", 136, b"8\n"),
    ("safe_single_bound", """fn main(){
      let a=alloc<i64>(8); let mut k=0; while k<8 { a[k]=k+1; k+=1; }
      let n=argc()+3; let mut i=0; let mut s=0;
      while i<n { s+=a[i+1]; i+=1; }
      print(s);
    }""", 0, b"14\n"),
    ("safe_two_bounds_and_counter", """fn main(){
      let a=alloc<i64>(16); let mut q=0; while q<16 { a[q]=q+1; q+=1; }
      let n=argc()+3; let m=argc()+4;
      let mut i=0; let mut j=0; let mut c=0; let mut s=0;
      while i<n && j<m { s+=a[j+1]+a[c+1]; i+=1; j+=1; c+=1; }
      print(s); print(c);
    }""", 0, b"28\n4\n"),
]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--compiler", default="./skite")
    args = parser.parse_args()
    compiler = str(pathlib.Path(args.compiler).resolve())
    with tempfile.TemporaryDirectory(prefix="skite-bv-guard-") as tmp:
        root = pathlib.Path(tmp)
        for name, text, expected_status, expected_out in CASES:
            source, binary = root / f"{name}.ck", root / name
            source.write_text(text)
            subprocess.run([compiler, str(source), str(binary)], check=True,
                           timeout=10, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            run = subprocess.run([str(binary)], timeout=2,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            if run.returncode != expected_status or run.stdout != expected_out:
                raise SystemExit(
                    f"{name}: status={run.returncode}, stdout={run.stdout!r}; "
                    f"expected status={expected_status}, stdout={expected_out!r}; "
                    f"stderr={run.stderr!r}"
                )
    print(f"bv_guard_traps: {len(CASES)} cases passed")


if __name__ == "__main__":
    main()
