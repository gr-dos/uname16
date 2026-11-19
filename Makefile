# Build uname.com, an 8086 .COM for MS-DOS 2.0 and later, with NASM.
#   make          build uname.com
#   make test     run tests/run.sh under DOSBox-X
#   make clean

NASM   ?= nasm
NFLAGS  = -f bin -Werror

VERSION := $(shell cat VERSION)

all: uname.com

uname.com: uname.asm VERSION
	$(NASM) $(NFLAGS) '-DVERSION="$(VERSION)"' -o $@ uname.asm

tests/fakedos.com: tests/fakedos.asm
	$(NASM) $(NFLAGS) -o $@ tests/fakedos.asm

test: uname.com tests/fakedos.com
	sh tests/run.sh $(CURDIR)/uname.com $(CURDIR)/tests/fakedos.com

clean:
	rm -f uname.com tests/fakedos.com

.PHONY: all test clean
