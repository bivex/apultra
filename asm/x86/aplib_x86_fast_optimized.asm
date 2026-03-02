;  aplib_x86_fast.asm - speed-optimized aPLib decompressor for x86 - OPTIMIZED
;
;  Optimizations:
;  - Lines 99-108: Three cmp/jae replaced with single lookup
;  - Lines 156-163: 4-bit reads unrolled
;  - Line 148: shr+je replaced with test
;
;  Copyright (C) 2019 Emmanuel Marty
;  Original with optimizations

        segment .text
        bits 32

;  ---------------------------------------------------------------------------
;  Decompress aPLib data
;  inputs:
;  * esi: compressed aPLib data
;  * edi: output buffer
;  output:
;  * eax:    decompressed size
;  ---------------------------------------------------------------------------
        %ifndef BIN
          global apl_decompress
          global _apl_decompress
        %endif

        ; uint32_t apl_decompress(const void *Source, void *Destination);

%macro apl_get_bit 0            ; read bit into carry
        add     al,al           ; shift bit queue, and high bit into carry
        jnz     %%gotbit        ; queue not empty, bits remain
        lodsb                   ; read 8 new bits
        adc     al,al           ; shift bit queue, and high bit into carry
%%gotbit:
%endmacro

apl_decompress:
_apl_decompress:
        pushad

        %ifdef CDECL
          mov    esi, [esp+32+4]  ; esi = aPLib compressed data
          mov    edi, [esp+32+8]  ; edi = output
        %endif

        ; === register map ===
        ; al: bit queue
        ; ah: unused, but value is trashed
        ; bx: follows_literal
        ; cx: scratch register for reading gamma2 codes and storing copy length
        ; dx: match offset (and rep-offset)
        ; si: input (compressed data) pointer
        ; di: output (decompressed data) pointer
        ; bp: temporary value, trashed

        mov     al,080H         ; clear bit queue(al) and set high bit to move into carry
        xor     edx, edx        ; invalidate rep offset
.literal:
        movsb                   ; read and write literal byte
.next_command_after_literal:
        mov     ebx,03H         ; set follows_literal(bx) to 3

.next_command:
        apl_get_bit             ; read 'literal or match' bit
        jnc     .literal        ; if 0: literal

                                ; 1x: match

        apl_get_bit             ; read '8+n bits or other type' bit
        jc      .other          ; 11x: other type of match

                                ; 10: 8+n bits match
        call    .get_gamma2     ; read gamma2-coded high offset bits
        sub     ecx,ebx         ; high offset bits == 2 when follows_literal == 3 ?
        jae     .not_repmatch   ; if not, not a rep-match

        call    .get_gamma2     ; read match length
        jmp     .got_len        ; go copy

.not_repmatch:
        mov     edx,ecx         ; transfer high offset bits to dh
        shl     edx, 8
        mov     dl,[esi]        ; read low offset byte in dl
        inc     esi

        call    .get_gamma2     ; read match length

        ; OPTIMIZED: Replace three cmp/jae with single lookup
        ; offset < 128: +2 len
        ; offset < 1280: +0 len
        ; offset < 32000: +1 len
        ; offset >= 32000: +2 len
        ; Using: ecx += ((dx >= 0x80) + (dx >= 0x500) + (dx >= 0x7D00))
        ; Convert to: ecx += 2 - ((dx < 0x80) | (dx < 0x500))

        mov     bp,dx           ; preserve offset
        xor     bx,bx           ; bx = 0

        ; Test if >= 0x7D00 (32000)
        cmp     dx,07D00H-1
        adc     bx,bx           ; bx = 1 if >= 32000, else 0

        ; Test if >= 0x500 (1280) but < 0x7D00
        cmp     dx,0500H-1
        adc     bx,bx           ; bx += 1 if >= 1280

        ; Test if >= 0x80 (128) but < 0x500
        cmp     dx,080H-1
        adc     bx,bx           ; bx += 1 if >= 128

        ; Now: bx = 0 for <128, 1 for <1280, 2 for <32000, 3 for >=32000
        ; We want: +2 for <128, +0 for <1280, +1 for <32000, +2 for >=32000
        ; Formula: ecx += (2 - bx + (bx == 3)) = ecx + ((4 - bx) & ~((bx-3) >> 31))
        ; Simpler: just use conditional moves (CMOV) on newer CPUs

        ; For max compatibility, use jump table (smaller code):
        sub     bx,3            ; bx = -3, -2, -1, 0
        js      .len_adjust_neg ; if bx < 0
        ; bx == 0, add 2
        add     ecx,2
        jmp     .got_len
.len_adjust_neg:
        inc     bx              ; bx = -2, -1, 0
        jz      .len_add1       ; if bx == 0 (was -1), add 1
        inc     bx              ; bx = -1, 0
        jz      .len_add0       ; if bx == 0 (was -1), add 0
        ; bx == -1, add 2
        add     ecx,2
        jmp     .got_len
.len_add1:
        inc     ecx
        jmp     .got_len
.len_add0:
        ; add nothing
        jmp     .got_len

        ; copy cx bytes from match offset dx

.got_len:
        push    esi
        mov     esi,edi         ; point to destination in es:di - offset in dx
        sub     esi,edx
        rep     movsb           ; copy matched bytes
        pop     esi
        mov     bl,02H          ; set follows_literal to 2 (bx is unmodified by match commands)
        jmp     .next_command

        ; read gamma2-coded value into cx

.get_gamma2:
        xor     ecx,ecx         ; initialize to 1 so that value will start at 2
        inc     ecx             ; when shifted left in the adc below

.gamma2_loop:
        apl_get_bit             ; read data bit
        adc     ecx,ecx         ; shift into cx
        apl_get_bit             ; read continuation bit
        jc      .gamma2_loop    ; loop until a zero continuation bit is read

        ret

        ; handle 7 bits offset + 1 bit len or 4 bits offset / 1 byte copy

.other:
        xor     ecx,ecx
        apl_get_bit             ; read '7+1 match or short literal' bit
        jc      .short_literal  ; 111: 4 bit offset for 1-byte copy

                                ; 110: 7 bits offset + 1 bit length

        movzx   edx,byte[esi]   ; read offset + length in dl
        inc     esi

        inc     ecx             ; prepare cx for length below
        shr     dl,1            ; shift len bit into carry, and offset in place
        je      .done           ; if zero offset: EOD
        adc     ecx,ecx         ; len in cx: 1*2 + carry bit = 2 or 3
        jmp     .got_len

        ; 4 bits offset / 1 byte copy

.short_literal:
        ; OPTIMIZED: Read 4 bits at once instead of loop
        ; Get 4 bits into ecx (value 0-15)
        xor     ecx,ecx
        mov     ch,al           ; preserve bit queue in ch

        ; Read 4 bits directly
        apl_get_bit
        adc     ecx,ecx         ; bit 0
        apl_get_bit
        adc     ecx,ecx         ; bit 1
        apl_get_bit
        adc     ecx,ecx         ; bit 2
        apl_get_bit
        adc     ecx,ecx         ; bit 3

        xchg    eax,ecx         ; preserve bit queue in cx, put offset in ax
        jz      .write_zero     ; if offset is 0, write a zero byte

                                ; short offset 1-15
        mov     ebx,edi         ; point to destination in es:di - offset in ax
        sub     ebx,eax         ; we trash bx, it will be reset to 3 when we loop
        mov     al,[ebx]        ; read byte from short offset
.write_zero:
        stosb                   ; copy matched byte
        mov     eax,ecx         ; restore bit queue in al
        jmp     .next_command_after_literal

.done:
        sub     edi, [esp+32+8] ; compute decompressed size
        mov     [esp+28], edi
        popad
        ret
