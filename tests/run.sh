#!/bin/sh
#
# Test uname.com under DOSBox-X.  With no C reference to compare
# against, this is uname's specification.
#
# The main session runs on DOSBox-X's 8086 CPU, so an instruction the
# 8086 lacks fails the tests.  It runs every step in one batch file;
# the results are checked on the host afterwards.  Step N records the
# exit status in RN.TXT and the output in ON.TXT.  Each step runs uname
# under tests/fakedos.com, which sends standard error to standard output
# and imitates other kernels' answers (see fakedos.asm for its modes).
# Most steps pass X (no network name): DOSBox-X answers AX=5E00h with
# the host's name.  rc.bat uses goto rather than "if errorlevel N echo
# ... >file" because the DOSBox-X shell opens the redirection even when
# the test is false.
#
# Further sessions check -m on each emulated CPU type and -r and -n on
# other reported DOS versions.
#
# To add a test: add a step to steps.bat (command, then "call rc N")
# and the matching rc/expect/check lines below.
#
# Usage: tests/run.sh [path/to/uname.com [path/to/fakedos.com]]
# Environment: DOSBOX (default dosbox-x), KEEP=1 to keep the work
#              directory.

set -u

top=$(cd "$(dirname "$0")/.." && pwd)
prog=${1:-$top/uname.com}
fake=${2:-$top/tests/fakedos.com}
DOSBOX=${DOSBOX:-dosbox-x}

command -v "$DOSBOX" >/dev/null || { echo "$DOSBOX not found" >&2; exit 2; }
for f in "$prog" "$fake"; do
    [ -f "$f" ] || { echo "$f not found" >&2; exit 2; }
done

work=$(mktemp -d "${TMPDIR:-/tmp}/dosuname.XXXXXX")
pass=0
fail=0
LC_ALL=C
export LC_ALL

# ------------------------------------------------------------------
# fixtures

cd "$work" || exit 2
cp "$prog" uname.com
cp "$fake" fakedos.com

cat > rc.bat <<'EOS'
@echo off
if errorlevel 2 goto rc2
if errorlevel 1 goto rc1
echo rc0 >c:\r%1.txt
goto end
:rc1
echo rc1 >c:\r%1.txt
goto end
:rc2
echo rc2 >c:\r%1.txt
:end
EOS

cat > steps.bat <<'EOS'
@echo off
rem --- fields on DOSBox-X (MS-DOS 5.00, OEM FFh), 8086 CPU
uname >o1.txt
call rc 1
fakedos X uname.com >o2.txt
call rc 2
fakedos X uname.com -s >o3.txt
call rc 3
fakedos X uname.com -a >o4.txt
call rc 4
fakedos X uname.com -mvrns >o5.txt
call rc 5
fakedos X uname.com -m -s >o6.txt
call rc 6
fakedos X uname.com  -r	 -s   >o7.txt
call rc 7
fakedos X uname.com -aa -s >o8.txt
call rc 8
rem --- machine name
fakedos N uname.com -n >o9.txt
call rc 9
fakedos Z uname.com -n >o10.txt
call rc 10
fakedos X uname.com -n >o11.txt
call rc 11
rem --- GR-DOS
fakedos XG uname.com -a >o12.txt
call rc 12
fakedos XB uname.com -a >o13.txt
call rc 13
fakedos XS uname.com -a >o14.txt
call rc 14
fakedos GN uname.com -snr >o15.txt
call rc 15
rem --- other kernels
fakedos XD uname.com -a >o16.txt
call rc 16
fakedos XF uname.com -sv >o17.txt
call rc 17
fakedos XI uname.com -sv >o18.txt
call rc 18
fakedos XO uname.com -sv >o19.txt
call rc 19
fakedos XV uname.com -srv >o20.txt
call rc 20
fakedos X1 uname.com -a >o21.txt
call rc 21
rem --- help and version
fakedos X uname.com --help >o22.txt
call rc 22
fakedos X uname.com -h >o23.txt
call rc 23
fakedos X uname.com -? >o24.txt
call rc 24
fakedos X uname.com /? >o25.txt
call rc 25
fakedos X uname.com --version >o26.txt
call rc 26
fakedos X uname.com -sh >o27.txt
call rc 27
fakedos X uname.com --help --bogus >o28.txt
call rc 28
fakedos X uname.com extra --help >o29.txt
call rc 29
rem --- errors
fakedos X uname.com --bogus >o30.txt
call rc 30
fakedos X uname.com -x >o31.txt
call rc 31
fakedos X uname.com -sx >o32.txt
call rc 32
fakedos X uname.com extra >o33.txt
call rc 33
fakedos X uname.com -s extra more >o34.txt
call rc 34
fakedos X uname.com - >o35.txt
call rc 35
fakedos X uname.com -- -s >o36.txt
call rc 36
fakedos X uname.com -s -- >o37.txt
call rc 37
fakedos X uname.com --bogus --help >o38.txt
call rc 38
fakedos X uname.com --all >o39.txt
call rc 39
EOS

# session NAME CPUTYPE DOSVER BATCH: run BATCH in a new DOSBox-X
session() {
    SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy timeout 300 \
        "$DOSBOX" -defaultconf -silent -nogui -nomenu \
        -set "cpu core=normal" -set "cpu cputype=$2" \
        -set "cpu cycles=max" -set "dos ver=$3" \
        -c "mount c \"$work\"" -c "c:" \
        -c "$4" -c "exit" >"$1.log" 2>&1
}

session main 8086 5.0 steps.bat

# -m on each CPU type DOSBox-X emulates, by class
cpus="8086:i8086 80186:i186 286:i286 386:i386 486old:i486 486:i486
      pentium:i586 ppro_slow:i686"
n=0
for c in $cpus; do
    n=$((n + 1))
    printf '@echo off\r\nfakedos X uname.com -m >M%d.TXT\r\n' $n > m$n.bat
    session m$n "${c%%:*}" 5.0 m$n.bat
done

# -r and -n on other reported versions: before 3.10, AX=5E00h is not
# called, so DOSBox-X's answer (the host's name) is never seen.
vers="3.0:3.00 3.10:3.10 7.10:7.10"
n=0
for v in $vers; do
    n=$((n + 1))
    printf '@echo off\r\nfakedos %s uname.com -rn >V%d.TXT\r\n' \
        "$([ "${v%%:*}" = 3.0 ] && echo - || echo X)" $n > v$n.bat
    session v$n 8086 "${v%%:*}" v$n.bat
done

# ------------------------------------------------------------------
# checks

ok()     { pass=$((pass + 1)); }
not_ok() { echo "FAIL: $*"; fail=$((fail + 1)); }

# check NAME COMMAND...
check() {
    name=$1
    shift
    if "$@"; then ok; else not_ok "$name"; fi
}

# rc STEP EXPECTED-STATUS
rc() {
    got=$(tr -d ' \r' < "R$1.TXT" 2>/dev/null | sed 's/^rc//')
    if [ "$got" = "$2" ]; then
        ok
    else
        not_ok "step $1: exit status ${got:-missing}, expected $2"
    fi
}

# expect FILE < expected-lines; compares FILE with CRs removed
expectf() {
    tr -d '\r' < "$1" 2>/dev/null > got.txt
    cat > want.txt
    if cmp -s got.txt want.txt; then
        ok
    else
        not_ok "$1: output differs"
        diff want.txt got.txt | sed 's/^/    /'
    fi
}

# expect STEP < expected-lines
expect() { expectf "O$1.TXT"; }

# crlf FILE: every line ends in CR LF
crlf() { [ -s "$1" ] && awk '!/\r$/ { bad = 1 } END { exit bad }' "$1"; }

version=$(cat "$top/VERSION")
try="Try 'uname --help' for more information."

# fields
rc 1 0
check "step 1: plain run prints MS-DOS" grep -q '^MS-DOS' O1.TXT
check "step 1: CR LF" crlf O1.TXT
rc 2 0
expect 2 <<'EOS'
MS-DOS
EOS
rc 3 0
check "step 3: -s same as no option" cmp -s O2.TXT O3.TXT
rc 4 0
expect 4 <<'EOS'
MS-DOS unknown 5.00 DOS 5.00 OEM FFh i8086
EOS
rc 5 0
check "step 5: -mvrns same as -a" cmp -s O4.TXT O5.TXT
rc 6 0
expect 6 <<'EOS'
MS-DOS i8086
EOS
rc 7 0
expect 7 <<'EOS'
MS-DOS 5.00
EOS
rc 8 0
check "step 8: -aa -s same as -a" cmp -s O4.TXT O8.TXT

# machine name
rc 9 0
expect 9 <<'EOS'
TESTPC
EOS
rc 10 0
expect 10 <<'EOS'
unknown
EOS
rc 11 0
expect 11 <<'EOS'
unknown
EOS

# GR-DOS
rc 12 0
expect 12 <<'EOS'
GR-DOS unknown 0.04 DOS 5.00 OEM FFh API 1 i8086
EOS
rc 13 0
check "step 13: same answer to both nonces rejected" cmp -s O4.TXT O13.TXT
rc 14 0
check "step 14: signature alone rejected" cmp -s O4.TXT O14.TXT
rc 15 0
expect 15 <<'EOS'
GR-DOS TESTPC 0.04
EOS

# other kernels
rc 16 0
expect 16 <<'EOS'
DR-DOS unknown 5.00 DOS 5.00 OEM FFh DR 1067h i8086
EOS
rc 17 0
expect 17 <<'EOS'
FreeDOS DOS 5.00 OEM FDh
EOS
rc 18 0
expect 18 <<'EOS'
PC-DOS DOS 5.00 OEM 00h
EOS
rc 19 0
expect 19 <<'EOS'
DOS DOS 5.00 OEM 42h
EOS
rc 20 0
expect 20 <<'EOS'
MS-DOS 6.22 DOS 5.00 OEM FFh
EOS
rc 21 0
expect 21 <<'EOS'
uname: DOS 2.0 or later required
EOS

# help and version
rc 22 0
check "step 22: help" grep -q '^Usage: uname' O22.TXT
check "step 22: CR LF" crlf O22.TXT
for s in 23 24 25 27 28 29; do
    rc $s 0
    check "step $s: same as --help" cmp -s O22.TXT O$s.TXT
done
rc 26 0
expect 26 <<EOS
uname (dos-uname16) $version
EOS

# errors
rc 30 1
expect 30 <<EOS
uname: unrecognized option '--bogus'
$try
EOS
rc 31 1
expect 31 <<EOS
uname: invalid option -- 'x'
$try
EOS
rc 32 1
check "step 32: -sx same as -x" cmp -s O31.TXT O32.TXT
rc 33 1
expect 33 <<EOS
uname: extra operand 'extra'
$try
EOS
rc 34 1
check "step 34: first operand reported" cmp -s O33.TXT O34.TXT
rc 35 1
expect 35 <<EOS
uname: extra operand '-'
$try
EOS
rc 36 1
expect 36 <<EOS
uname: extra operand '-s'
$try
EOS
rc 37 0
expect 37 <<'EOS'
MS-DOS
EOS
rc 38 1
check "step 38: same as --bogus" cmp -s O30.TXT O38.TXT
rc 39 1
expect 39 <<EOS
uname: unrecognized option '--all'
$try
EOS

# -m by CPU type
n=0
for c in $cpus; do
    n=$((n + 1))
    expectf "M$n.TXT" <<EOS
${c#*:}
EOS
done

# -r and -n by DOS version
n=0
for v in $vers; do
    n=$((n + 1))
    expectf "V$n.TXT" <<EOS
unknown ${v#*:}
EOS
done

# ------------------------------------------------------------------

echo "$pass passed, $fail failed"
if [ "$fail" -ne 0 ] || [ "${KEEP:-0}" = 1 ]; then
    echo "work directory: $work"
else
    rm -rf "$work"
fi
[ "$fail" -eq 0 ]
