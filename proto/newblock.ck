// operand kinds: 0 register group, 1 constant-pool broadcast, 2 one register holding a uniform
// value (the same for every half), 3 broadcast memory operand (a uniform 8-byte value, VOM_*)
let mut VOK: i64 = 0;
let mut VOR: i64 = 0;
let mut VOM_B: i64 = 0;
let mut VOM_I: i64 = -1;
let mut VOM_S: i64 = 0;
let mut VOM_D: i64 = 0;
fn vom() { vm_mem(VOM_B, VOM_I, VOM_S, VOM_D); VM_TAIL = 0; }
// what the temporaries hold while one expression or condition is generated: vr(t) holds the
// value of tcont[t] (-1: nothing known), as a register group (tkind 0) or one register (2)
let tcont = alloc<i64>(64);
let tkind = alloc<i64>(64);
fn tset(t: i64, e: i64, k: i64) { tcont[t] = e; tkind[t] = k; }
fn tclr_all() { let mut t = 0; while t < 64 { tcont[t] = -1; t += 1; } }
fn vsame(a: i64, b: i64) -> bool {
  if a == b { return true; }
  let k = nd[a].k;
  if k != nd[b].k || nd[a].op != nd[b].op || nd[a].ty != nd[b].ty { return false; }
  if k == N_CONST { return nd[a].v == nd[b].v; }
  if k == N_VAR { return nd[a].var == nd[b].var; }
  if k == N_LOAD { return nd[a].var == nd[b].var && vsame(nd[a].a, nd[b].a); }
  if k == N_UN { return vsame(nd[a].a, nd[b].a); }
  if k == N_BIN { return vsame(nd[a].a, nd[b].a) && vsame(nd[a].b, nd[b].b); }
  return false;
}
// dst{mask} = a OP b over every half. a: kind ak (0 or 2); b: kind bk (0..3)
fn vop3x(mm: i64, pp: i64, opc: i64, d: i64, ak: i64, a: i64, bk: i64, b: i64, lvl: i64) {
  let mut h = 0;
  while h < VU {
    let ah = if_sel(ak == 0, a + h, a);
    if bk == 0 { evx(mm, pp, 1, 2, opc, d + h, ah, 0, b + h, kreg(lvl, h), false, false); }
    else if bk == 2 { evx(mm, pp, 1, 2, opc, d + h, ah, 0, b, kreg(lvl, h), false, false); }
    else {
      if bk == 1 { VM_TAIL = 0; vm_pool(b); } else { vom(); }
      evx(mm, pp, 1, 2, opc, d + h, ah, 1, 0, kreg(lvl, h), false, true);
    }
    h += 1;
  }
}
fn vop3(mm: i64, pp: i64, opc: i64, d: i64, a: i64, bk: i64, b: i64, lvl: i64) { vop3x(mm, pp, opc, d, 0, a, bk, b, lvl); }
fn vshift(dig: i64, opc: i64, d: i64, a: i64, k: i64, lvl: i64) {   // vpsllq/vpsrlq (73 /6, /2), vpsraq (72 /4)
  let mut h = 0;
  while h < VU { evx(1, 1, 1, 2, opc, dig, d + h, 0, a + h, kreg(lvl, h), false, false); byte(k & 63); h += 1; }
}
fn vmov(d: i64, a: i64, lvl: i64) {   // vmovdqa64 d{k}, a
  if d == a && lvl < 0 { return; }
  let mut h = 0;
  while h < VU { evx(1, 1, 1, 2, 111, d + h, 0, 0, a + h, kreg(lvl, h), false, false); h += 1; }
}
fn vbcp(d: i64, off: i64, lvl: i64, nh: i64) {   // vpbroadcastq d{k}, [pool]
  let mut h = 0;
  while h < nh { VM_TAIL = 0; vm_pool(off); evx(2, 1, 1, 2, 89, d + h, 0, 1, 0, kreg(lvl, h), false, false); h += 1; }
}
fn vbc_pool(d: i64, off: i64, lvl: i64) { vbcp(d, off, lvl, VU); }
fn vbcg(d: i64, r: i64, lvl: i64, nh: i64) {      // vpbroadcastq d{k}, r64
  let mut h = 0;
  while h < nh { evx(2, 1, 1, 2, 124, d + h, 0, 0, r, kreg(lvl, h), false, false); h += 1; }
}
// broadcast a uniform scalar expression into nh registers d, d + 1, ..
fn vbcast(e: i64, d: i64, lvl: i64, nh: i64) {
  let k = nd[e].k;
  if k == N_CONST { vbcp(d, cp_u64(nd[e].v), lvl, nh); return; }
  if k == N_VAR {
    loc(nd[e].var);
    if OK == K_REG { vbcg(d, ORR, lvl, nh); return; }
    if OK == K_XMM { let mut h = 0; while h < nh { evx(2, 1, 1, 2, 25, d + h, 0, 0, ORR, kreg(lvl, h), false, false); h += 1; } return; }
    if OK == K_MEM { let mut h = 0; while h < nh { vm_mem(RSP, -1, 0, ORR * 8 + sp_adj); evx(2, 1, 1, 2, 89, d + h, 0, 1, 0, kreg(lvl, h), false, false); h += 1; } return; }
  }
  gen(e, VRG, VN); vbcg(d, RGS[VRG], lvl, nh);
}
fn fp_nan(v: u64) -> bool { return (v & 9218868437227405312) == 9218868437227405312 && (v & 4503599627370495) != 0; }
// a uniform load of an 8-byte value: usable as a broadcast memory operand
fn vmem_ok(e: i64) -> bool {
  if nd[e].k != N_LOAD { return false; }
  let ft = fld_ty(nd[e].var, nd[e].op);
  return ft == TY_F64 || ft == TY_I64 || ft == TY_U64;
}
// operand for e: a register group (computed into vr(t) if needed), a uniform value or a pool constant.
// A temporary at or below t that already holds e is reused (temporaries below t stay live).
fn vopnd(e: i64, t: i64) {
  let k = nd[e].k;
  if k == N_CONST { VOK = 1; VOR = cp_u64(nd[e].v); return; }
  if k == N_VAR && is_v(nd[e].var) { VOK = 0; VOR = VREG[nd[e].var]; return; }
  let mut u = 0;
  while u <= t { if tcont[u] >= 0 && vsame(tcont[u], e) { VOK = tkind[u]; VOR = vr(u); return; } u += 1; }
  if !refs_v(e) {
    if k == N_VAR {
      loc(nd[e].var);
      if OK == K_MEM { VOK = 3; VOM_B = RSP; VOM_I = -1; VOM_S = 0; VOM_D = ORR * 8 + sp_adj; return; }
    }
    if vmem_ok(e) {
      elem_addr(nd[e].var, nd[e].a, nd[e].chk, fld_off(nd[e].var, nd[e].op), VRG, VN);
      VOK = 3; VOM_B = EA_B; VOM_I = EA_RI; VOM_S = EA_SC; VOM_D = mdisp; mdisp = 0; return;
    }
    vbcast(e, vr(t), -1, 1); tset(t, e, 2); VOK = 2; VOR = vr(t); return;
  }
  vgen_into(e, vr(t), -1, t); tset(t, e, 0); VOK = 0; VOR = vr(t);
}
// the current operand (a constant or memory broadcast) into the one register vr(t)
fn vmat(t: i64, e: i64) {
  if VOK != 1 && VOK != 3 { return; }
  if VOK == 1 { VM_TAIL = 0; vm_pool(VOR); } else { vom(); }
  evx(2, 1, 1, 2, 89, vr(t), 0, 1, 0, 0, false, false);
  tset(t, e, 2); VOK = 2; VOR = vr(t);
}
// the current operand into a register group (vr(t) unless it is one already)
fn vgrp(t: i64, e: i64) {
  if VOK == 0 { return; }
  let d = vr(t);
  let mut h = 0;
  while h < VU {
    if VOK == 1 { VM_TAIL = 0; vm_pool(VOR); evx(2, 1, 1, 2, 89, d + h, 0, 1, 0, 0, false, false); }
    else if VOK == 3 { vom(); evx(2, 1, 1, 2, 89, d + h, 0, 1, 0, 0, false, false); }
    else { evx(1, 1, 1, 2, 111, d + h, 0, 0, VOR, 0, false, false); }
    h += 1;
  }
  tset(t, e, 0); VOK = 0; VOR = d;
}
fn vfop(op: i64) -> i64 { if op == O_FADD { return 88; } if op == O_FSUB { return 92; } if op == O_FMUL { return 89; } return 94; }
fn viop(op: i64) -> i64 { if op == O_ADD { return 212; } if op == O_SUB { return 251; } if op == O_AND { return 219; } if op == O_OR { return 235; } return 239; }
// e into register group d under mask level lvl (merge: inactive lanes keep d), temporaries from t
fn vgen_into(e: i64, d: i64, lvl: i64, t: i64) {
  let k = nd[e].k;
  if !refs_v(e) { vbcast(e, d, lvl, VU); return; }
  if k == N_VAR { vmov(d, VREG[nd[e].var], lvl); return; }
  if k == N_LOAD {
    let a = nd[e].var;
    gen(nd[e].a, VRG, VN);
    let ri = RGS[VRG];
    let b = base_reg(a);
    let mut h = 0;
    while h < VU { vm_mem(b, ri, 3, 64 * h); evx(1, 2, 1, 2, 111, d + h, 0, 1, 0, kreg(lvl, h), false, false); h += 1; }   // vmovdqu64
    return;
  }
  if k == N_UN {
    let op = nd[e].op;
    vopnd(nd[e].a, t); vgrp(t, nd[e].a);
    let ar = VOR;
    if op == U_FNEG { vop3(1, 1, 239, d, ar, 1, cp_u64(9223372036854775808), lvl); return; }
    if op == U_NOT { vop3(1, 1, 239, d, ar, 1, cp_u64(18446744073709551615), lvl); return; }
    if op == U_NEG { let z = vr(t + 1); tcont[t + 1] = -1; vop3(1, 1, 239, z, z, 0, z, -1); vop3(1, 1, 251, d, z, 0, ar, lvl); return; }
    if op == U_SQRTD { let mut h = 0; while h < VU { evx(1, 1, 1, 2, 81, d + h, 0, 0, ar + h, kreg(lvl, h), false, false); h += 1; } return; }
    if op == U_I2D { let mut h = 0; while h < VU { evx(1, 2, 1, 2, 230, d + h, 0, 0, ar + h, kreg(lvl, h), false, false); h += 1; } return; }
    if op == U_ZX8 { vop3(1, 1, 219, d, ar, 1, cp_u64(255), lvl); return; }
    if op == U_ZX16 { vop3(1, 1, 219, d, ar, 1, cp_u64(65535), lvl); return; }
    if op == U_ZX32 { vop3(1, 1, 219, d, ar, 1, cp_u64(4294967295), lvl); return; }
    let mut sh = 32; if op == U_SX8 { sh = 56; } else if op == U_SX16 { sh = 48; }
    let tt = vr(t + 1); tcont[t + 1] = -1;
    vshift(6, 115, tt, ar, sh, -1); vshift(4, 114, d, tt, sh, lvl); return;
  }
  let op = nd[e].op;
  let a = nd[e].a; let b = nd[e].b;
  if op == O_SHL || op == O_SHR || op == O_SAR {
    vopnd(a, t); vgrp(t, a); let ar = VOR;
    let c = (nd[b].v & 63) as i64;
    if op == O_SHL { vshift(6, 115, d, ar, c, lvl); } else if op == O_SHR { vshift(2, 115, d, ar, c, lvl); } else { vshift(4, 114, d, ar, c, lvl); }
    return;
  }
  if op == O_DIV || op == O_MOD || op == O_DIVU || op == O_MODU {
    vopnd(a, t); vgrp(t, a); let ar = VOR;
    let dv = nd[b].v;
    let mut kk = 0; while ((1 as u64) << (kk as u64)) != dv { kk += 1; }
    if op == O_DIVU || (op == O_DIV && nd[e].nn != 0) {
      if op == O_DIVU { vshift(2, 115, d, ar, kk, lvl); } else { vshift(4, 114, d, ar, kk, lvl); }
      return;
    }
    if op == O_MODU || nd[e].nn != 0 { vop3(1, 1, 219, d, ar, 1, cp_u64(dv - 1), lvl); return; }
    let tt = vr(t + 1); tcont[t + 1] = -1;
    vshift(4, 114, tt, ar, 63, -1);
    if kk > 0 { vshift(2, 115, tt, tt, 64 - kk, -1); } else { vop3(1, 1, 239, tt, tt, 0, tt, -1); }
    vop3(1, 1, 212, tt, ar, 0, tt, -1);                    // x + bias
    if op == O_DIV { vshift(4, 114, d, tt, kk, lvl); return; }
    vop3(1, 1, 219, tt, tt, 1, cp_u64(0 - dv), -1);        // & -2^k
    vop3(1, 1, 251, d, ar, 0, tt, lvl);                    // x - that
    return;
  }
  let fp = op == O_FADD || op == O_FSUB || op == O_FMUL || op == O_FDIV;
  let comm = op == O_FADD || op == O_FMUL || op == O_ADD || op == O_MUL || op == O_AND || op == O_OR || op == O_XOR;
  vopnd(a, t);
  // a memory operand would not survive b's code; a constant stays one only if the operands may swap
  if VOK == 3 || (VOK == 1 && (!comm || (fp && fp_nan(nd[a].v)))) { vmat(t, a); }
  let mut ak = VOK; let mut ar = VOR;
  vopnd(b, t + 1);
  let mut bk = VOK; let mut br = VOR;
  if ak == 1 {
    if bk != 0 { fail("internal: uniform vector operation"); }
    let c = ar; ak = 0; ar = br; bk = 1; br = c;
  }
  if fp { vop3x(1, 1, vfop(op), d, ak, ar, bk, br, lvl); return; }
  if op == O_MUL { vop3x(2, 1, 64, d, ak, ar, bk, br, lvl); return; }
  vop3x(1, 1, viop(op), d, ak, ar, bk, br, lvl);
}
// condition -> mask level lvl, restricted to mask level pm (-1: all lanes)
fn vcmp_pred(op: i64) -> i64 {
  if op == O_EQ || op == O_FEQ { return 0; } if op == O_LT || op == O_LTU || op == O_FLT { return 1; }
  if op == O_LE || op == O_LEU || op == O_FLE { return 2; } if op == O_NE || op == O_FNE { return 4; }
  if op == O_FGT { return 14; } if op == O_FGE { return 13; }
  if op == O_GE || op == O_GEU { return 5; } return 6;
}
fn vcond(e: i64, dst: i64, pm: i64, neg: bool) {
  let k = nd[e].k;
  if !refs_v(e) {
    gen(e, VRG, VN); let r = RGS[VRG];
    if neg { alui(A_XOR, r, 1); }
    unop(3, K_REG, r);
    kmov_kr(0, r);
    let mut h = 0;
    while h < VU { kand(kreg(dst, h), 0, kpar(pm, h)); h += 1; }
    return;
  }
  if k == N_UN { vcond(nd[e].a, dst, pm, !neg); return; }
  let op = nd[e].op;
  if (op == O_LAND && !neg) || (op == O_LOR && neg) { vcond(nd[e].a, dst, pm, neg); vcond(nd[e].b, dst, dst, neg); return; }
  if op == O_LAND || op == O_LOR {
    let t = mx(dst, pm) + 1;
    vcond(nd[e].a, t, pm, neg); vcond(nd[e].b, t + 1, pm, neg);
    let mut h = 0; while h < VU { kor(kreg(dst, h), kreg(t, h), kreg(t + 1, h)); h += 1; }
    return;
  }
  let a = nd[e].a; let b = nd[e].b;
  vopnd(a, 0); if VOK == 3 { vmat(0, a); }
  let mut ak = VOK; let mut ar = VOR;
  vopnd(b, 1);
  let mut bk = VOK; let mut br = VOR;
  let mut o = op;
  if ak == 1 {
    if bk != 0 { fail("internal: uniform vector comparison"); }
    let c = ar; ak = 0; ar = br; bk = 1; br = c; o = swap_cmp(op);
  }
  let fl = op >= O_FEQ && op <= O_FGE;
  let uns = op == O_LTU || op == O_LEU || op == O_GTU || op == O_GEU;
  let mut pred = vcmp_pred(o);
  if neg { pred = pred ^ 4; }
  let mut h = 0;
  while h < VU {
    let ah = if_sel(ak == 0, ar + h, ar);
    let mut rmk = 0; let mut rr = 0;
    if bk == 0 { rr = br + h; } else if bk == 2 { rr = br; }
    else { rmk = 1; if bk == 1 { vm_pool(br); } else { vom(); } }
    VM_TAIL = 1;
    if fl { evx(1, 1, 1, 2, 194, kreg(dst, h), ah, rmk, rr, kreg(pm, h), false, rmk == 1); }
    else if uns { evx(3, 1, 1, 2, 30, kreg(dst, h), ah, rmk, rr, kreg(pm, h), false, rmk == 1); }
    else { evx(3, 1, 1, 2, 31, kreg(dst, h), ah, rmk, rr, kreg(pm, h), false, rmk == 1); }
    byte(pred);
    VM_TAIL = 0;
    h += 1;
  }
}
