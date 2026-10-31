#!/usr/bin/env python3
"""Regression coverage for bootstrap ELF segment overlap and seed output."""
from __future__ import annotations

from pathlib import Path
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SEED = ROOT / "bootstrap" / "skite-seed"


def load_segments(image: bytes) -> list[tuple[int, int, int, int]]:
    if len(image) < 64 or image[:4] != b"\x7fELF" or image[4] != 2 or image[5] != 1:
        raise AssertionError("expected a little-endian ELF64 executable")
    phoff = struct.unpack_from("<Q", image, 32)[0]
    phentsize = struct.unpack_from("<H", image, 54)[0]
    phnum = struct.unpack_from("<H", image, 56)[0]
    if phentsize < 56 or phoff + phentsize * phnum > len(image):
        raise AssertionError("malformed ELF program-header table")
    out = []
    for i in range(phnum):
        p_type, _flags, _offset, vaddr, _paddr, filesz, memsz, _align = struct.unpack_from(
            "<IIQQQQQQ", image, phoff + i * phentsize
        )
        if p_type == 1:  # PT_LOAD
            if filesz > memsz:
                raise AssertionError(f"ELF LOAD {i} has p_filesz > p_memsz")
            out.append((i, vaddr, filesz, memsz))
    if not out:
        raise AssertionError("ELF has no PT_LOAD segments")
    return out


def assert_disjoint_loads(image: bytes, label: str) -> None:
    segs = load_segments(image)
    for n, (i, start, _filesz, size) in enumerate(segs):
        end = start + size
        for j, other_start, _other_filesz, other_size in segs[n + 1 :]:
            other_end = other_start + other_size
            if start < other_end and other_start < end:
                raise AssertionError(
                    f"ELF PT_LOAD overlap in {label}: LOAD {i} "
                    f"[0x{start:x},0x{end:x}) intersects LOAD {j} "
                    f"[0x{other_start:x},0x{other_end:x})"
                )


def run(*args: str, timeout: int = 90, **kwargs: object) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(args, check=True, timeout=timeout, **kwargs)


def compile_with(compiler: Path, source: Path, output: Path) -> None:
    run(str(compiler), str(source), str(output), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert_disjoint_loads(output.read_bytes(), str(output))


def main() -> None:
    # Inject the historical overlap into a real ELF's program headers and make
    # sure the same parser used on compiler output diagnoses it.
    probe = bytearray(SEED.read_bytes())
    segments = load_segments(probe)
    first, second = segments[:2]
    first_end = first[1] + first[3]
    injected_start = (first_end - 0x1000) & ~0xFFF
    phoff = struct.unpack_from("<Q", probe, 32)[0]
    phentsize = struct.unpack_from("<H", probe, 54)[0]
    phnum = struct.unpack_from("<H", probe, 56)[0]
    load_indices = []
    for i in range(phnum):
        if struct.unpack_from("<I", probe, phoff + i * phentsize)[0] == 1:
            load_indices.append(i)
    second_ph = phoff + load_indices[1] * phentsize
    struct.pack_into("<Q", probe, second_ph + 16, injected_start)
    struct.pack_into("<Q", probe, second_ph + 24, injected_start)
    try:
        assert_disjoint_loads(bytes(probe), "synthetic PHDR overlap")
    except AssertionError as exc:
        if "LOAD" not in str(exc) or "intersects" not in str(exc):
            raise
    else:
        raise AssertionError("synthetic overlapping ELF program headers were accepted")

    with tempfile.TemporaryDirectory(prefix="skite-bootstrap-elf-") as temp:
        td = Path(temp)
        assert_disjoint_loads(SEED.read_bytes(), str(SEED))

        trivial = td / "trivial.ck"
        trivial.write_text(
            "fn print_int(x: i64) { if x >= 10 { print_int(x / 10); } "
            "putc(x % 10 + 48); }\n"
            "fn main() { print_int(42); putc(10); }\n"
        )
        trivial_exe = td / "trivial"
        compile_with(SEED, trivial, trivial_exe)
        actual = run(str(trivial_exe), stdout=subprocess.PIPE).stdout
        if actual != b"42\n":
            raise AssertionError(f"seed-built trivial output was {actual!r}, expected b'42\\n'")

        # A source-sized string keeps code modest while pushing the emitted RX
        # image over the historical 2 MiB boundary (old BSS began at 6 MiB).
        padded_source = td / "padded-skite.ck"
        padded_source.write_bytes((ROOT / "skite.ck").read_bytes() + b'\nlet BOOTSTRAP_PADDING = "' + b"A" * 350_000 + b'";\n')
        padded_compiler = td / "padded-compiler"
        compile_with(SEED, padded_source, padded_compiler)
        rx_filesz = load_segments(padded_compiler.read_bytes())[0][2]
        if rx_filesz <= 0x200000:
            raise AssertionError(f"padding fixture did not exceed 2 MiB RX size: 0x{rx_filesz:x}")
        padded_trivial = td / "padded-trivial"
        compile_with(padded_compiler, trivial, padded_trivial)
        actual = run(str(padded_trivial), stdout=subprocess.PIPE).stdout
        if actual != b"42\n":
            raise AssertionError(f"large-image compiler output was {actual!r}, expected b'42\\n'")

    print("PASS: seed ELF loads are disjoint; >2 MiB compiler image stays disjoint and runs a trivial program")

if __name__ == "__main__":
    main()
