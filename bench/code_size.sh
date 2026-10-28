#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
CC=${CC:-cc}
T=$(mktemp -d);trap 'rm -rf "$T"' EXIT
"$CC" -std=c11 -O2 bootstrap/ling0_s0.c -o "$T/s0"
"$CC" -std=c11 -O2 ling0.c -o "$T/s1"
printf 'source,s0_machine_bytes,s1_machine_bytes,s0_elf_bytes,s1_elf_bytes\n'
for src in examples/*.cock;do
  old=$("$T/s0" "$src" "$T/old")
  new=$("$T/s1" "$src" "$T/new")
  old_b=$(printf '%s' "$old" | sed -E 's/.*\(([0-9]+) bytes, ([0-9]+) machine-code bytes.*/\2/')
  new_b=$(printf '%s' "$new" | sed -E 's/.*\(([0-9]+) bytes, ([0-9]+) machine-code bytes.*/\2/')
  printf '%s,%s,%s,%s,%s\n' "$src" "$old_b" "$new_b" "$(wc -c < "$T/old")" "$(wc -c < "$T/new")"
done
printf '\nCode size only: this is NOT a runtime speed benchmark.\n'
