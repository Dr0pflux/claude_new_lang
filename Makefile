# skite is written in skite (skite.cock). bootstrap/skite-seed is a prebuilt skite
# executable, so building needs no C compiler, assembler, linker or libc.
# bootstrap/skite.c is the original C seed, kept only for auditing the chain.
CORPUS ?= gutenberg
.PHONY: all selfcheck test fuzz bench runtime vigenere seed-from-c clean
all: skite
skite: skite.cock
	./bootstrap/skite-seed skite.cock skite.tmp && ./skite.tmp skite.cock skite && rm -f skite.tmp
# fixed point: skite must reproduce itself byte for byte
selfcheck: skite
	./skite skite.cock skite.check && cmp skite skite.check && rm -f skite.check && echo "selfcheck: fixed point"
test: skite selfcheck
	./test.sh
	./tests/run_cf_fuzz.sh 100 1 1 1 1 1
	./tests/run_ty_fuzz.sh 100 1
	python3 tests/vec_fuzz.py 100 1
fuzz: skite
	for s in 1 2 3 4 5 6 7 8; do for m in "0 0 0" "1 0 0" "0 1 0" "1 1 0" "0 0 1" "0 1 1" "1 1 1" "0 1 0 1" "1 1 1 1"; do ./tests/run_cf_fuzz.sh 1000 $$s $$m || exit 1; done; done
	for s in 1 2 3 4 5 6 7 8; do ./tests/run_ty_fuzz.sh 1000 $$s || exit 1; done
	for s in 1 2 3 4 5 6 7 8; do python3 tests/vec_fuzz.py 500 $$s || exit 1; done
bench: skite
	./bench/code_size.sh
runtime: skite
	./bench/runtime/run_runtime.sh 11
vigenere: skite
	python3 bench/vigenere/make_data.py $(CORPUS) /tmp/vigbig 4000 7
	./bench/vigenere/run_bench.sh /tmp/vigbig/quad.bin /tmp/vigbig/cipher.txt 11
# audit path only: rebuild the seed from the archived C compiler
seed-from-c:
	cc -std=c11 -O2 bootstrap/skite.c -o /tmp/skite-c && /tmp/skite-c skite.cock bootstrap/skite-seed
clean:
	rm -f skite skite.tmp skite.check
