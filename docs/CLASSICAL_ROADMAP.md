# Classical-cryptanalysis language roadmap

Working priorities from the owner's 2026-10-28 specification. These are goals, not claims of universal performance leadership. Compiler optimizations remain general; cipher algorithms and solvers belong in user programs and libraries. Do not expand this work into modern cryptography.

## Acceptance

- Matched algorithms, byte-identical results and declared GCC/Clang/Rust flags for any cross-language performance claim.
- Exact integer wrapping/traps and floating-point semantics. No silent reassociation or FMA contraction.
- Preserve the self-hosting fixed point; every optimization gets a relevant independent oracle, differential test or fuzzer.
- Record before/after commits and source/executable hashes, hardware/features, arguments, repeated samples and medians. Publish tradeoffs and missing tool/hardware coverage.
- Use small reviewed changes. Keep runtime, compiler cost, memory, startup, binary size and multicore scaling distinct.

## Current priority/status map

| Priority | Current status and next evidence |
| --- | --- |
| Runtime length facts | Candidate proves nonnegative constant predecessors from `i < len(a)`; 842 focused cases. See bench/length_facts. Runtime gain not established; terminal `a[len(a)-1]` remains a separate proof opportunity. |
| Masked stream loops / max-min / widths | Implemented in the integration baseline, with native dispatch and scalar fallback. Extend only from a reproduced uncovered shape; retain mixed-width alias regressions. |
| Unrolling / pipelining accumulators | Target real loop-carried kernels after profiling; exact reduction order and overflow behavior remain constraints. |
| Branchy byte state machines | Byte-lane character classes and one-bit state recurrences exist. Measure unsupported scanner shapes before changing lowering. |
| Periodic/constant modulus | Runtime periodic-index reduction and constant arithmetic exist. Extend with signed/unsigned zero, overflow, wrap and skipped-trap oracles. |
| Large immutable tables | Improve dense table layouts, optional SoA, cache behavior, prefetch and deterministic compile-time construction; measure memory as well as throughput. |
| Parallel search | Current `par` uses processes. Low-overhead shared-memory workers, atomics/scheduling and proved-disjoint stores remain future work. |
| Complete solver language | Modules/separate compilation, growable storage/arenas, first-class SoA, tagged unions and stronger compile-time table evaluation remain roadmap items. Existing structs are not tagged unions. |
| Alphabet/text primitives | Arbitrary alphabets, vector-friendly folding/classes and multi-pattern search should expose general semantics without hard-coded cipher recognition. |
| Targets | Current x86-64 uses AVX-512 with scalar fallback. AVX2 lowering and an actual ARM64 backend require separate implementation and hardware validation. |

Classical cipher coverage should include substitution, polyalphabetic ciphers, transposition, Playfair, Hill, running-key, crib/dictionary search, annealing/hill-climbing and n-gram scoring. Track the quality of the search algorithm separately from the generated-code comparison.

For arithmetic design: alphabet modulus 26 is the ring Z/26Z, not a field GF(26). Hill-style modular matrix operations must respect invertibility of determinants modulo 26. GF(2), bit matrices and rotates are separate general primitives; do not assume every nonzero residue modulo 26 has an inverse.

The shared review/integration protocol remains docs/TEAM_HANDOFF.md. Pending provider reviews must be stated as pending, and only a reviewed, tested head with passing CI should be merged.
