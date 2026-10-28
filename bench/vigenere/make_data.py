#!/usr/bin/env python3
"""Build the quadgram table and a held-out Vigenere test set from the NLTK
Gutenberg corpus. Training and test books are disjoint.
usage: make_data.py CORPUS_DIR OUT_DIR [N_TEXTS] [SEED]"""
import sys, os, math, random, struct
corpus, out = sys.argv[1], sys.argv[2]
ntexts = int(sys.argv[3]) if len(sys.argv) > 3 else 400
rng = random.Random(int(sys.argv[4]) if len(sys.argv) > 4 else 2026)
TEST = {'austen-persuasion.txt', 'chesterton-thursday.txt', 'melville-moby_dick.txt'}
def letters(path):
    t = open(path, encoding='latin-1').read().upper()
    return ''.join(ch for ch in t if 'A' <= ch <= 'Z')
books = sorted(f for f in os.listdir(corpus) if f.endswith('.txt'))
train = ''.join(letters(os.path.join(corpus, b)) for b in books if b not in TEST)
test = [letters(os.path.join(corpus, b)) for b in sorted(TEST)]
counts = [0] * 26**4
for i in range(len(train) - 3):
    a, b, c, d = (ord(x) - 65 for x in train[i:i+4])
    counts[((a*26+b)*26+c)*26+d] += 1
total = sum(counts)
floor = math.log10(0.01 / total)
tab = [max(-32768, round(100 * (math.log10(c / total) if c else floor))) for c in counts]
os.makedirs(out, exist_ok=True)
with open(os.path.join(out, 'quad.bin'), 'wb') as f:
    f.write(struct.pack('<%dh' % len(tab), *tab))
cts, keys = [], []
for _ in range(ntexts):
    src = rng.choice(test)
    n = rng.randint(100, 600)
    s = rng.randrange(len(src) - n)
    pt = src[s:s+n]
    p = rng.randint(2, 20)
    key = ''.join(chr(65 + rng.randrange(26)) for _ in range(p))
    cts.append(''.join(chr(65 + (ord(pt[i]) - 65 + ord(key[i % p]) - 65) % 26) for i in range(n)))
    keys.append(key)
open(os.path.join(out, 'cipher.txt'), 'w').write('\n'.join(cts) + '\n')
open(os.path.join(out, 'keys.txt'), 'w').write('\n'.join(keys) + '\n')
print(f'train letters {len(train)}, quadgrams {total}, floor {floor*100:.0f}, texts {ntexts}')
