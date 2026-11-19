; uname - print system information
;
; 8086 assembly for MS-DOS 2.0 and later, built as a .COM with NASM.
; See README.md for what each field means on GR-DOS and on other DOS
; kernels.  tests/run.sh is the specification.
;
; Build: nasm -f bin -DVERSION='"0.01"' -o uname.com uname.asm

        cpu     8086
        org     100h

%ifndef VERSION
%define VERSION 'unknown'
%endif

; [flags]: the fields to print, in this order
F_S     equ     1                       ; -s  system name
F_N     equ     2                       ; -n  machine name
F_R     equ     4                       ; -r  release
F_V     equ     8                       ; -v  version
F_M     equ     16                      ; -m  machine
F_ALL   equ     31                      ; -a

; [kind]
K_OTHER equ     0
K_GRDOS equ     1
K_DRDOS equ     2

start:
        cld

        ; AH=30h: AL = major, AH = minor, BH = OEM.  DOS 1.x has no
        ; function 30h and leaves AL = 0; it also has no handle I/O.
        mov     ax, 3000h
        int     21h
        test    al, al
        jnz     .dos2
        mov     dx, msg_dos1
        mov     ah, 9
        int     21h
        int     20h
.dos2:  mov     [dosver], ax
        mov     [truever], ax
        mov     [oem], bh

        ; DOS 5 and later: AX=3306h gives the true version, which
        ; SETVER cannot change (BL = major, BH = minor).
        cmp     al, 5
        jb      .args
        mov     ax, 3306h
        xor     bx, bx
        int     21h
        cmp     al, 0FFh
        je      .args
        test    bl, bl
        jz      .args
        mov     [truever], bx

        ; Parse the command tail (PSP:80h its length, PSP:81h the
        ; text).  Arguments are separated by blanks; quotes are not
        ; special.  Options are acted on from left to right, as GNU
        ; getopt does; an operand is reported only after every option
        ; has been seen.
.args:  mov     si, 81h
        mov     cl, [80h]
        xor     ch, ch
argloop:
        call    next_arg
        jc      report
        mov     di, dx                  ; DX = DI = argument, BX = length
        cmp     byte [dashdash], 0
        jne     operand

        ; --help, --version, /?, --
        push    si
        push    cx
        mov     si, longopts
.opt:   lodsb
        test    al, al
        jz      .nolong
        mov     cl, al
        xor     ch, ch
        mov     di, dx
        cmp     cx, bx
        jne     .skip
        repe    cmpsb
        je      .match
.skip:  add     si, cx
        inc     si
        inc     si
        jmp     .opt
.match: mov     ax, [si]
        pop     cx
        pop     si
        jmp     ax
.nolong:
        pop     cx
        pop     si
        mov     di, dx
        cmp     bx, 2
        jb      operand                 ; "-" alone is an operand
        cmp     byte [di], '-'
        jne     operand
        cmp     byte [di+1], '-'
        je      unrecognized

        ; a cluster of short options: -s, -snr, ...
        push    si
        push    cx
        lea     si, [di+1]
        mov     cx, bx
        dec     cx
.short: lodsb
        cmp     al, 'h'
        je      help
        cmp     al, '?'
        je      help
        push    cx
        mov     di, shortopts
        mov     cx, shortopts_len
        repne   scasb
        pop     cx
        jne     invalid
        mov     al, [di + shortopts_len - 1]
        or      [flags], al
        loop    .short
        pop     cx
        pop     si
        jmp     argloop

dashdash_opt:
        mov     byte [dashdash], 1
        jmp     argloop

operand:
        cmp     word [opnd_len], 0
        jne     argloop
        mov     [opnd], dx
        mov     [opnd_len], bx
        jmp     argloop

        ; "uname: invalid option -- 'C'"
invalid:
        dec     si                      ; SI = the option letter
        mov     ax, 1
        mov     dx, msg_invalid
        mov     cx, msg_invalid_len
        jmp     fail

        ; "uname: unrecognized option '--ARG'"
unrecognized:
        mov     si, dx
        mov     ax, bx
        mov     dx, msg_unrec
        mov     cx, msg_unrec_len
        jmp     fail

version:
        mov     dx, msg_version
        mov     cx, msg_version_len
        jmp     out

help:
        mov     dx, msg_help
        mov     cx, msg_help_len
out:    mov     bx, 1
        call    write
        mov     ax, 4C00h
        int     21h

        ; Every argument is read: print the fields asked for.
report:
        mov     ax, [opnd_len]
        test    ax, ax
        jz      .fields
        mov     si, [opnd]              ; "uname: extra operand 'ARG'"
        mov     dx, msg_extra
        mov     cx, msg_extra_len
        jmp     fail

.fields:
        cmp     byte [flags], 0
        jne     .detect
        mov     byte [flags], F_S
.detect:
        call    detect_os
        mov     di, outbuf

        test    byte [flags], F_S
        jz      .n
        call    put_sysname
.n:     test    byte [flags], F_N
        jz      .r
        call    sep
        call    put_node
.r:     test    byte [flags], F_R
        jz      .v
        call    sep
        call    put_release
.v:     test    byte [flags], F_V
        jz      .m
        call    sep
        call    put_version
.m:     test    byte [flags], F_M
        jz      .end
        call    sep
        call    put_machine
.end:   mov     ax, 0A0Dh
        stosw
        mov     cx, di
        mov     dx, outbuf
        sub     cx, dx
        jmp     out

        ; Write the message at DX (CX bytes), the AX bytes at SI and
        ; "'", then the hint, to standard error; exit with status 1.
fail:   push    ax
        mov     bx, 2
        call    write
        mov     dx, si
        pop     cx
        call    write
        mov     dx, msg_try
        mov     cx, msg_try_len
        call    write
        mov     ax, 4C01h
        int     21h

        ; write CX bytes at DX to handle BX
write:  mov     ah, 40h
        int     21h
        ret

        ; next_arg: the next blank-delimited argument of the tail at SI
        ; (CX bytes left).  DX = its start, BX = its length; SI and CX
        ; advance past it.  Carry set if there is none.
next_arg:
.skip:  jcxz    .none
        lodsb
        dec     cx
        cmp     al, ' '
        je      .skip
        cmp     al, 9
        je      .skip
        dec     si
        inc     cx
        mov     dx, si
.scan:  jcxz    .end
        lodsb
        cmp     al, ' '
        je      .back
        cmp     al, 9
        je      .back
        dec     cx
        jmp     .scan
.back:  dec     si
.end:   mov     bx, si
        sub     bx, dx
        clc
        ret
.none:  stc
        ret

; ------------------------------------------------------------------
; detection

        ; detect_os: [kind], and [grver] and [grrev] or [drcode].
        ; GR-DOS (gr-dos docs/grver.md): AX=3347h, BX=4752h with two
        ; nonces; both answers must pass and agree.
detect_os:
        mov     dx, 5A3Ch
        call    grcall
        jc      .notgr
        push    bx
        push    cx
        mov     dx, 0C3A5h
        call    grcall
        pop     ax                      ; AL = first revision
        pop     si                      ; SI = first version
        jc      .notgr
        cmp     bx, si
        jne     .notgr
        cmp     cl, al
        jne     .notgr
        mov     byte [kind], K_GRDOS
        mov     [grver], bx
        mov     [grrev], cl
        ret

        ; DR DOS 3.41 and later, Novell DOS: AX=4452h answers with
        ; carry clear and a version code 10xxh.  Elsewhere it is an
        ; invalid IOCTL subfunction (carry set).
.notgr: mov     ax, 4452h
        xor     bx, bx
        stc
        int     21h
        jc      .done
        cmp     ah, 10h
        jne     .done
        mov     byte [kind], K_DRDOS
        mov     [drcode], ax
.done:  ret

        ; grcall: one identification call with nonce DX.  Carry clear
        ; if the answer passes every check: BX = version (BH major, BL
        ; minor), CL = API revision.
grcall: push    dx
        mov     ax, 3347h
        mov     bx, 4752h
        xor     cx, cx
        int     21h
        pop     si
        not     si
        cmp     ax, 4752h
        jne     .no
        cmp     dx, si
        jne     .no
        test    cl, cl
        jz      .no
        cmp     bl, 99
        ja      .no
        clc
        ret
.no:    stc
        ret

        ; cpu_class: AL = 0 8086/8088 (and NEC V20/V30), 1 80186/80188,
        ; 2 80286, 3 80386, 4 80486 without CPUID, 5 CPUID present.
        ; From retrofetch16's cpu_probe: what FLAGS and the shifter do,
        ; never an instruction the CPU might not have.
cpu_class:
        pushf
        ; FLAGS bits 12-15 read back as 1 on the 8086 and 80186.
        pushf
        pop     ax
        and     ax, 0FFFh
        push    ax
        popf
        pushf
        pop     ax
        and     ax, 0F000h
        cmp     ax, 0F000h
        jne     .286up
        ; The 80186 masks shift counts to 5 bits; the 8086 does not.
        mov     ax, 0FFFFh
        mov     cl, 33
        shl     ax, cl                  ; AX = 0 on the 8086
        jz      .done
        mov     al, 1
        jmp     .done

        ; 286 or later.  SMSW is unprivileged; MSW.PE set under DOS
        ; means virtual 8086 mode, so a 386 or later.
.286up:
        cpu     286
        smsw    ax
        cpu     8086
        test    al, 1
        jnz     .386up
        ; In real mode the 80286 cannot set FLAGS bits 12-14.
        pushf
        pop     ax
        or      ax, 7000h
        push    ax
        popf
        pushf
        pop     ax
        test    ax, 7000h
        mov     al, 2
        jz      .done
.386up: call    probe486
.done:  popf
        ret

        ; probe486: AL = 3, 4 or 5 on a 386 or later: whether EFLAGS.AC
        ; (bit 18), then EFLAGS.ID (bit 21), can be toggled.  Interrupts
        ; are off and SP dword aligned while AC may be set.
        cpu     386
probe486:
        pushf
        cli
        mov     dx, sp
        and     sp, 0FFFCh
        pushfd
        pop     eax
        mov     ecx, eax
        xor     eax, 40000h
        push    eax
        popfd
        pushfd
        pop     eax
        push    ecx
        popfd
        xor     eax, ecx
        test    eax, 40000h
        mov     al, 3
        jz      .done
        pushfd
        pop     eax
        mov     ecx, eax
        xor     eax, 200000h
        push    eax
        popfd
        pushfd
        pop     eax
        push    ecx
        popfd
        xor     eax, ecx
        test    eax, 200000h
        mov     al, 4
        jz      .done
        mov     al, 5
.done:  mov     sp, dx
        popf
        ret
        cpu     8086

; ------------------------------------------------------------------
; fields: each appends to the output at DI

        ; sep: a space unless this is the first field
sep:    cmp     di, outbuf
        je      .r
        mov     al, ' '
        stosb
.r:     ret

put_sysname:
        mov     si, s_grdos
        mov     al, [kind]
        cmp     al, K_GRDOS
        je      .put
        mov     si, s_drdos
        cmp     al, K_DRDOS
        je      .put
        ; otherwise by the OEM number from AH=30h
        mov     al, [oem]
        mov     si, oemnames
.oem:   cmp     byte [si], 1            ; end of table: "DOS"
        je      .last
        cmp     al, [si]
        je      .last
.next:  inc     si
        cmp     byte [si], 0
        jne     .next
        inc     si
        jmp     .oem
.last:  inc     si
.put:   jmp     puts

        ; the network machine name (AX=5E00h, DOS 3.1 and later): valid
        ; if carry is clear and CH is not 0.  15 characters padded with
        ; blanks (some redirectors pad with NULs).
put_node:
        mov     ax, [dosver]
        xchg    al, ah
        cmp     ax, 030Ah
        jb      .unknown
        push    di
        mov     dx, netname
        mov     ax, 5E00h
        xor     cx, cx
        int     21h
        pop     di
        jc      .unknown
        test    ch, ch
        jz      .unknown
        mov     si, netname
        mov     cx, 15
.trim:  mov     bx, cx
        mov     al, [si+bx-1]
        cmp     al, ' '
        je      .less
        test    al, al
        jnz     .copy
.less:  loop    .trim
        jmp     .unknown
.copy:  rep     movsb
        ret
.unknown:
        mov     si, s_unknown
        jmp     puts

        ; GR-DOS's release, or else the true DOS version
put_release:
        cmp     byte [kind], K_GRDOS
        jne     .dos
        mov     ax, [grver]
        xchg    al, ah                  ; AL = major, AH = minor
        jmp     putver
.dos:   mov     ax, [truever]
        jmp     putver

        ; "DOS 4.00 OEM FFh", then " API 1" on GR-DOS or " DR 1067h"
        ; on DR DOS
put_version:
        mov     si, s_dos
        call    puts
        mov     ax, [dosver]
        call    putver
        mov     si, s_oem
        call    puts
        mov     al, [oem]
        call    puthex2
        mov     al, 'h'
        stosb
        mov     al, [kind]
        cmp     al, K_GRDOS
        jne     .dr
        mov     si, s_api
        call    puts
        mov     al, [grrev]
        jmp     putdec
.dr:    cmp     al, K_DRDOS
        jne     .r
        mov     si, s_dr
        call    puts
        mov     ax, [drcode]
        call    puthex4
        mov     al, 'h'
        stosb
.r:     ret

put_machine:
        push    di
        call    cpu_class
        cmp     al, 5
        jb      .name
        ; CPUID leaf 1: the family is EAX bits 8-11.
        cpu     586
        mov     eax, 1
        cpuid
        cpu     8086
        mov     al, ah
        and     al, 0Fh
        cmp     al, 4
        jae     .hi
        mov     al, 4
.hi:    cmp     al, 6
        jbe     .name
        mov     al, 6
.name:  pop     di
        xor     ah, ah
        shl     ax, 1
        mov     bx, ax
        mov     si, [machines + bx]
        ; fall through

        ; copy the NUL-terminated string at SI to DI
puts:   lodsb
        test    al, al
        jz      .r
        stosb
        jmp     puts
.r:     ret

        ; putver: AL = major (decimal), AH = minor (two digits)
putver: push    ax
        call    putdec
        mov     al, '.'
        stosb
        pop     ax
        mov     al, ah
        aam                             ; AH = tens, AL = units
        xchg    al, ah
        add     ax, '00'
        stosw
        ret

        ; putdec: AL in decimal
putdec: xor     ah, ah
        mov     bl, 10
        xor     cx, cx
.div:   div     bl                      ; AL = quotient, AH = digit
        push    ax
        inc     cx
        xor     ah, ah
        test    al, al
        jnz     .div
.out:   pop     ax
        mov     al, ah
        add     al, '0'
        stosb
        loop    .out
        ret

        ; puthex4: AX in hex; puthex2: AL in hex
puthex4:
        push    ax
        mov     al, ah
        call    puthex2
        pop     ax
puthex2:
        push    ax
        mov     cl, 4
        shr     al, cl
        call    hexnib
        pop     ax
        and     al, 0Fh
hexnib: cmp     al, 10
        sbb     al, 69h
        das
        stosb
        ret

; ------------------------------------------------------------------
; data

        ; length, text, handler
longopts:
        db      6, '--help'
        dw      help
        db      9, '--version'
        dw      version
        db      2, '/?'
        dw      help
        db      2, '--'
        dw      dashdash_opt
        db      0

shortopts:
        db      'snrvma'
shortopts_len equ $ - shortopts
        db      F_S, F_N, F_R, F_V, F_M, F_ALL

        ; OEM number, then name; 1 ends the table (the default name)
oemnames:
        db      0FFh, 'MS-DOS', 0
        db      000h, 'PC-DOS', 0
        db      0FDh, 'FreeDOS', 0
        db      1, 'DOS', 0

s_grdos:        db      'GR-DOS', 0
s_drdos:        db      'DR-DOS', 0
s_unknown:      db      'unknown', 0
s_dos:          db      'DOS ', 0
s_oem:          db      ' OEM ', 0
s_api:          db      ' API ', 0
s_dr:           db      ' DR ', 0

machines:
        dw      m_8086, m_186, m_286, m_386, m_486, m_586, m_686
m_8086: db      'i8086', 0
m_186:  db      'i186', 0
m_286:  db      'i286', 0
m_386:  db      'i386', 0
m_486:  db      'i486', 0
m_586:  db      'i586', 0
m_686:  db      'i686', 0

msg_dos1:
        db      'uname: DOS 2.0 or later required', 13, 10, '$'

msg_version:
        db      'uname (dos-uname16) ', VERSION, 13, 10
msg_version_len equ $ - msg_version

msg_help:
        db      'Usage: uname [OPTION]...', 13, 10
        db      'Print system information.  With no OPTION, same as -s.', 13, 10
        db      13, 10
        db      '  -a  all of the following, in this order', 13, 10
        db      '  -s  system name: GR-DOS, MS-DOS, PC-DOS, DR-DOS, FreeDOS or DOS', 13, 10
        db      '  -n  network machine name, or unknown', 13, 10
        db      "  -r  release: GR-DOS's version, or else the DOS version", 13, 10
        db      '  -v  DOS version and OEM number reported, GR-DOS API or DR DOS code', 13, 10
        db      '  -m  processor class: i8086, i186, i286, i386, i486, i586 or i686', 13, 10
        db      '  -h, --help     display this help and exit', 13, 10
        db      '      --version  output version information and exit', 13, 10
msg_help_len equ $ - msg_help

msg_invalid:
        db      "uname: invalid option -- '"
msg_invalid_len equ $ - msg_invalid

msg_unrec:
        db      "uname: unrecognized option '"
msg_unrec_len equ $ - msg_unrec

msg_extra:
        db      "uname: extra operand '"
msg_extra_len equ $ - msg_extra

msg_try:
        db      "'", 13, 10
        db      "Try 'uname --help' for more information.", 13, 10
msg_try_len equ $ - msg_try

        ; Variables that must start at 0 are initialized data: DOS does
        ; not clear the memory after a .COM image.
flags:    db    0
dashdash: db    0
kind:     db    0                       ; K_*
opnd_len: dw    0                       ; the first operand's length

        section .bss
oem:      resb  1
grrev:    resb  1
          alignb 2
dosver:   resw  1                       ; AL major, AH minor (AH=30h)
truever:  resw  1                       ; the same, from AX=3306h if any
grver:    resw  1                       ; BH major, BL minor
drcode:   resw  1
opnd:     resw  1
netname:  resb  16
outbuf:   resb  128
