BINDIR=/usr/local/bin
MODDIR=/usr/local/lib
VARDIR=/var/log/fhem

VERS=4.9
DATE=2010-03-14

all:
	@echo Nothing to do for all.
	@echo To install, check the Makefile, and then \'make install\'
	@echo or \'make install-pgm2\' to install a web frontend too.

install:install-base
	-mv $(VARDIR)/fhem.cfg $(VARDIR)/fhem.cfg.`date "+%Y-%m-%d_%H:%M:%S"`
	cp examples_changed/sample_fhem $(VARDIR)/fhem.cfg
	@echo
	@echo
	@echo Start fhem with
	@echo perl $(BINDIR)/fhem.pl $(VARDIR)/fhem.cfg

install-pgm2:install-base
	cp -r webfrontend/pgm2/* $(MODDIR)/FHEM
	cp docs/commandref.html docs/faq.html docs/HOWTO.html $(MODDIR)/FHEM
	cp docs/*.png docs/*.jpg $(MODDIR)/FHEM
	-mv $(VARDIR)/fhem.cfg $(VARDIR)/fhem.cfg.`date "+%Y-%m-%d_%H:%M:%S"`
	cp examples_changed/sample_pgm2 $(VARDIR)/fhem.cfg
	cd examples_changed; for i in *; do cp -r $$i $(MODDIR)/FHEM/example.$$i; done
	@echo
	@echo
	@echo Start fhem with
	@echo perl $(BINDIR)/fhem.pl $(VARDIR)/fhem.cfg

install-base:
	mkdir -p $(BINDIR) $(MODDIR) $(VARDIR)
	cp fhem.pl $(BINDIR)
	cp -r FHEM $(MODDIR)
	rm -rf examples_changed
	cp -r examples examples_changed
	perl -pi -e 's,modpath \.,modpath $(MODDIR),' examples_changed/[a-z]*
	perl -pi -e 's,([^h]) /tmp,$$1 $(VARDIR),' examples_changed/[a-z]*

dist:
	@echo Version is $(VERS), Date is $(DATE)
	mkdir .f
	cp -r CHANGED FHEM HISTORY Makefile README.CVS\
                TODO contrib docs examples fhem.pl webfrontend .f
	find .f -name CVS -print | xargs rm -rf
	find .f -name \*.orig -print | xargs rm -f
	find .f -name .#\* -print | xargs rm -f
	find .f -type f -print |\
		xargs perl -pi -e 's/=VERS=/$(VERS)/g;s/=DATE=/$(DATE)/g'
	mv .f fhem-$(VERS)
	tar cf - fhem-$(VERS) | gzip > fhem-$(VERS).tar.gz
	mv fhem-$(VERS)/docs/*.html .
	rm -rf fhem-$(VERS)
