# Claude Opus independent review handoff

## Goal

Participate in a three-party language/backend engineering review: project owner sets requirements, GPT-6 integrates implementation and tests, Claude Opus conducts an independent optimization/correctness review and proposes measurable patches. Target: an original self-hosted language and native backend specialized for computational linguistics. We explicitly do **not** assume that a novel language can universally beat the best C/Rust/assembly. We aim for proved improvements on controlled linguistic workloads.

## Source of truth

The canonical artifact is this ZIP. The existing compiler is `ling0.c`. Previous initial stage snapshot: `bootstrap/ling0_s0.c`. Tests: `test.sh`, `tests/differential.c`, `tests/run_differential.sh`. Plans: `ARCHITECTURE.md`, `LANGUAGE_SPEC.md`, `SELF_HOSTING.md`, `KNOWN_LIMITATIONS.md`.

Current target is **Linux x86-64**, and the current compiler is temporarily written in C11. It emits raw native instructions and directly constructs ELF executable bytes; no LLVM, GCC, Cranelift, QBE, assembler, linker, or generated C is allowed in the language compilation path. GCC/Clang may be used solely to build the temporary C seed and to create independent reference baselines.

## Verified results before handoff

- Existing baseline test suite passes.
- 100 deterministic randomized programs tested with four argc settings, **400 independent C reference comparisons**, including confirmed pressure/spills.
- Optimizer passes: forward constant folding, backward DCE (straight-line SSA-like IR only).
- Registers: R8/R9/R10/R11/R13/R14/R15 pool; RAX/RCX arithmetic temps; RDX implicit idiv; R12 initial argc; stack spill slots `[rbp - 8*n]`.
- ELF64 direct output (ET_EXEC, PT_LOAD RX, PT_GNU_STACK NX); direct Linux syscalls for decimal output and exit.
- Static emitted machine code on `examples/operations.l0`: S0 381 B, S1 239 B. This is code-size evidence, NOT measured execution speed.

## Workstream 1: independent correctness audit (highest priority)

1. Audit `reg_imm`, `reg_move`, `reg_spill`, `load_value`, `consume`, `allocate_result`, and all x86 REX/ModRM forms byte by byte.
2. Analyze whether `load_value` can clobber other needed temporaries; whether repeated operand references (`x+x` and `x/x`) are safe; whether spill eviction and reload preserve all live values.
3. Audit trap semantics, signed overflow, `INT64_MIN`, constant-fold vs runtime mismatches.
4. Audit ELF segments, entrypoint, Linux x86-64 entry stack invariants, stack alignment and NX.
5. Identify minimal counterexamples and add executable regression tests, not merely speculative concerns.

## Workstream 2: self-hosting route

Specify the smallest **actually sufficient** language feature set to port the compiler into `.ln` without calling C libraries, LLVM or any other backend. Give an implementation order for:
- `if`/`while`/CFG/SSA merges
- function signatures, ABI, calls, stack frames, recursion
- memory model, typed pointers/slices/structs
- byte buffers, allocation, fd I/O syscalls
- modules, diagnostics, object/linker concerns
- lexer/parser/code generator rewrite
- fixed-point stage-2/stage-3 compiler equality tests

Reject any unsupported shortcuts such as calling the C compiler behind the scenes, emitting LLVM IR, bundling assembler, or using a VM as the final runtime.

## Workstream 3: native optimizer and linguistics

Recommend specific implemented or implementable passes with cost/benefit and proof conditions, e.g. constant-immediate selection, LEA fusion, efficient x86-64 signed division-by-constant, graph coloring vs linear scan, copy coalescing, live-range splitting, SIMD batching across independent cipher candidates, rolling n-gram state fusion, finite-state transducer lowering, cache-aware score table layout. Clearly separate syntax change, algorithm change, and backend/codegen change.

Our initial workloads: `Alphabet<29>` transformations, rolling 5-gram scoring, prefix/length models, finite-state tokenization and multi-candidate cryptanalysis. Show how domain semantics are represented in IR rather than hidden behind opaque functions. Require fair C/Rust comparisons, matching algorithm and a second best-of-ecosystem comparison.

## Deliverable format requested from Opus

1. **Verified defects:** file, function, minimal reproducer, expected vs actual, severity.
2. **Patch:** unified diff or replacement files written in C until `.ln` has necessary features. No Python-generated runtime or LLVM dependencies.
3. **Bench methodology and results:** environment, sample size, exact commands, outputs, variance and speedup measured on same algorithms. If not executed say "unmeasured hypothesis".
4. **Self-hosting plan:** staged and testable, with an acceptance gate for each stage.
5. **Prioritized next three changes** with time/complexity and dependency rationale.
6. **Open disagreements** to adjudicate with GPT-6 and owner, including objective tests to resolve them.

Be skeptical: test this compiler as if it were hostile low-level code. Preserve the existing working entrypoint and binary/ELF tests when proposing changes. Do not declare the language faster than C/Rust before measured evidence.
