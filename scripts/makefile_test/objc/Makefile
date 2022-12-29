
GCC ?= gcc
STRIP ?= strip

all: hello

hello:
	$(GCC) -static -fgnu-runtime -o hello hello.m -lobjc

strip:
	$(STRIP) hello

clean:
	rm -f *.o hello
