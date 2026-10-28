#!/usr/bin/env python3
"""Scoped array alignment and isolation regression for the generated x86-64 code."""
import os
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent.parent
COMPILER = Path(os.environ.get("SKITE", ROOT / "skite"))
SOURCE = """\
struct Item { tag: u8, score: i64 }

let global_bytes = alloc<u8>(3);
let global_items = alloc<Item>(2);

fn nested() {
  let scratch = alloc<u8>(64);
  print(scratch[0]);
  scratch[0] = 99;
  print(scratch[0]);
}

fn worker(n: i64) {
  let bytes = alloc<u8>(n);
  print(bytes[0]);
  bytes[0] = 7;
  nested();
  print(bytes[0]);
  let items = alloc<Item>(2);
  print(items[0].tag);
  print(items[0].score);
  items[0].tag = 9;
  items[0].score = 123456;
  items[1].tag = 11;
  items[1].score = 654321;
  print(items[0].tag);
  print(items[0].score);
  print(items[1].tag);
  print(items[1].score);
}

fn main() {
  print(global_bytes[0]);
  print(global_items[0].tag);
  print(global_items[0].score);
  global_bytes[0] = 5;
  global_items[0].tag = 6;
  global_items[0].score = 789;
  print(global_bytes[0]);
  print(global_items[0].tag);
  print(global_items[0].score);
  let top = alloc<u64>(2);
  print(top[0]);
  top[0] = 42;
  print(top[0]);
  let shared_top = shared<u8>(2);
  print(shared_top[1]);
  shared_top[1] = 44;
  print(shared_top[1]);
  let mut iteration: i64 = 0;
  while iteration < 2 {
    let loop_bytes = alloc<u8>(iteration + 1);
    print(loop_bytes[0]);
    loop_bytes[0] = (iteration + 21) as u8;
    print(loop_bytes[0]);
    iteration += 1;
  }
  worker(17);
  worker(3);
}
"""
EXPECTED = """\
0
0
0
5
6
789
0
42
0
44
0
21
0
22
0
0
99
7
0
0
9
123456
11
654321
0
0
99
7
0
0
9
123456
11
654321
"""


def load_code_segment(executable):
    image = executable.read_bytes()
    phoff = struct.unpack_from("<Q", image, 32)[0]
    phentsize = struct.unpack_from("<H", image, 54)[0]
    phnum = struct.unpack_from("<H", image, 56)[0]
    for index in range(phnum):
        at = phoff + index * phentsize
        p_type = struct.unpack_from("<I", image, at)[0]
        p_offset, p_vaddr, _, p_filesz = struct.unpack_from("<QQQQ", image, at + 8)
        if p_type == 1 and p_vaddr == 0x400000:
            # ELF header/program headers occupy the first 256 bytes of this segment.
            return image[p_offset + 256:p_offset + p_filesz]
    raise AssertionError("executable has no x86-64 code segment")


class ScopedAlignmentTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.directory = Path(cls.tmp.name)
        cls.source = cls.directory / "alignment.ck"
        cls.executable = cls.directory / "alignment"
        cls.source.write_text(SOURCE)
        subprocess.run([str(COMPILER), str(cls.source), str(cls.executable)],
                       cwd=ROOT, check=True, stdout=subprocess.DEVNULL, timeout=10)
        cls.output = subprocess.run([str(cls.executable)], cwd=ROOT, check=True,
                                    capture_output=True, text=True, timeout=5).stdout
        cls.code = load_code_segment(cls.executable)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_zeroing_nested_isolation_and_scope_reuse(self):
        self.assertEqual(self.output, EXPECTED)

    def test_each_scoped_allocation_aligns_cursor_before_computing_end(self):
        # add rcx, 63; and rcx, -64; lea rdx, [rcx + rax]. The aligned
        # cursor becomes the returned base and the end used by the arena bound check.
        sequence = bytes.fromhex("48 83 c1 3f 48 83 e1 c0 48 8d 14 01")
        self.assertGreaterEqual(self.code.count(sequence), 4)

    def test_static_byte_and_struct_array_bases_remain_cacheline_aligned(self):
        # Find the stores of 5 and 6 used to initialize the two arrays, then
        # inspect their encoded absolute base addresses.
        bases = {}
        for offset in range(len(self.code) - 8):
            if self.code[offset:offset + 3] == b"\xc6\x04\x25":
                address = struct.unpack_from("<I", self.code, offset + 3)[0]
                value = self.code[offset + 7]
                if value in (5, 6):
                    bases[value] = address
        self.assertEqual(set(bases), {5, 6})
        for address in bases.values():
            self.assertEqual(address % 64, 0)

    def test_runtime_alloc_and_shared_paths_use_mmap(self):
        # syscall 9 is mmap; the arena, alloc<T>, and shared<T> each have a call.
        mmap_syscall = bytes.fromhex("b8 09 00 00 00 0f 05")
        self.assertGreaterEqual(self.code.count(mmap_syscall), 3)


if __name__ == "__main__":
    unittest.main()
