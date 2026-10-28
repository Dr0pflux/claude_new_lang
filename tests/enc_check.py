#!/usr/bin/env python3
"""Audit of skite's x86-64 machine-code encoder.

Two independent checks, both decoded by GNU objdump (the reference decoder):

  corpus  compile many programs (examples, tests, bench, the compiler itself, programs from
          the fuzz generators) and sweep each code image: no "(bad)" opcodes, no stray REX /
          66 / F2 / F3 prefixes, no high-byte registers, every rel8/rel32 branch lands on an
          instruction boundary of the same function (calls on a function entry), every
          RIP-relative operand hits the constant pool, absolute operands hit the BSS, EVEX
          operands use zmm16-31, prologue pushes match the epilogue pops, no code falls
          through into the next function.  (Region boundaries come from `skite --map`.)

  unit    tests/enc_unit.ck is compiled together with the encoder functions extracted from
          skite.ck and driven with thousands of test vectors (every instruction form x every
          register / index / scale / displacement / immediate class); the bytes are
          disassembled and compared with an independent description of the expected
          instruction.

usage: tests/enc_check.py [--skite PATH] [--full] [--no-unit] [--no-corpus] [--shapes]
                          [--keep DIR] [--cases N] [FILE.ck ...]
  default      unit test + corpus of repository programs + a few dozen fuzz programs (seconds)
  --full       adds skite.ck itself and several hundred fuzz programs
  FILE.ck      scan exactly these programs (corpus check only)
Exit status 0: no findings.
"""
import argparse, bisect, collections, os, random, re, shutil, subprocess, sys, tempfile, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASE = 0x400000
CODE0 = BASE + 256
BSS = 0x10000000
LINE = re.compile(r'^\s*([0-9a-f]+):\t((?:[0-9a-f]{2} )+)\s*(?:\t(.*))?$')


# ----------------------------------------------------------------------------- objdump
def disasm(path, start, stop):
    """-> list of [addr, bytes, text] (instruction stream of path[start:stop], addresses are VAs)."""
    out = subprocess.run(['objdump', '-D', '-b', 'binary', '-mi386:x86-64', '-M', 'intel', '--adjust-vma=%#x' % BASE,
                          '--start-address=%#x' % start, '--stop-address=%#x' % stop, path],
                         capture_output=True, text=True, check=True).stdout
    ins = []
    for ln in out.splitlines():
        m = LINE.match(ln)
        if not m:
            continue
        b = bytes.fromhex(m.group(2).replace(' ', ''))
        if m.group(3) is None:
            ins[-1][1] += b          # continuation line of a long instruction
        else:
            ins.append([int(m.group(1), 16), b, m.group(3).strip()])
    return ins


def compile_prog(skite, src, out, flags=()):
    """-> (stdout, region map {name: addr}); raises on compile failure."""
    r = subprocess.run([skite, src, out, '--map'] + list(flags), capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError('compile failed: %s\n%s%s' % (src, r.stdout, r.stderr))
    m = {}
    for ln in r.stderr.splitlines():
        p = ln.split()
        if len(p) == 2 and re.fullmatch(r'[0-9a-f]{8}', p[0]):
            m[p[1]] = int(p[0], 16)
    return m


# ----------------------------------------------------------------------------- corpus scan
PREFIX_WORDS = {'rep', 'repz', 'repnz', 'lock', 'data16', 'addr32', 'cs', 'ds', 'es', 'fs', 'gs', 'ss', 'notrack', 'bnd'}
BRANCH = re.compile(r'^(j[a-z]+|call|loop[a-z]*)\s+0x([0-9a-f]+)$')
RIPREL = re.compile(r'\[rip\+0x[0-9a-f]+\]\s*#\s*0x([0-9a-f]+)')
ABSOLUTE = re.compile(r'ds:0x([0-9a-f]+)')
HIGHBYTE = re.compile(r'\b[abcd]h\b')
ZMM = re.compile(r'\bzmm(\d+)')
KREG = re.compile(r'\bk(\d+)')
WORDREG = re.compile(r'\b(?:ax|bx|cx|dx|si|di|bp|sp|r(?:[89]|1[0-5])w)\b')


class Scan:
    def __init__(self, name, skite, src, flags=(), keep=None):
        self.name = name
        self.issues = []
        self.shapes = collections.Counter()
        tmp = tempfile.mkdtemp(prefix='encchk')
        try:
            out = os.path.join(tmp, 'prog')
            self.map = compile_prog(skite, src, out, flags)
            self.fn_names = {a: n for n, a in self.map.items() if not n.startswith('.')}
            self.fn_starts = sorted(self.fn_names)
            for k in ('.runtime', '.codeend', '.pool', '.data', '.end'):
                if k not in self.map:
                    raise RuntimeError('%s: --map lacks %s' % (name, k))
            self.runtime, self.codeend = self.map['.runtime'], self.map['.codeend']
            self.pool, self.data, self.end = self.map['.pool'], self.map['.data'], self.map['.end']
            self.ins = disasm(out, CODE0, self.codeend)
            hdr = open(out, 'rb').read(256)
            nph = int.from_bytes(hdr[56:58], 'little')
            self.bss_end = BSS
            if nph >= 3:   # third program header: the zero-filled BSS segment
                self.bss_end = int.from_bytes(hdr[176 + 16:176 + 24], 'little') + 0  # p_vaddr
                self.bss_end = BSS + int.from_bytes(hdr[176 + 40:176 + 48], 'little')
            if keep:
                shutil.copy(out, os.path.join(keep, os.path.basename(src) + '.bin'))
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
        self.check()

    def bad(self, kind, ins, why=''):
        a, b, t = ins
        self.issues.append('%s: %s @%#x [%s] %s %s%s' % (self.name, kind, a, self.func_of(a), b.hex(), t, (' -- ' + why) if why else ''))

    def func_of(self, a):
        if a >= self.runtime:
            return '.runtime'
        i = bisect.bisect_right(self.fn_starts, a) - 1
        return self.fn_names[self.fn_starts[i]] if i >= 0 else 'main'

    def range_of(self, a):
        """(lo, hi) of the function / runtime / main containing a"""
        if a >= self.runtime:
            return (self.runtime, self.codeend)
        i = bisect.bisect_right(self.fn_starts, a) - 1
        lo = self.fn_starts[i] if i >= 0 else CODE0
        hi = self.fn_starts[i + 1] if i + 1 < len(self.fn_starts) else self.runtime
        return (lo, hi)

    def check(self):
        ins = self.ins
        if not ins:
            self.issues.append('%s: empty code' % self.name)
            return
        starts = {i[0] for i in ins}
        if ins[-1][0] + len(ins[-1][1]) != self.codeend:
            self.issues.append('%s: instruction stream ends at %#x, not at code end %#x (desync)' % (
                self.name, ins[-1][0] + len(ins[-1][1]), self.codeend))
        for f in self.fn_starts + [self.runtime]:
            if f not in starts:
                self.issues.append('%s: function/runtime start %#x is not an instruction boundary' % (self.name, f))
        pos = {i[0]: n for n, i in enumerate(ins)}
        for n, I in enumerate(ins):
            a, b, t = I
            self.shapes[re.sub(r'\s+', ' ', re.sub(r'0x[0-9a-f]+', 'N', t))] += 1
            if '(bad)' in t:
                self.bad('BAD', I)
                continue
            words = t.split()
            k = 0
            while k < len(words) and (words[k].startswith('rex') or words[k] in PREFIX_WORDS):
                k += 1
            pre = words[:k]
            body = ' '.join(words[k:])
            if any(w.startswith('rex') for w in pre) and not (b[0] == 0x40 and (words[k].startswith('set') or 'BYTE PTR' in body)):   # setcc and byte stores force a REX for sil/dil
                self.bad('REX', I, 'unused or stray REX prefix')
            for w in pre:
                if w in ('rep', 'repz') and len(words) > k and words[k].startswith('stos'):
                    continue
                if not w.startswith('rex'):
                    self.bad('PREFIX', I, 'unexpected prefix %s' % w)
            if len(words) == k:
                self.bad('REX', I, 'prefix without instruction')
                continue
            if len(b) > 15:
                self.bad('LEN', I)
            mn = words[k]
            if HIGHBYTE.search(body):
                self.bad('HIGHBYTE', I, 'ah/bh/ch/dh: byte register encoded without REX')
            if WORDREG.search(body) and 'WORD PTR' not in body and mn not in ('xchg', 'nop', 'movzx', 'movsx'):
                self.bad('WORDREG', I, '16-bit register operand')
            # branches
            m = BRANCH.match(body)
            if m:
                tgt = int(m.group(2), 16)
                lo, hi = self.range_of(a)
                if tgt not in starts:
                    self.bad('BRANCH', I, 'target %#x is not an instruction boundary' % tgt)
                elif mn == 'call':
                    if not (tgt in self.fn_names or self.runtime <= tgt < self.codeend):
                        self.bad('CALL', I, 'target %#x is not a function entry or runtime routine' % tgt)
                elif not (lo <= tgt < hi or self.runtime <= tgt < self.codeend):
                    self.bad('BRANCH', I, 'jump to %#x leaves its function [%#x,%#x)' % (tgt, lo, hi))
            m = RIPREL.search(t)
            if m:
                tgt = int(m.group(1), 16)
                if not (self.pool <= tgt < self.data) or tgt % 8:
                    self.bad('RIPREL', I, 'target %#x outside the constant pool [%#x,%#x) or misaligned' % (tgt, self.pool, self.data))
            for m in ABSOLUTE.finditer(t):
                v = int(m.group(1), 16)
                if not (BSS <= v < self.bss_end):
                    self.bad('ABS', I, 'absolute address %#x outside BSS [%#x,%#x)' % (v, BSS, self.bss_end))
            if b[0] == 0x62:      # EVEX: reserved bits and register ranges
                p0, p1 = b[1], b[2]
                if p0 & 0x0c or not p1 & 4:
                    self.bad('EVEX', I, 'reserved EVEX bits set')
                for r in ZMM.findall(t):
                    if int(r) < 16:
                        self.bad('EVEX', I, 'zmm%s: the vectorizer only uses zmm16-31' % r)
                for r in KREG.findall(t):
                    if int(r) > 7:
                        self.bad('EVEX', I, 'bad mask register')
            if b[0] == 0xc4 and (b[1] & 0x1f) != 1:
                self.bad('VEX', I, 'unexpected VEX map')
            # stack pointer is only written by sub/add/push/pop/call/ret
            if re.match(r'^(mov|xor|lea|imul|movabs|and|or|neg|not|shl|shr|sar|pop|xchg)\s+rsp,', body) or body == 'pop rsp':
                self.bad('RSP', I, 'write to rsp')
            # 8-byte stack slots are 8-aligned (the print buffer lea and vector scratch excepted)
            m = re.search(r'QWORD PTR \[rsp\+0x([0-9a-f]+)\]', body)
            if m and int(m.group(1), 16) % 8 and mn not in ('lea',):
                self.bad('SLOT', I, 'misaligned stack slot')
        # prologue / epilogue pairing and fall-through
        by_addr = pos
        for f in self.fn_starts:
            lo, hi = self.range_of(f)
            first = by_addr[lo]
            last = by_addr.get(hi, len(ins)) - 1
            pushes = []
            j = first
            while j <= last and ins[j][2].startswith('push'):
                pushes.append(ins[j][2].split()[1]); j += 1
            if ins[j][0] - lo > 10 or (ins[j][0] - lo < 10 and not ins[j][2].startswith(('nop', 'xchg'))):
                self.bad('PROLOGUE', ins[j], 'saved-register area is not exactly 10 bytes of push/nop')
            if ins[last][2] != 'ret':
                self.bad('FALLTHROUGH', ins[last], 'function does not end in ret')
                continue
            pops = []
            j = last - 1
            while j > first and ins[j][2].startswith('pop'):
                pops.append(ins[j][2].split()[1]); j -= 1
            if pops != pushes:
                self.bad('EPILOGUE', ins[last], 'pops %s do not undo pushes %s' % (pops[::-1], pushes))
        # the instruction before main's end / the runtime / every function must not fall into it
        for f in self.fn_starts + [self.runtime]:
            j = by_addr[f] - 1
            if j >= 0 and not re.match(r'^(ret|jmp|ud2|syscall)\b', ins[j][2]):
                self.bad('FALLTHROUGH', ins[j], 'code falls through into %#x' % f)


# ----------------------------------------------------------------------------- corpus sources
def repo_programs():
    out = []
    for d in ('examples', 'examples/tutorial', 'tests/data', 'tests/types', 'bench/game', 'bench/kernels', 'bench/vigenere'):
        p = os.path.join(ROOT, d)
        if os.path.isdir(p):
            out += sorted(os.path.join(p, f) for f in os.listdir(p) if f.endswith('.ck'))
    return out


def generate_fuzz(work, cases, seed):
    """Programs from the repository's fuzz generators -> list of paths"""
    progs = []
    cc = shutil.which('cc') or shutil.which('gcc')
    d = os.path.join(work, 'gen')
    os.makedirs(d, exist_ok=True)
    if cc:
        for name in ('cf_fuzz', 'ty_fuzz', 'dag_fuzz', 'divconst_gen'):
            subprocess.run([cc, '-std=c11', '-O1', '-w', '-fno-math-errno', os.path.join(ROOT, 'tests', name + '.c'), '-o', os.path.join(d, name), '-lm'], check=True)
        def gen(tag, args, pat):
            o = os.path.join(d, tag)
            os.makedirs(o, exist_ok=True)
            subprocess.run(args[:1] + [o] + args[1:], check=True, capture_output=True)
            progs.extend(sorted(os.path.join(o, f) for f in os.listdir(o) if f.endswith('.ck') and re.match(pat, f)))
        n = max(1, cases)
        for i, (pr, mem, fn, par) in enumerate([(0, 0, 0, 0), (1, 0, 0, 0), (0, 1, 0, 0), (1, 1, 1, 0), (0, 1, 1, 0), (1, 1, 0, 1), (0, 1, 1, 1)]):
            gen('cf%d' % i, [os.path.join(d, 'cf_fuzz'), str(n), str(seed + i), str(pr), str(mem), str(fn), str(par)], r'c')
        gen('ty', [os.path.join(d, 'ty_fuzz'), str(2 * n), str(seed)], r't')
        gen('dag', [os.path.join(d, 'dag_fuzz'), str(n), str(seed)], r'f')
        o = os.path.join(d, 'dc')
        os.makedirs(o, exist_ok=True)
        subprocess.run([os.path.join(d, 'divconst_gen'), o], check=True, capture_output=True)
        dcs = sorted(os.path.join(o, f) for f in os.listdir(o) if f.endswith('.ck'))
        progs.extend(dcs[:max(2, n // 2)])
    # vectorizer programs: reuse the generator of tests/vec_fuzz.py (its main() is run only when executed)
    src = open(os.path.join(ROOT, 'tests', 'vec_fuzz.py')).read()
    src = re.sub(r'^main\(\)\s*$', '', src, flags=re.M)
    ns = {'__name__': 'vec_fuzz', '__file__': os.path.join(ROOT, 'tests', 'vec_fuzz.py')}
    exec(compile(src, 'vec_fuzz.py', 'exec'), ns)
    rnd = random.Random(seed)
    o = os.path.join(d, 'vec')
    os.makedirs(o, exist_ok=True)
    for c in range(max(2, cases * 2)):
        p = os.path.join(o, 'v%04d.ck' % c)
        open(p, 'w').write(ns['Gen'](rnd).program())
        progs.append(p)
    return progs


def corpus(skite, files, args, work):
    t0 = time.time()
    issues, shapes, nprog, ncode = [], collections.Counter(), 0, 0
    for p in files:
        for flags in ((),):
            try:
                s = Scan(os.path.relpath(p, ROOT) if p.startswith(ROOT) else p, skite, p, flags, args.keep)
            except RuntimeError as e:
                issues.append(str(e))
                continue
            nprog += 1
            ncode += len(s.ins)
            issues += s.issues
            shapes.update(s.shapes)
    print('corpus: %d programs, %d instructions, %d distinct shapes, %d findings (%.1fs)' % (nprog, ncode, len(shapes), len(issues), time.time() - t0))
    if args.shapes:
        for sh, c in sorted(shapes.items()):
            print('%7d  %s' % (c, sh))
    for i in issues[:60]:
        print('  ' + i)
    if len(issues) > 60:
        print('  ... %d more' % (len(issues) - 60))
    return not issues


# ----------------------------------------------------------------------------- unit test
def unit(skite, args):
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import enc_unit
    return enc_unit.run(skite, args, disasm, BASE)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--skite', default=os.environ.get('SKITE', os.path.join(ROOT, 'skite')))
    ap.add_argument('--full', action='store_true')
    ap.add_argument('--no-unit', action='store_true')
    ap.add_argument('--no-corpus', action='store_true')
    ap.add_argument('--shapes', action='store_true', help='print every distinct instruction shape of the corpus')
    ap.add_argument('--keep', help='directory to keep the compiled corpus images in')
    ap.add_argument('--cases', type=int, default=None, help='fuzz programs per generator configuration')
    ap.add_argument('--seed', type=int, default=1)
    ap.add_argument('files', nargs='*')
    args = ap.parse_args()
    args.skite = os.path.abspath(args.skite)
    if not os.access(args.skite, os.X_OK):
        sys.exit('no compiler at %s (build it, or set SKITE)' % args.skite)
    if args.keep:
        os.makedirs(args.keep, exist_ok=True)
    ok = True
    if not args.no_unit and not args.files:
        ok &= unit(args.skite, args)
    if not args.no_corpus:
        work = tempfile.mkdtemp(prefix='encchk')
        try:
            if args.files:
                files = args.files
            else:
                files = repo_programs()
                if args.full:
                    files.append(os.path.join(ROOT, 'skite.ck'))
                cases = args.cases if args.cases is not None else (40 if args.full else 4)
                files += generate_fuzz(work, cases, args.seed)
            ok &= corpus(args.skite, files, args, work)
        finally:
            shutil.rmtree(work, ignore_errors=True)
    print('enc_check: PASS' if ok else 'enc_check: FAIL')
    sys.exit(0 if ok else 1)


if __name__ == '__main__':
    main()
