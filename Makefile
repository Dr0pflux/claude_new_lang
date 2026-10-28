# skite is written in skite (skite.ck). bootstrap/skite-seed is a prebuilt skite
# executable, so building needs no C compiler, assembler, linker or libc.
# bootstrap/skite.c is the original C seed, kept only for auditing the chain.
.PHONY: all selfcheck test fuzz bench kernels seed-from-c clean
all: skite
skite: skite.ck
	./bootstrap/skite-seed skite.ck skite.tmp && ./skite.tmp skite.ck skite && rm -f skite.tmp
# fixed point: skite must reproduce itself byte for byte
selfcheck: skite
	./skite skite.ck skite.check && cmp skite skite.check && rm -f skite.check && echo "selfcheck: fixed point"
test: skite selfcheck
	./tests/run.sh
	./tests/run_cf_fuzz.sh 100 1 1 1 1 1
	./tests/run_ty_fuzz.sh 100 1
	python3 tests/vec_fuzz.py 100 1
fuzz: skite
	for s in 1 2 3 4 5 6 7 8; do for m in "0 0 0" "1 0 0" "0 1 0" "1 1 0" "0 0 1" "0 1 1" "1 1 1" "0 1 0 1" "1 1 1 1"; do ./tests/run_cf_fuzz.sh 1000 $$s $$m || exit 1; done; done
	for s in 1 2 3 4 5 6 7 8; do ./tests/run_ty_fuzz.sh 1000 $$s || exit 1; done
	for s in 1 2 3 4 5 6 7 8; do python3 tests/vec_fuzz.py 500 $$s || exit 1; done
	./tests/run_dag_fuzz.sh
	./tests/run_divconst.sh
# Benchmarks Game suite vs gcc, clang and rustc (QUICK=1 for smaller sizes)
bench: skite
	python3 bench/game/run.py 5 $(if $(QUICK),--quick)
# domain kernels and the Vigenere solver
kernels: skite
	python3 bench/kernels/run.py 7
# audit path only: rebuild the seed from the archived C compiler
seed-from-c:
	cc -std=c11 -O2 bootstrap/skite.c -o /tmp/skite-c && /tmp/skite-c skite.ck bootstrap/skite-seed
clean:
	rm -f skite skite.tmp skite.check
