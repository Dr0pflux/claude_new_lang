"""Direct unit test of skite's x86-64 encoder (imported by tests/enc_check.py).

tests/enc_unit.ck is a test driver.  The encoder functions are *extracted from skite.ck* (the roots
below plus everything they reference, so the production code is what is tested), compiled together
with the driver by the compiler under test, and run on a binary vector of test cases
(op, a0..a7 as little-endian i64).  Each case emits some bytes; the concatenation is disassembled by
objdump and every case is compared with an independent description of the instruction(s) it must
produce (the `exp_*` functions below).  Cases cover every instruction form x register x index x
scale x displacement / immediate class that the encoder supports.
"""
import os, re, struct, subprocess, sys, tempfile, shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ----------------------------------------------------------------------------- extraction from skite.ck
ROOTS = """byte u32_ u64_ patch32 rel32 hexv emh enc encr mov_rr mov_ri load store alu alur alui imul_r shift_ri lea
 memop lg load_elem store_elem store_elem_imm unop cqo setcc_zx test_rr jcc jmp sse fload fstore movx j8 p8
 push_r pop_r abs_op
 vm_mem vm_pool vm_abs evx vex3 kmov_kr kmov_rk kand kandn kor kortest kmovk cp_find cp_u64 cp_iota
 K_REG K_MEM K_IMM K_XMM K_XMMS A_ADD A_OR A_AND A_SUB A_XOR A_CMP CC_E CC_NE
 RAX RCX RDX RSP EA_B EA_RI EA_SC code cpool cp_at cp_off cp_tail ncp cplen clen mdisp sp_adj""".split()
STUBBED = {'fail'}


def split_items(src):
    """top-level items of skite.ck -> list of (names, text); a `fn` ends at its closing brace, a `let` at its `;`"""
    items = []
    i, n = 0, len(src)
    depth = 0
    start = 0
    def skip_str(i, q):
        i += 1
        while i < n and src[i] != q:
            i += 2 if src[i] == '\\' else 1
        return i + 1
    while i < n:
        c = src[i]
        if c == '/' and src.startswith('//', i):
            j = src.find('\n', i)
            i = n if j < 0 else j
            continue
        if c == '"' or c == "'":
            i = skip_str(i, c)
            continue
        if c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                items.append(src[start:i + 1]); start = i + 1
        elif c == ';' and depth == 0:
            items.append(src[start:i + 1]); start = i + 1
        i += 1
    out = []
    for t in items:
        body = re.sub(r'//[^\n]*', '', t).strip()
        m = re.match(r'(?:fn\s+(\w+)|let\s+(?:mut\s+)?(\w+)|struct\s+(\w+))', body)
        if m:
            out.append((m.group(1) or m.group(2) or m.group(3), body))
    return out


def extract(skite_ck):
    src = open(skite_ck).read()
    items = split_items(src)
    by = {}
    order = []
    for name, text in items:
        by.setdefault(name, text)
        order.append(name)
    want, todo = set(), [r for r in ROOTS if r in by]
    while todo:
        nm = todo.pop()
        if nm in want or nm in STUBBED:
            continue
        want.add(nm)
        for w in set(re.findall(r'[A-Za-z_]\w*', re.sub(r'"[^"]*"', '""', by[nm]))):
            if w in by and w not in want:
                todo.append(w)
    seen = set()
    text = []
    for nm in order:
        if nm in want and nm not in seen:
            seen.add(nm); text.append(by[nm])
    return '\n'.join(text) + '\n', sorted(want)


# ----------------------------------------------------------------------------- register naming (independent of skite.ck)
R64 = 'rax rcx rdx rbx rsp rbp rsi rdi r8 r9 r10 r11 r12 r13 r14 r15'.split()
R32 = 'eax ecx edx ebx esp ebp esi edi r8d r9d r10d r11d r12d r13d r14d r15d'.split()
R16 = 'ax cx dx bx sp bp si di r8w r9w r10w r11w r12w r13w r14w r15w'.split()
R8 = 'al cl dl bl spl bpl sil dil r8b r9b r10b r11b r12b r13b r14b r15b'.split()
RN = {8: R8, 16: R16, 32: R32, 64: R64}
PTR = {8: 'BYTE PTR', 16: 'WORD PTR', 32: 'DWORD PTR', 64: 'QWORD PTR', 128: 'XMMWORD PTR', 512: 'ZMMWORD PTR'}


def hx(v):
    return '0x%x' % v


def imm(v, bits):
    """immediate operand as objdump prints it for an operand of this size"""
    return hx(v & ((1 << bits) - 1))


def s64(v):
    v &= (1 << 64) - 1
    return v - (1 << 64) if v >> 63 else v


def disp_str(d):
    return '' if d == 0 else ('+%s' % hx(d) if d > 0 else '-%s' % hx(-d))


def mem(bits, base, index, scale, disp, mode='sib'):
    """[base+index*2^scale+disp] as objdump prints it ('mode' sib: encoder always uses a SIB byte)"""
    ptr = PTR[bits] + ' ' if bits else ''
    if base is None and index is None:
        return '%sds:%s' % (ptr, hx(disp & 0xffffffff))
    if base is None:
        return '%s[%s*%d%s]' % (ptr, R64[index], 1 << scale, '+' + hx(disp & 0xffffffff))
    s = R64[base]
    if index is not None:
        s += '+%s*%d' % (R64[index], 1 << scale)
    s += disp_str(disp)
    return '%s[%s]' % (ptr, s)


# ----------------------------------------------------------------------------- the driver
def parse_ops(ck_text):
    ops = {}
    for m in re.finditer(r'if op == (\d+) \{.*\}\s*//\s*(\w+)\s*$', ck_text, re.M):
        ops[m.group(2)] = int(m.group(1))
    return ops


class Cases:
    """list of (op name, args, expected instruction texts, expected return value or None)"""
    def __init__(self, ops):
        self.ops = ops
        self.items = []

    def add(self, name, args, expect, ret=None):
        if name not in self.ops:
            raise KeyError('driver has no op %s' % name)
        self.items.append((name, list(args), expect, ret))

    def vector(self):
        b = bytearray()
        for name, args, _, _ in self.items:
            a = list(args) + [0] * (8 - len(args))
            b += struct.pack('<q', self.ops[name])
            for x in a:
                b += struct.pack('<q', s64(x))
        return bytes(b)


def norm(t):
    t = re.sub(r'\s+', ' ', t.strip())
    t = t.replace('+riz*1', '')
    return t


def run(skite, args, disasm, BASE):
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import enc_cases
    ck = open(os.path.join(ROOT, 'tests', 'enc_unit.ck')).read()
    ops = parse_ops(ck)
    enc_src, names = extract(os.path.join(ROOT, 'skite.ck'))
    work = tempfile.mkdtemp(prefix='encunit')
    try:
        harness = os.path.join(work, 'harness.ck')
        open(harness, 'w').write(enc_src + '\n' + ck)
        exe = os.path.join(work, 'harness')
        r = subprocess.run([skite, harness, exe], capture_output=True, text=True)
        if r.returncode:
            print('unit: harness failed to compile (extracted: %s)\n%s%s' % (' '.join(names), r.stdout, r.stderr))
            if args.keep:
                shutil.copy(harness, os.path.join(args.keep, 'enc_harness.ck'))
            return False
        cs = Cases(ops)
        enc_cases.build(cs)
        vec = os.path.join(work, 'cases.bin')
        open(vec, 'wb').write(cs.vector())
        code, marks = os.path.join(work, 'code.bin'), os.path.join(work, 'marks.bin')
        r = subprocess.run([exe, vec, code, marks], capture_output=True, text=True, timeout=60)
        if r.returncode:
            print('unit: driver failed rc=%d\n%s%s' % (r.returncode, r.stdout, r.stderr))
            return False
        codeb = open(code, 'rb').read()
        mk = open(marks, 'rb').read()
        n = len(cs.items)
        if len(mk) != 16 * n:
            print('unit: driver wrote %d marks for %d cases' % (len(mk) // 16, n))
            return False
        ends = struct.unpack('<%dq' % (2 * n), mk)
        # disassemble from a padded copy so objdump's start address is 0
        img = os.path.join(work, 'img.bin')
        open(img, 'wb').write(codeb)
        ins = disasm_raw(img, len(codeb), BASE)
        fails = []
        k = 0
        start = 0
        for ci, (name, a, expect, ret) in enumerate(cs.items):
            end, rv = ends[2 * ci], ends[2 * ci + 1]
            got = []
            while k < len(ins) and ins[k][0] - BASE < end:
                got.append(ins[k]); k += 1
            if got and got[-1][0] - BASE + len(got[-1][1]) != end:
                fails.append('%s%r: instruction straddles the case boundary' % (name, tuple(a)))
                continue
            if ret is not None and rv != ret:
                fails.append('%s%r: returned %d, expected %d' % (name, tuple(a), rv, ret))
            gt = [norm(g[2]) for g in got]
            ex = [norm(e) for e in expect]
            if expect is not None and gt != ex:
                fails.append('%s%r: bytes %s\n      got      %s\n      expected %s' % (
                    name, tuple(a), codeb[start:end].hex(), ' ; '.join(gt), ' ; '.join(ex)))
            start = end
        print('unit: %d encoder cases, %d instructions, %d failures (extracted %d definitions from skite.ck)' % (
            n, len(ins), len(fails), len(names)))
        for f in fails[:40]:
            print('  ' + f)
        if len(fails) > 40:
            print('  ... %d more' % (len(fails) - 40))
        return not fails
    finally:
        shutil.rmtree(work, ignore_errors=True)


LINE = re.compile(r'^\s*([0-9a-f]+):\t((?:[0-9a-f]{2} )+)\s*(?:\t(.*))?$')


def disasm_raw(path, size, BASE):
    out = subprocess.run(['objdump', '-D', '-b', 'binary', '-mi386:x86-64', '-M', 'intel', '--adjust-vma=%#x' % BASE, path],
                         capture_output=True, text=True, check=True).stdout
    ins = []
    for ln in out.splitlines():
        m = LINE.match(ln)
        if not m:
            continue
        b = bytes.fromhex(m.group(2).replace(' ', ''))
        if m.group(3) is None:
            ins[-1][1] += b
        else:
            ins.append([int(m.group(1), 16), b, m.group(3).strip()])
    return ins
