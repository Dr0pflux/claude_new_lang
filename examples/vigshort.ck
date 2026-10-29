// vigshort.ck | standalone short-text Vigenere solver for Skite
// No corpus file, dictionary file, or trained n-gram model.
// A custom, manually specified English orthographic heuristic is used.
// Input: one ciphertext per line. Optional @CRIB line applies to next line.
// Digits/punctuation are preserved; only ASCII alphabetic symbols advance key.

fn upper(ch: u8) -> i64 {
    if ch >= 97 && ch <= 122 { return ch - 32; }
    return ch;
}
fn is_letter(ch: u8) -> bool {
    return (ch >= 65 && ch <= 90) || (ch >= 97 && ch <= 122);
}
fn pair(a: i64, b: i64, x: i64, y: i64) -> bool {
    return a == x && b == y;
}
fn tri(a: i64, b: i64, c: i64, x: i64, y: i64, z: i64) -> bool {
    return a == x && b == y && c == z;
}
fn vowel(x: i64) -> bool {
    return x == 0 || x == 4 || x == 8 || x == 14 || x == 20 || x == 24;
}
fn shape_score(p: [u8], n: i64, ws: [u8], we: [u8]) -> i64 {
    let mut sc: i64 = 0;
    let mut st: i64 = 0;
    while st < n {
        let mut en = st;
        while en < n && we[en] == 0 { en += 1; }
        if en >= n { en = n - 1; }
        let ln = en - st + 1;
        let a: i64 = p[st];
        let mut b: i64 = 0;
        let mut c: i64 = 0;
        if ln > 1 { b = p[st + 1]; }
        if ln > 2 { c = p[st + 2]; }
        if ln == 1 {
            if a == 0 || a == 8 { sc += 95; } else { sc -= 160; }
        } else if ln == 2 {
            let mut good = false;
            if pair(a,b,14,5) || pair(a,b,19,14) || pair(a,b,8,13) || pair(a,b,8,19) ||
               pair(a,b,8,18) || pair(a,b,0,18) || pair(a,b,0,19) || pair(a,b,14,13) ||
               pair(a,b,1,24) || pair(a,b,0,13) || pair(a,b,14,17) || pair(a,b,8,5) ||
               pair(a,b,20,15) || pair(a,b,20,18) || pair(a,b,22,4) || pair(a,b,7,4) ||
               pair(a,b,12,4) || pair(a,b,12,24) || pair(a,b,3,14) || pair(a,b,13,14) ||
               pair(a,b,18,14) || pair(a,b,6,14) || pair(a,b,0,12) || pair(a,b,1,4) ||
               pair(a,b,22,7) || pair(a,b,14,10) || pair(a,b,19,7) || pair(a,b,7,8) {
                good = true;
            }
            if good { sc += 105; } else { sc -= 100; }
        } else if ln == 3 {
            if tri(a,b,c,19,7,4) || tri(a,b,c,0,13,3) || tri(a,b,c,24,14,20) ||
               tri(a,b,c,5,14,17) || tri(a,b,c,0,17,4) || tri(a,b,c,13,14,19) ||
               tri(a,b,c,1,20,19) || tri(a,b,c,2,0,13) || tri(a,b,c,3,8,3) ||
               tri(a,b,c,22,0,18) || tri(a,b,c,7,8,18) || tri(a,b,c,7,4,17) ||
               tri(a,b,c,14,13,4) || tri(a,b,c,14,20,17) || tri(a,b,c,0,11,11) ||
               tri(a,b,c,0,13,24) || tri(a,b,c,6,4,19) || tri(a,b,c,6,14,19) ||
               tri(a,b,c,7,0,18) || tri(a,b,c,7,14,22) || tri(a,b,c,22,7,14) ||
               tri(a,b,c,14,20,19) || tri(a,b,c,18,0,24) || tri(a,b,c,13,14,22) ||
               tri(a,b,c,13,4,22) || tri(a,b,c,19,22,14) || tri(a,b,c,19,14,14) ||
               tri(a,b,c,18,4,4) || tri(a,b,c,18,7,4) || tri(a,b,c,7,8,12) ||
               tri(a,b,c,8,19,18) || tri(a,b,c,24,4,18) {
                sc += 135;
            } else { sc -= 22; }
        }
        let mut v: i64 = 0;
        let mut run: i64 = 0;
        for i in st..en + 1 {
            if vowel(p[i]) { v += 1; run = 0; }
            else { run += 1; if run >= 4 { sc -= 32; } }
        }
        if ln >= 4 && v == 0 { sc -= 110; }
        if ln >= 6 && v == 1 { sc -= 25; }
        st = en + 1;
    }
    return sc;
}
fn language_score(p: [u8], n: i64, uni: [i64], ws: [u8], we: [u8], use_words: bool) -> i64 {
    let mut sc: i64 = 0;
    for i in 0..n {
        let a: i64 = p[i];
        sc += uni[a];
        if a == 16 && i + 1 < n && p[i+1] != 20 { sc -= 190; }
        if i > 0 {
            let b: i64 = p[i-1];
            if pair(b,a,19,7) { sc += 49; }
            if pair(b,a,7,4) { sc += 42; }
            if pair(b,a,8,13) { sc += 29; }
            if pair(b,a,4,17) { sc += 24; }
            if pair(b,a,0,13) { sc += 28; }
            if pair(b,a,17,4) { sc += 25; }
            if pair(b,a,14,13) { sc += 22; }
            if pair(b,a,0,19) { sc += 24; }
            if pair(b,a,4,13) { sc += 21; }
            if pair(b,a,13,3) { sc += 20; }
            if pair(b,a,19,8) { sc += 22; }
            if pair(b,a,4,18) { sc += 21; }
            if pair(b,a,14,17) { sc += 19; }
            if pair(b,a,14,5) { sc += 33; }
            if pair(b,a,8,18) { sc += 21; }
            if pair(b,a,8,19) { sc += 24; }
            if pair(b,a,14,20) { sc += 20; }
            if pair(b,a,19,14) { sc += 27; }
            if pair(b,a,18,19) { sc += 20; }
            if pair(b,a,13,19) { sc += 18; }
            if pair(b,a,13,6) { sc += 19; }
            if pair(b,a,0,18) { sc += 21; }
            if pair(b,a,7,0) { sc += 18; }
            if pair(b,a,18,4) { sc += 18; }
            if pair(b,a,8,14) { sc += 15; }
            if pair(b,a,11,4) { sc += 18; }
            if pair(b,a,0,17) { sc += 17; }
            if pair(b,a,2,14) { sc += 16; }
            if pair(b,a,12,4) { sc += 18; }
            if pair(b,a,22,7) { sc += 14; }
            if pair(b,a,3,8) { sc += 13; }
            if pair(b,a,3,4) { sc += 13; }
            if pair(b,a,8,11) { sc += 15; }
            if pair(b,a,11,24) { sc += 13; }
            if pair(b,a,2,7) { sc += 13; }
            if pair(b,a,18,7) { sc += 17; }
            if pair(b,a,2,10) { sc -= 80; }
            if pair(b,a,9,16) || pair(b,a,16,9) || pair(b,a,16,16) { sc -= 90; }
            if pair(b,a,21,21) || pair(b,a,23,23) || pair(b,a,25,25) { sc -= 75; }
        }
        if i > 1 {
            let b: i64 = p[i-2]; let c: i64 = p[i-1];
            if tri(b,c,a,19,7,4) { sc += 92; }
            if tri(b,c,a,0,13,3) { sc += 65; }
            if tri(b,c,a,8,13,6) { sc += 61; }
            if tri(b,c,a,8,14,13) { sc += 51; }
            if tri(b,c,a,4,13,19) { sc += 46; }
            if tri(b,c,a,7,4,17) { sc += 40; }
            if tri(b,c,a,5,14,17) { sc += 46; }
            if tri(b,c,a,19,7,0) { sc += 46; }
            if tri(b,c,a,19,8,14) { sc += 40; }
            if tri(b,c,a,2,14,13) { sc += 46; }
            if tri(b,c,a,0,19,8) { sc += 36; }
            if tri(b,c,a,0,19,4) { sc += 32; }
            if tri(b,c,a,19,4,17) { sc += 32; }
            if tri(b,c,a,4,18,19) { sc += 39; }
            if tri(b,c,a,24,14,20) { sc += 92; }
            if tri(b,c,a,0,17,4) { sc += 64; }
            if tri(b,c,a,3,8,3) { sc += 60; }
            if tri(b,c,a,22,0,18) { sc += 48; }
            if tri(b,c,a,14,20,17) { sc += 35; }
            if tri(b,c,a,14,19,7) { sc += 32; }
        }
    }
    if use_words { sc += shape_score(p, n, ws, we); }
    return sc;
}
fn evaluate(ct: [u8], p: mut [u8], n: i64, key: [u8], per: i64,
            uni: [i64], ws: [u8], we: [u8], dummy: [u8]) -> i64 {
    for i in 0..n {
        p[i] = ((ct[i] as i64 - key[i % per] as i64 + 26) % 26) as u8;
    }
    let mut sc = language_score(p,n,uni,ws,we,true);
    if per >= 8 {
        // When key is English-like, this adds a second independent structural signal.
        // There is no key-word dictionary and no assumption that the key is English.
        sc += language_score(key,per,uni,dummy,dummy,false) / 3;
    }
    sc -= 38 * per; // penalize overly flexible keys on short input
    return sc;
}
fn emit(text: [u8], textlen: i64, plain: [u8]) {
    let mut j: i64 = 0;
    for i in 0..textlen {
        let ch = text[i];
        if is_letter(ch) {
            let b: i64 = plain[j];
            if ch >= 97 { putc(b + 97); } else { putc(b + 65); }
            j += 1;
        } else { putc(ch); }
    }
    putc(10);
}
fn decode(ct: [u8], plain: mut [u8], n: i64, key: [u8], per: i64) {
    for i in 0..n { plain[i] = ((ct[i] as i64 - key[i % per] as i64 + 26) % 26) as u8; }
}
fn main() {
    let source = file(1);
    let raw = alloc<u8>(4096);
    let ct = alloc<u8>(4096);
    let plain = alloc<u8>(4096);
    let ws = alloc<u8>(4096);
    let we = alloc<u8>(4096);
    let dummy = alloc<u8>(4096);
    let crib = alloc<u8>(4096);
    let key = alloc<u8>(32);
    let tmp_key = alloc<u8>(32);
    let opt_keys = alloc<u8>(32*21);
    let opt_score = alloc<i64>(21);
    let uni = alloc<i64>(26);
    // Hand-selected approximate English letter preferences, NOT a corpus table.
    uni[0]=16; uni[1]=4; uni[2]=9; uni[3]=12; uni[4]=23; uni[5]=7;
    uni[6]=6; uni[7]=13; uni[8]=15; uni[9]=-27; uni[10]=0; uni[11]=12;
    uni[12]=9; uni[13]=16; uni[14]=17; uni[15]=8; uni[16]=-28; uni[17]=15;
    uni[18]=15; uni[19]=19; uni[20]=7; uni[21]=1; uni[22]=5; uni[23]=-21;
    uni[24]=5; uni[25]=-23;
    let mut state: u64 = 88172645463325252;
    let mut pos: i64 = 0;
    let mut nc: i64 = 0;
    while pos < len(source) {
        let mut lenraw: i64 = 0;
        while pos < len(source) && source[pos] != 10 {
            if lenraw < 4095 { raw[lenraw] = source[pos]; lenraw += 1; }
            pos += 1;
        }
        pos += 1;
        if lenraw == 0 { continue; }
        if raw[0] == 64 {
            nc = 0;
            for j in 1..lenraw {
                if is_letter(raw[j]) { crib[nc] = (upper(raw[j])-65) as u8; nc += 1; }
            }
            continue;
        }
        let mut n: i64 = 0;
        for i in 0..lenraw {
            if is_letter(raw[i]) {
                ct[n] = (upper(raw[i]) - 65) as u8;
                ws[n] = 0; we[n] = 0;
                if i == 0 { ws[n] = 1; }
                else if !is_letter(raw[i-1]) { ws[n] = 1; }
                if i == lenraw-1 { we[n] = 1; }
                else if !is_letter(raw[i+1]) { we[n] = 1; }
                n += 1;
            }
        }
        if n == 0 { continue; }
        write("\nINPUT: "); write(raw,0,lenraw); putc(10);
        write("Letters: "); print(n);
        if nc > 0 {
            write("CRIB-assisted test (not a blind solve):\n");
            let mut best = -9000000000000000000;
            let mut found: i64 = 0;
            let mut bestper: i64 = 0;
            let mut upto = nc;
            if upto > 20 { upto = 20; }
            if nc <= n {
                for per in 1..upto+1 {
                    let mut fits = true;
                    for j in 0..nc {
                        let v: i64 = (ct[j] as i64 - crib[j] as i64 + 26) % 26;
                        if j < per { key[j] = v as u8; }
                        else if key[j%per] as i64 != v { fits = false; }
                    }
                    if fits {
                        let sc = evaluate(ct,plain,n,key,per,uni,ws,we,dummy);
                        if sc > best {
                            best = sc; bestper = per; found = 1;
                            for j in 0..per { tmp_key[j] = key[j]; }
                        }
                    }
                }
            }
            if found != 0 {
                write("KEY: "); for j in 0..bestper { putc(tmp_key[j] + 65); }
                write("\nPLAINTEXT: "); decode(ct,plain,n,tmp_key,bestper); emit(raw,lenraw,plain);
            } else { write("No period <=20 matches this initial crib.\n"); }
            nc = 0;
            continue;
        }
        let mut maxper: i64 = 20;
        if n < 20 { maxper = n - 1; }
        for per in 1..maxper+1 {
            opt_score[per] = -9000000000000000000;
            let mut starts: i64 = 50;
            if per > 9 { starts = 85; }
            if per > 14 { starts = 105; }
            for restart in 0..starts {
                for k in 0..per {
                    state ^= state << 13; state ^= state >> 7; state ^= state << 17;
                    key[k] = ((state >> 33) % 26) as u8;
                }
                // Start 0: a deterministic English-frequency guess for each column.
                if restart == 0 {
                    for k in 0..per {
                        let mut high: i64 = -9000000000000000000;
                        let mut bestshift: i64 = 0;
                        for shift in 0..26 {
                            let mut value: i64 = 0;
                            let mut j = k;
                            while j < n {
                                value += uni[(ct[j] as i64 - shift + 26) % 26];
                                j += per;
                            }
                            if value > high { high = value; bestshift = shift; }
                        }
                        key[k] = bestshift as u8;
                    }
                }
                let mut current = evaluate(ct,plain,n,key,per,uni,ws,we,dummy);
                let mut pass: i64 = 0;
                let mut changed = true;
                while pass < 7 && changed {
                    changed = false;
                    // Randomize key-coordinate order by cyclic rotation.
                    let offset = restart % per;
                    for kk in 0..per {
                        let k = (kk + offset) % per;
                        let old: i64 = key[k];
                        let mut winner = old;
                        let mut best = current;
                        for shift in 0..26 {
                            key[k] = shift as u8;
                            let trial = evaluate(ct,plain,n,key,per,uni,ws,we,dummy);
                            if trial > best { best = trial; winner = shift; }
                        }
                        key[k] = winner as u8;
                        if winner != old { changed = true; current = best; }
                    }
                    pass += 1;
                }
                if current > opt_score[per] {
                    opt_score[per] = current;
                    for k in 0..per { opt_keys[per*32+k] = key[k]; }
                }
            }
        }
        write("Ranked candidates (heuristic; not proof):\n");
        let used = alloc<u8>(21);
        let mut limit: i64 = 12;
        if maxper < limit { limit = maxper; }
        for rank in 0..limit {
            let mut top: i64 = -9000000000000000000;
            let mut winner: i64 = 0;
            for per in 1..maxper+1 {
                if used[per] == 0 && opt_score[per] > top { top = opt_score[per]; winner = per; }
            }
            if winner > 0 {
                used[winner] = 1;
                for k in 0..winner { key[k] = opt_keys[winner*32+k]; }
                write("length "); print(winner);
                write("score  "); print(top);
                write("key    "); for k in 0..winner { putc(key[k] + 65); } putc(10);
                write("plain  "); decode(ct,plain,n,key,winner); emit(raw,lenraw,plain);
            }
        }
    }
}