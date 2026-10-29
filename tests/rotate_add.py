#!/usr/bin/env python3
"""Constant rotate-add lowering against independent wrapping-bit oracles."""
import os, pathlib, subprocess, tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
SKITE = pathlib.Path(os.environ.get('SKITE', ROOT / 'skite')).resolve()
MASK = (1 << 64) - 1
VALUES = [0, 1, (1 << 63), MASK, 0x123456789ABCDEF0, 0xAAAAAAAAAAAAAAAA]

def run(args):
    return subprocess.run(list(map(str, args)), capture_output=True, check=True, timeout=30).stdout

checks = 0
with tempfile.TemporaryDirectory(prefix='skite-rotate-add-') as td:
    t = pathlib.Path(td)
    for ty in ['u64', 'i64']:
        for c in range(1, 64):
            lines = ['fn main(){']
            for v in VALUES:
                lines.append('{let x=((%d as u64)^(argc() as u64)) as %s;' % (v ^ 1, ty))
                lines.append('print(((x << %d)+(x >>> %d)) as u64);' % (c, 64-c))
                lines.append('print(((x >>> %d)+(x << %d)) as u64);' % (64-c, c))
                lines.append('print((((x^3) << %d)+((x^3) >>> %d)) as u64);}' % (c, 64-c))
            lines.append('}')
            src=t/'test.ck';src.write_text(''.join(lines))
            for flag in [[], ['--scalar']]:
                exe=t/'test';run([SKITE, src, exe, *flag])
                for args in [[], ['extra']]:
                    want=[]
                    for v in VALUES:
                        x=v ^ (1 ^ (len(args)+1))
                        rot=lambda z: ((z << c) | (z >> (64-c))) & MASK
                        want.extend([rot(x), rot(x), rot(x^3)])
                    assert run([exe,*args]) == ''.join(f'{x}\n' for x in want).encode(), (ty,c,args)
                    checks += len(want)
    # Boundary and non-complementary shifts must retain ordinary shift/add semantics.
    for c,d in [(0,64),(64,0),(64,64),(1,1),(5,58),(63,2),(65,63)]:
        src=t/'control.ck'
        src.write_text('fn main(){let x=(18446744073709551614 as u64)^(argc() as u64);print(((x<<%d)+(x>>>%d)) as u64);}' % (c,d))
        want=(((MASK << (c&63)) & MASK)+(MASK >> (d&63))) & MASK
        for flag in [[],['--scalar']]:
            run([SKITE,src,t/'control',*flag]);assert run([t/'control'])==f'{want}\n'.encode();checks+=1
    # Arithmetic right shifts and impure calls are not logical rotates.
    src=t/'effects.ck';src.write_text('let mut count=0;fn next()->u64 {count+=1;return (count as u64)+9223372036854775808;}fn main(){let x=argc()-3;print((x<<5)+(x>>59));print((next()<<5)+(next()>>>59));print(count);}')
    for flag in [[],['--scalar']]:
        run([SKITE,src,t/'effects',*flag]);assert run([t/'effects'])==b'-65\n48\n2\n';checks+=3
    # Different operands and 32-bit arithmetic are outside the 64-bit matcher.
    src=t/'excluded.ck';src.write_text('fn main(){let x=(argc()-1) as u64;let y=(18446744073709551614 as u64)^(argc() as u64);print((x<<5)+(y>>>59));let z=((argc() as u32)^4294967294) as u32;print(((z<<5) as u32)+((z>>>27) as u32));}')
    for flag in [[],['--scalar']]:
        run([SKITE,src,t/'excluded',*flag]);assert run([t/'excluded'])==b'31\n4294967295\n';checks+=2
    # Same pure expression: ADD and established OR form must emit identical code.
    for c in [1,5,31,32,63]:
        binaries=[]
        for op in ['|','+']:
            src=t/'shape.ck';src.write_text('fn main(){let x=(argc() as u64)^18446744073709551615;print((x<<%d)%s(x>>>%d));}' % (c,op,64-c))
            run([SKITE,src,t/'shape']);binaries.append((t/'shape').read_bytes())
        assert binaries[0]==binaries[1], ('rotate code shape',c)
print(f'PASS {checks} rotate-add oracle outputs and 5 identical OR/ADD code shapes')
