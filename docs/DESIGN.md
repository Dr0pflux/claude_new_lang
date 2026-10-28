# Design


## Native backend blueprint

### Non-negotiable boundaries

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

### Full staged pipeline

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

### Milestones and acceptance gates

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

### Measurement protocol

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

### Primary reference specifications

- Intel 64 and IA-32 Software Developer's Manual:
  https://www.intel.com/content/www/us/en/developer/articles/technical/intel-sdm.html
- ELF generic ABI, loading and program headers:
  https://gabi.xinuos.com/elf/07-loading-intro.html
- AMD64 System V psABI: https://gitlab.com/x86-psABIs/x86-64-ABI

## Native backend architecture and optimization program

### Existing v0.2 pipeline

`ASCII source -> recursive descent AST-as-IR -> single-block SSA-like value IDs -> constant fold + DCE -> direct x86-64 machine encoder -> direct ET_EXEC ELF writer`

- x86-64 encoding is authored byte-for-byte, including REX/ModRM, disp32 and branch patching.
- Register allocation: dynamic resident-value tracking over seven physical registers with use-count release and next-use victim selection. RAX/RCX/RDX are reserved for expression temporaries and division; R12 holds argc.
- Spills: RBP-relative memory. Constants and argc: rematerialized. ELF: fixed-address ET_EXEC, one RX PT_LOAD, non-executable PT_GNU_STACK. Process entry: Linux `_start`, direct `write`/`exit` syscalls.

### Target architecture

`Source -> typed HIR -> CFG MIR (SSA + typed effects) -> algebraic/domain optimizer -> target LIR -> register allocator -> scheduler -> independent encoder -> relocatable ELF objects -> original native linker -> executable`

Instruction selector: pattern-based target legalizer followed by target-specific peepholes and optional equality-saturation under a bounded budget. Source-level operators can lower to known kernels; important dynamic features include CPU capability dispatch, SIMD across text vs across candidates, and cache-aware allocation.

### Optimizations to implement in stages

**Next: control flow and self-hosting primitives.** CFG, branches/loops, phi/block arguments, calls/System V ABI, pointer/memory types, byte slices, allocation, syscall I/O. Ensure dominance/SSA validation.

**Then: proper allocator.** Live intervals over CFG, explicit fixed-register constraints, register classes, optimal copy coalescing, live-range splitting, rematerialization, spill slot reuse. Compare deterministic linear scan vs graph coloring, do not assume one wins universally.

**Then: machine-code target.** Table-driven instruction forms, register/memory operand selection, arithmetic immediates and strength reduction, LEA patterns, full REX/VEX/EVEX, relative relocation, safe PIC/PIE, caller/callee save correctness, instruction scheduling using target-specific uop and throughput cost models.

**Then: linguistics specialization.** Introduce packed symbol operations, fuse decrypt/transduce/ngram/score, specialize alphabet/cardinality, choose candidate batching and model lookup layout. Formalize precisions and boundaries to avoid false optimization.

**Then: independent linker and bootstrap.** ELF relocatable objects, symbols, section layout, relocation application and PIE. Port compiler into our language and verify stage-N compiler fixed point.

### Benchmark discipline

- Matching algorithms and outputs first. Report a second, separate comparison of best algorithms supported by each ecosystem.
- Clang `-O3 -march=native`, Rust `-C opt-level=3 -C target-cpu=native`, our compiler's performance switches. Consider PGO and LTO when used fairly.
- Repeated in-process kernel measurements with pre-generated inputs; avoid process-launch/syscall printing overhead.
- CPU model, frequency policy, compiler versions, flags, dataset size, cache behavior, vector instruction set and thread count always recorded.
- Profile cycles/op, instructions/op, branch misses, cache misses, allocations, bytes read/written, and robust distribution summaries.
- Verified output and independent randomized differential testing at every optimization stage.

### Safety/correctness constraints

Do not discard integer overflow rules, memory provenance, `div` traps, signedness, bounds checks, reproducibility, or numerical scoring order without changing the explicit language contract. These semantics control legal optimizations.

## Self-hosting: exit the C bootstrap permanently

### End state

Compiler, type checker, optimizer, instruction encoder, ELF object generator, linker, standard library and their build scripts are authored in our new language and compiled with our *own* prior compiler. A C compiler is not required for a normal source build. An auditable seed binary is retained as a reproducibility and trust anchor, and no claim is made that initial provenance has magically ceased to involve C.

### Bootstrapping chain

**B0, current:** `skite.c` compiled by ordinary C compiler -> a working S0/S1 native ELF `.ck` compiler. The generated `.ck` executables do not depend on C.

**B1, expressive core:** implement language features allowing compiler source code: primitive signed/unsigned ints, fixed-width bitwise ops, static arrays, dynamic slices, pointers and references, structs, explicit memory allocation, direct syscalls, conditionals, loops, functions/calls, error reporting, string/byte literals. Preserve deterministic arithmetic rules. Introduce proper CFG and block parameters/phi semantics in IR.

**B2, first language-authored compiler:** port frontend, IR, native instruction emitter, ELF writer into `compiler/*.ln`. C bootstrap must be able to compile the restricted language subset used by that port. Retain S0 as a fallback; no C-to-machine generated program pipeline may be introduced.

**B3, fixed-point compiler builds:**

1. Compile language-authored compiler `compiler/*.ln` using stage-0 compiler binary -> stage-1 binary.
2. Compile same sources using stage-1 -> stage-2 binary.
3. Compile same sources using stage-2 -> stage-3 binary.
4. Verify stage-2 and stage-3 byte identity (if deterministic builds and no metadata differences), otherwise compare normalized code/sections and check why differing.
5. Execute identical correctness and adversarial test suites with each stage, compare machine bytes and output semantics.

**B4, C-free normal workflow:** use stage-2/3 compiler as the default. Preserve source, seed binary, deterministic build recipe, source hashes, ELF section hashes, and provenance.

**B5, fully self-authored ecosystem:** port internal standard library, linker, debugger support, reference analyzer/test runners where useful. Build with the language compiler, not GCC/LLVM; independent verification tools like `objdump`, `readelf` remain permitted.

### Critical separation

- Self-hosting is about the implementation language/build chain, not the generated machine code's theoretical speed.
- Code-generation backends remain wholly ours at every stage.
- Using an existing OS ABI, Linux syscalls and processor documentation is not outsourcing our backend.
- Even after self-hosting, no universal claim of beating hand-written assembly, optimized C or Rust on every workload is technically justified.

### Status (v0.3)

- **G1 passed:** CFG, `if`/`while`, comparisons/booleans, mutable locals. Acceptance: control-flow fuzz vs an independent interpreter (see README).
- **G3 partially done (v0.4):** byte/typed arrays, file input (mmap), buffered output, bounds safety.
- **G2 passed (v0.5):** functions, recursion, array parameters, an internal calling convention; fuzzed against a frame-accurate interpreter.
- **Next:** file output, an allocator and structs (to finish G3), then port the lexer (G4).

### Required B1 order

1. CFG, `if`, `while`, comparison/boolean expressions, mutable local bindings.
2. Functions, explicit ABI-conforming calls, recursion, globals, stack objects.
3. Byte arrays, pointer arithmetic, slice bounds and UTF-8 byte literals.
4. File descriptor read/write/open/close, allocation, memory copy.
5. Module interfaces and deterministic cross-file resolution.
6. Port the lexer/tokenizer as the first real compiler self-hosting component.
7. Port parser, optimizer, encoder and ELF writer; fixed-point rebuild.

### Semantic risks

Settle wrap/trap behavior per integer type; aliasing guarantees; pointer provenance; safe vs unsafe memory; uninitialized memory; lifetime rules; compile-time integer overflow and signed division; code/data separation; deterministic floating-point reductions; Unicode normalization. Incorrect specifications will make optimizations unsound and break the self-hosted compiler.

## Linguistics-first systems language: design proposal, not implemented syntax

The language must be expressive enough for native OS programs but treat computational linguistics as a first-class workload. Standard systems primitives remain available; domain abstractions carry semantic information enabling optimizations impossible for a compiler that only sees opaque user calls.

### Proposed type families

- `ByteSlice`: length-tracked contiguous bytes, zero-copy view.
- `Utf8Text`: validated UTF-8 with explicitly chosen normalization; expensive conversions are visible.
- `Alphabet<N>`: distinct symbol set with `N` valid symbols; explicit encoding map, no implicit Unicode confusion.
- `Symbol<A>`: value constrained to alphabet A. For 29 runes, storage may use 5-bit packing for bandwidth or 8-bit lanes for SIMD. Compiler chooses per-use representation.
- `Text<A>`: packed or unpacked symbol stream with view semantics.
- `NGram<A,K>`: window state, explicit boundary and sentinel semantics.
- `FreqTable<A,K>` and `LogScore<A,K>`: specialized model representation with explicit precision and accumulated scoring order.
- `FST<A,B>`: finite-state transducer whose transitions can compile to direct indexed tables, branchless dispatch, or SIMD/batch kernels.

### Candidate semantic operators in HIR

`tokenize(text, rules)`, `normalize(text, scheme)`, `transduce(input, fst)`, `map_symbols(input, f)`, `rolling_ngram(text, K)`, `sum_log_scores(grams, model)`, `freq_count(text)`, `score_candidates(model, inputs)`, `search_patterns(text, patterns)`.

For every operator specify observable effects, aliasing, order, error semantics and precision. Optimizations must preserve them.

### Essential optimization example

Source-level intent (illustrative syntax):

```text
fn score(a: Text<Alphabet29>, key: Key<Alphabet29>, m: LogScore<Alphabet29,5>) -> f64 {
    return a.decrypt_cycle(key).ngrams(5).sum_log_scores(m)
}
```

Domain optimizer may eliminate the decrypted stream and n-gram arrays, use a 29-ary rolling index, and vectorize over distinct keys with parallel state. It may choose 8-bit lanes rather than bit-packed 5-bit storage if SIMD cost dominates bandwidth. It may specialize fixed key lengths and model layouts at compile time. These are choices requiring measured cost models.

### Hardware-first semantic contract

- Native CPU instructions (x86-64 first, AArch64 second), no interpreter.
- Zero-copy text views and preallocated arenas. No default mandatory garbage collector.
- Deterministic effect/alias system so fusions are legal.
- User-owned bounds and memory semantics; proof-based check elimination rather than globally deleting checks.
- Explicit precision of probability scores, quantization, rounding and summation order.
- Native multithreading and batched SIMD candidate processing, explicit CPU-feature dispatch.
- Separate correctness-preserving IR rewrites from domain-specific **algorithm substitutions**; compare both matched-algorithm and best-implementation baselines.

### First empirical workloads

1. 29-symbol stream conversion and modular alphabet transformations.
2. Rolling 3/4/5-gram lookup and log-probability summation over large model tables.
3. Dictionary/prefix-length scoring with fused candidate generation.
4. Finite-state morphological and tokenization pipelines.
5. Edit distance, substring search, and string transducer composition.
6. Cipher/key candidate evaluation at 1, 8, 64 and 1024-way batching.

Evaluate both compute-bound and memory-bound regimes. For short texts, vectorize across candidates. For long texts, choose adaptive tiling and memory layout. No speedup figure is asserted until verified with optimized Clang and Rust baselines.
