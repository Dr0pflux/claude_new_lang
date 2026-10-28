# Native backend blueprint

## Non-negotiable boundaries

- Entirely independent instruction selection, register allocation, machine
  scheduling, encoding, relocation, ELF linking and runtime primitives.
- No LLVM, GCC, Cranelift, QBE, external assembler or external linker in the
  source-language compilation pipeline.
- Bootstrapping via C11 is acceptable. Later self-hosting is a separate goal.
- Target real existing ISAs. Initial target Linux x86-64 System V ABI. Second
  target Linux AArch64. Architecture-neutral IR and target-specific lowering.
- Begin with existing kernel ABI and ELF for immediate testability. Building a
  *new compiler backend* does not imply inventing a replacement CPU ISA or OS.
- Preserve reproducibility: deterministic encoders and explicit feature flags.

## Full staged pipeline

```text
Source
  -> UTF-8 lexer + grammar parser
  -> HIR: typed high-level IR / constrained linguistic operators
  -> MIR: control-flow graph, SSA values, explicit effects
  -> domain fusion + const evaluation + algebraic optimizer
  -> LIR: legal target instructions, explicit operand constraints
  -> register allocation + spill code + rematerialization
  -> dependency-aware instruction scheduling
  -> x86-64 encoder / (future) AArch64 encoder
  -> symbol resolution + relocations + custom ELF object/linker
  -> final native executable
```

### 1. Frontend and semantics

Establish unambiguous integer, overflow, pointer, memory, aliasing, error and
concurrency rules before aggressive optimization. A high-performance compiler
cannot legally reorder or fuse work without knowing those semantics.

For computational linguistics, eventually make `Alphabet<N>`, `Rune<N>`,
`NGram<K>`, `TextView`, packed token sequences and `ScoreModel` first-class
strongly typed concepts. This lets a higher-level optimizer choose between
lookup-table, rolling-hash, fused loop, SIMD-across-text and SIMD-across-
candidates implementations. Such operators will be added after the basic
machine-code backend is trustworthy.

### 2. IR and transformations

Use SSA + basic blocks with explicit control flow, phi values and effects.
Proof-based rewrites, dominator analysis, loop-invariant code motion, dead
store elimination, global value numbering, SCCP and superword-level
parallelism should be separate testable compiler passes. Preserve signed
arithmetic / trapping semantics during each rewrite.

### 3. Target-specific machine IR

Machine instructions have typed operands (physical register, virtual register,
memory, immediate, block label, symbol). x86-64 operand ties, implicit RAX/RDX
for `idiv`, byte-register constraints, caller/callee-saved sets and clobber
masks belong here, not in a generic optimizer.

The instruction encoder should be developed incrementally by tables of opcode
forms: legacy prefixes, REX, VEX, EVEX, ModR/M, SIB, displacement and
immediates. Verification is byte-level round-tripping and randomized
semantic execution, plus cross-check disassembly against independent tools.

### 4. Register allocation

Introduce linear scan with live intervals first, spilling under register
pressure, splitting, rematerialization and explicit SIMD register classes.
Then compare optimized linear scan against graph coloring on selected kernels.
Register allocation must consider target-specific copy cost, rematerializable
constants, call clobbers and fixed-register instructions.

### 5. Scheduling

Start with per-basic-block dependency DAGs, critical-path priorities and a
microarchitecture cost model. Model latency, reciprocal throughput, register
pressure, fusion and address generation. Maintain strict semantic checks
on loads, stores, aliasing, trapping and ordering.

### 6. Binary file generation and custom linking

The initial prototype writes one fixed-base ET_EXEC executable directly.
Move to independent `.o` files with sections, symbols, `R_X86_64_PC32`,
`R_X86_64_PLT32`, `R_X86_64_64`, GOT/PLT where required, debug metadata,
then PIE and a custom executable linker. Test with `readelf`, execute the
output, and use independent tools only to verify, never as a backend.

### 7. Runtime and standard library

Start freestanding and syscall-only. Later implement allocators, I/O, slices,
strings, threading, futex-based synchronization, diagnostics, CPU feature
dispatch and a language-level standard library. Avoid runtime dependencies
unless their costs are explicit and benchmarked.

## Milestones and acceptance gates

- **S0 (implemented here)**: parse expressions, SSA-like single-block IR,
  constant-fold, emit native bytes, write and run ELF, regression tests.
- **S1**: real register allocation with register/memory operand selection,
  compare optimized instruction counts and runtime against S0.
- **S2**: branches, loops, functions, System V calling convention and stack
  alignment. Differential-test against a reference interpreter written in C.
- **S3**: ELF64 relocatable object writer + independent linker + multi-file
  support. PIE and stack unwinding follow.
- **S4**: typed arrays, bounds-check elimination, SIMD encoder and loop
  vectorization. Add CPU feature detection and target-tuned dispatch.
- **S5**: linguistic operators and domain-aware fusion, including tokenization,
  modular alphabet transformations, rolling n-gram scoring, and candidate
  searches.
- **S6**: AArch64 backend, concurrency, stronger safety semantics, self-hosted
  compiler bootstrapping, debugging and tooling.

## Measurement protocol

Create matching C, Rust, and language implementations of the same algorithm.
Require identical output, arithmetic semantics, corpus, memory layout, inputs,
CPU feature set and thread count. Benchmark optimized C (`clang -O3 -march=native`)
and Rust (`--release`, target-cpu=native) on warmed machines with repeated
trials. Report median, percentile spread, cycles, instructions, cache misses,
branch misses and binary size. Distinguish compiler-optimization wins from
algorithm changes, then compare equal algorithms separately. Do not claim a
universal speed advantage.

For domain operators, test n-gram lookup throughput, corpus tokenization,
29-symbol modular transforms, substring search, ragged transposition and
candidate-scoring workloads, always with realistic input sizes.

## Primary reference specifications

- Intel 64 and IA-32 Software Developer's Manual:
  https://www.intel.com/content/www/us/en/developer/articles/technical/intel-sdm.html
- ELF generic ABI, loading and program headers:
  https://gabi.xinuos.com/elf/07-loading-intro.html
- AMD64 System V psABI: https://gitlab.com/x86-psABIs/x86-64-ABI
