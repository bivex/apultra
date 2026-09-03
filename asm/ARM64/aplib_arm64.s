//  ARM64 aPLib decompressor - fast copy & optimized bit-reading
//  Direct port from expand.c with Apple Silicon optimizations

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

    // First literal byte
    ldrb    w24, [x19], #1
    strb    w24, [x20], #1

.main:
    // GET_BIT: tag0 (0=literal, 1=match)
    cbnz    w27, .tag0_has_bits
    ldrb    w22, [x19], #1
    mov     w27, #0x80
.tag0_has_bits:
    tst     w22, w27
    lsr     w27, w27, #1
    b.eq    .literal

.read_tag1:
    // GET_BIT: tag1 (0=match_8n, 1=match_11)
    cbnz    w27, .tag1_has_bits
    ldrb    w22, [x19], #1
    mov     w27, #0x80
.tag1_has_bits:
    tst     w22, w27
    lsr     w27, w27, #1
    b.ne    .match_11

// ============================================================================
//  match_8n
// ============================================================================
.match_8n:
    // === GET_GAMMA2 into x25 ===
    mov     x25, #1                  // v = 1
.g1:
    cbnz    w27, .g1_has_bits
    ldrb    w22, [x19], #1
    mov     w27, #0x80
.g1_has_bits:
    tst     w22, w27
    lsr     w27, w27, #1
    lsl     x25, x25, #1
    cinc    x25, x25, ne

    cbnz    w27, .g2_has_bits
    ldrb    w22, [x19], #1
    mov     w27, #0x80
.g2_has_bits:
    tst     w22, w27
    lsr     w27, w27, #1
    b.ne    .g1

    // Check: gamma - follows_literal >= 0 ?
    subs    x25, x25, x26
    b.ge    .regular_match

    // === REP-MATCH ===
    // GET_GAMMA2 into x24 (length)
    mov     x24, #1
.rg1:
    cbnz    w27, .rg1_has_bits
    ldrb    w22, [x19], #1
    mov     w27, #0x80
.rg1_has_bits:
    tst     w22, w27
    lsr     w27, w27, #1
    lsl     x24, x24, #1
    cinc    x24, x24, ne

    cbnz    w27, .rg2_has_bits
    ldrb    w22, [x19], #1
    mov     w27, #0x80
.rg2_has_bits:
    tst     w22, w27
    lsr     w27, w27, #1
    b.ne    .rg1

    mov     x23, x24                 // length in x23
    mov     x25, x21                 // use saved_offset
    b       .do_copy

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
    cbnz    w27, .re1_has_bits
    ldrb    w22, [x19], #1
    mov     w27, #0x80
.re1_has_bits:
    tst     w22, w27
    lsr     w27, w27, #1
    lsl     x24, x24, #1
    cinc    x24, x24, ne

    cbnz    w27, .re2_has_bits
    ldrb    w22, [x19], #1
    mov     w27, #0x80
.re2_has_bits:
    tst     w22, w27
    lsr     w27, w27, #1
    b.ne    .reg1

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
    b       .do_copy

.literal:
    ldrb    w24, [x19], #1
    strb    w24, [x20], #1
    mov     x26, #3
    b       .main

// ============================================================================
//  match_11
// ============================================================================
.match_11:
    // GET_BIT (0 -> .m110, 1 -> .m111)
    cbnz    w27, .tag2_has_bits
    ldrb    w22, [x19], #1
    mov     w27, #0x80
.tag2_has_bits:
    tst     w22, w27
    lsr     w27, w27, #1
    b.ne    .m111

.m110:
    ldrb    w24, [x19], #1           // command
    cbz     w24, .done               // EOF

    and     w23, w24, #1             // length bit
    add     w23, w23, #2             // nMatchLen = 2 + bit
    ubfx    x25, x24, #1, #7         // nMatchOffset = bits[7:1]
    mov     x21, x25                 // save offset for rep-match
    b       .do_copy

.m111:
    mov     x25, #0

    // Read 4 bits directly with lsl + cinc
    cbnz    w27, .m111_b3
    ldrb    w22, [x19], #1
    mov     w27, #0x80
.m111_b3:
    tst     w22, w27
    lsr     w27, w27, #1
    cinc    x25, x25, ne

    cbnz    w27, .m111_b2
    ldrb    w22, [x19], #1
    mov     w27, #0x80
.m111_b2:
    tst     w22, w27
    lsr     w27, w27, #1
    lsl     x25, x25, #1
    cinc    x25, x25, ne

    cbnz    w27, .m111_b1
    ldrb    w22, [x19], #1
    mov     w27, #0x80
.m111_b1:
    tst     w22, w27
    lsr     w27, w27, #1
    lsl     x25, x25, #1
    cinc    x25, x25, ne

    cbnz    w27, .m111_b0
    ldrb    w22, [x19], #1
    mov     w27, #0x80
.m111_b0:
    tst     w22, w27
    lsr     w27, w27, #1
    lsl     x25, x25, #1
    cinc    x25, x25, ne

    mov     x26, #3
    cbz     x25, .write_zero

    sub     x24, x20, x25
    ldrb    w0, [x24]
    strb    w0, [x20], #1
    b       .main

.write_zero:
    strb    wzr, [x20], #1
    b       .main

// ============================================================================
//  FAST COPY ENGINE
//  x23 = length, x25 = offset
// ============================================================================
.do_copy:
    mov     x26, #2
    sub     x24, x20, x25            // source = dest - offset

    cmp     x25, #16
    b.hs    .copy_ge16
    cmp     x25, #8
    b.hs    .copy_ge8
    cmp     x25, #1
    b.eq    .copy_rle

    // Fallback for 1 < offset < 8 (overlapping byte copy)
    cbz     x23, .main
.copy_bytes_loop:
    ldrb    w0, [x24], #1
    strb    w0, [x20], #1
    subs    x23, x23, #1
    b.ne    .copy_bytes_loop
    b       .main

// --- Offset >= 16: 16-byte chunks ---
.copy_ge16:
    cmp     x23, #16
    b.lo    .copy_ge16_tail8

.copy_ge16_loop16:
    ldp     x0, x2, [x24], #16
    stp     x0, x2, [x20], #16
    sub     x23, x23, #16
    cmp     x23, #16
    b.hs    .copy_ge16_loop16

.copy_ge16_tail8:
    tbz     w23, #3, .copy_tail_0_to_7
    ldr     x0, [x24], #8
    str     x0, [x20], #8
    b       .copy_tail_0_to_7

// --- Offset >= 8: 8-byte chunks ---
.copy_ge8:
    cmp     x23, #8
    b.lo    .copy_tail_0_to_7

.copy_ge8_loop8:
    ldr     x0, [x24], #8
    str     x0, [x20], #8
    sub     x23, x23, #8
    cmp     x23, #8
    b.hs    .copy_ge8_loop8

// --- Unrolled 0..7 bytes copy (offset >= 8) ---
.copy_tail_0_to_7:
    tbz     w23, #2, 1f
    ldr     w0, [x24], #4
    str     w0, [x20], #4
1:
    tbz     w23, #1, 2f
    ldrh    w0, [x24], #2
    strh    w0, [x20], #2
2:
    tbz     w23, #0, 3f
    ldrb    w0, [x24], #1
    strb    w0, [x20], #1
3:
    b       .main

// --- Offset == 1: RLE (replicate byte) ---
.copy_rle:
    ldrb    w0, [x24]
    orr     w0, w0, w0, lsl #8
    orr     w0, w0, w0, lsl #16
    orr     x0, x0, x0, lsl #32

.copy_rle_loop16:
    cmp     x23, #16
    b.lo    .copy_rle_tail8
    stp     x0, x0, [x20], #16
    sub     x23, x23, #16
    b       .copy_rle_loop16

.copy_rle_tail8:
    tbz     w23, #3, .copy_rle_tail_0_to_7
    str     x0, [x20], #8

.copy_rle_tail_0_to_7:
    tbz     w23, #2, 1f
    str     w0, [x20], #4
1:
    tbz     w23, #1, 2f
    strh    w0, [x20], #2
2:
    tbz     w23, #0, 3f
    strb    w0, [x20], #1
3:
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
