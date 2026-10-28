"""Test vectors + independent expectations for tests/enc_unit.py.

Every case is (driver op, arguments, expected disassembly, expected return value).  The expected
instruction text is derived here from the *meaning* of the call (registers, displacement, immediate), never
from the encoder, and compared with what objdump decodes from the bytes the encoder emitted.  The
expectations pin instruction selection (xor for 0, imm8 vs imm32, lea ...) as of this writing.
"""
import itertools
from enc_unit import R8, R16, R32, R64, PTR, hx, imm, s64

K_REG, K_MEM, K_IMM, K_XMM, K_XMMS = 0, 1, 2, 3, 4
ALU = 'add or adc sbb and sub xor cmp'.split()
CC = 'o no b ae e ne be a s ns p np l ge le g'.split()
REGS = list(range(16))
IDXS = [i for i in range(16) if i != 4]          # rsp cannot be an index
GLOB = 0x10010040

IMMS = [0, 1, 2, 127, 128, 255, 256, 0x7fff, 0x8000, 0xffff, 0x10000, 0x7fffffff, 0x80000000, 0xffffffff, 0x100000000,
        0x123456789abcdef0, 0x7fffffffffffffff, 0x8000000000000000, -1, -2, -127, -128, -129, -32768, -32769,
        -0x7fffffff, -0x80000000, -0x80000001, -0x100000000, -0x7fffffffffffffff - 1]
DISPS = [0, 1, -1, 4, 8, 127, 128, -127, -128, -129, 255, 256, 0x1000, -0x1000, 0x7fff, 0x12345678, 0x7fffffff, -0x7fffffff, -0x80000000]
SLOTS = [0, 1, 2, 15, 16, 17, 31, 32, 100, 1000]


def u64(v):
    return v & 0xffffffffffffffff


def fits8(v):
    v = s64(v)
    return -128 <= v <= 127


def fits32(v):
    v = s64(v)
    return -2 ** 31 <= v <= 2 ** 31 - 1


def dstr(d):
    return '' if d == 0 else ('+%s' % hx(d) if d > 0 else '-%s' % hx(-d))


def mtext(base, idx, sc, disp, bits=0, evex=False, bcst=None):
    """memory operand as objdump prints it.  base/idx None: absent."""
    ptr = (PTR[bits] + ' ') if bits else ''
    if bcst:
        ptr = bcst + ' '
    if base is None:
        if idx is None:
            return '%sds:%s' % (ptr, hx(u64(disp) if disp < 0 else disp))
        return '%s[%s*%d+%s]' % (ptr, R64[idx], 1 << sc, hx(disp & 0xffffffff))
    s = R64[base]
    if idx is not None:
        s += '+%s*%d' % (R64[idx], 1 << sc)
    if evex or (base & 7) == 5 and disp == 0:
        s += ('+0x0' if disp == 0 else dstr(disp))      # EVEX uses disp32 throughout; rbp/r13 need a displacement
    else:
        s += dstr(disp)
    return '%s[%s]' % (ptr, s)


def slot(n, sp_adj=0):
    d = n * 8 + sp_adj
    return mtext(4, None, 0, d)


def memset(mini=False):
    """(base, idx, scale, disp) combinations; base/idx None when absent"""
    out = []
    for b in REGS:
        for d in DISPS:
            out.append((b, None, 0, d))
    bases = [0, 3, 4, 5, 12, 13, 15, 8, 9] if not mini else [0, 4, 5, 13]
    for b in bases:
        for i in IDXS:
            for sc in range(4):
                for d in ([0, 1, -128, 0x1000] if not mini else [0]):
                    out.append((b, i, sc, d))
    for i in IDXS:
        for sc in range(4):
            for d in (0, GLOB, 0x7fffffff):
                out.append((None, i, sc, d))
    for d in (0, GLOB, 0x7fffffff, 0x100):
        out.append((None, None, 0, d))
    return out


def mov_ri_text(d, v):
    """instruction(s) mov_ri(d, v) must produce"""
    v = u64(v)
    if v == 0:
        return ['xor %s,%s' % (R32[d], R32[d])]
    if v <= 0xffffffff:
        return ['mov %s,%s' % (R32[d], hx(v))]
    if fits32(v):
        return ['mov %s,%s' % (R64[d], hx(v))]
    return ['movabs %s,%s' % (R64[d], hx(v))]


def build(cs):
    add = cs.add
    # ------------------------------------------------------------------ mov_rr, mov_ri, load, store
    for d in REGS:
        for s in REGS:
            add('mov_rr', [d, s], [] if d == s else ['mov %s,%s' % (R64[d], R64[s])])
    for d in REGS:
        for v in IMMS:
            add('mov_ri', [d, v], mov_ri_text(d, v))
    for d in REGS:
        for s in REGS:
            add('load', [d, K_REG, s, 0], [] if d == s else ['mov %s,%s' % (R64[d], R64[s])])
        for sl in SLOTS:
            add('load', [d, K_MEM, sl, 0], ['mov %s,QWORD PTR %s' % (R64[d], slot(sl))])
        for v in (0, 5, -5, 1 << 40):
            add('load', [d, K_IMM, 0, v], mov_ri_text(d, v))
        for x in REGS:
            add('load', [d, K_XMM, x, 0], ['movq %s,xmm%d' % (R64[d], x)])
            add('load', [d, K_XMMS, x, 0], ['movd %s,xmm%d' % (R32[d], x)])
    for s in REGS:
        for d in REGS:
            add('store', [K_REG, d, s], [] if d == s else ['mov %s,%s' % (R64[d], R64[s])])
            add('store', [K_XMM, d, s], ['movq xmm%d,%s' % (d, R64[s])])
            add('store', [K_XMMS, d, s], ['movd xmm%d,%s' % (d, R32[s])])
        for sl in SLOTS:
            add('store', [K_MEM, sl, s], ['mov QWORD PTR %s,%s' % (slot(sl), R64[s])])

    # ------------------------------------------------------------------ alu
    for dig in range(8):
        mn = ALU[dig]
        for d in REGS:
            for s in REGS:
                add('alu', [dig, K_REG, d, K_REG, s, 0], ['%s %s,%s' % (mn, R64[d], R64[s])])
            for sl in (0, 1, 20):
                add('alu', [dig, K_REG, d, K_MEM, sl, 0], ['%s %s,QWORD PTR %s' % (mn, R64[d], slot(sl))])
                add('alu', [dig, K_MEM, sl, K_REG, d, 0], ['%s QWORD PTR %s,%s' % (mn, slot(sl), R64[d])])
            for v in IMMS:
                if dig == 7 and v == 0:
                    ex = ['test %s,%s' % (R64[d], R64[d])]
                elif not fits32(v):
                    sc = 2 if d == 0 else 0
                    ex = mov_ri_text(sc, v) + ['%s %s,%s' % (mn, R64[d], R64[sc])]
                else:
                    ex = ['%s %s,%s' % (mn, R64[d], imm(v, 64))]
                add('alu', [dig, K_REG, d, K_IMM, 0, v], ex)
        for sl in (0, 3, 17):
            for v in (0, 1, 127, 128, -128, -129, 0x7fffffff, -0x80000000, 0x80000000, 1 << 40):
                if not fits32(v):
                    ex = mov_ri_text(0, v) + ['%s QWORD PTR %s,rax' % (mn, slot(sl))]
                else:
                    ex = ['%s QWORD PTR %s,%s' % (mn, slot(sl), imm(v, 64))]
                add('alu', [dig, K_MEM, sl, K_IMM, 0, v], ex)
    for dig in (0, 4, 5, 6, 7, 1):
        for d in REGS:
            add('alur', [dig, d, (d * 5 + 3) % 16], ['%s %s,%s' % (ALU[dig], R64[d], R64[(d * 5 + 3) % 16])])
            add('alui', [dig, d, 77], ['%s %s,0x4d' % (ALU[dig], R64[d])])

    # ------------------------------------------------------------------ imul, shifts, unary
    for d in REGS:
        for s in REGS:
            add('imul_r', [d, K_REG, s, 0], ['imul %s,%s' % (R64[d], R64[s])])
        for sl in (0, 9):
            add('imul_r', [d, K_MEM, sl, 0], ['imul %s,QWORD PTR %s' % (R64[d], slot(sl))])
        for v in IMMS:
            if fits8(v):
                ex = ['imul %s,%s,%s' % (R64[d], R64[d], imm(v, 64))]
            elif fits32(v):
                ex = ['imul %s,%s,%s' % (R64[d], R64[d], imm(v, 64))]
            else:
                sc = 2 if d == 0 else 0
                ex = mov_ri_text(sc, v) + ['imul %s,%s' % (R64[d], R64[sc])]
            add('imul_r', [d, K_IMM, 0, v], ex)
    SH = {0: 'rol', 1: 'ror', 2: 'rcl', 3: 'rcr', 4: 'shl', 5: 'shr', 7: 'sar'}
    for dig, mn in SH.items():
        for d in REGS:
            for k in (0, 1, 2, 7, 31, 32, 63, 64, 65, 127, 128, -1):
                kk = k & 63
                if kk == 0:
                    ex = []
                elif kk == 1:
                    ex = ['%s %s,1' % (mn, R64[d])]
                else:
                    ex = ['%s %s,%s' % (mn, R64[d], hx(kk))]
                add('shift_ri', [dig, d, k], ex)
    UN = {2: 'not', 3: 'neg', 4: 'mul', 5: 'imul', 6: 'div', 7: 'idiv'}
    for dig, mn in UN.items():
        for d in REGS:
            add('unop', [dig, K_REG, d], ['%s %s' % (mn, R64[d])])
        for sl in SLOTS:
            add('unop', [dig, K_MEM, sl], ['%s QWORD PTR %s' % (mn, slot(sl))])
    add('cqo', [], ['cqo'])
    for cc in range(16):
        for r in REGS:
            add('setcc_zx', [cc, r], ['set%s %s' % (CC[cc], R8[r]), 'movzx %s,%s' % (R64[r], R8[r])])
    for r in REGS:
        add('test_rr', [r], ['test %s,%s' % (R64[r], R64[r])])
        add('push_r', [r], ['push %s' % R64[r]])
        add('pop_r', [r], ['pop %s' % R64[r]])
        for op, mn in ((139, 'mov %s,QWORD PTR ds:%s'), (137, None)):
            for addr in (0x10000000, 0x10010040, 0x7fffffff):
                if mn:
                    add('abs_op', [op, r, addr], [mn % (R64[r], hx(addr))])
                else:
                    add('abs_op', [op, r, addr], ['mov QWORD PTR ds:%s,%s' % (hx(addr), R64[r])])

    # ------------------------------------------------------------------ lea
    for d in REGS:
        for b in REGS:
            for dsp in DISPS:
                add('lea', [d, b, -1, dsp], ['lea %s,[%s]' % (R64[d], mtext(b, None, 0, dsp)[1:-1])])
        for b in REGS:
            for i in IDXS:
                if (d + b + i) % 3 == 0:
                    for dsp in (0, 5, -5, 1000):
                        add('lea', [d, b, i, dsp], ['lea %s,[%s]' % (R64[d], mtext(b, i, 0, dsp)[1:-1])])

    # ------------------------------------------------------------------ raw enc with stack slots / registers
    for regf in REGS:
        for rr in REGS:
            add('enc', [1, 0, 1, 0x8b, 0, regf, K_REG, rr, 0], ['mov %s,%s' % (R64[regf], R64[rr])])
            add('enc', [0, 0, 2, 0x0f, 0xaf, regf, K_REG, rr, 0], ['imul %s,%s' % (R32[regf], R32[rr])])
        for sl in SLOTS:
            for adj in (0, 8, 24, 56, 120):
                add('enc', [1, 0, 1, 0x89, 0, regf, K_MEM, sl, adj], ['mov QWORD PTR %s,%s' % (slot(sl, adj), R64[regf])])
        for sl, adj in ((15, 7), (15, 8), (14, 15), (16, 0), (0, 127), (0, 128), (0, 129)):
            add('enc', [1, 0, 1, 0x8b, 0, regf, K_MEM, sl, adj], ['mov %s,QWORD PTR %s' % (R64[regf], slot(sl, adj))])
    for r in REGS:
        add('enc', [0, 1, 1, 0x88, 0, r, K_REG, 0, 0], ['mov al,%s' % R8[r]])
        add('enc', [0, 1, 1, 0x88, 0, 0, K_REG, r, 0], ['mov %s,al' % R8[r]])
        add('enc', [0, 1, 2, 0x0f, 0xb6, r, K_REG, r, 0], ['movzx %s,%s' % (R32[r], R8[r])])

    # ------------------------------------------------------------------ memory operands (memop and its users)
    ms = memset()
    n = 0
    for (b, i, sc, dsp) in ms:
        reg = (n * 7 + 3) % 16
        n += 1
        bb = -1 if b is None else b
        ii = -1 if i is None else i
        s = sc if i is not None else 0
        m = lambda bits: mtext(b, i, s, dsp, bits)
        add('memop', [1, 0, 0, 1, 0x8b, 0, reg, bb, ii, s, dsp], ['mov %s,%s' % (R64[reg], m(64))])
        # load_elem: one of every element type
        for t, ex in ((5, 'movzx %s,%s' % (R32[reg], m(8))), (9, 'movzx %s,%s' % (R32[reg], m(8))),
                      (1, 'movsx %s,%s' % (R64[reg], m(8))), (6, 'movzx %s,%s' % (R32[reg], m(16))),
                      (2, 'movsx %s,%s' % (R64[reg], m(16))), (7, 'mov %s,%s' % (R32[reg], m(32))),
                      (10, 'mov %s,%s' % (R32[reg], m(32))), (3, 'movsxd %s,%s' % (R64[reg], m(32))),
                      (4, 'mov %s,%s' % (R64[reg], m(64))), (8, 'mov %s,%s' % (R64[reg], m(64))),
                      (11, 'mov %s,%s' % (R64[reg], m(64)))):
            if (n + t) % 3 == 0 or b is not None and i is None and abs(dsp) < 300:
                add('load_elem', [t, reg, bb, ii, s, dsp], [ex])
        # store_elem: width x (mov | alu)
        for w, bits, R in ((1, 8, R8), (2, 16, R16), (4, 32, R32), (8, 64, R64)):
            for dig in (-1, 0, 5, 7):
                if (n + w + dig) % 3 == 0 or (b is not None and i is None and abs(dsp) < 300 and dig in (-1, 0)):
                    mn = 'mov' if dig < 0 else ALU[dig]
                    add('store_elem', [w, dig, reg, bb, ii, s, dsp], ['%s %s,%s' % (mn, m(bits), R[reg])])
        # store_elem_imm
        for w, bits in ((1, 8), (2, 16), (4, 32), (8, 64)):
            for dig, v in ((-1, 0x41), (-1, -1), (0, 5), (4, 0x7f), (6, -128), (1, 0x1234), (5, 0x12345678), (7, -2)):
                if (n + w + dig + v) % 7 == 0 or (b is not None and i is None and abs(dsp) < 300 and (dig, v) in ((-1, -1), (5, 0x12345678), (0, 5))):
                    mn = 'mov' if dig < 0 else ALU[dig]
                    add('store_elem_imm', [w, dig, v, bb, ii, s, dsp], ['%s %s,%s' % (mn, m(bits), imm(v, bits))])
        # sse with a memory operand (prefix byte emitted by the caller)
        for pfx, op, mn, bits in ((0xf2, 0x58, 'addsd', 64), (0xf2, 0x5e, 'divsd', 64), (0xf3, 0x59, 'mulss', 32), (0xf2, 0x10, 'movsd', 64),
                                  (0xf3, 0x5c, 'subss', 32)):
            if (n + op) % 5 == 0 or (b is not None and i is None and abs(dsp) < 300 and op == 0x58):
                add('pmemop', [0, 0, 0, 2, 0x0f, op, reg, bb, ii, s, dsp, pfx], ['%s xmm%d,%s' % (mn, reg, m(bits))])
        if (n % 4) == 0:
            add('pmemop', [0, 0, 0, 2, 0x0f, 0x11, reg, bb, ii, s, dsp, 0xf2], ['movsd %s,xmm%d' % (m(64), reg)])
    for r in REGS:
        for t in (5, 1, 6, 2, 7, 3, 4):
            pass

    # ------------------------------------------------------------------ branches
    DISP = [0, 1, 5, -6, -10, 127, 128, -128, -129, 0x12345678, -0x12345678, 0x7ffffff0]
    for cc in range(16):
        for d in DISP:
            add('jcc', [cc, d], lambda st, ln, cc=cc, d=d: ['j%s %s' % (CC[cc], hx((st + 6 + d) & u64(-1)))])
    for d in DISP:
        add('jmp', [d], lambda st, ln, d=d: ['jmp %s' % hx((st + 5 + d) & u64(-1))])
    for cc in range(16):
        for d in (0, 1, 127, -2, -128, -100):
            add('j8', [0x70 + cc, d], lambda st, ln, cc=cc, d=d: ['j%s %s' % (CC[cc], hx((st + 2 + d) & u64(-1)))])
    for d in (0, 1, 127, -2, -128):
        add('j8', [0xeb, d], lambda st, ln, d=d: ['jmp %s' % hx((st + 2 + d) & u64(-1))])

    # ------------------------------------------------------------------ SSE
    build_sse(cs)
    build_avx(cs)
    build_pool(cs)


# ---------------------------------------------------------------------------------------------- SSE
def build_sse(cs):
    add = cs.add
    X = lambda i: 'xmm%d' % i
    # (prefix, opcode, w) -> (mnemonic, kind)   kind: xx (xmm, xmm/mem), xr (xmm <- gpr), rx (gpr <- xmm), rr store forms
    scalar = {0xf2: ('sd', 64), 0xf3: ('ss', 32)}
    table = []
    for pfx, (sf, bits) in scalar.items():
        for op, mn in ((0x58, 'add'), (0x59, 'mul'), (0x5c, 'sub'), (0x5e, 'div'), (0x51, 'sqrt')):
            table.append((pfx, 0, op, mn + sf, 'xx', bits))
    table += [(0xf2, 0, 0x5a, 'cvtsd2ss', 'xx', 64), (0xf3, 0, 0x5a, 'cvtss2sd', 'xx', 32),
              (0x66, 0, 0x2e, 'ucomisd', 'xx', 64), (0, 0, 0x2e, 'ucomiss', 'xx', 32),
              (0x66, 0, 0xef, 'pxor', 'xx', 128), (0x66, 0, 0x57, 'xorpd', 'xx', 128), (0, 0, 0x57, 'xorps', 'xx', 128),
              (0, 0, 0x28, 'movaps', 'xx', 128), (0xf2, 0, 0x10, 'movsd', 'xx', 64), (0xf3, 0, 0x10, 'movss', 'xx', 32),
              (0xf3, 0, 0x7e, 'movq', 'xx', 64)]
    for pfx, w, op, mn, kind, bits in table:
        for x in REGS:
            for y in REGS:
                if (x * 3 + y) % 4 == 0 or x == 0 or y == 0 or x >= 8 and y >= 8 and (x + y) % 5 == 0:
                    add('sse', [pfx, w, op, x, K_REG, y], ['%s %s,%s' % (mn, X(x), X(y))])
            for sl in (0, 3, 30):
                add('sse', [pfx, w, op, x, K_MEM, sl], ['%s %s,%s' % (mn, X(x), mtext(4, None, 0, sl * 8, bits))])
    for pfx, op, mn in ((0xf2, 0x11, 'movsd'), (0xf3, 0x11, 'movss')):
        for x in REGS:
            for sl in (0, 3, 30):
                add('sse', [pfx, 0, op, x, K_MEM, sl], ['%s %s,%s' % (mn, mtext(4, None, 0, sl * 8, 64 if mn == 'movsd' else 32), X(x))])
    for w in (0, 1):
        R = R64 if w else R32
        for x in REGS:
            for r in REGS:
                add('sse', [0x66, w, 0x6e, x, K_REG, r], ['%s %s,%s' % ('movq' if w else 'movd', X(x), R[r])])
                add('sse', [0x66, w, 0x7e, x, K_REG, r], ['%s %s,%s' % ('movq' if w else 'movd', R[r], X(x))])
                add('sse', [0xf2, w, 0x2a, x, K_REG, r], ['cvtsi2sd %s,%s' % (X(x), R[r])])
                add('sse', [0xf3, w, 0x2a, x, K_REG, r], ['cvtsi2ss %s,%s' % (X(x), R[r])])
                add('sse', [0xf2, w, 0x2c, r, K_REG, x], ['cvttsd2si %s,%s' % (R[r], X(x))])
                add('sse', [0xf3, w, 0x2c, r, K_REG, x], ['cvttss2si %s,%s' % (R[r], X(x))])
            for sl in (0, 3, 40):
                add('sse', [0x66, w, 0x6e, x, K_MEM, sl], ['%s %s,%s' % ('movq' if w else 'movd', X(x), mtext(4, None, 0, sl * 8, 64 if w else 32))])
                add('sse', [0x66, w, 0x7e, x, K_MEM, sl], ['%s %s,%s' % ('movq' if w else 'movd', mtext(4, None, 0, sl * 8, 64 if w else 32), X(x))])
    # fload / fstore / movx
    for dbl in (0, 1):
        for x in REGS:
            for sr in REGS:
                add('fload', [x, K_XMM, sr, 0, dbl], [] if x == sr else ['movaps %s,%s' % (X(x), X(sr))])
                add('fload', [x, K_XMMS, sr, 0, dbl], [] if x == sr else ['movaps %s,%s' % (X(x), X(sr))])
                add('fload', [x, K_REG, sr, 0, dbl], ['%s %s,%s' % ('movq' if dbl else 'movd', X(x), (R64 if dbl else R32)[sr])])
                add('fstore', [sr, x, dbl], ['%s %s,%s' % ('movq' if dbl else 'movd', (R64 if dbl else R32)[sr], X(x))])
            for sl in (0, 7):
                add('fload', [x, K_MEM, sl, 0, dbl], ['movq %s,QWORD PTR %s' % (X(x), slot(sl))])
            for v in (0, 0x3ff0000000000000, 0x7ff8000000000000, 0xbf800000):
                add('fload', [x, K_IMM, 0, v, dbl], mov_ri_text(0, v) + ['%s %s,%s' % ('movq' if dbl else 'movd', X(x), 'rax' if dbl else 'eax')])
    for d in REGS:
        for s in REGS:
            add('movx', [d, s], [] if d == s else ['movaps %s,%s' % (X(d), X(s))])


# ---------------------------------------------------------------------------------------------- AVX-512 / VEX
PRED_PD = {0: 'eq', 1: 'lt', 2: 'le', 4: 'neq', 5: 'nlt', 6: 'nle', 13: 'ge', 14: 'gt'}
PRED_Q = {0: 'eq', 1: 'lt', 2: 'le', 4: 'neq', 5: 'nlt', 6: 'nle'}
VREGS = [0, 1, 7, 8, 15, 16, 17, 23, 24, 30, 31]


def vsz(ll):
    return ('xmm', 'ymm', 'zmm')[ll]


def vmem_bits(ll):
    return (128, 256, 512)[ll]


def evex_ops():
    """(mm, pp, w, op, mnemonic, form).  forms: rvm (3 operand), rm (2 operand), vmi (shift by imm, reg field = digit),
    kvmi (compare into a mask register, imm8), rmg (broadcast from a gpr), rmx (from xmm/m64), mr (store)"""
    out = []
    for op, mn in ((0x58, 'vaddpd'), (0x5c, 'vsubpd'), (0x59, 'vmulpd'), (0x5e, 'vdivpd')):
        out.append((1, 1, 1, op, mn, 'rvm'))
    for op, mn in ((0xd4, 'vpaddq'), (0xfb, 'vpsubq'), (0xdb, 'vpandq'), (0xeb, 'vporq'), (0xef, 'vpxorq')):
        out.append((1, 1, 1, op, mn, 'rvm'))
    out += [(2, 1, 1, 0x40, 'vpmullq', 'rvm'), (1, 1, 1, 0x6f, 'vmovdqa64', 'rm'), (1, 2, 1, 0x6f, 'vmovdqu64', 'rm'),
            (1, 2, 1, 0x7f, 'vmovdqu64', 'mr'), (1, 1, 1, 0x51, 'vsqrtpd', 'rm'), (1, 2, 1, 0xe6, 'vcvtqq2pd', 'rm'),
            (2, 1, 1, 0x7c, 'vpbroadcastq', 'rmg'), (2, 1, 1, 0x59, 'vpbroadcastq', 'rmx'), (2, 1, 1, 0x19, 'vbroadcastsd', 'rmx')]
    return out


def vtext(r, ll=2):
    return '%s%d' % (vsz(ll), r)


def build_avx(cs):
    add = cs.add
    ops = evex_ops()
    masks = [0, 1, 3, 7]
    n = 0
    for (mm, pp, w, op, mn, form) in ops:
        for reg in VREGS:
            for vv in VREGS:
                for rm in VREGS:
                    n += 1
                    if n % 7 and not (reg in (0, 31) and vv in (0, 31) and rm in (0, 31)) and not (reg in (8, 16, 24) and vv in (8, 16, 24)) and not (n % 9 == 0):
                        continue
                    aaa = masks[n % 4]; z = int(aaa != 0 and n % 2 == 0)
                    ll = 2
                    msk = ('{k%d}' % aaa if aaa else '') + ('{z}' if z else '')
                    if form == 'rvm':
                        ex = ['%s %s%s,%s,%s' % (mn, vtext(reg), msk, vtext(vv), vtext(rm))]
                        add('evx_reg', [mm, pp, w, ll, op, reg, vv, 0, rm, aaa, z, 0, 0, 0, 0, 0, -1], ex)
                    elif form == 'rm':
                        ex = ['%s %s%s,%s' % (mn, vtext(reg), msk, vtext(rm))]
                        add('evx_reg', [mm, pp, w, ll, op, reg, 0, 0, rm, aaa, z, 0, 0, 0, 0, 0, -1], ex)
                    elif form == 'rmg':
                        g = rm % 16
                        ex = ['%s %s%s,%s' % (mn, vtext(reg), msk, R64[g])]
                        add('evx_reg', [mm, pp, w, ll, op, reg, 0, 0, g, aaa, z, 0, 0, 0, 0, 0, -1], ex)
                    elif form == 'rmx':
                        ex = ['%s %s%s,%s' % (mn, vtext(reg), msk, vtext(rm, 0))]
                        add('evx_reg', [mm, pp, w, ll, op, reg, 0, 0, rm, aaa, z, 0, 0, 0, 0, 0, -1], ex)
                    elif form == 'mr':
                        pass
    # shifts by immediate: reg field is the opcode extension, vvvv the destination
    for (op, dig, mn) in ((0x73, 6, 'vpsllq'), (0x73, 2, 'vpsrlq'), (0x72, 4, 'vpsraq')):
        for dst in VREGS:
            for src in VREGS:
                for k in (1, 7, 63):
                    aaa = 1 if (dst + src) % 3 == 0 else 0
                    add('evx_reg', [1, 1, 1, 2, op, dig, dst, 0, src, aaa, 0, 0, 0, 0, 0, 0, k],
                        ['%s %s%s,%s,%s' % (mn, vtext(dst), '{k1}' if aaa else '', vtext(src), hx(k))])
    # compares into mask registers (vm: register or memory)
    for pred, nm in PRED_PD.items():
        for kd in (1, 2, 7):
            for a, b in ((16, 17), (31, 0), (8, 24), (23, 31)):
                add('evx_reg', [1, 1, 1, 2, 0xc2, kd, a, 0, b, 0, 0, 0, 0, 0, 0, 0, pred],
                    ['vcmp%spd k%d,%s,%s' % (nm, kd, vtext(a), vtext(b))])
    for (op, mnb) in ((0x1f, ''), (0x1e, 'u')):
        for pred, nm in PRED_Q.items():
            for kd in (1, 6):
                for a, b in ((16, 17), (31, 0), (8, 24)):
                    add('evx_reg', [3, 1, 1, 2, op, kd, a, 0, b, 1, 0, 0, 0, 0, 0, 0, pred],
                        ['vpcmp%s%sq k%d{k1},%s,%s' % (nm, mnb, kd, vtext(a), vtext(b))])
    # vector length: xmm / ymm forms of one instruction
    for ll in (0, 1, 2):
        for reg, vv, rm in ((1, 2, 3), (17, 18, 19), (31, 0, 8), (8, 9, 31)):
            add('evx_reg', [1, 1, 1, ll, 0xd4, reg, vv, 0, rm, 0, 0, 0, 0, 0, 0, 0, -1],
                ['vpaddq %s,%s,%s' % (vtext(reg, ll), vtext(vv, ll), vtext(rm, ll))])
    # memory operands: base x index x scale x displacement, all with a disp32 and the high register bits
    ms = memset(mini=True)
    for j, (b, i, sc, dsp) in enumerate(ms):
        reg = VREGS[j % len(VREGS)]
        vv = VREGS[(j * 3 + 1) % len(VREGS)]
        bb = -1 if b is None else b
        ii = -1 if i is None else i
        if b is None:
            continue                         # vm_mem always has a base register
        s = sc if i is not None else 0
        aaa = j % 4
        msk = '{k%d}' % aaa if aaa else ''
        m512 = mtext(b, i, s, dsp, 512, evex=True)
        add('evx_mem', [1, 1, 1, 2, 0xd4, reg, vv, 0, 0, aaa, 0, 0, bb, ii, s, dsp, -1], ['vpaddq %s%s,%s,%s' % (vtext(reg), msk, vtext(vv), m512)])
        add('evx_mem', [1, 2, 1, 2, 0x6f, reg, 0, 0, 0, aaa, 0, 0, bb, ii, s, dsp, -1], ['vmovdqu64 %s%s,%s' % (vtext(reg), msk, m512)])
        add('evx_mem', [1, 2, 1, 2, 0x7f, reg, 0, 0, 0, aaa, 0, 0, bb, ii, s, dsp, -1], ['vmovdqu64 %s%s,%s' % (m512, msk, vtext(reg))])
        add('evx_mem', [2, 1, 1, 2, 0x59, reg, 0, 0, 0, aaa, 0, 0, bb, ii, s, dsp, -1],
            ['vpbroadcastq %s%s,%s' % (vtext(reg), msk, mtext(b, i, s, dsp, 64, evex=True))])
        add('evx_mem', [1, 1, 1, 2, 0x58, reg, vv, 0, 0, aaa, 0, 1, bb, ii, s, dsp, -1],
            ['vaddpd %s%s,%s,%s' % (vtext(reg), msk, vtext(vv), mtext(b, i, s, dsp, 0, evex=True, bcst='QWORD BCST'))])
        if j % 3 == 0:
            add('evx_mem', [1, 1, 1, 2, 0xc2, 1 + j % 7, vv, 0, 0, aaa, 0, 1, bb, ii, s, dsp, 2],
                ['vcmplepd k%d%s,%s,%s' % (1 + j % 7, msk, vtext(vv), mtext(b, i, s, dsp, 0, evex=True, bcst='QWORD BCST'))])
    # absolute operand
    for reg in (0, 9, 16, 31):
        for addr in (0, 0x10000000, 0x10010040, 0x7fffffff):
            add('evx_abs', [1, 2, 1, 2, 0x6f, reg, 0, 0, 0, 0, 0, 0, addr, 0, 0, 0, -1],
                ['vmovdqu64 %s,%s' % (vtext(reg), mtext(None, None, 0, addr, 512))])
            add('evx_abs', [1, 2, 1, 2, 0x7f, reg, 0, 0, 0, 1, 0, 0, addr, 0, 0, 0, -1],
                ['vmovdqu64 %s{k1},%s' % (mtext(None, None, 0, addr, 512), vtext(reg))])
    # rip-relative constant-pool operands, with and without a trailing imm8
    for off in (0, 8, 64, 4096 + 64):
        for reg in (0, 16, 31, 9):
            add('evx_pool', [2, 1, 1, 2, 0x59, reg, 0, 0, 0, 0, 0, 0, off, 0, 0, 0, -1],
                lambda st, ln, off=off, reg=reg: ['vpbroadcastq %s,QWORD PTR [rip+%s]        # %s' % (
                    vtext(reg), hx((0x400000 + 4096 + off) - (st + ln)), hx(0x400000 + 4096 + off))])
            add('evx_pool', [1, 1, 1, 2, 0xd4, reg, 17, 0, 0, 1, 0, 0, off, 0, 0, 0, -1],
                lambda st, ln, off=off, reg=reg: ['vpaddq %s{k1},zmm17,ZMMWORD PTR [rip+%s]        # %s' % (
                    vtext(reg), hx((0x400000 + 4096 + off) - (st + ln)), hx(0x400000 + 4096 + off))])
            add('evx_pool', [1, 1, 1, 2, 0xc2, 1 + reg % 7, 22, 0, 0, 0, 0, 1, off, 1, 0, 0, 1],
                lambda st, ln, off=off, reg=reg: ['vcmpltpd k%d,zmm22,QWORD BCST [rip+%s]        # %s' % (
                    1 + reg % 7, hx((0x400000 + 4096 + off) - (st + ln)), hx(0x400000 + 4096 + off))])
    # mask-register instructions (VEX): k0-k7 against r0-r15
    for k in range(8):
        for r in REGS:
            add('kmov_kr', [k, r], ['kmovw k%d,%s' % (k, R32[r])])
            add('kmov_rk', [r, k], ['kmovw %s,k%d' % (R32[r], k)])
        for k2 in range(8):
            add('kmovk', [k, k2], ['kmovw k%d,k%d' % (k, k2)])
            add('kortest', [k, k2], ['kortestw k%d,k%d' % (k, k2)])
            for k3 in (0, 3, 7):
                add('kand', [k, k2, k3], ['kandw k%d,k%d,k%d' % (k, k2, k3)])
                add('kandn', [k, k2, k3], ['kandnw k%d,k%d,k%d' % (k, k2, k3)])
                add('kor', [k, k2, k3], ['korw k%d,k%d,k%d' % (k, k2, k3)])


def build_pool(cs):
    """constant pool: dedupe, 8-byte entries, 64-byte aligned iota table"""
    add = cs.add
    peek = lambda off, v: add('cp_peek', [off], [], v)
    add('cp_u64', [5], [], 0)
    add('cp_u64', [7], [], 8)
    add('cp_u64', [5], [], 0)
    add('cp_u64', [0], [], 16)
    add('cp_u64', [-1], [], 24)
    add('cp_u64', [0x8000000000000000], [], 32)
    add('cp_u64', [7], [], 8)
    add('cp_len', [], [], 40)
    peek(0, 5); peek(8, 7); peek(16, 0); peek(24, -1); peek(32, s64(0x8000000000000000))
    add('cp_iota', [10], [], 64)
    for k in range(8):
        peek(64 + 8 * k, 10 + k)
    add('cp_len', [], [], 128)
    add('cp_iota', [-3], [], 128)
    for k in range(8):
        peek(128 + 8 * k, -3 + k)
    add('cp_u64', [9], [], 192)
    add('cp_u64', [10], [], 200)        # 10 is also iota entry 64 - dedupe finds the first match
    add('cp_iota', [0], [], 256)
    add('cp_len', [], [], 320)
