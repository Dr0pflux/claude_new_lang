# Exhaustive check, in precision p, of the Markstein reciprocal step:
#   y within one ulp of 1/b, r = RN(1 - b*y), y' = RN(y + y*r)  =>  y' == RN(1/b)
# for every significand b in (1, 2) except the all-ones one.
import sys
from fractions import Fraction as F

def rn(x, p):
    # round positive rational x to p significant bits, ties to even
    assert x > 0
    e = x.numerator.bit_length() - x.denominator.bit_length()
    if F(2) ** e > x: e -= 1
    if F(2) ** (e + 1) <= x: e += 1
    m = x * F(2) ** (p - 1 - e)
    q, rem = divmod(m.numerator, m.denominator)
    if 2 * rem > m.denominator or (2 * rem == m.denominator and q & 1): q += 1
    return F(q) * F(2) ** (e - p + 1)

def rn_signed(x, p):
    if x == 0: return F(0)
    return rn(x, p) if x > 0 else -rn(-x, p)

def check(p):
    bad = []
    for B in range(2 ** (p - 1) + 1, 2 ** p):
        b = F(B, 2 ** (p - 1))
        exact = 1 / b
        want = rn(exact, p)
        t = F(2 ** p) * exact          # y = Y / 2^p, Y in [2^(p-1), 2^p)
        for Y in (t.numerator // t.denominator, t.numerator // t.denominator + 1):
            y = F(Y, 2 ** p)
            if abs(y - exact) >= F(1, 2 ** p): continue
            r = rn_signed(1 - b * y, p)
            y2 = rn(y + y * r, p)
            if y2 != want: bad.append((B, Y))
    return bad

for p in range(int(sys.argv[1]), int(sys.argv[2]) + 1):
    bad = check(p)
    allones = [x for x in bad if x[0] == 2 ** p - 1]
    print(p, "failures:", len(bad), "of which all-ones b:", len(allones), bad[:4])
