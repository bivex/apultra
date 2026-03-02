//  Minimal ARM64 aPLib decompressor - working version
//  Direct port of expand.c logic

.globl _apl_decompress
_apl_decompress:

    // Save registers (96 bytes = 16-byte aligned)
    stp     x29, x30, [sp, #-96]!
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    stp     x25, x26, [sp, #64]
    stp     x27, x28, [sp, #80]

    // x0 = src, x1 = dest
    mov     x19, x0                  // src
    mov     x20, x1                  // dest
    mov     x28, x1                  // dest_start

    // bit_mask = 0, bits = 0, match_offset = 0, follows_literal = 3
    mov     x27, #0                  // bit_mask (0 = need new byte)
    mov     x26, #3                  // follows_literal
    mov     x25, #0                  // match_offset (saved)

    // First literal
    ldrb    w22, [x19], #1
    strb    w22, [x20], #1

    // === Helper: GET_BIT (returns result in w23, sets Z flag) ===
    // Inlined at each use

.main:
    // GET_BIT
    cbz     x27, .new1
    tst     x22, x27
    lsr     x27, x27, #1
    b.eq    .literal
    b       .bit1_done
.new1:
    ldrb    w22, [x19], #1
    mov     x27, #0x80
    tst     x22, x27
    lsr     x27, x27, #1
    b.ne    .bit1_is_one
.literal:
    // Bit was 0 - literal byte
    ldrb    w23, [x19], #1
    strb    w23, [x20], #1
    mov     x26, #3
    b       .main
.bit1_is_one:
    // Bit was 1 - match
.bit1_done:

    // GET_BIT (second)
    cbz     x27, .new2
    tst     x22, x27
    lsr     x27, x27, #1
    b.eq    .match_8n
    b       .match_11
.new2:
    ldrb    w22, [x19], #1
    mov     x27, #0x80
    tst     x22, x27
    lsr     x27, x27, #1
    b.eq    .match_8n
    b       .match_11

// ============================================================================
//  8+n match (10x)
// ============================================================================
.match_8n:
    // GET_GAMMA2 into x24
    mov     x24, #1                  // v = 1
.g1:
    // GET_BIT
    cbz     x27, .gn1
    tst     x22, x27
    lsr     x27, x27, #1
    cset    w23, ne
    b       .gn1ok
.gn1:
    ldrb    w22, [x19], #1
    mov     x27, #0x80
    tst     x22, x27
    lsr     x27, x27, #1
    cset    w23, ne
.gn1ok:
    // v = (v << 1) + bit
    lsl     x24, x24, #1
    add     x24, x24, x23

    // GET_BIT (continuation)
    cbz     x27, .gn2
    tst     x22, x27
    lsr     x27, x27, #1
    cset    w23, ne
    b       .gn2ok
.gn2:
    ldrb    w22, [x19], #1
    mov     x27, #0x80
    tst     x22, x27
    lsr     x27, x27, #1
    cset    w23, ne
.gn2ok:
    // Continue if bit is 1
    cbnz    w23, .g1

    // x24 = gamma2 result
    // Check: gamma - follows_literal >= 0 ?
    subs    x24, x24, x26
    b.ge    .regular_match

    // === REP-MATCH ===
    // Read gamma for length into x23
    mov     x23, #1
.g2:
    cbz     x27, .gn3
    tst     x22, x27
    lsr     x27, x27, #1
    cset    w0, ne
    b       .gn3ok
.gn3:
    ldrb    w22, [x19], #1
    mov     x27, #0x80
    tst     x22, x27
    lsr     x27, x27, #1
    cset    w0, ne
.gn3ok:
    lsl     x23, x23, #1
    add     x23, x23, x0

    cbz     x27, .gn4
    tst     x22, x27
    lsr     x27, x27, #1
    cset    w0, ne
    b       .gn4ok
.gn4:
    ldrb    w22, [x19], #1
    mov     x27, #0x80
    tst     x22, x27
    lsr     x27, x27, #1
    cset    w0, ne
.gn4ok:
    cbnz    w0, .g2

    // x23 = length, x25 = saved_offset
    mov     x26, #2                  // follows_literal = 2
    b       .do_copy

.regular_match:
    // offset = (x24 << 8) | low_byte
    lsl     x25, x24, #8
    ldrb    w24, [x19], #1
    orr     x25, x25, x24            // x25 = offset

    // Read gamma for length into x23
    mov     x23, #1
.g3:
    cbz     x27, .gn5
    tst     x22, x27
    lsr     x27, x27, #1
    cset    w0, ne
    b       .gn5ok
.gn5:
    ldrb    w22, [x19], #1
    mov     x27, #0x80
    tst     x22, x27
    lsr     x27, x27, #1
    cset    w0, ne
.gn5ok:
    lsl     x23, x23, #1
    add     x23, x23, x0

    cbz     x27, .gn6
    tst     x22, x27
    lsr     x27, x27, #1
    cset    w0, ne
    b       .gn6ok
.gn6:
    ldrb    w22, [x19], #1
    mov     x27, #0x80
    tst     x22, x27
    lsr     x27, x27, #1
    cset    w0, ne
.gn6ok:
    cbnz    w0, .g3

    // Adjust length
    cmp     x25, #128
    b.lo    .adj2
    cmp     x25, #1280
    b.lo    .adj0
    mov     x0, #32000
    cmp     x25, x0
    b.lo    .adj1
.adj2:
    add     x23, x23, #2
    b       .adj_done
.adj1:
    add     x23, x23, #1
    b       .adj_done
.adj0:
.adj_done:
    mov     x26, #2                  // follows_literal = 2

.do_copy:
    // x23 = length, x25 = offset
    sub     x24, x20, x25            // source
.copy:
    subs    x23, x23, #1
    b.lo    .copy_done
    ldrb    w0, [x24], #1
    strb    w0, [x20], #1
    b       .copy
.copy_done:
    b       .main

// ============================================================================
//  11x match
// ============================================================================
.match_11:
    // GET_BIT
    cbz     x27, .new3
    tst     x22, x27
    lsr     x27, x27, #1
    b.eq    .m110
    b       .m111
.new3:
    ldrb    w22, [x19], #1
    mov     x27, #0x80
    tst     x22, x27
    lsr     x27, x27, #1
    b.eq    .m110
    b       .m111

.m110:
    // 7 bits offset + 1 bit length
    ldrb    w24, [x19], #1
    cbz     w24, .done               // EOF

    and     w23, w24, #1
    add     w23, w23, #2             // length
    lsr     w25, w24, #1             // offset

    mov     x26, #2
    b       .do_copy

.m111:
    // 4 bit offset / 1 byte copy
    mov     x25, #0

    // Read 4 bits
    // bit 3
    cbz     x27, .sb1
    tst     x22, x27
    lsr     x27, x27, #1
    cset    w0, ne
    b       .sb1ok
.sb1:
    ldrb    w22, [x19], #1
    mov     x27, #0x80
    tst     x22, x27
    lsr     x27, x27, #1
    cset    w0, ne
.sb1ok:
    bfi     x25, x0, #3, #1

    // bit 2
    cbz     x27, .sb2
    tst     x22, x27
    lsr     x27, x27, #1
    cset    w0, ne
    b       .sb2ok
.sb2:
    ldrb    w22, [x19], #1
    mov     x27, #0x80
    tst     x22, x27
    lsr     x27, x27, #1
    cset    w0, ne
.sb2ok:
    bfi     x25, x0, #2, #1

    // bit 1
    cbz     x27, .sb3
    tst     x22, x27
    lsr     x27, x27, #1
    cset    w0, ne
    b       .sb3ok
.sb3:
    ldrb    w22, [x19], #1
    mov     x27, #0x80
    tst     x22, x27
    lsr     x27, x27, #1
    cset    w0, ne
.sb3ok:
    bfi     x25, x0, #1, #1

    // bit 0
    cbz     x27, .sb4
    tst     x22, x27
    lsr     x27, x27, #1
    cset    w0, ne
    b       .sb4ok
.sb4:
    ldrb    w22, [x19], #1
    mov     x27, #0x80
    tst     x22, x27
    lsr     x27, x27, #1
    cset    w0, ne
.sb4ok:
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
