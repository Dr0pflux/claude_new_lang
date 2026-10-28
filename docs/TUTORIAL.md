# Learn skite

This is a short, practical introduction. Every program here is in `examples/tutorial/` and runs as shown. The full rules are in `docs/LANGUAGE.md`.

## 0. Build and run

```sh
make                                   # builds the compiler: ./skite
./skite examples/tutorial/01_hello.cock hello
./hello
```

`skite input.cock output` writes a native Linux x86-64 executable. There is no runtime to install and no libraries to link.

## 1. Hello

```text
fn main() {
  write("Hello, world!\n");
  print(6 * 7);
}
```

- `write` outputs text.
- `print` outputs a value and a newline.
- Every program has a `fn main()`.

## 2. Variables and types

```text
let n = 10;                 // untyped constant
let mut total: i64 = 0;     // `mut` = can change
let small: u8 = 200;
let ratio: f64 = 0.75;
let ok = small > 100;       // bool
total += n * small;         // u8 widens to i64 automatically
print(small as i8);         // -56: conversions are explicit with `as`
```

- **Integer types:** `i8 i16 i32 i64` (signed) and `u8 u16 u32 u64` (unsigned).
- **Other types:** `bool`, `f32`, `f64`.
- **Variables:** immutable unless declared `mut`.
- **Promotion:** integer math happens in 64 bits, so `u8 + u8` can't overflow at 255.
- **Narrowing:** going *back* to a narrow type needs `as`, so you always see where a value is cut down.

## 3. Control flow

```text
let mut i = 1;
while i <= 15 {
  if i % 15 == 0 { write("FizzBuzz\n"); }
  else if i % 3 == 0 { write("Fizz\n"); }
  else { print(i); }
  i += 1;
}
```

- **Conditions** must be `bool`: write `x != 0`, not `x`.
- **Loops:** `break` and `continue` work as usual.

## 4. Functions

```text
fn gcd(a: i64, b: i64) -> i64 {
  if b == 0 { return a; }
  return gcd(b, a % b);
}
fn shout(n: i64) { print(n); }     // no `->`: returns nothing
```

- Functions can be in any order and can call themselves.
- Small functions are inlined automatically, so writing helpers costs nothing.

## 5. Arrays and files

```text
let text = file(1);                  // argv[1] as a byte array: [u8]
let count = alloc<u32>(26);          // 26 zeroed counters
let mut i = 0;
while i < len(text) {
  let c = text[i];
  if c >= 97 && c <= 122 { count[c - 97] += 1; }
  i += 1;
}
```

- **Allocating:** `alloc<T>(n)` makes an array of any type.
- **Length and indexing:** `len(a)` is its length; indexes are always bounds-checked.
- **Free when proven:** the compiler removes a check it can **prove** unnecessary. Here it knows `c - 97` is in 0..25.
- **Passing arrays:** `fn f(a: [u8])` takes a read-only array, `fn f(a: mut [u8])` a writable one.

## 6. Structs and globals

```text
struct Word { start: i32, len: u16, count: u32 }

let MAX = 4096;
let words = alloc<Word>(MAX);    // global table, visible in every function
let mut nwords: i64 = 0;         // global counter

fn add(start: i64, n: i64) {
  words[nwords].start = start as i32;
  words[nwords].len = n as u16;
  words[nwords].count = 1;
  nwords += 1;
}
```

- **Structs** are records stored in arrays; access a field with `a[i].field`.
- **Globals:** top-level `let`s are global. Arrays are zeroed at start, and constants have no runtime cost.
- **Example:** `06_structs.cock` counts repeated words in a file with this table.

## 7. Memory without leaks

```text
fn reversed_copy_sum(a: [i64]) -> i64 {
  let tmp = alloc<i64>(len(a));     // scratch space
  ...
  return s;                         // tmp is freed here, automatically
}
```

`alloc` works anywhere:
- **Inside a function:** arrays are freed when the function returns.
- **Inside a loop:** arrays are freed at the end of each iteration.
- **At `main`'s top level:** arrays live for the whole program.

Arrays can't outlive their scope (they can't be returned or stored), so there is never a dangling pointer. You never write `free`, and there is no garbage collector.

## 8. Floats

```text
fn mean(a: [f64]) -> f64 {
  let mut s = 0.0;
  let mut i = 0;
  while i < len(a) { s += a[i]; i += 1; }
  return s / len(a) as f64;
}
```

- Floats never mix with integers silently; use `as`.
- `sqrt(x)` is built in.
- Float to int conversions saturate: `300.7 as u8` is 255, and NaN becomes 0.

## 9. Using every core

```text
let res = shared<i64>(4);
par w in 0..4 { res[w] = work(w + 1); }   // 4 workers in parallel
```

- **Workers:** each one gets a private copy of memory, and only `shared<T>` arrays come back.
- **Checked rules:** the compiler rejects anything that could race or print out of order.

## 10. Writing files

```text
save(1, buf, n);      // first n bytes of buf -> the file named by argv[1]
```

## When something is wrong

- **Compile errors** point at the exact spot:

  ```text
  prog.cock:3:15: error: type mismatch: expected u8, found i64
      let y: u8 = x + 1;
                  ^
  ```

  Fix it with `let y: u8 = (x + 1) as u8;` (wraps), or keep `y` as an `i64`.
- **Runtime errors** stop the program instead of corrupting memory. Output printed before the error is kept.
  - out-of-bounds index: exit code 132
  - integer division by zero: exit code 136

## Next steps

- Read [`LANGUAGE.md`](LANGUAGE.md), the complete reference.
- Look at `bench/vigenere/vig.cock`, a real Vigenère solver that is faster than its gcc -O3 equivalent.
