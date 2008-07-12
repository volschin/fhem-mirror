BINDIR=/usr/local/bin
MODDIR=/usr/local/lib

VERS=4.3
DATE=2008-07-12
DIR=fhem-$(VERS)

all:
	@echo Nothing to do for all.
	@echo To install, check the Makefile, and then \'make install\'

install:
	cp fhem.pl $(BINDIR)
	cp -rp FHEM $(MODDIR)
	perl -pi -e 's,modpath .,modpath $(MODDIR),' examples/*

install-pgm2:
	cp fhem.pl $(BINDIR)
	cp -rp FHEM $(MODDIR)
	cp -rp webfrontend/pgm2/* $(MODDIR)
	perl -pi -e 's,modpath .,modpath $(MODDIR),' examples/*

dist:
	@echo Version is $(VERS), Date is $(DATE)
	mkdir .f
	cp -rp * .f
	find .f -name \*.orig -print | xargs rm -f
	find .f -type f -print |\
		xargs perl -pi -e 's/=VERS=/$(VERS)/g;s/=DATE=/$(DATE)/g'
	mv .f fhem-$(VERS)
	tar cf - fhem-$(VERS) | gzip > fhem-$(VERS).tar.gz
	mv fhem-$(VERS)/docs/*.html .
	rm -rf fhem-$(VERS)
