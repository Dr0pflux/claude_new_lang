// Runtime expression: argc() cannot be folded at compile time.
fn main() -> i64 {
    let n: i64 = argc();
    return ((n * 29) + 17) % 100;
}
