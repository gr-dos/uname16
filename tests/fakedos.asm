; fakedos - run a program under imitated DOS answers, with its standard
; error sent to standard output
;
;   fakedos MODES PROGRAM.EXT [ARGUMENTS]
;
; Test fixture, not part of uname.  DOS shells cannot redirect standard
; error, and DOSBox-X is none of the kernels uname tells apart, so the
; tests run "fakedos MODES uname.com ARGS >file".  fakedos hooks INT 21h
; for the run of PROGRAM only, then unhooks.  MODES is one word of
; letters (or "-" for none):
;
;   G   AX=3347h, BX=4752h: a valid GR-DOS 0.04 answer, API revision 1
;   B   the same, but DX = 1234h whatever the nonce (must be rejected)
;   S   AX=4752h only, everything else unchanged (must be rejected)
;   D   AX=4452h: carry clear, AX = 1067h (DR DOS 6.0)
;   F   AH=30h: OEM number FDh (FreeDOS)
;   I   AH=30h: OEM number 00h (IBM PC DOS)
;   O   AH=30h: OEM number 42h (some other OEM)
;   V   AH=30h: version 5.00; AX=3306h: true version 6.22 (SETVER)
;   1   AH=30h: AL = 0 (DOS 1.x)
;   N   AX=5E00h: machine name "TESTPC", blank padded, CH = 1
;   X   AX=5E00h: carry set, AX = 1 (no network)
;   Z   AX=5E00h: carry clear, CH = 0 (no name set)
;
; The rest of the command tail after PROGRAM, from the blank before
; ARGUMENTS, is passed to PROGRAM unchanged.  The exit status is
; PROGRAM's, or 255 if it could not be run.
;
; Build: nasm -f bin -o fakedos.com fakedos.asm

        cpu     8086
        org     100h

start:
        mov     sp, stack_top

        ; give back the memory we do not use, to run PROGRAM in
        mov     bx, stack_top + 15
        mov     cl, 4
        shr     bx, cl
        mov     ah, 4Ah
        int     21h
        jc      fail

        mov     si, 81h
        mov     cl, [80h]
        xor     ch, ch

        ; MODES: set mode[letter] for each letter
        call    skipbl
.mode:  jcxz    .fail
        lodsb
        dec     cx
        cmp     al, ' '
        je      .named0
        cmp     al, 9
        je      .named0
        mov     bl, al
        and     bl, 7Fh
        xor     bh, bh
        mov     byte [mode + bx], 1
        jmp     .mode
.fail:  jmp     fail
.named0:
        ; PROGRAM: the next word
        call    skipbl
        mov     di, progname
.name:  jcxz    .named
        lodsb
        cmp     al, ' '
        je      .blank
        cmp     al, 9
        je      .blank
        stosb
        dec     cx
        jmp     .name
.blank: dec     si
.named: mov     byte [di], 0

        ; the rest of the tail, CR-terminated, is PROGRAM's tail
        mov     di, tail
        mov     al, cl
        stosb
        rep     movsb
        mov     al, 0Dh
        stosb

        ; standard error to the same file as standard output
        mov     ah, 46h
        mov     bx, 1
        mov     cx, 2
        int     21h
        jc      fail

        ; hook INT 21h
        mov     ax, 3521h
        int     21h
        mov     [old21], bx
        mov     [old21 + 2], es
        push    cs
        pop     es
        mov     dx, handler
        mov     ax, 2521h
        int     21h

        mov     [pb_tail + 2], cs
        mov     [pb_fcb1 + 2], cs
        mov     [pb_fcb2 + 2], cs
        mov     [save_sp], sp
        mov     dx, progname
        mov     bx, pblock
        mov     ax, 4B00h
        int     21h

        ; DOS 2.x keeps only CS:IP across EXEC
        cli
        mov     ax, cs
        mov     ss, ax
        mov     sp, [cs:save_sp]
        sti
        mov     ds, ax
        mov     es, ax
        pushf

        ; unhook
        push    ds
        lds     dx, [old21]
        mov     ax, 2521h
        int     21h
        pop     ds

        popf
        jc      fail
        mov     ah, 4Dh                 ; AL = PROGRAM's exit status
        int     21h
        mov     ah, 4Ch
        int     21h

fail:   mov     ax, 4CFFh
        int     21h

skipbl: jcxz    .r
        lodsb
        dec     cx
        cmp     al, ' '
        je      skipbl
        cmp     al, 9
        je      skipbl
        dec     si
        inc     cx
.r:     ret

; ------------------------------------------------------------------
; the INT 21h hook

handler:
        cmp     ah, 30h
        je      h30
        cmp     ax, 3306h
        je      h3306
        cmp     ax, 3347h
        je      hgr
        cmp     ax, 4452h
        je      hdr
        cmp     ax, 5E00h
        je      hnet
chain:  jmp     far [cs:old21]

h30:    pushf
        call    far [cs:old21]
        cmp     byte [cs:mode + 'F'], 0
        je      .i
        mov     bh, 0FDh
.i:     cmp     byte [cs:mode + 'I'], 0
        je      .o
        mov     bh, 00h
.o:     cmp     byte [cs:mode + 'O'], 0
        je      .v
        mov     bh, 42h
.v:     cmp     byte [cs:mode + 'V'], 0
        je      .1
        mov     ax, 0005h
.1:     cmp     byte [cs:mode + '1'], 0
        je      .r
        xor     ax, ax
.r:     iret

h3306:  cmp     byte [cs:mode + 'V'], 0
        je      chain
        mov     bx, 1606h               ; BL = 6, BH = 22
        xor     dx, dx
        iret

hgr:    cmp     bx, 4752h
        jne     chain
        cmp     byte [cs:mode + 'S'], 0
        je      .g
        mov     ax, 4752h
        iret
.g:     cmp     byte [cs:mode + 'G'], 0
        jne     .answer
        cmp     byte [cs:mode + 'B'], 0
        je      chain
.answer:
        mov     ax, 4752h
        mov     bx, 0004h               ; 0.04
        mov     cx, 0001h               ; revision 1
        not     dx
        cmp     byte [cs:mode + 'B'], 0
        je      .r
        mov     dx, 1234h
.r:     iret

hdr:    cmp     byte [cs:mode + 'D'], 0
        je      chain
        mov     ax, 1067h
        clc
        retf    2

hnet:   cmp     byte [cs:mode + 'X'], 0
        je      .z
        mov     ax, 1
        stc
        retf    2
.z:     cmp     byte [cs:mode + 'Z'], 0
        je      .n
        xor     cx, cx
        clc
        retf    2
.n:     cmp     byte [cs:mode + 'N'], 0
        je      chain
        push    si
        push    di
        push    es
        push    ds
        pop     es                      ; ES:DI = the caller's DS:DX
        mov     di, dx
        mov     si, netname
        mov     cx, 16
.copy:  mov     al, [cs:si]
        stosb
        inc     si
        loop    .copy
        pop     es
        pop     di
        pop     si
        mov     cx, 0101h               ; CH = 1: valid, CL = NetBIOS 1
        clc
        retf    2

netname: db     'TESTPC         ', 0

pblock:  dw     0                       ; inherit the environment
pb_tail: dw     tail, 0
pb_fcb1: dw     5Ch, 0
pb_fcb2: dw     6Ch, 0

mode:    times 128 db 0

        section .bss
old21:    resd  1
save_sp:  resw  1
progname: resb  128
tail:     resb  128
        resb    256
stack_top:
