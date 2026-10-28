// Test driver for tests/enc_unit.py (run by tests/enc_check.py).  The encoder functions of skite.ck
// (byte, enc, mov_rr, alu, memop, evx, ...) are pasted in front of this file; this program feeds
// them test vectors and records the bytes they emit.
//
//   enc_unit harness CASES CODE MARKS
//     CASES  argv[1]: records of 21 little-endian i64: op, a0 .. a19
//     CODE   argv[2]: the concatenated machine code of all cases
//     MARKS  argv[3]: per case two little-endian i64: end offset in CODE, return value of the case
//
// Every dispatch line has the form `if op == N { ... } // name`; the python side reads N and name from here.
fn fail(msg: [u8]) { ewrite("encoder: "); ewrite(msg); ewrite("\n"); exit(1); }
let A = alloc<i64>(20);
let POOL_AT = 4096;       // pretend address (image offset) of the constant pool for the rip-relative cases
// what generate() does with the constant-pool references once the pool address is known
fn pool_fix() {
  let at = cp_at[ncp - 1];
  patch32(at, POOL_AT + cp_off[ncp - 1] - (at + 4 + cp_tail[ncp - 1]));
}
fn tail() { if A[16] >= 0 { byte(A[16]); } }      // trailing imm8 of the vector instruction
fn step(op: i64) -> i64 {
  if op == 1 { mov_rr(A[0], A[1]); }                                                          // mov_rr
  if op == 2 { mov_ri(A[0], A[1] as u64); }                                                   // mov_ri
  if op == 3 { load(A[0], A[1], A[2], A[3] as u64); }                                         // load
  if op == 4 { store(A[0], A[1], A[2]); }                                                     // store
  if op == 5 { alu(A[0], A[1], A[2], A[3], A[4], A[5] as u64); }                              // alu
  if op == 6 { alur(A[0], A[1], A[2]); }                                                      // alur
  if op == 7 { alui(A[0], A[1], A[2] as u64); }                                               // alui
  if op == 8 { imul_r(A[0], A[1], A[2], A[3] as u64); }                                       // imul_r
  if op == 9 { shift_ri(A[0], A[1], A[2]); }                                                  // shift_ri
  if op == 10 { lea(A[0], A[1], A[2], A[3]); }                                                // lea
  if op == 11 { mdisp = A[10]; memop(A[0], A[1] != 0, A[2] != 0, A[3], A[4], A[5], A[6], A[7], A[8], A[9]); }   // memop
  if op == 12 { mdisp = A[5]; load_elem(A[0], A[1], A[2], A[3], A[4]); }                      // load_elem
  if op == 13 { mdisp = A[6]; store_elem(A[0], A[1], A[2], A[3], A[4], A[5]); }               // store_elem
  if op == 14 { EA_B = A[3]; EA_RI = A[4]; EA_SC = A[5]; mdisp = A[6]; store_elem_imm(A[0], A[1], A[2] as u64); }   // store_elem_imm
  if op == 15 { unop(A[0], A[1], A[2]); }                                                     // unop
  if op == 16 { setcc_zx(A[0], A[1]); }                                                       // setcc_zx
  if op == 17 { test_rr(A[0]); }                                                              // test_rr
  if op == 18 { cqo(); }                                                                      // cqo
  if op == 19 { let at = jcc(A[0]); rel32(at, at + 4 + A[1]); return at; }                    // jcc
  if op == 20 { let at = jmp(); rel32(at, at + 4 + A[0]); return at; }                        // jmp
  if op == 21 { let at = j8(A[0]); p8(at, at + 1 + A[1]); return at; }                        // j8
  if op == 22 { sse(A[0], A[1], A[2], A[3], A[4], A[5]); }                                    // sse
  if op == 23 { fload(A[0], A[1], A[2], A[3] as u64, A[4] != 0); }                            // fload
  if op == 24 { fstore(A[0], A[1], A[2] != 0); }                                              // fstore
  if op == 25 { movx(A[0], A[1]); }                                                           // movx
  if op == 26 { push_r(A[0]); }                                                               // push_r
  if op == 27 { pop_r(A[0]); }                                                                // pop_r
  if op == 28 { abs_op(A[0], A[1], A[2]); }                                                   // abs_op
  if op == 29 { sp_adj = A[8]; enc(A[0], A[1] != 0, A[2], A[3], A[4], A[5], A[6], A[7]); sp_adj = 0; }   // enc
  if op == 30 { evx(A[0], A[1], A[2], A[3], A[4], A[5], A[6], 0, A[8], A[9], A[10] != 0, A[11] != 0); tail(); }   // evx_reg
  if op == 31 { vm_mem(A[12], A[13], A[14], A[15]); evx(A[0], A[1], A[2], A[3], A[4], A[5], A[6], 1, 0, A[9], A[10] != 0, A[11] != 0); tail(); }   // evx_mem
  if op == 32 { VM_TAIL = A[13]; vm_pool(A[12]); evx(A[0], A[1], A[2], A[3], A[4], A[5], A[6], 1, 0, A[9], A[10] != 0, A[11] != 0); tail(); pool_fix(); }   // evx_pool
  if op == 33 { vm_abs(A[12]); evx(A[0], A[1], A[2], A[3], A[4], A[5], A[6], 1, 0, A[9], A[10] != 0, A[11] != 0); tail(); }   // evx_abs
  if op == 34 { kmov_kr(A[0], A[1]); }                                                        // kmov_kr
  if op == 35 { kmov_rk(A[0], A[1]); }                                                        // kmov_rk
  if op == 36 { kand(A[0], A[1], A[2]); }                                                     // kand
  if op == 37 { kandn(A[0], A[1], A[2]); }                                                    // kandn
  if op == 38 { kor(A[0], A[1], A[2]); }                                                      // kor
  if op == 39 { kortest(A[0], A[1]); }                                                        // kortest
  if op == 40 { kmovk(A[0], A[1]); }                                                          // kmovk
  if op == 41 { return cp_u64(A[0] as u64); }                                                 // cp_u64
  if op == 42 { return cp_iota(A[0]); }                                                       // cp_iota
  if op == 43 { let mut x: u64 = 0; let mut j = 7; while j >= 0 { x = (x << 8) | (cpool[A[0] + j] as u64); j -= 1; } return x as i64; }   // cp_peek
  if op == 44 { return cplen; }                                                               // cp_len
  if op == 45 { let at = clen; u32_(0); patch32(at, A[0]); rel32(at, A[1]); return at; }      // rel32
  if op == 46 { u64_(A[0] as u64); }                                                          // u64_
  if op == 47 { byte(A[11]); mdisp = A[10]; memop(A[0], A[1] != 0, A[2] != 0, A[3], A[4], A[5], A[6], A[7], A[8], A[9]); }   // pmemop
  return 0;
}
fn rd(f: [u8], at: i64) -> i64 {
  let mut x: u64 = 0;
  let mut j = 7;
  while j >= 0 { x = (x << 8) | (f[at + j] as u64); j -= 1; }
  return x as i64;
}
fn main() {
  let f = file(1);
  let n = len(f) / 168;
  let marks = alloc<u8>(16 * n + 16);
  let mut c = 0;
  while c < n {
    let mut j = 0;
    while j < 20 { A[j] = rd(f, c * 168 + 8 + 8 * j); j += 1; }
    let r = step(rd(f, c * 168));
    let mut b = 0;
    while b < 8 { marks[16 * c + b] = ((clen >> (8 * b)) & 255) as u8; marks[16 * c + 8 + b] = ((r >> (8 * b)) & 255) as u8; b += 1; }
    c += 1;
  }
  save(2, code, clen);
  save(3, marks, 16 * n);
}
