# Alpine Linux 32bit: currently all binaries crash:
#  Floating point exception   (return code 136)
#    https://gitlab.alpinelinux.org/alpine/aports/-/issues/12242
#    https://github.com/alpinelinux/aports/commit/4b3952f03f53f2f60ee68a5b83a58c65d0c79343

GDC ?= gdc
STRIP ?= strip

hello:
	$(GDC) -static -o hello hello.d

strip: hello
	$(STRIP) hello

clean:
	rm -f *.o hello
