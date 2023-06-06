
PREFIX ?= /usr/local

INCLUDEDIR = $(DESTDIR)$(PREFIX)/include

all:

install:
	mkdir -p $(INCLUDEDIR)/sys
	install -m 644 include/error.h    $(INCLUDEDIR)
	install -m 644 include/execinfo.h $(INCLUDEDIR)
	install -m 644 include/stab.h     $(INCLUDEDIR)
	install -m 644 include/sys/cdefs.h $(INCLUDEDIR)/sys
	install -m 644 include/sys/queue.h $(INCLUDEDIR)/sys
	install -m 644 include/sys/tree.h  $(INCLUDEDIR)/sys
	#install -m 644 include/sys/sgidefs.h $(INCLUDEDIR)/sys
