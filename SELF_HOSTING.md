# Self-hosting: exit the C bootstrap permanently

## End state

Compiler, type checker, optimizer, instruction encoder, ELF object generator, linker, standard library and their build scripts are authored in our new language and compiled with our *own* prior compiler. A C compiler is not required for a normal source build. An auditable seed binary is retained as a reproducibility and trust anchor, and no claim is made that initial provenance has magically ceased to involve C.

### Bootstrapping chain

**B0, current:** `skite.c` compiled by ordinary C compiler -> a working S0/S1 native ELF `.cock` compiler. The generated `.cock` executables do not depend on C.

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
