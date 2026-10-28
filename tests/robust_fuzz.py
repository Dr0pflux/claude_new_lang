#!/usr/bin/env python3
"""Robustness fuzzer for the skite compiler (tests/run_robust.sh drives it).

The compiler must never crash (SIGSEGV/SIGILL/SIGFPE), hang, or silently emit a broken binary on bad or
extreme input: it either compiles correctly or prints a diagnostic and exits 1.

  robust_fuzz.py extreme            deterministic extreme-but-valid programs (+ limit probes), checked against
                                    expected output; every program must either compile and run correctly or be
                                    rejected with a clean diagnostic (exact expectations per case)
  robust_fuzz.py regress            the checked-in programs in tests/robust/ (header line says what to expect)
  robust_fuzz.py mutate N [SEED]    N random mutants of the corpus (tests, examples, bench, generated programs)
  robust_fuzz.py all [N] [SEED]     regress + extreme + mutate

Environment: SKITE (compiler, default ./skite), ROBUST_KEEP=dir (save failing inputs), ROBUST_TIMEOUT (seconds).
Every failure is minimized (line- then token-level delta debugging) before it is reported. Exit status 1 on failure.
"""
import os, re, sys, random, subprocess, tempfile, shutil, glob, struct, time, hashlib
sys.stdout.reconfigure(line_buffering=True)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKITE = os.environ.get('SKITE', os.path.join(ROOT, 'skite'))
TIMEOUT = float(os.environ.get('ROBUST_TIMEOUT', '10'))
KEEP = os.environ.get('ROBUST_KEEP')
TMP = tempfile.mkdtemp(prefix='robust.')

SIGNAMES = {4: 'SIGILL', 6: 'SIGABRT', 7: 'SIGBUS', 8: 'SIGFPE', 9: 'SIGKILL', 11: 'SIGSEGV', 24: 'SIGXCPU', 25: 'SIGXFSZ'}
DIAG_RE = re.compile(rb'^(?:.*:\d+:\d+: error: .+|skite: error: .+)', re.S)


def limits():
    import resource
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    resource.setrlimit(resource.RLIMIT_FSIZE, (512 << 20, 512 << 20))


def run_limits_run():
    import resource
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    resource.setrlimit(resource.RLIMIT_FSIZE, (8 << 20, 8 << 20))
    resource.setrlimit(resource.RLIMIT_CPU, (4, 4))


class Result:
    """Outcome of compiling one source. cls is one of: ok, diag, diag-noline, BADDIAG, HANG, CRASH-<sig>, EXIT-<n>"""
    def __init__(self, cls, rc, out, err, secs):
        self.cls, self.rc, self.out, self.err, self.secs = cls, rc, out, err, secs

    @property
    def bad(self):
        return self.cls not in ('ok', 'diag', 'diag-noline')


def compile_src(src, name='t', flags=(), timeout=None):
    """Compile `src` (bytes) with SKITE; returns (Result, path-of-output-binary)."""
    timeout = timeout or TIMEOUT
    p = os.path.join(TMP, name + '.ck')
    o = os.path.join(TMP, name + '.bin')
    with open(p, 'wb') as f:
        f.write(src)
    if os.path.exists(o):
        os.unlink(o)
    t0 = time.time()
    try:
        r = subprocess.run([SKITE, p, o] + list(flags), stdin=subprocess.DEVNULL, capture_output=True,
                           timeout=timeout, preexec_fn=limits)
    except subprocess.TimeoutExpired:
        return Result('HANG', None, b'', b'', time.time() - t0), o
    secs = time.time() - t0
    rc = r.returncode
    if rc < 0:
        return Result('CRASH-' + SIGNAMES.get(-rc, str(-rc)), rc, r.stdout, r.stderr, secs), o
    if rc == 0:
        if not (os.path.exists(o) and open(o, 'rb').read(4) == b'\x7fELF'):
            return Result('BADBIN', rc, r.stdout, r.stderr, secs), o
        return Result('ok', rc, r.stdout, r.stderr, secs), o
    if rc == 1:
        e = r.stderr
        if b'internal' in e.lower() or not DIAG_RE.match(e) or len(e) > 20000:
            return Result('BADDIAG', rc, r.stdout, e, secs), o
        first = e.split(b'\n', 1)[0]
        return Result('diag' if re.search(rb':\d+:\d+: error:', first) else 'diag-noline', rc, r.stdout, e, secs), o
    return Result('EXIT-%d' % rc, rc, r.stdout, r.stderr, secs), o


def run_bin(path, args=(), timeout=5):
    """Run a compiled program; returns (rc, stdout) with rc negative for signals, 'TIMEOUT' on hang."""
    try:
        r = subprocess.run([path] + list(args), stdin=subprocess.DEVNULL, capture_output=True, timeout=timeout,
                           preexec_fn=run_limits_run, cwd=TMP)
    except subprocess.TimeoutExpired:
        return 'TIMEOUT', b''
    return r.returncode, r.stdout


# --------------------------------------------------------------------------------------------- mutation fuzzing
TOKRE = re.compile(rb'''(\s+|//[^\n]*|"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])+'|0[xX][0-9a-fA-F_]+|\d[\d_]*(?:\.\d+)?(?:[eE][+-]?\d+)?'''
                   rb'''|[A-Za-z_]\w*|>>>=|<<=|>>=|>>>|<<|>>|==|!=|<=|>=|&&|\|\||->|\.\.|[+\-*/%&|^]=|.)''', re.S)
KEYWORDS = [b'fn', b'let', b'mut', b'return', b'if', b'else', b'while', b'break', b'continue', b'par', b'in', b'as',
            b'true', b'false', b'struct', b'main', b'alloc', b'shared', b'view', b'file', b'argv', b'argc', b'len',
            b'print', b'putc', b'write', b'ewrite', b'save', b'exit', b'bits', b'sqrt', b'ncpu', b'f64_from_bits',
            b'f32_from_bits', b'i8', b'i16', b'i32', b'i64', b'u8', b'u16', b'u32', b'u64', b'bool', b'f32', b'f64',
            b'alloc8', b'view16', b'__pdig', b'__x']
OPS = [b'+', b'-', b'*', b'/', b'%', b'&', b'|', b'^', b'<<', b'>>', b'>>>', b'==', b'!=', b'<', b'<=', b'>', b'>=',
       b'&&', b'||', b'!', b'~', b'=', b'+=', b'-=', b'*=', b'/=', b'%=', b'<<=', b'>>=', b'>>>=', b'->', b'..',
       b'(', b')', b'{', b'}', b'[', b']', b',', b';', b':', b'.', b'<', b'>', b'as', b'"', b"'", b'\\', b'@', b'#',
       b'$', b'`', b'?']
HUGE = [b'0', b'1', b'-1', b'255', b'256', b'65535', b'65536', b'2147483647', b'2147483648', b'4294967295',
        b'4294967296', b'9223372036854775807', b'9223372036854775808', b'18446744073709551615',
        b'18446744073709551616', b'99999999999999999999999', b'0xFFFFFFFFFFFFFFFF', b'0x10000000000000000',
        b'0x', b'1e308', b'1e309', b'1e-400', b'1e99999999999999999999', b'0.' + b'0' * 400 + b'1', b'1.5e', b'.5',
        b'5.', b'1_000', b'0xFF_FF', b'1e', b'1.e5', b'1f', b'0b11', b'00000000000000000000000000000000000000001',
        b'1' + b'0' * 300, b'4.9e-324', b'1.7976931348623157e308', b'123456789.123456789e-5', b'-0.0']
NESTERS = [b'(', b'{', b'-', b'!', b'~', b'[', b'if x {', b'while true {', b'+', b'a(']


def tokenize(src):
    return TOKRE.findall(src)


def is_ws(t):
    return t[:1].isspace()


class Corpus:
    def __init__(self, extra_dirs=()):
        pats = ['tests/*.ck', 'tests/*/*.ck', 'examples/*.ck', 'examples/*/*.ck', 'bench/*/*.ck']
        files = []
        for p in pats:
            files += sorted(glob.glob(os.path.join(ROOT, p)))
        for d in extra_dirs:
            files += sorted(glob.glob(os.path.join(d, '*.ck')))
        self.files = [f for f in files if os.path.getsize(f) < 60000]
        self.srcs = [open(f, 'rb').read() for f in self.files]
        self.toks = [tokenize(s) for s in self.srcs]

    def pick(self, rnd):
        i = rnd.randrange(len(self.srcs))
        return self.srcs[i], self.toks[i]


def gen_seed_programs(n, seed):
    """Programs from the repository's own generators (richer optimizer paths than the hand-written corpus)."""
    out = os.path.join(TMP, 'gen')
    os.makedirs(out, exist_ok=True)
    for name, extra in (('cf_fuzz', ['1', '1', '1', '0']), ('ty_fuzz', [])):
        exe = os.path.join(TMP, name)
        r = subprocess.run(['cc', '-std=c11', '-O2', os.path.join(ROOT, 'tests', name + '.c'), '-o', exe, '-lm'],
                           capture_output=True)
        if r.returncode:
            continue
        d = os.path.join(out, name)
        os.makedirs(d, exist_ok=True)
        subprocess.run([exe, d, str(n), str(seed)] + extra, capture_output=True)
    return out


def mutate_tokens(rnd, toks):
    """One random token-level mutation; returns a new token list."""
    toks = list(toks)
    idx = [i for i, t in enumerate(toks) if not is_ws(t)]
    if not idx:
        return toks
    i = rnd.choice(idx)
    op = rnd.randrange(16)
    if op == 0:                                        # delete
        del toks[i]
    elif op == 1:                                      # duplicate
        toks.insert(i, toks[i])
    elif op == 2:                                      # swap with next
        j = i + 1
        while j < len(toks) and is_ws(toks[j]):
            j += 1
        if j < len(toks):
            toks[i], toks[j] = toks[j], toks[i]
    elif op == 3:                                      # swap two random
        j = rnd.choice(idx)
        toks[i], toks[j] = toks[j], toks[i]
    elif op == 4:                                      # replace with keyword / operator
        toks[i] = rnd.choice(KEYWORDS + OPS)
    elif op == 5:                                      # insert keyword / operator
        toks.insert(i, b' ' + rnd.choice(KEYWORDS + OPS) + b' ')
    elif op == 6:                                      # extreme literal in place of a number (or anywhere)
        nums = [k for k in idx if toks[k][:1].isdigit()]
        k = rnd.choice(nums) if nums and rnd.random() < 0.8 else i
        toks[k] = rnd.choice(HUGE)
    elif op == 7:                                      # replace an identifier by another identifier of the file
        ids = [k for k in idx if re.match(rb'[A-Za-z_]', toks[k])]
        if ids:
            toks[rnd.choice(ids)] = toks[rnd.choice(ids)]
    elif op == 8:                                      # nesting bomb
        n = rnd.choice([3, 10, 50, 120, 200, 255, 256, 257, 300, 1000, 5000, 70000])
        toks.insert(i, rnd.choice(NESTERS) * n)
    elif op == 9:                                      # repeat a chunk many times
        j = min(len(toks), i + rnd.randrange(1, 40))
        chunk = toks[i:j]
        toks[i:i] = chunk * rnd.choice([2, 3, 10, 100, 1000, 5000])
    elif op == 10:                                     # long identifier
        ids = [k for k in idx if re.match(rb'[A-Za-z_]', toks[k])]
        k = rnd.choice(ids) if ids else i
        toks[k] = b'x' * rnd.choice([1, 62, 63, 64, 65, 200, 5000])
    elif op == 11:                                     # delete a range
        j = min(len(toks), i + rnd.randrange(1, 30))
        del toks[i:j]
    elif op == 12:                                     # long string / huge string
        toks.insert(i, b' "' + b'a' * rnd.choice([1, 100, 70000, 600000]) + b'" ')
    elif op == 13:                                     # swap a type name
        tys = [k for k in idx if toks[k] in (b'i8', b'i16', b'i32', b'i64', b'u8', b'u16', b'u32', b'u64', b'f32',
                                              b'f64', b'bool')]
        if tys:
            toks[rnd.choice(tys)] = rnd.choice([b'i8', b'i16', b'i32', b'i64', b'u8', b'u16', b'u32', b'u64', b'f32', b'f64', b'bool'])
    elif op == 14:                                     # wrap a token run in parentheses / a block
        j = min(len(toks), i + rnd.randrange(1, 12))
        toks.insert(j, rnd.choice([b')', b'}']))
        toks.insert(i, rnd.choice([b'(', b'{', b'-(', b'!(']))
    else:                                              # replace with an arbitrary non-ASCII or control byte
        toks[i] = bytes([rnd.choice([0, 1, 7, 127, 128, 200, 255, 0xC3, 0xE2])]) + b' '
    return toks


def mutate_bytes(rnd, s):
    s = bytearray(s)
    if not s:
        return bytes(s)
    op = rnd.randrange(6)
    i = rnd.randrange(len(s))
    if op == 0:
        s[i] = rnd.randrange(256)
    elif op == 1:
        s.insert(i, rnd.randrange(256))
    elif op == 2:
        del s[i]
    elif op == 3:
        del s[i:]                                      # truncate
    elif op == 4:
        j = min(len(s), i + rnd.randrange(1, 200))
        s[i:i] = s[i:j] * rnd.choice([2, 5, 50])
    else:
        s[i:i] = bytes(rnd.randrange(256) for _ in range(rnd.randrange(1, 8)))
    return bytes(s)


def mutate_lines(rnd, s):
    ls = s.split(b'\n')
    op = rnd.randrange(4)
    i = rnd.randrange(len(ls))
    if op == 0:
        del ls[i]
    elif op == 1:
        ls[i:i] = [ls[i]] * rnd.choice([2, 3, 10, 200])
    elif op == 2:
        j = rnd.randrange(len(ls))
        ls[i], ls[j] = ls[j], ls[i]
    else:
        j = min(len(ls), i + rnd.randrange(1, 20))
        ls[i:i] = ls[i:j] * rnd.choice([2, 5, 100])
    return b'\n'.join(ls)


def make_mutant(rnd, corpus):
    src, toks = corpus.pick(rnd)
    for _ in range(rnd.choice([1, 1, 1, 2, 2, 3, 5])):
        r = rnd.random()
        if r < 0.70:
            toks = mutate_tokens(rnd, toks)
            src = b''.join(toks)
        elif r < 0.82:
            src = mutate_bytes(rnd, b''.join(toks))
            toks = tokenize(src)
        elif r < 0.92:
            src = mutate_lines(rnd, b''.join(toks))
            toks = tokenize(src)
        else:                                          # splice a chunk of another seed
            s2, t2 = corpus.pick(rnd)
            a = rnd.randrange(len(t2))
            b = min(len(t2), a + rnd.randrange(1, 80))
            p = rnd.randrange(len(toks) + 1)
            toks = toks[:p] + t2[a:b] + toks[p:]
            src = b''.join(toks)
    return b''.join(toks) if toks else src


# --------------------------------------------------------------------------------------------- minimization
def minimize(src, cls):
    """Delta-debug `src` while the compile still ends in class `cls` (lines first, then tokens)."""
    hang = cls == 'HANG'
    def still(s):
        r, _ = compile_src(s, 'min', timeout=min(TIMEOUT, 3 if hang else 10))
        return r.cls == cls
    budget = [60 if hang else 400]

    def ddmin(items, join, minchunk=1):
        n = 2
        while len(items) >= 2 and budget[0] > 0:
            chunk = max(minchunk, len(items) // n)
            reduced = False
            i = 0
            while i < len(items) and budget[0] > 0:
                cand = items[:i] + items[i + chunk:]
                budget[0] -= 1
                if still(join(cand)):
                    items = cand
                    reduced = True
                else:
                    i += chunk
            if not reduced:
                if chunk == minchunk:
                    break
                n = min(len(items), n * 2)
        return items
    lines = ddmin(src.split(b'\n'), lambda l: b'\n'.join(l))
    s = b'\n'.join(lines)
    toks = ddmin(tokenize(s), lambda t: b''.join(t))
    return b''.join(toks)


FAILS = []


def report_failure(kind, src, res, note=''):
    h = hashlib.sha1(src).hexdigest()[:8]
    for k, h2 in FAILS:
        if h2 == h:
            return
    FAILS.append((kind, h))
    print('FAIL [%s] %s%s' % (kind, res.cls if res else '', (' ' + note) if note else ''))
    if res and res.err:
        print('   stderr: ' + res.err[:200].decode('utf-8', 'replace').replace('\n', ' | '))
    small = src
    if res and res.cls and not re.match(r'(RUN|WRONG)', res.cls) and kind in ('mutant', 'regress', 'extreme') and len(src) < 100_000:
        try:
            small = minimize(src, res.cls)
        except Exception as e:  # minimization must never hide the failure
            print('   (minimization failed: %r)' % (e,))
    if KEEP:
        os.makedirs(KEEP, exist_ok=True)
        with open(os.path.join(KEEP, '%s_%s.ck' % (res.cls if res else kind, h)), 'wb') as f:
            f.write(small)
    shown = small if len(small) <= 1500 else small[:1500] + b'\n... (%d bytes total)' % len(small)
    print('   minimized (%d bytes):\n' % len(small) + shown.decode('utf-8', 'replace'))


def check_runtime(src, path, tag):
    """Mutants that compile: run them and compare against --scalar. A runtime SIGSEGV is only suspicious
    (infinite recursion legitimately overflows the stack), so it is reported but compared to --scalar first."""
    rc, out = run_bin(path)
    if rc == 'TIMEOUT':
        return None
    r2, p2 = compile_src(src, tag + 's', flags=['--scalar'])
    if r2.cls != 'ok':
        return ('scalar-compile-differs', r2)
    rc2, out2 = run_bin(p2)
    if rc2 == 'TIMEOUT':
        return None
    if rc != rc2 or out != out2:
        return ('scalar-output-differs', None)
    return None


def fuzz_mutants(n, seed):
    gen = gen_seed_programs(max(10, n // 20), seed)
    corpus = Corpus([os.path.join(gen, 'cf_fuzz'), os.path.join(gen, 'ty_fuzz')])
    rnd = random.Random(seed)
    stats = {}
    t0 = time.time()
    for k in range(n):
        src = make_mutant(rnd, corpus)
        res, path = compile_src(src, 'm')
        stats[res.cls] = stats.get(res.cls, 0) + 1
        if res.bad:
            report_failure('mutant', src, res)
            continue
        if res.cls == 'ok' and rnd.random() < 0.5:
            c = check_runtime(src, path, 'm')
            if c:
                stats['runtime-diff'] = stats.get('runtime-diff', 0) + 1
                print('FAIL [mutant-runtime] %s' % c[0])
                report_failure('mutant-runtime', src, c[1] or Result(c[0], 0, b'', b'', 0), c[0])
    print('mutants: %d in %.0fs: %s' % (n, time.time() - t0, ', '.join('%s=%d' % kv for kv in sorted(stats.items()))))


# --------------------------------------------------------------------------------------------- extreme programs
M64 = (1 << 64) - 1


def s64(x):
    x &= M64
    return x - (1 << 64) if x >> 63 else x


def u64(x):
    return x & M64


class Case:
    """expect: 'ok' (must compile and print `out`), 'err' (clean diagnostic required, optional regex `msg`),
    'any' (either; if it compiles it must print `out`)."""
    def __init__(self, name, src, expect='ok', out=None, msg=None, args=()):
        self.name, self.src, self.expect, self.out, self.msg, self.args = name, src, expect, out, msg, args
        if isinstance(self.src, str):
            self.src = self.src.encode('latin-1')


def fmt_ret(v):
    return (str(v) + '\n').encode()


def chain_sum(n, expr='a'):
    return 'fn main() -> i64 { let a = argc(); return ' + '+'.join([expr] * n) + '; }\n'


def gen_cases():
    C = []
    add = C.append
    # ---- trivial / degenerate files
    add(Case('empty', b'', 'err'))
    add(Case('only_ws', b'  \n\t\n  ', 'err'))
    add(Case('only_comment', b'// nothing here', 'err'))
    add(Case('no_newline', b'fn main() -> i64 { return 7; }', 'ok', fmt_ret(7)))
    add(Case('comment_at_eof', b'fn main() -> i64 { return 7; } // done', 'ok', fmt_ret(7)))
    add(Case('crlf', b'fn main() -> i64 {\r\n  return 7;\r\n}\r\n', 'ok', fmt_ret(7)))
    add(Case('ctl_ws', b'fn\x0bmain()\x0c->\ti64\x0b{ return 7; }', 'ok', fmt_ret(7)))
    add(Case('bom', b'\xef\xbb\xbffn main() -> i64 { return 7; }', 'err'))
    add(Case('utf8_comment', 'fn main() -> i64 { return 7; } // héllo 世界 \U0001f600\n'.encode(), 'ok', fmt_ret(7)))
    add(Case('utf8_string', 'fn main() { write("héllo 世界\\n"); }\n'.encode(), 'ok', 'héllo 世界\n'.encode()))
    add(Case('utf8_ident', 'fn main() -> i64 { let é = 1; return é; }\n'.encode(), 'err'))
    add(Case('high_bytes', b'fn main() -> i64 { return 7; }\xff\xfe\xfd\n', 'err'))
    add(Case('nul_mid', b'fn main() -> i64 { return 7; }\x00fn x() {}', 'err', msg='NUL'))
    add(Case('nul_only', b'\x00', 'err'))
    add(Case('lone_slash', b'/', 'err'))
    add(Case('lone_quote', b'"', 'err'))
    add(Case('lone_tick', b"'", 'err'))
    add(Case('lone_brace', b'{', 'err'))
    add(Case('no_main', b'fn f() -> i64 { return 1; }\n', 'err'))
    add(Case('main_twice', b'fn main() { }\nfn main() { }\n', 'err'))
    add(Case('str_unterminated_eof', b'fn main() { write("abc', 'err'))
    add(Case('tick_unterminated_eof', b"fn main() -> i64 { return 'a", 'err'))
    add(Case('comment_with_cr', b'// a\rfn main() -> i64 { return 7; }\n', 'err'))
    add(Case('exit_at_eof', b'fn main() -> i64 { return', 'err'))
    add(Case('semicolon_storm', b'fn main() -> i64 { ' + b';' * 100000 + b' return 7; }\n', 'any', fmt_ret(7)))
    # ---- source size boundary (1 MiB)
    body = b'fn main() -> i64 { return 7; }\n'
    pad = 1048576 - len(body)
    add(Case('src_exactly_1mib', b'//' + b'x' * (pad - 3) + b'\n' + body, 'ok', fmt_ret(7)))
    add(Case('src_1mib_plus1', b'//' + b'x' * (pad - 2) + b'\n' + body, 'err'))
    add(Case('src_5mib', b'//' + b'x' * (5 << 20) + b'\n' + body, 'err'))
    add(Case('src_one_huge_line_error', b'fn main() -> i64 { return ' + b'1+' * 200000 + b' ; }\n', 'any'))
    add(Case('src_huge_line_bad_char', b'fn main() -> i64 { return 7; } ' + b' ' * 900000 + b'@\n', 'err'))
    # ---- long functions
    for n in (1000, 20000, 60000):
        stm = ''.join('s += %d;' % (i % 1000) for i in range(n))
        exp = sum(i % 1000 for i in range(n))
        add(Case('long_fn_%d' % n, 'fn main() -> i64 { let mut s = 0; ' + stm + ' return s; }\n', 'any', fmt_ret(exp)))
        stm = ''.join('if s %% 7 == %d { s += %d; } else { s += 1; }\n' % (i % 7, i % 13) for i in range(n // 4))
        s = 0
        for i in range(n // 4):
            s += (i % 13) if s % 7 == i % 7 else 1
        add(Case('long_fn_ifs_%d' % n, 'fn main() -> i64 { let mut s = 0; ' + stm + ' return s; }\n', 'any', fmt_ret(s)))
    # long loop body with break/continue (branch distances far beyond rel8)
    for n in (50, 400, 3000, 12000):
        stm = ''.join('  s += %d; if s %% 3 == 0 { s += 1; }\n' % (i % 5) for i in range(n))
        prog = ('fn main() -> i64 {\n let mut s = 0; let mut i = 0;\n while i < 5 {\n  i += 1;\n  if i == 2 { continue; }\n' +
                stm + '  if i == 4 { break; }\n }\n return s; }\n')
        s = 0
        for i in range(1, 6):
            if i == 2:
                continue
            for k in range(n):
                s += k % 5
                if s % 3 == 0:
                    s += 1
            if i == 4:
                break
        add(Case('long_loop_body_%d' % n, prog, 'any', fmt_ret(s)))
    # ---- many functions
    for n in (100, 1000, 4000, 4090, 4100, 8000, 20000):
        fs = ''.join('fn f%d(x: i64) -> i64 { return x + %d; }\n' % (i, i) for i in range(n))
        calls = ' + '.join('f%d(a)' % i for i in range(0, n, max(1, n // 50)))
        exp = sum(1 + i for i in range(0, n, max(1, n // 50)))
        add(Case('many_fns_%d' % n, fs + 'fn main() -> i64 { let a = argc(); return ' + calls + '; }\n',
                 'ok' if n <= 4000 else 'any', fmt_ret(exp), msg='too many'))
    # chain of calls through every function (f_i calls f_{i+1}): inlining of deep non-recursive chains
    for n in (50, 500, 3000):
        fs = ''.join('fn f%d(x: i64) -> i64 { return f%d(x + 1) + 1; }\n' % (i, i + 1) for i in range(n - 1))
        fs += 'fn f%d(x: i64) -> i64 { return x; }\n' % (n - 1)
        add(Case('call_chain_%d' % n, fs + 'fn main() -> i64 { return f0(argc()); }\n', 'any', fmt_ret(2 * (n - 1) + 1)))
    # exponential inlining: every function calls the next one twice
    for n in (10, 25, 40):
        fs = ''.join('fn f%d(x: i64) -> i64 { return f%d(x) + f%d(x + 1); }\n' % (i, i + 1, i + 1) for i in range(n))
        fs += 'fn f%d(x: i64) -> i64 { return x; }\n' % n
        # value: sum over paths; compute with memoized recursion
        memo = {}
        def val(i, x):
            if i == n:
                return x
            return val(i + 1, x) + val(i + 1, x + 1)
        # closed form: f_i(x) = 2^(n-i) * x + (n-i)*2^(n-i-1)
        k = n
        exp = (2 ** k) * 1 + k * 2 ** (k - 1)
        add(Case('exp_inline_%d' % n, fs + 'fn main() -> i64 { return f0(argc()); }\n', 'any', fmt_ret(s64(exp)) if n <= 20 else None))
    # exponential inlining with statements
    for n in (8, 20):
        fs = ''.join('fn g%d(x: i64) -> i64 { let mut s = 0; s += g%d(x); s += g%d(x + 1); return s; }\n' % (i, i + 1, i + 1)
                     for i in range(n))
        fs += 'fn g%d(x: i64) -> i64 { return x; }\n' % n
        exp = (2 ** n) * 1 + n * 2 ** (n - 1)
        add(Case('exp_inline_stmt_%d' % n, fs + 'fn main() -> i64 { return g0(argc()); }\n', 'any', fmt_ret(s64(exp)) if n <= 20 else None))
    # mutual recursion + recursion that inlines
    add(Case('mutual_rec', 'fn even(n: i64) -> bool { if n == 0 { return true; } return odd(n - 1); }\n'
             'fn odd(n: i64) -> bool { if n == 0 { return false; } return even(n - 1); }\n'
             'fn main() -> i64 { if even(10 + argc()) { return 1; } return 0; }\n', 'ok', fmt_ret(0)))
    add(Case('self_rec_many_calls', 'fn f(n: i64) -> i64 { if n < 2 { return n; } return f(n-1) + f(n-2) + f(n-3) + f(n-4) + f(n-5) + f(n-6); }\n'
             'fn main() -> i64 { return f(10 + argc()); }\n', 'any'))
    # ---- many parameters
    for n in (1, 15, 16, 17, 40, 300):
        ps = ', '.join('p%d: i64' % i for i in range(n))
        sm = ' + '.join('p%d * %d' % (i, i + 1) for i in range(n))
        cs = ', '.join(str(i + 2) for i in range(n))
        exp = sum((i + 2) * (i + 1) for i in range(n))
        add(Case('params_%d' % n, 'fn f(%s) -> i64 { return %s; }\nfn main() -> i64 { return f(%s); }\n' % (ps, sm, cs),
                 'ok' if n <= 16 else 'err', fmt_ret(exp), msg='param'))
    mix = ', '.join('p%d: %s' % (i, ['i64', 'f64', 'u8', 'f32', 'bool', 'i16'][i % 6]) for i in range(16))
    add(Case('params_mixed_16', 'fn f(%s) -> i64 { return 1; }\nfn main() -> i64 { return f(1, 2.0, 3, 4.0, true, 6, 7, 8.0, 9, 10.0, false, 12, 13, 14.0, 15, 16.0); }\n' % mix, 'ok', fmt_ret(1)))
    arrs = ', '.join('a%d: [u8]' % i for i in range(16))
    add(Case('params_arrays_16', 'fn f(%s) -> i64 { return len(a0) + len(a15); }\nfn main() -> i64 { let b = alloc<u8>(5); return f(%s); }\n'
             % (arrs, ', '.join(['b'] * 16)), 'ok', fmt_ret(10)))
    for n in (17, 100):
        add(Case('call_args_%d' % n, 'fn f(a: i64) -> i64 { return a; }\nfn main() -> i64 { return f(%s); }\n' % ', '.join(['1'] * n), 'err'))
    add(Case('call_args_missing', b'fn f(a: i64, b: i64) -> i64 { return a; }\nfn main() -> i64 { return f(1); }\n', 'err'))
    # ---- identifiers
    for n in (1, 62, 63, 64, 65, 1000, 100000):
        nm = 'a' * (n - 1) + 'b'
        add(Case('ident_%d' % n, 'fn %s(x: i64) -> i64 { let %s2 = x; return x; }\nfn main() -> i64 { let %s = 5; return %s(%s); }\n' % (nm, 'y', 'z', nm, 'z') if False else
                 'fn main() -> i64 { let %s = 5; return %s * 2; }\n' % (nm, nm), 'ok' if n <= 63 else 'err', fmt_ret(10), msg='too long'))
    add(Case('ident_prefix_kw', b'fn main() -> i64 { let fnx = 1; let lets = 2; let iff = 3; let whilee = 4; let _x = 5; let in2 = 6; let as_ = 7; let true1 = 8; return fnx + lets + iff + whilee + _x + in2 + as_ + true1; }\n', 'ok', fmt_ret(36)))
    add(Case('ident_underscore_only', b'fn main() -> i64 { let _ = 5; let __ = 6; return _; }\n', 'any'))
    add(Case('ident_dunder', b'fn main() -> i64 { let __x = 5; return __x; }\n', 'err'))
    add(Case('ident_shadow', b'fn main() -> i64 { let x = 5; let x = 6; return x; }\n', 'err'))
    # ---- literals
    ints = [('0', 0), ('9223372036854775807', 9223372036854775807), ('0x7FFFFFFFFFFFFFFF', 9223372036854775807),
            ('1_000_000', 1000000), ('0xFF_FF', 65535), ('0X1f', 31), ('007', 7), ('00000000000000000000000000000000000000000000000000000000000000000000000000000001', 1),
            ('0x' + '0' * 200 + '1', 1)]
    for i, (lit, v) in enumerate(ints):
        add(Case('int_lit_%d' % i, 'fn main() -> i64 { return %s; }\n' % lit, 'ok', fmt_ret(v)))
    add(Case('u64_max', b'fn main() { let x: u64 = 18446744073709551615; print(x); }\n', 'ok', b'18446744073709551615\n'))
    add(Case('u64_max_hex', b'fn main() { let x: u64 = 0xFFFFFFFFFFFFFFFF; print(x); }\n', 'ok', b'18446744073709551615\n'))
    add(Case('u64_half', b'fn main() { let x: u64 = 9223372036854775808; print(x); }\n', 'ok', b'9223372036854775808\n'))
    add(Case('i64_min_expr', b'fn main() { let x = -9223372036854775807 - 1; print(x); }\n', 'ok', b'-9223372036854775808\n'))
    add(Case('i64_min_lit', b'fn main() { let x: i64 = -9223372036854775808; print(x); }\n', 'any', b'-9223372036854775808\n'))
    add(Case('i64_min_lit_ret', b'fn main() -> i64 { return -9223372036854775808; }\n', 'any', b'-9223372036854775808\n'))
    for lit in ('18446744073709551616', '99999999999999999999999999', '0x10000000000000000', '0x' + 'F' * 40, '1' + '0' * 400):
        add(Case('int_too_big_%d' % len(lit), 'fn main() { let x: u64 = %s; print(x); }\n' % lit, 'err', msg='exceeds'))
    for lit in ('0x', '0x_', '1__', '1_', '12ab', '0b101', '1e', '1e+', '1.5e', '08x', '0xg', '1.2.3', '1e5e5', '1u8', '5i64'):
        add(Case('bad_num_' + re.sub(r'\W', '_', lit), 'fn main() { let x = %s; }\n' % lit, 'any'))
    add(Case('lit_overflow_u8', b'fn main() { let x: u8 = 256; }\n', 'err'))
    add(Case('lit_neg_u8', b'fn main() { let x: u8 = -1; }\n', 'err'))
    add(Case('lit_overflow_i64', b'fn main() { let x: i64 = 9223372036854775808; }\n', 'err'))
    add(Case('char_lits', b"fn main() -> i64 { return 'a' + '\\n' + '\\x41' + '\\\\' + '\\'' + '\"'; }\n", 'ok', fmt_ret(97 + 10 + 65 + 92 + 39 + 34)))
    # ---- float literals (compare the compiler's correctly rounded parse with Python's)
    flts = ['0.0', '1.5', '1e308', '1.7976931348623157e308', '1.7976931348623158e308', '1.7976931348623159e308', '1e309', '1e-324', '4.9e-324',
            '2.4703282292062327e-324', '2.4703282292062328e-324', '2.2250738585072011e-308', '2.2250738585072014e-308', '1e-400',
            '0.' + '0' * 100 + '1', '1' + '0' * 100 + '.0', '123456789012345678901234567890e-20', '9007199254740993.0', '9007199254740993.00000000000000000000001',
            '0.1', '0.3', '5e-324', '1e22', '1e23', '8.41e21', '1e+22', '2e10', '3.0e-7', '1_0.5', '1e0', '0e0', '0e99999', '0.0e-99999',
            '00000000000000000000000000000000000000000000000000000000000000000000001.5', '1.5' + '0' * 80]
    for i, lit in enumerate(flts):
        try:
            v = float(lit.replace('_', ''))
        except Exception:
            continue
        if v == float('inf'):
            add(Case('flt_lit_%d' % i, 'fn main() { let x = %s; print(bits(x)); }\n' % lit, 'any', b'%d\n' % struct.unpack('<Q', struct.pack('<d', v))[0]))
        else:
            add(Case('flt_lit_%d' % i, 'fn main() { let x = %s; print(bits(x)); }\n' % lit, 'any', b'%d\n' % struct.unpack('<Q', struct.pack('<d', v))[0]))
    for lit in ('1e99999', '1e999999999', '1e9999999999999999999999', '1e-99999', '1e-999999999999999999999999', '1' + '0' * 300 + 'e-300',
                '0.' + '0' * 300 + '1e300', '1e+99999999999999999999', '123.456e-99999999999999999999'):
        add(Case('flt_huge_exp_' + str(len(lit)) + '_' + str(abs(hash(lit)) % 1000), 'fn main() { let x = %s; print(bits(x)); }\n' % lit, 'any'))
    add(Case('flt_too_long', 'fn main() { let x = 0.%s1; print(bits(x)); }\n' % ('0' * 200), 'any'))
    add(Case('flt_32', b'fn main() { let x: f32 = 1e39; }\n', 'any'))
    add(Case('flt_32_ok', b'fn main() { let x: f32 = 3.4028235e38; print(bits(x)); }\n', 'any', b'2139095039\n'))
    add(Case('flt_32_tiny', b'fn main() { let x: f32 = 1e-50; print(bits(x)); }\n', 'any'))
    add(Case('flt_int_conv', b'fn main() { let x: f64 = 9007199254740993; }\n', 'err'))
    # ---- strings
    for n in (1, 255, 65536, 500000, 1048000):
        add(Case('string_%d' % n, 'fn main() -> i64 { let s = "%s"; return len(s); }\n' % ('x' * n), 'any', fmt_ret(n), msg='string data'))
    s_all = ''.join('\\x%02x' % i for i in range(256))
    add(Case('string_all_bytes', 'fn main() -> i64 { let s = "%s"; let mut t = 0; let mut i = 0; while i < len(s) { t += s[i]; i += 1; } return t; }\n' % s_all, 'ok', fmt_ret(sum(range(256)))))
    add(Case('string_escapes', b'fn main() -> i64 { let s = "\\n\\t\\r\\0\\\\\\"\\x7f"; return len(s) * 1000 + s[6]; }\n', 'ok', fmt_ret(7127)))
    add(Case('string_bad_escape', b'fn main() { let s = "\\q"; }\n', 'err'))
    add(Case('string_bad_hex', b'fn main() { let s = "\\xZZ"; }\n', 'err'))
    add(Case('string_hex_eof', b'fn main() { let s = "\\x', 'err'))
    add(Case('string_empty', b'fn main() { let s = ""; }\n', 'err'))
    add(Case('string_newline', b'fn main() { let s = "ab\ncd"; }\n', 'err'))
    # many string literals: total data over the 1 MiB limit
    for n, per in ((100, 100), (2000, 600), (3000, 700)):
        lits = ''.join('  write("%s");\n' % (chr(65 + i % 26) * per) for i in range(n))
        out = ''.join((chr(65 + i % 26) * per) for i in range(n)).encode()
        add(Case('many_strings_%dx%d' % (n, per), 'fn main() {\n' + lits + '}\n', 'any', out, msg='string data'))
    add(Case('many_let_strings', ('fn main() -> i64 { ' + ''.join('let s%d = "a%d"; ' % (i, i) for i in range(3000)) +
                                  'return len(s0) + len(s2999); }\n'), 'any', fmt_ret(2 + 5)))
    # ---- nesting
    for d in (10, 100, 250, 255, 256, 257, 258, 1000, 5000, 100000):
        add(Case('nest_paren_%d' % d, 'fn main() -> i64 { return %s1%s; }\n' % ('(' * d, ')' * d), 'ok' if d <= 200 else 'any', fmt_ret(1), msg='nesting'))
        add(Case('nest_block_%d' % d, 'fn main() -> i64 { %s return 1; %s }\n' % ('{' * d, '}' * d), 'ok' if d <= 200 else 'any', fmt_ret(1), msg='nesting'))
        add(Case('nest_if_%d' % d, 'fn main() -> i64 { let a = argc(); let mut s = 0; %s s = 1; %s return s; }\n' % ('if a == 1 {' * d, '}' * d), 'ok' if d <= 200 else 'any', fmt_ret(1), msg='nesting'))
        add(Case('nest_while_%d' % d, 'fn main() -> i64 { let mut s = 0; let mut i = 0; %s s = 1; %s return s; }\n' % ('while i < 1 { i += 1; ' * d if False else 'if s == 0 { ', '}' * d), 'ok' if d <= 200 else 'any', fmt_ret(1), msg='nesting'))
        add(Case('nest_neg_%d' % d, 'fn main() -> i64 { let a = argc(); return %sa; }\n' % ('-' * d), 'any', fmt_ret(1 if d % 2 == 0 else -1), msg='nesting'))
        add(Case('nest_not_%d' % d, 'fn main() -> i64 { let a = argc(); if %sa == 1 { return 1; } return 0; }\n' % ('!' * d), 'any', fmt_ret(1 if d % 2 == 0 else 0), msg='nesting'))
        add(Case('nest_tilde_%d' % d, 'fn main() -> i64 { let a = argc(); return %sa; }\n' % ('~' * d), 'any', fmt_ret(1 if d % 2 == 0 else -2), msg='nesting'))
        add(Case('nest_elseif_%d' % d, 'fn main() -> i64 { let a = argc(); let mut s = 0; %s s = 2; return s; }\n' % ('if a == 0 { s = 1; } else ' * d, ), 'any', fmt_ret(2), msg='nesting'))
        add(Case('nest_call_%d' % d, 'fn f(x: i64) -> i64 { return x + 1; }\nfn main() -> i64 { return %sargc()%s; }\n' % ('f(' * d, ')' * d), 'any', fmt_ret(1 + d), msg='nesting'))
        add(Case('nest_index_%d' % d, 'fn main() -> i64 { let t = alloc<i64>(4); return %s0%s; }\n' % ('t[' * d, ']' * d), 'any', fmt_ret(0), msg='nesting'))
        add(Case('nest_while_real_%d' % d, 'fn main() -> i64 { let mut s = 0; %s s += 1; %s return s; }\n' % ('while s < 1 { ' * d, '}' * d), 'any', fmt_ret(1), msg='nesting'))
    # left-associative chains: shallow source nesting, deep trees
    for n in (100, 1000, 10000, 100000):
        add(Case('chain_add_%d' % n, chain_sum(n), 'any', fmt_ret(n), msg='too (deep|long|big|many)'))
        add(Case('chain_sub_%d' % n, 'fn main() -> i64 { let a = argc(); return 1000000%s; }\n' % ('-a' * n), 'any', fmt_ret(1000000 - n)))
        add(Case('chain_mul_%d' % n, 'fn main() -> i64 { let a = argc(); return a' + '*a' * n + '; }\n', 'any', fmt_ret(1)))
        add(Case('chain_and_%d' % n, 'fn main() -> i64 { let a = argc(); if a == 1' + ' && a == 1' * n + ' { return 1; } return 0; }\n', 'any', fmt_ret(1)))
        add(Case('chain_or_%d' % n, 'fn main() -> i64 { let a = argc(); if a == 0' + ' || a == 0' * n + ' { return 1; } return 0; }\n', 'any', fmt_ret(0)))
        add(Case('chain_bits_%d' % n, 'fn main() -> i64 { let a = argc(); return a' + ' | a ^ a & a' * n + '; }\n', 'any', fmt_ret(1)))
        add(Case('chain_cast_%d' % n, 'fn main() -> i64 { let a = argc(); return a' + ' as i64 as i32' * n + '; }\n', 'any', fmt_ret(1)))
        add(Case('chain_shift_%d' % n, 'fn main() -> i64 { let a = argc(); return a' + ' << 1 >> 1' * n + '; }\n', 'any', fmt_ret(1)))
        add(Case('chain_float_%d' % n, 'fn main() { let a = 1.0; print(a' + ' + a' * n + '); }\n', 'any'))
        add(Case('chain_index_%d' % n, 'fn main() -> i64 { let t = alloc<i64>(4); t[0] = 1; return t[0]' + ' + t[0]' * n + '; }\n', 'any', fmt_ret(n + 1)))
        add(Case('chain_call_%d' % n, 'fn f(x: i64) -> i64 { return x; }\nfn main() -> i64 { let a = argc(); return f(a)' + ' + f(a)' * n + '; }\n', 'any', fmt_ret(n + 1)))
    # right-leaning trees via parentheses (limited by nesting, but with many live temporaries)
    for d in (8, 14, 15, 16, 30, 60, 120, 200):
        add(Case('rightlean_int_%d' % d, 'fn main() -> i64 { let a = argc(); return ' + ''.join('a + %d * (' % i for i in range(d)) + 'a' + ')' * d + '; }\n', 'any'))
        add(Case('rightlean_flt_%d' % d, 'fn main() { let a = 1.5; print(' + ''.join('a + %d.5 * (' % i for i in range(d)) + 'a' + ')' * d + '); }\n', 'any'))
        add(Case('rightlean_f32_%d' % d, 'fn main() { let a: f32 = 1.5; print(' + ''.join('a + %d.5 * (' % i for i in range(d)) + 'a' + ')' * d + '); }\n', 'any'))
        add(Case('rightlean_arr_%d' % d, 'fn main() -> i64 { let t = alloc<f64>(8); t[1] = 2.0; let a = argc(); return (' + ''.join('t[1] * (t[a] + (' for i in range(d)) + '1.0' + '))' * d + ') as i64; }\n', 'any'))
        add(Case('rightlean_call_%d' % d, 'fn f(x: i64) -> i64 { return x * 3 + 1; }\nfn main() -> i64 { let a = argc(); return ' + ''.join('f(a) + (' for i in range(d)) + 'a' + ')' * d + '; }\n', 'any'))
    # ---- variables
    for n in (100, 3000, 20000, 60000, 66000, 100000):
        decl = ''.join('let v%d = a + %d; ' % (i, i) for i in range(n))
        use = ' + '.join('v%d' % i for i in range(0, n, max(1, n // 100)))
        exp = sum(1 + i for i in range(0, n, max(1, n // 100)))
        add(Case('many_locals_%d' % n, 'fn main() -> i64 { let a = argc(); ' + decl + 'return ' + use + '; }\n', 'ok' if n <= 3000 else 'any', fmt_ret(exp), msg='too many'))
        # all live at once
        decl = ''.join('let mut w%d = a * %d; ' % (i, i + 1) for i in range(min(n, 3000)))
        upd = ''.join('w%d += w%d; ' % (i, (i + 1) % min(n, 3000)) for i in range(min(n, 3000)))
    for n in (20, 100, 600, 3000):
        decl = ''.join('let mut w%d = a * %d; ' % (i, i + 1) for i in range(n))
        w = [1 * (i + 1) for i in range(n)]
        loop = ''.join('w%d += w%d; ' % (i, (i + 1) % n) for i in range(n))
        for i in range(n):
            w[i] += w[(i + 1) % n]
        tot = ' + '.join('w%d' % i for i in range(n))
        add(Case('pressure_%d' % n, 'fn main() -> i64 { let a = argc(); ' + decl + loop + 'return ' + tot + '; }\n', 'ok', fmt_ret(sum(w))))
        # same in a loop with float and int mix
        fdecl = ''.join('let mut x%d: f64 = %d.5; ' % (i, i) for i in range(n))
        floop = ''.join('x%d = x%d * 1.0 + x%d; ' % (i, i, (i + 1) % n) for i in range(n))
        add(Case('pressure_flt_%d' % n, 'fn main() -> i64 { ' + fdecl + 'let mut k = 0; while k < 3 { ' + floop + 'k += 1; } return (x0 + x1) as i64; }\n', 'any'))
        # many variables live across a call
        add(Case('pressure_call_%d' % n, 'fn id(x: i64) -> i64 { return x; }\nfn main() -> i64 { let a = argc(); ' + decl + 'let r = id(a);' + loop + 'return r + ' + tot + '; }\n', 'ok', fmt_ret(1 + sum(w))))
    # globals
    for n in (100, 3000, 30000, 60000, 70000):
        g = ''.join('let g%d = %d;\n' % (i, i) for i in range(n))
        add(Case('const_globals_%d' % n, g + 'fn main() -> i64 { return g0 + g%d; }\n' % (n - 1), 'ok' if n <= 3000 else 'any', fmt_ret(n - 1), msg='too many'))
        g = ''.join('let mut m%d: i64 = %d;\n' % (i, i) for i in range(n))
        add(Case('mut_globals_%d' % n, g + 'fn main() -> i64 { m%d += 1; return m0 + m%d; }\n' % (n - 1, n - 1), 'ok' if n <= 3000 else 'any', fmt_ret(n), msg='too many'))
        g = ''.join('let mut f%d: f64 = %d.25;\n' % (i, i) for i in range(n))
        add(Case('flt_globals_%d' % n, g + 'fn main() -> i64 { return (f0 + f%d) as i64; }\n' % (n - 1), 'ok' if n <= 3000 else 'any', fmt_ret(n - 1), msg='too many'))
    for n in (100, 1000, 5000, 20000):
        g = ''.join('let ga%d = alloc<u8>(%d);\n' % (i, 1 + i % 7) for i in range(n))
        add(Case('global_arrays_%d' % n, g + 'fn main() -> i64 { ga0[0] = 5; ga%d[0] = 6; return ga0[0] + ga%d[0] + len(ga%d); }\n' % (n - 1, n - 1, n - 1), 'any', fmt_ret(11 + 1 + (n - 1) % 7)))
    for lenexpr, ok in (('1', True), ('1073741824', True), ('1073741825', False), ('2147483647', False), ('2147483648', False), ('4294967296', False), ('0', False), ('-1', False), ('18446744073709551615', False)):
        add(Case('garray_' + lenexpr, 'let ga = alloc<u8>(%s);\nfn main() -> i64 { ga[0] = 1; return ga[0]; }\n' % lenexpr, 'ok' if ok else 'err', fmt_ret(1)))
    for lenexpr in ('536870912', '536870913', '1073741823'):
        add(Case('garray_u16_' + lenexpr, 'let ga = alloc<u16>(%s);\nfn main() -> i64 { ga[0] = 1; return ga[0]; }\n' % lenexpr, 'any', fmt_ret(1)))
    add(Case('garrays_total_over_1g', b'let a1 = alloc<u8>(700000000);\nlet a2 = alloc<u8>(700000000);\nfn main() -> i64 { a1[0] = 1; a2[0] = 2; return a1[0] + a2[0]; }\n', 'any', fmt_ret(3)))
    add(Case('garrays_total_1g', b'let a1 = alloc<u8>(500000000);\nlet a2 = alloc<u8>(500000000);\nfn main() -> i64 { a1[0] = 1; a2[0] = 2; return a1[0] + a2[0]; }\n', 'any', fmt_ret(3)))
    add(Case('garray_u64_big', b'let a = alloc<u64>(134217728);\nfn main() -> i64 { a[134217727] = 3; return a[134217727] as i64; }\n', 'any', fmt_ret(3)))
    add(Case('garray_u64_toobig', b'let a = alloc<u64>(134217729);\nfn main() -> i64 { return 1; }\n', 'err'))
    for lenexpr in ('1', '2147483647', '2147483648', '4294967296', '0', '-1', '9223372036854775807', '18446744073709551615'):
        add(Case('alloc_main_' + lenexpr, 'fn main() -> i64 { let a = alloc<u8>(%s); return len(a); }\n' % lenexpr, 'any'))
        add(Case('alloc_fn_' + lenexpr, 'fn f() -> i64 { let a = alloc<u8>(%s); return len(a); }\nfn main() -> i64 { return f(); }\n' % lenexpr, 'any'))
    add(Case('alloc_variable_len', b'fn main() -> i64 { let n = argc() * 100; let a = alloc<i64>(n); a[n - 1] = 7; return a[n - 1] + len(a); }\n', 'ok', fmt_ret(107)))
    add(Case('alloc_len_zero_rt', b'fn main() -> i64 { let n = argc() - 1; let a = alloc<i64>(n); return len(a); }\n', 'any'))
    # ---- loops
    for n in (100, 2000, 20000, 70000):
        lp = ''.join('i = 0; while i < 3 { s += %d; i += 1; }\n' % (i % 9) for i in range(n))
        add(Case('many_loops_%d' % n, 'fn main() -> i64 { let mut s = 0; let mut i = 0;\n' + lp + 'return s; }\n', 'ok' if n <= 2000 else 'any', fmt_ret(sum(3 * (i % 9) for i in range(n))), msg='too many'))
    for d in (2, 5, 10, 30, 100, 200):
        head = ''.join('let mut i%d = 0; while i%d < 2 { i%d += 1; ' % (k, k, k) for k in range(d))
        add(Case('nested_loops_%d' % d, 'fn main() -> i64 { let mut s = 0; ' + head + 's += 1; ' + '}' * d + ' return s; }\n', 'any', fmt_ret(2 ** d), msg='nesting'))
    # fully unrolled constant-trip nests (16^k explosion)
    for d in (2, 3, 4, 6):
        head = ''.join('let mut i%d = 0; while i%d < 16 { ' % (k, k) for k in range(d))
        tail = ''.join('i%d += 1; }' % k for k in reversed(range(d)))
        add(Case('unroll_nest_%d' % d, 'fn main() -> i64 { let mut s = 0; ' + head + 's += %s; ' % ('i0 + i%d' % (d - 1)) + tail + ' return s; }\n', 'any'))
        head = ''.join('for_%d: ' % k for k in range(0))
    for d in (2, 4):
        head = ''.join('let mut i%d = 0; while i%d < 3 { ' % (k, k) for k in range(d))
        tail = ''.join('i%d += 1; }' % k for k in reversed(range(d)))
        body = ' '.join('s += %d;' % k for k in range(300))
        add(Case('unroll_big_body_%d' % d, 'fn main() -> i64 { let mut s = 0; ' + head + body + tail + ' return s; }\n', 'any', fmt_ret(3 ** d * sum(range(300)))))
    # ---- structs
    for n in (1, 63, 64, 65, 200):
        sd = ''.join('struct S%d { a: i64, b: u8 }\n' % i for i in range(n))
        add(Case('structs_%d' % n, sd + 'let t = alloc<S%d>(4);\nfn main() -> i64 { t[1].a = 5; t[1].b = 6; return t[1].a + t[1].b; }\n' % (n - 1), 'ok' if n <= 60 else 'any', fmt_ret(11), msg='too many'))
    for n in (1, 31, 32, 33, 100, 1000):
        fd = ', '.join('f%d: %s' % (i, ['i64', 'u8', 'f64', 'i16', 'f32', 'bool', 'u32'][i % 7]) for i in range(n))
        add(Case('fields_%d' % n, 'struct S { %s }\nlet t = alloc<S>(4);\nfn main() -> i64 { t[1].f0 = 5; t[1].f%d = %s; return t[1].f0 + t[2].f%d as i64; }\n' % (fd, n - 1, ['6', '6', '6.5', '6', '6.5', 'true', '6'][(n - 1) % 7], 0 if False else 0), 'any'))
    add(Case('struct_empty', b'struct S { }\nfn main() { }\n', 'any'))
    add(Case('struct_dup_field', b'struct S { a: i64, a: i64 }\nfn main() { }\n', 'any'))
    add(Case('struct_dup', b'struct S { a: i64 }\nstruct S { a: i64 }\nfn main() { }\n', 'err'))
    add(Case('struct_self', b'struct S { a: S }\nfn main() { }\n', 'err'))
    add(Case('struct_unknown_field', b'struct S { a: i64 }\nlet t = alloc<S>(1);\nfn main() -> i64 { return t[0].zz; }\n', 'err'))
    add(Case('struct_big_array', b'struct S { a: i64, b: i64, c: i64, d: i64 }\nlet t = alloc<S>(33554432);\nfn main() -> i64 { t[33554431].d = 1; return t[33554431].d; }\n', 'any', fmt_ret(1)))
    add(Case('struct_big_array_over', b'struct S { a: i64, b: i64, c: i64, d: i64 }\nlet t = alloc<S>(33554433);\nfn main() -> i64 { return 1; }\n', 'err'))
    add(Case('struct_huge_stride', 'struct S { %s }\nlet t = alloc<S>(2);\nfn main() -> i64 { t[1].f9 = 1; return t[1].f9; }\n' % ', '.join('f%d: i64' % i for i in range(10)), 'ok', fmt_ret(1)))
    # ---- frames / spills / displacements
    for n in (10, 200, 5000, 40000):
        dec = ''.join('let mut q%d = a + %d; ' % (i, i) for i in range(n))
        add(Case('frame_%d' % n, 'fn f(a: i64) -> i64 { ' + dec + ' let mut s = 0; ' + ''.join('s += q%d; ' % i for i in range(n)) + 'return s; }\nfn main() -> i64 { return f(argc()) + f(argc() + 1); }\n', 'any', fmt_ret(sum(1 + i for i in range(n)) + sum(2 + i for i in range(n)))))
    add(Case('recursion_deep_runtime', b'fn f(n: i64) -> i64 { if n == 0 { return 0; } return f(n - 1) + 1; }\nfn main() -> i64 { return f(100000); }\n', 'ok', fmt_ret(100000)))
    # ---- calls: many sites of one function (patch lists), many array calls
    for n in (100, 10000, 100000):
        add(Case('call_sites_%d' % n, 'fn f(x: i64) -> i64 { let mut s = 0; let mut i = 0; while i < x { s += i; i += 1; } return s; }\nfn main() -> i64 { let a = argc();\n' + 'let mut t = 0;\n' + ''.join('t += f(a + %d);\n' % (i % 20) for i in range(n)) + 'return t; }\n', 'any', fmt_ret(sum(((1 + i % 20) * (i % 20)) // 2 for i in range(n)))))
        add(Case('call_stmts_%d' % n, 'let mut c: i64 = 0;\nfn f() { c += 1; }\nfn main() -> i64 { ' + 'f(); ' * n + 'return c; }\n', 'any', fmt_ret(n)))
    # ---- par
    add(Case('par_many', 'let r = shared<i64>(8);\nfn main() -> i64 { ' + ''.join('par w in 0..2 { r[w] = w + %d; }\n' % i for i in range(300)) + ' return r[0] + r[1]; }\n', 'any', fmt_ret(299 + 300)))
    add(Case('par_workers_257', b'fn main() -> i64 { let r = shared<i64>(300); par w in 0..257 { r[w] = 1; } return r[0]; }\n', 'any'))
    add(Case('par_nested', b'fn main() { par w in 0..2 { par v in 0..2 { } } }\n', 'err'))
    add(Case('par_negative_range', b'fn main() -> i64 { let r = shared<i64>(4); par w in 5..2 { r[0] = 1; } return r[0]; }\n', 'any'))
    # ---- shifts / constants folded by the compiler itself
    add(Case('const_min_div_neg1', b'fn main() -> i64 { let a = -9223372036854775807 - 1; return a / -1; }\n', 'any'))
    add(Case('const_min_mod_neg1', b'fn main() -> i64 { let a = -9223372036854775807 - 1; return a % -1; }\n', 'any'))
    add(Case('const_min_div_neg1_b', b'fn main() -> i64 { let a: i64 = -9223372036854775807 - 1; let b: i64 = -1; return a / b; }\n', 'any'))
    add(Case('const_min_div_neg1_c', b'fn main() -> i64 { let mut a: i64 = -9223372036854775807 - 1; a /= -1; return a; }\n', 'any'))
    add(Case('const_min_mod_neg1_d', b'fn main() -> i64 { let mut a: i64 = -9223372036854775807 - 1; a %= -1; return a; }\n', 'any'))
    add(Case('const_div_zero_var', b'fn main() -> i64 { let z = 0; return 5 / z; }\n', 'any'))
    add(Case('const_mod_zero_var', b'fn main() -> i64 { let z = 0; return 5 % z; }\n', 'any'))
    add(Case('const_div_zero_mut', b'fn main() -> i64 { let mut z = 0; z += 0; return 5 / z; }\n', 'any'))
    add(Case('const_u64_div_zero', b'fn main() -> i64 { let z: u64 = 0; return (5 as u64 / z) as i64; }\n', 'any'))
    add(Case('const_shift_big', b'fn main() -> i64 { return (1 << 64) + (1 << 100) + (1 >> 200) + (-1 >>> 70) + (1 << -1); }\n', 'any'))
    add(Case('const_shift_var', b'fn main() -> i64 { let s = 9223372036854775807; return (1 << s) + (3 >> s) + (3 >>> s); }\n', 'any'))
    add(Case('const_cast_float', b'fn main() { let x = 1e300; print(x as i64); print(x as u64); print(x as u8); print((0.0 / 0.0) as i64); print((-1e300) as i64); }\n', 'any'))
    add(Case('const_sqrt_neg', b'fn main() { print(bits(sqrt(-1.0))); print(bits(sqrt(0.0 - 0.0))); }\n', 'any'))
    add(Case('const_nan_cmp', b'fn main() -> i64 { let n = 0.0 / 0.0; if n == n { return 1; } if n != n { return 2; } return 3; }\n', 'any', fmt_ret(2)))
    add(Case('const_i2f_big', b'fn main() { let x: u64 = 18446744073709551615; print(x as f64); print(x as f32); let y: i64 = -9223372036854775807 - 1; print(y as f64); print(y as f32); }\n', 'any'))
    add(Case('const_neg_min', b'fn main() -> i64 { let a = -9223372036854775807 - 1; return -a; }\n', 'any', fmt_ret(-9223372036854775808)))
    add(Case('const_mul_ovf', b'fn main() -> i64 { return 9223372036854775807 * 9223372036854775807 * 3; }\n', 'any', fmt_ret(s64(9223372036854775807 ** 2 * 3))))
    add(Case('const_u64_mix', b'fn main() -> i64 { let a: u64 = 1; let b: i64 = 1; return (a + b) as i64; }\n', 'err'))
    add(Case('const_div_magic_min', b'fn main() -> i64 { let a = argc() - 2; return (a * 9223372036854775807) / 3 + a / -9223372036854775807 + a / 9223372036854775807 + a % 1 + a / 1 + a / -1; }\n', 'any'))
    for dv in ('1', '-1', '2', '-2', '3', '7', '-7', '10', '9223372036854775807', '-9223372036854775807', '4611686018427387904', '4294967296', '18446744073709551615'):
        add(Case('div_const_' + dv.replace('-', 'n'), 'fn main() -> i64 { let a = argc() * 123456789123456789 - 5; return a / %s + a %% %s; }\n' % (dv, dv), 'any'))
    add(Case('div_min_const_min', b'fn main() -> i64 { let a = (argc() - 1) - 9223372036854775807 - 1 + 1; return a / (-9223372036854775807 - 1) + a % (-9223372036854775807 - 1); }\n', 'any'))
    # ---- dead / odd code shapes
    add(Case('unreachable_after_return', b'fn main() -> i64 { return 1; return 2; let x = 3; }\n', 'any', fmt_ret(1)))
    add(Case('unreachable_after_break', b'fn main() -> i64 { let mut i = 0; while true { break; i = 1; } return i; }\n', 'any', fmt_ret(0)))
    add(Case('infinite_loop_dead_code', b'fn main() -> i64 { while true { } return 1; }\n', 'any'))
    add(Case('empty_fn_body', b'fn f() { }\nfn main() -> i64 { f(); f(); return 3; }\n', 'ok', fmt_ret(3)))
    add(Case('empty_while_const', b'fn main() -> i64 { while false { } if false { } else { } { } return 3; }\n', 'ok', fmt_ret(3)))
    add(Case('return_missing', b'fn f() -> i64 { }\nfn main() -> i64 { return f(); }\n', 'err'))
    add(Case('return_in_unit', b'fn f() { return 1; }\nfn main() { f(); }\n', 'err'))
    add(Case('main_params', b'fn main(a: i64) -> i64 { return a; }\n', 'err'))
    add(Case('break_outside', b'fn main() { break; }\n', 'err'))
    add(Case('continue_outside', b'fn main() { continue; }\n', 'err'))
    add(Case('array_oob_const', b'fn main() -> i64 { let a = alloc<u8>(4); return a[4]; }\n', 'any'))
    add(Case('array_neg_const', b'fn main() -> i64 { let a = alloc<u8>(4); return a[-1]; }\n', 'any'))
    add(Case('array_huge_index', b'fn main() -> i64 { let a = alloc<u8>(4); return a[18446744073709551615]; }\n', 'any'))
    add(Case('save_args', b'fn main() { let a = alloc<u8>(4); save(1, a, 4); }\n', 'any'))
    add(Case('recursive_arr_fn', b'fn f(a: mut [u8], n: i64) { if n > 0 { a[0] += 1; f(a, n - 1); } }\nfn main() -> i64 { let a = alloc<u8>(4); f(a, 100); return a[0]; }\n', 'ok', fmt_ret(100)))
    add(Case('alloc_in_loop_big', b'fn main() -> i64 { let mut s = 0; let mut i = 0; while i < 100000 { let a = alloc<u8>(65536); a[3] = 1; s += a[3] + a[4]; i += 1; } return s; }\n', 'ok', fmt_ret(100000)))
    add(Case('alloc_in_fn_rec', b'fn f(n: i64) -> i64 { let a = alloc<u8>(1000); a[1] = 1; if n == 0 { return 0; } return f(n - 1) + a[1]; }\nfn main() -> i64 { return f(10000); }\n', 'any', fmt_ret(10000)))
    # inlining stress: big function inlined at many call sites
    big = ''.join('s += x * %d; if s %% 3 == 0 { s ^= %d; }\n' % (i, i) for i in range(150))
    for n in (10, 300, 3000):
        cs = ''.join('t += big(%d);\n' % (i % 5) for i in range(n))
        add(Case('inline_big_%d' % n, 'fn big(x: i64) -> i64 { let mut s = 0;\n' + big + 'return s; }\nfn main() -> i64 { let mut t = 0;\n' + cs + 'return t; }\n', 'any'))
    return C


def check_case(c):
    """Returns None if the case behaves as required, else a (kind, Result, note)."""
    name = re.sub(r'\W', '_', c.name)[:60]
    res, path = compile_src(c.src, name)
    if res.bad:
        return res, 'did not compile cleanly: ' + res.cls
    if res.cls == 'ok':
        if c.expect == 'err':
            return res, 'accepted, but a diagnostic was required'
        if c.out is not None:
            rc, out = run_bin(path, c.args)
            if rc == 'TIMEOUT':
                return Result('RUNHANG', 0, b'', b'', 0), 'compiled program timed out'
            if rc != 0:
                return Result('RUN-RC%s' % rc, 0, b'', b'', 0), 'compiled program exited with %s' % rc
            if out != c.out:
                return Result('WRONG-OUTPUT', 0, b'', b'', 0), 'wrong output: got %r expected %r' % (out[:100], c.out[:100])
        return None
    # clean diagnostic
    if c.expect == 'ok':
        return res, 'rejected, but must compile: ' + res.err[:160].decode('utf-8', 'replace').replace('\n', ' | ')
    if c.msg and c.expect == 'err' and not re.search(c.msg.encode(), res.err, re.I):
        return res, 'diagnostic does not match /%s/: %s' % (c.msg, res.err[:160].decode('utf-8', 'replace'))
    return None


def run_extreme(only=None):
    cases = gen_cases()
    if only:
        cases = [c for c in cases if re.search(only, c.name)]
    nbad = 0
    t0 = time.time()
    stats = {}
    slow = []
    for c in cases:
        t1 = time.time()
        r = check_case(c)
        dt = time.time() - t1
        if dt > 3:
            slow.append((c.name, dt))
        if r:
            res, note = r
            nbad += 1
            print('FAIL [extreme] %s: %s' % (c.name, note))
            report_failure('extreme', c.src, res, c.name)
        else:
            stats['ok'] = stats.get('ok', 0) + 1
    print('extreme: %d cases, %d failures, %.0fs%s' % (len(cases), nbad, time.time() - t0,
          ('; slow: ' + ', '.join('%s=%.1fs' % s for s in slow)) if slow else ''))
    return nbad


# --------------------------------------------------------------------------------------------- regression files
def run_regress():
    """tests/robust/*.ck: first line `// robust: ok|error [regex]`; optional NAME.expected holds stdout for `ok`.
    Large inputs are written as NAME.gen python snippets? No: kept literal and small; big ones live in `extreme`."""
    nbad = 0
    files = sorted(glob.glob(os.path.join(ROOT, 'tests', 'robust', '*.ck')))
    for f in files:
        src = open(f, 'rb').read()
        head = src.split(b'\n', 1)[0].decode('utf-8', 'replace')
        m = re.match(r'// robust: (ok|error|any)(?: (.*))?$', head)
        if not m:
            print('FAIL [regress] %s: missing `// robust:` header' % f)
            nbad += 1
            continue
        exp = None
        ef = f[:-3] + '.expected'
        if os.path.exists(ef):
            exp = open(ef, 'rb').read()
        c = Case(os.path.basename(f), src, {'ok': 'ok', 'error': 'err', 'any': 'any'}[m.group(1)], exp, msg=m.group(2))
        r = check_case(c)
        if r:
            nbad += 1
            print('FAIL [regress] %s: %s' % (f, r[1]))
    print('regress: %d files, %d failures' % (len(files), nbad))
    return nbad


def main():
    try:
        os.nice(10)
    except OSError:
        pass
    args = sys.argv[1:]
    mode = args[0] if args else 'all'
    rc = 0
    try:
        if mode in ('regress', 'all'):
            rc |= run_regress() != 0
        if mode in ('extreme', 'all'):
            rc |= run_extreme(args[1] if mode == 'extreme' and len(args) > 1 else None) != 0
        if mode in ('mutate', 'all'):
            n = int(args[1]) if len(args) > 1 else 300
            seed = int(args[2]) if len(args) > 2 else 1
            fuzz_mutants(n, seed)
            rc |= bool(FAILS)
    finally:
        shutil.rmtree(TMP, ignore_errors=True)
    print('ROBUST: %s' % ('FAIL' if rc or FAILS else 'PASS'))
    sys.exit(1 if rc or FAILS else 0)


if __name__ == '__main__':
    main()
