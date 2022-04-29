NAME     = oathbreaker
VERSION  = 1.0.0
PKGNAME  = $(NAME)-$(shell uname -s)-$(shell uname -m)-$(VERSION)
CMD      = @

.PHONY: dist
dist: zig-out/bin/rl
	$(CMD)mkdir $(PKGNAME)
	$(CMD)cp -r zig-out/bin/rl $(PKGNAME)
	$(CMD)cp -r data           $(PKGNAME)
	$(CMD)cp -r doc            $(PKGNAME)
	$(CMD)cp -r prefabs        $(PKGNAME)
	$(CMD)cp -r run.sh         $(PKGNAME)
	$(CMD)tar -cf - $(PKGNAME) | xz -qcT0 > $(PKGNAME).tar.xz
	$(CMD)rm -rf $(PKGNAME)
