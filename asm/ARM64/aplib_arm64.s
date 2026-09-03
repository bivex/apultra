//  ARM64 aPLib decompressor - inline all helpers
//  Direct port from expand.c with careful register handling

.globl _apl_decompress
_apl_decompress:

    stp     x29, x30, [sp, #-96]!
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    stp     x25, x26, [sp, #64]
    stp     x27, x28, [sp, #80]

    mov     x19, x0                  // src
    mov     x20, x1                  // dest
    mov     x28, x1                  // dest_start

    mov     w27, wzr                 // nCurBitMask = 0
    mov     x22, #0                  // bits = 0
    mov     x26, #3                  // nFollowsLiteral = 3
    mov     x21, #0                  // saved_offset = 0
    mov     x1, #1                   // constant 1 for csel

    // First byte
    ldrb    w24, [x19], #1
    strb    w24, [x20], #1

.main:
    // GET_BIT: tag0 (0=literal, 1=match)
    cbz     w27, .nb1_tag0
    tst     w22, w27
    lsr     w27, w27, #1
    b.eq    .literal
    b       .read_tag1
.nb1_tag0:
    ldrb    w22, [x19], #1
    mov     w27, #0x80
    tst     w22, w27
    lsr     w27, w27, #1
    b.eq    .literal

.read_tag1:
    // GET_BIT: tag1 (0=match_8n, 1=match_11)
    cbz     w27, .nb1_tag1
    tst     w22, w27
    lsr     w27, w27, #1
    b.eq    .match_8n
    b       .match_11
.nb1_tag1:
    ldrb    w22, [x19], #1
    mov     w27, #0x80
    tst     w22, w27
    lsr     w27, w27, #1
    b.eq    .match_8n
    b       .match_11

.literal:
    ldrb    w24, [x19], #1
    strb    w24, [x20], #1
    mov     x26, #3
    b       .main

// ============================================================================
//  match_8n
// ============================================================================
.match_8n:
    // === GET_GAMMA2 into x25 ===
    mov     x25, #1                  // v = 1
.g1:
    // GET_BIT
    cbz     w27, .g1_nb
    tst     w22, w27
    lsr     w27, w27, #1
    csel    w23, w1, wzr, ne         // w23 = bit (0 or 1)
    b       .g1_ok
.g1_nb:
    ldrb    w22, [x19], #1
    mov     w27, #0x80
    tst     w22, w27
    lsr     w27, w27, #1
    csel    w23, w1, wzr, ne
.g1_ok:
    // x25 = (x25 << 1) | w23
    lsl     x25, x25, #1
    orr     x25, x25, x23

    // GET_BIT (continuation)
    cbz     w27, .g2_nb
    tst     w22, w27
    lsr     w27, w27, #1
    csel    w23, w1, wzr, ne
    b       .g2_ok
.g2_nb:
    ldrb    w22, [x19], #1
    mov     w27, #0x80
    tst     w22, w27
    lsr     w27, w27, #1
    csel    w23, w1, wzr, ne
.g2_ok:
    cbnz    w23, .g1

    // x25 = gamma2 result
    // Check: gamma - follows_literal >= 0 ?
    subs    x25, x25, x26
    b.ge    .regular_match

    // === REP-MATCH ===
    // GET_GAMMA2 into x24 (length)
    mov     x24, #1
.rg1:
    cbz     w27, .rg_nb
    tst     w22, w27
    lsr     w27, w27, #1
    csel    w23, w1, wzr, ne
    b       .rg_ok
.rg_nb:
    ldrb    w22, [x19], #1
    mov     w27, #0x80
    tst     w22, w27
    lsr     w27, w27, #1
    csel    w23, w1, wzr, ne
.rg_ok:
    // x24 = (x24 << 1) | bit
    lsl     x24, x24, #1
    orr     x24, x24, x23

    cbz     w27, .rg2_nb
    tst     w22, w27
    lsr     w27, w27, #1
    csel    w23, w1, wzr, ne
    b       .rg2_ok
.rg2_nb:
    ldrb    w22, [x19], #1
    mov     w27, #0x80
    tst     w22, w27
    lsr     w27, w27, #1
    csel    w23, w1, wzr, ne
.rg2_ok:
    cbnz    w23, .rg1

    // x24 = length, use x21 (saved_offset) for copy
    b       .do_copy_saved

.regular_match:
    // offset = (x25 << 8) | low_byte
    lsl     x25, x25, #8
    ldrb    w24, [x19], #1
    orr     x25, x25, x24

    // Save offset for rep-match
    mov     x21, x25

    // GET_GAMMA2 into x24 (length)
    mov     x24, #1
.reg1:
    cbz     w27, .re1_nb
    tst     w22, w27
    lsr     w27, w27, #1
    csel    w23, w1, wzr, ne
    b       .re1_ok
.re1_nb:
    ldrb    w22, [x19], #1
    mov     w27, #0x80
    tst     w22, w27
    lsr     w27, w27, #1
    csel    w23, w1, wzr, ne
.re1_ok:
    lsl     x24, x24, #1
    orr     x24, x24, x23

    cbz     w27, .re2_nb
    tst     w22, w27
    lsr     w27, w27, #1
    csel    w23, w1, wzr, ne
    b       .re2_ok
.re2_nb:
    ldrb    w22, [x19], #1
    mov     w27, #0x80
    tst     w22, w27
    lsr     w27, w27, #1
    csel    w23, w1, wzr, ne
.re2_ok:
    cbnz    w23, .reg1

    // Adjust length based on offset
    cmp     x25, #128
    b.lo    .adj2
    cmp     x25, #1280
    b.lo    .adj0
    mov     w0, #32000
    cmp     x25, x0
    b.lo    .adj1
.adj2:
    add     x24, x24, #2
    b       .do_copy_len
.adj1:
    add     x24, x24, #1
    b       .do_copy_len
.adj0:
.do_copy_len:
    mov     x23, x24                 // length in x23
    // x25 = offset
    b       .do_copy

.do_copy_saved:
    // For rep-match: x24 = length, use x21 as saved_offset
    mov     x23, x24                 // save length before x24 is overwritten
    mov     x25, x21

.do_copy:
    mov     x26, #2
    // x23 = length, x25 = offset
    sub     x24, x20, x25            // source = dest - offset

.copy:
    subs    x23, x23, #1
    b.lo    .main

    ldrb    w0, [x24], #1
    strb    w0, [x20], #1
    b       .copy

// ============================================================================
//  match_11
// ============================================================================
.match_11:
    // GET_BIT (ONE bit: 0 -> .m110, 1 -> .m111)
    cbz     w27, .nb3_tag
    tst     w22, w27
    lsr     w27, w27, #1
    b.eq    .m110
    b       .m111

.nb3_tag:
    ldrb    w22, [x19], #1
    mov     w27, #0x80
    tst     w22, w27
    lsr     w27, w27, #1
    b.eq    .m110
    b       .m111

.m110:
    ldrb    w24, [x19], #1           // command
    cbz     w24, .done               // EOF

    mov     x23, #0                  // clear x23 explicitly
    and     w23, w24, #1             // length bit
    add     w23, w23, #2             // nMatchLen = 2 + bit
    ubfx    x25, x24, #1, #7         // nMatchOffset = bits[7:1]
    mov     x21, x25                 // save offset for rep-match

    mov     x26, #2
    b       .do_copy

.m111:
    mov     x25, #0

    // Read 4 bits
    // bit 3
    cbz     w27, .sb1
    tst     w22, w27
    lsr     w27, w27, #1
    csel    w0, w1, wzr, ne
    b       .sb1_ok
.sb1:
    ldrb    w22, [x19], #1
    mov     w27, #0x80
    tst     w22, w27
    lsr     w27, w27, #1
    csel    w0, w1, wzr, ne
.sb1_ok:
    bfi     x25, x0, #3, #1

    // bit 2
    cbz     w27, .sb2
    tst     w22, w27
    lsr     w27, w27, #1
    csel    w0, w1, wzr, ne
    b       .sb2_ok
.sb2:
    ldrb    w22, [x19], #1
    mov     w27, #0x80
    tst     w22, w27
    lsr     w27, w27, #1
    csel    w0, w1, wzr, ne
.sb2_ok:
    bfi     x25, x0, #2, #1

    // bit 1
    cbz     w27, .sb3
    tst     w22, w27
    lsr     w27, w27, #1
    csel    w0, w1, wzr, ne
    b       .sb3_ok
.sb3:
    ldrb    w22, [x19], #1
    mov     w27, #0x80
    tst     w22, w27
    lsr     w27, w27, #1
    csel    w0, w1, wzr, ne
.sb3_ok:
    bfi     x25, x0, #1, #1

    // bit 0
    cbz     w27, .sb4
    tst     w22, w27
    lsr     w27, w27, #1
    csel    w0, w1, wzr, ne
    b       .sb4_ok
.sb4:
    ldrb    w22, [x19], #1
    mov     w27, #0x80
    tst     w22, w27
    lsr     w27, w27, #1
    csel    w0, w1, wzr, ne
.sb4_ok:
    bfi     x25, x0, #0, #1

    mov     x26, #3
    cbz     x25, .write_zero

    sub     x24, x20, x25
    ldrb    w0, [x24]
    strb    w0, [x20], #1
    b       .main

.write_zero:
    strb    wzr, [x20], #1
    b       .main

.done:
    sub     x0, x20, x28

    ldp     x27, x28, [sp, #80]
    ldp     x25, x26, [sp, #64]
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #96
    ret
