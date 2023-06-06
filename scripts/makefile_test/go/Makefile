# musl-fts-devs

GCCGO ?= gccgo
STRIP ?= strip

# - need to add -lucontext
# - avoid libgo.a(proc.o): in function `runtime.mcall': undefined reference to `getcontext'
# - by adding -lgo before -lucontext

hello:
	$(GCCGO) -static-libgo -static-libgcc -static -o hello hello.go -Wl,-lgo,-lucontext

# Go programs must generally be compiled with debugging information, and -g1 is the default as described below. Stripping a Go program will generally cause it to misbehave or fail. 
strip: hello
#	$(STRIP) hello

clean:
	rm -f *.o hello
