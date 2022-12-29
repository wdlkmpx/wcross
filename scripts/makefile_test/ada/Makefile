
GNATMAKE ?= gnatmake
GNATBIND ?= gnatbind
GNATLINK ?= gnatlink
STRIP ?= strip

hello_world:
	$(GNATMAKE) -gnatf hello_world.adb

strip: hello_world
	$(STRIP) hello_world

clean:
	rm -f *.o hello_world.ali hello_world
