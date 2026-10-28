# Vigenère solver benchmark

Three implementations of the **same algorithm**, line for line, all producing byte-identical output: `vig.ck` (skite), `vig.c` (C) and `vig.rs` (Rust).

## Algorithm

For each ciphertext (A–Z, one per line):
1. **Period:** for p = 1..20, compute the column index of coincidence; choose the smallest p within 90% of the best.
2. **Initial key:** for each column, the shift that maximizes correlation with English unigram frequencies.
3. **Refine:** quadgram coordinate ascent (up to 4 passes). For each key position and each of 26 letters, rescore only the 4-gram windows touching that column (delta scoring), and keep the best letter.
4. **Output:** print the key; the final line is the summed quadgram score of all decryptions.

## Data

`make_data.py` builds the table and test set from the NLTK Gutenberg corpus (`gutenberg.zip` from the nltk_data GitHub repository):
- **Quadgram table** (26⁴ × i16 log10 scores ×100): trained on 17 books.
- **Test set:** passages of 100–600 letters from 3 *held-out* books (Persuasion, The Man Who Was Thursday, Moby Dick), with random keys of length 2–20.

`data/` holds a 400-text set for regression tests; the benchmark uses 4,000 texts (seed 7).

## Run

```sh
python3 make_data.py /path/to/gutenberg /tmp/vigbig 4000 7
python3 ../kernels/run.py 11 vig-solver vig-par   # uses data/ (400 texts x 10)
```

`bench/kernels/run.py` rejects the run unless all binaries produce identical output.

## Results (Intel Xeon @ 2.10 GHz, 2-vCPU VM; median of 21 interleaved runs)

| | skite v0.4 | gcc 13.3 -O3 -march=native | clang 18 -O3 -march=native | rustc 1.97 -O3 native |
|---|---:|---:|---:|---:|
| 4,000 texts | **487 ms** (min 464) | 545 ms (min 515) | 573 ms (min 530) | 764 ms (min 729) |
| memory safety | all 67 checks proven, 0 executed | none | runtime checks | runtime checks |

Accuracy, identical for all four: 87.4% exact keys, and **92.6% equivalent** (a key that repeats the true key decrypts identically).

**Where the win comes from (same source algorithm):**
1. **Periodic-index strength reduction.** `i % p` inside the IoC and decryption loops becomes a wrapping counter, so there is no `idiv`. gcc and clang keep a hardware divide (~25–40 cycles) per character.
2. **Proven bounds.** skite is safe like Rust but pays nothing for it in the hot loop.
3. **Code quality at least matching gcc** in the scoring loop: folded address offsets and registers for all hot values.

**Not measured:** AZDecrypt (a Windows binary; it can't run in this Linux environment). It uses different algorithms (higher-order n-grams, simulated annealing), so a fair comparison needs a matched-algorithm port, which is planned.
