// Benchmarks Game k-nucleotide (same algorithm as knucleotide.ck / .rs). usage: knucleotide FASTA
// Reads the THREE section of the FASTA file, packs it to 2-bit symbols (A=0 C=1 G=2 T=3) and counts
// k-mers in a hand-written open-addressing hash table: linear probing, multiplicative hash of the
// integer-encoded k-mer, 2^lg slots with 2^lg >= 2 * (number of possible distinct k-mers). Slot h is the
// word pair tab[2h] = k-mer code, tab[2h+1] = count (0 means the slot is empty).
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

#define GOLD 0x9E3779B97F4A7C15ull

// Offset just past the ">THREE" header line (or the end of the file if there is none).
static long find_three(const unsigned char *inp, long n) {
  long p = 0;
  while (p + 6 <= n) {
    if (inp[p] == '>' && inp[p + 1] == 'T' && inp[p + 2] == 'H' && inp[p + 3] == 'R' && inp[p + 4] == 'E' && inp[p + 5] == 'E') {
      while (p < n && inp[p] != '\n') p++;
      return p;
    }
    p++;
  }
  return n;
}

// log2 of the slot count for k-mers of length k in a sequence of m symbols.
static int table_lg(long m, long k) {
  long distinct = m - k + 1;
  if (2 * k < 62) {
    long lim = 1L << (2 * k);
    if (lim < distinct) distinct = lim;
  }
  int lg = 4;
  while ((1L << lg) < 2 * distinct) lg++;
  return lg;
}

// Count every k-mer of seq[0..m) into tab (2^(64 - shift) slots).
static void build(const unsigned char *seq, long m, long k, uint64_t *tab, long len, int shift) {
  uint64_t kmask = (1ull << (2 * k)) - 1;
  uint64_t mask = len / 2 - 1;
  uint64_t code = 0;
  long i = 0;
  while (i < k - 1) { code = (code << 2) | seq[i]; i++; }
  for (; i < m; i++) {
    code = ((code << 2) | seq[i]) & kmask;
    uint64_t h = (code * GOLD) >> shift;
    for (;;) {
      uint64_t s = h * 2;
      if (tab[s + 1] == 0) { tab[s] = code; tab[s + 1] = 1; break; }
      if (tab[s] == code) { tab[s + 1]++; break; }
      h = (h + 1) & mask;
    }
  }
}

static long lookup(const uint64_t *tab, long len, uint64_t code, int shift) {
  uint64_t mask = len / 2 - 1;
  uint64_t h = (code * GOLD) >> shift;
  while (tab[h * 2 + 1] != 0) {
    if (tab[h * 2] == code) return (long)tab[h * 2 + 1];
    h = (h + 1) & mask;
  }
  return 0;
}

// Frequencies of all k-mers (k <= 2), most frequent first, ties in alphabetical order.
static void frequencies(const unsigned char *seq, long m, long k) {
  long total = m - k + 1;
  if (total > 0) {
    int lg = table_lg(m, k);
    long len = 2L << lg;
    uint64_t *tab = calloc(len, sizeof *tab);
    build(seq, m, k, tab, len, 64 - lg);
    uint64_t ek[16], ec[16];
    long ne = 0;
    for (long j = 0; j < len; j += 2) {
      if (tab[j + 1] != 0) { ek[ne] = tab[j]; ec[ne] = tab[j + 1]; ne++; }
    }
    for (long a = 1; a < ne; a++) {
      uint64_t ck = ek[a], cc = ec[a];
      long b = a;
      while (b > 0 && (ec[b - 1] < cc || (ec[b - 1] == cc && ek[b - 1] > ck))) {
        ek[b] = ek[b - 1];
        ec[b] = ec[b - 1];
        b--;
      }
      ek[b] = ck;
      ec[b] = cc;
    }
    const char *letters = "ACGT";
    for (long a = 0; a < ne; a++) {
      for (long s = k; s > 0;) { s--; putchar(letters[(ek[a] >> (2 * s)) & 3]); }
      long pct = ((long)ec[a] * 100000 + total / 2) / total;
      printf(" %ld.%03ld\n", pct / 1000, pct % 1000);
    }
    free(tab);
  }
  putchar('\n');
}

// Number of occurrences of the nucleotide string pat, printed as "count<TAB>pat".
static void count_kmer(const unsigned char *seq, long m, const unsigned char *enc, const char *pat) {
  long k = (long)strlen(pat);
  long c = 0;
  if (m >= k) {
    int lg = table_lg(m, k);
    long len = 2L << lg;
    uint64_t *tab = calloc(len, sizeof *tab);
    build(seq, m, k, tab, len, 64 - lg);
    uint64_t code = 0;
    for (long j = 0; j < k; j++) code = (code << 2) | enc[(unsigned char)pat[j]];
    c = lookup(tab, len, code, 64 - lg);
    free(tab);
  }
  printf("%ld\t%s\n", c, pat);
}

int main(int argc, char **argv) {
  if (argc < 2) return 1;
  int fd = open(argv[1], O_RDONLY);
  struct stat st;
  if (fd < 0 || fstat(fd, &st) != 0) return 1;
  long n = st.st_size;
  if (n == 0) return 0;
  const unsigned char *inp = mmap(0, n, PROT_READ, MAP_PRIVATE, fd, 0);
  if (inp == MAP_FAILED) return 1;
  unsigned char enc[256];
  memset(enc, 255, sizeof enc);
  enc['A'] = 0; enc['C'] = 1; enc['G'] = 2; enc['T'] = 3;
  enc['a'] = 0; enc['c'] = 1; enc['g'] = 2; enc['t'] = 3;
  unsigned char *seq = malloc(n + 1);
  long m = 0;
  long p = find_three(inp, n);
  while (p < n && inp[p] != '>') {
    unsigned char s = enc[inp[p]];
    if (s != 255) seq[m++] = s;
    p++;
  }
  frequencies(seq, m, 1);
  frequencies(seq, m, 2);
  count_kmer(seq, m, enc, "GGT");
  count_kmer(seq, m, enc, "GGTA");
  count_kmer(seq, m, enc, "GGTATT");
  count_kmer(seq, m, enc, "GGTATTTTAATT");
  count_kmer(seq, m, enc, "GGTATTTTAATTTATAGT");
  return 0;
}
