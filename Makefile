# ling is written in ling0 (ling.cock). bootstrap/ling-seed is a prebuilt ling
# executable, so building needs no C compiler, assembler, linker or libc.
# bootstrap/ling0.c is the original C seed, kept only for auditing the chain.
CORPUS ?= gutenberg
.PHONY: all selfcheck test fuzz bench runtime vigenere seed-from-c clean
all: ling
ling: ling.cock
	./bootstrap/ling-seed ling.cock ling.tmp && ./ling.tmp ling.cock ling && rm -f ling.tmp
# fixed point: ling must reproduce itself byte for byte
selfcheck: ling
	./ling ling.cock ling.check && cmp ling ling.check && rm -f ling.check && echo "selfcheck: fixed point"
test: ling selfcheck
	./test.sh
	./tests/run_cf_fuzz.sh 100 1 1 1 1 1
	./tests/run_ty_fuzz.sh 100 1
fuzz: ling
	for s in 1 2 3 4 5 6 7 8; do for m in "0 0 0" "1 0 0" "0 1 0" "1 1 0" "0 0 1" "0 1 1" "1 1 1" "0 1 0 1" "1 1 1 1"; do ./tests/run_cf_fuzz.sh 1000 $$s $$m || exit 1; done; done
	for s in 1 2 3 4 5 6 7 8; do ./tests/run_ty_fuzz.sh 1000 $$s || exit 1; done
bench: ling
	./bench/code_size.sh
runtime: ling
	./bench/runtime/run_runtime.sh 11
vigenere: ling
	python3 bench/vigenere/make_data.py $(CORPUS) /tmp/vigbig 4000 7
	./bench/vigenere/run_bench.sh /tmp/vigbig/quad.bin /tmp/vigbig/cipher.txt 11
# audit path only: rebuild the seed from the archived C compiler
seed-from-c:
	cc -std=c11 -O2 bootstrap/ling0.c -o /tmp/ling0-c && /tmp/ling0-c ling.cock bootstrap/ling-seed
clean:
	rm -f ling ling.tmp ling.check
