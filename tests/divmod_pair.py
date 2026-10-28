#!/usr/bin/env python3
"""Paired division/remainder must stay inside unconditional short-circuit regions."""
import os
from pathlib import Path
import signal
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
COMPILER = Path(os.environ.get('SKITE', str(ROOT / 'skite'))).resolve()
PAIR = 'a / b + a % b == 0'
CASES = [
    ('signed_or_skips_pair', f'''fn main() {{ let a = argc(); let b = argc() - 1; let hit: bool = a == 1 || {PAIR}; print(hit); }}''', [], 0, b'true\n'),
    ('signed_and_skips_pair', f'''fn main() {{ let a = argc(); let b = argc() - 1; let hit: bool = a != 1 && {PAIR}; print(hit); }}''', [], 0, b'false\n'),
    ('signed_assignment_skips_pair', f'''fn main() {{ let a = argc(); let b = argc() - 1; let mut hit: bool = false; hit = a == 1 || {PAIR}; print(hit); }}''', [], 0, b'true\n'),
    ('unsigned_or_skips_pair', '''fn main() { let a = argc() as u64; let b = (argc() as u64) - 1; let hit: bool = a == 1 || a / b + a % b == 0; print(hit); }''', [], 0, b'true\n'),
    ('pair_crosses_or_branches', '''fn main() { let a = argc(); let b = argc() - 1; let hit: bool = a == 1 || a / b == 0 || a % b == 0; print(hit); }''', [], 0, b'true\n'),
    ('nested_skipped_pair', f'''fn main() {{ let a = argc(); let b = argc() - 1; let hit: bool = (a == 1 || {PAIR}) && (a == 1 || {PAIR}); print(hit); }}''', [], 0, b'true\n'),
    ('and_executes_nonzero_pair', '''fn main() { let a = argc(); let b = argc() - 1; let hit: bool = a != 1 && a / b + a % b == 2; print(hit); }''', ['x'], 0, b'true\n'),
    ('and_executes_zero_pair_traps', f'''fn main() {{ let a = argc(); let b = argc() - 1; print(9); let hit: bool = a == 1 && {PAIR}; print(hit); }}''', [], None, b'9\n'),
    ('signed_min_over_minus_one_traps', '''fn main() { let a: i64 = 0 - 9223372036854775807 - 1; let b: i64 = 0 - argc(); let z = a / b + a % b; print(z); }''', [], None, b''),
    ('unconditional_signed_pair', '''fn main() { let a = argc() + 17; let b = argc() + 4; let z = a / b + a % b; print(z); }''', [], 0, b'6\n'),
    ('unconditional_unsigned_pair', '''fn main() { let a: u64 = argc() as u64 + 17; let b: u64 = argc() as u64 + 4; let z = a / b + a % b; print(z); }''', [], 0, b'6\n'),
]

with tempfile.TemporaryDirectory(prefix='skite-divmod-pair-') as td:
    tmp = Path(td)
    for name, text, argv, expected_status, expected_out in CASES:
        source = tmp / f'{name}.ck'
        binary = tmp / name
        source.write_text(text + '\n')
        try:
            build = subprocess.run([str(COMPILER), str(source), str(binary)], capture_output=True, timeout=10)
            if build.returncode:
                raise SystemExit(f'FAIL {name}: compile rc={build.returncode}, stderr={build.stderr!r}')
            result = subprocess.run([str(binary), *argv], capture_output=True, timeout=3)
        except subprocess.TimeoutExpired as error:
            raise SystemExit(f'FAIL {name}: timed out') from error
        if expected_status is None:
            good_status = result.returncode in (-signal.SIGFPE, 128 + signal.SIGFPE)
        else:
            good_status = result.returncode == expected_status
        if not good_status or result.stdout != expected_out:
            raise SystemExit(f'FAIL {name}: rc={result.returncode}, stdout={result.stdout!r}, stderr={result.stderr!r}')
print(f'PASS: {len(CASES)} divmod-pair evaluation/trap cases')
