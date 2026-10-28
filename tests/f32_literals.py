#!/usr/bin/env python3
"""Check decimal float literals round directly to binary32 in f32 context."""
from decimal import Decimal, localcontext
from fractions import Fraction
from pathlib import Path
import argparse
import struct
import subprocess
import tempfile


def decimal_text(x: Fraction) -> str:
    if x == 0:
        return '0.0'
    sign = '-' if x < 0 else ''
    x = abs(x)
    n, d = x.numerator, x.denominator
    k = 0
    while d != 1:
        assert d % 2 == 0
        d //= 2
        k += 1
    digits = str(n * (5 ** k))
    exp10 = len(digits) - k - 1
    coeff = digits[0] + ('.' + digits[1:] if len(digits) > 1 else '.0')
    exact = f'{sign}{coeff}e{exp10}'
    if len(exact) <= 127:
        return exact
    # Enough digits to remain far to the same side of the midpoint, under Skite's limit.
    with localcontext() as ctx:
        ctx.prec = 70
        rounded = Decimal(x.numerator) / Decimal(x.denominator)
        out = format(rounded, '.69E').rstrip('0').rstrip('.')
    return sign + out.lower()


def round_ratio_even(n: int, d: int) -> int:
    q, r = divmod(n, d)
    if 2 * r > d or (2 * r == d and q & 1):
        q += 1
    return q


def f32bits(x: Fraction) -> int:
    sign = 0
    if x < 0:
        sign = 0x80000000
        x = -x
    if x == 0:
        return sign
    n, d = x.numerator, x.denominator
    e = n.bit_length() - d.bit_length()
    if e >= 0:
        if n < (d << e):
            e -= 1
    elif (n << -e) < d:
        e -= 1
    if e < -126:
        m = round_ratio_even(n << 149, d)
        return sign | m
    shift = 23 - e
    if shift >= 0:
        m = round_ratio_even(n << shift, d)
    else:
        m = round_ratio_even(n, d << -shift)
    if m >= (1 << 24):
        m >>= 1
        e += 1
    if e > 127:
        return sign | 0x7f800000
    return sign | ((e + 127) << 23) | (m & 0x7fffff)


def f64_then_f32(x: Fraction) -> int:
    return struct.unpack('<I', struct.pack('<f', float(x)))[0]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--compiler', default='./skite', help='path to Skite compiler')
    ap.add_argument('--work-dir', help='directory for generated source and executable')
    args = ap.parse_args()
    compiler = str(Path(args.compiler).resolve())
    if args.work_dir:
        work = Path(args.work_dir).resolve()
        work.mkdir(parents=True, exist_ok=True)
        return run(compiler, work)
    with tempfile.TemporaryDirectory(prefix='skite-f32-') as td:
        return run(compiler, Path(td))


def run(compiler: str, work: Path) -> int:
    eps = Fraction(1, 1 << 60)
    mid_even = Fraction(1) + Fraction(1, 1 << 24)
    mid_odd = Fraction(1) + Fraction(3, 1 << 24)
    normal_mid = Fraction(1, 1 << 126) - Fraction(1, 1 << 150)
    overflow_mid = Fraction(1 << 128) - Fraction(1 << 103)
    cases = [
        ('mid_even', mid_even, 'direct'),
        ('above_even', mid_even + eps, 'direct'),
        ('tie_odd', mid_odd, 'direct'),
        ('below_odd', mid_odd - eps, 'direct'),
        ('subnormal_tie', Fraction(1, 1 << 150), 'direct'),
        ('subnormal_above', Fraction(1, 1 << 150) + Fraction(1, 1 << 200), 'direct'),
        ('normal_boundary_tie', normal_mid, 'direct'),
        ('normal_boundary_below', normal_mid - Fraction(1, 1 << 200), 'direct'),
        ('negative_subnormal', -(Fraction(1, 1 << 149) + Fraction(1, 1 << 200)), 'negative'),
        ('positive_zero', Fraction(0), 'direct'),
        ('negative_zero', Fraction(0), 'negative_zero'),
        ('explicit_literal_cast', mid_even + eps, 'explicit_literal'),
        ('max_finite', Fraction((1 << 24) - 1) * (1 << 104), 'direct'),
        ('overflow_mid_below', overflow_mid - (1 << 70), 'direct'),
        ('overflow_tie', overflow_mid, 'direct'),
        ('explicit_f64_control', mid_even + eps, 'explicit_f64'),
        ('local_const', mid_even + eps, 'local'),
        ('local_alias', mid_even + eps, 'alias'),
        ('local_negative_alias', -(mid_even + eps), 'negative_alias'),
        ('global_const', mid_even + eps, 'global'),
    ]
    global_x = mid_even + eps
    lines = [f'let GLOBAL = {decimal_text(global_x)};', 'fn main() -> i64 {']
    expected = []
    literals = [decimal_text(global_x)]
    for name, target_x, mode in cases:
        lit = decimal_text(target_x)
        literals.append(lit)
        if mode == 'local':
            lines += [f'  let c_{name} = {lit};', f'  let out_{name}: f32 = c_{name};']
            actual_x = Fraction(Decimal(lit))
        elif mode == 'alias':
            lines += [f'  let c_{name} = {lit};', f'  let alias_{name} = c_{name};', f'  let out_{name}: f32 = alias_{name};']
            actual_x = Fraction(Decimal(lit))
        elif mode == 'negative_alias':
            operand = decimal_text(-target_x)
            literals.append(operand)
            lines += [f'  let c_{name} = {operand};', f'  let alias_{name} = c_{name};', f'  let out_{name}: f32 = -alias_{name};']
            actual_x = -Fraction(Decimal(operand))
        elif mode == 'global':
            lines += [f'  let out_{name}: f32 = GLOBAL;']
            actual_x = Fraction(Decimal(decimal_text(global_x)))
        elif mode == 'explicit_literal':
            lines += [f'  let out_{name} = {lit} as f32;']
            actual_x = Fraction(Decimal(lit))
        elif mode == 'negative_zero':
            lines += [f'  let out_{name}: f32 = -0.0;']
            actual_x = Fraction(0)
        elif mode == 'explicit_f64':
            lines += [f'  let d_{name}: f64 = {lit};', f'  let out_{name}: f32 = d_{name} as f32;']
            actual_x = Fraction(Decimal(lit))
        elif mode == 'negative':
            operand = decimal_text(-target_x)
            literals.append(operand)
            lines += [f'  let out_{name}: f32 = -({operand});']
            actual_x = -Fraction(Decimal(operand))
        else:
            lines += [f'  let out_{name}: f32 = {lit};']
            actual_x = Fraction(Decimal(lit))
        want = f64_then_f32(actual_x) if mode in ('explicit_f64', 'explicit_literal') else f32bits(actual_x)
        if mode == 'negative_zero':
            want = 0x80000000
        expected.append(want)
        lines.append(f'  print(bits(out_{name}));')
    lines += ['  return 0;', '}']
    source = '\n'.join(lines) + '\n'
    assert max(map(len, literals)) <= 127
    (work / 'f32_literals.ck').write_text(source)
    expected_text = ''.join(f'{x}\n' for x in expected) + '0\n'
    (work / 'f32_literals.expected').write_text(expected_text)
    exe = work / 'f32_literals'
    try:
        c = subprocess.run([compiler, str(work / 'f32_literals.ck'), str(exe)], text=True, capture_output=True, timeout=10)
        if c.returncode:
            print('compile failed:', c.returncode, c.stderr or c.stdout)
            return 2
        r = subprocess.run([str(exe)], text=True, capture_output=True, timeout=2)
    except subprocess.TimeoutExpired:
        print('compiler or generated program timed out')
        return 3
    if r.returncode:
        print('program failed:', r.returncode, r.stderr or r.stdout)
        return 4
    if r.stdout != expected_text:
        got, want = r.stdout.splitlines(), expected_text.splitlines()
        for i, (a, b) in enumerate(zip(got, want)):
            if a != b:
                print(f'{cases[i][0]}: got {a}, expected {b}')
                return 1
        print(f'line count mismatch: got {len(got)}, expected {len(want)}')
        return 1
    print(f'PASS: {len(cases)} binary32 literal cases (max literal {max(map(len, literals))} chars)')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
