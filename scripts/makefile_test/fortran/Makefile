
GFORTRAN ?= gfortran
STRIP ?= strip

hello:
	$(GFORTRAN) -o hello hello.f90

strip: hello
	$(STRIP) hello

clean:
	rm -f *.o hello
