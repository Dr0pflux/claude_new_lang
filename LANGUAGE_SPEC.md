# Linguistics-first systems language: design proposal, not implemented syntax

The language must be expressive enough for native OS programs but treat computational linguistics as a first-class workload. Standard systems primitives remain available; domain abstractions carry semantic information enabling optimizations impossible for a compiler that only sees opaque user calls.

## Proposed type families

- `ByteSlice`: length-tracked contiguous bytes, zero-copy view.
- `Utf8Text`: validated UTF-8 with explicitly chosen normalization; expensive conversions are visible.
- `Alphabet<N>`: distinct symbol set with `N` valid symbols; explicit encoding map, no implicit Unicode confusion.
- `Symbol<A>`: value constrained to alphabet A. For 29 runes, storage may use 5-bit packing for bandwidth or 8-bit lanes for SIMD. Compiler chooses per-use representation.
- `Text<A>`: packed or unpacked symbol stream with view semantics.
- `NGram<A,K>`: window state, explicit boundary and sentinel semantics.
- `FreqTable<A,K>` and `LogScore<A,K>`: specialized model representation with explicit precision and accumulated scoring order.
- `FST<A,B>`: finite-state transducer whose transitions can compile to direct indexed tables, branchless dispatch, or SIMD/batch kernels.

## Candidate semantic operators in HIR

`tokenize(text, rules)`, `normalize(text, scheme)`, `transduce(input, fst)`, `map_symbols(input, f)`, `rolling_ngram(text, K)`, `sum_log_scores(grams, model)`, `freq_count(text)`, `score_candidates(model, inputs)`, `search_patterns(text, patterns)`.

For every operator specify observable effects, aliasing, order, error semantics and precision. Optimizations must preserve them.

## Essential optimization example

Source-level intent (illustrative syntax):

```text
fn score(a: Text<Alphabet29>, key: Key<Alphabet29>, m: LogScore<Alphabet29,5>) -> f64 {
    return a.decrypt_cycle(key).ngrams(5).sum_log_scores(m)
}
```

Domain optimizer may eliminate the decrypted stream and n-gram arrays, use a 29-ary rolling index, and vectorize over distinct keys with parallel state. It may choose 8-bit lanes rather than bit-packed 5-bit storage if SIMD cost dominates bandwidth. It may specialize fixed key lengths and model layouts at compile time. These are choices requiring measured cost models.

## Hardware-first semantic contract

- Native CPU instructions (x86-64 first, AArch64 second), no interpreter.
- Zero-copy text views and preallocated arenas. No default mandatory garbage collector.
- Deterministic effect/alias system so fusions are legal.
- User-owned bounds and memory semantics; proof-based check elimination rather than globally deleting checks.
- Explicit precision of probability scores, quantization, rounding and summation order.
- Native multithreading and batched SIMD candidate processing, explicit CPU-feature dispatch.
- Separate correctness-preserving IR rewrites from domain-specific **algorithm substitutions**; compare both matched-algorithm and best-implementation baselines.

## First empirical workloads

1. 29-symbol stream conversion and modular alphabet transformations.
2. Rolling 3/4/5-gram lookup and log-probability summation over large model tables.
3. Dictionary/prefix-length scoring with fused candidate generation.
4. Finite-state morphological and tokenization pipelines.
5. Edit distance, substring search, and string transducer composition.
6. Cipher/key candidate evaluation at 1, 8, 64 and 1024-way batching.

Evaluate both compute-bound and memory-bound regimes. For short texts, vectorize across candidates. For long texts, choose adaptive tiling and memory layout. No speedup figure is asserted until verified with optimized Clang and Rust baselines.
