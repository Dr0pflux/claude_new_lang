# Native backend architecture and optimization program

## Existing v0.2 pipeline

`ASCII source -> recursive descent AST-as-IR -> single-block SSA-like value IDs -> constant fold + DCE -> direct x86-64 machine encoder -> direct ET_EXEC ELF writer`

- x86-64 encoding is authored byte-for-byte, including REX/ModRM, disp32 and branch patching.
- Register allocation: dynamic resident-value tracking over seven physical registers with use-count release and next-use victim selection. RAX/RCX/RDX are reserved for expression temporaries and division; R12 holds argc.
- Spills: RBP-relative memory. Constants and argc: rematerialized. ELF: fixed-address ET_EXEC, one RX PT_LOAD, non-executable PT_GNU_STACK. Process entry: Linux `_start`, direct `write`/`exit` syscalls.

## Target architecture

`Source -> typed HIR -> CFG MIR (SSA + typed effects) -> algebraic/domain optimizer -> target LIR -> register allocator -> scheduler -> independent encoder -> relocatable ELF objects -> original native linker -> executable`

Instruction selector: pattern-based target legalizer followed by target-specific peepholes and optional equality-saturation under a bounded budget. Source-level operators can lower to known kernels; important dynamic features include CPU capability dispatch, SIMD across text vs across candidates, and cache-aware allocation.

### Optimizations to implement in stages

**Next: control flow and self-hosting primitives.** CFG, branches/loops, phi/block arguments, calls/System V ABI, pointer/memory types, byte slices, allocation, syscall I/O. Ensure dominance/SSA validation.

**Then: proper allocator.** Live intervals over CFG, explicit fixed-register constraints, register classes, optimal copy coalescing, live-range splitting, rematerialization, spill slot reuse. Compare deterministic linear scan vs graph coloring, do not assume one wins universally.

**Then: machine-code target.** Table-driven instruction forms, register/memory operand selection, arithmetic immediates and strength reduction, LEA patterns, full REX/VEX/EVEX, relative relocation, safe PIC/PIE, caller/callee save correctness, instruction scheduling using target-specific uop and throughput cost models.

**Then: linguistics specialization.** Introduce packed symbol operations, fuse decrypt/transduce/ngram/score, specialize alphabet/cardinality, choose candidate batching and model lookup layout. Formalize precisions and boundaries to avoid false optimization.

**Then: independent linker and bootstrap.** ELF relocatable objects, symbols, section layout, relocation application and PIE. Port compiler into our language and verify stage-N compiler fixed point.

## Benchmark discipline

- Matching algorithms and outputs first. Report a second, separate comparison of best algorithms supported by each ecosystem.
- Clang `-O3 -march=native`, Rust `-C opt-level=3 -C target-cpu=native`, our compiler's performance switches. Consider PGO and LTO when used fairly.
- Repeated in-process kernel measurements with pre-generated inputs; avoid process-launch/syscall printing overhead.
- CPU model, frequency policy, compiler versions, flags, dataset size, cache behavior, vector instruction set and thread count always recorded.
- Profile cycles/op, instructions/op, branch misses, cache misses, allocations, bytes read/written, and robust distribution summaries.
- Verified output and independent randomized differential testing at every optimization stage.

## Safety/correctness constraints

Do not discard integer overflow rules, memory provenance, `div` traps, signedness, bounds checks, reproducibility, or numerical scoring order without changing the explicit language contract. These semantics control legal optimizations.
