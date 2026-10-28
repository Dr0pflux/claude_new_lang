// Benchmarks Game reverse-complement (same algorithm as revcomp.ck / .rs). usage: revcomp FASTA
// Each sequence is found by scanning forward to the next '>', then walked backward from its end,
// complementing each residue through a 256-entry table and emitting 60-column lines.
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

static void revcomp(const unsigned char *inp, long start, long end, const unsigned char *tab, unsigned char *obuf) {
  long on = 0, col = 0;
  for (long p = end; p > start;) {
    unsigned char c = inp[--p];
    if (c != '\n') {
      obuf[on++] = tab[c];
      if (++col == 60) {
        obuf[on++] = '\n';
        col = 0;
        if (on >= 65536) { fwrite(obuf, 1, on, stdout); on = 0; }
      }
    }
  }
  if (col > 0) obuf[on++] = '\n';
  fwrite(obuf, 1, on, stdout);
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
  unsigned char tab[256], obuf[65600];
  const char *from = "ACBDGHKMNSRUTWVYacbdghkmnsrutwvy";
  const char *to = "TGVHCDMKNSYAAWBRTGVHCDMKNSYAAWBR";
  for (int i = 0; i < 256; i++) tab[i] = (unsigned char)i;
  for (int i = 0; i < 32; i++) tab[(unsigned char)from[i]] = (unsigned char)to[i];
  long pos = 0;
  while (pos < n) {
    long e = pos;
    while (e < n && inp[e] != '\n') e++;
    fwrite(inp + pos, 1, e - pos, stdout);
    putc('\n', stdout);
    pos = e + 1;
    long start = pos;
    while (pos < n && inp[pos] != '>') pos++;
    if (start < pos) revcomp(inp, start, pos, tab, obuf);
  }
  return 0;
}
