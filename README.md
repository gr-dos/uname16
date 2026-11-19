# uname16

A small Unix-style `uname` for 16-bit DOS: GR-DOS, MS-DOS, PC DOS,
DR DOS, FreeDOS and other DOS 2.0 or later, on any CPU from the 8086 up.

`uname.com` is 8086 assembly built with NASM, under 2 KB, small enough
for a boot floppy. It is part of the [gr-dos](https://github.com/gr-dos)
utilities and follows [hello16](https://github.com/gr-dos/hello16)'s
conventions in its layout 2 (assembly only).

## Usage

    uname [OPTION]...

    -a  all of the following, in this order
    -s  system name (the default with no option)
    -n  network machine name
    -r  release
    -v  version
    -m  processor class
    -h, --help, -?, /?   show help
    --version            show version

Short options can be combined (`-snr`). The fields always come out in
the order above, separated by single spaces, on one line, whatever order
the options were given in. `--` ends the options.

The exit status is 0 on success and 1 for a bad option or an operand.
Errors go to standard error, GNU style:

    uname: invalid option -- 'x'
    uname: unrecognized option '--all'
    uname: extra operand 'foo'
    Try 'uname --help' for more information.

Only the short options are supported, not GNU's long forms (`--all`,
`--kernel-name`, ...), nor `-p`, `-i` or `-o`.

## Output

Examples:

    C:\>uname -a
    GR-DOS unknown 0.04 DOS 4.00 OEM FFh API 1 i8086

    C:\>uname -a
    MS-DOS unknown 5.00 DOS 5.00 OEM FFh i486

    C:\>uname -sr
    MS-DOS 5.00

(The second and third are DOSBox-X 2026.01.02, which reports MS-DOS
5.00.)

### `-s`: system name

One word, so scripts can compare it:

| Name | When |
|---|---|
| `GR-DOS` | the GR-DOS identification call answers (below) |
| `DR-DOS` | `INT 21h AX=4452h` answers with carry clear and a version code 10xxh (DR DOS 3.41 and later, Novell DOS) |
| `MS-DOS` | the OEM number from `INT 21h AH=30h` is FFh (Microsoft) |
| `PC-DOS` | the OEM number is 00h (IBM) |
| `FreeDOS` | the OEM number is FDh |
| `DOS` | any other OEM number |

GR-DOS is recognized as gr-dos's `docs/grver.md` ("Recognizing GR-DOS")
specifies, and as `GRVER` and retrofetch16 do: `INT 21h AX=3347h`,
`BX=4752h` is called twice, with the nonces 5A3Ch and C3A5h. Each answer
must have `AX=4752h`, `DX` the nonce complemented, revision `CL` ≥ 1 and
minor version `BL` ≤ 99, and the two answers must agree. On any other DOS
the call is an invalid subfunction and harmless.

The OEM number names the vendor that built the kernel, as reported; it
is not checked further. Windows 9x's DOS and DOSBox report FFh, and show
as `MS-DOS`.

### `-n`: network machine name

The name set by a network redirector (`INT 21h AX=5E00h`, DOS 3.1 and
later), without its padding. A plain DOS machine has none, and `-n`
prints `unknown`, the word GNU `uname` uses for a field it cannot
determine. `-a` prints it too, so the fields keep their positions.

### `-r`: release

- **GR-DOS:** its own release, `major.minor` with two digits after the
  point (`0.04`), from the identification call. This is what `GRVER`
  prints; the DOS version GR-DOS reports to programs is 4.00, in `-v`.
- **Elsewhere:** the DOS version, `major.minor` with two digits
  (`3.30`, `6.22`, `7.10`). On DOS 5 and later it is the true version
  (`INT 21h AX=3306h`), which `SETVER` cannot change.

### `-v`: version

What the kernel reports, as evidence rather than a judgment, in words:

- `DOS n.nn`: the version from `INT 21h AH=30h`, as programs see it
  (`SETVER` can change it);
- `OEM XXh`: the OEM number from the same call, in hex;
- then, on GR-DOS, `API n`: the identification call's revision;
- or, on DR DOS, `DR XXXXh`: the version code from `AX=4452h` (1067h is
  DR DOS 6.0; uname does not translate codes into product names).

`-v` is several words, as on Unix, where it is the kernel build string.

### `-m`: processor class

The instruction set class of the CPU, found from how FLAGS and the
shifter behave (retrofetch16's `cpu_probe`), never by running an
instruction the CPU might not have:

| Output | CPU |
|---|---|
| `i8086` | 8086, 8088, NEC V20, V30 |
| `i186` | 80186, 80188 |
| `i286` | 80286 |
| `i386` | 80386 |
| `i486` | 80486 (or a CPUID family 4) |
| `i586` | CPUID family 5 (Pentium) |
| `i686` | CPUID family 6 or later |

`CPUID` is used only once the probe has shown the CPU has it. This names
a class the CPU is compatible with, not the chip. A clone or an emulator
shows as the class it behaves as. In virtual 8086 mode (under EMM386 or
Windows) the result is still the CPU's class, at least `i386`.

## Requirements

- DOS 2.0 or later. On DOS 1.x, which has no handle output, it prints
  `uname: DOS 2.0 or later required` and exits.
- An 8086 or later; no coprocessor. `uname.asm` is assembled with
  `cpu 8086`, and the 286, 386 and Pentium instructions in the CPU probe
  are enabled only around code that runs after the probe has shown they
  exist. The tests run on DOSBox-X's 8086 CPU.
- Memory: the 1.9 KB image, its 256-byte PSP, about 200 bytes of
  variables and a small stack, under 3 KB in all. On a 360 KB or 720 KB
  floppy (1 KB clusters) it takes 2 clusters.

## Building and testing

On Linux, with GNU make, NASM and DOSBox-X:

    make            build uname.com
    make test       run tests/run.sh under DOSBox-X
    make clean

`VERSION` holds the version, compiled in and printed by `--version`:

    uname (dos-uname16) 0.01

There is no C reference program, so `tests/run.sh` is the specification.
It runs uname in a headless DOSBox-X on the 8086 CPU, under
`tests/fakedos.com`, a fixture that sends standard error to standard
output (DOS cannot redirect it) and imitates the answers of other
kernels: GR-DOS, valid and forged; DR DOS; the FreeDOS, IBM and other
OEM numbers; SETVER; DOS 1.x; and a network name present or absent.
Further sessions check `-m` on each CPU type DOSBox-X emulates and
`-r`/`-n` on DOS 3.0, 3.10 and 7.10. `KEEP=1` keeps the work directory.

The hello16 conventions apply: `main` is protected and changes only by
a pull request whose `test` check (`.github/workflows/ci.yml`) passes,
and `.github/workflows/release.yml` tags and releases `uname.com` when a
merge changes `VERSION` (MS-DOS style versions: 0.01, 0.02, ...).

## Why a new implementation

No existing `uname` fits: GNU coreutils' DOS build (DJGPP) needs a 386
and a DPMI host, and is GPL. A small program of a few DOS calls is less
work to write than to adapt, and can recognize GR-DOS.

## Files

- `uname.asm`: the program
- `Makefile`: the NASM build (`make`, `make test`, `make clean`)
- `VERSION`: the version, compiled in and printed by `--version`
- `tests/run.sh`: the test suite, run under DOSBox-X by `make test`
- `tests/fakedos.asm`: the test fixture
- `.github/workflows/ci.yml`: build and test on PRs and pushes to `main`
- `.github/workflows/release.yml`: tag and release when `VERSION` changes

## License

MIT. See `LICENSE`.
