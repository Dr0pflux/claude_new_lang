# Claude Opus review of ling0 v0.2 → v0.2.1 patch

Legend: **[T]** = tested here; **[I]** = by inspection; **[H]** = hypothesis, not measured.
Environment: Intel Xeon @ 2.10 GHz (2 vCPU, VM), Linux 6.18, gcc + clang 18. Patch: `opus-review-v0.2.1.patch` (applies with `patch -p1` to the v0.2 zip; verified on a clean extract).

## 1. Defects

| # | Sev | Where | Repro | Expected | Actual | Status |
|---|---|---|---|---|---|---|
| D1 | High (hostile input) | `unary`/`atom`/`expr` recursion | `return ((((…1…))));` 200k parens, or 1M `-` signs | diagnostic | **compiler SIGSEGV (rc 139)** [T] | **Fixed**: `MAX_DEPTH=256` on `unary()`; regression in `test.sh` (fails on old binary [T]) |
| D2 | Medium (semantics) | `optimize` fold+DCE | (a) `let x = 1/0; return 5;` (b) `let x = argc()/0; return 5;` (c) `return argc()/0;` | one consistent rule | (a) compile error, (b) compiles, prints 5, (c) compiles, SIGFPE [T] | **Open — needs owner decision** (§6) |
| D3 | Low (perf) | `reg_imm` | any literal | short encoding | always 10-byte `movabs`; no ALU-immediate forms [T] | **Fixed** |
| D4 | Low (perf) | `allocate_result` | `examples/operations.cock` | value stays in RAX | `mov r8,rax; mov rax,r8` round-trip for single-use values [T] | **Fixed** (RAX forwarding) |
| D5 | Low (perf) | `generate` prologue | any program w/o spills | no frame | `push rbp; mov rbp,rsp; sub rsp,0` (11 B) [T] | Open |
| D6 | Low (hardening) | `write_elf` | any output | headers not executable | single R+X `PT_LOAD` maps ELF header/phdrs executable [T] | Open — split R / RX when data sections arrive |
| D7 | Low (input integrity) | `read_source` | `return 7; }\0 garbage` | reject | garbage after NUL silently ignored [T] | **Fixed** + regression |
| D8 | Low (test gap) | `tests/differential.c` | — | — | locals only reference `n`; no `x/x`, negative divisors, operand sharing, or imm boundaries [I] | **Fixed**: `tests/dag_fuzz.c` |
| D9 | Low (forward risk) | entry | — | — | after `push rbp`, `rsp ≡ 8 (mod 16)`; harmless today (no calls), ABI violation once calls exist [I] | Gate G2 |
| D10 | Process | zip | — | — | prebuilt `ling0` binary shipped; unauditable, build scripts already rebuild [I] | Drop from canonical zip |

**Audited, no defect found:** all REX/ModRM/disp32 forms (byte-checked vs `objdump`) [T]; `x+x`, `x/x`, spill eviction/reload [T: 8,000 DAG-fuzz comparisons on the original, ~74% of programs spilling]; `INT64_MIN` print [T]; constant fold vs runtime agreement [T: 1,000 programs with `argc()` replaced by `1`, all fully folded, all equal]; ELF header fields, entry, `PT_GNU_STACK` RW [T].

## 2. Patch (v0.2.1)

- `ling0.c`: D1 depth bound; D7 NUL rejection; `reg_imm` uses `mov r32,imm32` (zero-ext) / `mov r/m64,simm32` / `movabs`; `add/sub/imul rax,imm8|imm32`; commutative swap puts constants into the immediate slot; RAX forwarding when a value's single use is operand `a` of the next emitting instruction (commutative swap applied when it is operand `b`).
- `test.sh`: D1, D7 regressions; immediate-boundary program (values from an independent Python oracle; old binary produces the same values [T]).
- `tests/dag_fuzz.c`, `tests/run_dag_fuzz.sh`: DAG fuzzer, wired into `make test`.
- Existing tests untouched and passing.

**Evidence for patched compiler [T]:** `make test` pass; `run_differential.sh 250` → 1,000/1,000; DAG fuzz seeds 1–8 (old generator) 12,800/12,800 and seeds 11–16 (with boundary constants) 12,000/12,000; ASan+UBSan build (gcc) 1,200/1,200 + D1 repro clean; clang `-Werror` clean.

## 3. Measurements

| Input | v0.2 code bytes | v0.2.1 | Δ |
|---|---:|---:|---:|
| examples/argc.cock | 187 | 151 | −19.3% |
| examples/arith.cock | 137 | 132 | −3.6% |
| examples/minimum.cock | 145 | 145 | 0 |
| examples/negative.cock | 137 | 134 | −2.2% |
| examples/operations.cock | 239 | 178 | −25.5% |
| 300 DAG-fuzz programs (seed 31), total | 200,784 | 168,181 | −16.2% |

Code size only [T]. **Runtime: unmeasured.** These programs run in microseconds and are dominated by `execve`, so a timing result would just measure noise. Runtime claims must wait for loops (G1).

**Methodology for runtime once loops exist:** in-process kernel with ≥10⁸ iterations; `taskset -c N`, performance governor, turbo state recorded; `perf stat -r 30 -e cycles,instructions,branch-misses,cache-misses`; report median + IQR; same algorithm in C (`clang -O3 -march=native`) and Rust (`opt-level=3`, `target-cpu=native`), output checksums must match; separate "best-of-ecosystem" table. Use a dedicated bare-metal host, not this VM.

## 4. Self-hosting gates

| Gate | Features | Acceptance test |
|---|---|---|
| G1 | CFG, `if`/`while`, comparisons, mutable locals, block params | DAG fuzzer extended with loops vs a C oracle; 10k programs, 0 mismatches; SSA/dominance verifier runs on every IR |
| G2 | functions, SysV calls, recursion, callee-saved regs | call/recursion fuzz; every call site asserts `rsp%16==0` (test callee executes `movaps [rsp],xmm0`); deep recursion terminates by guard page, not corruption |
| G3 | u8/i32/u64, pointers, slices with bounds checks, structs, `read/write/open/close/mmap` | `.cock` implementations of `cat`, `wc -c`, hexdump; byte-identical output to coreutils on a 1 GiB randomized corpus |
| G4 | lexer ported | `.cock` lexer token stream == C lexer over all test sources + fuzz corpus |
| G5 | parser, IR, regalloc, encoder, ELF writer ported | stage1→stage2→stage3; `sha256(stage2)==sha256(stage3)`; all suites pass on every stage |

## 5. Next three changes (priority order)

1. **CFG + linear-scan allocator with fixed-register constraints** (G1/G2). ~2–3 weeks. Prerequisite for every loop-bound linguistic kernel; the current next-use allocator has no answer for back edges. [H on perf]
2. **Signed division/modulo by constant → multiply-high + shifts** (Granlund–Montgomery). ~3 days. `idiv r64` is tens of cycles on many x86 cores vs ~3–4 for `imul`. `% 29` is on the hot path of `Alphabet<29>`. Proof condition: exact for all i64 dividends; verify with boundary + random dividends for every divisor 2..2¹⁶ against C. [H: speedup unmeasured]
3. **Rolling 5-gram index without modulo** for `Alphabet<29>`: `idx = (idx − s_old·29⁴)·29 + s_new` (29⁵ = 20,511,149 entries: 41 MB as i16 or 82 MB as f32, so it will miss L3). Batch K candidates per text position to get independent loads in flight (memory-level parallelism); also compare an i16-quantized table. Needs G1–G3. [H: likely memory-bound; must be measured against C with the same algorithm]

## 6. Open disagreements (need owner adjudication)

1. **D2 trap semantics.** Option A: div/mod is a *trapping effect*, never removed by DCE unless the divisor is proven ≠0 and (≠−1 or dividend ≠ INT64_MIN), and a literal-zero divisor is always a compile error. Option B: traps are UB-free "may elide if dead". **I recommend A** (predictable, safe). Objective test: programs (a)(b)(c) above must yield the spec-defined result.
2. README says constant division by zero is "rejected at compile time"; in fact only when *both* operands are constant (`argc()/0` compiles). Fix the doc or implement A.
3. "Faster than C/Rust": claim only per workload, after §3 methodology. A universal claim isn't testable.
