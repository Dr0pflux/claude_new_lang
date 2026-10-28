// usage: ./save out.txt   -> writes a file
fn main() {
  let buf = alloc<u8>(64);
  let msg = "made by skite\n";
  let mut i = 0;
  while i < len(msg) { buf[i] = msg[i]; i += 1; }
  save(1, buf, len(msg));
}
